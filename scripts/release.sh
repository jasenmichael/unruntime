#! /bin/bash

ROOT_DIR="$(dirname "$(dirname "$0")")"
# read version from src/unruntime.sh
VERSION=$(grep -oP 'UNRUNTIME_VERSION=\K[^ ]+' "$ROOT_DIR/src/unruntime.sh")

# Parse command line arguments
NO_BUMP=false
while [[ "$#" -gt 0 ]]; do
  case $1 in
  --no-bump) NO_BUMP=true ;;
  *)
    echo "Unknown parameter: $1"
    exit 1
    ;;
  esac
  shift
done

# check for git command
if ! command -v git &>/dev/null; then
  echo "git could not be found"
  exit 1
fi

# check if we're on main branch
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "Please switch to main branch before releasing"
  exit 1
fi

# Pull latest changes from remote
echo "Pulling latest changes from remote..."
if ! git pull origin main; then
  echo "Failed to pull from remote. Please resolve any conflicts and try again."
  exit 1
fi

# check if working directory is clean
if [ -n "$(git status --porcelain)" ]; then
  echo "Working directory is not clean. Please commit or stash changes first."
  exit 1
fi

# Function to bump version
bump_version() {
  local version=$1
  local type=$2
  local major minor patch
  IFS='.' read -r major minor patch <<<"$version"

  case $type in
  major)
    echo "$((major + 1)).0.0"
    ;;
  minor)
    echo "$major.$((minor + 1)).0"
    ;;
  patch)
    echo "$major.$minor.$((patch + 1))"
    ;;
  *)
    echo "Invalid version bump type: $type"
    exit 1
    ;;
  esac
}

# Function to update version in unruntime.sh
update_version() {
  local new_version=$1
  sed -i "s/UNRUNTIME_VERSION=.*/UNRUNTIME_VERSION=$new_version/" "$ROOT_DIR/src/unruntime.sh"
}

# Function to create release notes
create_release_notes() {
  local version=$1
  local prev_version=$2

  # Get commits between versions
  local commits
  commits=$(git log --pretty=format:"- %s" "$prev_version..HEAD")

  # Create release notes
  cat <<EOF
# Release v$version

## Changes
$commits

## Installation
\`\`\`bash
curl -fsSL https://github.com/jasenmichael/unruntime/raw/main/unruntime.sh | bash
\`\`\`

## What's New
- Updated unruntime to v$version
- See commit history for detailed changes
EOF
}

# Function to update changelog
update_changelog() {
  local release_notes=$1
  local changelog_file="$ROOT_DIR/CHANGELOG.md"

  # Create changelog if it doesn't exist
  if [ ! -f "$changelog_file" ]; then
    cat <<EOF >"$changelog_file"
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

EOF
  fi

  # Insert new release notes after the Unreleased section
  sed -i "/^## \[Unreleased\]/a\\\n$release_notes" "$changelog_file"
}

# Function to revert all changes
revert_changes() {
  echo "Reverting all changes..."
  # Remove the tag we just created
  git tag -d "v$new_version"
  # Reset to the commit before we started
  git reset --hard HEAD~1
  echo "All changes have been reverted."
}

# Main release process
main() {
  # Get current version
  echo "Current version: $VERSION"

  if [ "$NO_BUMP" = true ]; then
    echo "Using current version (no bump)"
    new_version=$VERSION
  else
    # Ask for version bump type
    echo "What type of version bump would you like?"
    echo "1) Major (X.0.0)"
    echo "2) Minor (0.X.0)"
    echo "3) Patch (0.0.X)"
    read -r -p "Enter choice (1-3): " choice

    case $choice in
    1) new_version=$(bump_version "$VERSION" "major") ;;
    2) new_version=$(bump_version "$VERSION" "minor") ;;
    3) new_version=$(bump_version "$VERSION" "patch") ;;
    *) echo "Invalid choice" && exit 1 ;;
    esac

    echo "New version will be: $new_version"
    read -r -p "Continue? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
      echo "Release cancelled"
      exit 0
    fi

    # Update version in unruntime.sh
    update_version "$new_version"
  fi

  # Create release notes
  release_notes=$(create_release_notes "$new_version" "v$VERSION")

  # Update changelog
  update_changelog "$release_notes"

  # Commit changes
  if [ "$NO_BUMP" = true ]; then
    git add "$ROOT_DIR/CHANGELOG.md"
    git commit -m "chore: update changelog for v$new_version"
  else
    git add "$ROOT_DIR/src/unruntime.sh" "$ROOT_DIR/CHANGELOG.md"
    git commit -m "chore: bump version to v$new_version"
  fi

  # Create git tag
  git tag -a "v$new_version" -m "Release v$new_version"

  # Show changes before pushing
  echo "The following changes will be pushed:"
  echo "----------------------------------------"
  git diff --cached
  echo "----------------------------------------"
  echo "CHANGELOG.md has been updated with:"
  echo "----------------------------------------"
  echo "$release_notes"
  echo "----------------------------------------"

  read -r -p "Review the changes above. Push to GitHub? (y/n): " push_confirm
  if [ "$push_confirm" != "y" ]; then
    echo "Release cancelled. Reverting all changes..."
    revert_changes
    exit 0
  fi

  # Push changes and tag
  git push origin main
  git push origin "v$new_version"

  echo "Release v$new_version completed successfully!"
  echo "Please create a release on GitHub with the following notes:"
  echo "----------------------------------------"
  echo "$release_notes"
  echo "----------------------------------------"
}

main

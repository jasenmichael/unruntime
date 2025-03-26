#! /bin/bash

# backup the release script
SCRIPT_PATH="$0"
mkdir -p .git/.bak
cp "$SCRIPT_PATH" ".git/.bak/release.sh"

# Handle script interruption
cleanup() {
  echo -e "\nScript interrupted. Reverting changes..."
  revert_changes
  exit 1
}
trap cleanup INT TERM

# restore the release script
trap 'mv ".git/.bak/release.sh" "$SCRIPT_PATH" > /dev/null 2>&1' EXIT

ROOT_DIR="$(dirname "$(dirname "$0")")"
# read version from unruntime.sh
UNRUNTIME_PATH="$ROOT_DIR/unruntime.sh"
VERSION=$(grep -oP 'UNRUNTIME_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "$UNRUNTIME_PATH")

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
if git status --porcelain | grep -v '^ M scripts/release.sh$' | grep -q .; then
  echo "Working directory is not clean. Please commit or stash changes first."
  exit 1
fi

# Check if version was found
if [ -z "$VERSION" ]; then
  echo "Error: Could not find UNRUNTIME_VERSION in $UNRUNTIME_PATH"
  exit 1
fi

# Parse command line arguments
NO_BUMP=false
while [[ $# -gt 0 ]]; do
  case $1 in
  --no-bump)
    NO_BUMP=true
    shift
    ;;
  *)
    echo "Unknown option: $1"
    exit 1
    ;;
  esac
done

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
  sed -i "s/UNRUNTIME_VERSION=.*/UNRUNTIME_VERSION=$new_version/" "$UNRUNTIME_PATH"
}

# Function to create release notes
create_release_notes() {
  local version=$1
  local prev_version=$2

  # Get commits between versions, only the subject line
  local commits
  if git rev-parse "$prev_version" >/dev/null 2>&1; then
    commits=$(git log --format='%s' "$prev_version..HEAD" | sed 's/\$([^)]*)//g' | sed 's/"//g')
  else
    commits=$(git log --format='%s' | sed 's/\$([^)]*)//g' | sed 's/"//g')
  fi

  # Write directly to file to avoid shell interpolation
  {
    echo "# Changelog"
    echo
    echo "## v${version}"
    echo
    echo "$commits" | while IFS= read -r msg; do
      type=$(echo "$msg" | sed -n 's/^\([^:]*\):.*/\1/p')
      message=$(echo "$msg" | sed 's/^[^:]*: *//')
      [ -z "$type" ] || [ -z "$message" ] && continue
      echo "### $type"
      echo "- $message"
    done
  } >"$ROOT_DIR/CHANGELOG.md"
}

# Function to update changelog
update_changelog() {
  local new_version=$1
  create_release_notes "$new_version" "v$VERSION"
}

# Function to revert all changes
revert_changes() {
  echo "Reverting all changes..."

  # Get the commit hash from before we started the release
  local start_point
  start_point=$(git rev-list -n 1 "HEAD~$(git rev-list --count HEAD...origin/main)")

  # Hard reset to that point
  git reset --hard "$start_point"

  # Clean up any untracked files (like CHANGELOG.md if it was just created)
  git clean -f
  mv ".git/.bak/release.sh" "$SCRIPT_PATH"

  echo "All changes have been reverted to state before release."
}

# Main release process
main() {
  # Get current version
  echo "Current version: $VERSION"

  if [ "$NO_BUMP" = true ]; then
    echo "Using current version (no bump)"
    release_version=$VERSION
    echo "---"
  else
    echo "Select version bump type:"
    echo "1) Major (X.0.0)"
    echo "2) Minor (0.X.0)"
    echo "3) Patch (0.0.X)"
    read -r choice

    case $choice in
    1) release_version=$(bump_version "$VERSION" "major") ;;
    2) release_version=$(bump_version "$VERSION" "minor") ;;
    3) release_version=$(bump_version "$VERSION" "patch") ;;
    *)
      echo "Invalid choice"
      exit 1
      ;;
    esac

    echo "New version will be: v$release_version"
    read -r -p "Continue? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
      echo "Release cancelled"
      exit 0
    fi

    # Update version in unruntime.sh
    update_version "$release_version"
  fi

  # ====================
  # ====================
  # ====================
  # ====================
  # ====================
  echo "release_version: $release_version"
  echo "version: $VERSION"
  updated_version=$(grep -oP 'UNRUNTIME_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "$UNRUNTIME_PATH")
  echo "updated_version: $updated_version"
  # sleep 10
  # revert_changes
  # exit 0
  # ====================
  # ====================
  # ====================
  # ====================
  # ====================

  # Now make the changes
  if [ "$NO_BUMP" = false ]; then
    update_version "$release_version"
  fi
  update_changelog "$release_version"

  sleep 10
  revert_changes
  exit 0

  # Show changes before committing
  # echo "The following changes will be committed:"
  # echo "----------------------------------------"
  # git diff | cat # Use cat to prevent pager
  # echo "----------------------------------------"

  read -r -p "Review the changes above. Commit and push to GitHub? (y/n): " push_confirm
  if [ "$push_confirm" != "y" ]; then
    echo "Release cancelled. Reverting all changes..."
    revert_changes
    exit 0
  fi

  # Commit changes
  if [ "$NO_BUMP" = true ]; then
    git add "$ROOT_DIR/CHANGELOG.md"
    git commit -m "chore: update changelog for v${release_version}"
  else
    git add "$UNRUNTIME_PATH" "$ROOT_DIR/CHANGELOG.md"
    git commit -m "chore: bump version to v${release_version}"
  fi

  # Create git tag
  git tag -a "v$release_version" -m "Release v$release_version"

  # Push changes and tag
  git push origin main
  git push origin "v$release_version"

  echo "Release v$release_version completed successfully!"
}

main

#! /bin/bash

# set -e

# backup the release script
SCRIPT_PATH="$0"
ROOT_DIR="$(dirname "$(dirname "$0")")"
UNRUNTIME_PATH="$ROOT_DIR/unruntime.sh"
CHANGELOG_PATH="$ROOT_DIR/CHANGELOG.md"
REPO_URL="https://github.com/jasenmichael/unruntime"

# Error handling and cleanup functions
cleanup() {
  echo -e "\nScript interrupted. Reverting changes..."
  revert_changes
  exit 1
}

revert_changes() {
  echo "Reverting all changes..."

  # Get the commit hash from before we started the release
  local start_point
  start_point=$(git rev-list -n 1 "HEAD~$(git rev-list --count HEAD...origin/main)")

  # Hard reset to that point
  git reset --hard "$start_point"

  # Clean up any untracked files (like CHANGELOG.md if it was just created)
  git clean -f
  mv ".git/.bak/release.sh" "$SCRIPT_PATH" >/dev/null 2>&1

  echo "All changes have been reverted to state before release."
}

# Helper functions
get_version() {
  grep -oP 'UNRUNTIME_VERSION=\K[0-9]+\.[0-9]+\.[0-9]+' "$UNRUNTIME_PATH" | tr -d ' \r'
}

bump_version() {
  local type=$1
  local major minor patch
  IFS='.' read -r major minor patch <<<"$VERSION"

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

update_unruntime_version() {
  sed -i "1,/^UNRUNTIME_VERSION=/s/UNRUNTIME_VERSION=.*/UNRUNTIME_VERSION=$VERSION/" "$UNRUNTIME_PATH"
}

get_bump_version() {
  local bump_type="patch" # default to patch

  # Get commits since last tag
  local commits
  if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    commits=$(git log --format='%s' "$(git describe --tags --abbrev=0)..HEAD")
  else
    commits=$(git log --format='%s')
  fi

  # Check for breaking changes (feat! or feature!)
  if echo "$commits" | grep -qE "^(feat!|feature!):"; then
    bump_type="major"
  # Check for new features (feat or feature)
  elif echo "$commits" | grep -qE "^(feat|feature):"; then
    bump_type="minor"
  fi

  # Return the new version
  bump_version "$bump_type"
}

get_release_notes() {
  local version=$1
  local prev_version=$2

  # Get commits between versions, including both subject line and hash
  local commits
  if git rev-parse "$prev_version" >/dev/null 2>&1; then
    commits=$(git log --format='%s|%h' "$prev_version..HEAD" | sed "s/\$([^)]*)//g" | sed 's/"//g')
  else
    commits=$(git log --format='%s|%h' | sed "s/\$([^)]*)//g" | sed 's/"//g')
  fi

  # Format the release notes
  {
    echo "## v${version}"
    echo
    # if not the first release, add compare link
    if [ -n "$(git tag -l)" ]; then
      echo "[compare changes](${REPO_URL}/compare/v${prev_version}...v${version})"
      echo
    fi
    # set types and messages
    declare -A type_messages
    while IFS='|' read -r msg hash; do
      type=${msg//:*/}
      message=${msg//*: /}
      [ -z "$type" ] || [ -z "$message" ] && continue
      type_messages["$type"]+="- $message ([$hash](${REPO_URL}/commit/$hash))"$'\n'
    done <<<"$commits"

    # Map types to their styled names and emojis
    declare -A type_styles=(
      ["docs"]="### 📖 Documentation"
      ["feat"]="### 🚀 Enhancements"
      ["feature"]="### 🚀 Enhancements"
      ["chore"]="### 🏡 Chore"
      ["fix"]="### 🐛 Bug Fixes"
      ["fix!"]="### 🐛 Bug Fixes"
      ["refactor"]="### 🔄 Refactor"
      ["ci"]="### 🤖 CI"
      ["test"]="### 🧪 Tests"
      ["perf"]="### 📈 Performance"
      ["style"]="### 🎨 Style"
    )

    # Then output each type and its messages
    for type in "${!type_messages[@]}"; do
      style="${type_styles[$type]:-### $type}"
      echo "$style"
      echo -n "${type_messages[$type]}"
      echo
    done
  }
}

# Main execution flow functions
ensure_git_installed() {
  # check for git command
  if ! command -v git &>/dev/null; then
    echo "git could not be found"
    exit 1
  fi
}

ensure_on_main_branch() {
  # check if we're on main branch
  CURRENT_BRANCH=$(git branch --show-current)
  if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "Please switch to main branch before releasing"
    exit 1
  fi
}

ensure_pulled_latest_changes() {
  # Pull latest changes from remote
  if ! git pull origin main >/dev/null 2>&1; then
    echo "Failed to pull from remote. Please resolve any conflicts and try again."
    exit 1
  fi
}

ensure_working_directory_is_clean() {
  mkdir -p .git/.bak
  cp "$SCRIPT_PATH" ".git/.bak/release.sh"

  # check if working directory is clean
  if git status --porcelain | grep -v '^ M scripts/release.sh$' | grep -q .; then
    echo "Working directory is not clean. Please commit or stash changes first."
    exit 1
  fi
}

ensure_code_formatted() {
  if ! "$ROOT_DIR/scripts/fmt.sh" "$ROOT_DIR" >/dev/null 2>&1; then
    echo "Failed to format code"
    exit 1
  else
    if git status --porcelain | grep -v '^ M scripts/release.sh$' | grep -q .; then
      echo "Format and commit changes before releasing"
      exit 1
    fi
  fi
}

ensure_version_set() {
  # Check if version was found
  if [ -z "$VERSION" ]; then
    echo "Error: Could not find UNRUNTIME_VERSION in $UNRUNTIME_PATH"
    exit 1
  fi
}

parse_args() {
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
}

set_release_version() {
  # Get current version
  echo "Current version: $VERSION"
  suggested_release_version=$(get_bump_version)
  echo "Suggested version: $suggested_release_version"

  if [ "$NO_BUMP" = true ]; then
    echo "Using current version ($VERSION) (no bump)"
  else
    echo "Press enter to accept suggested version"
    echo "Or select version bump type:"
    echo "1) Major (X.0.0)"
    echo "2) Minor (0.X.0)"
    echo "3) Patch (0.0.X)"
    read -r choice

    case $choice in
    1) VERSION=$(bump_version "major") ;;
    2) VERSION=$(bump_version "minor") ;;
    3) VERSION=$(bump_version "patch") ;;
    *)
      if [ -z "$choice" ]; then
        VERSION=$(get_bump_version)
      else
        echo "Invalid choice: $choice"
        exit 1
      fi
      ;;
    esac

    echo "New version will be: v$VERSION"
    read -r -p "Continue? (y/n): " confirm
    if [ "$confirm" != "y" ]; then
      echo "Release cancelled"
      exit 0
    fi

    echo "---"

    update_unruntime_version
    # TODO: update readme version
  fi
}

init_changelog() {
  if [ ! -f "$CHANGELOG_PATH" ]; then
    echo "# Changelog" >"$CHANGELOG_PATH"
  fi
}

update_changelog() {
  # Get the last release tag
  last_release=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')

  # remove the v from the version
  release_notes=$(get_release_notes "$VERSION" "$last_release")

  echo "-------------------"
  echo "**Changelog Release Notes**"
  echo "$release_notes"
  echo "-------------------"
  # replace the first line of $CHANGELOG_PATH with '# Changelog\n\n$release_notes'
  sed -i "1c\\# Changelog\n\n${release_notes//$'\n'/\\n}" "$CHANGELOG_PATH"
}

confirm_release() {
  read -r -p "Review the changes above. Commit and push to GitHub? (y/n): " push_confirm
  if [ "$push_confirm" != "y" ]; then
    echo "Release cancelled. Reverting all changes..."
    revert_changes
    exit 0
  fi
}

commit_changes() {
  local message=$1
  if [ "$NO_BUMP" = true ]; then
    git add "$ROOT_DIR/CHANGELOG.md"
  else
    git add "$UNRUNTIME_PATH" "$ROOT_DIR/CHANGELOG.md" "$ROOT_DIR/README.md"
  fi
  git commit -m "$message"
}

create_tag() {
  git tag -a "v$VERSION" -m "$1"
}

push_changes() {
  # Push changes and tag
  git push origin main
  git push origin "v$VERSION"
}

# Main execution
trap cleanup INT TERM
trap 'mv ".git/.bak/release.sh" "$SCRIPT_PATH" >/dev/null 2>&1' EXIT

ensure_git_installed
ensure_on_main_branch
ensure_pulled_latest_changes
ensure_working_directory_is_clean
ensure_code_formatted

VERSION=$(get_version)
ensure_version_set

parse_args "$@"
set_release_version

init_changelog # create changelog if it doesn't exist
update_changelog
confirm_release

commit_changes "Release v$VERSION"
create_tag "Release v$VERSION"
push_changes

echo "Release v$VERSION completed successfully!"

#!/usr/bin/env bash

ROOT_DIR="$(dirname "$(dirname "$0")")"

# Detect architecture
case "$(uname -m)" in
x86_64) ARCH="amd64" ;;
aarch64) ARCH="arm64" ;;
*) echo "Unsupported architecture: $(uname -m)" && exit 1 ;;
esac

# shfmt configuration
SHFMT_PATH="$ROOT_DIR/.bin/shfmt"
SHFMT_VERSION="3.8.0"
SHFMT_FILE="shfmt_v${SHFMT_VERSION}_linux_${ARCH}"
SHFMT_URL="https://github.com/mvdan/sh/releases/download/v${SHFMT_VERSION}/${SHFMT_FILE}"
install_shfmt() {
  if [ ! -s "$SHFMT_PATH" ]; then
    mkdir -p "$ROOT_DIR/.bin"
    echo "Downloading shfmt"
    if ! curl -L -o "$SHFMT_PATH" "$SHFMT_URL"; then
      rm -f "$SHFMT_PATH" >/dev/null 2>&1
      echo "ERROR: Download shfmt failed."
      exit 1
    fi
    chmod +x "$SHFMT_PATH"
  fi
}

# check if shfmt is installed
if [ ! -f "$SHFMT_PATH" ]; then
  install_shfmt
fi

[ -z "$1" ] && echo "Missing file or directory argument" && exit 1

format() {
  echo "Formatting $1"
  "$SHFMT_PATH" -i 2 -w "$1"
}

if [ -f "$1" ]; then
  format "$1"
elif [ -d "$1" ]; then
  echo "Formatting all files in directory"
  while IFS= read -r file; do
    format "$file"
  done < <(find "$1" -type f -name "*.sh")
else
  echo "Error: $1 is not a file or directory"
  exit 1
fi

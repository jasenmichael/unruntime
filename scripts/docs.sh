#!/bin/bash

ROOT_DIR="$(dirname "$(dirname "$0")")"
TITLE="unruntime"
DESCRIPTION="unruntime - A web installer for JavaScript runtimes and package managers. Set up your JavaScript development environment with essential tools like Node.js, npm, pnpm, yarn, bun, and deno."
KEYWORDS="JavaScript, runtime installer, Node.js, npm, pnpm, yarn, bun, deno, package manager, web development, development tools"
AUTHOR="Jasen Michael"

MD=$ROOT_DIR/README.md
TEMPLATE=$ROOT_DIR/src/template.html
PUBLIC_DIR=$ROOT_DIR/src/public
OUTPUT_DIR=$ROOT_DIR/docs

# check for pandoc command
if ! command -v pandoc &>/dev/null; then
  echo "pandoc could not be found"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

pandoc -f markdown \
  -t html "$MD" \
  --metadata title="$TITLE" \
  --metadata description="$DESCRIPTION" \
  --metadata author="$AUTHOR" \
  --metadata keywords="$KEYWORDS" \
  --template="$TEMPLATE" \
  --highlight-style=tango \
  -o "$OUTPUT_DIR/index.html" &&
  echo "Build successful" ||
  echo "Build failed"

cp -r "$PUBLIC_DIR"/* "$OUTPUT_DIR/"

#!/bin/bash

ROOT_DIR="$(dirname "$(dirname "$0")")"
TITLE="unruntime"
MD=$ROOT_DIR/README.md
TEMPLATE=$ROOT_DIR/src/template.html
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
  --template="$TEMPLATE" \
  -o "$OUTPUT_DIR/index.html" &&
  echo "Build successful" ||
  echo "Build failed"

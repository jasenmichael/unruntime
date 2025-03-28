#!/bin/bash
# shellcheck disable=SC1091

# sources:
#     DOCS_README, DOCS_TITLE, DOCS_DESCRIPTION, DOCS_AUTHOR,
#     DOCS_KEYWORDS, DOCS_BUILD_OUTPUT, DOCS_PUBLIC_DIR,
#     DOCS_BUILD_DIR, DOCS_SCRIPT, SCRIPT_DIR
. "$(dirname "$0")/.vars"

build_docs() {
  # check for pandoc command
  if ! command -v pandoc &>/dev/null; then
    echo "pandoc could not be found"
    exit 1
  fi

  # check for public dir
  if [ ! -d "$DOCS_PUBLIC_DIR" ]; then
    echo "Error: DOCS_PUBLIC_DIR $DOCS_PUBLIC_DIR does not exist"
    exit 1
  fi

  mkdir -p "$DOCS_BUILD_DIR"

  # build html from template and README.md
  pandoc -f markdown \
    -t html "$DOCS_README" \
    --metadata title="$DOCS_TITLE" \
    --metadata description="$DOCS_DESCRIPTION" \
    --metadata author="$DOCS_AUTHOR" \
    --metadata keywords="$DOCS_KEYWORDS" \
    --template="$DOCS_TEMPLATE" \
    --highlight-style=tango \
    -o "$DOCS_BUILD_OUTPUT" || { echo "Build failed" && exit 1; }

  # copy public assets to build dir
  cp -r "$DOCS_PUBLIC_DIR"/* "$DOCS_BUILD_DIR/" || { echo "Copy failed" && exit 1; }

  shellify_html

  echo "Build successful"
  echo "  - $DOCS_BUILD_OUTPUT"
}

dev() {
  npx_cmd="npx"
  # check for pnpm command
  if command -v pnpm &>/dev/null; then
    npx_cmd="pnpm dlx"
  fi

  # Start http-server in the background
  mkdir -p "$DOCS_BUILD_DIR"
  # $npx_cmd http-server "$DOCS_BUILD_DIR" &
  $npx_cmd live-server "$DOCS_BUILD_DIR" &

  # Store the server's PID
  SERVER_PID=$!

  # Function to kill the server
  cleanup() {
    echo "Stopping server..."
    kill "$SERVER_PID" >/dev/null 2>&1
  }

  # Set up cleanup on script exit
  trap cleanup EXIT

  # Watch for file changes and rebuild
  echo "Starting file watcher..."
  $npx_cmd nodemon \
    --watch "$DOCS_DIR" \
    --watch "$DOCS_README" \
    --watch "$SCRIPT_DIR/vars" \
    --ignore "$DOCS_SCRIPT" \
    --ignore "$DOCS_BUILD_DIR" \
    --ext md,sh,html \
    --exec "$DOCS_SCRIPT build"
}

shellify_html() {
  #!/bin/bash

  # Make HTML one line and split at </body>
  tr -d '\r' <"$DOCS_BUILD_OUTPUT" | tr '\n' ' ' | sed 's/  */ /g' >"$DOCS_BUILD_OUTPUT.tmp" && mv "$DOCS_BUILD_OUTPUT.tmp" "$DOCS_BUILD_OUTPUT"

  # split_at_body
  sed -i 's/\(<\/body>\)/\n\1/g' "$DOCS_BUILD_OUTPUT"

  # append opening div tag to END the fist line, I SAID APPEND TO END OF LINE
  sed -i '1s/$/<div style="display: none; visibility: hidden;">/' "$DOCS_BUILD_OUTPUT"

  # prepend closing body tag with closing div tag
  sed -i 's/\(<\/body>\)/<\/div><\/body>/g' "$DOCS_BUILD_OUTPUT"

  # comment markers
  sed -i 's/^/# /' "$DOCS_BUILD_OUTPUT"
  # this is not really needed
  # sed -i '1i #!/usr/bin/env bash' "$DOCS_BUILD_OUTPUT"

  code=$(cat "$DOCS_WEB_INSTALL")

  # # replace last line with $code\n$last_line
  awk -v code="$code" 'NR==1{print} NR==2{print code "\n" $0}' "$DOCS_BUILD_OUTPUT" >"$DOCS_BUILD_OUTPUT.tmp" && mv "$DOCS_BUILD_OUTPUT.tmp" "$DOCS_BUILD_OUTPUT"
}

if [ "$1" = "build" ]; then
  build_docs
elif [ "$1" = "dev" ]; then
  dev
else
  echo "Invalid command"
  exit 1
fi

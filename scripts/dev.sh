#!/bin/bash

ROOT_DIR="$(dirname "$(dirname "$0")")"

# run build.sh
"$ROOT_DIR/scripts/build.sh"

# Start http-server in the background
pnpm dlx http-server docs &

# Store the server's PID
SERVER_PID=$!

# Function to kill the server
cleanup() {
  kill $SERVER_PID
  exit 0
}

# Set up cleanup on script exit
trap cleanup EXIT

# Watch for file changes and rebuild
echo "Starting file watcher..."
pnpm dlx nodemon --watch src --watch README.md --ext md,sh,html --exec "$ROOT_DIR/scripts/docs.sh"

#!/usr/bin/env bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Session file path
SESSION_FILE="$SCRIPT_DIR/clean_session.lys"

# Check if session file exists
if [[ ! -f "$SESSION_FILE" ]]; then
    echo "Error: session.lys not found in $SCRIPT_DIR"
    exit 1
fi

# Launch KLayout in read-only mode with session
klayout -u "$SESSION_FILE" -e

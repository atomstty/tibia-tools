#!/bin/bash
# fix-drop-chances.sh - Analyze and fix monster drop chances
#
# Usage:
#   ./fix-drop-chances.sh --analyze [--top N] [--below N] [--fix] [--dry-run]
#   ./fix-drop-chances.sh --fix <item_id> [item_id...] [--dry-run] [--min-chance N]
#   ./fix-drop-chances.sh --fix --all [--dry-run] [--min-chance N]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
if [[ -f "$SCRIPT_DIR/config.sh" ]]; then
    source "$SCRIPT_DIR/config.sh"
else
    echo "Error: config.sh not found!"
    echo "Copy config.example.sh to config.sh and edit with your server details."
    exit 1
fi

# Ensure tools directory exists on server
ssh "$SERVER" "mkdir -p $DEST/tools"

# Copy python script to server
scp -q "$SCRIPT_DIR/fix-drop-chances.py" "$SERVER:$DEST/tools/"

# Run python script on server, passing through all arguments
ssh "$SERVER" "python3 $DEST/tools/fix-drop-chances.py \
    --mon-dir $DEST/game/mon \
    --objects-srv $DEST/game/dat/objects.srv \
    $@"

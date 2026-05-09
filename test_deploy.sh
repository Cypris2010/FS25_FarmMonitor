#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MOD_SOURCE="$SCRIPT_DIR/FS25_FarmMonitor"
SERVER_DIR="$SCRIPT_DIR/Server"
MODS_DIR="$HOME/Library/Application Support/FarmingSimulator2025/mods"
ZIP_NAME="FS25_FarmMonitor.zip"

# Stop running server if active
if pgrep -f farmmonitor > /dev/null; then
    echo "Stopping running farmmonitor..."
    pkill -f farmmonitor
    sleep 1
fi

# Build Go server binary
echo "Building server..."
cd "$SERVER_DIR"
go build -o farmmonitor
mv farmmonitor "$SCRIPT_DIR/"
echo "Binary moved to: $SCRIPT_DIR/farmmonitor"

# Deploy ZIP
rm -f "$MODS_DIR/$ZIP_NAME"
cd "$MOD_SOURCE"
zip -r "$MODS_DIR/$ZIP_NAME" .

echo "Deployed $ZIP_NAME to: $MODS_DIR"

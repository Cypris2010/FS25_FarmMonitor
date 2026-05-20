#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
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

# Stamp modDesc.xml with local dev version (base + 0-padded commit count)
cd "$SCRIPT_DIR"
BASE=$(grep -m1 '<version>' "$MOD_SOURCE/modDesc.xml" | sed 's/.*<version>\([0-9]*\.[0-9]*\.[0-9]*\).*/\1/')
COMMITS=$(git rev-list --count HEAD)
BUILD=$(printf "0%d" "$COMMITS")
VERSION="${BASE}.${BUILD}"
sed -i '' "s|<version>.*</version>|<version>${VERSION}</version>|" "$MOD_SOURCE/modDesc.xml"
echo "modDesc version set to: ${VERSION}"

# Deploy ZIP
rm -f "$MODS_DIR/$ZIP_NAME"
cd "$MOD_SOURCE"
zip -r "$MODS_DIR/$ZIP_NAME" .

# Restore modDesc.xml to avoid dirty working tree
cd "$SCRIPT_DIR"
git checkout -- "$MOD_SOURCE/modDesc.xml"

echo "Deployed $ZIP_NAME to: $MODS_DIR"

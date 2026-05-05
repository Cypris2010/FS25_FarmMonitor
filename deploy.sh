#!/bin/bash
set -e

MOD_DIR="$HOME/Library/Application Support/FarmingSimulator2025/mods/FS25_FarmMonitor"

mkdir -p "$MOD_DIR"
cp FarmMonitor.lua modDesc.xml "$MOD_DIR/"

echo "Deployed to: $MOD_DIR"

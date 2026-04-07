#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/update-app-icon.sh /path/to/source-icon.png

if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <path/to/source-icon-png>"
    exit 1
fi

SRC_ICON="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APPICON_DIR="$PROJECT_DIR/AgentIsland/Assets.xcassets/AppIcon.appiconset"

if [ ! -f "$SRC_ICON" ]; then
    echo "ERROR: source icon not found: $SRC_ICON"
    exit 1
fi

if ! command -v sips >/dev/null 2>&1; then
    echo "ERROR: sips is required on macOS"
    exit 1
fi

if ! command -v pngcheck >/dev/null 2>&1; then
    echo "WARN: pngcheck is not installed; skip PNG validity check."
fi

ICON_MAP=(
    "icon_16x16.png:16"
    "icon_32x32.png:32"
    "icon_32x32 1.png:32"
    "icon_64x64.png:64"
    "icon_128x128.png:128"
    "icon_256x256 1.png:256"
    "icon_256x256.png:256"
    "icon_512x512 1.png:512"
    "icon_512x512.png:512"
    "icon_1024x1024.png:1024"
)

for row in "${ICON_MAP[@]}"; do
    file_name="${row%:*}"
    target_size="${row#*:}"
    out_path="$APPICON_DIR/$file_name"

    cp "$SRC_ICON" "$out_path"
    sips -s format png "$out_path" --out "$out_path" >/dev/null
    sips -Z "$target_size" "$out_path" >/dev/null
done

echo "Updated App icon files in:"
echo "  $APPICON_DIR"

#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/update-app-icon.sh
#   ./scripts/update-app-icon.sh /path/to/source-icon.png

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APPICON_DIR="$PROJECT_DIR/AgentIsland/Assets.xcassets/AppIcon.appiconset"
DEFAULT_SRC_ICON="$PROJECT_DIR/agent-island.png"
SRC_ICON="${1:-$DEFAULT_SRC_ICON}"

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

if command -v pngcheck >/dev/null 2>&1; then
    pngcheck "$SRC_ICON" >/dev/null
fi

width="$(sips -g pixelWidth "$SRC_ICON" | awk '/pixelWidth:/ { print $2 }')"
height="$(sips -g pixelHeight "$SRC_ICON" | awk '/pixelHeight:/ { print $2 }')"

if [ -z "$width" ] || [ -z "$height" ]; then
    echo "ERROR: unable to read source icon size: $SRC_ICON"
    exit 1
fi

if [ "$width" != "$height" ]; then
    echo "ERROR: source icon must be square, got ${width}x${height}"
    exit 1
fi

if [ "$width" -lt 1024 ]; then
    echo "ERROR: source icon must be at least 1024x1024, got ${width}x${height}"
    exit 1
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
    sips -z "$target_size" "$target_size" "$out_path" >/dev/null
done

echo "Updated App icon files in:"
echo "  $APPICON_DIR"

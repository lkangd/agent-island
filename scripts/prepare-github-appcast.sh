#!/bin/bash
# Generate a Sparkle appcast.xml that is hosted on GitHub Pages
# while the downloadable update archive remains on GitHub Releases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

VERSION_TAG="${VERSION_TAG:-${1:-}}"
DMG_PATH="${DMG_PATH:-${2:-}}"
OUTPUT_DIR="${OUTPUT_DIR:-${3:-$PROJECT_DIR/build/appcast-pages}}"
KEY_FILE="${SPARKLE_PRIVATE_KEY_FILE:-$PROJECT_DIR/.sparkle-keys/eddsa_private_key}"
GITHUB_REPO="${GITHUB_REPO:-javen-yan/agent-island}"

if [ -z "$VERSION_TAG" ]; then
    echo "ERROR: VERSION_TAG is required"
    echo "Usage: VERSION_TAG=v1.0.0 DMG_PATH=/path/to/AgentIsland-v1.0.0.dmg $0"
    exit 1
fi

if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG_PATH must point to an existing DMG"
    exit 1
fi

if [ ! -f "$KEY_FILE" ]; then
    echo "ERROR: Sparkle private key not found at $KEY_FILE"
    exit 1
fi

GENERATE_APPCAST=""
POSSIBLE_PATHS=(
    "$HOME/Library/Developer/Xcode/DerivedData/AgentIsland-*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
    "$PROJECT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
)

for path_pattern in "${POSSIBLE_PATHS[@]}"; do
    for path in $path_pattern; do
        if [ -x "$path" ]; then
            GENERATE_APPCAST="$path"
            break 2
        fi
    done
done

if [ -z "$GENERATE_APPCAST" ]; then
    echo "ERROR: Could not find Sparkle generate_appcast tool"
    echo "Run xcodebuild -resolvePackageDependencies or build the project first."
    exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"
cp "$DMG_PATH" "$TMP_DIR/"

"$GENERATE_APPCAST" --ed-key-file "$KEY_FILE" "$TMP_DIR"

APPCAST_PATH="$TMP_DIR/appcast.xml"
if [ ! -f "$APPCAST_PATH" ]; then
    echo "ERROR: generate_appcast did not produce appcast.xml"
    exit 1
fi

RELEASE_URL="https://github.com/$GITHUB_REPO/releases/download/$VERSION_TAG/$(basename "$DMG_PATH")"

python3 - <<'PY' "$APPCAST_PATH" "$RELEASE_URL"
import sys
import xml.etree.ElementTree as ET

appcast_path, release_url = sys.argv[1], sys.argv[2]
tree = ET.parse(appcast_path)
root = tree.getroot()
for enclosure in root.iter():
    if enclosure.tag.endswith("enclosure"):
        enclosure.set("url", release_url)
tree.write(appcast_path, encoding="utf-8", xml_declaration=True)
PY

cp "$APPCAST_PATH" "$OUTPUT_DIR/appcast.xml"
echo "Generated GitHub Pages appcast at: $OUTPUT_DIR/appcast.xml"
echo "Release download URL: $RELEASE_URL"

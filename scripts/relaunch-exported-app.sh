#!/bin/bash
# Relaunch the freshly built app from build/export by force-quitting any running instance first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_PATH="$PROJECT_DIR/build/export/Agent Island.app"

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: App not found at: $APP_PATH"
    echo "Please run ./scripts/build.sh first."
    exit 1
fi

echo "Force quitting running Agent Island instance(s)..."
killall -9 "Agent Island" >/dev/null 2>&1 || true
killall -9 "AgentIsland" >/dev/null 2>&1 || true

echo "Launching: $APP_PATH"
open "$APP_PATH"

echo "Done."

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BRIDGE_DIR="$PROJECT_DIR/bridge-rs"

for candidate_dir in "$HOME/.cargo/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
    if [ -d "$candidate_dir" ]; then
        PATH="$candidate_dir:$PATH"
    fi
done

if ! command -v cargo >/dev/null 2>&1; then
    echo "cargo is required to build agent-island-bridge"
    echo "PATH=$PATH"
    exit 1
fi

cd "$BRIDGE_DIR"
cargo build --release

echo ""
echo "Built bridge binary:"
echo "  $BRIDGE_DIR/target/release/agent-island-bridge"

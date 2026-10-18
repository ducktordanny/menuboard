#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
pkill -x MenuBoard 2>/dev/null || true
open build/MenuBoard.app

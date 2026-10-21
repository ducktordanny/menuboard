#!/bin/zsh
# Builds the SwiftPM executable and wraps it into a signed build/MenuBoard.app.
# Signing with a real identity keeps the audio-capture permission grant stable across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/MenuBoard.app"
BINARY=".build/$CONFIG/MenuBoard"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/MenuBoard"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application|Apple Development/ { print $2; exit }')"
fi
IDENTITY="${IDENTITY:--}"

codesign --force --sign "$IDENTITY" --identifier com.daniellazar.menuboard "$APP"
echo "Built $APP (signed with: $IDENTITY)"

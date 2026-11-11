#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/TouchBuddy.app"
IDENTITY="${TOUCHBUDDY_SIGN_IDENTITY:-TouchBuddy Local Signing}"

cd "$ROOT"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TouchBuddy" "$BIN_DIR/touchbuddy-hook" "$APP/Contents/MacOS/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -d "$ROOT/Resources/Characters" ]; then
    cp -R "$ROOT/Resources/Characters" "$APP/Contents/Resources/Characters"
fi

if security find-identity -p codesigning | grep -qF "\"$IDENTITY\""; then
    SIGN="$IDENTITY"
else
    echo "warning: signing identity '$IDENTITY' not found; signing ad-hoc" >&2
    SIGN="-"
fi
codesign --force --deep --options runtime --sign "$SIGN" "$APP"
echo "Built $APP"

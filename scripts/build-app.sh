#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-debug}"
INSTALL=0
CONFIG="$MODE"
if [ "$MODE" = "install" ]; then
    INSTALL=1
    CONFIG="release"
fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/TouchBuddy.app"
IDENTITY="${TOUCHBUDDY_SIGN_IDENTITY:-TouchBuddy Local Signing}"

# Release builds are universal: Touch Bar Macs are mostly Intel, CI runners are arm64.
# --show-bin-path must get the same flags as the build (multi-arch changes the bin path).
if [ "$CONFIG" = "release" ]; then
    BUILD_FLAGS=(-c "$CONFIG" --arch arm64 --arch x86_64)
else
    BUILD_FLAGS=(-c "$CONFIG")
fi

cd "$ROOT"
swift build "${BUILD_FLAGS[@]}"
BIN_DIR="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TouchBuddy" "$BIN_DIR/touchbuddy-hook" "$APP/Contents/MacOS/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -d "$ROOT/Resources/Characters" ]; then
    cp -R "$ROOT/Resources/Characters" "$APP/Contents/Resources/Characters"
fi

IDENTITIES="$(security find-identity -v -p codesigning)"
if grep -qF "\"$IDENTITY\"" <<<"$IDENTITIES"; then
    SIGN="$IDENTITY"
else
    echo "warning: signing identity '$IDENTITY' not found; signing ad-hoc" >&2
    SIGN="-"
fi
if [ "$INSTALL" = 1 ] && [ "$SIGN" = "-" ]; then
    echo "error: refusing to install an ad-hoc signed build; run scripts/make-signing-identity.sh first." >&2
    exit 1
fi
codesign --force --options runtime --sign "$SIGN" "$APP/Contents/MacOS/touchbuddy-hook"
codesign --force --options runtime --entitlements "$ROOT/Resources/TouchBuddy.entitlements" --sign "$SIGN" "$APP"
echo "Built $APP"

if [ "$INSTALL" = 1 ]; then
    codesign --verify --strict "$APP"
    pkill -x TouchBuddy || true
    for _ in $(seq 1 15); do
        pgrep -x TouchBuddy >/dev/null || break
        sleep 0.2
    done
    rm -rf /Applications/TouchBuddy.app
    ditto "$APP" /Applications/TouchBuddy.app
    open /Applications/TouchBuddy.app
    echo "Installed /Applications/TouchBuddy.app"
fi

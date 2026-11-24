#!/usr/bin/env bash
# Builds dist/PixelPlayer Dev.app from the Swift package, so `open` can bring it to the front
# (glass only looks as it does in use when the app is active).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c debug --arch arm64 --product PixelPlayerMac 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | grep -v "^$" | tail -30 || true
BIN="$(swift build -c debug --arch arm64 --show-bin-path 2>/dev/null)/PixelPlayerMac"
[ -x "$BIN" ] || { echo "build failed"; exit 1; }
APP="dist/PixelPlayer Dev.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PixelPlayerMac"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"

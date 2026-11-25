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
# The icon, drawn in code (scripts/make-icon.swift), in every size macOS asks for.
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
swift scripts/make-icon.swift "$ICONSET/base.png" 1024
for size in 16 32 128 256 512; do
  sips -z $size $size "$ICONSET/base.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$ICONSET/base.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
rm "$ICONSET/base.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "built $APP"

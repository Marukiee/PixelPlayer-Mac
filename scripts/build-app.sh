#!/usr/bin/env bash
# Builds the app from the Swift package.
#   scripts/build-app.sh            dist/PixelPlayer Dev.app, a debug build that never updates itself
#   scripts/build-app.sh release    dist/PixelPlayer.app, version from $VERSION and $BUILD (the release workflow sets them)
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-debug}"
if [ "$MODE" = release ]; then CONFIG=release; APP="dist/PixelPlayer.app"; else CONFIG=debug; APP="dist/PixelPlayer Dev.app"; fi
swift build -c $CONFIG --arch arm64 --product PixelPlayerMac 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" | grep -v "^$" | tail -30 || true
BIN="$(swift build -c $CONFIG --arch arm64 --show-bin-path 2>/dev/null)/PixelPlayerMac"
[ -x "$BIN" ] || { echo "build failed"; exit 1; }
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PixelPlayerMac"
PLIST="$APP/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
# The key the update signatures are checked with (scripts/gen-update-key.swift made it).
plutil -replace PixelPlayerUpdatePublicKey -string "$(tr -d '[:space:]' < Resources/update-public-key.txt)" "$PLIST"
if [ "$MODE" = release ]; then
  plutil -replace CFBundleName -string PixelPlayer "$PLIST"
  plutil -replace CFBundleDisplayName -string PixelPlayer "$PLIST"
  plutil -replace CFBundleIdentifier -string nl.markmaaktmedia.PixelPlayer "$PLIST"
  plutil -replace CFBundleShortVersionString -string "${VERSION:?set VERSION}" "$PLIST"
  plutil -replace CFBundleVersion -string "${BUILD:-1}" "$PLIST"
fi
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
# One lasting identity, so Local Network and Bluetooth permissions survive every new build.
./scripts/mac-signing.sh sign "$APP" >/dev/null
echo "built $APP"

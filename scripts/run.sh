#!/usr/bin/env bash
# Runs the prototype with a capture script and waits until it quits.
#   scripts/run.sh <out-dir> "<script>" [extra env as KEY=VALUE ...]
# Only the app's own windows are captured (screencapture -l), never the screen.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; SCRIPT="$2"; shift 2
mkdir -p "$OUT"
pkill -f "PixelPlayer Dev.app/Contents/MacOS" 2>/dev/null || true
env PP_DEBUG_DIR="$OUT" PP_WINDOW="${PP_WINDOW:-1180x760}" PP_FREEZE=1 PP_SCRIPT="$SCRIPT" "$@" \
  "dist/PixelPlayer Dev.app/Contents/MacOS/PixelPlayerMac" >"$OUT/run.log" 2>&1 &
PID=$!
sleep 1.2; open "dist/PixelPlayer Dev.app" >/dev/null 2>&1 || true   # brings it to the front, so the glass is drawn as in use
# The app quits itself at the end of the script; a stuck run is stopped after five minutes.
for _ in $(seq 1 600); do kill -0 $PID 2>/dev/null || break; sleep 0.5; done
kill $PID 2>/dev/null || true

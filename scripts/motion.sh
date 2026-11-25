#!/usr/bin/env bash
# Clips of the motion, one per direction, at real speed.
#   scripts/motion.sh [out-dir]       (default design/ronde-4)
# Every spring runs SLOW times slower while the app's own window is captured frame by frame with
# screencapture -l (real glass, nothing else of the screen). Each frame keeps its moment, and the clip is put
# together with those moments divided by SLOW, so it plays at the real speed.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-design/ronde-4}"; shift || true
DIRS="${*:-r3}"
SLOW="${SLOW:-6}"
W="wait:$(echo "0.75 * $SLOW" | bc)"     # long enough for one spring to settle
FRAMES="${FRAMES:-${TMPDIR:-/tmp}/pixelplayer-frames}"   # hundreds of PNGs: kept out of the repo
mkdir -p "$FRAMES" "$OUT"
[ -n "${NOBUILD:-}" ] || ./scripts/build-app.sh >/dev/null

for d in $DIRS; do
  # Pages, the queue in the inspector, Speelt nu in and out, play and pause.
  steps="page:liked,$W,page:album:a2,$W,page:home,$W,queue:1,$W,queue:0,$W,full:1,$W,full:0,$W,fullscreen:1,$W,fullscreen:0,$W,play:0,$W,play:1,$W"
  n=$(echo "$steps" | tr ',' '\n' | grep -c wait)
  secs=$(echo "$n * 0.75 * $SLOW + 2" | bc)
  ./scripts/run.sh "$FRAMES" "page:home,wait:1,shot:probe-$d,slow:$SLOW,frames:$d:$secs,wait:0.8,$steps,wait:3,quit" PP_APPEARANCE="${APPEARANCE:-light}"
  F="$FRAMES/frames-$d"
  # A concat list with each frame's real duration.
  awk -v slow="$SLOW" -v dir="$F" 'NR>1 { if (prev != "") printf "file %s/%s.png\nduration %.5f\n", dir, prev, ($2 - pt) / slow; prev=$1; pt=$2 } END { printf "file %s/%s.png\n", dir, prev }' "$F/times.txt" > "$F/list.txt"
  ffmpeg -nostdin -loglevel error -y -f concat -safe 0 -i "$F/list.txt" -vf "fps=30,scale=1180:-2:flags=lanczos,format=yuv420p" -c:v libx264 -crf 18 -preset slow -movflags +faststart "$OUT/beweging.mp4"
  echo "$OUT/beweging.mp4 ($(($(wc -l < "$F/times.txt") - 1)) frames)"
done

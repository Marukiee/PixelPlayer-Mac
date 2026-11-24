#!/usr/bin/env bash
# Real screenshots of both variants and every scene, light and dark, plus side-by-side sheets.
#   scripts/capture-all.sh [out-dir]      (default design/ronde-2)
# Only the app's own windows are captured (screencapture -l); an open popover is captured as its own
# window and laid over the picture at its real place. Nothing else of the screen ends up in a picture.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-design/ronde-2}"
RAW="$OUT/los"
mkdir -p "$RAW"
[ -n "${NOBUILD:-}" ] || ./scripts/build-app.sh >/dev/null

scenes() {   # $1 = licht|donker
  local s="$1" steps=""
  for d in a b; do
    steps+="dir:$d,page:home,wait:1.4,shot:$d-1-home-$s,page:songs,wait:1.2,shot:$d-2-nummers-$s,queue:1,wait:1.4,shot:$d-3-wachtrij-$s,queue:0,page:home,wait:1,"
    steps+="devices:1,wait:1.4,shot:$d-4-verbinden-$s,devices:0,wait:0.8,full:1,wait:1.6,shot:$d-5-speelt-nu-$s,full:0,wait:0.8,"
  done
  steps+="search:blue,wait:1.2,shot:x-zoeken-$s,search:,page:home,"
  steps+="settings:general,shot:x,settingsshot:x-instellingen-algemeen-$s,settings:sources,wait:0.8,settingsshot:x-instellingen-bronnen-$s,closesettings,"
  steps+="stage:x-menubalk-$s"
  echo "$steps"
}
[ -n "${COMPOSE_ONLY:-}" ] || ./scripts/run.sh "$RAW" "$(scenes licht),appearance:dark,wait:1,$(scenes donker),quit" PP_APPEARANCE=light
rm -f "$RAW/x.png" "$RAW"/*-region.png

# The window pictures have see-through rounded corners; put them on white first, or they turn black when combined.
FLAT="$(mktemp -d)"
for f in "$RAW"/*.png; do magick -quiet "$f" -background white -alpha remove -alpha off "$FLAT/$(basename "$f")"; done
RAW_IN="$RAW"; RAW="$FLAT"

# Per scene: A | B side by side with their names above, light over dark.
LABELS="$(mktemp -d)"
for pair in "a:A  Balk onderin" "b:B  Zwevende speler"; do
  magick -size 1220x64 xc:white -font /System/Library/Fonts/SFNS.ttf -pointsize 30 -fill '#5A5E70' \
    -annotate +24+44 "${pair#*:}" "$LABELS/${pair%%:*}.png"
done
for scene in 1-home 2-nummers 3-wachtrij 4-verbinden 5-speelt-nu; do
  ffmpeg -nostdin -loglevel error -y -i "$LABELS/a.png" -i "$LABELS/b.png" \
    -i "$RAW/a-$scene-licht.png" -i "$RAW/b-$scene-licht.png" -i "$RAW/a-$scene-donker.png" -i "$RAW/b-$scene-donker.png" \
    -filter_complex "[0][1]hstack=2[labels];\
[2]scale=1180:-1,pad=1220:ih+20:20:0:color=white[a];[3]scale=1180:-1,pad=1220:ih+20:20:0:color=white[b];\
[4]scale=1180:-1,pad=1220:ih+20:20:0:color=white[c];[5]scale=1180:-1,pad=1220:ih+20:20:0:color=white[d];\
[a][b]hstack=2[top];[c][d]hstack=2[bottom];[labels][top][bottom]vstack=3" \
    "$OUT/$scene.png"
done
rm -rf "$LABELS"
# Settings, menu bar and search: light over dark, at half the Retina size.
ffmpeg -nostdin -loglevel error -y \
  -i "$RAW/x-instellingen-algemeen-licht.png" -i "$RAW/x-instellingen-bronnen-licht.png" -i "$RAW/x-menubalk-licht.png" \
  -i "$RAW/x-instellingen-algemeen-donker.png" -i "$RAW/x-instellingen-bronnen-donker.png" -i "$RAW/x-menubalk-donker.png" \
  -filter_complex "[0]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[a];[1]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[b];[2]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[c];\
[3]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[d];[4]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[e];[5]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[f];\
[a][b][c]hstack=3[top];[d][e][f]hstack=3[bottom];[top][bottom]vstack" \
  "$OUT/6-instellingen-en-menubalk.png"
rm -rf "$FLAT"; RAW="$RAW_IN"
echo "$OUT"

#!/usr/bin/env bash
# Real screenshots of every screen, light and dark, plus sheets with light and dark side by side.
#   scripts/capture-all.sh [out-dir]      (default design/ronde-3)
# Only the app's own windows are captured (screencapture -l); an open popover is taken from the window's own
# rectangle of the screen and cut to the window's shape. Nothing else of the screen ends up in a picture.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-design/ronde-3}"
RAW="$OUT/los"
mkdir -p "$RAW"
[ -n "${NOBUILD:-}" ] || ./scripts/build-app.sh >/dev/null

scenes() {   # $1 = licht|donker
  local s="$1"
  echo "page:home,wait:1.4,shot:1-home-$s,page:liked,wait:1.2,shot:2-vind-ik-leuk-$s,page:album:2,wait:1.2,shot:3-album-$s,\
page:home,queue:1,wait:1.4,shot:4-wachtrij-$s,queue:0,wait:0.8,devices:1,wait:1.4,shot:5-verbinden-$s,devices:0,wait:0.8,\
full:1,wait:1.6,shot:6-speelt-nu-$s,full:0,wait:0.8,search:blue,wait:1.2,shot:7-zoeken-$s,search:,page:search,wait:1,shot:8-bladeren-$s,page:home,\
settings:general,settingsshot:x-instellingen-algemeen-$s,settings:sources,wait:0.8,settingsshot:x-instellingen-bronnen-$s,closesettings,\
stage:x-menubalk-$s"
}
[ -n "${COMPOSE_ONLY:-}" ] || ./scripts/run.sh "$RAW" "$(scenes licht),appearance:dark,wait:1,$(scenes donker),quit" PP_APPEARANCE=light
rm -f "$RAW"/*-region.png

# The window pictures have see-through rounded corners; put them on white first, or they turn black when combined.
FLAT="$(mktemp -d)"
for f in "$RAW"/*.png; do magick -quiet "$f" -background white -alpha remove -alpha off "$FLAT/$(basename "$f")"; done
# Per screen: light and dark side by side.
for scene in 1-home 2-vind-ik-leuk 3-album 4-wachtrij 5-verbinden 6-speelt-nu 7-zoeken 8-bladeren; do
  ffmpeg -nostdin -loglevel error -y -i "$FLAT/$scene-licht.png" -i "$FLAT/$scene-donker.png" \
    -filter_complex "[0]scale=1180:-1,pad=1220:ih+40:20:20:color=white[a];[1]scale=1180:-1,pad=1220:ih+40:20:20:color=white[b];[a][b]hstack=2" \
    "$OUT/$scene.png"
done
ffmpeg -nostdin -loglevel error -y \
  -i "$FLAT/x-instellingen-algemeen-licht.png" -i "$FLAT/x-instellingen-bronnen-licht.png" -i "$FLAT/x-menubalk-licht.png" \
  -i "$FLAT/x-instellingen-algemeen-donker.png" -i "$FLAT/x-instellingen-bronnen-donker.png" -i "$FLAT/x-menubalk-donker.png" \
  -filter_complex "[0]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[a];[1]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[b];[2]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[c];\
[3]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[d];[4]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[e];[5]scale=iw/2:-1,pad=iw+40:700:20:20:color=white[f];\
[a][b][c]hstack=3[top];[d][e][f]hstack=3[bottom];[top][bottom]vstack" \
  "$OUT/9-instellingen-en-menubalk.png"
rm -rf "$FLAT"
echo "$OUT"

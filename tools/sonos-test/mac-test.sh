#!/usr/bin/env bash
# The Mac on the fake Sonos household of the Android repo (three rooms on 127.0.0.1:1400 to 1402, no SSDP).
# Needs the fake Navidrome on 127.0.0.1:4533 and a built dist app (scripts/build-app.sh).
#   tools/sonos-test/mac-test.sh <out-dir>     (FAKE_SONOS=<path to fake_sonos.py>, default the Android repo next door)
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$1"; mkdir -p "$OUT"; rm -f "$OUT/sonos.txt" "$OUT/fake.log" "$OUT/speaker-states.txt"
FAKE="${FAKE_SONOS:-../broncode-oss/tools/sonos-test/fake_sonos.py}"
mkdir -p "$OUT/fake"; cp "$FAKE" "$OUT/fake/fake_sonos.py"
python3 -I "$OUT/fake/fake_sonos.py" "$OUT/fake.log" >"$OUT/fake.out" 2>&1 &
FAKEPID=$!
trap 'kill $FAKEPID 2>/dev/null || true' EXIT
sleep 1
speaker() { curl -s "http://127.0.0.1:1400/debug/$1"; }
# Waits for a marker the app writes, notes what the speakers say, then does something on the speakers.
on() {
  for _ in $(seq 1 240); do grep -q "^$1	" "$OUT/sonos.txt" 2>/dev/null && break; sleep 0.25; done
  echo "$1: $(speaker state | python3 -c 'import json,sys
d=json.load(sys.stdin); sp=d if isinstance(d,list) else d.get("speakers",d)
print(json.dumps(sp)[:900])')" >>"$OUT/speaker-states.txt"
  [ -n "${2:-}" ] && speaker "$2" >/dev/null
  return 0
}
( on connected; on afternext; on paused; on resumed; on afterseek; on volume; on grouped; on ungrouped skip; on afterspeakerskip; on mac ) &
WATCH=$!
SCRIPT="wait:6,playsong:Lighthouse,wait:2,sonos:Living room,wait:5,sonosstate:connected"
SCRIPT+=",next,wait:3,sonosstate:afternext,pause,wait:2,sonosstate:paused,resume,wait:3,sonosstate:resumed"
SCRIPT+=",seek:60,wait:3,sonosstate:afterseek,groupvolume:40,wait:2,sonosstate:volume"
SCRIPT+=",sonos:Kitchen,wait:4,sonosstate:grouped,devices:1,wait:2,shot:sonos-connect,devices:0,wait:0.5"
SCRIPT+=",sonosoff:Kitchen,wait:3,sonosstate:ungrouped,wait:5,sonosstate:afterspeakerskip,sonosmac,wait:3,sonosstate:mac,quit"
scripts/run.sh "$OUT" "$SCRIPT" PP_LIVE_SERVER=http://127.0.0.1:4533 PP_SONOS_HOSTS=127.0.0.1:1400 ${PP_MUSIC_FOLDER:+PP_MUSIC_FOLDER=$PP_MUSIC_FOLDER}
wait $WATCH 2>/dev/null || true
cat "$OUT/sonos.txt"; echo; cat "$OUT/speaker-states.txt"
echo; echo "faults: $(grep -c '"fault"' "$OUT/fake.log" || true)"; grep '"fault"' "$OUT/fake.log" | head -5

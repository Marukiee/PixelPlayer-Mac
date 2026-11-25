#!/usr/bin/env bash
# The Mac as controller against the fake phone, over TCP. Needs the fake Navidrome on 127.0.0.1:4533 and a built
# dist app (scripts/build-app.sh). Optional: PP_MUSIC_FOLDER for local songs.
#   tools/remote-test/mac-test.sh <out-dir> [main|edge]
# main: queue, following the phone, seek, pause, volume, queue edits, reconnect, a song missing on the phone.
# edge: no song on the phone, the phone playing something else, the phone ending the session.
set -euo pipefail
cd "$(dirname "$0")/../.."
OUT="$1"; SCENARIO="${2:-main}"; mkdir -p "$OUT"; rm -f "$OUT/remote.txt" "$OUT/phone.log" "$OUT/phone-states.txt"
PORT=47123
MISSING="Velvet"; [ "$SCENARIO" = edge ] && MISSING="a,e,i,o,u"
FAKE_MISSING="$MISSING" python3 tools/remote-test/fake_phone.py $PORT "$OUT/phone.log" >"$OUT/fake.out" 2>&1 &
FAKE=$!
trap 'kill $FAKE 2>/dev/null || true' EXIT
sleep 0.5
ctl() { python3 -c "import socket,sys;s=socket.create_connection(('127.0.0.1',$((PORT+1))));s.sendall(sys.argv[1].encode());print(s.makefile().read(),end='')" "$1"; }
# Waits for a marker the app writes, then tells the fake phone what happens on the phone.
on() {
  for _ in $(seq 1 240); do grep -q "^$1	" "$OUT/remote.txt" 2>/dev/null && break; sleep 0.25; done
  echo "$1: phone $(ctl state)" >>"$OUT/phone-states.txt"
  [ -n "${2:-}" ] && ctl "$2" >/dev/null
  return 0
}
if [ "$SCENARIO" = edge ]; then
  ( on nonefound foreign; on afterforeign; on again bye; on afterbye ) &
  WATCH=$!
  SCRIPT="wait:6,playsong:Lighthouse,wait:2,phone:Fake Phone,wait:3,remotestate:nonefound,wait:3,remotestate:afterforeign"
  SCRIPT+=",phone:Fake Phone,wait:3,remotestate:again,wait:3,remotestate:afterbye,quit"
else
  (
    on connected; on afternext skip; on afterskip; on afterseek; on paused "drift 10000"; on afterdrift
    on queued back; on afterback; on gosilent silent; on afterreconnect; on missing; on off
  ) &
  WATCH=$!
  SCRIPT="wait:6,playsong:Lighthouse,wait:2,phone:Fake Phone,wait:3,remotestate:connected"
  SCRIPT+=",next,wait:2,remotestate:afternext,wait:4,remotestate:afterskip"
  SCRIPT+=",seek:60,wait:2,remotestate:afterseek,pause,wait:2,remotestate:paused,wait:4,remotestate:afterdrift"
  SCRIPT+=",resume,wait:1,volume:30,wait:2,playnext:Kitchen Radio,wait:2,remotestate:queued,wait:4,remotestate:afterback"
  SCRIPT+=",remotestate:gosilent,wait:16,remotestate:afterreconnect"
  SCRIPT+=",playsong:Velvet Room,wait:4,remotestate:missing,phone:off,wait:1.5,remotestate:off,quit"
fi
scripts/run.sh "$OUT" "$SCRIPT" PP_LIVE_SERVER=http://127.0.0.1:4533 "PP_REMOTE_TCP=127.0.0.1:$PORT Fake Phone" ${PP_MUSIC_FOLDER:+PP_MUSIC_FOLDER=$PP_MUSIC_FOLDER}
wait $WATCH 2>/dev/null || true
ctl report >"$OUT/report.txt"
cat "$OUT/remote.txt"; echo; cat "$OUT/phone-states.txt"; echo; cat "$OUT/report.txt"

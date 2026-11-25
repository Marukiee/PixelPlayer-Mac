#!/usr/bin/env python3
"""A fake phone in the remote player role (Android spec section 6), for testing the Mac as controller.

    python3 tools/remote-test/fake_phone.py [port] [log]

Listens on 127.0.0.1:<port> (default 47123) for the Mac and on <port+1> for test commands, one per line:
  skip        the song ends and the next one starts, as an auto-advance
  back        the phone goes to the previous song (someone used the phone)
  drift <ms>  the phone's position jumps ahead
  pause       someone paused on the phone
  foreign     the phone starts playing something that is not in the queue
  silent      stop answering (the Mac should give up after 8 s and reconnect)
  bye         the phone ends the session
  report      print the checks so far
Songs whose title contains a word from FAKE_MISSING (comma separated) are "not on this phone".
Every message is logged as a JSON line. The checks are printed on exit and by `report`.
"""
import json, os, socket, sys, threading, time

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 47123
LOG = open(sys.argv[2] if len(sys.argv) > 2 else os.devnull, "a")
MISSING = [w.strip().lower() for w in os.environ.get("FAKE_MISSING", "").split(",") if w.strip()]

lock = threading.RLock()
conn = None
silent = False
st = dict(qid=0, items=[], index=-1, pos=0.0, play=False, vol=50, repeat=0, foreign=False)
last_tick = time.time()
problems, facts = [], []
seen = dict(hello_session=None, queues=0, pings=[], qids=[], phone_moved_to=None, phone_moved_at=0.0)


def log(kind, obj):
    LOG.write(json.dumps({"t": round(time.time(), 3), "kind": kind, "msg": obj}) + "\n")
    LOG.flush()


def send(obj):
    global conn
    if conn is None or silent:
        return
    try:
        conn.sendall((json.dumps(obj) + "\n").encode())
        log("out", obj)
    except OSError:
        pass


def found(item):
    return not any(w in item.get("ti", "").lower() for w in MISSING)


def advance_clock():
    global last_tick
    now = time.time()
    if st["play"] and st["index"] >= 0 and not st["foreign"]:
        st["pos"] += (now - last_tick) * 1000
        dur = st["items"][st["index"]].get("d", 0)
        if dur > 0 and st["pos"] >= dur:
            next_song(auto=True)
    last_tick = now


def next_song(auto=False):
    items = st["items"]
    i = st["index"] + 1
    while i < len(items) and not found(items[i]):
        i += 1
    if i >= len(items):
        if st["repeat"] == 2 and items:
            i = 0
        else:
            st["play"] = False
            st["pos"] = items[st["index"]].get("d", 0) if items else 0
            return
    st["index"], st["pos"] = i, 0.0
    seen["phone_moved_to"], seen["phone_moved_at"] = items[i]["id"], time.time()


def state():
    advance_clock()
    item = st["items"][st["index"]] if 0 <= st["index"] < len(st["items"]) else None
    send({"t": "state", "qid": st["qid"], "id": None if st["foreign"] or item is None else item["id"], "foreign": st["foreign"],
          "pos": int(st["pos"]), "dur": item.get("d", 0) if item else 0, "play": st["play"], "playing": st["play"] and item is not None,
          "vol": st["vol"], "steps": 15})


def check_queue(msg):
    items, index = msg.get("items", []), msg.get("index", 0)
    seen["queues"] += 1
    if index > 20:
        problems.append(f"queue sends {index} songs before the current one (max 20)")
    if len(items) - index > 301:
        problems.append(f"queue sends {len(items) - index - 1} songs ahead (max 300)")
    empty = [it["ti"] for it in items if not it.get("p")]
    if empty:
        problems.append(f"{len(empty)} items without a path tail, e.g. {empty[0]!r}")
    deep = [it["p"] for it in items if it.get("p", "").count("/") > 2]
    if deep:
        problems.append(f"path tail longer than 3 parts: {deep[0]!r}")
    if seen["qids"] and msg["qid"] <= seen["qids"][-1]:
        problems.append(f"qid went down or stayed: {seen['qids'][-1]} then {msg['qid']}")
    seen["qids"].append(msg["qid"])
    # Pulled back: the phone moved on by itself in the last 3 s, and the Mac sends the old song as current.
    moved = seen["phone_moved_to"]
    if moved and time.time() - seen["phone_moved_at"] < 3 and 0 <= index < len(items) and items[index]["id"] != moved:
        problems.append(f"Mac pulled the phone back from {moved} to {items[index]['id']}")


def handle(msg):
    t = msg.get("t")
    with lock:
        advance_clock()
        if t == "hello":
            if seen["hello_session"] is None:
                seen["hello_session"] = msg.get("session")
            send({"t": "hello", "v": 1, "name": "Fake Phone", "role": "player"})
            state()
        elif t == "queue":
            check_queue(msg)
            items = msg.get("items", [])
            missing = [it["id"] for it in items if not found(it)]
            st["foreign"] = False
            if len(missing) == len(items):
                st["play"] = False
                st["qid"] = msg["qid"]
                send({"t": "queued", "qid": msg["qid"], "missing": missing, "found": 0})
                state()
                return
            want = msg.get("index", 0)
            start = next((i for i in range(want, len(items)) if found(items[i])), None)
            play = msg.get("play", False)
            if start is None:
                start = max(i for i in range(len(items)) if found(items[i]))
                play = False
            old = st["items"][st["index"]]["id"] if 0 <= st["index"] < len(st["items"]) else None
            same = old == items[start]["id"]
            st.update(qid=msg["qid"], items=items, index=start, repeat=msg.get("repeat", 0), play=play)
            if not same or abs(st["pos"] - msg.get("pos", 0)) > 3000:
                st["pos"] = float(msg.get("pos", 0)) if start == want else 0.0
            send({"t": "queued", "qid": msg["qid"], "missing": missing, "found": len(items) - len(missing)})
            state()
        elif t == "jump":
            if msg.get("qid") == st["qid"]:
                ids = [i for i, it in enumerate(st["items"]) if it["id"] == msg.get("id")]
                if ids:
                    st["index"] = min(ids, key=lambda i: abs(i - msg.get("index", 0)))
                    st["pos"], st["play"] = float(msg.get("pos", 0)), msg.get("play", False)
            state()
        elif t == "play":
            st["play"] = True
            state()
        elif t == "pause":
            st["play"] = False
            state()
        elif t == "seek":
            st["pos"] = float(msg.get("pos", 0))
            state()
        elif t == "volume":
            st["vol"] = int(msg.get("v", 0))
            state()
        elif t == "ping":
            seen["pings"].append(time.time())
            state()
        elif t == "bye":
            facts.append("Mac said bye")


def mac_loop():
    global conn, silent
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", PORT))
    server.listen(4)
    while True:
        c, _ = server.accept()
        c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        with lock:
            if conn is not None:
                # A new link replaces the old one, as on the phone.
                send({"t": "bye"})
                conn.close()
            conn, silent = c, False
            seen["pings"] = []
            facts.append(f"connection at {time.strftime('%H:%M:%S')}")
        buf = b""
        while True:
            try:
                data = c.recv(65536)
            except OSError:
                break
            if not data:
                break
            buf += data
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                if not line.strip():
                    continue
                try:
                    msg = json.loads(line)
                except ValueError:
                    continue
                log("in", msg)
                if not silent:
                    handle(msg)
        with lock:
            if conn is c:
                conn = None
                facts.append(f"Mac closed at {time.strftime('%H:%M:%S')}")


def ticker():
    while True:
        time.sleep(1)
        with lock:
            if conn is not None:
                state()


def report():
    gaps = [b - a for a, b in zip(seen["pings"], seen["pings"][1:])]
    lines = [f"hello session: {seen['hello_session']}", f"queues: {seen['queues']}",
             f"largest ping gap: {max(gaps):.2f} s" if gaps else "pings: none yet",
             f"now: index {st['index']} of {len(st['items'])}, pos {int(st['pos'])} ms, play {st['play']}, vol {st['vol']}"]
    if seen["hello_session"] is False:
        problems.append("first hello had session false")
    if gaps and max(gaps) > 2.5:
        problems.append(f"ping gap {max(gaps):.2f} s (over 2.5)")
    lines += facts
    lines += [f"PROBLEM: {p}" for p in dict.fromkeys(problems)] or ["no problems"]
    return "\n".join(lines)


def control_loop():
    global silent
    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", PORT + 1))
    server.listen(4)
    while True:
        c, _ = server.accept()
        cmd = c.recv(1024).decode().strip().split()
        out = "ok"
        with lock:
            advance_clock()
            if not cmd:
                pass
            elif cmd[0] == "skip":
                next_song(auto=True)
                state()
            elif cmd[0] == "back":
                if st["index"] > 0:
                    st["index"] -= 1
                    st["pos"] = 0.0
                    seen["phone_moved_to"], seen["phone_moved_at"] = st["items"][st["index"]]["id"], time.time()
                state()
            elif cmd[0] == "drift":
                st["pos"] += int(cmd[1]) if len(cmd) > 1 else 5000
                state()
            elif cmd[0] == "pause":
                st["play"] = False
                state()
            elif cmd[0] == "foreign":
                st["foreign"] = True
                state()
            elif cmd[0] == "silent":
                silent = True
            elif cmd[0] == "bye":
                send({"t": "bye"})
            elif cmd[0] == "state":
                item = st["items"][st["index"]] if 0 <= st["index"] < len(st["items"]) else {}
                out = json.dumps({"id": item.get("id"), "title": item.get("ti"), "tail": item.get("p"), "index": st["index"],
                                  "count": len(st["items"]), "pos": int(st["pos"]), "play": st["play"], "vol": st["vol"],
                                  "repeat": st["repeat"], "qid": st["qid"]})
            elif cmd[0] == "report":
                out = report()
        c.sendall((out + "\n").encode())
        c.close()


threading.Thread(target=ticker, daemon=True).start()
threading.Thread(target=control_loop, daemon=True).start()
print(f"fake phone on 127.0.0.1:{PORT}, commands on {PORT + 1}", flush=True)
try:
    mac_loop()
except KeyboardInterrupt:
    print(report())

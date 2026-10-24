#!/usr/bin/env python3
"""Checks the new game's host port (p4.2) end to end, on this PC.

It starts a test server (ws, no TLS) with the host port, two fake players
(tools/v2_synth.py) and a headless person named Kid (bench/tools/play_probe.gd),
then drives every host command over http and checks the answers and the game:
the lobby settings, a match started by the host, bots added in a match (they
come at the next round), a kick (Kid goes back to watching), the players'
numbers against the server's own [KILL] and [ROUND] lines, the end of a match,
bad requests, a request that arrives in two pieces, and the numbers coming
back after a restart. Exit 1 on any FAIL.

    ./venv/bin/python tools/v2_host_check.py [--port 8097] [--host-port 8098] [--out DIR]
"""
import argparse
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILS = []


def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what, flush=True)
    if not ok:
        FAILS.append(what)
    return ok


def call(base, path, body=None):
    """GET (body None) or POST json; returns (http code, reply dict)."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, method="GET" if body is None else "POST",
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def wait_for(base, test, seconds, what):
    end = time.time() + seconds
    st = None
    while time.time() < end:
        try:
            st = call(base, "/state")[1]
            if test(st):
                return st
        except (OSError, ValueError):
            pass
        time.sleep(0.25)
    check(False, f"{what} (waited {seconds} s)")
    return st


def start_server(out, port, host_port, log):
    cmd = ["godot", "--headless", "--path", os.path.join(ROOT, "bench"), "res://server/game_server.tscn", "--",
           "--no-tls", "--port", str(port), "--admin-port", str(host_port), "--bots", "3", "--goal", "99",
           "--walls-s", "8", "--out", out, "--quiet"]
    return subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)


def stop(p):
    if p and p.poll() is None:
        os.killpg(p.pid, signal.SIGTERM)
        try:
            p.wait(10)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)


def in_round(st):
    return sum(1 for s in st["seats"] if s["in_round"])


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--port", type=int, default=8097)
    ap.add_argument("--host-port", type=int, default=8098)
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    out = a.out or tempfile.mkdtemp(prefix="v2_host_check_")
    os.makedirs(out, exist_ok=True)
    done = False
    base = f"http://127.0.0.1:{a.host_port}"
    server_log_path = os.path.join(out, "server.log")
    procs = []
    try:
        server_log = open(server_log_path, "w")
        server = start_server(out, a.port, a.host_port, server_log)
        procs.append(server)
        st = wait_for(base, lambda s: s.get("ok"), 60, "the host port answers")
        if not st:
            return
        with open(os.path.join(ROOT, "bench", "sim", "proto.gd")) as f:
            version = re.search(r'const VERSION := "([^"]+)"', f.read()).group(1)
        check(st["version"] == version and st["phase_name"] == "LOBBY" and len(st["seats"]) == 8,
              f"GET /state: version {st['version']}, phase {st['phase_name']}, {len(st['seats'])} seats")
        probe_log = open(os.path.join(out, "probe.log"), "w")
        procs.append(subprocess.Popen(
            [sys.executable, os.path.join(ROOT, "tools", "v2_synth.py"), "--url", f"ws://127.0.0.1:{a.port}",
             "--n", "2", "--seconds", "240", "--out", out], stdout=open(os.path.join(out, "synth.log"), "w"),
            stderr=subprocess.STDOUT, start_new_session=True))
        procs.append(subprocess.Popen(
            ["godot", "--headless", "--path", os.path.join(ROOT, "bench"), "--script", "res://tools/play_probe.gd", "--",
             f"--server=ws://127.0.0.1:{a.port}", "--name=Kid", "--watch=240"],
            stdout=probe_log, stderr=subprocess.STDOUT, start_new_session=True))
        st = wait_for(base, lambda s: s["people"] == 3, 60, "3 people seated (2 fakes + Kid)")
        if not st:
            return
        check(all(s["ip"] == "127.0.0.1" and s["client"] > 0 for s in st["seats"] if s["who"] == "person"),
              "each person has an address and a client")

        # the lobby
        code, r = call(base, "/bots", {"n": 0})
        check(code == 200 and r["ok"] and r["state"]["bots_wanted"] == 0 and r["state"]["bots_now"] == 0,
              f"POST /bots 0 in the lobby: {r.get('text')}")
        code, r = call(base, "/bots", {"n": 2})
        check(code == 200 and r["state"]["bots_wanted"] == 2 and r["state"]["bots_now"] == 2, "POST /bots 2")
        code, r = call(base, "/bot_level", {"n": 3})
        check(code == 200 and r["state"]["bot_level_name"] == "HARD", f"POST /bot_level 3: {r.get('text')}")
        code, r = call(base, "/bot_level", {"n": 9})
        check(code == 400 and not r["ok"], f"POST /bot_level 9 refused: {r.get('text')}")
        code, r = call(base, "/arena", {"n": 2})
        check(code == 200 and r["state"]["arena_pick"] == 2 and r["state"]["arena_now"] == 2,
              f"POST /arena 2 in the lobby: {r.get('text')} (now {r['state']['arena_now_name']})")
        code, r = call(base, "/arena", {"n": 7})
        check(code == 400, f"POST /arena 7 refused: {r.get('text')}")
        code, r = call(base, "/stop", {})
        check(code == 400, f"POST /stop in the lobby refused: {r.get('text')}")
        code, r = call(base, "/power", {"n": 1})
        check(code == 200 and r["state"]["power_arrows"] is True, f"POST /power 1: {r.get('text')}")
        code, r = call(base, "/power", {"n": 0})
        check(code == 200 and r["state"]["power_arrows"] is False, f"POST /power 0: {r.get('text')}")

        # a match
        code, r = call(base, "/start", {})
        check(code == 200 and r["state"]["phase_name"] == "COUNTDOWN", f"POST /start: {r.get('text')}")
        code, r = call(base, "/start", {})
        check(code == 400, f"POST /start again refused: {r.get('text')}")
        st = wait_for(base, lambda s: s["phase_name"] == "PLAYING" and s["round"] == 1, 15, "round 1 is on")
        if st:
            check(in_round(st) == 5 and st["arena_now"] == 2,
                  f"round 1: {in_round(st)} fighters (3 people + 2 bots), arena {st['arena_now_name']}")
        code, r = call(base, "/bots", {"n": 4})
        check(code == 200 and "next round" in r["text"] and in_round(r["state"]) == 5,
              f"POST /bots 4 in round 1: {r['text']} (still {in_round(r['state'])} fighting)")
        st = wait_for(base, lambda s: s["round"] >= 2 and s["phase_name"] == "PLAYING", 60, "round 2 is on")
        if st:
            check(in_round(st) == 7 and st["bots_now"] == 4,
                  f"round 2: {in_round(st)} fighters (3 people + 4 bots)")

        # the kick
        kid = next((s for s in st["seats"] if s["name"] == "Kid"), None) if st else None
        if check(kid is not None, "Kid has a seat"):
            code, r = call(base, "/kick", {"seat": kid["i"]})
            seat_after = r["state"]["seats"][kid["i"]]
            watching = [w["name"] for w in r["state"]["watching"]]
            check(code == 200 and seat_after["who"] != "person" and "Kid" in watching,
                  f"POST /kick seat {kid['i']}: {r.get('text')} (the seat is {seat_after['who']}, watching: {watching})")
            bot = next((s for s in r["state"]["seats"] if s["who"] == "bot"), None)
            code, r = call(base, "/kick", {"seat": bot["i"] if bot else 7})
            check(code == 400, f"POST /kick on a bot's seat refused: {r.get('text')}")

        st = wait_for(base, lambda s: s["round"] >= 4, 150, "round 4")
        code, r = call(base, "/stop", {})
        check(code == 200 and r["state"]["phase_name"] == "LOBBY", f"POST /stop in a match: {r.get('text')}")
        time.sleep(1.0)
        st = call(base, "/state")[1]
        tags = [e["tag"] for e in st["events"]]
        check("HOST" in tags and "JOIN" in tags and len(st["events"]) <= 80,
              f"events: {len(st['events'])} kept, tags {sorted(set(tags))}")

        # the players' numbers against the server's own lines
        time.sleep(0.5)
        server_log.flush()
        text = open(server_log_path, encoding="utf-8", errors="replace").read()
        kills, deaths, selfk, wins, causes = {}, {}, {}, {}, {}
        for m in re.finditer(r"\[KILL\] seat \d+ '([^']*)' killed seat \d+ '([^']*)' \((\w[\w ]*)\)", text):
            if m.group(1):
                kills[m.group(1)] = kills.get(m.group(1), 0) + 1
                causes.setdefault(m.group(1), {}).setdefault(m.group(3), 0)
                causes[m.group(1)][m.group(3)] += 1
            if m.group(2):
                deaths[m.group(2)] = deaths.get(m.group(2), 0) + 1
        for m in re.finditer(r"\[KILL\] seat \d+ '([^']*)' (killed themselves|died) ", text):
            if m.group(1):
                deaths[m.group(1)] = deaths.get(m.group(1), 0) + 1
                if m.group(2) == "killed themselves":
                    selfk[m.group(1)] = selfk.get(m.group(1), 0) + 1
        for m in re.finditer(r"\[ROUND\] \d+ end after [\d.]+ s: seat \d+ '([^']*)' is the last one standing", text):
            if m.group(1):
                wins[m.group(1)] = wins.get(m.group(1), 0) + 1
        got = {}
        for p in st["stats"]:
            g = got.setdefault(p["name"], {"kills": 0, "deaths": 0, "self": 0, "wins": 0, "arrow": 0, "stomp": 0})
            g["kills"] += p["kills"]
            g["deaths"] += p["deaths"]
            g["self"] += p["self_kills"]
            g["wins"] += p["round_wins"]
            g["arrow"] += p["arrow_kills"]
            g["stomp"] += p["stomp_kills"]
        names = sorted(set(got) | set(kills) | set(deaths))
        bad = [n for n in names if got.get(n, {}).get("kills", 0) != kills.get(n, 0)
               or got.get(n, {}).get("deaths", 0) != deaths.get(n, 0)
               or got.get(n, {}).get("self", 0) != selfk.get(n, 0)
               or got.get(n, {}).get("wins", 0) != wins.get(n, 0)
               or got.get(n, {}).get("arrow", 0) != causes.get(n, {}).get("arrow", 0)
               or got.get(n, {}).get("stomp", 0) != causes.get(n, {}).get("stomp", 0)]
        check(not bad and sum(kills.values()) > 0,
              f"stats match the [KILL] and [ROUND] lines for {len(names)} players: {sum(kills.values())} kills, "
              f"{sum(deaths.values())} deaths, {sum(wins.values())} round wins" + (f"; differ: {bad}" if bad else ""))
        people = [p for p in st["stats"] if not p["bot"]]
        check(any(p["name"] == "Kid" and p["matches"] == 1 for p in people) and all(p["matches"] == 1 and p["shots"] >= p["arrow_kills"]
                                                              for p in st["stats"]),
              f"each player played 1 match (Kid too, kicked and back) and has at least as many shots as arrow kills ({sum(p['shots'] for p in st['stats'])} shots, "
              f"{sum(p['catches'] for p in st['stats'])} catches)")
        rounds = [json.loads(l) for l in open(os.path.join(out, time.strftime("%Y-%m-%d"), "v2_server.jsonl"))
                  if '"kind":"round"' in l]
        check(rounds and all(len(r.get("names", [])) == 8 for r in rounds), f"the round lines carry the seat names ({len(rounds)} rounds)")
        probe_text = open(os.path.join(out, "probe.log"), encoding="utf-8", errors="replace").read()
        check("The host took your seat" in probe_text and "welcome: seat -1" in probe_text,
              "Kid's page got the note and went back to watching")

        # bad requests
        code, r = call(base, "/nope")
        check(code == 404, "GET /nope: 404")
        code, r = call(base, "/nope", {})
        check(code == 404, f"POST /nope: 404 ({r.get('text')})")
        s = socket.create_connection(("127.0.0.1", a.host_port), 5)
        body = json.dumps({"n": 5}).encode()
        s.sendall(b"POST /bots HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: %d\r\n\r\n" % len(body))
        time.sleep(0.3)
        s.sendall(body)
        reply = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            reply += chunk
        s.close()
        check(reply.startswith(b"HTTP/1.1 200") and json.loads(reply.split(b"\r\n\r\n", 1)[1])["state"]["bots_wanted"] == 5,
              "a request in two pieces (the body 0.3 s after the head) is answered")
        t0 = time.time()
        codes = [call(base, "/state")[0] for _ in range(30)]
        check(all(c == 200 for c in codes), f"30 GET /state in a row: all 200, {1000 * (time.time() - t0) / 30:.1f} ms each")

        # tonight's numbers survive a restart
        before = {(p["name"], p["bot"]): (p["kills"], p["deaths"], p["shots"]) for p in st["stats"]}
        since = st["stats_since"]
        for p in procs[1:]:
            stop(p)
        stop(server)
        server_log.close()
        server_log = open(os.path.join(out, "server2.log"), "w")
        server = start_server(out, a.port, a.host_port, server_log)
        procs = [server]
        st = wait_for(base, lambda s: s.get("ok"), 60, "the host port answers after a restart")
        if st:
            after = {(p["name"], p["bot"]): (p["kills"], p["deaths"], p["shots"]) for p in st["stats"]}
            check(after == before and abs(st["stats_since"] - since) < 1,
                  f"after a restart the numbers are back ({len(after)} players)")
        done = True
    finally:
        for p in procs:
            stop(p)
        print(f"out: {out}")
        if not done:
            FAILS.append("the check stopped early")
        print("ALL PASS" if not FAILS else f"{len(FAILS)} FAIL: " + "; ".join(FAILS), flush=True)
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()

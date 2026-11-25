#!/usr/bin/env python3
# ==============================================================================
# The seat bugs of the November review (docs/reference/game-review-2026-11.md), each
# with a fixed script on a test server of its own. Fake players (tools/v2_chaos.py's
# Client) do the exact thing that went wrong on the October nights, and the check says
# PASS or FAIL with the numbers. Bugs 1, 2 (the server's half), 3, 5, 9 and 12.
#
#   ./venv/bin/python tools/v2_seat_check.py [--only S1,S4] [--port 8111] [--admin-port 8121] [--out DIR]
#   --bench DIR: run the server from another copy of bench/ (an older commit, to see
#   the bug: a check that fails there and passes here is a proof).
#   S5 waits for the 60 s hold to run out: about 80 s. The whole run: about 4 minutes.
# Exit 1 on any FAIL.
# ==============================================================================
import argparse, os, sys, time, socket
import websocket
from v2_chaos import (Client, Host, Server, game_version, ROOT, PH_LOBBY, PH_PLAY, PH_ROUND_END, PH_MATCH_END,
                      E_DEATH, E_KILL, F_DEAD, F2_AWAY, OWN_FIGHTER, OWN_BRAIN, B_RIGHT)

FAILS = []
A = None          # the arguments


def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what, flush=True)
    if not ok:
        FAILS.append(what)
    return ok


def wait(test, seconds, step=0.02):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        v = test()
        if v:
            return v
        time.sleep(step)
    return test()


class Run:
    """One scenario: a server of its own, its fake players, the host port."""

    def __init__(self, name, extra):
        self.name = name
        out = os.path.join(A.out, name)
        self.server = Server(A.port, A.admin_port, out, ["--season", "off", "--no-powerups"] + extra, A.bench or None)
        self.host = Host(A.admin_port)
        self.url = f"ws://127.0.0.1:{A.port}"
        self.clients = []
        self.version = game_version() if not A.bench else _version_of(A.bench)

    def player(self, idx, mode="idle", name=None, token=None):
        c = Client(self.url, idx, self.version, name, token)
        c.mode = mode
        self.clients.append(c)
        return c

    def seat(self, c):
        """Connect, say hello, take a seat."""
        assert c.connect(), c.err
        assert wait(lambda: len(c.welcomes) >= 1, 5), "no welcome"
        if c.seat < 0:
            c.send({"kind": "join", "name": c.name})
        assert wait(lambda: c.seat >= 0, 5), "no seat"
        return c.seat

    def start(self, watcher):
        """The host starts the match; back when the first round is being played."""
        self.host.cmd("start")
        assert wait(lambda: watcher.phase() == PH_PLAY, 12), "the match never started"

    def seat_state(self, i):
        return self.host.state()["seats"][i]

    def log(self):
        with open(self.server.log_path, errors="replace") as f:
            return f.read()

    def done(self, allow=""):
        for c in self.clients:
            c.close()
        self.server.stop()
        text = self.log()
        errs = [l for l in text.splitlines() if ("SCRIPT ERROR" in l or l.startswith("ERROR")) and not (allow and allow in l)]
        check(not errs, f"{self.name}: no error in the server's output" + ("" if not errs else ": " + errs[0][:200]))
        time.sleep(0.3)


def _version_of(bench_dir):
    import re
    with open(os.path.join(bench_dir, "sim", "proto.gd")) as f:
        m = re.search(r'const VERSION := "([^"]+)"', f.read())
    return m.group(1) if m else "?"


# ---------------------------------------------------------------- bug 3: the freed seat
def s1():
    """Two people, no bots. In the round one leaves. Before: its fighter played on as a bot,
    won, the banner said ' WINS THE ROUND' with no name and the point went to an empty seat."""
    r = Run("S1", ["--bots", "0", "--arena", "bench", "--spots", "2,3"])
    try:
        a, b = r.player(0), r.player(1)
        sa, sb = r.seat(a), r.seat(b)
        r.start(b)
        time.sleep(0.5)
        t0 = time.monotonic()
        a.send({"kind": "leave"})
        got = wait(lambda: [m for m in b.msgs if m["kind"] == "round_end"], 40)
        m = got[0] if got else {}
        secs = (m.get("_t", t0) - t0) if got else -1
        check(bool(got) and not m.get("draw") and m.get("winner") == sb and m.get("name") == b.name,
              f"S1 (bug 3) a person leaves in the round: the round ends for the other one by name: round_end {secs:.2f} s later, "
              f"winner seat {m.get('winner')} '{m.get('name')}' (the other is seat {sb} '{b.name}', the leaver was seat {sa})")
        bad = []
        end = time.monotonic() + 4.0
        while time.monotonic() < end:
            for s in r.host.state()["seats"]:
                if s["kind"] == 0 and (s["points"] != 0 or s["name"] != ""):
                    bad.append((s["i"], s["name"], s["points"]))
            time.sleep(0.1)
        check(not bad, f"S1 (bug 3) no point and no name on the empty seat in the 4 s after: {len(bad)} bad looks" + (f", the first {bad[0]}" if bad else ""))
    finally:
        r.done()


def s2():
    """Two people and a bot. The host kicks one in the round: its fighter is out at once
    (before: it played on as a bot to the round's end)."""
    r = Run("S2", ["--bots", "1", "--arena", "keep", "--bot-level", "easy"])
    try:
        a, b = r.player(0), r.player(1)
        sa, sb = r.seat(a), r.seat(b)
        r.start(b)
        b.events.clear()
        t0 = time.monotonic()
        r.host.cmd("kick", seat=sa)
        dead = wait(lambda: b.snap and b.snap["fighters"].get(sa, {}).get("state") == F_DEAD, 2.0)
        secs = time.monotonic() - t0
        causes = [e[5] for e in list(b.events) if e[1] == E_DEATH and e[4] == sa]
        check(bool(dead) and causes == [12] and secs < 0.5,
              f"S2 (bug 3) the host kicks a seat in the round: its fighter is out {secs:.2f} s later, death causes seen {causes} (12: left the game)")
        st = r.seat_state(sa)
        check(st["kind"] == 0 and a.seat == -1, f"S2 the kicked seat is empty (kind {st['kind']}) and the person watches (seat {a.seat})")
    finally:
        r.done()


def s3():
    """Three people. Two leave: the third wins the round. It leaves too in the 1.5 s
    before the point: no point goes to the empty seat."""
    r = Run("S3", ["--bots", "0", "--arena", "keep"])
    try:
        a, b, c = r.player(0), r.player(1), r.player(2)
        sa, sb, sc = r.seat(a), r.seat(b), r.seat(c)
        r.start(a)
        time.sleep(0.3)
        c.send({"kind": "leave"})
        b.send({"kind": "leave"})
        got = wait(lambda: [m for m in a.msgs if m["kind"] == "round_end"], 5)
        m = got[0] if got else {}
        check(bool(got) and m.get("winner") == sa and m.get("name") == a.name, f"S3 (bug 3) two of three leave: the round is called for the third by name: '{m.get('name')}'")
        a.send({"kind": "leave"})
        time.sleep(2.5)
        seats = r.host.state()["seats"]
        pts = [s["points"] for s in seats]
        check(sum(pts) == 0 and all(s["kind"] == 0 for s in seats) and "no point: the winner's seat" in r.log(),
              f"S3 (bug 3) the winner leaves before the point: nobody has a point (points {pts}), the server says 'no point'")
    finally:
        r.done()


# ---------------------------------------------------------------- bug 1: a dropped phone keeps its seat
def s4():
    """A person with a point loses the socket in a match and is back 20 s later (the old
    hold was 8 s: 16 of 33 drops on 25 October lost the seat). The same seat, the points
    still there, with no JOIN."""
    r = Run("S4", ["--bots", "0", "--arena", "bench", "--spots", "2,3", "--goal", "40"])
    try:
        a, b = r.player(0, "brain"), r.player(1)
        sa, sb = r.seat(a), r.seat(b)
        r.start(b)

        def pts():
            m = b.seats_msg
            return m["seats"][sa]["points"] if m else 0
        ok = wait(lambda: pts() >= 1 and b.phase() == PH_PLAY, 150, 0.05)
        before = pts()
        check(bool(ok), f"S4 (setup) the fake player with a brain has a point before the drop: {before}")
        a.drop()
        time.sleep(10.0)
        mid = r.seat_state(sa)
        time.sleep(10.0)
        a.mode = "brain"
        a.connect()                                       # hello with its token; no join
        wait(lambda: len(a.welcomes) >= 1, 5)
        back = a.welcomes[-1] if a.welcomes else None
        time.sleep(0.5)
        st = r.seat_state(sa)
        check(mid["kind"] == 1 and not mid["online"], f"S4 (bug 1) 10 s after the drop the seat is still held (kind {mid['kind']}, held {mid['held_s']} s more)")
        check(back == sa and st["name"] == a.name and st["points"] >= before and st["online"],
              f"S4 (bug 1) back after 20 s, hello alone: welcome seat {back} (it was {sa}), name '{st['name']}', points {st['points']} (before the drop {before}), online {st['online']}")
        mine = wait(lambda: a.own and (a.own["flags"] & OWN_FIGHTER) and not (a.own["flags"] & OWN_BRAIN), 20, 0.05)
        check(bool(mine), "S4 (bug 1) and the person plays its fighter again (T_OWN: a fighter, no brain)")
    finally:
        r.done()


def s5():
    """The hold is 60 s in a match. When it runs out in a round, the seat goes at that
    round's end: its fighter is not taken out of the round."""
    r = Run("S5", ["--bots", "1", "--arena", "keep", "--bot-level", "easy", "--goal", "60"])
    try:
        a, b = r.player(0), r.player(1)
        sa, sb = r.seat(a), r.seat(b)
        r.start(b)
        b.events.clear()
        t0 = time.monotonic()
        a.drop()
        freed_at, phase_then = None, None
        while time.monotonic() - t0 < 130:
            st = r.host.state()
            if st["seats"][sa]["kind"] != 1 or st["seats"][sa]["name"] != a.name:    # (a bot may sit down on it at once)
                freed_at, phase_then = time.monotonic() - t0, st["phase"]
                break
            time.sleep(0.05)
        left = [e for e in list(b.events) if e[1] == E_DEATH and e[4] == sa and e[5] == 12]
        check(freed_at is not None and freed_at >= 59.5, f"S5 (bug 1) a seat dropped in a match is held 60 s: it was free again after {freed_at if freed_at is not None else -1:.1f} s")
        check(freed_at is not None and not left, f"S5 (bug 3) and its fighter was not taken out mid-round ({len(left)} 'left the game' deaths); the seat went in phase {phase_then}")
        text = r.log()
        check("its fighter played the round out" in text or "is free again" in text, "S5 the server's line says the seat is free again")
    finally:
        r.done()


# ---------------------------------------------------------------- bug 5: the silent phone, the second socket
def s6():
    """A page freezes with a button held: nothing comes, the socket stays open. Before: it
    kept its seat with the button held, round after round. Now: 3 s of silence is a drop
    (the brain plays, the seat is held), and the same token is back in its seat."""
    r = Run("S6", ["--bots", "1", "--arena", "keep", "--bot-level", "easy", "--goal", "60"])
    try:
        a, b = r.player(0, "hold"), r.player(1)
        a.hold_buttons = B_RIGHT
        sa, sb = r.seat(a), r.seat(b)
        r.start(b)
        time.sleep(0.5)
        t0 = time.monotonic()
        a.silent = True
        held = wait(lambda: not r.seat_state(sa)["online"], 8.0, 0.05)
        secs = time.monotonic() - t0
        closed = wait(lambda: a.server_closed, 2.0)
        check(bool(held) and 2.5 <= secs <= 4.5, f"S6 (bug 5) a silent socket with a button held counts as a drop after {secs:.2f} s (3 s wanted): seat online {r.seat_state(sa)['online']}")
        check(bool(closed), f"S6 (bug 5) the server closed that socket (the page will open a new one): {bool(closed)}")
        a.mode = "idle"
        a.connect()
        wait(lambda: len(a.welcomes) >= 1, 5)
        check(a.welcomes and a.welcomes[-1] == sa, f"S6 (bug 5) the same token is back in its seat: welcome {a.welcomes[-1] if a.welcomes else None} (it was {sa})")
    finally:
        r.done()


def s7():
    """The same phone on a new socket while the old one is still open (a dead Wi-Fi link
    nobody closed, or a second tab). Before: a second seat. Now: it takes its seat over."""
    r = Run("S7", ["--bots", "1", "--arena", "keep"])
    try:
        a = r.player(0)
        b = r.player(1)
        sa, sb = r.seat(a), r.seat(b)
        a2 = r.player(0)                     # the same name and token
        a2.connect()
        wait(lambda: len(a2.welcomes) >= 1, 5)
        first = a2.welcomes[-1] if a2.welcomes else None
        time.sleep(0.5)
        check(first == -1 and a.seat == sa, f"S7 (bug 5) hello alone takes nothing from a live socket (a second tab that only looks, THE BIG SCREEN): welcome {first}, the first socket keeps seat {a.seat}")
        a2.send({"kind": "join", "name": a2.name})     # JOIN (the page sends it by itself after a drop)
        wait(lambda: a2.seat >= 0, 3)
        time.sleep(0.5)
        seats = [s for s in r.host.state()["seats"] if s["kind"] == 1 and s["name"] == a.name]
        check(a2.seat == sa and len(seats) == 1 and seats[0]["i"] == sa,
              f"S7 (bug 5) join on a second socket with the same token takes its own seat over: seat {a2.seat} (it was {sa}); seats with that name: {[s['i'] for s in seats]}")
        check(a.seat == -1, f"S7 (bug 5) the old socket was told it has no seat any more: its seat reads {a.seat}")
        r.start(b)
        mine = wait(lambda: a2.own and (a2.own["flags"] & OWN_FIGHTER) and not (a2.own["flags"] & OWN_BRAIN), 8, 0.05)
        check(bool(mine), "S7 (bug 5) the new socket plays the fighter (T_OWN: a fighter, no brain)")
    finally:
        r.done()


# ---------------------------------------------------------------- bug 12: a close that cannot finish
def s8():
    """A socket whose reading side is stuck: the server cannot send to it. (a) It says
    goodbye: the server's own goodbye cannot leave, the socket hangs half closed. Before:
    8 s later it was dropped without a word to the seats, and the seat stayed 'on' for
    ever. (b) It keeps talking and never reads, until 1 MB waits for it.
    (The server has two rules now: 120 packets in a row that cannot be queued, and a
    socket half closed for 1 s. With both on, the first one catches (a) too, 2 s in. To
    see the second alone, set SEND_FAIL_MAX very high in game_server.gd for one run.)"""
    import json, struct
    for part, hellos, goodbye, words in (("a", 4000, True, ""), ("b", 4000, False, "could not be sent to")):
        r = Run("S8" + part, ["--bots", "7", "--arena", "keep"])
        try:
            b = r.player(1)
            r.seat(b)
            ws = websocket.create_connection(r.url, timeout=4, sockopt=[(socket.SOL_SOCKET, socket.SO_RCVBUF, 2048)])
            ws.send(json.dumps({"kind": "hello", "name": "Stuck", "version": r.version, "token": "stucktoken"}))
            ws.send(json.dumps({"kind": "join", "name": "Stuck"}))
            wait(lambda: next((s["i"] for s in r.host.state()["seats"] if s["name"] == "Stuck"), None) is not None, 5)
            sa = next((s["i"] for s in r.host.state()["seats"] if s["name"] == "Stuck"), -1)
            r.host.cmd("start")
            # it never reads again; it keeps talking (a ping now and then), and asks for the
            # seat list again and again: (a) about 0.7 MB waits for it, (b) about 6 MB
            try:
                for i in range(hellos):
                    ws.send(json.dumps({"kind": "hello", "name": "Stuck", "version": r.version, "token": "stucktoken"}))
                    if i % 100 == 0:
                        ws.send_binary(struct.pack("<BIHH", 3, i, 0, 0))
                t_end = time.monotonic() + (1.0 if goodbye else 2.5)
                while time.monotonic() < t_end:
                    ws.send_binary(struct.pack("<BIHH", 3, 1, 0, 0))
                    time.sleep(0.25)
                if goodbye:
                    ws.send_close()      # goodbye, and still not reading; the TCP link stays open
            except OSError:
                pass                     # (the server dropped the socket while this side was still talking)
            t0 = time.monotonic()
            gone = wait(lambda: not r.seat_state(sa)["online"], 14.0, 0.1)
            secs = time.monotonic() - t0
            st = r.seat_state(sa)
            text = r.log()
            said = words in text
            if goodbye:
                how = "hung half closed" if "hung half closed" in text else ("could not be sent to" if "could not be sent to" in text else "none of the two lines")
                check(bool(gone) and how != "none of the two lines", f"S8a (bug 12) a socket says goodbye while the server cannot send to it: its seat is 'on' no more "
                      f"{secs:.1f} s after the goodbye (online {st['online']}, ping {st['ping_ms']} ms, client {st['client']}); the server says: {how}")
            else:
                check(bool(gone) and said, f"S8b (bug 12) a socket that talks and never reads, 1 MB waiting: its seat is 'on' no more "
                      f"(online {st['online']}); the server says '{words}': {said}")
            try:
                ws.sock.close()
            except Exception:
                pass
        finally:
            # (the engine prints one line for each packet it cannot queue for that socket: that is this test's own doing)
            r.done(allow="outbound_buffer_size")


# ---------------------------------------------------------------- bug 9: the winner's screen
def replay_secs(kills):
    """The match's end montage, as client/deathcam.gd plays it (proto.gd replay_ticks)."""
    if kills <= 0:
        return 0.0
    early = min(kills, 6) - 1
    t = 0.0
    for k in range(early):
        speed = 1.6 if early == 1 else 1.0 + (3.4 - 1.0) * k / (early - 1)
        t += (1.6 + 0.35) / speed
    return t + 1.6 / 1.0 + 0.9 / 0.3 + 0.5 / 0.6 + 0.4


def s9():
    """The match ends. Before: the lobby came 12 s later whatever the replay took (0.8 s of
    winner's screen after 6 kills). Now: the replay's length plus 8 s."""
    r = Run("S9", ["--bots", "0", "--arena", "bench", "--spots", "2,3", "--goal", "3"])
    try:
        a, b = r.player(0, "brain"), r.player(1)
        sa, sb = r.seat(a), r.seat(b)
        a.events.clear()
        r.start(b)
        got = wait(lambda: [m for m in b.msgs if m["kind"] == "match_end"], 240, 0.02)
        if not check(bool(got), "S9 (setup) the match ended"):
            return
        t_end = got[0]["_t"]
        w = int(got[0]["winner"])
        kills = len({(e[0], e[5]) for e in list(a.events) if e[1] == E_KILL and e[4] == w and e[5] != w})
        wait(lambda: b.phase() == PH_LOBBY, 40, 0.01)
        secs = time.monotonic() - t_end
        want = 8.0 + replay_secs(kills)
        check(abs(secs - want) <= 0.4, f"S9 (bug 9) the match's end lasts the replay plus 8 s: the winner (seat {w}) had {kills} kills, "
              f"the replay takes {replay_secs(kills):.2f} s, the lobby came {secs:.2f} s after the end (wanted {want:.2f} s; before the fix: 12.00 s)")
    finally:
        r.done()


# ---------------------------------------------------------------- bug 2: the margin byte
def s10():
    """Inputs 200 ticks too early (a page whose clock ran ahead). T_OWN's margin is one
    signed byte and 127 means 'no input came': before, 200 was cut to 127, so the page
    never heard that it was early. Now the most it says is 126."""
    r = Run("S10", ["--bots", "1", "--arena", "keep", "--bot-level", "easy"])
    try:
        a = r.player(0)
        sa = r.seat(a)
        r.start(a)
        a.ahead = 200
        time.sleep(1.5)
        seen = set()
        end = time.monotonic() + 1.5
        while time.monotonic() < end:
            if a.own:
                seen.add(a.own["margin"])
            time.sleep(0.01)
        check(seen == {126}, f"S10 (bug 2) inputs 200 ticks early: T_OWN's margin says {sorted(seen)} (126 wanted: early; 127 would mean no input came)")
    finally:
        r.done()


def main():
    global A
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="S1,S4: only these")
    ap.add_argument("--port", type=int, default=8111)
    ap.add_argument("--admin-port", type=int, default=8121)
    ap.add_argument("--bench", default="", help="another copy of bench/ to run the server from (an older commit)")
    ap.add_argument("--out", default=os.path.join(ROOT, "bench_results", "seat_check"))
    A = ap.parse_args()
    todo = [("S1", s1), ("S2", s2), ("S3", s3), ("S4", s4), ("S5", s5), ("S6", s6), ("S7", s7), ("S8", s8), ("S9", s9), ("S10", s10)]
    only = [x.strip().upper() for x in A.only.split(",") if x.strip()]
    for name, fn in todo:
        if only and name not in only:
            continue
        try:
            fn()
        except AssertionError as e:
            check(False, f"{name} could not run: {e}")
        except Exception as e:
            check(False, f"{name} broke: {type(e).__name__}: {e}")
    print(("✅ v2_seat_check: every check passed" if not FAILS else f"❌ v2_seat_check: {len(FAILS)} FAIL"), flush=True)
    sys.exit(1 if FAILS else 0)


if __name__ == "__main__":
    main()

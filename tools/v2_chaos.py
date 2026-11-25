#!/usr/bin/env python3
# ==============================================================================
# The chaos soak for the new game's server (bench/server/game_server.gd).
# The owner asked for a soak that catches more bugs (2026-11-24, after the November
# review's 12). Fake players do at random what phones do on a bad night: join, leave,
# close the tab, lose the socket with no close, go silent with a button held, come
# back with their token, come back on a second socket while the first is still open,
# send junk. A fake host starts and stops matches, kicks, and changes the arena, the
# season, the bots and the power-ups. TEAMS (2026-11-24): fake players change sides
# (in the lobby, in a match, in the countdown: only the lobby's tap may count) and
# change the MODE, and the host flips the MODE at any time. All the while the tool checks:
#   - no SCRIPT ERROR (or any ERROR) in the server's output, and the server stays up
#   - no phase stuck (each phase has a longest time), so every round ends
#   - seats and points stay sane: an empty seat has no name and no points, no two
#     seats for one fake player, no client on two seats, points from 0 to the goal
#   - a bot keeps its seat, its name and its points through a match (looked at twice a
#     second): the same name and points on a seat that is still a bot's, and never one
#     bot gone from its seat while a new one appears on another (the bots moved)
#   - no round or match winner without a name
#   - TEAMS: every seated fighter has a team, every seat of a team shows its team's
#     points, a team's win names the team and its members, the fighters' team flags in
#     the snapshot are the seats' teams, and nobody is ever knocked out by a teammate
#   - the server's tick stays fast (its own report line every 5 s)
#
#   ./venv/bin/python tools/v2_chaos.py --spawn --port 8110 --admin-port 8120 --minutes 15 \
#       --season harvest --arena mix --bots 3 [--mode teams] [--seed 1] [--fakes 10] [--out DIR]
#   --spawn starts its own test server (ws, no TLS) and stops it by its PID at the end.
#   Without it: --url ws://host:port --admin-port N [--server-log FILE] for a server
#   that already runs (it must have --admin-port).
#   --calm: the host never stops a match and never kicks (more whole matches).
#   --bench DIR: with --spawn, the server from another copy of bench/.
#   -> a line every 30 s, a summary at the end, <out>/chaos_report.json; exit 1 on a finding.
# The same fake player (class Client) is used by tools/v2_seat_check.py, the check with
# a fixed script for each seat bug of the review.
# ==============================================================================
import argparse, collections, json, os, random, re, socket, ssl, struct, subprocess, sys, threading, time
import urllib.error, urllib.request
import websocket
from v2_synth import Synth, game_version

T_SNAP, T_INPUT, T_PING, T_PONG, T_OWN = 1, 2, 3, 4, 5
B_LEFT, B_RIGHT, B_UP, B_DOWN, B_JUMP, B_SHOOT, B_DODGE, B_CANCEL = 1, 2, 4, 8, 16, 32, 64, 128
PH_LOBBY, PH_COUNTDOWN, PH_ROUND_START, PH_PLAY, PH_ROUND_END, PH_MATCH_END = range(6)
PHASES = ["LOBBY", "COUNTDOWN", "ROUND START", "PLAYING", "ROUND END", "MATCH END"]
E_DEATH, E_KILL, E_PHEW = 9, 19, 45
F_DEAD = 2
F2_BOT, F2_AWAY = 1, 4
F2_TEAMS, F2_TEAM_B = 8, 16      # TEAMS: a fighter's team in the snapshot (proto.gd)
OWN_FIGHTER, OWN_BRAIN, OWN_SAFE = 1, 2, 4
NO_ONE = 255
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")


def decode_snapshot(data):
    """The whole snapshot a client needs here: the header, the fighters, the events."""
    tick, phase, rnd, left, goal, winner, walls, arena = struct.unpack_from("<IBBHBBHB", data, 1)
    nf, na, nz, ne = struct.unpack_from("<BHBH", data, 14)
    off = 20
    fighters = {}
    for _ in range(nf):
        sid, state, x, y, vx, vy, flags, aim, arrows, st, points, flags2 = struct.unpack_from("<BBhhbbBBBBBB", data, off)
        fighters[sid] = {"state": state, "x": x, "y": y, "points": points, "arrows": arrows, "flags": flags, "flags2": flags2}
        off += 14
    arrows = []
    for _ in range(na):
        aid, ks = struct.unpack_from("<HB", data, off)
        if (ks >> 4) & 3 in (2, 3):      # stuck, or in a body
            x, y, ang = struct.unpack_from("<hhB", data, off + 3)
            arrows.append({"state": (ks >> 4) & 3, "x": x, "y": y, "ang": 0.0})
            off += 8
        else:
            x, y, vx, vy, age, owner = struct.unpack_from("<ffffBB", data, off + 3)
            arrows.append({"state": (ks >> 4) & 3, "x": x, "y": y, "ang": 0.0, "owner": owner})
            off += 21
    off += nz * 9
    events = []
    for _ in range(ne):
        events.append((tick,) + struct.unpack_from("<BhhBB", data, off))
        off += 7
    return {"tick": tick, "phase": phase, "round": rnd, "left": left, "goal": goal, "winner": winner,
            "walls": walls & 0x7FFF, "arena": arena, "fighters": fighters, "arrows": arrows, "events": events}


class Client:
    """One fake player: a websocket, a thread that reads, a thread that sends inputs and pings."""

    def __init__(self, url, idx, version, name=None, token=None):
        self.url, self.idx, self.version = url, idx, version
        self.name = name or f"C{idx:02d}"
        self.name_ = self.name               # (v2_synth's brain reads these names)
        self.token = token or f"chaos{idx:02d}"
        self.rng = random.Random(idx * 7919 + 13)
        self.ws = None
        self.alive = False                   # the socket is open, as far as this side knows
        self.gen = 0                         # counts connects: an old thread sees it change and stops
        self.server_closed = False           # the server closed the socket (not this side)
        self.seat = -1
        self.welcomes = []                   # every welcome's seat, in order
        self.msgs = []                       # round_end, match_end, note, full, version_error, in order
        self.seats_msg = None
        self.snap = None
        self.snap_tick, self.snap_t = 0, 0.0
        self.own = None                      # the last T_OWN: {tick, used, margin, late, flags}
        self.events = collections.deque(maxlen=20000)
        self.friendly = []                   # TEAMS: knockouts by a teammate seen in a snapshot (there must be none): text lines
        self.team_kills = 0                  # and the knockouts by a foe seen in TEAMS rounds (so "none" means something)
        self.mode = "brain"                  # brain (v2_synth's small brain), hold (fixed buttons), idle (no buttons)
        self.hold_buttons = 0
        self.silent = False                  # send nothing at all (a frozen page)
        self.ahead = 0                       # a test knob: inputs this many ticks too early
        self.last_rtt = 0
        self.sent_inputs = 0
        self.err = None
        self.last_pos, self.still_t, self.unstick_t, self.unstick_dir = None, 0, 0, 1

    # ---------------------------------------------------------------- the socket
    def connect(self, hello=True, version=None, timeout=4.0):
        self.gen += 1
        gen = self.gen
        self.server_closed = False
        self.silent = False
        self.seat = -1
        self.welcomes = []                   # this socket's welcomes only
        self.snap, self.snap_t, self.own = None, 0.0, None
        try:
            self.ws = websocket.create_connection(self.url, timeout=timeout, enable_multithread=True,
                                                  sslopt={"cert_reqs": ssl.CERT_NONE, "check_hostname": False})
        except Exception as e:
            self.err = f"connect: {e}"
            self.alive = False
            return False
        self.ws.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        self.ws.settimeout(0.5)
        self.alive = True
        threading.Thread(target=self._read_loop, args=(self.ws, gen), daemon=True).start()
        threading.Thread(target=self._send_loop, args=(self.ws, gen), daemon=True).start()
        if hello:
            self.send({"kind": "hello", "name": self.name, "version": version or self.version, "token": self.token})
        return True

    def send(self, d):
        return self.send_text(json.dumps(d))

    def send_text(self, s):
        try:
            self.ws.send(s)
            return True
        except Exception:
            return False

    def send_bin(self, b):
        try:
            self.ws.send_binary(b)
            return True
        except Exception:
            return False

    def close(self):
        """A clean close (the tab is closed)."""
        self.alive = False
        self.gen += 1
        try:
            self.ws.close()
        except Exception:
            pass

    def drop(self):
        """The socket goes with no close frame (Wi-Fi gone, the phone sleeps)."""
        self.alive = False
        self.gen += 1
        try:
            self.ws.sock.close()
        except Exception:
            pass

    def abandon(self):
        """This side forgets the socket but leaves it open and silent (a zombie)."""
        self.alive = False
        self.gen += 1
        old = self.ws
        self.ws = None
        return old

    # ---------------------------------------------------------------- reading
    def _read_loop(self, ws, gen):
        while self.gen == gen:
            try:
                op, data = ws.recv_data()
            except websocket.WebSocketTimeoutException:
                continue
            except Exception:
                if self.gen == gen:
                    self.alive = False
                    self.server_closed = True
                return
            if self.gen != gen:
                return
            if op == websocket.ABNF.OPCODE_CLOSE:
                self.alive = False
                self.server_closed = True
                return
            if not data:
                continue
            if op == websocket.ABNF.OPCODE_TEXT:
                self._on_text(data.decode("utf-8", "replace"))
            elif op == websocket.ABNF.OPCODE_BINARY:
                if data[0] == T_SNAP:
                    try:
                        s = decode_snapshot(data)
                    except struct.error as e:
                        self.err = f"snapshot: {e}"
                        continue
                    self.snap = s
                    self.snap_tick, self.snap_t = s["tick"], time.monotonic()
                    self.events.extend(s["events"])
                    # TEAMS: a knockout whose killer is on the victim's team, by this same snapshot's
                    # team flags (the event: tick, type, x, y, killer, victim)
                    for e in s["events"]:
                        if e[1] != E_KILL or e[4] == e[5]:
                            continue
                        fk, fv = s["fighters"].get(e[4]), s["fighters"].get(e[5])
                        if fk and fv and (fk["flags2"] & F2_TEAMS) and (fv["flags2"] & F2_TEAMS):
                            if (fk["flags2"] & F2_TEAM_B) == (fv["flags2"] & F2_TEAM_B):
                                self.friendly.append(f"tick {s['tick']}: seat {e[4]} knocked out its teammate seat {e[5]}")
                            else:
                                self.team_kills += 1
                elif data[0] == T_OWN and len(data) >= 16:
                    tick, used, margin, late, flags, moves = struct.unpack_from("<IIbBBI", data, 1)
                    self.own = {"tick": tick, "used": used, "margin": margin, "late": late, "flags": flags}
                elif data[0] == T_PONG and len(data) >= 9:
                    sent = struct.unpack_from("<I", data, 1)[0]
                    self.last_rtt = ((int(time.monotonic() * 1000) & 0xFFFFFFFF) - sent) & 0xFFFFFFFF

    def _on_text(self, s):
        try:
            d = json.loads(s)
        except json.JSONDecodeError:
            return
        kind = d.get("kind")
        if kind == "welcome":
            self.seat = int(d.get("seat", -1))
            self.welcomes.append(self.seat)
        elif kind == "seats":
            self.seats_msg = d
        elif kind in ("round_end", "match_end", "note", "full", "version_error"):
            d["_t"] = time.monotonic()
            self.msgs.append(d)

    # ---------------------------------------------------------------- sending
    def _send_loop(self, ws, gen):
        tick = 0
        next_t = time.monotonic()
        next_ping = next_t
        hist = []
        while self.gen == gen and self.alive:
            now = time.monotonic()
            if now < next_t:
                time.sleep(min(0.004, next_t - now))
                continue
            next_t += 1.0 / 60.0
            if next_t < now - 0.5:
                next_t = now
            if self.silent or self.snap_t <= 0.0:
                continue
            want = int(self.snap_tick + (now - self.snap_t) * 60.0 + self.last_rtt * 0.06) + 3 + self.ahead
            if tick == 0 or want - tick > 20:
                tick = want
            elif tick > want + 3:
                continue
            else:
                tick += 1
            if self.mode == "brain":
                try:
                    buttons, aim = Synth.think(self, tick)     # v2_synth's small brain, on this object
                except Exception:
                    buttons, aim = 0, 0
            elif self.mode == "hold":
                buttons, aim = self.hold_buttons, 0
            else:
                buttons, aim = 0, 0
            hist.append(struct.pack("<BIBH", T_INPUT, tick & 0xFFFFFFFF, buttons & 255, aim % 3600))
            hist = hist[-4:]
            try:
                if self.seat >= 0:
                    ws.send_binary(b"".join(hist))
                    self.sent_inputs += 1
                if now >= next_ping:
                    next_ping = now + 0.5
                    ws.send_binary(struct.pack("<BIHH", T_PING, int(now * 1000) & 0xFFFFFFFF, min(self.last_rtt, 65535), 0))
            except Exception:
                if self.gen == gen:
                    self.alive = False
                return

    # ---------------------------------------------------------------- helpers for the checks
    def wait(self, test, seconds, step=0.02):
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            if test():
                return True
            time.sleep(step)
        return test()

    def phase(self):
        return self.snap["phase"] if self.snap else -1

    def take_msgs(self, kind):
        out = [m for m in self.msgs if m.get("kind") == kind]
        self.msgs = [m for m in self.msgs if m.get("kind") != kind]
        return out


class Host:
    """The server's host port (--admin-port): GET /state, POST a command."""

    def __init__(self, port):
        self.base = f"http://127.0.0.1:{port}"

    def call(self, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = urllib.request.Request(self.base + path, data=data, method="GET" if body is None else "POST",
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            try:
                return e.code, json.loads(e.read() or b"{}")
            except ValueError:
                return e.code, {}

    def state(self):
        return self.call("/state")[1]

    def cmd(self, name, **body):
        return self.call("/" + name, body)


class Server:
    """A test server of our own: ws (no TLS), its output in a file, stopped by its PID."""

    def __init__(self, port, admin_port, out_dir, extra, bench_dir=None, tls=None, log_name="server_stdout.log"):
        os.makedirs(out_dir, exist_ok=True)
        self.log_path = os.path.join(out_dir, log_name)
        self.log = open(self.log_path, "w")
        self.port, self.admin_port = port, admin_port
        cmd = ["godot", "--headless", "--path", bench_dir or os.path.join(ROOT, "bench"), "res://server/game_server.tscn", "--",
               "--port", str(port), "--admin-port", str(admin_port), "--out", os.path.join(out_dir, "results")] + extra
        cmd += ["--cert", tls[0], "--key", tls[1]] if tls else ["--no-tls"]      # tls: (cert file, key file) for wss
        self.proc = subprocess.Popen(cmd, stdout=self.log, stderr=subprocess.STDOUT)
        end = time.time() + 30
        while time.time() < end:
            try:
                socket.create_connection(("127.0.0.1", port), timeout=0.5).close()
                return
            except OSError:
                if self.proc.poll() is not None:
                    raise RuntimeError("the test server stopped at once: see " + self.log_path)
                time.sleep(0.2)
        raise RuntimeError("the test server never opened port %d" % port)

    def stop(self):
        if self.proc.poll() is None:
            self.proc.terminate()          # by its PID (never pkill)
            try:
                self.proc.wait(8)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.log.close()


# The longest each phase may last (seconds), with room: COUNTDOWN 3, ROUND START 1.5,
# PLAYING 60 (the server's backstop), ROUND END 1.5, MATCH END 8 + the longest replay (11.2).
PHASE_MAX = {PH_COUNTDOWN: 6.0, PH_ROUND_START: 4.0, PH_PLAY: 64.0, PH_ROUND_END: 4.0, PH_MATCH_END: 23.0}
JUNK_TEXT = [
    "", "{", "[]", "null", "42", '"hello"', '{"kind": 7}', '{"kind": "join", "name": 12345}', '{"kind": "join", "name": null}',
    '{"kind": "bots", "n": "many"}', '{"kind": "bots", "n": -99}', '{"kind": "bots", "n": 1e99}', '{"kind": "arena", "n": 999}',
    '{"kind": "arena", "n": -7}', '{"kind": "arena", "n": [1, 2]}', '{"kind": "season", "pick": 7}', '{"kind": "season", "pick": "winter"}',
    '{"kind": "bot_level", "n": {}}', '{"kind": "power", "n": "x"}', '{"kind": "name", "name": {"a": 1}}', '{"kind": "name"}',
    '{"kind": "report", "why": [], "errors": "no list", "fps": "fast", "frames": -5}', '{"kind": "report", "errors": [1, 2, {"x": []}]}',
    '{"kind": "hello"}', '{"kind": "hello", "version": 5, "token": [], "name": {}}', '{"kind": "skip"}', '{"kind": "start"}',
    '{"kind": "tv"}', '{"kind": "leave", "seat": 3}', '{"kind": "kick", "seat": 0}', '{"kind": "nope"}', '{"KIND": "join"}',
    '{"kind": "join", "name": "' + "A" * 5000 + '"}', '{"kind": "name", "name": "\\u0000\\u0007\\u202e<b>x</b>"}',
    '{"kind": "bots", "n": NaN}', "���", '{"kind": "join"' * 50,
    '{"kind": "mode"}', '{"kind": "mode", "pick": 7}', '{"kind": "mode", "pick": "pancakes"}', '{"kind": "mode", "pick": ["teams"]}',
    '{"kind": "team", "n": []}', '{"kind": "team", "seat": 3, "team": 9}', '{"kind": "team", "team": "TURKEY"}',
]


def junk(c, rng):
    """One junk packet from a fake player: bad JSON, wrong types, odd binary."""
    k = rng.randrange(8)
    if k <= 3:
        c.send_text(rng.choice(JUNK_TEXT))
    elif k == 4:
        c.send_bin(bytes(rng.randrange(256) for _ in range(rng.choice([1, 2, 7, 8, 9, 15, 33, 200, 4000]))))
    elif k == 5:      # an input packet with wild ticks (far ahead, far back, the same again)
        t = rng.choice([0, 1, 0xFFFFFFFF, 0x7FFFFFFF, (c.snap_tick + 100000) & 0xFFFFFFFF, max(0, c.snap_tick - 5000)])
        c.send_bin(b"".join(struct.pack("<BIBH", T_INPUT, t, rng.randrange(256), rng.randrange(65536)) for _ in range(rng.randrange(1, 9))))
    elif k == 6:      # packets with a known first byte and a short or odd body
        c.send_bin(bytes([rng.choice([T_SNAP, T_INPUT, T_PING, T_PONG, T_OWN, 0, 99])]) + bytes(rng.randrange(256) for _ in range(rng.randrange(0, 12))))
    else:             # a burst of pings
        for _ in range(rng.randrange(5, 60)):
            c.send_bin(struct.pack("<BIHH", T_PING, rng.randrange(1 << 32), rng.randrange(65536), rng.randrange(65536)))


def raw_junk(port, rng):
    """A socket that is no websocket: garbage, half a handshake, or nothing at all."""
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=1.0)
        k = rng.randrange(3)
        if k == 0:
            s.sendall(bytes(rng.randrange(256) for _ in range(rng.randrange(1, 600))))
        elif k == 1:
            s.sendall(b"GET / HTTP/1.1\r\nHost: x\r\nUpgrade: websocket\r\n")
        threading.Timer(rng.uniform(0.2, 12.0), s.close).start()
    except OSError:
        pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spawn", action="store_true", help="start a test server of our own (and stop it at the end)")
    ap.add_argument("--port", type=int, default=8110)
    ap.add_argument("--admin-port", type=int, default=8120)
    ap.add_argument("--url", default="", help="a server that already runs (ws://host:port); needs --admin-port")
    ap.add_argument("--server-log", default="", help="with --url: the server's output file, read for errors")
    ap.add_argument("--minutes", type=float, default=15.0)
    ap.add_argument("--fakes", type=int, default=10, help="fake players (more than 8: FULL happens too)")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--bots", type=int, default=3)
    ap.add_argument("--season", default="harvest")
    ap.add_argument("--arena", default="mix")
    ap.add_argument("--mode", default="ffa", help="the MODE the spawned server starts in: ffa or teams")
    ap.add_argument("--no-mode-moves", action="store_true", help="nobody changes the MODE or a team (with --mode ffa: a soak of FREE FOR ALL alone)")
    ap.add_argument("--goal", type=int, default=0, help="points to win (0: the server's rule)")
    ap.add_argument("--calm", action="store_true", help="no host stop, no kick: matches run to their end (more rounds, more winner's screens)")
    ap.add_argument("--bench", default="", help="with --spawn: the server from another copy of bench/ (an older commit: the soak should find its bugs)")
    ap.add_argument("--out", default=os.path.join(ROOT, "bench_results", "chaos"))
    a = ap.parse_args()
    rng = random.Random(a.seed)
    os.makedirs(a.out, exist_ok=True)
    server = None
    if a.spawn:
        extra = ["--bots", str(a.bots), "--season", a.season, "--arena", a.arena, "--mode", a.mode]
        if a.goal > 0:
            extra += ["--goal", str(a.goal)]
        server = Server(a.port, a.admin_port, a.out, extra, a.bench or None)
        url, log_path = f"ws://127.0.0.1:{a.port}", server.log_path
    else:
        url, log_path = a.url, a.server_log
        a.port = int(url.rsplit(":", 1)[1].split("/")[0])
    host = Host(a.admin_port)
    version = game_version()
    if a.bench:
        with open(os.path.join(a.bench, "sim", "proto.gd")) as f:
            version = re.search(r'const VERSION := "([^"]+)"', f.read()).group(1)
    clients = [Client(url, i, version) for i in range(a.fakes)]
    zombies = []                       # old sockets left open and silent: [socket, close at]
    did = collections.Counter()
    findings = []                      # what the soak found: (seconds in, text)
    seen_find = set()
    t0 = time.monotonic()

    repeats = [0]

    def find(text, key=None):
        key = key or text
        if key in seen_find:
            repeats[0] += 1
            return
        seen_find.add(key)
        findings.append((round(time.monotonic() - t0, 1), text))
        print(f"🔥 [Chaos] FOUND at {time.monotonic() - t0:.1f} s: {text}", flush=True)

    # ------------------------------------------------------------ one fake player's move
    def act(c):
        if c.ws is None or not c.alive:
            k = rng.random()
            if k < 0.04:
                raw_junk(a.port, rng)
                did["raw junk sockets"] += 1
            elif k < 0.08:
                if c.connect(version="v0.0.0-old"):
                    did["hello with a wrong version"] += 1
            elif c.connect():
                did["connect + hello (its token)"] += 1
                c.next_join = time.monotonic() + rng.uniform(0.1, 3.0)
            return
        k = rng.random()
        if c.seat < 0:
            if k < 0.45 and time.monotonic() >= getattr(c, "next_join", 0):
                c.send({"kind": "join", "name": c.name})
                did["join"] += 1
            elif k < 0.52:
                c.close()
                did["close (a watcher)"] += 1
            elif k < 0.58:
                c.drop()
                did["drop with no close (a watcher)"] += 1
            elif k < 0.70:
                junk(c, rng)
                did["junk packets"] += 1
            return
        if k < 0.030:
            c.send({"kind": "leave"})
            did["leave"] += 1
        elif k < 0.070:
            c.close()
            did["close (seated)"] += 1
        elif k < 0.140:
            c.drop()
            did["drop with no close (seated)"] += 1
        elif k < 0.200:
            c.mode, c.hold_buttons = "hold", rng.choice([B_RIGHT, B_LEFT, B_RIGHT | B_JUMP, B_SHOOT, B_DODGE | B_LEFT, B_DOWN | B_JUMP])
            c.silent_at = time.monotonic() + 0.3      # the button is held for a moment first, then nothing comes
            c.silent_for = rng.choice([1.0, 2.0, 4.0, 8.0, 30.0])
            did["silent with a button held"] += 1
        elif k < 0.250:
            # the same person on a second socket, the first still open: sometimes it goes on
            # sending (two tabs), mostly it is silent (a dead Wi-Fi link nobody closed)
            old = c.abandon()
            if rng.random() < 0.3:
                threading.Timer(rng.uniform(0.5, 6.0), lambda s=old: _quiet_close(s)).start()
            else:
                zombies.append([old, time.monotonic() + rng.uniform(5.0, 40.0)])
            c.connect()
            c.next_join = time.monotonic() + rng.uniform(0.1, 1.5)
            did["second socket, same token"] += 1
        elif k < 0.330:
            for _ in range(rng.randrange(1, 6)):
                junk(c, rng)
            did["junk packets"] += 1
        elif k < 0.360:
            c.send({"kind": "start"})
            did["start (a player)"] += 1
        elif k < 0.380:
            c.send({"kind": "skip"})
            did["skip (a player)"] += 1
        elif k < 0.400:
            c.send(rng.choice([{"kind": "bots", "n": rng.randrange(0, 8)}, {"kind": "power", "n": rng.randrange(2)},
                               {"kind": "bot_level", "n": rng.randrange(1, 4)}, {"kind": "name", "name": c.name + rng.choice("abc")}]))
            did["lobby settings (a player)"] += 1
        elif k < 0.50:
            c.mode = rng.choice(["brain", "brain", "brain", "idle", "hold"])
            c.hold_buttons = rng.randrange(256)
        elif k < 0.58 and not a.no_mode_moves:
            # TEAMS: a tap on its own card (at any time: only one in the lobby may count)
            for _ in range(rng.choice([1, 1, 1, 2, 5])):
                c.send({"kind": "team"})
            did["change sides (a player)"] += 1
        elif k < 0.60 and not a.no_mode_moves:
            c.send({"kind": "mode", "pick": rng.choice(["teams", "teams", "ffa"])})
            did["mode (a player)"] += 1

    def _quiet_close(s):
        try:
            s.close()
        except Exception:
            pass

    def host_act():
        st = host.state()
        k = rng.random()
        ph = st.get("phase", 0)
        if k < 0.55:
            if ph == PH_LOBBY:           # (in a match: nothing this time, the match plays on)
                host.cmd("start")
                did["host: start"] += 1
        elif k < 0.58:
            if not a.calm:               # about once a minute and a half
                host.cmd("stop")
                did["host: stop"] += 1
        elif k < 0.68:
            if not a.calm:
                host.cmd("kick", seat=rng.randrange(8))
                did["host: kick"] += 1
        elif k < 0.74:
            host.cmd("arena", n=rng.choice([-1, -1, -1, 1, 2, 3, 4, 5, 6, 7, 8]))
            did["host: arena"] += 1
        elif k < 0.80:
            if not a.no_mode_moves:
                host.cmd("mode", pick=rng.choice(["teams", "teams", "teams", "ffa"]))     # TEAMS: in a match it counts from the next one
                did["host: mode"] += 1
        elif k < 0.87:
            host.cmd("season", pick=rng.choice([a.season, a.season, a.season, "auto", "off", "halloween", "harvest", "christmas"]))   # (mostly the run's own season)
            did["host: season"] += 1
        elif k < 0.93:
            host.cmd("bots", n=rng.choice([0, 1, 2, 3, 3, 5, 7]))
            did["host: bots"] += 1
        elif k < 0.96:
            host.cmd("bot_level", n=rng.randrange(1, 4))
            did["host: bot level"] += 1
        else:
            host.cmd("power", n=rng.choice([1, 1, 1, 0]))
            did["host: power-ups"] += 1

    # ------------------------------------------------------------ the checks
    last_key, key_since = None, time.monotonic()
    worst = {"tick_mean_ms": 0.0, "tick_p99_ms": 0.0, "tick_max_ms": 0.0, "interval_max_ms": 0.0, "rss_mb": 0.0}
    rss_first = [None]
    log_pos = [0]
    round_open = [False]
    slow_lines = []
    counts = collections.Counter()
    seen_rounds = set()
    bots_seen = {"match": -1, "bots": {}}      # the last look: the match, and {seat: (name, points)} of its bots

    def check_state():
        nonlocal last_key, key_since
        try:
            st = host.state()
        except Exception as e:
            find(f"the host port did not answer: {e}", "host port")
            return
        now = time.monotonic()
        key = (st["phase"], st["round"], st["match"])
        if key != last_key:
            last_key, key_since = key, now
            if st["phase"] == PH_ROUND_START and (st["match"], st["round"]) not in seen_rounds:
                seen_rounds.add((st["match"], st["round"]))
                counts["rounds started"] += 1
        elif st["phase"] in PHASE_MAX and now - key_since > PHASE_MAX[st["phase"]]:
            find(f"phase stuck: {PHASES[st['phase']]} (match {st['match']}, round {st['round']}) for {now - key_since:.1f} s",
                 f"stuck {key}")
        names, cids = {}, {}
        for s in st["seats"]:
            i, kind = s["i"], s["kind"]
            # (crowns are left out: a bot's match wins stay on its seat between matches, by design)
            if kind == 0 and (s["points"] != 0 or s["name"] != ""):
                find(f"an empty seat with something on it: seat {i} name '{s['name']}' points {s['points']}", f"empty {i}")
            if s["points"] < 0 or (st["phase"] != PH_LOBBY and st["goal"] > 0 and s["points"] > st["goal"]):
                find(f"points out of range: seat {i} '{s['name']}' has {s['points']} (goal {st['goal']})", f"points {i}")
            if kind == 1:
                who = s["name"][:3]
                if who in names and who.startswith("C"):
                    find(f"two seats for one player: '{s['name']}' on seats {names[who]} and {i}", f"twice {who}")
                names[who] = i
                if s["client"] != 0:
                    if s["client"] in cids:
                        find(f"one client on two seats: client {s['client']} on seats {cids[s['client']]} and {i}", "client twice")
                    cids[s["client"]] = i
                if s["name"] == "":
                    find(f"a person's seat with no name: seat {i}", f"noname {i}")
        # TEAMS, from the host port's own view of the seats
        in_match = st["phase"] not in (PH_LOBBY, PH_COUNTDOWN)
        if st.get("mode_now") == "teams":
            counts["checks in TEAMS"] += 1
            tp = st.get("team_points", [0, 0])
            for s in st["seats"]:
                if s["kind"] == 0:
                    continue
                if s.get("team") not in (0, 1):
                    find(f"TEAMS: a seated fighter with no team: seat {s['i']} '{s['name']}' team {s.get('team')}", f"noteam {s['i']}")
                elif in_match and s["points"] != tp[s["team"]]:
                    find(f"TEAMS: seat {s['i']} '{s['name']}' shows {s['points']} points, its team {s['team']} has {tp[s['team']]}", f"teampoints {s['i']}")
            if in_match and (min(tp) < 0 or (st["goal"] > 0 and max(tp) > st["goal"])):
                find(f"TEAMS: team points out of range: {tp} (goal {st['goal']})", "teampoints range")
        elif in_match:
            counts["checks in FREE FOR ALL"] += 1
            if st.get("team_points", [0, 0]) != [0, 0]:
                find(f"FREE FOR ALL: team points are not 0: {st.get('team_points')}", "ffa teampoints")
        # A bot keeps its seat, its name and its points through a match (p4.19's "found, not
        # fixed" 6: the bots were put back on the lowest empty seats every round, and the
        # points stayed on the seats). Two looks in the same match:
        #  - the same seat, a bot then and now: the same name, the same points or one more;
        #  - a bot's seat is empty now AND a seat that was no bot's has a bot now: the bots
        #    moved (with fewer bots wanted, bots only go; with more, bots only come).
        bots_now = {s["i"]: (s["name"], s["points"]) for s in st["seats"] if s["kind"] == 2}
        if st["match"] == bots_seen["match"]:
            for i, (name, pts) in bots_now.items():
                old = bots_seen["bots"].get(i)
                if old and (old[0] != name or not old[1] <= pts <= old[1] + 1):
                    find(f"a bot changed in the middle of match {st['match']}: seat {i} was '{old[0]}' with {old[1]} points, now it is '{name}' with {pts}", f"bot {i}")
                elif old:
                    counts["looks at a bot that stayed as it was"] += 1
            gone = [i for i in bots_seen["bots"] if st["seats"][i]["kind"] == 0]
            came = [i for i in bots_now if i not in bots_seen["bots"]]
            if gone and came:
                counts["times the bots moved seats"] += 1
                find(f"the bots moved seats in the middle of match {st['match']} (round {st['round']}): the bot of seat {gone[0]} "
                     f"('{bots_seen['bots'][gone[0]][0]}', {bots_seen['bots'][gone[0]][1]} points) is gone, and a new one sits on seat {came[0]} "
                     f"('{bots_now[came[0]][0]}', {bots_now[came[0]][1]} points)", "bots moved")
        bots_seen["match"], bots_seen["bots"] = st["match"], bots_now
        t = st.get("tick", {})
        worst["rss_mb"] = max(worst["rss_mb"], float(t.get("rss_mb", 0.0)))
        if rss_first[0] is None and float(t.get("rss_mb", 0.0)) > 0:
            rss_first[0] = float(t["rss_mb"])

    def check_msgs():
        for c in clients:
            for m in c.take_msgs("round_end"):
                counts["round_end messages"] += 1
                if not m.get("draw") and (str(m.get("name", "")) == "" or int(m.get("winner", 255)) > 7):
                    find(f"a round's winner with no name: round_end {json.dumps({k: m[k] for k in ('round', 'winner', 'name', 'draw')})}", "round noname")
                if "team" in m:      # TEAMS: a team won: its name, its members, and the seat that stands for it is one of them
                    counts["rounds won by a team (messages)"] += 1
                    if m.get("draw") or m["team"] not in (0, 1) or not str(m.get("name", "")).startswith("TEAM ") \
                            or not m.get("members") or int(m.get("winner", 255)) not in [int(x) for x in m.get("members", [])]:
                        find(f"TEAMS: an odd round_end: {json.dumps({k: m.get(k) for k in ('round', 'winner', 'name', 'draw', 'team', 'members')})}", "team round odd")
            for m in c.take_msgs("match_end"):
                counts["match_end messages"] += 1
                if str(m.get("name", "")) == "":
                    find(f"a match's winner with no name: seat {m.get('winner')}", "match noname")
                if "team" in m:
                    counts["matches won by a team (messages)"] += 1
                    if not str(m.get("name", "")).startswith("TEAM ") or not m.get("members") or str(m.get("best", "")) == "" \
                            or int(m.get("winner", 255)) not in [int(x) for x in m.get("members", [])]:
                        find(f"TEAMS: an odd match_end: {json.dumps({k: m.get(k) for k in ('winner', 'name', 'team', 'members', 'best')})}", "team match odd")
            c.take_msgs("note")
            c.take_msgs("full")
            c.take_msgs("version_error")
            c.events.clear()
            # TEAMS: no friendly fire, as this fake player saw it in its snapshots
            for line in c.friendly:
                find(f"TEAMS: friendly fire: {line} (seen by {c.name})", "friendly " + line)
            c.friendly = []
            counts["knockouts by a foe in TEAMS rounds (as the fakes saw them)"] += c.team_kills
            c.team_kills = 0
            # and each fighter's team flag in the snapshot is its seat's team (a seat taken over in the
            # middle of a round is left out: its fighter keeps the round's team, "in" is false)
            sm, sn = c.seats_msg, c.snap
            if c.alive and sm and sn and sm.get("mode") == "teams" and sn["phase"] == PH_PLAY and sm.get("phase") == PH_PLAY \
                    and sm.get("round") == sn["round"]:
                for s in sm.get("seats", []):
                    f = sn["fighters"].get(s["i"])
                    if f is None or not s.get("in") or s.get("kind") == 0:
                        continue
                    flag = (1 if f["flags2"] & F2_TEAM_B else 0) if f["flags2"] & F2_TEAMS else -1
                    if flag != s.get("team"):
                        find(f"TEAMS: seat {s['i']} '{s['name']}' is on team {s.get('team')} in the seats message, its fighter's flag says {flag}", f"flag {s['i']}")

    def check_log():
        if not log_path or not os.path.exists(log_path):
            return
        with open(log_path, errors="replace") as f:
            f.seek(log_pos[0])
            chunk = f.read()
            log_pos[0] = f.tell()
        for line in chunk.splitlines():
            if "SCRIPT ERROR" in line or line.startswith("ERROR") or "   at: " in line and "game_server" in line:
                find("the server's output: " + line.strip()[:300], line.strip()[:120])
            m = re.search(r"tick mean ([\d.]+) p99 ([\d.]+) max ([\d.]+) ms .*interval p99 ([\d.]+) max ([\d.]+) ms", line)
            if m:
                counts["report lines"] += 1
                worst["tick_mean_ms"] = max(worst["tick_mean_ms"], float(m.group(1)))
                worst["tick_p99_ms"] = max(worst["tick_p99_ms"], float(m.group(2)))
                worst["tick_max_ms"] = max(worst["tick_max_ms"], float(m.group(3)))
                worst["interval_max_ms"] = max(worst["interval_max_ms"], float(m.group(5)))
                # a tick has 16.7 ms: a mean over 8 ms or a p99 over 16.7 ms is a server too slow to keep 60 a second
                if float(m.group(1)) > 8.0 or float(m.group(2)) > 16.7:
                    find(f"the server's tick is slow: {m.group(0)}", "slow tick")
            # every round ends: a round that started is followed by its end, or by the lobby
            # (the host stopped the match, too few fighters were left)
            if re.search(r"\[ROUND\] \d+ start on", line):
                counts["rounds started (the log)"] += 1
                round_open[0] = True
            elif re.search(r"\[ROUND\] \d+ end after", line):
                counts["rounds ended"] += 1
                if " a draw" in line:
                    counts["draws"] += 1
                round_open[0] = False
            elif "[LOBBY] back in the lobby" in line:
                if round_open[0]:
                    counts["rounds cut short (host stop, too few fighters)"] += 1
                round_open[0] = False
            if "[SLOW]" in line:
                slow_lines.append(line.strip()[:260])
            for word, name in (("is the last team standing", "rounds won by a team"), ("joins TEAM", "taps that changed sides"),
                               ("[LOBBY] mode ", "MODE changes"), ("countdown stopped: a team has no fighter", "countdowns stopped (a team was empty)"),
                               ("left (a team has none)", "matches stopped (a team was empty)"), ("TEAMS, first to", "matches started in TEAMS"),
                               ("FREE FOR ALL, first to", "matches started in FREE FOR ALL"), ("no point: nobody of", "no-point lines (the whole team left)"),
                               ("PHEW:", "PHEW lines (the winner was saved)"), ("[MATCH] end after", "matches ended with a winner"),
                               ("[MATCH] start", "matches started"), ("is back from", "seats taken back by a token"),
                               (": held ", "seats held after a drop"), ("went silent", "silent sockets dropped"), ("no point:", "no-point lines"),
                               ("took over", "seats taken over by a second socket"), ("is free again", "held seats freed"),
                               ("left the round", "fighters taken out (seat given up)"), ("skipped the montage", "replays skipped"),
                               ("[KILL]", "kill lines")):
                if word in line:
                    counts[name] += 1

    # ------------------------------------------------------------ the run
    print(f"🔥 [Chaos] {a.fakes} fake players on {url} for {a.minutes:g} min, seed {a.seed}, host port {a.admin_port}"
          + (f", our own server (PID {server.proc.pid}, output {log_path})" if server else ""), flush=True)
    end = t0 + a.minutes * 60.0
    next_host = t0 + 2.0
    next_check = t0 + 1.0
    next_line = t0 + 30.0
    try:
        while time.monotonic() < end:
            now = time.monotonic()
            for c in clients:
                # a silent player: nothing is sent for a while; then it sends again, or stays gone
                if getattr(c, "silent_at", 0) and now >= c.silent_at:
                    c.silent, c.silent_until, c.silent_at = True, now + c.silent_for, 0
                if c.silent and now >= getattr(c, "silent_until", 0):
                    c.silent = False
                    c.mode = "brain"
                    did["a silent player sends again"] += 1
                if rng.random() < 0.012:       # each fake player makes a move about every 4 s
                    act(c)
            for z in zombies[:]:
                if now >= z[1]:
                    _quiet_close(z[0])
                    zombies.remove(z)
            if now >= next_host:
                next_host = now + rng.uniform(1.5, 7.0)
                try:
                    host_act()
                except Exception as e:
                    find(f"a host command failed: {e}", "host cmd")
            if now >= next_check:
                next_check = now + 0.5
                check_state()
                check_msgs()
                check_log()
                if server and server.proc.poll() is not None:
                    find(f"the server stopped by itself (exit code {server.proc.returncode})", "server died")
                    break
            if now >= next_line:
                next_line = now + 30.0
                st = host.state()
                print(f"🔥 [Chaos] {now - t0:5.0f} s: phase {PHASES[st['phase']]}, match {st['match']}, {st['people']} people, "
                      f"{counts['rounds started']} rounds, {sum(did.values())} moves, {len(findings)} found, "
                      f"tick mean {st['tick']['mean_ms']:.2f} max {st['tick']['max_ms']:.2f} ms, rss {st['tick']['rss_mb']:.0f} MB", flush=True)
            time.sleep(0.05)
        check_state()
        check_msgs()
        time.sleep(0.6)
        check_log()
    finally:
        for c in clients:
            try:
                c.close()
            except Exception:
                pass
        for z in zombies:
            _quiet_close(z[0])
        if server:
            time.sleep(0.5)
            server.stop()
            check_log()
    secs = time.monotonic() - t0
    print(f"\n🔥 [Chaos] done: {secs / 60.0:.1f} min, seed {a.seed}")
    print("   moves: " + ", ".join(f"{k} {v}" for k, v in sorted(did.items(), key=lambda kv: -kv[1])))
    print("   seen: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items(), key=lambda kv: -kv[1])))
    print(f"   the server's tick, the worst 5 s: mean {worst['tick_mean_ms']:.2f} ms, p99 {worst['tick_p99_ms']:.2f} ms, max {worst['tick_max_ms']:.2f} ms; "
          f"interval max {worst['interval_max_ms']:.1f} ms; memory {rss_first[0] or 0:.0f} -> {worst['rss_mb']:.0f} MB at most")
    if slow_lines:
        print(f"   the server's own [SLOW] lines (a tick over 12 ms): {len(slow_lines)}")
        for l in slow_lines[:12]:
            print("     " + l)
    left_open = counts["rounds started (the log)"] - counts["rounds ended"] - counts["rounds cut short (host stop, too few fighters)"]
    print(f"   every round ends: {counts['rounds started (the log)']} started = {counts['rounds ended']} ended + "
          f"{counts['rounds cut short (host stop, too few fighters)']} cut short by the lobby + {left_open} still on when the soak stopped")
    if left_open not in (0, 1):
        find(f"rounds that neither ended nor were cut short: {left_open}", "open rounds")
    if findings:
        print(f"   FOUND {len(findings)} (and {repeats[0]} repeats):")
        for t, text in findings:
            print(f"     {t:7.1f} s  {text}")
    else:
        print("   found nothing: no error in the server's output, no phase stuck, seats and points sane, every winner had a name, "
              "teams and their points sane, no knockout by a teammate")
    with open(os.path.join(a.out, "chaos_report.json"), "w") as f:
        json.dump({"seconds": round(secs, 1), "seed": a.seed, "fakes": a.fakes, "moves": did, "seen": counts, "worst": worst,
                   "rss_first_mb": rss_first[0], "findings": findings}, f, indent=1)
    sys.exit(1 if findings else 0)


if __name__ == "__main__":
    main()

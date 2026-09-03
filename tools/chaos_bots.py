#!/usr/bin/env python3
"""
Tower Brawl test harness: protocol bots with an oracle, assertions and scenarios.

    ./venv/bin/python tools/chaos_bots.py                      # run every scenario
    ./venv/bin/python tools/chaos_bots.py --scenario smoke     # one scenario
    ./venv/bin/python tools/chaos_bots.py --scenario play --bots 3 --duration 90 --die-rate 0
    ./venv/bin/python tools/chaos_bots.py --list

Every bot is a headless WebSocket client that behaves like the Godot client
(join, name, lock in, 20 Hz binary sync_pos with idle suppression while alive, silence while dead, 1 s pings)
and keeps a MODEL of what the server state should be. Every packet the server
sends is checked against a per-type SCHEMA, against the model (ORACLE), and
against a short window of recently received packets (DUPLICATE detection).
Scenarios orchestrate bots through named situations and record findings; the
run ends with a report and a non-zero exit code if anything failed.

Duplicates are counted but NOT fed to the model, so each finding maps to one
root cause instead of cascading. Seeds make bot behaviour deterministic up to
network timing.

Step 2 (after Phase 1): fault injection (--latency-ms/--jitter-ms/--loss, lag, slow_reader,
stop_pinging), fuzzing (fuzz), a headless Godot fleet (fleet, --godot N) and a soak
monitor (--soak MINUTES) that samples the server's RSS, threads and fds.
"""
import argparse
import collections
import heapq
import json
import math
import os
import random
import re
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time

try:
    import websocket  # websocket-client
except ImportError:
    sys.exit("websocket-client is missing. Run with ./venv/bin/python")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ARENA_W, ARENA_H = 640.0, 360.0
WEAPONS = ["arrow", "firebolt", "kunai"]
MOVEMENT_TYPES = ("sync_pos", "spawn_projectile")
# Identical raw packets closer than this = duplicate broadcast. Event packets get a
# wider window because the server has no TCP_NODELAY: the second copy to the
# victim's own socket can trail the first by a ~40 ms delayed-ACK stall. Movement
# packets keep a tight window so an idle real client (identical sync_pos every
# 33 ms) is never mistaken for a duplicate.
DUP_WINDOW_EVENT = 0.150
DUP_WINDOW_MOVEMENT = 0.020
RESPAWN_DELAY = 1.2         # arena.gd respawn delay
SPAWN_INVULN = 1.0          # player.gd spawn_invuln_timer: no death possible right after a respawn
NEXT_ROUND_DELAY = 2.6      # serve_game.py NEXT_ROUND_DELAY
MATCH_END_DELAY = 6.0       # serve_game.py MATCH_END_DELAY (banner time before return_to_lobby)
MATCH_SCORE_LIMIT = 5       # serve_game.py MATCH_SCORE_LIMIT
REJOIN_GRACE = 8.0          # serve_game.py REJOIN_GRACE: a fighter's seat is held after a disconnect
FORFEIT_GRACE = 1.5         # serve_game.py FORFEIT_GRACE: explicit leave, round decided after this
DEATH_DEDUPE_S = 1.5        # serve_game.py DEATH_DEDUPE_S

# ── Schema ───────────────────────────────────────────────────────────────────
NUM = "num"
SCHEMA = {
    "spectator_state": {"active_players": list, "playing_players": list, "match_state": str,
                        "locked_players": dict, "player_names": dict, "current_round": int,
                        "scores": dict, "stocks": dict, "arena_flips": int},
    "assign_id": {"id": int, "rejoined": bool, "active_players": list, "playing_players": list, "match_state": str,
                  "locked_players": dict, "player_names": dict, "current_round": int,
                  "scores": dict, "stocks": dict, "arena_flips": int},
    "player_joined": {"id": int, "active_players": list, "playing_players": list, "player_names": dict},
    "player_left": {"id": int, "active_players": list},
    "name_update": {"player_names": dict},
    "lock_in": {"class": int, "sender": int},
    "force_start": {"sender": int},
    "scene_transition": {},
    "player_died": {"victim": int, "killer": int, "stock": int},
    "round_end": {"winner": int, "scores": dict, "round": int, "match_over": bool},
    "new_round": {"round": int},
    "return_to_lobby": {},
    "version_error": {"server_version": str},
    "server_full": {},
    "pong": {},
    "sync_pos": {"tick": int, "x": NUM, "y": NUM, "aim_x": NUM, "aim_y": NUM, "facing": bool, "dash": bool,
                 "shield": bool, "bear": bool, "egg": bool, "sender": int},
    "spawn_projectile": {"weapon": str, "pos_x": NUM, "pos_y": NUM, "dir_x": NUM, "dir_y": NUM,
                         "sender": int},
    "spawn_powerup": {"x": NUM, "y": NUM, "sender": int},
    "activate_powerup": {"powerup_id": int, "sender": int},
}


def _type_ok(value, expected):
    if expected is NUM:
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    if expected is int:
        return isinstance(value, int) and not isinstance(value, bool)
    return isinstance(value, expected)


# ── Binary movement packets (Phase 2; mirrors global.gd / serve_game.py) ────
BIN_SYNC_POS, BIN_SPAWN_PROJECTILE = 1, 2
BIN_SYNC_SIZE, BIN_PROJ_SIZE = 11, 9      # sync_pos carries a u16 tick since Phase 3a
NET_TICK_HZ = 20.0
NET_IDLE_RESEND = 0.5
BIN_WEAPONS = ["arrow", "firebolt", "kunai", "thorn"]
FLAG_FACING, FLAG_DASH, FLAG_SHIELD, FLAG_BEAR, FLAG_EGG = 1, 2, 4, 8, 16


def q10(v):
    return max(-32768, min(32767, int(round(v * 10.0))))


def dir_to_u16(dx, dy):
    return int(round((math.degrees(math.atan2(dy, dx)) % 360.0) * 10.0)) % 3600


def u16_to_dir(a):
    r = math.radians(a / 10.0)
    return math.cos(r), math.sin(r)


def encode_sync_pos(x, y, aim_x, aim_y, facing=True, dash=False, shield=False, bear=False, egg=False, sender=0, tick=0):
    flags = ((FLAG_FACING if facing else 0) | (FLAG_DASH if dash else 0) | (FLAG_SHIELD if shield else 0)
             | (FLAG_BEAR if bear else 0) | (FLAG_EGG if egg else 0))
    return struct.pack("<BBHhhHB", BIN_SYNC_POS, sender, tick & 0xFFFF, q10(x), q10(y), dir_to_u16(aim_x, aim_y), flags)


def encode_projectile(weapon, x, y, dx, dy, sender=0):
    return struct.pack("<BBBhhH", BIN_SPAWN_PROJECTILE, sender, BIN_WEAPONS.index(weapon), q10(x), q10(y), dir_to_u16(dx, dy))


def decode_binary(b):
    """bytes -> the same dict shape the JSON packets had, or None if malformed."""
    if not b:
        return None
    if b[0] == BIN_SYNC_POS and len(b) == BIN_SYNC_SIZE:
        _, sender, tick, x, y, aim, flags = struct.unpack("<BBHhhHB", b)
        ax, ay = u16_to_dir(aim)
        return {"type": "sync_pos", "sender": sender, "tick": tick, "x": x / 10.0, "y": y / 10.0, "aim_x": ax, "aim_y": ay,
                "facing": bool(flags & FLAG_FACING), "dash": bool(flags & FLAG_DASH),
                "shield": bool(flags & FLAG_SHIELD), "bear": bool(flags & FLAG_BEAR), "egg": bool(flags & FLAG_EGG)}
    if b[0] == BIN_SPAWN_PROJECTILE and len(b) == BIN_PROJ_SIZE:
        _, sender, wid, x, y, d = struct.unpack("<BBBhhH", b)
        dx, dy = u16_to_dir(d)
        return {"type": "spawn_projectile", "sender": sender,
                "weapon": BIN_WEAPONS[wid] if wid < len(BIN_WEAPONS) else "?",
                "pos_x": x / 10.0, "pos_y": y / 10.0, "dir_x": dx, "dir_y": dy}
    return None


def read_game_version():
    with open(os.path.join(ROOT, "scripts", "global.gd"), encoding="utf-8") as f:
        m = re.search(r'const GAME_VERSION: String = "(v\d+\.\d+\.\d+)"', f.read())
    return m.group(1) if m else "v0.0.0"


def ints(seq):
    return {int(x) for x in seq}


# ── Findings ─────────────────────────────────────────────────────────────────
class Findings:
    """name -> (count, first few details). Thread-safe."""
    def __init__(self):
        self.lock = threading.Lock()
        self.counts = collections.Counter()
        self.examples = collections.defaultdict(list)
        self.order = []

    def fail(self, name, detail):
        with self.lock:
            if name not in self.counts:
                self.order.append(name)
            self.counts[name] += 1
            if len(self.examples[name]) < 3:
                self.examples[name].append(detail)

    def failed(self):
        return bool(self.counts)


# ── Model (oracle) ───────────────────────────────────────────────────────────
class Model:
    def __init__(self):
        self.state = "LOBBY"
        self.active = set()
        self.playing = set()
        self.waiting = set()
        self.alive = set()
        self.stocks = {}
        self.scores = {}
        self.names = {}
        self.locked = {}
        self.round = 1
        self.round_over = False
        self.match_over = False        # round_end carried match_over: only return_to_lobby may follow
        self.round_end_at = None       # watchdog: next_round / return_to_lobby expected
        self.alive_le1_since = None    # watchdog: round_end expected
        self.round_ends = []           # (round, winner)
        self.pending = {}              # pid -> deadline: seat held by the server after a disconnect/leave
        self.last_tick = {}            # sender -> newest movement tick seen (order check)

    def expire_pending(self, now):
        for pid in [p for p, t in self.pending.items() if t <= now]:
            self.pending.pop(pid, None)
        self._check_alive_watchdog(now)

    def _sync_snapshot(self, pkt):
        self.state = pkt["match_state"]
        self.active = ints(pkt["active_players"])
        self.playing = ints(pkt["playing_players"])
        self.round = int(pkt["current_round"])
        self.scores = {int(k): int(v) for k, v in pkt["scores"].items()}
        self.stocks = {int(k): int(v) for k, v in pkt["stocks"].items()}
        self.names = {int(k): v for k, v in pkt["player_names"].items()}
        self.locked = {int(k): int(v) for k, v in pkt["locked_players"].items()}
        self.waiting = set()
        self.round_over = False
        self.alive = {p for p in self.playing if self.stocks.get(p, 3) > 0} if self.state == "PLAYING" else set()

    def _check_alive_watchdog(self, now):
        if any(t > now for t in self.pending.values()):
            return  # a seat is still held; the server decides the round only when the grace ends
        if self.state == "PLAYING" and len(self.alive) <= 1 and not self.round_over and self.alive_le1_since is None:
            self.alive_le1_since = now

    def apply(self, pkt, now, F, who):
        t = pkt["type"]
        if t in ("spectator_state", "assign_id"):
            self._sync_snapshot(pkt)
            if t == "assign_id":
                pid = int(pkt["id"])
                if pid not in self.active:
                    F.fail("oracle.assign-not-active", f"{who}: assign_id {pid} but active={sorted(self.active)}")
                (self.waiting if self.state == "PLAYING" else self.playing).add(pid)
        elif t == "player_joined":
            pid = int(pkt["id"])
            self.active = ints(pkt["active_players"])
            self.names = {int(k): v for k, v in pkt["player_names"].items()}
            if pid not in self.active:
                F.fail("oracle.joined-not-active", f"{who}: player_joined {pid} but active={sorted(self.active)}")
            self.last_tick.pop(pid, None)   # (re)joined: movement sequence starts over
            if "playing_players" in pkt:
                self.playing = ints(pkt["playing_players"])
                if pid in self.playing:
                    self.waiting.discard(pid)
                    self.pending.pop(pid, None)
                    if self.state == "PLAYING" and self.stocks.get(pid, 3) > 0:
                        self.alive.add(pid)   # rejoined its held seat
                else:
                    self.waiting.add(pid)
            else:
                (self.waiting if self.state == "PLAYING" else self.playing).add(pid)
        elif t == "player_left":
            pid = int(pkt["id"])
            self.active = ints(pkt["active_players"])
            if pid in self.active:
                F.fail("oracle.left-still-active", f"{who}: player_left {pid} but active={sorted(self.active)}")
            if self.state == "PLAYING" and pid in self.playing:
                self.pending[pid] = now + REJOIN_GRACE + 1.0   # seat held; may come back
            self.playing.discard(pid)
            self.waiting.discard(pid)
            self.alive.discard(pid)
            self._check_alive_watchdog(now)
        elif t == "scene_transition":
            if self.state == "PLAYING":
                F.fail("oracle.transition-while-playing", f"{who}: scene_transition received while already PLAYING")
            self.state = "PLAYING"
            self.playing = set(self.active)
            self.waiting = set()
            self.alive = set(self.active)
            self.stocks = {p: 3 for p in self.active}
            self.scores = {p: 0 for p in (1, 2, 3, 4)}
            self.round = 1
            self.round_over = False
            self.round_end_at = None
            self.alive_le1_since = None
        elif t == "player_died":
            v, k, s = int(pkt["victim"]), int(pkt["killer"]), int(pkt["stock"])
            if self.state != "PLAYING":
                F.fail("oracle.died-in-lobby", f"{who}: player_died victim={v} while {self.state}")
            elif v not in self.alive:
                F.fail("oracle.died-not-alive", f"{who}: player_died victim={v} but alive={sorted(self.alive)} (waiting={sorted(self.waiting)})")
            else:
                expected = self.stocks.get(v, 3) - 1
                if s != expected:
                    F.fail("oracle.stock-mismatch", f"{who}: P{v} died, server says stock={s}, model expected {expected}")
            if k not in self.active and k != 0:
                F.fail("oracle.killer-not-active", f"{who}: killer={k} not in active={sorted(self.active)}")
            self.stocks[v] = s
            if s <= 0:
                self.alive.discard(v)
            self._check_alive_watchdog(now)
        elif t == "round_end":
            w, r = int(pkt["winner"]), int(pkt["round"])
            if self.state != "PLAYING":
                F.fail("oracle.round-end-in-lobby", f"{who}: round_end while {self.state}")
            if len(self.alive) >= 2:
                F.fail("oracle.round-end-early", f"{who}: round_end with {len(self.alive)} alive per model: {sorted(self.alive)}")
            elif len(self.alive) == 1 and w != next(iter(self.alive)):
                F.fail("oracle.round-end-winner", f"{who}: winner={w} but only alive={sorted(self.alive)}")
            if w > 0:
                got = int(pkt["scores"].get(str(w), -1))
                exp = self.scores.get(w, 0) + 1
                if got != exp:
                    F.fail("oracle.round-end-score", f"{who}: winner P{w} score={got}, expected {exp}")
            if r != self.round:
                F.fail("oracle.round-end-round-number", f"{who}: round_end round={r}, model round={self.round}")
            self.scores = {int(k): int(v) for k, v in pkt["scores"].items()}
            flagged = bool(pkt.get("match_over", False))
            top = max(self.scores.values()) if self.scores else 0
            if flagged and top < MATCH_SCORE_LIMIT:
                F.fail("oracle.match-over-early", f"{who}: match_over with best score {top} < {MATCH_SCORE_LIMIT}")
            if not flagged and top >= MATCH_SCORE_LIMIT:
                F.fail("oracle.match-over-missing", f"{who}: P{w} has {top} crowns but round_end lacks match_over")
            self.match_over = flagged
            self.round_over = True
            self.round_end_at = now
            self.alive_le1_since = None
            self.round_ends.append((r, w))
        elif t == "new_round":
            r = int(pkt["round"])
            if self.match_over:
                F.fail("oracle.new-round-after-match-over", f"{who}: new_round {r} after the match was already won")
            if not self.round_over:
                F.fail("oracle.new-round-without-round-end", f"{who}: new_round {r} but no round_end seen")
            if r != self.round + 1:
                F.fail("oracle.new-round-number", f"{who}: new_round round={r}, expected {self.round + 1}")
            self.round = r
            self.round_over = False
            self.round_end_at = None
            self.stocks = {p: 3 for p in self.playing}
            self.alive = set(self.playing) & self.active
            self._check_alive_watchdog(now)
        elif t == "return_to_lobby":
            self.state = "LOBBY"
            self.playing = set()
            self.waiting = set()
            self.alive = set()
            self.pending = {}
            self.round_over = False
            self.match_over = False
            self.round_end_at = None
            self.alive_le1_since = None
            self.locked = {}
        elif t == "sync_pos":
            snd, tick = int(pkt["sender"]), int(pkt["tick"])
            prev = self.last_tick.get(snd)
            # behind by up to 200 ticks (10 s) = reordered; further back = the sender
            # restarted its counter (reload / rejoin), which is a new sequence
            if prev is not None and ((tick - prev) & 0xFFFF) >= 0x8000 and ((prev - tick) & 0xFFFF) <= 200:
                F.fail("oracle.movement-out-of-order", f"{who}: P{snd} tick {tick} after {prev}")
            self.last_tick[snd] = tick
        elif t == "name_update":
            self.names = {int(k): v for k, v in pkt["player_names"].items()}
        elif t == "lock_in":
            self.locked[int(pkt["sender"])] = int(pkt["class"])


# ── Bot ──────────────────────────────────────────────────────────────────────
class Bot:
    def __init__(self, ctx, bot_id, name=None):
        self.ctx = ctx
        self.id = bot_id
        self.name = name or f"Bot{bot_id}"
        self.rng = random.Random(ctx.seed * 1000 + bot_id)
        self.F = ctx.findings
        self.model = Model()
        self.token = f"harness-{ctx.seed}-{bot_id}-{self.name}"   # client identity across reconnects
        self.ws = None
        self.open = False
        self.slot = None
        self.events = []                       # (t, type, pkt)
        self.cv = threading.Condition()
        self.recent = collections.OrderedDict()
        # metrics
        self.in_pkts = collections.Counter()
        self.in_bytes = collections.Counter()
        self.out_pkts = collections.Counter()
        self.out_bytes = collections.Counter()
        self.dups = collections.Counter()
        self.rtts = []
        self.connected_at = None
        # behaviour
        self.autoplay = False
        self.die_rate = ctx.args.die_rate
        self.dead = False
        self.dead_until = None
        self.invuln_until = 0.0
        self.pending_death_at = None
        self.match_started_at = None
        self.x = self.rng.uniform(40, ARENA_W - 40)
        self.y = self.rng.uniform(40, ARENA_H - 40)
        self.vx = self.rng.choice([-220.0, 0.0, 220.0])
        self.vy = 0.0
        self.aim = self.rng.uniform(-math.pi, math.pi)
        # fault injection (send path) and misbehaviour switches
        self.latency = 0.0        # seconds added to every send
        self.jitter = 0.0         # +/- seconds of random variation on top of latency
        self.loss = 0.0           # probability a packet is silently dropped
        self.dropped = 0
        self._delayed = []        # heap of (due, seq, raw) for latency simulation
        self._delayed_cv = threading.Condition()
        self._delayed_seq = 0
        self._delayed_thread = None
        self._last_due = 0.0        # latency+jitter never reorders (TCP cannot)
        self.paused_rx = False    # slow reader: stop draining the socket
        self.muted = False        # silent client: send nothing at all (not even pings)
        self.sockopt = None       # e.g. a tiny SO_RCVBUF for the slow-reader scenario
        self.last_sync_at = None  # inter-arrival tracking of relayed sync_pos
        self.max_sync_gap = 0.0
        self.tick = 0             # our movement sample counter
        self._last_sync_body = None
        self._last_sync_sent = 0.0

    def log(self, msg):
        if self.ctx.args.verbose:
            print(f"{time.strftime('%H:%M:%S')} [{self.name}] {msg}", flush=True)

    # -- connection ---------------------------------------------------------
    def connect(self):
        ws = websocket.WebSocket(sockopt=self.sockopt) if self.sockopt else websocket.WebSocket()
        ws.connect(f"ws://{self.ctx.args.host}:{self.ctx.args.port}")
        ws.settimeout(0.5)
        self.ws = ws
        self.open = True
        self.connected_at = time.monotonic()
        threading.Thread(target=self._receiver, daemon=True, name=f"{self.name}-rx").start()
        threading.Thread(target=self._ticker, daemon=True, name=f"{self.name}-tick").start()
        return self

    def disconnect(self):
        self.open = False
        try:
            self.ws.close()
        except Exception:
            pass

    def send(self, d, spoof_sender=None):
        d = dict(d)
        d["sender"] = spoof_sender if spoof_sender is not None else (self.slot or 0)
        self._dispatch(json.dumps(d, separators=(",", ":")), d["type"])

    def send_binary(self, b):
        pkt = decode_binary(b)
        self._dispatch(b, pkt["type"] if pkt else "<bad-binary>")

    def _dispatch(self, raw, type_name):
        if not self.open:
            return
        if self.muted:
            return
        if self.loss > 0 and self.rng.random() < self.loss:
            self.dropped += 1
            return
        if self.latency > 0:
            due = max(self._last_due, time.monotonic() + self.latency + self.rng.uniform(-self.jitter, self.jitter))
            self._last_due = due
            with self._delayed_cv:
                self._delayed_seq += 1
                heapq.heappush(self._delayed, (due, self._delayed_seq, raw))
                self._delayed_cv.notify()
            if self._delayed_thread is None:
                self._delayed_thread = threading.Thread(target=self._delayed_sender, daemon=True, name=f"{self.name}-lag")
                self._delayed_thread.start()
        elif not self._write(raw):
            return
        nbytes = len(raw) if isinstance(raw, (bytes, bytearray)) else len(raw.encode())
        self.out_pkts[type_name] += 1
        self.out_bytes[type_name] += nbytes
        tf = self.ctx.trace
        if tf is not None and type_name not in MOVEMENT_TYPES and type_name != "ping" and isinstance(raw, str):
            tf.write(json.dumps({"t": round(time.monotonic() - self.ctx.t0, 3), "bot": self.name,
                                 "slot": self.slot, "sent": json.loads(raw)}) + "\n")

    def _write(self, raw):
        try:
            if isinstance(raw, (bytes, bytearray)):
                self.ws.send(bytes(raw), websocket.ABNF.OPCODE_BINARY)
            else:
                self.ws.send(raw)
            return True
        except Exception as e:
            self.log(f"send failed: {e!r}")
            self.open = False
            return False

    def _delayed_sender(self):
        while self.open:
            with self._delayed_cv:
                while self.open and (not self._delayed or self._delayed[0][0] > time.monotonic()):
                    wait = (self._delayed[0][0] - time.monotonic()) if self._delayed else 0.25
                    self._delayed_cv.wait(max(0.001, min(wait, 0.25)))
                if not self.open:
                    return
                _, _, raw = heapq.heappop(self._delayed)
            self._write(raw)

    def send_raw_frame(self, frame):
        """Write a hand-built WebSocket frame straight to the socket (fuzzing)."""
        try:
            self.ws.sock.sendall(frame)
            return True
        except Exception as e:
            self.log(f"raw send failed: {e!r}")
            self.open = False
            return False

    # -- client actions -------------------------------------------------------
    def join(self, version=None, reclaim=0):
        self.send({"type": "request_join", "reclaim_id": reclaim, "token": self.token,
                   "version": version if version is not None else self.ctx.version})

    def report_death(self, victim, killer, weapon="Harness"):
        """Observer report: this bot saw `victim` die (need not be itself)."""
        self.send({"type": "player_died", "victim": victim, "killer": killer, "weapon": weapon})

    def set_name(self, name=None):
        self.send({"type": "set_name", "name": name or self.name})

    def lock_in(self, cls=None):
        self.send({"type": "lock_in", "class": self.rng.randint(0, 4) if cls is None else cls})

    def start_match(self):
        self.match_started_at = time.monotonic()
        self.send({"type": "match_started"})

    def die(self, killer=None):
        others = sorted(self.model.alive - {self.slot})
        if killer is None:
            killer = self.rng.choice(others) if others else self.slot
        self.send({"type": "player_died", "victim": self.slot, "killer": killer,
                   "weapon": self.rng.choice(["Arrow", "Melee", "Kunai", "Goomba Stomp"])})
        self.dead = True
        self.dead_until = None
        self.pending_death_at = time.monotonic()

    def wait_for(self, ptype, timeout, since=0, pred=None):
        """Wait for a packet of ptype received at event index >= since. Returns (index, pkt) or (None, None)."""
        deadline = time.monotonic() + timeout
        with self.cv:
            while True:
                for i in range(since, len(self.events)):
                    _, t, pkt = self.events[i]
                    if t == ptype and (pred is None or pred(pkt)):
                        return i, pkt
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not self.open:
                    return None, None
                self.cv.wait(min(remaining, 0.25))

    def mark(self):
        with self.cv:
            return len(self.events)

    def count(self, ptype, since=0):
        with self.cv:
            return sum(1 for _, t, _ in self.events[since:] if t == ptype)

    # -- receive path ---------------------------------------------------------
    def _receiver(self):
        while self.open:
            if self.paused_rx:
                time.sleep(0.05)
                continue
            try:
                raw = self.ws.recv()
            except websocket.WebSocketTimeoutException:
                continue
            except Exception:
                break
            if raw is None or raw == "":
                break
            self._on_packet(raw, time.monotonic())
        self.open = False
        with self.cv:
            self.cv.notify_all()

    def _on_packet(self, raw, now):
        if isinstance(raw, (bytes, bytearray)):
            raw = bytes(raw)
            pkt = decode_binary(raw)
            if pkt is None:
                self.F.fail("schema.bad-binary", f"{self.name}: {len(raw)} B, type {raw[0] if raw else '-'}")
                return
            size = len(raw)
        else:
            try:
                pkt = json.loads(raw)
            except ValueError:
                self.F.fail("schema.bad-json", f"{self.name}: {raw[:80]!r}")
                return
            if not isinstance(pkt, dict) or "type" not in pkt:
                self.F.fail("schema.no-type", f"{self.name}: {raw[:80]!r}")
                return
            size = len(raw.encode())
        t = str(pkt["type"])
        self.in_pkts[t] += 1
        self.in_bytes[t] += size
        if t == "sync_pos":
            if self.last_sync_at is not None:
                self.max_sync_gap = max(self.max_sync_gap, now - self.last_sync_at)
            self.last_sync_at = now

        # schema
        spec = SCHEMA.get(t)
        if spec is None:
            self.F.fail("schema.unknown-type", f"{self.name}: type={t!r} {str(raw)[:80]}")
        else:
            for field, expected in spec.items():
                if field not in pkt:
                    self.F.fail("schema.missing-field", f"{self.name}: {t} lacks {field!r}: {str(raw)[:100]}")
                elif not _type_ok(pkt[field], expected):
                    self.F.fail("schema.wrong-type", f"{self.name}: {t}.{field}={pkt[field]!r} not {getattr(expected, '__name__', expected)}")

        # duplicate broadcast detection
        prev = self.recent.get(raw)
        window = DUP_WINDOW_MOVEMENT if t in MOVEMENT_TYPES else DUP_WINDOW_EVENT
        dup = prev is not None and now - prev < window
        self.recent[raw] = now
        if len(self.recent) > 4000:
            for _ in range(2000):
                self.recent.popitem(last=False)
        if dup:
            self.dups[t] += 1
            kind = "dup.movement" if t in MOVEMENT_TYPES else "dup.event"
            self.F.fail(kind, f"{self.name}: {t} received twice within {(now - prev) * 1000:.1f} ms")
        else:
            if spec is not None:
                try:
                    self.model.apply(pkt, now, self.F, self.name)
                except (KeyError, TypeError, ValueError) as e:
                    self.F.fail("oracle.exception", f"{self.name}: {t}: {e!r}")
            self._react(t, pkt, now)

        with self.cv:
            self.events.append((now, t, pkt))
            self.cv.notify_all()
        tf = self.ctx.trace
        if tf is not None and t not in MOVEMENT_TYPES and t != "pong":
            m = self.model
            tf.write(json.dumps({"t": round(now - self.ctx.t0, 3), "bot": self.name, "slot": self.slot,
                                 "dup": dup, "pkt": pkt,
                                 "model": {"state": m.state, "alive": sorted(m.alive), "stocks": m.stocks,
                                           "round": m.round, "over": m.round_over}}) + "\n")

    def _react(self, t, pkt, now):
        if t == "assign_id":
            self.slot = int(pkt["id"])
            self.log(f"assigned P{self.slot} (match {pkt['match_state']})")
        elif t == "pong":
            if pkt.get("t") is not None:
                self.rtts.append((now - float(pkt["t"])) * 1000.0)
        elif t == "scene_transition":
            self.match_started_at = None
            self.dead = False
        elif t in ("new_round", "return_to_lobby"):
            self.dead = False
            self.dead_until = None
        elif t == "player_died" and self.slot and int(pkt["victim"]) == self.slot:
            self.pending_death_at = None
            self.dead = True
            self.dead_until = (now + RESPAWN_DELAY) if int(pkt["stock"]) > 0 else None
        elif t == "version_error":
            self.log(f"version_error: server wants {pkt.get('server_version')}")

    # -- tick loop: ping, watchdogs, autoplay traffic ---------------------------
    def _ticker(self):
        period = 1.0 / self.ctx.args.rate
        next_tick = time.monotonic()
        last_ping = 0.0
        while self.open:
            now = time.monotonic()
            if now - last_ping >= 1.0:
                self.send({"type": "ping", "t": now})
                last_ping = now
            self._watchdogs(now)
            if self.autoplay and self.slot and self.model.state == "PLAYING":
                if self.dead:
                    if self.dead_until is not None and now >= self.dead_until:
                        self.dead = False
                        self.dead_until = None
                        self.invuln_until = now + SPAWN_INVULN
                if not self.dead and self.slot in self.model.alive:
                    self._step_motion(period)
                    pkt = self._sync_bytes()
                    body = pkt[4:]                      # idle suppression, same rule as player.gd
                    if body != self._last_sync_body or now - self._last_sync_sent >= NET_IDLE_RESEND:
                        self._last_sync_body = body
                        self._last_sync_sent = now
                        self.tick = (self.tick + 1) & 0xFFFF
                        self.send_binary(pkt)
                    if self.rng.random() < 0.02:
                        self.send_binary(self._projectile_bytes())
                    if self.die_rate > 0 and now >= self.invuln_until and self.rng.random() < self.die_rate * period:
                        self.log(f"dying (stock before={self.model.stocks.get(self.slot)})")
                        self.die()
            next_tick += period
            time.sleep(max(0.0, next_tick - time.monotonic()))

    def _watchdogs(self, now):
        m = self.model
        m.expire_pending(now)
        if m.alive_le1_since is not None and now - m.alive_le1_since > 2.0:
            self.F.fail("timeout.round-end", f"{self.name}: alive={sorted(m.alive)} for >2 s with no round_end (round {m.round})")
            m.alive_le1_since = None
        grace = (MATCH_END_DELAY if m.match_over else NEXT_ROUND_DELAY) + 2.0
        if m.round_end_at is not None and now - m.round_end_at > grace:
            self.F.fail("timeout.next-round", f"{self.name}: no new_round / return_to_lobby {grace:.1f} s after round_end (match_over={m.match_over})")
            m.round_end_at = None
        if self.match_started_at is not None and now - self.match_started_at > 1.5:
            self.F.fail("timeout.scene-transition", f"{self.name}: sent match_started, no scene_transition within 1.5 s")
            self.match_started_at = None
        if self.pending_death_at is not None and now - self.pending_death_at > 1.0 + self.latency * 2:
            if self.loss > 0:            # our own injected loss may have eaten the packet
                self.pending_death_at = None
                self.dead = False
                return
            self.F.fail("oracle.death-not-echoed", f"{self.name}: sent player_died, server never broadcast it back")
            self.pending_death_at = None
            self.dead = False

    def _step_motion(self, dt):
        r = self.rng
        if r.random() < 0.05:
            self.vx = r.choice([-220.0, 0.0, 220.0])
        if r.random() < 0.03 and self.vy == 0.0:
            self.vy = -430.0
        self.vy = min(self.vy + 1150.0 * dt, 600.0)
        self.x += self.vx * dt
        self.y += self.vy * dt
        if self.x < -12:
            self.x = ARENA_W + 10
        elif self.x > ARENA_W + 12:
            self.x = -10
        if self.y > ARENA_H - 30:
            self.y = ARENA_H - 30
            self.vy = 0.0
        self.aim += r.uniform(-0.3, 0.3)

    def _sync_packet(self):
        return {"type": "sync_pos", "x": self.x, "y": self.y,
                "aim_x": math.cos(self.aim), "aim_y": math.sin(self.aim),
                "facing": math.cos(self.aim) > 0, "dash": self.rng.random() < 0.05,
                "shield": self.rng.random() < 0.03, "bear": False, "egg": False}

    def _sync_bytes(self):
        return encode_sync_pos(self.x, self.y, math.cos(self.aim), math.sin(self.aim),
                               facing=math.cos(self.aim) > 0, dash=self.rng.random() < 0.05,
                               shield=self.rng.random() < 0.03, tick=self.tick)

    def _projectile_bytes(self):
        return encode_projectile(self.rng.choice(WEAPONS), self.x + math.cos(self.aim) * 18.0,
                                 self.y + math.sin(self.aim) * 18.0, math.cos(self.aim), math.sin(self.aim))

    def _projectile_packet(self):
        return {"type": "spawn_projectile", "weapon": self.rng.choice(WEAPONS),
                "pos_x": self.x + math.cos(self.aim) * 18.0, "pos_y": self.y + math.sin(self.aim) * 18.0,
                "dir_x": math.cos(self.aim), "dir_y": math.sin(self.aim)}


# ── Scenario context ─────────────────────────────────────────────────────────
class Ctx:
    def __init__(self, args, version, seed):
        self.args = args
        self.version = version
        self.seed = seed
        self.findings = Findings()
        self.bots = []
        self.t0 = time.monotonic()
        self.trace = None            # JSONL file for --trace (non-movement packets + model snapshots)
        self.notes = []              # informational lines for the report (timings, counts)

    def bot(self, i, name=None):
        b = Bot(self, i, name)
        self.bots.append(b)
        return b

    def close_all(self):
        for b in self.bots:
            b.disconnect()

    def fail(self, name, detail):
        self.findings.fail(name, detail)

    def say(self, msg):
        print(f"    {time.monotonic() - self.t0:5.1f}s  {msg}", flush=True)

    def note(self, msg):
        self.notes.append(msg)
        self.say("note: " + msg)


def lobby_join(ctx, bots, lock=True):
    for b in bots:
        b.connect()
        _, st = b.wait_for("spectator_state", 3.0)
        if st is None:
            ctx.fail("timeout.spectator-state", f"{b.name}: no spectator_state after connect")
        b.join()
        _, pkt = b.wait_for("assign_id", 3.0)
        if pkt is None:
            ctx.fail("timeout.assign-id", f"{b.name}: no assign_id after request_join")
            continue
        if pkt.get("rejoined", False):
            ctx.fail("server.rejoined-on-fresh-join", f"{b.name}: a fresh lobby join was flagged rejoined")
        b.set_name()
        time.sleep(0.15)
        if lock:
            b.lock_in()
            time.sleep(0.1)
    slots = [b.slot for b in bots if b.slot]
    if len(set(slots)) != len(slots):
        ctx.fail("scenario.duplicate-slots", f"slots={slots}")
    return bots


def start_match(ctx, bots, starter):
    marks = {b: b.mark() for b in bots}
    starter.start_match()
    for b in bots:
        _, pkt = b.wait_for("scene_transition", 2.0, since=marks[b])
        if pkt is None:
            ctx.fail("timeout.scene-transition", f"{b.name}: no scene_transition after match_started")
    for b in bots:
        b.autoplay = True


def ensure_lobby(ctx):
    """The server keeps no idle reset: after a match empties it stays PLAYING.
    Probe, record the finding, and heal with the join-then-die workaround."""
    time.sleep(NEXT_ROUND_DELAY + 0.6)   # let server timers from the previous scenario fire
    probe = Bot(ctx, 90, "Probe").connect()
    _, st = probe.wait_for("spectator_state", 3.0)
    if st is None:
        ctx.fail("timeout.spectator-state", "Probe: no spectator_state")
        probe.disconnect()
        return
    if st["match_state"] == "LOBBY":
        probe.disconnect()
        return
    ctx.fail("precondition.server-not-lobby",
             f"server still {st['match_state']} with active={st['active_players']} before scenario (no idle reset)")
    ctx.say("server stuck in PLAYING with no players; applying join+die workaround")
    healer = Bot(ctx, 91, "Healer").connect()
    probe.join()
    healer.join()
    probe.wait_for("assign_id", 3.0)
    healer.wait_for("assign_id", 3.0)
    mark = probe.mark()
    time.sleep(0.3)
    # The server's round-end check uses a per-thread `active` list that is stale
    # for early joiners, so the LAST joiner (higher slot number) has to be the one
    # that dies. Slots are assigned in request order, which need not match ours.
    first, second = sorted([probe, healer], key=lambda b: b.slot or 0)
    second.send({"type": "player_died", "victim": second.slot or 0, "killer": first.slot or 0, "weapon": "Heal"})
    _, back = probe.wait_for("return_to_lobby", NEXT_ROUND_DELAY + 3.0, since=mark)
    if back is None:
        first.send({"type": "player_died", "victim": first.slot or 0, "killer": second.slot or 0, "weapon": "Heal"})
        _, back = probe.wait_for("return_to_lobby", NEXT_ROUND_DELAY + 3.0, since=mark)
    if back is None:
        ctx.fail("precondition.heal-failed", "server did not return to LOBBY after workaround")
    probe.disconnect()
    healer.disconnect()
    time.sleep(0.5)


# ── Scenarios ────────────────────────────────────────────────────────────────
SCENARIOS = {}


def scenario(name, desc):
    def deco(fn):
        SCENARIOS[name] = (desc, fn)
        return fn
    return deco


@scenario("smoke", "4 bots join, lock in, start, play with mortality; expect rounds to end and restart")
def sc_smoke(ctx):
    bots = [ctx.bot(i) for i in range(1, 5)]
    lobby_join(ctx, bots)
    start_match(ctx, bots, bots[0])
    for b in bots:
        b.die_rate = max(ctx.args.die_rate, 0.3)
    ctx.say("playing 20 s")
    time.sleep(20.0)
    for b in bots:
        if b.count("round_end") == 0:
            ctx.fail("scenario.smoke.no-round-end", f"{b.name}: no round_end in 20 s of play with mortality")
    # a round_end at the very end of the window is followed by new_round 2.6 s later
    for b in bots:
        if b.count("round_end") > 0 and b.count("new_round") == 0 and b.count("return_to_lobby") == 0:
            _, nr = b.wait_for("new_round", NEXT_ROUND_DELAY + 1.5)
            if nr is None and b.count("return_to_lobby") == 0:
                ctx.fail("scenario.smoke.no-next-round", f"{b.name}: no new_round after round_end")


@scenario("rounds", "3 bots, high mortality, three consecutive rounds with consistent numbering and scores")
def sc_rounds(ctx):
    bots = [ctx.bot(i) for i in range(1, 4)]
    lobby_join(ctx, bots)
    start_match(ctx, bots, bots[0])
    for b in bots:
        b.die_rate = 0.6
    deadline = time.monotonic() + 45.0
    while time.monotonic() < deadline and bots[0].count("round_end") < 3:
        time.sleep(0.25)
    ends = bots[0].model.round_ends
    if len(ends) < 3:
        ctx.fail("scenario.rounds.too-few", f"only {len(ends)} round_end in 45 s: {ends}")
    rounds = [r for r, _ in ends]
    if rounds != list(range(1, len(rounds) + 1)):
        ctx.fail("scenario.rounds.numbering", f"round_end rounds={rounds}")
    wins = sum(1 for _, w in ends if w > 0)
    total = sum(bots[0].model.scores.values())
    if total != wins:
        ctx.fail("scenario.rounds.score-sum", f"scores sum {total} but {wins} rounds had a winner")


@scenario("disconnect_mid_round", "one of 3 players drops mid-round; others see player_left and can still finish the round")
def sc_disconnect(ctx):
    bots = [ctx.bot(i) for i in range(1, 4)]
    lobby_join(ctx, bots)
    start_match(ctx, bots, bots[0])
    time.sleep(4.0)
    leaver = bots[2]
    marks = {b: b.mark() for b in bots[:2]}
    ctx.say(f"{leaver.name} (P{leaver.slot}) drops")
    leaver.disconnect()
    for b in bots[:2]:
        _, pkt = b.wait_for("player_left", 2.0, since=marks[b], pred=lambda p: int(p["id"]) == leaver.slot)
        if pkt is None:
            ctx.fail("scenario.disconnect.no-player-left", f"{b.name}: no player_left for P{leaver.slot} within 2 s")
    for b in bots[:2]:
        b.die_rate = 0.6
    m = bots[0].mark()
    _, end = bots[0].wait_for("round_end", 25.0, since=m)
    if end is None:
        ctx.fail("scenario.disconnect.no-round-end", "remaining players could not finish a round in 25 s")
    elif int(end["winner"]) not in {bots[0].slot, bots[1].slot, 0}:
        ctx.fail("scenario.disconnect.winner", f"winner={end['winner']} is not a remaining player")


@scenario("spectator_mid_match", "a client connecting mid-match gets a PLAYING snapshot; joining queues it and the match returns to lobby after the round")
def sc_spectator(ctx):
    bots = [ctx.bot(1), ctx.bot(2)]
    lobby_join(ctx, bots)
    start_match(ctx, bots, bots[0])
    time.sleep(2.0)
    late = ctx.bot(3, "Late").connect()
    _, st = late.wait_for("spectator_state", 3.0)
    if st is None:
        ctx.fail("scenario.spectator.no-state", "late client got no spectator_state")
    else:
        if st["match_state"] != "PLAYING":
            ctx.fail("scenario.spectator.state", f"late client sees match_state={st['match_state']}")
        if ints(st["active_players"]) != {b.slot for b in bots}:
            ctx.fail("scenario.spectator.active", f"late client sees active={st['active_players']}, expected {[b.slot for b in bots]}")
    late.join()
    _, aid = late.wait_for("assign_id", 3.0)
    if aid is None:
        ctx.fail("scenario.spectator.no-assign", "late client could not join mid-match")
    elif aid["match_state"] != "PLAYING":
        ctx.fail("scenario.spectator.assign-state", f"assign_id match_state={aid['match_state']}")
    for b in bots:
        b.die_rate = 0.8
    m = late.mark()
    _, end = late.wait_for("round_end", 25.0, since=m)
    if end is None:
        ctx.fail("scenario.spectator.no-round-end", "round did not end in 25 s")
    else:
        _, back = late.wait_for("return_to_lobby", NEXT_ROUND_DELAY + 2.0, since=m)
        if back is None:
            ctx.fail("scenario.spectator.no-return-to-lobby", "waiting player present but no return_to_lobby after round_end")


@scenario("reclaim", "a dropped player reclaims its slot; a hot reclaim evicts the old socket")
def sc_reclaim(ctx):
    a = ctx.bot(1, "A").connect()
    a.wait_for("spectator_state", 3.0)
    a.join()
    _, aid = a.wait_for("assign_id", 3.0)
    if aid is None:
        ctx.fail("timeout.assign-id", "A: no assign_id")
        return
    slot = a.slot
    a.disconnect()
    time.sleep(0.6)
    a2 = ctx.bot(2, "A-again")
    a2.token = a.token
    a2.connect()
    a2.wait_for("spectator_state", 3.0)
    a2.join(reclaim=slot)
    _, aid2 = a2.wait_for("assign_id", 3.0)
    if aid2 is None:
        ctx.fail("scenario.reclaim.no-assign", "reclaim after drop got no assign_id")
    elif a2.slot != slot:
        ctx.fail("scenario.reclaim.slot-mismatch", f"reclaimed {a2.slot}, expected {slot}")
    # hot reclaim: old socket still open (page reload before timeout)
    b = ctx.bot(3, "B").connect()
    b.wait_for("spectator_state", 3.0)
    b.join()
    b.wait_for("assign_id", 3.0)
    bslot = b.slot
    b2 = ctx.bot(4, "B-reload")
    b2.token = b.token
    b2.connect()
    b2.wait_for("spectator_state", 3.0)
    b2.join(reclaim=bslot)
    _, bid2 = b2.wait_for("assign_id", 3.0)
    if bid2 is None or b2.slot != bslot:
        ctx.fail("scenario.reclaim.hot-slot", f"hot reclaim got slot {b2.slot}, expected {bslot}")
    deadline = time.monotonic() + 3.0
    while b.open and time.monotonic() < deadline:
        time.sleep(0.1)
    if b.open:
        ctx.fail("scenario.reclaim.old-socket-open", "old socket still open 3 s after its slot was reclaimed")
    # a stranger (different token) asking for an occupied slot gets the lowest free one instead
    c = ctx.bot(5, "Stranger").connect()
    c.wait_for("spectator_state", 3.0)
    c.join(reclaim=bslot)
    _, cid = c.wait_for("assign_id", 3.0)
    if cid is None:
        ctx.fail("scenario.reclaim.stranger-no-slot", "stranger got no slot at all")
    elif c.slot == bslot:
        ctx.fail("server.reclaim-without-token", f"a client with a different token took occupied slot {bslot}")
    if not b2.open:
        ctx.fail("server.reclaim-without-token", "the legitimate holder was evicted by a stranger's reclaim")


@scenario("server_full", "a fifth client asking for a slot is told server_full and keeps receiving as a spectator")
def sc_full(ctx):
    bots = [ctx.bot(i) for i in range(1, 5)]
    lobby_join(ctx, bots, lock=False)
    fifth = ctx.bot(5, "Fifth").connect()
    fifth.wait_for("spectator_state", 3.0)
    m = fifth.mark()
    fifth.join()
    _, full = fifth.wait_for("server_full", 2.0, since=m)
    if full is None:
        ctx.fail("scenario.server-full.not-rejected", "fifth client got no server_full")
    m2 = fifth.mark()
    bots[0].set_name("Renamed")
    _, upd = fifth.wait_for("name_update", 2.0, since=m2)
    if upd is None:
        ctx.fail("scenario.server-full.spectator-not-receiving", "fifth client did not receive a broadcast as spectator")


@scenario("version_mismatch", "a stale build is refused with version_error; the right version then joins")
def sc_version(ctx):
    b = ctx.bot(1).connect()
    b.wait_for("spectator_state", 3.0)
    m = b.mark()
    b.join(version="v9.9.9")
    _, err = b.wait_for("version_error", 2.0, since=m)
    if err is None:
        ctx.fail("scenario.version.not-rejected", "stale version was not refused")
    elif err["server_version"] != ctx.version:
        ctx.fail("scenario.version.server-version", f"server_version={err['server_version']}, expected {ctx.version}")
    if b.count("assign_id") > 0:
        ctx.fail("scenario.version.assigned-anyway", "stale client received assign_id")
    b.join()
    _, aid = b.wait_for("assign_id", 3.0)
    if aid is None:
        ctx.fail("scenario.version.good-refused", "correct version was not assigned a slot")


@scenario("double_force_start", "two clients send match_started at once; everyone must get exactly one scene_transition")
def sc_double_start(ctx):
    bots = [ctx.bot(i) for i in range(1, 5)]
    lobby_join(ctx, bots)
    marks = {b: b.mark() for b in bots}
    bots[0].send({"type": "match_started"})
    bots[1].send({"type": "match_started"})
    time.sleep(2.0)
    for b in bots:
        n = b.count("scene_transition", since=marks[b])
        if n != 1:
            ctx.fail("scenario.double-start.transition-count", f"{b.name}: {n} scene_transition packets, expected 1")


@scenario("match_end", f"one player wins {MATCH_SCORE_LIMIT} rounds; round_end carries match_over, the lobby follows, no new_round")
def sc_match_end(ctx):
    champ, victim = ctx.bot(1, "Champ"), ctx.bot(2, "Victim")
    lobby_join(ctx, [champ, victim])
    start_match(ctx, [champ, victim], champ)
    champ.die_rate = 0.0
    victim.die_rate = 2.0
    m = champ.mark()
    _, end = champ.wait_for("round_end", 90.0, since=m, pred=lambda p: bool(p.get("match_over")))
    if end is None:
        ctx.fail("scenario.match-end.no-match-over", f"no round_end with match_over in 90 s (rounds seen: {champ.model.round_ends})")
        return
    if int(end["winner"]) != champ.slot:
        ctx.fail("scenario.match-end.winner", f"match winner={end['winner']}, expected P{champ.slot}")
    if int(end["scores"].get(str(champ.slot), 0)) != MATCH_SCORE_LIMIT:
        ctx.fail("scenario.match-end.score", f"winner score={end['scores']}, expected {MATCH_SCORE_LIMIT}")
    if len(champ.model.round_ends) != MATCH_SCORE_LIMIT:
        ctx.fail("scenario.match-end.round-count", f"{len(champ.model.round_ends)} round_end packets, expected {MATCH_SCORE_LIMIT}")
    m2 = champ.mark()
    _, back = champ.wait_for("return_to_lobby", MATCH_END_DELAY + 2.0, since=m2)
    if back is None:
        ctx.fail("scenario.match-end.no-return-to-lobby", f"no return_to_lobby within {MATCH_END_DELAY + 2.0:.0f} s of the match ending")
    if champ.count("new_round", since=m2) > 0:
        ctx.fail("scenario.match-end.new-round-after-win", "server started another round after the match was won")


# ── Fault injection / fuzz helpers ───────────────────────────────────────────
def ws_frame(payload, opcode=1, claimed_len=None):
    """Hand-built client->server frame (masked). claimed_len lies in the length header."""
    n = len(payload) if claimed_len is None else claimed_len
    b1 = 0x80 | opcode
    if n <= 125:
        hdr = bytes([b1, 0x80 | n])
    elif n <= 65535:
        hdr = bytes([b1, 0x80 | 126]) + struct.pack(">H", n)
    else:
        hdr = bytes([b1, 0x80 | 127]) + struct.pack(">Q", n)
    mask = bytes([0x12, 0x34, 0x56, 0x78])
    body = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
    return hdr + mask + body


def server_pid():
    out = subprocess.run(["pgrep", "-f", "^python3 serve_game.py"], capture_output=True, text=True).stdout.split()
    return int(out[0]) if out else None


def server_proc_stats():
    """RSS / threads / open fds of the local server process (None if not local)."""
    pid = server_pid()
    if pid is None:
        return None
    st = {"pid": pid}
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    st["rss_kb"] = int(line.split()[1])
                elif line.startswith("Threads:"):
                    st["threads"] = int(line.split()[1])
        st["fds"] = len(os.listdir(f"/proc/{pid}/fd"))
    except OSError:
        return None
    return st


def server_sendq_for(client_port, server_port):
    """Bytes the local server has queued (kernel Send-Q) towards one client socket."""
    out = subprocess.run(["ss", "-tn", "state", "established"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[2].endswith(f":{server_port}") and parts[3].endswith(f":{client_port}"):
            try:
                return int(parts[1])
            except ValueError:
                return None
    return None


HARNESS_LOG_DIR = os.path.join(ROOT, ".harness_logs")


class GodotClient:
    """A real headless Godot client (global.gd --autojoin). Its log is the
    assertion surface: any SCRIPT ERROR / ERROR: line fails the scenario."""
    def __init__(self, ctx, idx, cls):
        self.ctx = ctx
        self.idx = idx
        self.cls = cls
        self.name = f"Godot{idx}"
        os.makedirs(HARNESS_LOG_DIR, exist_ok=True)
        self.log_path = os.path.join(HARNESS_LOG_DIR, f"{self.name.lower()}.log")
        self.proc = None
        self.logf = None

    def start(self):
        self.logf = open(self.log_path, "w")
        self.proc = subprocess.Popen(
            ["godot", "--headless", "--path", ROOT, "--", "--autojoin", f"--name={self.name}",
             f"--class={self.cls}", f"--server=ws://{self.ctx.args.host}:{self.ctx.args.port}"],
            stdout=self.logf, stderr=subprocess.STDOUT)
        return self

    def alive(self):
        return self.proc is not None and self.proc.poll() is None

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait()
        if self.logf:
            self.logf.close()

    def text(self):
        try:
            with open(self.log_path, encoding="utf-8", errors="replace") as f:
                return f.read()
        except OSError:
            return ""

    def errors(self):
        seen = collections.OrderedDict()
        for line in self.text().splitlines():
            s = line.strip()
            if "SCRIPT ERROR" in s or s.startswith("ERROR:"):
                seen[s] = seen.get(s, 0) + 1
        return seen

    def stats(self):
        t = self.text()
        out_sync = sum(int(m) for m in re.findall(r"out: [^|\n]*?sync_pos=(\d+)", t))
        return {"assigned": "Assigned Player ID" in t, "netstats_lines": t.count("[NetStats"),
                "out_sync_pos": out_sync}


# ── Step-2 scenarios: fleet, fuzz, fault injection ───────────────────────────
@scenario("lag", "one of 3 players has 150 ms +/- 50 ms latency and 10% loss on its send path; the match must still run clean")
def sc_lag(ctx):
    bots = [ctx.bot(i) for i in range(1, 4)]
    lobby_join(ctx, bots)
    start_match(ctx, bots, bots[0])
    laggy = bots[2]
    laggy.latency, laggy.jitter, laggy.loss = 0.150, 0.050, 0.10
    for b in bots:
        b.die_rate = 0.4
    time.sleep(25.0)
    if bots[0].count("round_end") == 0:
        ctx.fail("scenario.lag.no-round-end", "no round_end in 25 s with a lagging player in the match")
    ctx.note(f"laggy bot dropped {laggy.dropped} packets on purpose; rounds ended: {len(bots[0].model.round_ends)}")


@scenario("silent_client", "a client that sends nothing for 20 s (hidden browser tab) keeps its seat and keeps receiving; only a dead TCP peer is dropped")
def sc_silent_client(ctx):
    bots = [ctx.bot(i) for i in range(1, 4)]
    lobby_join(ctx, bots)
    start_match(ctx, bots, bots[0])
    for b in bots:
        b.die_rate = 0.0
    time.sleep(2.0)
    ghost = bots[2]
    m = bots[0].mark()
    mg = ghost.mark()
    ghost.muted = True
    ctx.say(f"{ghost.name} (P{ghost.slot}) goes silent for 20 s (still reading)")
    _, left = bots[0].wait_for("player_left", 20.0, since=m, pred=lambda p: int(p["id"]) == ghost.slot)
    if left is not None:
        ctx.fail("server.silent-client-dropped", "a connected client that merely stopped sending was dropped (hidden tabs do this for minutes)")
    if ghost.count("sync_pos", since=mg) == 0:
        ctx.fail("server.silent-client-not-served", "the silent client stopped receiving relayed movement")
    ghost.muted = False
    m2 = ghost.mark()
    ghost.send({"type": "ping", "t": time.monotonic()})
    _, pong = ghost.wait_for("pong", 2.0, since=m2)
    if pong is None:
        ctx.fail("server.silent-client-socket-dead", "the silent client could not resume after 20 s")
    else:
        ctx.note("silent client kept its seat for 20 s and resumed")


@scenario("reload_mid_match", "a fighter disconnects mid-round (page reload) and rejoins with its token within the grace: same seat, still in the match, no forfeit")
def sc_reload_mid_match(ctx):
    a, b = ctx.bot(1, "A"), ctx.bot(2, "B")
    lobby_join(ctx, [a, b])
    start_match(ctx, [a, b], a)
    a.die_rate = b.die_rate = 0.0
    time.sleep(3.0)
    bslot = b.slot
    m = a.mark()
    b.disconnect()
    ctx.say(f"B (P{bslot}) drops")
    _, left = a.wait_for("player_left", 3.0, since=m, pred=lambda p: int(p["id"]) == bslot)
    if left is None:
        ctx.fail("scenario.rejoin.no-player-left", "no player_left when B dropped")
    time.sleep(2.0)
    if a.count("round_end", since=m) > 0:
        ctx.fail("server.forfeit-before-grace", f"round ended 2 s after a disconnect; the seat should be held {REJOIN_GRACE:g} s")
    b2 = ctx.bot(3, "B-reloaded")
    b2.token = b.token
    b2.tick = (b.tick + 100) & 0xFFFF     # the real client continues its counter across a reload
    b2.connect()
    b2.wait_for("spectator_state", 3.0)
    b2.join(reclaim=bslot)
    _, aid = b2.wait_for("assign_id", 3.0)
    if aid is None:
        ctx.fail("scenario.rejoin.no-assign", "rejoin after reload got no assign_id")
        return
    if b2.slot != bslot:
        ctx.fail("scenario.rejoin.slot", f"rejoined as P{b2.slot}, expected P{bslot}")
    if aid["match_state"] != "PLAYING":
        ctx.fail("scenario.rejoin.state", f"rejoin landed in {aid['match_state']}, expected PLAYING")
    if bslot not in ints(aid["playing_players"]):
        ctx.fail("scenario.rejoin.not-playing", f"rejoined player is not in playing_players={aid['playing_players']}")
    if not aid.get("rejoined", False):
        ctx.fail("scenario.rejoin.flag", "assign_id after a mid-match reload lacks rejoined=true (client would hand out a fresh quiver)")
    _, joined = a.wait_for("player_joined", 3.0, since=m, pred=lambda p: int(p["id"]) == bslot)
    if joined is None:
        ctx.fail("scenario.rejoin.no-player-joined", "the other player never heard the rejoin")
    elif bslot not in ints(joined.get("playing_players", [])):
        ctx.fail("scenario.rejoin.joined-not-playing", "player_joined for the rejoin lacks the seat in playing_players")
    b2.autoplay = True
    time.sleep(REJOIN_GRACE + 1.0)
    if a.count("round_end", since=m) > 0:
        ctx.fail("scenario.rejoin.round-ended", "the round ended even though the fighter came back in time")
    else:
        ctx.note("reload mid-match: same seat, still fighting, no forfeit")


@scenario("simultaneous_leave", "both fighters press leave within half a second: no forfeit win, straight back to the lobby")
def sc_simultaneous_leave(ctx):
    a, b = ctx.bot(1, "A"), ctx.bot(2, "B")
    lobby_join(ctx, [a, b])
    start_match(ctx, [a, b], a)
    a.die_rate = b.die_rate = 0.0
    time.sleep(2.0)
    m = a.mark()
    a.send({"type": "leave_slot"})
    time.sleep(0.3)
    b.send({"type": "leave_slot"})
    a.autoplay = b.autoplay = False
    _, back = a.wait_for("return_to_lobby", FORFEIT_GRACE + NEXT_ROUND_DELAY + 3.0, since=m)
    if back is None:
        ctx.fail("scenario.simultaneous-leave.no-lobby", "no return_to_lobby after both players left")
    for _, t, pkt in list(a.events[m:]):
        if t == "round_end" and int(pkt.get("winner", 0)) > 0:
            ctx.fail("server.accidental-forfeit", f"P{pkt['winner']} was awarded the round although both players left within 0.3 s")
            break
    else:
        ctx.note("both left: no winner awarded, lobby reached")


@scenario("observer_death", "any client may report a death; the first report counts once, repeats inside the dedupe window are ignored")
def sc_observer_death(ctx):
    bots = [ctx.bot(i) for i in range(1, 4)]
    lobby_join(ctx, bots)
    start_match(ctx, bots, bots[0])
    for b in bots:
        b.die_rate = 0.0
    time.sleep(1.5)
    a, victim, observer = bots
    m = a.mark()
    observer.report_death(victim.slot, observer.slot, "Melee")
    time.sleep(0.2)
    a.report_death(victim.slot, a.slot, "Arrow")          # the same death seen from another screen
    time.sleep(1.0)
    deaths = [pkt for _, t, pkt in list(a.events[m:]) if t == "player_died" and int(pkt["victim"]) == victim.slot]
    if len(deaths) != 1:
        ctx.fail("server.death-dedupe", f"{len(deaths)} player_died broadcasts for one death reported by two clients")
    elif int(deaths[0]["stock"]) != 2:
        ctx.fail("server.observer-death-stock", f"stock after an observer-reported death = {deaths[0]['stock']}, expected 2")
    time.sleep(DEATH_DEDUPE_S + 0.5)
    m2 = a.mark()
    observer.report_death(victim.slot, observer.slot, "Melee")
    _, d2 = a.wait_for("player_died", 2.0, since=m2, pred=lambda p: int(p["victim"]) == victim.slot)
    if d2 is None:
        ctx.fail("server.observer-death-rejected", "a second, later death report from an observer was not accepted")
    elif int(d2["stock"]) != 1:
        ctx.fail("server.observer-death-stock", f"stock after the second death = {d2['stock']}, expected 1")
    else:
        ctx.note("observer-reported deaths: counted once, deduped, stocks 3 -> 2 -> 1")


@scenario("slow_reader", "a client stops reading; the others must keep receiving (no head-of-line blocking) and the stalled client must be dropped within ~35 s")
def sc_slow_reader(ctx):
    bots = [ctx.bot(1), ctx.bot(2)]
    slow = ctx.bot(3, "SlowReader")
    slow.sockopt = ((socket.SOL_SOCKET, socket.SO_RCVBUF, 4096),)
    lobby_join(ctx, bots + [slow])
    start_match(ctx, bots + [slow], bots[0])
    for b in bots + [slow]:
        b.die_rate = 0.0
    time.sleep(3.0)
    bots[0].max_sync_gap = 0.0
    bots[1].max_sync_gap = 0.0
    m = bots[0].mark()
    t0 = time.monotonic()
    slow_port = slow.ws.sock.getsockname()[1]
    slow.paused_rx = True
    ctx.say(f"{slow.name} (P{slow.slot}) stops reading (still sending)")
    backlog = []
    for _ in range(4):
        time.sleep(5.0)
        q = server_sendq_for(slow_port, ctx.args.port)
        backlog.append(q)
    gap = max(bots[0].max_sync_gap, bots[1].max_sync_gap)
    if gap > 1.0:
        ctx.fail("server.head-of-line-blocking",
                 f"other players saw a {gap:.1f} s gap in relayed sync_pos while one client stopped reading (blocking sendall in broadcast)")
    ctx.note(f"max sync_pos gap seen by the other players during the stall: {gap:.2f} s")
    qs = [q for q in backlog if q is not None]
    if qs:
        rate = (qs[-1] - qs[0]) / 15.0 if len(qs) >= 2 else 0.0
        ctx.note(f"server Send-Q towards the stalled client at 5/10/15/20 s: {', '.join(f'{q // 1024} KB' for q in qs)} ({rate / 1024:.1f} KB/s)")
        if qs[-1] > 64 * 1024:
            eta = f"; at this rate a 4 MB kernel send buffer fills in ~{4 * 1024 * 1024 / rate / 60:.0f} min, after which every other player stalls up to 10 s per broadcast" if rate > 0 else ""
            ctx.fail("server.no-backpressure",
                     f"{qs[-1] // 1024} KB queued in the kernel for a client that stopped reading 20 s ago; nothing detects or drops it{eta}")
    _, left = bots[0].wait_for("player_left", 15.0, since=m, pred=lambda p: int(p["id"]) == slow.slot)
    if left is None:
        ctx.fail("server.stalled-reader-tolerated", "a client that has not read for 35 s is still a member of the match (send queue / stall detection missing)")
    else:
        ctx.note(f"slow reader dropped after {time.monotonic() - t0:.1f} s (server stall detection)")
    slow.paused_rx = False


@scenario("fuzz", "malformed and hostile frames from a joined client; the server must survive, keep relaying and reject oversized frames")
def sc_fuzz(ctx):
    bots = [ctx.bot(1), ctx.bot(2)]
    fz = ctx.bot(3, "Fuzzer")
    lobby_join(ctx, bots + [fz])
    start_match(ctx, bots + [fz], bots[0])
    fz.autoplay = False
    for b in bots:
        b.die_rate = 0.0

    def alive(label):
        m = fz.mark()
        fz.send({"type": "ping", "t": time.monotonic()})
        _, pong = fz.wait_for("pong", 2.0, since=m)
        if pong is None:
            ctx.fail(f"fuzz.{label}.server-unresponsive", f"no pong within 2 s after '{label}'")
        return pong is not None

    def relaying(label):
        m = bots[0].mark()
        time.sleep(0.5)
        if bots[0].count("sync_pos", since=m) == 0:
            ctx.fail(f"fuzz.{label}.relay-stalled", f"other players received nothing for 0.5 s after '{label}'")

    fz._write("{this is not json")
    alive("bad-json"); relaying("bad-json")
    fz._write("[1, 2, 3]")
    alive("non-object"); relaying("non-object")
    fz._write('{"type":"player_died","victim":"abc","killer":null,"weapon":5}')
    alive("wrong-types"); relaying("wrong-types")
    fz._write('{"type":"player_died","victim":99,"killer":-1}')
    alive("out-of-range-ids"); relaying("out-of-range-ids")
    m = bots[0].mark()
    fz._write('{"type":"new_round","round":99}')
    time.sleep(0.5)
    if bots[0].count("new_round", since=m) > 0:
        ctx.fail("server.server-only-type-relayed", "a client-sent new_round reached the other players")
    alive("server-only-type")
    # binary frames: JSON inside a binary frame, bad type byte, wrong length -> all dropped, server alive
    fz.send_raw_frame(ws_frame(json.dumps(fz._sync_packet() | {"sender": fz.slot}).encode(), opcode=2))
    alive("json-in-binary"); relaying("json-in-binary")
    fz.send_raw_frame(ws_frame(bytes([99, 0, 1, 2, 3, 4, 5, 6, 7]), opcode=2))
    alive("binary-bad-type"); relaying("binary-bad-type")
    fz.send_raw_frame(ws_frame(bytes([1, 0, 1, 2, 3]), opcode=2))
    alive("binary-wrong-length"); relaying("binary-wrong-length")
    fz.send_raw_frame(ws_frame(bytes([1, 0]) + bytes(7), opcode=2))   # old 9-byte sync_pos layout
    alive("binary-old-layout"); relaying("binary-old-layout")

    # sender spoofing in the binary header: the server must stamp the real slot
    m = bots[1].mark()
    fz.tick = (fz.tick + 1) & 0xFFFF
    fz.send_binary(encode_sync_pos(123.4, 56.7, 1.0, 0.0, sender=bots[0].slot, tick=fz.tick))
    _, got = bots[1].wait_for("sync_pos", 1.5, since=m, pred=lambda p: abs(p["x"] - 123.4) < 0.06 and abs(p["y"] - 56.7) < 0.06)
    if got is None:
        ctx.fail("fuzz.spoof.not-relayed", "spoofed-sender movement packet never reached the other players")
    elif int(got["sender"]) != fz.slot:
        ctx.fail("server.binary-sender-not-stamped", f"movement packet relayed with sender={got['sender']} (claimed) instead of P{fz.slot}")

    # flood: 3000 movement packets as fast as the socket takes them
    t0 = time.monotonic()
    for _ in range(3000):
        fz.x = (fz.x + 0.7) % ARENA_W     # guarantee every packet differs after 0.1 px quantisation
        fz.tick = (fz.tick + 1) & 0xFFFF
        fz._write(fz._sync_bytes())
    m = fz.mark()
    fz.send({"type": "ping", "t": time.monotonic()})
    _, pong = fz.wait_for("pong", 10.0, since=m)
    if pong is None:
        ctx.fail("fuzz.flood.server-unresponsive", "no pong within 10 s after a 3000-packet burst")
    else:
        ctx.note(f"3000-packet burst drained in {time.monotonic() - t0:.2f} s (pong after the burst)")
    relaying("flood")

    # text message above the relay cap but below the frame cap: must be dropped, not relayed
    m = bots[0].mark()
    fz._write(json.dumps({"type": "chatter", "pad": "x" * 2000}, separators=(",", ":")))
    time.sleep(0.8)
    if bots[0].count("chatter", since=m) > 0:
        ctx.fail("server.large-frame-relayed", "a 2 KB text message was relayed to every player: no payload size cap")
    alive("large-payload")

    # text frame above the frame cap (5 KB real payload): the server must close the socket
    t0 = time.monotonic()
    fz._write(json.dumps({"type": "chatter", "pad": "x" * 5000}, separators=(",", ":")))
    deadline = time.monotonic() + 3.0
    while fz.open and time.monotonic() < deadline:
        time.sleep(0.05)
    if fz.open:
        ctx.fail("server.over-cap-frame-accepted", "a 5 KB frame (cap 4 KB) did not get the connection closed")
    else:
        ctx.note(f"5 KB frame: connection closed in {time.monotonic() - t0:.2f} s")
    relaying("over-cap-frame")

    # oversized length header: claims 64 MB, sends 64 bytes. The reader must not
    # trust the header (allocation / thread stall); the connection should close fast.
    # A fresh spectator connection is enough: frames are read before slot checks.
    fz2 = ctx.bot(4, "Fuzzer2").connect()
    fz2.wait_for("spectator_state", 3.0)
    st0 = server_proc_stats()
    t0 = time.monotonic()
    fz2.send_raw_frame(ws_frame(b"x" * 64, claimed_len=64 * 1024 * 1024))
    deadline = time.monotonic() + 3.0
    while fz2.open and time.monotonic() < deadline:
        time.sleep(0.05)
    st1 = server_proc_stats()
    rss = f", server RSS {st0['rss_kb'] // 1024} -> {st1['rss_kb'] // 1024} MB" if st0 and st1 else ""
    if fz2.open:
        deadline = time.monotonic() + 15.0
        while fz2.open and time.monotonic() < deadline:
            time.sleep(0.1)
        closed = "never closed" if fz2.open else f"closed after {time.monotonic() - t0:.1f} s"
        ctx.fail("server.oversized-frame-not-rejected",
                 f"frame header claiming 64 MB was accepted: reader waits for the whole payload ({closed}{rss}); no frame length cap")
    else:
        ctx.note(f"oversized frame header rejected in {time.monotonic() - t0:.2f} s{rss}")
    relaying("oversized-header")


@scenario("fleet", "N headless Godot clients (--godot) fight bots for --duration s; fails on any client script error")
def sc_fleet(ctx):
    if shutil.which("godot") is None:
        ctx.fail("fleet.no-godot", "godot binary not on PATH")
        return
    n = max(1, min(int(ctx.args.godot), 4))
    bots = [ctx.bot(i) for i in range(1, 5 - n)]
    if bots:
        lobby_join(ctx, bots)
    clients = [GodotClient(ctx, i + 1, cls=(i + 1) % 5).start() for i in range(n)]
    ctx.say(f"{n} headless Godot client(s) starting, {len(bots)} bot(s)")
    deadline = time.monotonic() + 20.0
    while time.monotonic() < deadline:
        if bots and len(bots[0].model.active) >= n + len(bots):
            break
        if not bots and all("Assigned Player ID" in c.text() for c in clients):
            break
        time.sleep(0.25)
    if bots:
        start_match(ctx, bots, bots[0])
        for b in bots:
            b.die_rate = 0.3
    dur = ctx.args.duration
    ctx.say(f"playing {dur:.0f} s")
    time.sleep(dur)
    for c in clients:
        if not c.alive():
            ctx.fail("fleet.client-exited", f"{c.name} exited early (code {c.proc.returncode})")
        errs = c.errors()
        for line, count in errs.items():
            ctx.fail("fleet.script-error", f"{c.name}: {line} (x{count})")
        st = c.stats()
        if not st["assigned"]:
            ctx.fail("fleet.not-assigned", f"{c.name} never got a player slot")
        if st["out_sync_pos"] == 0:
            ctx.fail("fleet.client-silent", f"{c.name} never sent movement (not in the arena, or dead all along)")
        ctx.note(f"{c.name}: {st['netstats_lines']} NetStats lines, {st['out_sync_pos']} sync_pos sent, {len(errs)} error kinds, log {os.path.relpath(c.log_path, ROOT)}")
    for c in clients:
        c.stop()

@scenario("play", "free play for --duration seconds with --bots bots (bandwidth baseline; use --die-rate 0 for steady state)")
def sc_play(ctx):
    bots = [ctx.bot(i) for i in range(1, ctx.args.bots + 1)]
    lobby_join(ctx, bots)
    start_match(ctx, bots, bots[0])
    for b in bots:
        b.latency, b.jitter, b.loss = ctx.args.latency_ms / 1000.0, ctx.args.jitter_ms / 1000.0, ctx.args.loss
    ctx.say(f"playing {ctx.args.duration:.0f} s at {ctx.args.rate:g} Hz, die-rate {ctx.args.die_rate:g}/s"
            f", latency {ctx.args.latency_ms:g}+/-{ctx.args.jitter_ms:g} ms, loss {ctx.args.loss:g}")
    time.sleep(ctx.args.duration)


# ── Runner / report ──────────────────────────────────────────────────────────
def restart_server():
    print("restarting towerbrawl.service ...", flush=True)
    subprocess.run(["systemctl", "--user", "restart", "towerbrawl"], check=False)
    for _ in range(30):
        out = subprocess.run(["ss", "-ltn"], capture_output=True, text=True).stdout
        if ":8081 " in out:
            time.sleep(1.5)
            return
        time.sleep(1)
    print("warning: port 8081 not listening after restart", flush=True)


def metrics(ctx, elapsed):
    bots = [b for b in ctx.bots if b.connected_at is not None]
    in_p = sum(sum(b.in_pkts.values()) for b in bots)
    in_b = sum(sum(b.in_bytes.values()) for b in bots)
    out_p = sum(sum(b.out_pkts.values()) for b in bots)
    out_b = sum(sum(b.out_bytes.values()) for b in bots)
    dups = sum(sum(b.dups.values()) for b in bots)
    rtts = [r for b in bots for r in b.rtts]
    sync_out_p = sum(b.out_pkts["sync_pos"] for b in bots)
    sync_out_b = sum(b.out_bytes["sync_pos"] for b in bots)
    n = max(len(bots), 1)
    elapsed = max(elapsed, 0.001)
    return {
        "bots": len(bots), "elapsed_s": round(elapsed, 1),
        "in_pkts": in_p, "in_bytes": in_b, "out_pkts": out_p, "out_bytes": out_b,
        "in_pps_per_bot": round(in_p / elapsed / n, 1), "in_kbps_per_bot": round(in_b / elapsed / n / 1024, 2),
        "out_pps_per_bot": round(out_p / elapsed / n, 1), "out_kbps_per_bot": round(out_b / elapsed / n / 1024, 2),
        "sync_pos_avg_bytes": round(sync_out_b / sync_out_p) if sync_out_p else 0,
        "duplicates": dups,
        "rtt_ms": {"min": round(min(rtts), 2), "avg": round(sum(rtts) / len(rtts), 2), "max": round(max(rtts), 2)} if rtts else None,
    }


def write_json_report(path, version, seed, results, complete, soak=None):
    """Serialize the report atomically (temp file + rename) so a reader never sees
    a partial or empty file. Called after every scenario, so a killed run still
    leaves the scenarios that finished, marked complete=false."""
    payload = {"version": version, "seed": seed, "complete": complete,
               "written_at": time.strftime("%Y-%m-%d %H:%M:%S"), "results": results}
    if soak is not None:
        payload["soak"] = soak
    data = json.dumps(payload, indent=2)
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    return len(data.encode("utf-8"))


def run_scenario(name, args, version):
    desc, fn = SCENARIOS[name]
    ctx = Ctx(args, version, args.seed)
    if args.trace:
        ctx.trace = open(args.trace, "a", encoding="utf-8")
        ctx.trace.write(json.dumps({"scenario": name, "seed": args.seed, "version": version}) + "\n")
    print(f"\n▶ {name}: {desc}", flush=True)
    t0 = time.monotonic()
    try:
        if args.restart_each:
            restart_server()
        elif not args.no_precheck:
            ensure_lobby(ctx)
        fn(ctx)
    except Exception as e:
        ctx.fail("harness.exception", f"{type(e).__name__}: {e}")
    finally:
        ctx.close_all()
        if ctx.trace is not None:
            time.sleep(0.3)
            ctx.trace.close()
            ctx.trace = None
    elapsed = time.monotonic() - t0
    F = ctx.findings
    res = {"scenario": name, "passed": not F.failed(), "elapsed_s": round(elapsed, 1),
           "findings": {k: {"count": F.counts[k], "examples": F.examples[k]} for k in F.order},
           "notes": list(ctx.notes), "metrics": metrics(ctx, elapsed)}
    print(f"  {'PASS' if res['passed'] else 'FAIL'}  ({elapsed:.1f} s, {len(F.order)} finding kinds)", flush=True)
    time.sleep(0.5)
    return res


def soak_summary(samples):
    """Findings on server resource growth across a soak. Compares the sample after
    the first full pass (warm) with the last one, so start-up allocation is ignored."""
    F = Findings()
    if len(samples) >= 3:
        warm, last = samples[1][2], samples[-1][2]
        rss = (last.get("rss_kb", 0) - warm.get("rss_kb", 0)) // 1024
        thr = last.get("threads", 0) - warm.get("threads", 0)
        fds = last.get("fds", 0) - warm.get("fds", 0)
        if rss > 20:
            F.fail("soak.rss-growth", f"server RSS grew {rss} MB between warm and final sample")
        if thr > 4:
            F.fail("soak.thread-leak", f"server thread count grew by {thr}")
        if fds > 8:
            F.fail("soak.fd-leak", f"server open fds grew by {fds}")
    return F


def run(args):
    version = read_game_version()
    if args.scenario == "all":
        names = [n for n in SCENARIOS if n != "play"]
        if "fleet" in names and shutil.which("godot") is None:
            names.remove("fleet")
            print("note: godot not on PATH, skipping the fleet scenario", flush=True)
    else:
        names = [args.scenario]
    if args.restart_server:
        restart_server()
    print(f"Tower Brawl harness  server=ws://{args.host}:{args.port}  version={version}  seed={args.seed}  scenarios={names}", flush=True)
    results = []
    soak = None
    if args.soak > 0:
        # A soak needs one long-lived server process: no per-scenario restarts.
        args.restart_each = False
        names = [n for n in names if n != "fleet"]
        started = time.monotonic()
        deadline = started + args.soak * 60.0
        samples = []
        st = server_proc_stats()
        if st:
            samples.append((0.0, "start", st))
        print(f"soak: {args.soak:g} min over {names}", flush=True)
        pass_no = 0
        while time.monotonic() < deadline:
            for name in names:
                if time.monotonic() >= deadline:
                    break
                res = run_scenario(name, args, version)
                res["scenario"] = f"{name}#{pass_no}"
                results.append(res)
                st = server_proc_stats()
                if st:
                    samples.append((round(time.monotonic() - started, 1), res["scenario"], st))
                if args.json:
                    write_json_report(args.json, version, args.seed, results, complete=False)
            pass_no += 1
        F = soak_summary(samples)
        soak = {"minutes": args.soak, "passes": pass_no,
                "samples": [{"t": t, "after": n, **st} for t, n, st in samples],
                "findings": {k: {"count": F.counts[k], "examples": F.examples[k]} for k in F.order}}
        results.append({"scenario": "soak-monitor", "passed": not F.failed(), "elapsed_s": round(time.monotonic() - started, 1),
                        "findings": soak["findings"], "notes": [], "metrics": metrics(Ctx(args, version, args.seed), 1.0)})
    else:
        for name in names:
            results.append(run_scenario(name, args, version))
            if args.json:
                write_json_report(args.json, version, args.seed, results, complete=False)

    # ── report ──
    W = 78
    print("\n" + "=" * W)
    print("TOWER BRAWL HARNESS REPORT".center(W))
    print(f"server ws://{args.host}:{args.port}   version {version}   seed {args.seed}".center(W))
    print("=" * W)
    print(f"{'scenario':<22}{'result':<7}{'time':>7}{'in pkts':>9}{'out pkts':>9}{'dups':>7}{'kinds':>7}")
    for r in results:
        m = r["metrics"]
        print(f"{r['scenario']:<22}{'PASS' if r['passed'] else 'FAIL':<7}{r['elapsed_s']:>6.1f}s{m['in_pkts']:>9}{m['out_pkts']:>9}{m['duplicates']:>7}{len(r['findings']):>7}")
    all_findings = collections.OrderedDict()
    for r in results:
        for k, v in r["findings"].items():
            all_findings.setdefault(k, []).append((r["scenario"], v))
    if all_findings:
        print("-" * W)
        print("FINDINGS (kind: total across scenarios, first example)")
        for k, lst in all_findings.items():
            total = sum(v["count"] for _, v in lst)
            scen = ",".join(s for s, _ in lst)
            print(f"  {k:<36} x{total:<6} [{scen}]")
            print(f"      e.g. {lst[0][1]['examples'][0]}")
    notes = [(r["scenario"], n) for r in results for n in r.get("notes", [])]
    if notes:
        print("-" * W)
        print("NOTES")
        for scen, n in notes:
            print(f"  [{scen}] {n}")
    if soak is not None and soak["samples"]:
        print("-" * W)
        print(f"SOAK SAMPLES ({soak['passes']} passes)")
        print(f"  {'t(s)':>7}  {'after':<26}{'RSS MB':>8}{'threads':>9}{'fds':>6}")
        for smp in soak["samples"]:
            print(f"  {smp['t']:>7}  {smp['after']:<26}{smp.get('rss_kb', 0) / 1024:>8.1f}{smp.get('threads', 0):>9}{smp.get('fds', 0):>6}")
    print("-" * W)
    print("METRICS (per bot, payload bytes only)")
    for r in results:
        m = r["metrics"]
        rtt = m["rtt_ms"]
        rtt_s = f"rtt {rtt['min']:.1f}/{rtt['avg']:.1f}/{rtt['max']:.1f} ms" if rtt else "rtt n/a"
        print(f"  {r['scenario']:<22} IN {m['in_pps_per_bot']:6.1f} pkt/s {m['in_kbps_per_bot']:6.2f} KB/s"
              f" | OUT {m['out_pps_per_bot']:5.1f} pkt/s {m['out_kbps_per_bot']:5.2f} KB/s"
              f" | sync_pos {m['sync_pos_avg_bytes']} B | {rtt_s}")
    failed = [r["scenario"] for r in results if not r["passed"]]
    print("=" * W)
    print(f"{len(results) - len(failed)}/{len(results)} scenarios passed" + (f"   FAILED: {', '.join(failed)}" if failed else ""))
    if args.json:
        size = write_json_report(args.json, version, args.seed, results, complete=True, soak=soak)
        print(f"json report -> {args.json} ({size} bytes, {len(results)} scenarios)")
    return 1 if failed else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scenario", default="all", help="all (default) or one of: " + ", ".join(SCENARIOS))
    ap.add_argument("--list", action="store_true", help="list scenarios and exit")
    ap.add_argument("--bots", type=int, default=3, help="bots for the play scenario")
    ap.add_argument("--duration", type=float, default=60.0, help="seconds for the play and fleet scenarios")
    ap.add_argument("--die-rate", type=float, default=0.15, help="per-second probability an alive bot dies (0 = immortal)")
    ap.add_argument("--rate", type=float, default=NET_TICK_HZ, help="movement samples per second while alive (client: 20)")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8081)
    ap.add_argument("--godot", type=int, default=2, help="headless Godot clients in the fleet scenario (1-4)")
    ap.add_argument("--latency-ms", type=float, default=0.0, help="play scenario: added send latency per bot")
    ap.add_argument("--jitter-ms", type=float, default=0.0, help="play scenario: +/- jitter on that latency")
    ap.add_argument("--loss", type=float, default=0.0, help="play scenario: send-side packet loss probability (0-1)")
    ap.add_argument("--soak", type=float, default=0.0, help="minutes: loop the scenarios on one server and watch RSS/threads/fds")
    ap.add_argument("--json", default="", help="write the report as JSON to this path")
    ap.add_argument("--trace", default="", help="append every non-movement packet (with model snapshot) as JSONL to this path")
    ap.add_argument("--restart-server", action="store_true", help="systemctl --user restart towerbrawl before running")
    ap.add_argument("--restart-each", action="store_true", help="restart the server before EVERY scenario (isolates scenarios)")
    ap.add_argument("--no-precheck", action="store_true", help="skip the LOBBY precondition probe between scenarios")
    ap.add_argument("--verbose", action="store_true", help="per-bot event log")
    args = ap.parse_args()
    if args.list:
        for n, (d, _) in SCENARIOS.items():
            print(f"{n:<22} {d}")
        return 0
    if args.scenario != "all" and args.scenario not in SCENARIOS:
        sys.exit(f"unknown scenario {args.scenario!r}; use --list")
    return run(args)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
TowerBrawl Relay Server
- HTTP  :8000   desktop web game
- HTTPS :8443   mobile web game (SSL)
- WS    :8081   desktop WebSocket (plain)
- WSS   :8444   mobile WebSocket (SSL)

All four endpoints share ONE player_slots list.
"""

import http.server
import socketserver
import socket
import ssl
import select
import fcntl
import termios
import collections
import threading
import logging
import sys
import os
import re
import time

# Set up dedicated game server logging.
# Phase 3c step 0 (v0.0.21): every line starts with a short tag in square
# brackets, so you can see at a glance what kind of line it is:
#   [JOIN] someone took a seat      [LEAVE] someone left a seat
#   [CONN] a spectator socket came or went
#   [NAME] a name was set           [LOCK]  a class was locked in
#   [MATCH] the match started or ended   [ROUND] a round started or ended
#   [KILL] a fighter died           [NET]   a bad packet or a network problem
#   [STATS] the 10-second traffic line (unchanged since v0.0.1)
#   [GATE] the harness gate opened or closed a seat (v0.0.23)
#   [MSG] / [SEND] every event packet in and out (debug level: debug.log only)
# The file format "HH:MM:SS | LEVEL | message" did not change.
logger = logging.getLogger("TowerBrawl")
logger.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s | %(levelname)-7s | %(message)s', datefmt='%H:%M:%S')

class _ColourFormatter(logging.Formatter):
    """Colours, but only on a real terminal. journalctl and the log files stay plain,
    so nothing that reads the files has to know about colour codes."""
    RESET = "\033[0m"
    BY_TAG = {"JOIN": "\033[32m", "LEAVE": "\033[33m", "CONN": "\033[2m", "NAME": "\033[35m",
              "LOCK": "\033[34m", "MATCH": "\033[1;36m", "ROUND": "\033[36m", "KILL": "\033[31m",
              "NET": "\033[33m", "STATS": "\033[2m", "MSG": "\033[2m", "SEND": "\033[2m",
              "TAPE": "\033[95m"}
    BY_LEVEL = {"WARNING": "\033[33m", "ERROR": "\033[1;31m", "CRITICAL": "\033[1;31m", "DEBUG": "\033[2m"}
    def format(self, record):
        line = super().format(record)
        m = re.match(r"\[([A-Z]+)", record.getMessage())
        col = self.BY_LEVEL.get(record.levelname) or (self.BY_TAG.get(m.group(1), "") if m else "")
        return f"{col}{line}{self.RESET}" if col else line

class _RingHandler(logging.Handler):
    """Keeps the last few tagged log lines in memory. status.json copies them out
    once a second, so the dashboard can show a live event feed. [STATS] lines and
    untagged lines (the start-up banner) are skipped."""
    def __init__(self, size=40):
        super().__init__(level=logging.INFO)
        self.lines = collections.deque(maxlen=size)
        self.ring_lock = threading.Lock()
    def emit(self, record):
        msg = record.getMessage()
        m = re.match(r"\[([A-Z]+)\]", msg)
        if m is None or m.group(1) == "STATS":
            return
        with self.ring_lock:
            self.lines.append({"t": time.strftime("%H:%M:%S", time.localtime(record.created)),
                               "level": record.levelname, "tag": m.group(1), "msg": msg})
    def snapshot(self):
        with self.ring_lock:
            return list(self.lines)

# Console output (journalctl, or a terminal when run by hand)
ch = logging.StreamHandler(sys.stdout)
ch.setFormatter(_ColourFormatter('%(asctime)s | %(levelname)-7s | %(message)s', datefmt='%H:%M:%S')
                if sys.stdout.isatty() else formatter)
ch.setLevel(logging.DEBUG)
logger.addHandler(ch)

# The last few events, for status.json
ring = _RingHandler()
logger.addHandler(ring)

# File output (server.log) - INFO level for the user
fh = logging.FileHandler(os.path.join(os.path.dirname(__file__), "server.log"))
fh.setLevel(logging.INFO)
fh.setFormatter(formatter)
logger.addHandler(fh)

# Diagnostic File output (debug.log) - DEBUG level for AI
dfh = logging.FileHandler(os.path.join(os.path.dirname(__file__), "debug.log"))
dfh.setLevel(logging.DEBUG)
dfh.setFormatter(logging.Formatter('%(asctime)s | %(threadName)s | %(levelname)s | %(message)s'))
logger.addHandler(dfh)

# Override print to use logger for the simple stuff
def print(*args, **kwargs):
    msg = " ".join(str(a) for a in args)
    logger.info(msg)

def _who(pid):
    """'P2' for a seat, 'spectator' for a socket without one. For log lines."""
    return f"P{pid}" if pid else "spectator"

def _ip(addr):
    """The address as 'ip:port' text. addr is the tuple the socket gave us."""
    try:
        return f"{addr[0]}:{addr[1]}"
    except Exception:
        return str(addr)

def _as_int(value, default=0):
    """A whole number from a packet field, or `default` when the field is not one.
    The story: the fuzz test sends "victim": "abc" and int("abc") blew up with a
    traceback in the log. Bad values are dropped quietly now. True/False are not
    numbers here either."""
    if isinstance(value, bool):
        return default
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value == int(value):
        return int(value)
    if isinstance(value, str):
        try:
            return int(value.strip())
        except ValueError:
            return default
    return default

def _lives_text(n):
    """'1 life left', '0 lives left', '2 lives left'. Plain English for the log."""
    return f"{n} life left" if n == 1 else f"{n} lives left"

import hashlib
import base64
import struct
import json

# Fallback only. bump_build.sh rewrites this line, but get_game_version() below
# prefers the live value in scripts/global.gd so a running server accepts a
# freshly built client without a restart.
GAME_VERSION = "v0.0.38"

# Phase 0 knobs ---------------------------------------------------------------
LOG_MOVEMENT   = False   # True = log every sync_pos / spawn_projectile relay (very noisy, slows the relay)
MOVEMENT_TYPES = ("sync_pos", "spawn_projectile", "ping")
STATS_INTERVAL = 10.0    # seconds between [STATS] lines in server.log, 0 = off

# Phase 2: parser hardening + binary movement packets -------------------------
MAX_FRAME_BYTES = 4096   # a frame header claiming more than this closes the socket (no trusting the length field)
MAX_RELAY_BYTES = 1024   # text messages above this are dropped, never relayed (no amplification)
# Binary packets: [0] type, [1] sender slot (stamped here), fixed-size body. See global.gd.
BIN_TYPES = {1: ("sync_pos", 11), 2: ("spawn_projectile", 9)}   # sync_pos gained a u16 tick (Phase 3a)

# v0.0.36 (optimisation Step C, build 3): sync_bundle. The relay used to send
# every sync_pos on its own the moment it arrived: 3 puppets x 13 pkt/s = about
# 40 packets a second into every client, and on the wire each one carries 40 to
# 50 B of headers around 11 B of payload. Now the reader threads hand type 1
# packets to one MovementBatcher, which flushes every RELAY_BUNDLE_MS as ONE
# binary frame per client: [0] = 3, [1] = n, then n entries of 10 B, each entry
# being a sync_pos from byte 1 onward ([sender u8, tick u16, x s16, y s16, aim u16,
# flags u8]). A player never gets its own entries (like exclude=sock before);
# spectators get all of them. Server -> client only: a client sending type 3 is
# dropped like any other unknown binary type. 0 = relay each sync_pos at once, as
# before (the client decodes both). spawn_projectile stays immediate.
RELAY_BUNDLE_MS = 50     # one bundle per 50 ms, the client's own NET_TICK_INTERVAL
BIN_SYNC_BUNDLE = 3
BIN_BUNDLE_ENTRY = 10    # bytes per entry
BIN_BUNDLE_MAX = 25      # entries per bundle; more pending than this flushes early (252 B frame)

# Phase 3a: per-client send queues + backpressure ---------------------------
MAX_QUEUE_FRAMES = 128   # queued frames per client before movement frames are dropped
MAX_QUEUE_BYTES  = 32 * 1024
STALL_MIN_BYTES  = 2048  # unsent bytes in the kernel before a client counts as "not reading"
STALL_TIMEOUT    = 5.0   # s of no send progress above that -> the client is disconnected
# -----------------------------------------------------------------------------

HTTP_PORT  = 8000
HTTPS_PORT = 8443
WS_PORT    = 8081
WSS_PORT   = 8444

BASE_DIR  = os.path.dirname(os.path.abspath(__file__))
BUILD_DIR = os.path.join(BASE_DIR, "build", "web")
CERT_FILE = os.path.join(BASE_DIR, "cert.pem")
KEY_FILE  = os.path.join(BASE_DIR, "key.pem")
GLOBAL_GD = os.path.join(BASE_DIR, "scripts", "global.gd")

_version_cache = {"mtime": None, "value": GAME_VERSION}

def get_game_version():
    """Version the server accepts on request_join. Read from scripts/global.gd
    (cached by mtime) so a bump_build.sh run takes effect without a restart."""
    try:
        mtime = os.path.getmtime(GLOBAL_GD)
        if mtime != _version_cache["mtime"]:
            with open(GLOBAL_GD, encoding="utf-8") as f:
                m = re.search(r'const GAME_VERSION: String = "(v\d+\.\d+\.\d+)"', f.read())
            if m:
                _version_cache["value"] = m.group(1)
            _version_cache["mtime"] = mtime
    except OSError:
        pass
    return _version_cache["value"]

# ── Net stats (Phase 0 instrumentation) ───────────────────────────────────────
# Payload bytes/packets through the relay, logged every STATS_INTERVAL seconds.
# WebSocket frame headers and TLS overhead are not counted.
net_stats_lock = threading.Lock()
net_stats = {"in_pkts": 0, "in_bytes": 0, "out_pkts": 0, "out_bytes": 0,
             "out_fail": 0, "out_drop": 0, "in_types": {}}
# The same counts, but never reset: status.json (v0.0.21) works out per-second
# rates from the difference between two reads.
net_totals = {"in_pkts": 0, "in_bytes": 0, "out_pkts": 0, "out_bytes": 0,
              "out_fail": 0, "out_drop": 0, "in_types": {}}

def _stat_in(nbytes):
    with net_stats_lock:
        net_stats["in_pkts"] += 1
        net_stats["in_bytes"] += nbytes
        net_totals["in_pkts"] += 1
        net_totals["in_bytes"] += nbytes

def _stat_in_type(mtype):
    with net_stats_lock:
        net_stats["in_types"][mtype] = net_stats["in_types"].get(mtype, 0) + 1
        net_totals["in_types"][mtype] = net_totals["in_types"].get(mtype, 0) + 1

def _stat_out(nbytes, ok):
    with net_stats_lock:
        if ok:
            net_stats["out_pkts"] += 1
            net_stats["out_bytes"] += nbytes
            net_totals["out_pkts"] += 1
            net_totals["out_bytes"] += nbytes
        else:
            net_stats["out_fail"] += 1
            net_totals["out_fail"] += 1

def stats_loop():
    while True:
        time.sleep(STATS_INTERVAL)
        with net_stats_lock:
            s = dict(net_stats)
            s["in_types"] = dict(net_stats["in_types"])
            net_stats.update({"in_pkts": 0, "in_bytes": 0, "out_pkts": 0,
                              "out_bytes": 0, "out_fail": 0, "out_drop": 0, "in_types": {}})
        with lobby_lock:
            players = sum(1 for p in player_slots if p)
            bots = _bot_count()
            spectators = len(spectator_sockets)   # sockets without a slot (a slot holder is not in here)
            state = global_match_state
        top = ", ".join(f"{k}={v}" for k, v in sorted(s["in_types"].items(), key=lambda kv: -kv[1])[:6])
        bundle_txt = ""
        if batcher is not None:
            with batcher.lock:
                nb, ne = batcher.bundles, batcher.entries
                batcher.bundles = batcher.entries = 0
            if nb:
                bundle_txt = f" bundles={nb / STATS_INTERVAL:.1f}/s x{ne / nb:.1f}"
        bots_txt = f" ({bots} bot{'s' if bots != 1 else ''})" if bots else ""
        logger.info(
            f"[STATS {STATS_INTERVAL:.0f}s] {state} players={players}{bots_txt} spectators={spectators} sockets={players + spectators}"
            f" | IN {s['in_pkts'] / STATS_INTERVAL:6.1f} pkt/s {s['in_bytes'] / STATS_INTERVAL / 1024:6.2f} KB/s"
            f" (avg {s['in_bytes'] / max(s['in_pkts'], 1):.0f} B)"
            f" | OUT {s['out_pkts'] / STATS_INTERVAL:6.1f} pkt/s {s['out_bytes'] / STATS_INTERVAL / 1024:6.2f} KB/s"
            f" fail={s['out_fail']} drop={s['out_drop']}{bundle_txt} | in: {top or '-'}")

# ── Live status file (Phase 3c step 0, v0.0.21) ──────────────────────────────
# The story: to watch a match from the terminal you had to read raw log lines.
# Now the server writes a small file, status.json, once a second: the match
# state, every seat, the traffic and the last events. tools/watch_server.py
# reads it and draws a live dashboard. The file is written under a temp name
# and then renamed, so a reader never sees a half-written file. Standard
# library only: the systemd service runs the system python3, not the venv.
STATUS_INTERVAL = 1.0    # seconds between writes, 0 = off
STATUS_FILE = os.path.join(BASE_DIR, "status.json")
SERVER_STARTED = time.time()
CLASS_NAMES = {0: "Ranger", 1: "Knight", 2: "Mage", 3: "Rogue", 4: "Druid"}   # Global.ClassType order

def _build_status(prev_totals, prev_conns, dt):
    """One picture of the server right now (a dict ready for JSON).
    prev_totals / prev_conns are the counts from the last write, so we can
    turn them into per-second rates over dt seconds."""
    now = time.time()
    dt = max(dt, 1e-3)
    with net_stats_lock:
        tot = dict(net_totals)
        tot["in_types"] = dict(net_totals["in_types"])
    rate = lambda k: (tot[k] - prev_totals.get(k, 0)) / dt
    types_s = {k: round((v - prev_totals.get("in_types", {}).get(k, 0)) / dt, 1)
               for k, v in tot["in_types"].items()
               if v - prev_totals.get("in_types", {}).get(k, 0) > 0}
    seats = []
    new_conns = {}
    with lobby_lock:
        with conns_lock:
            conn_by_sock = dict(conns)
        with client_stats_lock:
            stats_by_sock = dict(client_stats)
        for i in range(4):
            pid = i + 1
            entry = player_slots[i]
            pend = pending_rejoin.get(pid)
            conn = conn_by_sock.get(id(entry["sock"])) if entry else None
            seat = {
                "id": pid,
                "name": player_names.get(pid),
                "class": player_locked.get(pid),
                "class_name": CLASS_NAMES.get(player_locked.get(pid)),
                "locked": pid in player_locked,
                "connected": entry is not None,
                "transport": entry.get("label") if entry else None,
                "ip": entry.get("ip") if entry else None,
                "playing": pid in global_playing_players,
                "waiting": pid in global_waiting_players,
                "alive": pid in global_alive_players,
                "stocks": global_player_stocks.get(pid, 0),
                "crowns": global_player_scores.get(pid, 0),
                "held_s": round(max(pend["until"] - now, 0.0), 1) if pend else None,
                "in_pps": 0.0, "in_kbps": 0.0, "queue": 0, "dropped": 0, "seen_s": None, "age_s": None,
                # v0.0.22: fight counts for this match, the client's ping, and its bot card.
                "kills": match_kd[pid]["kills"],
                "deaths": match_kd[pid]["deaths"],
                "rtt_ms": None,
                "bot": player_bots.get(pid) if entry is not None or pend else None,
                # v0.0.25: the screen's tape card (history_status), for the deck's Tape column.
                "tape": player_tapes.get(pid) if entry is not None or pend else None,
                # v0.0.37: the screen's own numbers (client_stats card), for the deck's Screen column.
                "stats": stats_by_sock.get(id(entry["sock"])) if entry else None,
            }
            if conn is not None:
                seat["rtt_ms"] = conn.rtt_ms
                key = id(entry["sock"])
                p_pkts, p_bytes = prev_conns.get(key, (conn.in_pkts, conn.in_bytes))
                seat["in_pps"] = round((conn.in_pkts - p_pkts) / dt, 1)
                seat["in_kbps"] = round((conn.in_bytes - p_bytes) / dt / 1024, 2)
                seat["queue"] = len(conn.q)
                seat["dropped"] = conn.dropped
                seat["seen_s"] = round(now - conn.last_rx, 1)
                seat["age_s"] = round(now - conn.opened_at, 1)
                new_conns[key] = (conn.in_pkts, conn.in_bytes)
            seats.append(seat)
        status = {
            "written_at": now,
            "version": get_game_version(),
            "started_at": SERVER_STARTED,
            "uptime_s": round(now - SERVER_STARTED, 1),
            "pid": os.getpid(),
            "threads": threading.active_count(),
            "match": {
                "state": global_match_state,
                "round": global_current_round,
                "flips": global_arena_flips,
                "round_over": global_is_round_over,
                "match_over": global_match_over,
                "score_limit": MATCH_SCORE_LIMIT,
                "playing": list(global_playing_players),
                "waiting": list(global_waiting_players),
                "alive": sorted(global_alive_players),
                # v0.0.22: every kill and every round of the current (or last) match.
                "timeline": {
                    "started_at": match_timeline["started_at"],
                    "kills": list(match_timeline["kills"]),
                    "rounds": [list(r) for r in match_timeline["rounds"]],
                    "ended_at": match_timeline["ended_at"],
                    "winner": match_timeline["winner"],
                    "names": dict(match_timeline["names"]),
                },
            },
            "seats": seats,
            "bots": _bot_count(),
            "spectators": len(spectator_sockets),
            "spectator_stats": [stats_by_sock[id(sp["sock"])] for sp in spectator_sockets if id(sp["sock"]) in stats_by_sock],
            "sockets": sum(1 for p in player_slots if p) + len(spectator_sockets),
            "harness": dict(harness_gate),   # v0.0.23: is the harness gate closed right now?
        }
    status["traffic"] = {
        "in_pps": round(rate("in_pkts"), 1),
        "in_kbps": round(rate("in_bytes") / 1024, 2),
        "out_pps": round(rate("out_pkts"), 1),
        "out_kbps": round(rate("out_bytes") / 1024, 2),
        "fail_s": round(rate("out_fail"), 1),
        "drop_s": round(rate("out_drop"), 1),
        "in_types_s": types_s,
        "totals": tot,
    }
    status["events"] = ring.snapshot()
    return status, tot, new_conns

def status_loop():
    prev_totals = {}
    prev_conns = {}
    last = time.time()
    tmp = STATUS_FILE + ".tmp"
    # v0.0.23: read harness_state.json right away, so a server that the harness
    # just restarted is locked from its first second, not after the first sleep.
    _harness_tick(time.time())
    while True:
        time.sleep(STATUS_INTERVAL)
        try:
            now = time.time()
            _harness_tick(now)
            status, prev_totals, prev_conns = _build_status(prev_totals, prev_conns, now - last)
            last = now
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(status, f, separators=(",", ":"))
            os.replace(tmp, STATUS_FILE)
        except Exception as e:
            logger.debug(f"[NET] status.json not written: {type(e).__name__}: {e}")

# ── Shared lobby ──────────────────────────────────────────────────────────────
# player_slots[i] = {"sock": socket, "addr": str}  or  None
player_slots  = [None, None, None, None]
player_locked = {}
player_names  = {}          # {player_id(int): name(str)}

def _unique_name(raw, pid):
    """Make sure no two seats share a name (v0.0.19).

    The story: two brothers both typed "Tav" and nobody knew who was who.
    Now the server owns the names. If another seat already has this name
    (big or small letters do not matter), we add a number: Tav-2, then
    Tav-3. The name stays 12 letters at most, so a long name is trimmed
    to make room for the number. An empty name becomes "Player".
    Call this with lobby_lock held.
    """
    base = str(raw).strip()[:12] or "Player"
    taken = {str(v).lower() for k, v in player_names.items() if k != pid}
    if base.lower() not in taken:
        return base
    n = 2
    while True:
        tail = f"-{n}"
        cand = base[:12 - len(tail)] + tail
        if cand.lower() not in taken:
            return cand
        n += 1
lobby_lock    = threading.RLock()

global_match_state = 'LOBBY'
global_playing_players = []
global_waiting_players = []
global_current_round = 1
global_player_scores = {1: 0, 2: 0, 3: 0, 4: 0}
global_player_stocks = {1: 3, 2: 3, 3: 3, 4: 3}
global_alive_players = set()
global_is_round_over = False
global_transition_sent = False      # scene_transition already broadcast for this match
global_round_player_count = 0       # players in the match when the round started (>=2 needed for a round to end)
global_match_over = False           # someone reached MATCH_SCORE_LIMIT; next step is the lobby, never new_round
MATCH_SCORE_LIMIT = 5               # crowns needed to win the match (client shows the same number)
NEXT_ROUND_DELAY = 2.6              # seconds between round_end and new_round / return_to_lobby (draws, forfeits)
REPLAY_ROUND_DELAY = 6.5            # v0.0.26: the gap after a round won on a kill, so every screen can play its tape back
MATCH_END_DELAY = 7.0               # seconds the "wins the match" banner stays before return_to_lobby (was 6.0; the replay needs 6.1)
REPLAY_KILL_WINDOW = 1.5            # a round that ended within this many seconds of a death ended on a kill
spectator_sockets = []              # pure spectators only; a socket holding a slot is NOT in here

# Playtest fixes (v0.0.6) ----------------------------------------------------
CLIENT_READ_TIMEOUT = 120.0         # safety net only; liveness comes from TCP keepalive (a hidden tab sends nothing for minutes)
TCP_KEEPALIVE = (10, 5, 3)          # idle s, probe interval s, probes: a dead peer is detected in ~25 s
REJOIN_GRACE = 8.0                  # s a fighter's seat is held after a mid-match disconnect (page reload, Wi-Fi blip)
FORFEIT_GRACE = 1.5                 # s after an explicit leave before the round is decided (two leaving together = no winner)
RECENT_SLOT_S = 120.0               # s a client token may reclaim its previous lobby slot
DEATH_DEDUPE_S = 1.5                # any client may report a death; repeats inside this window are the same death
slot_tokens = {}                    # pid -> client token currently holding the slot
recent_slots = {}                   # token -> (pid, time left)
pending_rejoin = {}                 # pid -> {"token", "seq", "until"}: seat held, not counted alive
pending_names = {}                  # id(sock) -> name sent before the client had a slot
last_death = {}                     # pid -> time of the last accepted death report
global_arena_flips = 0              # activate_powerup count this match (platform rotation for late arrivals)
_grace_seq = 0

# Fight telemetry (v0.0.22) --------------------------------------------------
# The story: the dashboard wanted to show who is winning, not only who is alive.
# So the server now counts kills and deaths per seat for the current match and
# keeps a small timeline of every kill and every round. All of it starts fresh
# in _setup_match and stays readable after the match ends, until the next one.
TIMELINE_MAX_KILLS = 300            # a match never has this many, it is only a safety cap
match_kd = {i: {"kills": 0, "deaths": 0} for i in range(1, 5)}   # pid -> counts this match
match_timeline = {"started_at": None, "kills": [], "rounds": [], "ended_at": None, "winner": None, "names": {}}
# rounds: [round, start_s, winner, end_s]. v0.0.24 added end_s (stamped when the
# round closes) and ended_at / winner for the match, so the deck can draw them.
# One kill is [seconds since match start, killer, victim, weapon, round].
# One round is [round number, start seconds, winner or None while it runs].

# Bots (v0.0.22) -------------------------------------------------------------
# A headless bot says "bot": "<persona>" in request_join, and a bot brain sends
# a bot_status packet every 5 s with its numbers. The server keeps the last one
# per seat here and copies it into status.json. It is never sent to the players.
player_bots = {}                    # pid -> the last bot telemetry dict for that seat

# v0.0.37: every client (seat or spectator, phone or PC or headless bot) mails its
# NetStats numbers home every 5 s as a `client_stats` card. The newest card per
# socket goes into status.json (the deck's Screen column); every card and every
# match / round marker is appended to client_stats.jsonl, one JSON object per
# line, so a playtest table is a time window, not a console hunt
# (tools/stats_table.py). Never relayed to the players.
client_stats = {}                   # id(sock) -> the last card from that socket
client_stats_lock = threading.Lock()
CLIENT_STATS_MAX_BYTES = 1024       # a card bigger than this is dropped
CLIENT_STATS_FILE = os.path.join(BASE_DIR, "client_stats.jsonl")
CLIENT_STATS_ROTATE_BYTES = 10 * 1024 * 1024   # then the file becomes client_stats.jsonl.1 (one copy kept)

def _stats_log(rec):
    """Append one record (a card or a marker) to client_stats.jsonl with the server clock."""
    rec["t"] = round(time.time(), 3)
    rec["clock"] = time.strftime("%H:%M:%S")
    line = json.dumps(rec, separators=(",", ":"), default=str)
    try:
        with client_stats_lock:
            try:
                if os.path.getsize(CLIENT_STATS_FILE) > CLIENT_STATS_ROTATE_BYTES:
                    os.replace(CLIENT_STATS_FILE, CLIENT_STATS_FILE + ".1")
            except OSError:
                pass
            with open(CLIENT_STATS_FILE, "a", encoding="utf-8") as f:
                f.write(line + "\n")
    except OSError as e:
        logger.debug(f"[NET] client_stats.jsonl not written: {type(e).__name__}: {e}")
BOT_STATUS_MAX_BYTES = 1024         # a bot_status packet bigger than this is dropped
player_tapes = {}                   # pid -> the last history_status card of that screen (Phase 3c, v0.0.25)
TAPE_STATUS_MAX_BYTES = 1024        # a history_status packet bigger than this is dropped
BOT_PERSONA_MAX = 16

def _bot_count():
    """(lobby_lock held) How many of the seated players said they are bots."""
    return sum(1 for i in range(4) if player_slots[i] and (i + 1) in player_bots)

def _bot_from_join(value, pid):
    """The bot card for a seat from the "bot" field of request_join, or None.
    "protocol" is a harness bot, anything else is a brain persona."""
    if not isinstance(value, str) or not value.strip():
        return None
    persona = value.strip()[:BOT_PERSONA_MAX]
    kind = "brain"
    if persona in ("protocol", "headless"):
        kind = persona          # "protocol" = harness bot, "headless" = plain headless client (v0.0.23)
    return {"schema": 1, "kind": kind, "seat": pid, "persona": persona, "updated_at": time.time()}

# Harness gate (v0.0.23) -----------------------------------------------------
# The story: someone could open the game while tools/chaos_bots.py was running
# and take a seat in the middle of a test. Now the server reads
# harness_state.json (the harness writes it once a second). While its "state"
# is "running" or "restarting", the heartbeat is fresh and the harness process
# is alive, the seats are for bots only: a human request_join gets a
# join_locked packet, and a human already in a seat is moved back to spectator
# (same code path as leave_slot). Everyone connected gets a harness_status
# packet when the numbers change, so a spectator screen can show a small
# ticker: the scenario name and "tests done X / Y".
HARNESS_FILE = os.path.join(BASE_DIR, "harness_state.json")
HARNESS_STALE = 5.0                 # s without a heartbeat = the harness is gone (same number as watch_server.py)
HARNESS_ACTIVE_STATES = ("running", "restarting")
harness_gate = {"active": False, "state": "idle", "scenario": None,
                "done": 0, "total": 0, "passed": 0, "failed": 0, "minor": 0}
_harness_last_sent = None           # text of the last harness_status packet: we only send when it changes
demoted_socks = set()               # id(sock) of seats taken back by the gate; the reader thread drops its seat number

def _pid_alive(pid):
    """True when the process is still there. A missing pid counts as alive,
    so the freshness rule decides on its own."""
    try:
        pid = int(pid)
    except (TypeError, ValueError):
        return True
    if pid <= 0:
        return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True

def _read_harness_state():
    try:
        with open(HARNESS_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None

def _gate_from_file(data, now):
    """Turn harness_state.json into the small gate dict. No file = open gate."""
    gate = {"active": False, "state": "idle", "scenario": None,
            "done": 0, "total": 0, "passed": 0, "failed": 0, "minor": 0}
    if not isinstance(data, dict):
        return gate
    state = str(data.get("state", "idle"))[:16]
    gate["state"] = state
    sc = data.get("scenario")
    if isinstance(sc, dict) and sc.get("name"):
        gate["scenario"] = str(sc.get("name"))[:32]
    suite = data.get("suite")
    if isinstance(suite, dict):
        gate["done"] = _as_int(suite.get("index", 0))
        for k in ("total", "passed", "failed", "minor"):
            gate[k] = _as_int(suite.get(k, 0))
    try:
        fresh = now - float(data.get("written_at", 0) or 0) < HARNESS_STALE
    except (TypeError, ValueError):
        fresh = False
    gate["active"] = state in HARNESS_ACTIVE_STATES and fresh and _pid_alive(data.get("pid"))
    return gate

def _harness_status_packet():
    return json.dumps({"type": "harness_status", **harness_gate}, separators=(",", ":"))

def _harness_tick(now):
    """Once a second from status_loop. Reads the file, locks or opens the gate,
    and tells everyone when the ticker text changed."""
    global _harness_last_sent
    gate = _gate_from_file(_read_harness_state(), now)
    with lobby_lock:
        was_active = harness_gate["active"]
        harness_gate.update(gate)
    if gate["active"] and not was_active:
        logger.info(f"[GATE] harness run seen ({gate['state']}): seats are for bots only until it ends")
        _demote_humans()
    elif was_active and not gate["active"]:
        logger.info(f"[GATE] harness run over ({gate['state']}): seats are open again")
    pkt = _harness_status_packet()
    if pkt != _harness_last_sent:
        _harness_last_sent = pkt
        broadcast(pkt, msg_type="harness_status")

def _demote_humans():
    """Every seat whose owner did not say "bot" in request_join goes back to
    spectator. The owner gets join_locked with demoted=true."""
    with lobby_lock:
        humans = [(i + 1, player_slots[i]) for i in range(4)
                  if player_slots[i] is not None and (i + 1) not in player_bots]
    for pid, entry in humans:
        sock = entry["sock"]
        with lobby_lock:
            if player_slots[pid - 1] is not entry:
                continue        # the seat changed hands while we looked
            demoted_socks.add(id(sock))
        _release_seat(sock, entry["addr"], entry["label"], pid,
                      f"was moved to spectator by the harness gate")
        ws_send(sock, json.dumps({"type": "join_locked", "demoted": True, **harness_gate}))
# ─────────────────────────────────────────────────────────────────────────────

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def _recvall(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("socket closed")
        buf += chunk
    return buf

def ws_handshake(sock):
    try:
        sock.settimeout(6.0)
        raw = sock.recv(4096).decode("utf-8", errors="ignore")
        headers = {}
        for line in raw.split("\r\n"):
            if ": " in line:
                k, v = line.split(": ", 1)
                headers[k.lower()] = v.strip()
        key = headers.get("sec-websocket-key")
        if not key:
            return False
        accept = base64.b64encode(
            hashlib.sha1((key + WS_GUID).encode()).digest()
        ).decode()
        sock.sendall((
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        ).encode())
        sock.settimeout(10.0)
        return True
    except Exception:
        return False

def ws_read(sock):
    """One frame. Returns None when the connection is closed, broken or hostile
    (length header above MAX_FRAME_BYTES), else (opcode, payload):
    (1, str) text, (2, bytes) binary, (0, None) for control frames (consumed)."""
    try:
        head = _recvall(sock, 2)
        b1, b2 = head[0], head[1]
        opcode = b1 & 0x0F
        if opcode == 8:
            return None
        masked = bool(b2 & 0x80)
        plen   = b2 & 0x7F
        if plen == 126:
            plen = struct.unpack(">H", _recvall(sock, 2))[0]
        elif plen == 127:
            plen = struct.unpack(">Q", _recvall(sock, 8))[0]
        if plen > MAX_FRAME_BYTES:
            # Never wait for (or allocate) what the header claims: close immediately.
            logger.warning(f"[NET] frame header claims {plen} bytes (cap {MAX_FRAME_BYTES}); closing connection")
            return None
        mask = _recvall(sock, 4) if masked else b""
        data = bytearray(_recvall(sock, plen))
        if masked:
            for i in range(len(data)):
                data[i] ^= mask[i % 4]
        _stat_in(plen)
        if opcode == 1:
            return (1, data.decode("utf-8", errors="ignore"))
        if opcode == 2:
            return (2, bytes(data))
        return (0, None)   # ping/pong/continuation: payload consumed, nothing to do
    except Exception:
        return None

def ws_frame(msg):
    """Server->client frame (unmasked). msg: str -> text frame, bytes -> binary frame."""
    if isinstance(msg, (bytes, bytearray)):
        payload = bytes(msg)
        frame = bytearray([0x82])
    else:
        payload = msg.encode("utf-8")
        frame = bytearray([0x81])
    n = len(payload)
    if n <= 125:
        frame.append(n)
    elif n <= 65535:
        frame += bytes([126]) + struct.pack(">H", n)
    else:
        frame += bytes([127]) + struct.pack(">Q", n)
    frame += payload
    return bytes(frame)

def _sock_outq(sock):
    """Bytes the kernel still has to deliver on this socket (unsent + unacked)."""
    try:
        return struct.unpack("i", fcntl.ioctl(sock.fileno(), termios.TIOCOUTQ, struct.pack("i", 0)))[0]
    except (OSError, ValueError):
        return 0

class ClientConn:
    """Per-client outgoing queue with its own writer thread (Phase 3a).

    broadcast() used to call a blocking sendall() on every socket in turn, so one
    peer that stopped reading stalled the relay for everybody once the kernel
    buffers filled. Now every socket has a bounded queue: enqueue never blocks,
    movement frames are dropped first when a queue backs up (events are kept),
    and a client whose kernel send queue stops draining for STALL_TIMEOUT is
    disconnected. A hidden browser tab still reads (its queue stays empty), so
    it is never mistaken for a stalled reader."""
    def __init__(self, sock, label):
        self.sock = sock
        self.label = label
        self.q = collections.deque()
        self.q_bytes = 0
        self.movement_pending = 0
        self.cv = threading.Condition()
        self.alive = True
        self.dropped = 0
        # v0.0.21: what came in on this socket, for the status file.
        self.in_pkts = 0
        self.in_bytes = 0
        self.last_rx = time.time()
        self.opened_at = time.time()
        self.rtt_ms = None          # v0.0.22: the round trip the client measured, sent with its pings
        self.stall_since = None
        self.last_outq = 0
        self.last_stall_check = time.time()
        self.thread = threading.Thread(target=self._writer, daemon=True, name="writer")
        self.thread.start()

    def enqueue(self, frame, movement=False):
        with self.cv:
            if not self.alive:
                return False
            if len(self.q) >= MAX_QUEUE_FRAMES or self.q_bytes + len(frame) > MAX_QUEUE_BYTES:
                if movement:
                    self.dropped += 1
                    _stat_drop()
                    return False
                # keep events: throw away queued movement to make room
                kept = collections.deque()
                for f, mv in self.q:
                    if mv:
                        self.dropped += 1
                        self.q_bytes -= len(f)
                        _stat_drop()
                    else:
                        kept.append((f, mv))
                self.q = kept
                if len(self.q) >= MAX_QUEUE_FRAMES or self.q_bytes + len(frame) > MAX_QUEUE_BYTES:
                    self._stalled("event queue full")
                    return False
            self.q.append((frame, movement))
            self.q_bytes += len(frame)
            self.cv.notify()
            return True

    def _stalled(self, why):
        if self.alive:
            logger.warning(f"[NET] {self.label} client not reading ({why}); disconnecting")
        self.close()

    def close(self):
        with self.cv:
            self.alive = False
            self.q.clear()
            self.q_bytes = 0
            self.cv.notify_all()
        # shutdown() wakes the reader thread blocked in recv(); close() alone would not.
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass

    def _check_stall(self):
        # Sampled about once per second whatever the writer is doing: a peer that
        # keeps reading holds its kernel backlog near zero; one that stopped shows a
        # backlog that never shrinks.
        now = time.time()
        if now - self.last_stall_check < 1.0:
            return
        self.last_stall_check = now
        outq = _sock_outq(self.sock)
        if outq >= STALL_MIN_BYTES and outq >= self.last_outq:
            if self.stall_since is None:
                self.stall_since = now
            elif now - self.stall_since > STALL_TIMEOUT:
                self._stalled(f"{outq} B unsent for {STALL_TIMEOUT:g} s")
                return
        else:
            self.stall_since = None
        self.last_outq = outq

    def _writer(self):
        while True:
            with self.cv:
                while self.alive and not self.q:
                    self.cv.wait(1.0)
                    if self.alive:
                        self._check_stall()
                if not self.alive:
                    return
                frame, _ = self.q.popleft()
                self.q_bytes -= len(frame)
            self._check_stall()
            if not self.alive:
                return
            view = memoryview(frame)
            try:
                while view:
                    _, w, _ = select.select([], [self.sock], [], 1.0)
                    if not w:
                        self._check_stall()
                        if not self.alive:
                            return
                        continue
                    n = self.sock.send(view)
                    view = view[n:]
                _stat_out(len(frame), True)   # handed to the kernel; peer progress is judged by _check_stall
            except Exception:
                _stat_out(0, False)
                self.close()
                return

conns = {}
conns_lock = threading.Lock()

class MovementBatcher:
    """Holds the sync_pos samples that arrived in the last RELAY_BUNDLE_MS and
    relays them as one sync_bundle per client (v0.0.36). Samples keep their
    arrival order and none is dropped: with jitter two ticks of one sender can
    land in one window, and a receiver reads a missing tick as "stood still"."""
    def __init__(self, period_ms):
        self.period = period_ms / 1000.0
        self.lock = threading.Lock()
        self.pending = []          # [(sender slot, id(sender socket), 10 B entry)] in arrival order
        self.bundles = 0           # flushes that sent something (for the [STATS] line)
        self.entries = 0
        self.thread = threading.Thread(target=self._loop, daemon=True, name="batcher")
        self.thread.start()

    def add(self, slot, sock, entry):
        with self.lock:
            self.pending.append((slot, id(sock), entry))
            full = len(self.pending) >= BIN_BUNDLE_MAX
        if full:
            self.flush()

    def _loop(self):
        next_at = time.monotonic()
        while True:
            next_at += self.period
            wait = next_at - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            else:
                next_at = time.monotonic()   # fell behind (a stall): realign instead of bursting
            self.flush()

    def flush(self):
        with self.lock:
            if not self.pending:
                return
            pending, self.pending = self.pending, []
        with lobby_lock:
            seen = set()
            targets = []   # (sock, slot id or None for a spectator)
            for i, entry in enumerate(player_slots):
                if entry and id(entry["sock"]) not in seen:
                    seen.add(id(entry["sock"]))
                    targets.append((entry["sock"], i + 1))
            for entry in spectator_sockets:
                if entry and id(entry["sock"]) not in seen:
                    seen.add(id(entry["sock"]))
                    targets.append((entry["sock"], None))
        # A recipient never gets its own entries: not the ones from its slot, and not
        # the ones its socket sent (a fighter that pressed leave is a spectator by the
        # time of the flush, but the sample it sent as a fighter is still not for it).
        # Frames are built once per distinct set of left-out entries.
        frames = {}
        with conns_lock:
            queues = [(s, pid, conns.get(id(s))) for s, pid in targets]
        sent = 0
        for s, pid, conn in queues:
            sid = id(s)
            key = tuple(i for i, (snd, src, _) in enumerate(pending) if snd == pid or src == sid)
            frame = frames.get(key)
            if frame is None:
                entries = [e for i, (_, _, e) in enumerate(pending) if i not in key]
                frame = ws_frame(bytes([BIN_SYNC_BUNDLE, len(entries)]) + b"".join(entries)) if entries else b""
                frames[key] = frame
            if not frame:
                continue
            sent += 1
            if conn is None:
                try:
                    s.sendall(frame)
                except Exception:
                    try: s.close()
                    except Exception: pass
            else:
                conn.enqueue(frame, True)
        if sent:
            with self.lock:
                self.bundles += 1
                self.entries += len(pending)

batcher = MovementBatcher(RELAY_BUNDLE_MS) if RELAY_BUNDLE_MS > 0 else None

def _stat_drop():
    with net_stats_lock:
        net_stats["out_drop"] += 1
        net_totals["out_drop"] += 1

def ws_send(sock, msg, movement=False):
    """Queue msg for one socket (never blocks the caller)."""
    with conns_lock:
        conn = conns.get(id(sock))
    if conn is None:
        try:
            sock.sendall(ws_frame(msg))
            _stat_out(len(msg), True)
            return True
        except Exception:
            _stat_out(0, False)
            return False
    return conn.enqueue(ws_frame(msg), movement)

def _is_movement(msg, msg_type=None):
    if msg_type is not None:
        return msg_type in MOVEMENT_TYPES
    return any(f'"{t}"' in msg for t in MOVEMENT_TYPES)

# Packet types only the server may originate. A client sending one is dropped:
# match flow (new_round, return_to_lobby, scene_transition...) is server-authoritative.
SERVER_ONLY_TYPES = {"spectator_state", "assign_id", "player_joined", "player_left", "name_update",
                     "scene_transition", "round_end", "new_round", "return_to_lobby",
                     "version_error", "server_full", "pong", "harness_status", "join_locked"}

def broadcast(msg, exclude=None, msg_type=None):
    """Send msg once to every connected socket except `exclude`.

    A socket lives in player_slots OR spectator_sockets, never both (a slot holder
    is removed from the spectator list on request_join and put back on leave_slot);
    the identity set below guarantees single delivery even if that invariant slips.
    Movement packets are not logged unless LOG_MOVEMENT.
    Frames are queued per client (ClientConn); a socket whose writer fails or
    stalls is closed and its own reader thread runs the normal disconnect
    cleanup (player_left broadcast, round-end / idle checks)."""
    if isinstance(msg, str) and (LOG_MOVEMENT or not _is_movement(msg, msg_type)):
        logger.debug(f"[SEND] {msg}")
    with lobby_lock:
        seen = set()
        targets = []
        for entry in list(player_slots) + list(spectator_sockets):
            if not entry:
                continue
            s = entry["sock"]
            if s is exclude or id(s) in seen:
                continue
            seen.add(id(s))
            targets.append(s)
    frame = ws_frame(msg)
    movement = msg_type in MOVEMENT_TYPES if msg_type is not None else isinstance(msg, (bytes, bytearray))
    with conns_lock:
        queues = [(s, conns.get(id(s))) for s in targets]
    for s, conn in queues:
        if conn is None:
            try:
                s.sendall(frame)
            except Exception:
                try: s.close()
                except Exception: pass
        else:
            conn.enqueue(frame, movement)

# ── Match state helpers (every one of these expects lobby_lock to be held) ────
def _present_players():
    return [i + 1 for i in range(4) if player_slots[i]]

def _release_seat(sock, addr, label, old_id, why):
    """Give a seat back and make its socket a plain spectator again.

    Used by leave_slot (the player pressed SPECTATE or LEAVE MATCH) and by the
    harness gate (v0.0.23, the server takes the seat back). Mid-match the seat
    is held for FORFEIT_GRACE seconds first, so two players leaving together do
    not hand one of them a win. Everyone else hears player_left."""
    with lobby_lock:
        player_slots[old_id - 1] = None
        player_locked.pop(old_id, None)
        token = slot_tokens.pop(old_id, None)
        if token:
            recent_slots[token] = (old_id, time.time())
        in_match = global_match_state == 'PLAYING' and old_id in global_playing_players
        if in_match:
            _hold_seat(label, old_id, None, FORFEIT_GRACE)
        else:
            _remove_player(old_id)
        player_bots.pop(old_id, None)
        player_tapes.pop(old_id, None)
        spectator_sockets.append({"sock": sock, "addr": str(addr), "label": label, "ip": _ip(addr)})  # pure spectator again
        logger.info(f"[LEAVE] P{old_id} {why}")
        broadcast(json.dumps({
            "type": "player_left",
            "id": old_id,
            "active_players": _present_players(),
        }))
        if not in_match:
            _idle_reset_if_empty(label)
            _check_round_end(label)

def _state_snapshot(ptype, **extra):
    d = {
        "type":            ptype,
        "active_players":  _present_players(),
        "playing_players": list(global_playing_players),
        "match_state":     global_match_state,
        "locked_players":  {str(k): v for k, v in player_locked.items()},
        "player_names":    {str(k): v for k, v in player_names.items()},
        "current_round":   global_current_round,
        "scores":          global_player_scores,
        "stocks":          global_player_stocks,
        "arena_flips":     global_arena_flips,
    }
    d.update(extra)
    return d

def _remove_player(pid):
    for lst in (global_playing_players, global_waiting_players):
        while pid in lst:
            lst.remove(pid)
    global_alive_players.discard(pid)
    pending_rejoin.pop(pid, None)

def _reset_match_state():
    global global_match_state, global_playing_players, global_waiting_players, global_current_round
    global global_alive_players, global_is_round_over, global_transition_sent, global_round_player_count
    global global_match_over, global_arena_flips
    global_match_over = False
    global_match_state = 'LOBBY'
    global_playing_players = []
    global_waiting_players = []
    global_current_round = 1
    global_alive_players = set()
    global_is_round_over = False
    global_transition_sent = False
    global_round_player_count = 0
    global_arena_flips = 0
    for i in range(1, 5):
        global_player_scores[i] = 0
        global_player_stocks[i] = 3
    player_locked.clear()
    pending_rejoin.clear()
    last_death.clear()

def _setup_match():
    global global_match_state, global_playing_players, global_waiting_players, global_current_round
    global global_alive_players, global_is_round_over, global_transition_sent, global_round_player_count
    global global_arena_flips
    present = _present_players()
    global_match_state = 'PLAYING'
    global_current_round = 1
    global_playing_players = list(present)
    global_waiting_players = []
    global_alive_players = set(present)
    global_is_round_over = False
    global_transition_sent = False
    global_round_player_count = len(present)
    global_arena_flips = 0
    for i in range(1, 5):
        global_player_scores[i] = 0
        global_player_stocks[i] = 3
    pending_rejoin.clear()
    last_death.clear()
    # A new match: the fight telemetry starts from zero (v0.0.22).
    for i in range(1, 5):
        match_kd[i] = {"kills": 0, "deaths": 0}
    match_timeline["started_at"] = time.time()
    _stats_log({"kind": "match", "event": "start", "players": list(present),
                "names": {str(p): player_names.get(p, "Bot") for p in present}})
    player_tapes.clear()   # v0.0.25: no tape card from the last match
    match_timeline["kills"] = []
    match_timeline["rounds"] = [[1, 0.0, None, None]]
    match_timeline["ended_at"] = None
    match_timeline["winner"] = None
    match_timeline["names"] = {}
    _stamp_names(present)

def _stamp_names(pids):
    """(lobby_lock held) Remember the names behind the seat numbers on the
    timeline (v0.0.24), so the deck still says who killed whom after a seat
    changed hands."""
    for pid in pids:
        if pid in player_names:
            match_timeline["names"][str(pid)] = player_names[pid]

def _match_t():
    """Seconds since the match started, for the timeline."""
    started = match_timeline["started_at"]
    return round(time.time() - started, 1) if started else 0.0

def _live_alive():
    """Alive fighters that are actually connected. A fighter inside its rejoin
    grace is neither a winner nor a loser until the grace runs out."""
    return {p for p in global_alive_players if p not in pending_rejoin}

def _check_round_end(label):
    """End the round when at most one connected fighter is alive, judged on LIVE
    state. (The old code compared against a per-thread `active` list captured at
    each player's join, so a round hung whenever the first joiner was eliminated last.)"""
    global global_is_round_over, global_match_over
    if global_match_state != 'PLAYING' or global_is_round_over:
        return False
    live = _live_alive()
    if len(live) > 1 or global_round_player_count < 2:
        return False
    global_is_round_over = True
    winner = next(iter(live)) if len(live) == 1 else 0
    if match_timeline["rounds"]:
        match_timeline["rounds"][-1][2] = winner   # close the round marker on the timeline
        match_timeline["rounds"][-1][3] = _match_t()
    if winner > 0:
        global_player_scores[winner] += 1
        if global_player_scores[winner] >= MATCH_SCORE_LIMIT:
            global_match_over = True
            match_timeline["ended_at"] = _match_t()   # v0.0.24: the deck draws the match end
            match_timeline["winner"] = winner
    # v0.0.26: "replay": true tells every screen (and the harness) that a replay is due,
    # and the server waits REPLAY_ROUND_DELAY instead of NEXT_ROUND_DELAY. A draw or a
    # forfeit win has no closing kill to show, so the short gap stays.
    replay = winner > 0 and bool(last_death) and time.time() - max(last_death.values()) < REPLAY_KILL_WINDOW
    if global_match_over:
        logger.info(f"[ROUND] round {global_current_round} over: P{winner} ({player_names.get(winner, 'Bot')}) "
                    f"wins the match with {global_player_scores[winner]} crowns, lobby in {MATCH_END_DELAY:g} s")
    elif winner > 0:
        logger.info(f"[ROUND] round {global_current_round} over: P{winner} ({player_names.get(winner, 'Bot')}) wins, "
                    f"crowns {dict(global_player_scores)}")
    else:
        logger.info(f"[ROUND] round {global_current_round} over: no winner")
    _stats_log({"kind": "round", "event": "over", "round": global_current_round, "winner": winner,
                "crowns": dict(global_player_scores), "match_over": global_match_over})
    broadcast(json.dumps({
        "type": "round_end",
        "winner": winner,
        "scores": global_player_scores,
        "round": global_current_round,
        "match_over": global_match_over,
        "replay": replay,
    }))
    threading.Thread(target=_next_round_later, args=(label, replay), daemon=True, name="next_round").start()
    return True

def _next_round_later(label, replay=False):
    """The ONLY place a new round starts. Clients wait for new_round; they no longer
    advance on their own timer. `replay` (v0.0.26) = the round ended on a kill, so the
    screens are playing their tapes back and the gap is REPLAY_ROUND_DELAY."""
    global global_current_round, global_is_round_over, global_alive_players, global_round_player_count
    with lobby_lock:
        won = global_match_over
    time.sleep(MATCH_END_DELAY if won else (REPLAY_ROUND_DELAY if replay else NEXT_ROUND_DELAY))
    with lobby_lock:
        if global_match_state != 'PLAYING':
            return  # idle reset already returned everyone to the lobby
        # v0.0.28 (backlog 13): a seat the server is still holding (page reload, hidden
        # phone) counts as present. Before, a fighter that dropped inside the replay gap
        # ended the match ("only 1 player left") although its seat was held for 8 s. If
        # it never comes back, _grace_expired ends the new round as a forfeit instead.
        held = [p for p in global_playing_players if not player_slots[p - 1] and p in pending_rejoin]
        present = [p for p in global_playing_players if player_slots[p - 1] or p in pending_rejoin]
        if global_match_over or global_waiting_players or len(present) < 2:
            if global_match_over:
                reason = f"match won ({MATCH_SCORE_LIMIT} crowns)"
            elif global_waiting_players:
                reason = "waiting players want in"
            else:
                reason = f"only {len(present)} player(s) left"
            logger.info(f"[MATCH] over, back to the lobby ({reason})")
            _stats_log({"kind": "match", "event": "end", "reason": reason,
                        "winner": match_timeline["winner"], "rounds": global_current_round})
            _reset_match_state()
            broadcast(json.dumps({"type": "return_to_lobby"}))
        else:
            global_current_round += 1
            global_is_round_over = False
            global_alive_players = set(present)
            global_round_player_count = len(present)
            for i in range(1, 5):
                global_player_stocks[i] = 3
            last_death.clear()
            match_timeline["rounds"].append([global_current_round, _match_t(), None, None])
            _stats_log({"kind": "round", "event": "start", "round": global_current_round, "players": list(present)})
            _stamp_names(present)
            logger.info(f"[ROUND] round {global_current_round} starting with {present}"
                        + (f" (seat held for {held}, back within the grace or out)" if held else ""))
            broadcast(json.dumps({"type": "new_round", "round": global_current_round}))

def _idle_reset_if_empty(label):
    """Last active player gone mid-match: back to a clean LOBBY. Spectators still
    watching the arena are sent back too."""
    if global_match_state == 'PLAYING' and not _present_players():
        logger.info(f"[MATCH] last player left mid-match, back to the lobby (idle reset)")
        _stats_log({"kind": "match", "event": "end", "reason": "idle reset", "winner": None,
                    "rounds": global_current_round})
        _reset_match_state()
        broadcast(json.dumps({"type": "return_to_lobby"}))

def _hold_seat(label, pid, token, delay):
    """(lobby_lock held) A fighter's place in the match is kept for `delay` seconds.
    A disconnect mid-match (page reload, Wi-Fi blip) gets REJOIN_GRACE with its token;
    an explicit leave gets FORFEIT_GRACE so two players leaving together produce no
    accidental forfeit win. The round is only decided when the grace runs out."""
    global _grace_seq
    _grace_seq += 1
    pending_rejoin[pid] = {"token": token, "seq": _grace_seq, "until": time.time() + delay}
    threading.Thread(target=_grace_expired, args=(label, pid, _grace_seq, delay), daemon=True, name="grace").start()

def _grace_expired(label, pid, seq, delay):
    time.sleep(delay)
    with lobby_lock:
        entry = pending_rejoin.get(pid)
        if entry is None or entry["seq"] != seq:
            return  # came back, or superseded
        pending_rejoin.pop(pid, None)
        _remove_player(pid)
        if player_slots[pid - 1] is None:
            player_locked.pop(pid, None)
            player_names.pop(pid, None)
            player_bots.pop(pid, None)
            player_tapes.pop(pid, None)
        logger.info(f"[LEAVE] P{pid} did not come back within {delay:g} s, out of the match")
        _idle_reset_if_empty(label)
        _check_round_end(label)

def ws_client_thread(sock, addr, label, skip_handshake=False):
    global global_transition_sent, global_arena_flips
    if not skip_handshake and not ws_handshake(sock):
        try: sock.close()
        except: pass
        return

    # Relay traffic is many small frames; without TCP_NODELAY the second frame of a
    # burst waits for the peer's delayed ACK (~40 ms stalls, seen as RTT spikes).
    # Liveness is TCP keepalive, not application pings: a browser tab in the
    # background stops running Godot (no pings for minutes) but its socket is alive,
    # and dropping it every 10 s was the source of most playtest chaos. A dead peer
    # (Wi-Fi gone) is detected by the kernel in ~25 s.
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
        idle, interval, probes = TCP_KEEPALIVE
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, idle)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, interval)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, probes)
    except OSError:
        pass

    sock.settimeout(CLIENT_READ_TIMEOUT)
    conn = ClientConn(sock, label)
    with conns_lock:
        conns[id(sock)] = conn
    assigned_id = None
    with lobby_lock:
        spectator_sockets.append({"sock": sock, "addr": str(addr), "label": label, "ip": _ip(addr)})
        snapshot = _state_snapshot("spectator_state")

    logger.info(f"[CONN] spectator connected via {label} from {_ip(addr)}")
    ws_send(sock, json.dumps(snapshot))
    if harness_gate["active"]:
        ws_send(sock, _harness_status_packet())   # v0.0.23: the ticker, so a new spectator sees it at once

    try:
        while True:
            frame = ws_read(sock)
            if frame is None:
                break
            opcode, payload = frame
            conn.in_pkts += 1
            conn.in_bytes += len(payload)
            conn.last_rx = time.time()
            if assigned_id is not None and id(sock) in demoted_socks:
                # v0.0.23: the harness gate took this seat back from the status
                # thread. This thread only learns it here, so forget the seat now.
                with lobby_lock:
                    demoted_socks.discard(id(sock))
                assigned_id = None
            if opcode == 0:
                continue

            if opcode == 2:
                # Binary movement packet: validate shape, stamp the sender, relay. Never parsed further.
                if assigned_id is None:
                    continue
                spec = BIN_TYPES.get(payload[0]) if payload else None
                if spec is None or len(payload) != spec[1]:
                    logger.warning(f"[NET] P{assigned_id} sent an invalid binary packet "
                                   f"({len(payload)} B, type {payload[0] if payload else '-'}), dropped")
                    continue
                _stat_in_type(spec[0])
                stamped = bytearray(payload)
                stamped[1] = assigned_id
                if payload[0] == 1 and batcher is not None:
                    batcher.add(assigned_id, sock, bytes(stamped[1:]))   # relayed as part of the next sync_bundle
                else:
                    broadcast(bytes(stamped), exclude=sock, msg_type=spec[0])
                continue

            msg = payload
            if len(msg) > MAX_RELAY_BYTES:
                logger.warning(f"[NET] {_who(assigned_id)} sent a {len(msg)} B text message (cap {MAX_RELAY_BYTES}), dropped")
                continue
            mtype = None
            if LOG_MOVEMENT or not _is_movement(msg):
                logger.debug(f"[MSG] {_who(assigned_id)} {msg}")
            try:
                data = json.loads(msg)
            except ValueError:
                logger.warning(f"[NET] {_who(assigned_id)} sent invalid JSON, dropped: {msg[:80]!r}")
                continue
            if not isinstance(data, dict):
                continue
            mtype = data.get("type")
            _stat_in_type(mtype if mtype is not None else "<no-type>")

            try:
                if mtype == "ping":
                    # Echo the client's timestamp (if any) so it can measure round-trip time.
                    # v0.0.22: the client also tells us the round trip it measured last
                    # time ("rtt", in ms), so the dashboard can show a ping per seat.
                    rtt = _as_int(data.get("rtt"), -1)
                    if 0 <= rtt < 60000:
                        conn.rtt_ms = rtt
                    ws_send(sock, json.dumps({"type": "pong", "t": data.get("t")}))
                    continue

                if mtype in SERVER_ONLY_TYPES:
                    logger.warning(f"[NET] {_who(assigned_id)} sent server-only packet {mtype!r}, dropped")
                    continue

                if mtype == "leave_slot":
                    if assigned_id is not None:
                        _release_seat(sock, addr, label, assigned_id, "gave up its seat and is a spectator again")
                        assigned_id = None
                    continue

                if mtype == "request_join":
                    client_version = data.get("version", "")
                    expected_version = get_game_version()
                    logger.debug(f"[JOIN] request via {label} from {_ip(addr)}: client {client_version!r}, server {expected_version!r}")
                    if client_version != expected_version:
                        logger.warning(f"[JOIN] rejected via {label} from {_ip(addr)}: client build {client_version!r}, "
                                       f"server {expected_version!r} (old page in the browser cache?)")
                        ws_send(sock, json.dumps({"type": "version_error", "server_version": expected_version}))
                        continue
                    if harness_gate["active"] and _bot_from_join(data.get("bot"), 0) is None:
                        # v0.0.23: tests are running, so a human waits and watches.
                        logger.info(f"[GATE] join refused via {label} from {_ip(addr)}: the harness is running, humans watch for now")
                        ws_send(sock, json.dumps({"type": "join_locked", "demoted": False, **harness_gate}))
                        continue

                    with lobby_lock:
                        if assigned_id is not None:
                            continue
                        try:
                            reclaim_id = int(data.get("reclaim_id", 0) or 0)
                        except (TypeError, ValueError):
                            reclaim_id = 0
                        token = str(data.get("token", ""))[:64]
                        hot_reclaim = False
                        rejoin = False
                        target = None
                        # A saved slot number is only honoured with the client token that held
                        # it: a page reload (hot reclaim), a fighter inside its rejoin grace, or
                        # a client that left the lobby less than RECENT_SLOT_S ago. Everyone
                        # else fills the lowest free slot, 1 -> 2 -> 3 -> 4.
                        if 1 <= reclaim_id <= 4 and token:
                            cur = player_slots[reclaim_id - 1]
                            if cur is not None and cur["sock"] is not sock:
                                if slot_tokens.get(reclaim_id) == token:
                                    hot_reclaim = True
                                    target = reclaim_id
                                    try: cur["sock"].close()
                                    except: pass
                            else:
                                pend = pending_rejoin.get(reclaim_id)
                                recent = recent_slots.get(token)
                                if pend is not None and pend["token"] == token:
                                    rejoin = True
                                    target = reclaim_id
                                elif recent and recent[0] == reclaim_id and time.time() - recent[1] < RECENT_SLOT_S:
                                    target = reclaim_id
                        if target is None:
                            for i in range(4):
                                if player_slots[i] is None and (i + 1) not in pending_rejoin:
                                    target = i + 1
                                    break
                        if target is None:
                            logger.warning(f"[JOIN] rejected via {label} from {_ip(addr)}: all 4 seats are taken")
                            ws_send(sock, json.dumps({"type": "server_full"}))
                            continue
                        player_slots[target - 1] = {"sock": sock, "addr": str(addr), "label": label, "ip": _ip(addr)}
                        assigned_id = target
                        if token:
                            slot_tokens[assigned_id] = token
                            recent_slots.pop(token, None)

                        # A slot holder is no longer a pure spectator. Leaving it in both
                        # lists made every broadcast arrive twice.
                        spectator_sockets[:] = [s for s in spectator_sockets if s["sock"] is not sock]
                        if rejoin:
                            pending_rejoin.pop(assigned_id, None)   # seat resumed: still playing, still alive
                        elif not hot_reclaim:
                            _remove_player(assigned_id)
                            if global_match_state == 'PLAYING':
                                global_waiting_players.append(assigned_id)
                            else:
                                global_playing_players.append(assigned_id)
                        pending = pending_names.pop(id(sock), None)
                        if pending:
                            player_names[assigned_id] = _unique_name(pending, assigned_id)
                        # v0.0.22: a headless bot says so when it joins, so the dashboard
                        # can show a bot badge before the first bot_status packet arrives.
                        bot_card = _bot_from_join(data.get("bot"), assigned_id)
                        if bot_card is not None:
                            player_bots[assigned_id] = bot_card
                        else:
                            player_bots.pop(assigned_id, None)
                        # rejoined: this socket resumed its own seat in a RUNNING match (page
                        # reload inside the grace, or hot reclaim). The client keeps its ammo.
                        snapshot = _state_snapshot("assign_id", id=assigned_id,
                                                   rejoined=bool((rejoin or hot_reclaim) and global_match_state == 'PLAYING'
                                                                 and assigned_id in global_playing_players))
                        joined = {
                            "type":            "player_joined",
                            "id":              assigned_id,
                            "active_players":  snapshot["active_players"],
                            "playing_players": snapshot["playing_players"],
                            "player_names":    snapshot["player_names"],
                        }

                    known_name = snapshot["player_names"].get(str(assigned_id))
                    logger.info(f"[JOIN] P{assigned_id} took seat {assigned_id} via {label} from {_ip(addr)}"
                                + (f" as '{known_name}'" if known_name else "")
                                + (f" (bot: {bot_card['persona']})" if bot_card else "")
                                + (" (hot reclaim)" if hot_reclaim else "") + (" (rejoined mid-match)" if rejoin else ""))
                    ws_send(sock, json.dumps(snapshot))
                    if not hot_reclaim:
                        broadcast(json.dumps(joined), exclude=sock)
                    continue

                if mtype == "set_name":
                    name = str(data.get("name", ""))[:12]
                    if assigned_id is None:
                        # Clients confirm a saved name before pressing JOIN; keep it for the slot.
                        pending_names[id(sock)] = name
                        continue
                    with lobby_lock:
                        final = _unique_name(name, assigned_id)
                        player_names[assigned_id] = final
                        names = {str(k): v for k, v in player_names.items()}
                    if final != name:
                        logger.info(f"[NAME] P{assigned_id} asked for '{name}', it was taken, now '{final}'")
                    else:
                        logger.info(f"[NAME] P{assigned_id} is now '{final}'")
                    broadcast(json.dumps({"type": "name_update", "player_names": names}))
                    continue

                if assigned_id is None:
                    continue  # spectators may only ping / request_join / set_name

                if mtype == "bot_status":
                    # v0.0.22: a bot brain's numbers (persona, actions, aim, and empty slots
                    # for the future). Kept for status.json only, never sent to the players.
                    if len(msg) > BOT_STATUS_MAX_BYTES:
                        logger.debug(f"[NET] P{assigned_id} bot_status too big ({len(msg)} B), dropped")
                        continue
                    card = {k: v for k, v in data.items() if k not in ("type", "sender")}
                    card["seat"] = assigned_id
                    card["schema"] = _as_int(card.get("schema"), 1)
                    persona = card.get("persona")
                    card["persona"] = persona.strip()[:BOT_PERSONA_MAX] if isinstance(persona, str) else "?"
                    card["kind"] = "protocol" if card.get("kind") == "protocol" else "brain"
                    card["updated_at"] = time.time()
                    with lobby_lock:
                        player_bots[assigned_id] = card
                    continue

                if mtype == "client_stats":
                    # v0.0.37: the client's NetStats card. Kept for status.json and the
                    # jsonl only, never sent to the players.
                    if len(msg) > CLIENT_STATS_MAX_BYTES:
                        logger.debug(f"[NET] {_who(assigned_id)} client_stats too big ({len(msg)} B), dropped")
                        continue
                    card = {k: v for k, v in data.items() if k not in ("type", "sender")}
                    card["seat"] = assigned_id or 0
                    card["addr"] = _ip(addr)
                    card["link"] = label
                    with lobby_lock:
                        card["name"] = player_names.get(assigned_id, "?") if assigned_id else "spectator"
                        card["state"] = global_match_state
                        card["round"] = global_current_round if global_match_state == 'PLAYING' else 0
                    card["updated_at"] = time.time()
                    with client_stats_lock:
                        client_stats[id(sock)] = card
                    _stats_log(dict(card, kind="card"))
                    continue

                if mtype == "history_status":
                    # Phase 3c (v0.0.25): the screen's tape card: how many frames it holds,
                    # the last kill it stamped, and whether it froze for the round. Kept for
                    # status.json only (seats[].tape), never sent to the players.
                    if len(msg) > TAPE_STATUS_MAX_BYTES:
                        logger.debug(f"[NET] P{assigned_id} history_status too big ({len(msg)} B), dropped")
                        continue
                    card = {k: v for k, v in data.items() if k not in ("type", "sender")}
                    card["seat"] = assigned_id
                    card["schema"] = _as_int(card.get("schema"), 1)
                    card["frames"] = _as_int(card.get("frames"), 0)
                    card["round"] = _as_int(card.get("round"), 0)
                    card["stamps"] = _as_int(card.get("stamps"), 0)
                    card["frozen"] = bool(card.get("frozen"))
                    card["recording"] = bool(card.get("recording"))
                    last = card.get("last")
                    if not isinstance(last, dict):
                        last = None
                    card["last"] = last
                    # v0.0.26: the replay card: {playing, played, round, frames, drawn, dur_ms, late_ms, cut, skipped}
                    rp = card.get("replay")
                    card["replay"] = rp if isinstance(rp, dict) else None
                    card["updated_at"] = time.time()
                    with lobby_lock:
                        player_tapes[assigned_id] = card
                    if rp is not None and card["replay"] is not None:
                        if rp.get("skipped"):
                            logger.info(f"[TAPE] P{assigned_id}'s screen skipped the round {_as_int(rp.get('round'), 0)} replay: {rp.get('skipped')}")
                        elif rp.get("played"):
                            logger.info(f"[TAPE] P{assigned_id}'s screen played the round {_as_int(rp.get('round'), 0)} replay: "
                                        f"{_as_int(rp.get('frames'), 0)} frames in {_as_int(rp.get('dur_ms'), 0) / 1000.0:.1f} s, "
                                        f"started {_as_int(rp.get('late_ms'), 0) / 1000.0:.1f} s after the round end"
                                        + (", cut by the next round" if rp.get("cut") else ""))
                        else:
                            logger.debug(f"[TAPE] P{assigned_id}'s screen is playing the round {_as_int(rp.get('round'), 0)} replay")
                    elif card["frozen"]:
                        if last and last.get("closing"):
                            k, v = _as_int(last.get("killer"), 0), _as_int(last.get("victim"), 0)
                            what = (f"P{v} fell to its own '{last.get('weapon')}'" if k == v
                                    else f"P{k} killed P{v} with '{last.get('weapon')}'")
                            logger.info(f"[TAPE] P{assigned_id}'s screen froze the round {card['round']} tape: "
                                        f"{what}, {_as_int(last.get('before'), 0)} frames before, "
                                        f"{_as_int(last.get('after'), 0)} after")
                        else:
                            logger.info(f"[TAPE] P{assigned_id}'s screen froze the round {card['round']} tape: "
                                        f"no closing kill, {card['frames']} frames")
                    else:
                        logger.debug(f"[TAPE] P{assigned_id}'s screen stamped a kill: {last}")
                    continue

                if mtype in ("force_start", "match_started"):
                    # Transition guard: only the first start request sets the match up,
                    # only the first match_started broadcasts scene_transition. Every
                    # client sends match_started after its countdown; without the guard
                    # each one reloaded the arena for everybody.
                    with lobby_lock:
                        if global_match_state == 'LOBBY':
                            logger.info(f"[MATCH] starting, lobby -> arena ({mtype} from P{assigned_id}, players {_present_players()})")
                            _setup_match()
                            if mtype == "force_start":
                                player_locked[assigned_id] = int(data.get("class", 0))
                        elif mtype == "force_start":
                            logger.info(f"[MATCH] force_start from P{assigned_id} ignored, match already {global_match_state}")
                            continue
                        if mtype == "match_started":
                            if global_transition_sent:
                                logger.debug(f"[MATCH] match_started from P{assigned_id} ignored, transition already sent")
                                continue
                            global_transition_sent = True
                    if mtype == "match_started":
                        broadcast(json.dumps({"type": "scene_transition"}))
                        continue
                    # force_start: relay so the other lobbies run their reveal countdown
                    data["sender"] = assigned_id
                    broadcast(json.dumps(data, separators=(",", ":")))
                    continue

                if mtype == "player_died":
                    # Observer-authoritative: whichever client sees the hit reports it (the
                    # victim's own client, the attacker's for melee and stomps, a spectator).
                    # The first report inside DEATH_DEDUPE_S counts, the rest are the same death.
                    # _as_int (v0.0.22): a wrong type here used to raise and leave a
                    # traceback in the log. Now a bad victim is simply not a seat, so it is dropped.
                    victim = _as_int(data.get("victim"), 0)
                    killer = _as_int(data.get("killer"), 0)
                    weapon = data.get("weapon", "Unknown")
                    weapon = weapon if isinstance(weapon, str) else str(weapon)
                    if not 1 <= victim <= 4:
                        continue
                    with lobby_lock:
                        now = time.time()
                        if global_match_state != 'PLAYING' or victim not in global_alive_players or victim in pending_rejoin:
                            logger.debug(f"[KILL] death of P{victim} reported by P{assigned_id} ignored (not a live fighter)")
                            continue
                        if now - last_death.get(victim, 0.0) < DEATH_DEDUPE_S:
                            logger.debug(f"[KILL] death of P{victim} reported by P{assigned_id} ignored (same death reported twice)")
                            continue
                        last_death[victim] = now
                        victim_name = player_names.get(victim, "Bot")
                        killer_name = player_names.get(killer, "Bot")
                        _stamp_names((killer, victim))
                        left = global_player_stocks[victim] - 1
                        if killer == victim:
                            logger.info(f"[KILL] P{victim} ({victim_name}) fell to its own '{weapon}', "
                                        f"{_lives_text(left)} (seen by P{assigned_id})")
                        else:
                            logger.info(f"[KILL] P{killer} ({killer_name}) killed P{victim} ({victim_name}) with '{weapon}', "
                                        f"{_lives_text(left)} (seen by P{assigned_id})")
                        # Fight telemetry (v0.0.22): count it and put it on the timeline.
                        match_kd[victim]["deaths"] += 1
                        if 1 <= killer <= 4 and killer != victim:
                            match_kd[killer]["kills"] += 1
                        if len(match_timeline["kills"]) < TIMELINE_MAX_KILLS:
                            match_timeline["kills"].append([_match_t(), killer, victim, weapon[:16], global_current_round])
                        global_player_stocks[victim] -= 1
                        if global_player_stocks[victim] <= 0:
                            global_alive_players.discard(victim)
                        broadcast(json.dumps({
                            "type": "player_died",
                            "victim": victim,
                            "killer": killer,
                            "stock": global_player_stocks[victim],
                            "weapon": weapon[:16],   # v0.0.25: every screen stamps the same weapon on its tape
                        }))
                        _check_round_end(label)
                    continue

                if mtype == "lock_in":
                    logger.info(f"[LOCK] P{assigned_id} locked in as {CLASS_NAMES.get(data.get('class'), data.get('class'))}")
                    with lobby_lock:
                        player_locked[assigned_id] = int(data.get("class", 0))

                if mtype == "activate_powerup":
                    # Track the arena flip so a client arriving mid-match (spectator
                    # reconnect, late joiner) draws the platforms the right way up.
                    with lobby_lock:
                        global_arena_flips += 1

                # Fall-through relay for the remaining JSON events (lock_in, powerups, anything
                # unknown and small). The sender is stamped from the assigned slot: clients
                # cannot impersonate each other. Movement travels as binary (above).
                data["sender"] = assigned_id
                broadcast(json.dumps(data, separators=(",", ":")), exclude=sock, msg_type=mtype)
            except Exception:
                logger.exception(f"[NET] error handling {mtype!r} from {_who(assigned_id)}")
    except Exception:
        pass

    # ── Cleanup ─────────────────────────────────────────────────────────────
    with conns_lock:
        conns.pop(id(sock), None)
    with client_stats_lock:
        client_stats.pop(id(sock), None)
    conn.close()
    with lobby_lock:
        spectator_sockets[:] = [s for s in spectator_sockets if s["sock"] is not sock]
        demoted_socks.discard(id(sock))
        pending_names.pop(id(sock), None)

    if assigned_id is not None:
        freed = False
        in_match = False
        with lobby_lock:
            entry = player_slots[assigned_id - 1]
            if entry and entry["sock"] is sock:
                player_slots[assigned_id - 1] = None
                token = slot_tokens.pop(assigned_id, None)
                if token:
                    recent_slots[token] = (assigned_id, time.time())
                in_match = global_match_state == 'PLAYING' and assigned_id in global_playing_players
                if in_match:
                    # Seat, name and class are kept for REJOIN_GRACE: a page reload comes back
                    # into the same fight. player_left still goes out so the puppet freezes.
                    _hold_seat(label, assigned_id, token, REJOIN_GRACE)
                else:
                    player_locked.pop(assigned_id, None)
                    player_names.pop(assigned_id, None)
                    player_bots.pop(assigned_id, None)
                    player_tapes.pop(assigned_id, None)
                    _remove_player(assigned_id)
                freed = True
                remaining = _present_players()
        if freed:
            logger.info(f"[LEAVE] P{assigned_id} disconnected via {label}, remaining {remaining}"
                        + (f" (seat held {REJOIN_GRACE:g} s)" if in_match else ""))
            broadcast(json.dumps({
                "type":           "player_left",
                "id":             assigned_id,
                "active_players": remaining,
            }))
            if not in_match:
                with lobby_lock:
                    _idle_reset_if_empty(label)
                    _check_round_end(label)
        else:
            # Slot was taken over by a reclaim: the new socket owns it, say nothing.
            logger.info(f"[CONN] P{assigned_id} old socket closed after a hot reclaim (seat kept by the new connection)")
    else:
        logger.info(f"[CONN] spectator left via {label} from {_ip(addr)}")

    try: sock.close()
    except: pass

def start_ws():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", WS_PORT))
    srv.listen(8)
    logger.info(f"[NET] WS  relay -> ws://0.0.0.0:{WS_PORT}")
    while True:
        c, a = srv.accept()
        threading.Thread(target=ws_client_thread, args=(c, a, "WS"), daemon=True).start()

def start_wss():
    raw = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    raw.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    raw.bind(("0.0.0.0", WSS_PORT))
    raw.listen(8)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
    srv = ctx.wrap_socket(raw, server_side=True)
    logger.info(f"[NET] WSS relay -> wss://0.0.0.0:{WSS_PORT}")
    while True:
        try:
            c, a = srv.accept()
            threading.Thread(target=ws_client_thread, args=(c, a, "WSS"), daemon=True).start()
        except Exception:
            pass

class GameHTTPHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BUILD_DIR, **kwargs)

    def translate_path(self, path):
        path = path.split('?', 1)[0]
        return super().translate_path(path)

    def do_GET(self):
        # One stable URL for everyone: "/" (or "/play") redirects to the current
        # versioned page. The version is read live from global.gd, so this follows
        # every bump_build.sh run and survives an editor F5 re-export, which rewrites
        # the plain index.html without the mainPack patch.
        path = self.path.split('?', 1)[0].rstrip('/') or '/'
        # A refresh of an old versioned page (pruned by bump_build.sh --clean) lands
        # on the current one instead of a 404.
        stale_versioned = (re.fullmatch(r"/index_v\d+\.\d+\.\d+\.html", path)
                           and not os.path.exists(os.path.join(BUILD_DIR, path.lstrip('/'))))
        if path in ('/', '/index.html', '/play') or stale_versioned:
            target = f"/index_{get_game_version()}.html"
            if os.path.exists(os.path.join(BUILD_DIR, target.lstrip('/'))):
                self.send_response(302)
                self.send_header("Location", target)
                self.end_headers()
                return
        super().do_GET()

    def handle_one_request(self):
        try:
            self.raw_requestline = self.rfile.readline(65537)
            if not self.raw_requestline:
                self.close_connection = True
                return
            if not self.parse_request():
                return
            
            # Hijack WebSocket
            if self.headers.get("Upgrade", "").lower() == "websocket":
                key = self.headers.get("Sec-WebSocket-Key", "")
                if key:
                    accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
                    self.connection.sendall((
                        "HTTP/1.1 101 Switching Protocols\r\n"
                        "Upgrade: websocket\r\n"
                        "Connection: Upgrade\r\n"
                        f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
                    ).encode())
                    self.close_connection = True
                    ws_client_thread(self.connection, self.client_address, "MERGED-WS", skip_handshake=True)
                    return

            mname = 'do_' + self.command
            if not hasattr(self, mname):
                self.send_error(501, "Unsupported method (%r)" % self.command)
                return
            method = getattr(self, mname)
            method()
            self.wfile.flush()
        except socket.timeout as e:
            self.log_error("Request timed out: %r", e)
            self.close_connection = True
            return

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy",   "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin",  "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()
    def log_message(self, fmt, *args):
        pass

def start_http():
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer(("0.0.0.0", HTTP_PORT), GameHTTPHandler) as h:
        h.serve_forever()

def start_https():
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
    with socketserver.ThreadingTCPServer(("0.0.0.0", HTTPS_PORT), GameHTTPHandler) as h:
        h.socket = ctx.wrap_socket(h.socket, server_side=True)
        h.serve_forever()

def local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

if __name__ == "__main__":
    if not os.path.exists(BUILD_DIR):
        print(f"ERROR: build dir not found: {BUILD_DIR}")
        sys.exit(1)

    ip = local_ip()
    print("\n" + "="*60)
    print("  TOWERBRAWL — 4-Player Family Server")
    print(f"  Game version      -> {get_game_version()}  (from scripts/global.gd)")
    print(f"  Phones / tablets  -> https://{ip}:{HTTPS_PORT}")
    print(f"  PC / browser      -> http://{ip}:{HTTP_PORT}")
    print("  WS + WSS share ONE lobby. Everyone sees everyone.")
    print(f"  Movement logging  -> {'ON' if LOG_MOVEMENT else 'off'}   Stats every {STATS_INTERVAL:g}s")
    print(f"  Live status       -> status.json every {STATUS_INTERVAL:g}s   (./venv/bin/python tools/watch_server.py)")
    print("="*60 + "\n")

    threading.Thread(target=start_ws,   daemon=True).start()
    threading.Thread(target=start_wss,  daemon=True).start()
    threading.Thread(target=start_http, daemon=True).start()
    if STATS_INTERVAL > 0:
        threading.Thread(target=stats_loop, daemon=True, name="stats").start()
    if STATUS_INTERVAL > 0:
        threading.Thread(target=status_loop, daemon=True, name="status").start()
        _stats_log({"kind": "server", "event": "start", "version": get_game_version(), "pid": os.getpid()})

    try:
        start_https()
    except KeyboardInterrupt:
        print("\nServer stopped.")

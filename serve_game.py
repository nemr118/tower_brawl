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

# Set up dedicated game server logging
logger = logging.getLogger("TowerBrawl")
logger.setLevel(logging.DEBUG)
formatter = logging.Formatter('%(asctime)s | %(levelname)-7s | %(message)s', datefmt='%H:%M:%S')

# Console output (journalctl)
ch = logging.StreamHandler(sys.stdout)
ch.setFormatter(formatter)
ch.setLevel(logging.DEBUG)
logger.addHandler(ch)

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

import hashlib
import base64
import struct
import json

# Fallback only. bump_build.sh rewrites this line, but get_game_version() below
# prefers the live value in scripts/global.gd so a running server accepts a
# freshly built client without a restart.
GAME_VERSION = "v0.0.16"

# Phase 0 knobs ---------------------------------------------------------------
LOG_MOVEMENT   = False   # True = log every sync_pos / spawn_projectile relay (very noisy, slows the relay)
MOVEMENT_TYPES = ("sync_pos", "spawn_projectile", "ping")
STATS_INTERVAL = 10.0    # seconds between [STATS] lines in server.log, 0 = off

# Phase 2: parser hardening + binary movement packets -------------------------
MAX_FRAME_BYTES = 4096   # a frame header claiming more than this closes the socket (no trusting the length field)
MAX_RELAY_BYTES = 1024   # text messages above this are dropped, never relayed (no amplification)
# Binary packets: [0] type, [1] sender slot (stamped here), fixed-size body. See global.gd.
BIN_TYPES = {1: ("sync_pos", 11), 2: ("spawn_projectile", 9)}   # sync_pos gained a u16 tick (Phase 3a)

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

def _stat_in(nbytes):
    with net_stats_lock:
        net_stats["in_pkts"] += 1
        net_stats["in_bytes"] += nbytes

def _stat_in_type(mtype):
    with net_stats_lock:
        net_stats["in_types"][mtype] = net_stats["in_types"].get(mtype, 0) + 1

def _stat_out(nbytes, ok):
    with net_stats_lock:
        if ok:
            net_stats["out_pkts"] += 1
            net_stats["out_bytes"] += nbytes
        else:
            net_stats["out_fail"] += 1

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
            spectators = len(spectator_sockets)   # sockets without a slot (a slot holder is not in here)
            state = global_match_state
        top = ", ".join(f"{k}={v}" for k, v in sorted(s["in_types"].items(), key=lambda kv: -kv[1])[:6])
        logger.info(
            f"[STATS {STATS_INTERVAL:.0f}s] {state} players={players} spectators={spectators} sockets={players + spectators}"
            f" | IN {s['in_pkts'] / STATS_INTERVAL:6.1f} pkt/s {s['in_bytes'] / STATS_INTERVAL / 1024:6.2f} KB/s"
            f" (avg {s['in_bytes'] / max(s['in_pkts'], 1):.0f} B)"
            f" | OUT {s['out_pkts'] / STATS_INTERVAL:6.1f} pkt/s {s['out_bytes'] / STATS_INTERVAL / 1024:6.2f} KB/s"
            f" fail={s['out_fail']} drop={s['out_drop']} | in: {top or '-'}")

# ── Shared lobby ──────────────────────────────────────────────────────────────
# player_slots[i] = {"sock": socket, "addr": str}  or  None
player_slots  = [None, None, None, None]
player_locked = {}
player_names  = {}          # {player_id(int): class_int}
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
NEXT_ROUND_DELAY = 2.6              # seconds between round_end and new_round / return_to_lobby
MATCH_END_DELAY = 6.0               # seconds the "wins the match" banner stays before return_to_lobby
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
            logger.warning(f"frame header claims {plen} bytes (cap {MAX_FRAME_BYTES}); closing connection")
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
            logger.warning(f"[{self.label}] client not reading ({why}); disconnecting")
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

def _stat_drop():
    with net_stats_lock:
        net_stats["out_drop"] += 1

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
                     "version_error", "server_full", "pong"}

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
        logger.debug(f"BROADCAST: {msg}")
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
    if winner > 0:
        global_player_scores[winner] += 1
        if global_player_scores[winner] >= MATCH_SCORE_LIMIT:
            global_match_over = True
    if global_match_over:
        logger.info(f"[{label}] ROUND {global_current_round} OVER! P{winner} WINS THE MATCH "
                    f"({global_player_scores[winner]} crowns) -> lobby in {MATCH_END_DELAY:g}s")
    else:
        logger.info(f"[{label}] ROUND {global_current_round} OVER! Winner: P{winner}")
    broadcast(json.dumps({
        "type": "round_end",
        "winner": winner,
        "scores": global_player_scores,
        "round": global_current_round,
        "match_over": global_match_over,
    }))
    threading.Thread(target=_next_round_later, args=(label,), daemon=True, name="next_round").start()
    return True

def _next_round_later(label):
    """The ONLY place a new round starts. Clients wait for new_round; they no longer
    advance on their own timer."""
    global global_current_round, global_is_round_over, global_alive_players, global_round_player_count
    with lobby_lock:
        won = global_match_over
    time.sleep(MATCH_END_DELAY if won else NEXT_ROUND_DELAY)
    with lobby_lock:
        if global_match_state != 'PLAYING':
            return  # idle reset already returned everyone to the lobby
        present = [p for p in global_playing_players if player_slots[p - 1]]
        if global_match_over or global_waiting_players or len(present) < 2:
            if global_match_over:
                reason = f"match won ({MATCH_SCORE_LIMIT} crowns)"
            elif global_waiting_players:
                reason = "waiting players want in"
            else:
                reason = f"only {len(present)} player(s) left"
            logger.info(f"[{label}] MATCH OVER -> LOBBY ({reason})")
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
            logger.info(f"[{label}] NEW ROUND STARTING: Round {global_current_round}")
            broadcast(json.dumps({"type": "new_round", "round": global_current_round}))

def _idle_reset_if_empty(label):
    """Last active player gone mid-match: back to a clean LOBBY. Spectators still
    watching the arena are sent back too."""
    if global_match_state == 'PLAYING' and not _present_players():
        logger.info(f"[{label}] Last player left mid-match -> LOBBY (idle reset)")
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
        logger.info(f"[{label}] P{pid} did not return within {delay:g} s: removed from the match")
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
        spectator_sockets.append({"sock": sock, "addr": str(addr)})
        snapshot = _state_snapshot("spectator_state")

    print(f"[{label}] Spectator CONNECTED  addr={addr}")
    ws_send(sock, json.dumps(snapshot))

    try:
        while True:
            frame = ws_read(sock)
            if frame is None:
                break
            opcode, payload = frame
            if opcode == 0:
                continue

            if opcode == 2:
                # Binary movement packet: validate shape, stamp the sender, relay. Never parsed further.
                if assigned_id is None:
                    continue
                spec = BIN_TYPES.get(payload[0]) if payload else None
                if spec is None or len(payload) != spec[1]:
                    logger.warning(f"[{label}] P{assigned_id} sent an invalid binary packet "
                                   f"({len(payload)} B, type {payload[0] if payload else '-'}), dropped")
                    continue
                _stat_in_type(spec[0])
                stamped = bytearray(payload)
                stamped[1] = assigned_id
                broadcast(bytes(stamped), exclude=sock, msg_type=spec[0])
                continue

            msg = payload
            if len(msg) > MAX_RELAY_BYTES:
                logger.warning(f"[{label}] P{assigned_id} sent a {len(msg)} B text message (cap {MAX_RELAY_BYTES}), dropped")
                continue
            mtype = None
            if LOG_MOVEMENT or not _is_movement(msg):
                print(f"DEBUG_PRINT: from P{assigned_id}: {msg}")
            try:
                data = json.loads(msg)
            except ValueError:
                logger.warning(f"[{label}] P{assigned_id} sent invalid JSON, dropped: {msg[:80]!r}")
                continue
            if not isinstance(data, dict):
                continue
            mtype = data.get("type")
            _stat_in_type(mtype if mtype is not None else "<no-type>")

            try:
                if mtype == "ping":
                    # Echo the client's timestamp (if any) so it can measure round-trip time.
                    ws_send(sock, json.dumps({"type": "pong", "t": data.get("t")}))
                    continue

                if mtype in SERVER_ONLY_TYPES:
                    logger.warning(f"[{label}] P{assigned_id} sent server-only packet {mtype!r}, dropped")
                    continue

                if mtype == "leave_slot":
                    with lobby_lock:
                        if assigned_id is not None:
                            old_id = assigned_id
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
                            assigned_id = None
                            spectator_sockets.append({"sock": sock, "addr": str(addr)})  # pure spectator again
                            print(f"[{label}] P{old_id} became spectator.")
                            broadcast(json.dumps({
                                "type": "player_left",
                                "id": old_id,
                                "active_players": _present_players(),
                            }))
                            if not in_match:
                                _idle_reset_if_empty(label)
                                _check_round_end(label)
                    continue

                if mtype == "request_join":
                    client_version = data.get("version", "")
                    expected_version = get_game_version()
                    logger.info(f"[{label}] request_join received! version='{client_version}', expected='{expected_version}'")
                    if client_version != expected_version:
                        logger.warning(f"[{label}] REJECTED join due to version mismatch! (stale cached .pck?)")
                        ws_send(sock, json.dumps({"type": "version_error", "server_version": expected_version}))
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
                            print("DEBUG_JOIN: Server full")
                            ws_send(sock, json.dumps({"type": "server_full"}))
                            continue
                        player_slots[target - 1] = {"sock": sock, "addr": str(addr)}
                        assigned_id = target
                        if token:
                            slot_tokens[assigned_id] = token
                            recent_slots.pop(token, None)
                        print(f"DEBUG_JOIN: Assigned ID: {assigned_id}")

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
                            player_names[assigned_id] = pending
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

                    logger.info(f"[{label}] Player Status Update: Spectator became ACTIVE PLAYER (P{assigned_id})"
                                + (" [hot reclaim]" if hot_reclaim else "") + (" [rejoined mid-match]" if rejoin else ""))
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
                        player_names[assigned_id] = name
                        names = {str(k): v for k, v in player_names.items()}
                    broadcast(json.dumps({"type": "name_update", "player_names": names}))
                    continue

                if assigned_id is None:
                    continue  # spectators may only ping / request_join / set_name

                if mtype in ("force_start", "match_started"):
                    # Transition guard: only the first start request sets the match up,
                    # only the first match_started broadcasts scene_transition. Every
                    # client sends match_started after its countdown; without the guard
                    # each one reloaded the arena for everybody.
                    with lobby_lock:
                        if global_match_state == 'LOBBY':
                            logger.info(f"[{label}] SCENE TRANSITION: Lobby -> Arena (Match Starting, {mtype} from P{assigned_id})")
                            _setup_match()
                            if mtype == "force_start":
                                player_locked[assigned_id] = int(data.get("class", 0))
                        elif mtype == "force_start":
                            logger.info(f"[{label}] force_start from P{assigned_id} ignored: match already {global_match_state}")
                            continue
                        if mtype == "match_started":
                            if global_transition_sent:
                                logger.debug(f"[{label}] match_started from P{assigned_id} ignored: transition already sent")
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
                    victim = int(data.get("victim", 0))
                    killer = int(data.get("killer", 0))
                    weapon = data.get("weapon", "Unknown")
                    if not 1 <= victim <= 4:
                        continue
                    with lobby_lock:
                        now = time.time()
                        if global_match_state != 'PLAYING' or victim not in global_alive_players or victim in pending_rejoin:
                            logger.debug(f"[{label}] death of P{victim} reported by P{assigned_id} ignored (not a live fighter)")
                            continue
                        if now - last_death.get(victim, 0.0) < DEATH_DEDUPE_S:
                            logger.debug(f"[{label}] death of P{victim} reported by P{assigned_id} ignored (duplicate report)")
                            continue
                        last_death[victim] = now
                        victim_name = player_names.get(victim, "Bot")
                        killer_name = player_names.get(killer, "Bot")
                        if killer == victim:
                            logger.info(f"[{label}] P{victim} ({victim_name}) COMMITTED SUICIDE with '{weapon}' (reported by P{assigned_id})")
                        else:
                            logger.info(f"[{label}] P{victim} ({victim_name}) was KILLED by P{killer} ({killer_name}) with '{weapon}' (reported by P{assigned_id})")
                        global_player_stocks[victim] -= 1
                        if global_player_stocks[victim] <= 0:
                            global_alive_players.discard(victim)
                        broadcast(json.dumps({
                            "type": "player_died",
                            "victim": victim,
                            "killer": killer,
                            "stock": global_player_stocks[victim],
                        }))
                        _check_round_end(label)
                    continue

                if mtype == "lock_in":
                    logger.info(f"[{label}] P{assigned_id} LOCKED IN as class {data.get('class')}")
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
                logger.exception(f"[{label}] error handling {mtype!r} from P{assigned_id}")
    except Exception:
        pass

    # ── Cleanup ─────────────────────────────────────────────────────────────
    with conns_lock:
        conns.pop(id(sock), None)
    conn.close()
    with lobby_lock:
        spectator_sockets[:] = [s for s in spectator_sockets if s["sock"] is not sock]
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
                    _remove_player(assigned_id)
                freed = True
                remaining = _present_players()
        if freed:
            print(f"[{label}] P{assigned_id} LEFT    remaining={remaining}" + (f"  (seat held {REJOIN_GRACE:g} s)" if in_match else ""))
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
            logger.info(f"[{label}] P{assigned_id} old socket closed after hot reclaim (slot kept by the new connection)")
    else:
        print(f"[{label}] Spectator LEFT")

    try: sock.close()
    except: pass

def start_ws():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", WS_PORT))
    srv.listen(8)
    print(f"WS  relay → ws://0.0.0.0:{WS_PORT}")
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
    print(f"WSS relay → wss://0.0.0.0:{WSS_PORT}")
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
    print("="*60 + "\n")

    threading.Thread(target=start_ws,   daemon=True).start()
    threading.Thread(target=start_wss,  daemon=True).start()
    threading.Thread(target=start_http, daemon=True).start()
    if STATS_INTERVAL > 0:
        threading.Thread(target=stats_loop, daemon=True, name="stats").start()

    try:
        start_https()
    except KeyboardInterrupt:
        print("\nServer stopped.")

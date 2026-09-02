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
GAME_VERSION = "v0.0.5"

# Phase 0 knobs ---------------------------------------------------------------
LOG_MOVEMENT   = False   # True = log every sync_pos / spawn_projectile relay (very noisy, slows the relay)
MOVEMENT_TYPES = ("sync_pos", "spawn_projectile", "ping")
STATS_INTERVAL = 10.0    # seconds between [STATS] lines in server.log, 0 = off

# Phase 2: parser hardening + binary movement packets -------------------------
MAX_FRAME_BYTES = 4096   # a frame header claiming more than this closes the socket (no trusting the length field)
MAX_RELAY_BYTES = 1024   # text messages above this are dropped, never relayed (no amplification)
# Binary packets: [0] type, [1] sender slot (stamped here), fixed-size body. See global.gd.
BIN_TYPES = {1: ("sync_pos", 9), 2: ("spawn_projectile", 9)}
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
             "out_fail": 0, "in_types": {}}

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
                              "out_bytes": 0, "out_fail": 0, "in_types": {}})
        with lobby_lock:
            players = sum(1 for p in player_slots if p)
            sockets = len(spectator_sockets)
            state = global_match_state
        top = ", ".join(f"{k}={v}" for k, v in sorted(s["in_types"].items(), key=lambda kv: -kv[1])[:6])
        logger.info(
            f"[STATS {STATS_INTERVAL:.0f}s] {state} players={players} sockets={sockets}"
            f" | IN {s['in_pkts'] / STATS_INTERVAL:6.1f} pkt/s {s['in_bytes'] / STATS_INTERVAL / 1024:6.2f} KB/s"
            f" (avg {s['in_bytes'] / max(s['in_pkts'], 1):.0f} B)"
            f" | OUT {s['out_pkts'] / STATS_INTERVAL:6.1f} pkt/s {s['out_bytes'] / STATS_INTERVAL / 1024:6.2f} KB/s"
            f" fail={s['out_fail']} | in: {top or '-'}")

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

def ws_send(sock, msg):
    """msg: str -> text frame, bytes -> binary frame."""
    try:
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
        sock.sendall(bytes(frame))
        _stat_out(n, True)
        return True
    except Exception:
        _stat_out(0, False)
        return False

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
    A socket that fails to send is closed; its own thread then runs the normal
    disconnect cleanup (player_left broadcast, round-end / idle checks)."""
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
    for s in targets:
        if not ws_send(s, msg):
            try:
                s.close()
            except Exception:
                pass

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
    }
    d.update(extra)
    return d

def _remove_player(pid):
    for lst in (global_playing_players, global_waiting_players):
        while pid in lst:
            lst.remove(pid)
    global_alive_players.discard(pid)

def _reset_match_state():
    global global_match_state, global_playing_players, global_waiting_players, global_current_round
    global global_alive_players, global_is_round_over, global_transition_sent, global_round_player_count
    global global_match_over
    global_match_over = False
    global_match_state = 'LOBBY'
    global_playing_players = []
    global_waiting_players = []
    global_current_round = 1
    global_alive_players = set()
    global_is_round_over = False
    global_transition_sent = False
    global_round_player_count = 0
    for i in range(1, 5):
        global_player_scores[i] = 0
        global_player_stocks[i] = 3
    player_locked.clear()

def _setup_match():
    global global_match_state, global_playing_players, global_waiting_players, global_current_round
    global global_alive_players, global_is_round_over, global_transition_sent, global_round_player_count
    present = _present_players()
    global_match_state = 'PLAYING'
    global_current_round = 1
    global_playing_players = list(present)
    global_waiting_players = []
    global_alive_players = set(present)
    global_is_round_over = False
    global_transition_sent = False
    global_round_player_count = len(present)
    for i in range(1, 5):
        global_player_scores[i] = 0
        global_player_stocks[i] = 3

def _check_round_end(label):
    """End the round when at most one player is alive, judged on LIVE state.
    (The old code compared against a per-thread `active` list captured at each
    player's join, so a round hung whenever the first joiner was eliminated last.)"""
    global global_is_round_over, global_match_over
    if global_match_state != 'PLAYING' or global_is_round_over:
        return False
    if len(global_alive_players) > 1 or global_round_player_count < 2:
        return False
    global_is_round_over = True
    winner = next(iter(global_alive_players)) if len(global_alive_players) == 1 else 0
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
            logger.info(f"[{label}] NEW ROUND STARTING: Round {global_current_round}")
            broadcast(json.dumps({"type": "new_round", "round": global_current_round}))

def _idle_reset_if_empty(label):
    """Last active player gone mid-match: back to a clean LOBBY. Spectators still
    watching the arena are sent back too."""
    if global_match_state == 'PLAYING' and not _present_players():
        logger.info(f"[{label}] Last player left mid-match -> LOBBY (idle reset)")
        _reset_match_state()
        broadcast(json.dumps({"type": "return_to_lobby"}))

def ws_client_thread(sock, addr, label, skip_handshake=False):
    global global_transition_sent
    if not skip_handshake and not ws_handshake(sock):
        try: sock.close()
        except: pass
        return

    # Relay traffic is many small frames; without TCP_NODELAY the second frame of a
    # burst waits for the peer's delayed ACK (~40 ms stalls, seen as RTT spikes).
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except OSError:
        pass

    sock.settimeout(10.0)
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
                            _remove_player(old_id)
                            assigned_id = None
                            spectator_sockets.append({"sock": sock, "addr": str(addr)})  # pure spectator again
                            print(f"[{label}] P{old_id} became spectator.")
                            broadcast(json.dumps({
                                "type": "player_left",
                                "id": old_id,
                                "active_players": _present_players(),
                            }))
                            _check_round_end(label)
                            _idle_reset_if_empty(label)
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
                        hot_reclaim = False
                        if 1 <= reclaim_id <= 4:
                            old = player_slots[reclaim_id - 1]
                            if old is not None and old["sock"] is not sock:
                                # Hot reclaim (page reload before the old socket timed out): evict it.
                                # Its thread sees the slot is no longer its own and stays silent,
                                # and the roster is unchanged so nobody gets player_joined either.
                                hot_reclaim = True
                                try: old["sock"].close()
                                except: pass
                            player_slots[reclaim_id - 1] = {"sock": sock, "addr": str(addr)}
                            assigned_id = reclaim_id
                        else:
                            for i in range(4):
                                if player_slots[i] is None:
                                    player_slots[i] = {"sock": sock, "addr": str(addr)}
                                    assigned_id = i + 1
                                    break
                        if assigned_id is None:
                            print("DEBUG_JOIN: Server full")
                            ws_send(sock, json.dumps({"type": "server_full"}))
                            continue
                        print(f"DEBUG_JOIN: Assigned ID: {assigned_id}")

                        # A slot holder is no longer a pure spectator. Leaving it in both
                        # lists made every broadcast arrive twice.
                        spectator_sockets[:] = [s for s in spectator_sockets if s["sock"] is not sock]
                        _remove_player(assigned_id)
                        if global_match_state == 'PLAYING':
                            global_waiting_players.append(assigned_id)
                        else:
                            global_playing_players.append(assigned_id)
                        snapshot = _state_snapshot("assign_id", id=assigned_id)
                        joined = {
                            "type":           "player_joined",
                            "id":             assigned_id,
                            "active_players": snapshot["active_players"],
                            "player_names":   snapshot["player_names"],
                        }

                    logger.info(f"[{label}] Player Status Update: Spectator became ACTIVE PLAYER (P{assigned_id})"
                                + (" [hot reclaim]" if hot_reclaim else ""))
                    ws_send(sock, json.dumps(snapshot))
                    if not hot_reclaim:
                        broadcast(json.dumps(joined), exclude=sock)
                    continue

                if assigned_id is None:
                    continue  # spectators may only ping / request_join

                if mtype == "set_name":
                    with lobby_lock:
                        player_names[assigned_id] = str(data.get("name", ""))[:12]
                        names = {str(k): v for k, v in player_names.items()}
                    broadcast(json.dumps({"type": "name_update", "player_names": names}))
                    continue

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
                    victim = int(data.get("victim", 0))
                    killer = int(data.get("killer", 0))
                    weapon = data.get("weapon", "Unknown")
                    if not 1 <= victim <= 4:
                        continue
                    victim_name = player_names.get(victim, "Bot")
                    killer_name = player_names.get(killer, "Bot")
                    if killer == victim:
                        logger.info(f"[{label}] P{victim} ({victim_name}) COMMITTED SUICIDE with '{weapon}'")
                    else:
                        logger.info(f"[{label}] P{victim} ({victim_name}) was KILLED by P{killer} ({killer_name}) with '{weapon}'")
                    with lobby_lock:
                        if victim in global_alive_players:
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
    with lobby_lock:
        spectator_sockets[:] = [s for s in spectator_sockets if s["sock"] is not sock]

    if assigned_id is not None:
        freed = False
        with lobby_lock:
            entry = player_slots[assigned_id - 1]
            if entry and entry["sock"] is sock:
                player_slots[assigned_id - 1] = None
                player_locked.pop(assigned_id, None)
                player_names.pop(assigned_id, None)
                _remove_player(assigned_id)
                freed = True
                remaining = _present_players()
        if freed:
            print(f"[{label}] P{assigned_id} LEFT    remaining={remaining}")
            broadcast(json.dumps({
                "type":           "player_left",
                "id":             assigned_id,
                "active_players": remaining,
            }))
            with lobby_lock:
                _check_round_end(label)
                _idle_reset_if_empty(label)
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

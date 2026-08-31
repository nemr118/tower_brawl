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
import hashlib
import base64
import struct
import json
import os
import sys

HTTP_PORT  = 8000
HTTPS_PORT = 8443
WS_PORT    = 8081
WSS_PORT   = 8444

BASE_DIR  = os.path.dirname(os.path.abspath(__file__))
BUILD_DIR = os.path.join(BASE_DIR, "build", "web")
CERT_FILE = os.path.join(BASE_DIR, "cert.pem")
KEY_FILE  = os.path.join(BASE_DIR, "key.pem")

# ── Shared lobby ──────────────────────────────────────────────────────────────
# player_slots[i] = {"sock": socket, "addr": str}  or  None
player_slots  = [None, None, None, None]
player_locked = {}
player_names  = {}          # {player_id(int): class_int}
lobby_lock    = threading.Lock()
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
        sock.settimeout(None)
        return True
    except Exception:
        return False

def ws_read(sock):
    try:
        head = _recvall(sock, 2)
        b1, b2 = head[0], head[1]
        opcode = b1 & 0x0F
        if opcode == 8:
            return None
        if opcode not in (1, 2):
            return ""
        masked = bool(b2 & 0x80)
        plen   = b2 & 0x7F
        if plen == 126:
            plen = struct.unpack(">H", _recvall(sock, 2))[0]
        elif plen == 127:
            plen = struct.unpack(">Q", _recvall(sock, 8))[0]
        mask = _recvall(sock, 4) if masked else b""
        data = bytearray(_recvall(sock, plen))
        if masked:
            for i in range(len(data)):
                data[i] ^= mask[i % 4]
        return data.decode("utf-8", errors="ignore")
    except Exception:
        return None

def ws_send(sock, text):
    try:
        payload = text.encode("utf-8")
        n = len(payload)
        frame = bytearray([0x81])
        if n <= 125:
            frame.append(n)
        elif n <= 65535:
            frame += bytes([126]) + struct.pack(">H", n)
        else:
            frame += bytes([127]) + struct.pack(">Q", n)
        frame += payload
        sock.sendall(bytes(frame))
        return True
    except Exception:
        return False

def broadcast(msg, exclude=None):
    """Send msg to all connected slots. On send failure, mark slot as dead."""
    with lobby_lock:
        targets = [(i, entry) for i, entry in enumerate(player_slots)
                   if entry and entry["sock"] is not exclude]
    dead_slots = []
    for i, entry in targets:
        if not ws_send(entry["sock"], msg):
            dead_slots.append(i)
    if dead_slots:
        with lobby_lock:
            for i in dead_slots:
                if player_slots[i]:
                    pid = i + 1
                    print(f"[SERVER] Dead socket detected in slot {pid}, freeing")
                    player_slots[i] = None
                    player_locked.pop(pid, None)

def ws_client_thread(sock, addr, label, skip_handshake=False):
    global global_match_state, global_playing_players, global_waiting_players, global_current_round, global_player_scores, global_player_stocks, global_alive_players, global_is_round_over
    if not skip_handshake and not ws_handshake(sock):
        try: sock.close()
        except: pass
        return

    # ── Slot assignment ───────────────────────────────────────────────────────
    # Read optional first frame: client may send {"type":"hello","reclaim_id":N}
    # to reclaim their previous slot after a page reload or reconnect.
    sock.settimeout(0.5)
    reclaim_id = 0
    try:
        hello_msg = ws_read(sock)
        if hello_msg:
            hello = json.loads(hello_msg)
            if hello.get("type") == "hello":
                reclaim_id = int(hello.get("reclaim_id", 0))
                if "name" in hello and hello["name"]:
                    with lobby_lock:
                        player_names[reclaim_id] = str(hello["name"])[:12]
    except Exception:
        pass
    sock.settimeout(None)

    assigned_id = None
    with lobby_lock:
        # Try to reclaim previous slot first
        if 1 <= reclaim_id <= 4 and player_slots[reclaim_id - 1] is None:
            player_slots[reclaim_id - 1] = {"sock": sock, "addr": str(addr)}
            assigned_id = reclaim_id
            print(f"[{label}] P{assigned_id} RECLAIMED slot  addr={addr}")
        else:
            for i in range(4):
                if player_slots[i] is None:
                    player_slots[i] = {"sock": sock, "addr": str(addr)}
                    assigned_id = i + 1
                    break

    if assigned_id is None:
        ws_send(sock, json.dumps({"type": "server_full"}))
        try: sock.close()
        except: pass
        with lobby_lock:
            active = [i+1 for i in range(4) if player_slots[i]]
        print(f"[{label}] Server full — rejected {addr}  active={active}")
        return

    with lobby_lock:
        active = [i+1 for i in range(4) if player_slots[i]]
        if global_match_state == 'PLAYING':
            if assigned_id not in global_playing_players and assigned_id not in global_waiting_players:
                global_waiting_players.append(assigned_id)
        else:
            if assigned_id not in global_playing_players:
                global_playing_players.append(assigned_id)
                
        locked = {str(k): v for k, v in player_locked.items()}
        names  = {str(k): v for k, v in player_names.items()}

    print(f"[{label}] P{assigned_id} JOINED  active={active}  addr={addr}")

    ws_send(sock, json.dumps({
        "type":           "assign_id",
        "id":             assigned_id,
        "active_players": active,
        "playing_players": global_playing_players,
        "match_state": global_match_state,
        "locked_players": locked,
        "player_names": names,
        "current_round": global_current_round,
        "scores": global_player_scores,
        "stocks": global_player_stocks
    }))

    broadcast(json.dumps({
        "type":           "player_joined",
        "id":             assigned_id,
        "active_players": active,
        "player_names": names,
    }), exclude=sock)

    try:
        while True:
            msg = ws_read(sock)
            if msg is None:
                break
            if not msg:
                continue
            try:
                data = json.loads(msg)
                if data.get("type") == "set_name":
                    with lobby_lock:
                        player_names[assigned_id] = str(data.get("name", ""))[:12]
                    broadcast(json.dumps({
                        "type": "name_update",
                        "player_names": {str(k): v for k, v in player_names.items()}
                    }))
                    continue
                
                if data.get("type") == "force_start":
                    with lobby_lock:
                        global_current_round = 1
                        for i in range(1, 5):
                            global_player_scores[i] = 0
                            global_player_stocks[i] = 3
                        global_match_state = 'PLAYING'
                        active_now = [i+1 for i in range(4) if player_slots[i]]
                        global_alive_players = set(active_now)
                        global_playing_players = list(active_now)
                        global_waiting_players = []
                        global_is_round_over = False
                        player_locked[assigned_id] = int(data.get("class", 0))
                    data["sender"] = assigned_id
                    msg = json.dumps(data)
                    broadcast(msg)
                    continue
                    
                if data.get("type") == "player_died":
                    victim = int(data.get("victim", 0))
                    killer = int(data.get("killer", 0))
                    
                    with lobby_lock:
                        if victim in global_alive_players:
                            global_player_stocks[victim] -= 1
                            if global_player_stocks[victim] <= 0:
                                global_alive_players.remove(victim)
                                
                        # broadcast death
                        broadcast(json.dumps({
                            "type": "player_died",
                            "victim": victim,
                            "killer": killer,
                            "stock": global_player_stocks[victim]
                        }))
                        
                        if len(global_alive_players) <= 1 and not global_is_round_over and len(active) > 1:
                            global_is_round_over = True
                            winner = list(global_alive_players)[0] if len(global_alive_players) == 1 else 0
                            if winner > 0:
                                global_player_scores[winner] += 1
                                
                            broadcast(json.dumps({
                                "type": "round_end",
                                "winner": winner,
                                "scores": global_player_scores,
                                "round": global_current_round
                            }))
                            
                            def next_round():
                                global global_current_round, global_is_round_over, global_alive_players, global_player_stocks, global_match_state, global_waiting_players, global_playing_players
                                import time
                                time.sleep(2.6)
                                with lobby_lock:
                                    if len(global_waiting_players) > 0:
                                        global_match_state = 'LOBBY'
                                        global_waiting_players = []
                                        global_playing_players = []
                                        player_locked.clear()
                                        broadcast(json.dumps({"type": "return_to_lobby"}))
                                    else:
                                        global_current_round += 1
                                        global_is_round_over = False
                                        global_alive_players = set([p for p in global_playing_players if player_slots[p-1]])
                                        for i in range(1, 5):
                                            global_player_stocks[i] = 3
                                        broadcast(json.dumps({
                                            "type": "new_round",
                                            "round": global_current_round
                                        }))
                                    
                            import threading
                            threading.Thread(target=next_round, daemon=True).start()
                    continue

                if data.get("type") == "lock_in":
                    with lobby_lock:
                        player_locked[assigned_id] = int(data.get("class", 0))
                    data["sender"] = assigned_id
                    msg = json.dumps(data)
            except Exception:
                pass
            broadcast(msg, exclude=sock)
    except Exception:
        pass

    # Cleanup — only free if this socket still owns the slot
    with lobby_lock:
        if player_slots[assigned_id - 1] and player_slots[assigned_id - 1]["sock"] is sock:
            player_slots[assigned_id - 1] = None
            player_locked.pop(assigned_id, None)
            player_names.pop(assigned_id, None)
        active = [i+1 for i in range(4) if player_slots[i]]

    print(f"[{label}] P{assigned_id} LEFT    remaining={active}")

    broadcast(json.dumps({
        "type":           "player_left",
        "id":             assigned_id,
        "active_players": active,
    }))

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
    print(f"  Phones / tablets  -> https://{ip}:{HTTPS_PORT}")
    print(f"  PC / browser      -> http://{ip}:{HTTP_PORT}")
    print("  WS + WSS share ONE lobby. Everyone sees everyone.")
    print("="*60 + "\n")

    threading.Thread(target=start_ws,   daemon=True).start()
    threading.Thread(target=start_wss,  daemon=True).start()
    threading.Thread(target=start_http, daemon=True).start()

    try:
        start_https()
    except KeyboardInterrupt:
        print("\nServer stopped.")

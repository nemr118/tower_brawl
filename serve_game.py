#!/usr/bin/env python3
"""
TowerBrawl Relay Server
- HTTP  :8000  (desktop web game)
- HTTPS :8443  (mobile web game with SSL)
- WS    :8081  (desktop WebSocket — plain)
- WSS   :8444  (mobile WebSocket — SSL)

CRITICAL: All four endpoints share ONE lobby (player_slots).
Desktop (ws://127.0.0.1:8081) and phones (wss://192.168.4.21:8444)
are in the SAME match room and relay messages to each other.
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

# ── Shared lobby state ────────────────────────────────────────────────────────
# ALL connections — both plain WS and SSL WSS — share this single list.
player_slots  = [None, None, None, None]
player_locked = {}
lobby_lock    = threading.Lock()
# ─────────────────────────────────────────────────────────────────────────────

WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

def ws_handshake(sock):
    try:
        sock.settimeout(5.0)
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

def _recvall(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise ConnectionError("socket closed")
        buf += chunk
    return buf

def ws_read(sock):
    try:
        head = _recvall(sock, 2)
        if not head:
            return None
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
            frame += bytearray([126]) + struct.pack(">H", n)
        else:
            frame += bytearray([127]) + struct.pack(">Q", n)
        frame += payload
        sock.sendall(bytes(frame))
        return True
    except Exception:
        return False

def broadcast(msg, exclude=None):
    with lobby_lock:
        targets = [s for s in player_slots if s and s is not exclude]
    for s in targets:
        ws_send(s, msg)

def ws_client_thread(sock, addr, label):
    if not ws_handshake(sock):
        try: sock.close()
        except: pass
        return

    assigned_id = None
    with lobby_lock:
        for i in range(4):
            if player_slots[i] is None:
                player_slots[i] = sock
                assigned_id = i + 1
                break

    if assigned_id is None:
        ws_send(sock, json.dumps({"type": "server_full"}))
        try: sock.close()
        except: pass
        print(f"[{label}] Server full — rejected {addr}")
        return

    with lobby_lock:
        active = [i+1 for i in range(4) if player_slots[i]]
        locked = {str(k): v for k, v in player_locked.items()}

    print(f"[{label}] P{assigned_id} JOINED  active={active}")

    ws_send(sock, json.dumps({
        "type":           "assign_id",
        "id":             assigned_id,
        "active_players": active,
        "locked_players": locked,
    }))

    broadcast(json.dumps({
        "type":           "player_joined",
        "id":             assigned_id,
        "active_players": active,
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

    with lobby_lock:
        if player_slots[assigned_id - 1] is sock:
            player_slots[assigned_id - 1] = None
        player_locked.pop(assigned_id, None)
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
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy",   "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin",  "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()
    def log_message(self, fmt, *args):
        pass  # suppress file-request noise; keep WS logs readable

def start_http():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", HTTP_PORT), GameHTTPHandler) as h:
        h.serve_forever()

def start_https():
    socketserver.TCPServer.allow_reuse_address = True
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
    with socketserver.TCPServer(("0.0.0.0", HTTPS_PORT), GameHTTPHandler) as h:
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
    print("  TOWERBRAWL 4-Player Family Server")
    print(f"  Phones / tablets  -> https://{ip}:{HTTPS_PORT}")
    print(f"  PC / browser      -> http://{ip}:{HTTP_PORT}")
    print(f"  WS  (desktop)     -> ws://{ip}:{WS_PORT}")
    print(f"  WSS (mobile)      -> wss://{ip}:{WSS_PORT}")
    print("  WS + WSS share ONE lobby. Everyone sees everyone.")
    print("="*60 + "\n")

    threading.Thread(target=start_ws,   daemon=True).start()
    threading.Thread(target=start_wss,  daemon=True).start()
    threading.Thread(target=start_http, daemon=True).start()

    try:
        start_https()
    except KeyboardInterrupt:
        print("\nServer stopped.")

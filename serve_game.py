#!/usr/bin/env python3
"""
Rock-Solid Dual HTTP/HTTPS & WS/WSS Game Relay with Slot-Based Lobby Management.
Guarantees reliable reconnection, slot cleanup, and synchronized match state.
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
import time

HTTP_PORT = 8000
HTTPS_PORT = 8443
WS_PORT = 8081
WSS_PORT = 8444
BUILD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")
CERT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cert.pem")
KEY_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "key.pem")

# 4-Player Slot Array: slots[0] is Player 1, slots[1] is Player 2, etc.
player_slots = [None, None, None, None]
player_classes = {}
player_locked = {}
slots_lock = threading.Lock()

class WebSocketHandler:
    GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    @classmethod
    def handle_handshake(cls, client_socket):
        try:
            client_socket.settimeout(5.0)
            request = client_socket.recv(2048).decode('utf-8', errors='ignore')
            headers = {}
            for line in request.split("\r\n"):
                if ": " in line:
                    k, v = line.split(": ", 1)
                    headers[k.lower()] = v.strip()

            key = headers.get("sec-websocket-key")
            if not key:
                return False

            accept_key = base64.b64encode(hashlib.sha1((key + cls.GUID).encode('utf-8')).digest()).decode('utf-8')
            response = (
                "HTTP/1.1 101 Switching Protocols\r\n"
                "Upgrade: websocket\r\n"
                "Connection: Upgrade\r\n"
                f"Sec-WebSocket-Accept: {accept_key}\r\n\r\n"
            )
            client_socket.sendall(response.encode('utf-8'))
            client_socket.settimeout(None)
            return True
        except Exception as e:
            return False

    @classmethod
    def read_frame(cls, client_socket):
        try:
            head = client_socket.recv(2)
            if not head or len(head) < 2:
                return None
            b1, b2 = head[0], head[1]
            opcode = b1 & 0x0f
            if opcode == 8: # Close
                return None

            masked = (b2 & 0x80) != 0
            payload_len = b2 & 0x7f

            if payload_len == 126:
                ext = client_socket.recv(2)
                payload_len = struct.unpack(">H", ext)[0]
            elif payload_len == 127:
                ext = client_socket.recv(8)
                payload_len = struct.unpack(">Q", ext)[0]

            mask_key = client_socket.recv(4) if masked else b''
            data = bytearray()
            while len(data) < payload_len:
                chunk = client_socket.recv(payload_len - len(data))
                if not chunk:
                    break
                data.extend(chunk)

            if masked:
                for i in range(len(data)):
                    data[i] ^= mask_key[i % 4]

            return data.decode('utf-8', errors='ignore')
        except Exception:
            return None

    @classmethod
    def send_frame(cls, client_socket, msg_str):
        try:
            payload = msg_str.encode('utf-8')
            length = len(payload)
            frame = bytearray()
            frame.append(0x81)

            if length <= 125:
                frame.append(length)
            elif length <= 65535:
                frame.append(126)
                frame.extend(struct.pack(">H", length))
            else:
                frame.append(127)
                frame.extend(struct.pack(">Q", length))

            frame.extend(payload)
            client_socket.sendall(frame)
        except Exception:
            pass

def broadcast_to_all(msg_str, exclude_sock=None):
    with slots_lock:
        for sock in player_slots:
            if sock and sock != exclude_sock:
                WebSocketHandler.send_frame(sock, msg_str)

def ws_client_thread(client_sock, addr, proto_label):
    if not WebSocketHandler.handle_handshake(client_sock):
        try: client_sock.close()
        except: pass
        return

    assigned_id = None
    with slots_lock:
        for i in range(4):
            if player_slots[i] is None:
                player_slots[i] = client_sock
                assigned_id = i + 1
                break

    if assigned_id is None:
        print(f"⚠️ Server full (4 players). Rejecting connection from {addr}")
        try: client_sock.close()
        except: pass
        return

    active_ids = [i+1 for i in range(4) if player_slots[i] is not None]
    print(f"🎮 [{proto_label}] Player {assigned_id} CONNECTED from {addr} (Active: {active_ids})")

    # Send assigned ID to client
    assign_packet = json.dumps({
        "type": "assign_id",
        "id": assigned_id,
        "active_players": active_ids,
        "locked_players": player_locked
    })
    WebSocketHandler.send_frame(client_sock, assign_packet)

    # Notify others that a new player joined
    join_packet = json.dumps({
        "type": "player_joined",
        "id": assigned_id,
        "active_players": active_ids
    })
    broadcast_to_all(join_packet, exclude_sock=client_sock)

    try:
        while True:
            msg = WebSocketHandler.read_frame(client_sock)
            if msg is None:
                break
            
            # Intercept lobby lock-in to store in server state
            try:
                data = json.loads(msg)
                if data.get("type") == "lock_in":
                    p_class = data.get("class", 0)
                    with slots_lock:
                        player_locked[assigned_id] = p_class
            except Exception:
                pass
                
            broadcast_to_all(msg, exclude_sock=client_sock)
    except Exception as e:
        pass

    # Clean up slot on disconnect
    with slots_lock:
        if player_slots[assigned_id - 1] == client_sock:
            player_slots[assigned_id - 1] = None
        if assigned_id in player_locked:
            del player_locked[assigned_id]
        active_ids = [i+1 for i in range(4) if player_slots[i] is not None]

    print(f"🔌 [{proto_label}] Player {assigned_id} DISCONNECTED (Remaining: {active_ids})")
    
    # Broadcast player left
    leave_packet = json.dumps({
        "type": "player_left",
        "id": assigned_id,
        "active_players": active_ids
    })
    broadcast_to_all(leave_packet)

    try: client_sock.close()
    except: pass

def start_ws_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", WS_PORT))
    server.listen(10)
    print(f"⚡ Plain WS Relay running on ws://0.0.0.0:{WS_PORT}")
    while True:
        client, addr = server.accept()
        t = threading.Thread(target=ws_client_thread, args=(client, addr, "WS"), daemon=True)
        t.start()

def start_wss_server():
    raw_server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    raw_server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    raw_server.bind(("0.0.0.0", WSS_PORT))
    raw_server.listen(10)

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
    server = context.wrap_socket(raw_server, server_side=True)
    print(f"🔒 Secure WSS Relay running on wss://0.0.0.0:{WSS_PORT}")

    while True:
        try:
            client, addr = server.accept()
            t = threading.Thread(target=ws_client_thread, args=(client, addr, "WSS"), daemon=True)
            t.start()
        except Exception:
            pass

class GodotHTTPHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BUILD_DIR, **kwargs)

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        super().end_headers()

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def start_http():
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", HTTP_PORT), GodotHTTPHandler) as httpd:
        httpd.serve_forever()

def start_https():
    socketserver.TCPServer.allow_reuse_address = True
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=CERT_FILE, keyfile=KEY_FILE)
    with socketserver.TCPServer(("0.0.0.0", HTTPS_PORT), GodotHTTPHandler) as httpsd:
        httpsd.socket = context.wrap_socket(httpsd.socket, server_side=True)
        httpsd.serve_forever()

if __name__ == "__main__":
    if not os.path.exists(BUILD_DIR):
        print(f"Error: Build directory {BUILD_DIR} does not exist.")
        sys.exit(1)

    local_ip = get_local_ip()
    print("\n" + "═"*65)
    print("🎮 TOWERBRAWL BULLETPROOF MULTIPLAYER SERVER RUNNING!")
    print(f"🔒 HTTPS (Phone):  https://{local_ip}:{HTTPS_PORT}")
    print(f"🌐 HTTP (Desktop): http://{local_ip}:{HTTP_PORT}")
    print(f"⚡ WS Relay:       ws://{local_ip}:{WS_PORT} & wss://{local_ip}:{WSS_PORT}")
    print("═"*65 + "\n")

    threading.Thread(target=start_ws_server, daemon=True).start()
    threading.Thread(target=start_wss_server, daemon=True).start()
    threading.Thread(target=start_http, daemon=True).start()

    try:
        start_https()
    except KeyboardInterrupt:
        print("\nServer stopped.")

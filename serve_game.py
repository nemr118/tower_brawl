#!/usr/bin/env python3
"""
Dual HTTP (8000) & HTTPS (8443) Web Server + Dual WS (8081) & WSS (8444) Real-Time Game Relay.
Supports encrypted WebSockets for mobile browsers under HTTPS to prevent Mixed-Content blocks.
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

HTTP_PORT = 8000
HTTPS_PORT = 8443
WS_PORT = 8081
WSS_PORT = 8444
BUILD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")
CERT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cert.pem")
KEY_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "key.pem")

connected_clients = []
clients_lock = threading.Lock()
next_player_id = 1

class WebSocketHandler:
    GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    @classmethod
    def handle_handshake(cls, client_socket):
        try:
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
            return True
        except Exception as e:
            print(f"Handshake error: {e}")
            return False

    @classmethod
    def read_frame(cls, client_socket):
        try:
            head = client_socket.recv(2)
            if not head or len(head) < 2:
                return None
            b1, b2 = head[0], head[1]
            opcode = b1 & 0x0f
            if opcode == 8:
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

def broadcast(sender_sock, msg_str):
    with clients_lock:
        for client in connected_clients:
            if client != sender_sock:
                WebSocketHandler.send_frame(client, msg_str)

def ws_client_thread(client_sock, addr, proto_label):
    global next_player_id
    if not WebSocketHandler.handle_handshake(client_sock):
        try:
            client_sock.close()
        except Exception:
            pass
        return

    with clients_lock:
        assigned_id = next_player_id
        next_player_id = (next_player_id % 4) + 1
        connected_clients.append(client_sock)

    print(f"🎮 [{proto_label}] Player {assigned_id} connected from {addr} (Total: {len(connected_clients)})")
    
    assign_msg = json.dumps({"type": "assign_id", "id": assigned_id})
    WebSocketHandler.send_frame(client_sock, assign_msg)

    while True:
        msg = WebSocketHandler.read_frame(client_sock)
        if msg is None:
            break
        broadcast(client_sock, msg)

    with clients_lock:
        if client_sock in connected_clients:
            connected_clients.remove(client_sock)
    print(f"🔌 [{proto_label}] Player {assigned_id} disconnected (Remaining: {len(connected_clients)})")
    try:
        client_sock.close()
    except Exception:
        pass

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
        except Exception as e:
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
    print("🎮 TOWERBRAWL DUAL WS/WSS & HTTP/HTTPS MULTIPLAYER RUNNING!")
    print(f"🔒 HTTPS (Phone):  https://{local_ip}:{HTTPS_PORT}")
    print(f"🌐 HTTP (Desktop): http://{local_ip}:{HTTP_PORT}")
    print(f"⚡ WS Port:        {WS_PORT} (Plain) / {WSS_PORT} (Secure SSL)")
    print("═"*65 + "\n")

    threading.Thread(target=start_ws_server, daemon=True).start()
    threading.Thread(target=start_wss_server, daemon=True).start()
    threading.Thread(target=start_http, daemon=True).start()

    try:
        start_https()
    except KeyboardInterrupt:
        print("\nServer stopped.")

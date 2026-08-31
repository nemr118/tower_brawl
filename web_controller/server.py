#!/usr/bin/env python3
"""
Zero-dependency Python HTTP & WebSocket bridge for TowerBrawl Mobile Controllers.
Serves the mobile touch web controller on port 8080.
Bridges WebSocket input packets directly to Godot via UDP port 9090.
"""

import http.server
import socketserver
import socket
import threading
import hashlib
import base64
import struct
import json
import os

HTTP_PORT = 8000
WS_PORT = 8081
GODOT_UDP_PORT = 9090
GODOT_UDP_HOST = "127.0.0.1"

udp_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

def forward_to_godot(msg_str):
    try:
        udp_sock.sendto(msg_str.encode('utf-8'), (GODOT_UDP_HOST, GODOT_UDP_PORT))
    except Exception as e:
        print(f"Error forwarding UDP to Godot: {e}")

class WebSocketHandler:
    GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    @classmethod
    def handle_handshake(cls, client_socket):
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

    @classmethod
    def read_frame(cls, client_socket):
        try:
            head = client_socket.recv(2)
            if not head or len(head) < 2:
                return None
            b1, b2 = head[0], head[1]
            opcode = b1 & 0x0f
            if opcode == 8: # Close frame
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

def ws_client_thread(client_sock, addr):
    print(f"📱 Mobile controller connected from {addr}")
    if not WebSocketHandler.handle_handshake(client_sock):
        client_sock.close()
        return

    while True:
        msg = WebSocketHandler.read_frame(client_sock)
        if msg is None:
            break
        forward_to_godot(msg)

    print(f"📱 Mobile controller disconnected from {addr}")
    client_sock.close()

def start_ws_server():
    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("0.0.0.0", WS_PORT))
    server.listen(10)
    print(f"⚡ WebSocket Server running on ws://0.0.0.0:{WS_PORT}")
    while True:
        client, addr = server.accept()
        t = threading.Thread(target=ws_client_thread, args=(client, addr), daemon=True)
        t.start()

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"

def start_http_server():
    web_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(web_dir)
    handler = http.server.SimpleHTTPRequestHandler
    with socketserver.TCPServer(("0.0.0.0", HTTP_PORT), handler) as httpd:
        local_ip = get_local_ip()
        print("\n" + "="*60)
        print("🎮 TOWERBRAWL MOBILE CONTROLLER SERVER READY!")
        print(f"👉 Open on phone: http://{local_ip}:{HTTP_PORT}")
        print("="*60 + "\n")
        httpd.serve_forever()

if __name__ == "__main__":
    t_ws = threading.Thread(target=start_ws_server, daemon=True)
    t_ws.start()
    start_http_server()

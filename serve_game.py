#!/usr/bin/env python3
"""
High-performance local web server for Godot 4 Web Exports.
Injects COOP/COEP isolation headers required for WebAssembly SharedArrayBuffer.
"""

import http.server
import socketserver
import socket
import os
import sys

PORT = 8000
BUILD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")

class GodotHTTPHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BUILD_DIR, **kwargs)

    def end_headers(self):
        # Cross-Origin Isolation headers for Godot 4 WASM
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

if __name__ == "__main__":
    if not os.path.exists(BUILD_DIR):
        print(f"Error: Build directory {BUILD_DIR} does not exist. Run export first.")
        sys.exit(1)

    local_ip = get_local_ip()
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(("0.0.0.0", PORT), GodotHTTPHandler) as httpd:
        print("\n" + "═"*65)
        print("🎮 TOWERBRAWL LOCAL WEB SERVER RUNNING!")
        print(f"👉 Local PC:    http://localhost:{PORT}")
        print(f"👉 Mobile/LAN:  http://{local_ip}:{PORT}")
        print("═"*65 + "\n")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\nServer stopped.")

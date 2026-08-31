import re

with open("serve_game.py", "r") as f:
    code = f.read()

# 1. Update ws_client_thread signature
code = code.replace("def ws_client_thread(sock, addr, label):", "def ws_client_thread(sock, addr, label, skip_handshake=False):")
code = code.replace("    if not ws_handshake(sock):", "    if not skip_handshake and not ws_handshake(sock):")

# 2. Inject handle_one_request into GameHTTPHandler
handler_injection = """
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
                        "HTTP/1.1 101 Switching Protocols\\r\\n"
                        "Upgrade: websocket\\r\\n"
                        "Connection: Upgrade\\r\\n"
                        f"Sec-WebSocket-Accept: {accept}\\r\\n\\r\\n"
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
"""

code = code.replace("    def end_headers(self):", handler_injection + "\n    def end_headers(self):")

with open("serve_game.py", "w") as f:
    f.write(code)

with open("scripts/global.gd", "r") as f:
    gd = f.read()

gd_new_url = """	if OS.has_feature("web"):
		var js_host = JavaScriptBridge.eval("window.location.hostname", true)
		if js_host and str(js_host) != "":
			host = str(js_host)
			
		var js_port = JavaScriptBridge.eval("window.location.port", true)
		var port_str = ""
		if js_port and str(js_port) != "":
			port_str = ":" + str(js_port)
			
		var js_proto = JavaScriptBridge.eval("window.location.protocol", true)
		if str(js_proto) == "https:":
			server_url = "wss://" + host + port_str
		else:
			server_url = "ws://" + host + port_str
	else:
		server_url = "ws://127.0.0.1:8000" """

gd = re.sub(r'	if OS\.has_feature\("web"\):.*?server_url = "ws://" \+ str\(host\) \+ ":8081"', gd_new_url, gd, flags=re.DOTALL)

with open("scripts/global.gd", "w") as f:
    f.write(gd)


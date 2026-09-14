# ==============================================================================
# The benchmark server (bench/8p). Headless Godot. Runs the stand-in simulation
# at 60 ticks a second, sends every client a snapshot every second tick over wss
# (ws with --no-tls), reads their inputs, answers pings, stores the phones' bench
# cards, and writes one line a second about its own cost.
#   godot --headless --path bench res://server/bench_server.tscn -- \
#       [--port 8091] [--fighters 8] [--arrow-cap 24] [--no-tls]
#       [--cert <pem>] [--key <pem>] [--out <dir>] [--seconds N] [--net-thread 0|1]
# --net-thread 1 (the default): TLS handshakes, reading and sending run on their
# own thread, so a join or a slow socket never holds up a tick. 0 = all on one thread.
# --net-sleep-ms N: how long that thread rests between socket checks (default 4;
# on the laptop 1 ms cost twice the CPU for no faster ticks).
# Output: <out>/<date>/server.jsonl (a line a second), cards.jsonl (phone cards).
# ==============================================================================
extends Node

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")

class Client:
	var id: int = 0
	var ip: String = ""
	var name: String = ""
	var tcp: StreamPeerTCP
	var tls: StreamPeerTLS
	var ws: WebSocketPeer
	var state: int = 0          # 0 TLS handshake, 1 websocket
	var since_ms: int = 0
	var bytes_out: int = 0
	var bytes_in: int = 0
	var inputs: int = 0
	var rtt: int = -1
	var gap: int = -1
	var send_fail: int = 0

var sim
var server := TCPServer.new()
var tls_opts: TLSOptions = null
var clients: Array = []
var next_client_id := 1
var buf := StreamPeerBuffer.new()
var pending_events: Array = []
var tick_us := PackedInt64Array()
var interval_us := PackedInt64Array()
var sim_us_sum := 0
var send_us_sum := 0
var last_tick_usec := 0
var sec_start_ms := 0
var started_ms := 0
var bytes_out_sec := 0
var bytes_in_sec := 0
var cpu_last := -1.0
var cpu_last_ms := 0
var server_log: FileAccess
var cards_log: FileAccess
var seconds_limit := 0
var fighters := 8
var arrow_cap := 24
var port := P.PORT
var net_thread_on := true
var net_sleep_us := 4000
var net_thread: Thread
var net_mutex := Mutex.new()
var net_quit := false
var net_out: Array = []          # snapshots waiting for the network thread
var net_tick := 0                # the tick a pong reports
var net_per_client: Array = []   # the client list, published by the network thread
var net_out_pub := 0
var net_in_pub := 0
var net_busy_pub := 0            # microseconds of network work since the last report

func _ready() -> void:
	var o := _args()
	port = int(o.get("port", P.PORT))
	fighters = int(o.get("fighters", 8))
	arrow_cap = int(o.get("arrow-cap", 24))
	seconds_limit = int(o.get("seconds", 0))
	net_thread_on = str(o.get("net-thread", "1")) != "0"
	net_sleep_us = int(float(o.get("net-sleep-ms", 4)) * 1000.0)
	var root_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var out_dir := str(o.get("out", root_dir.path_join("bench_results"))).path_join(Time.get_date_string_from_system())
	DirAccess.make_dir_recursive_absolute(out_dir)
	server_log = FileAccess.open(out_dir.path_join("server.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(out_dir.path_join("server.jsonl")) else FileAccess.WRITE)
	server_log.seek_end()
	cards_log = FileAccess.open(out_dir.path_join("cards.jsonl"), FileAccess.READ_WRITE if FileAccess.file_exists(out_dir.path_join("cards.jsonl")) else FileAccess.WRITE)
	cards_log.seek_end()
	Engine.max_fps = 120     # no busy loop in headless; physics stays at 60
	sim = SimScript.new(fighters, arrow_cap, int(Time.get_unix_time_from_system()))
	if not o.has("no-tls"):
		var cert := X509Certificate.new()
		var key := CryptoKey.new()
		var cert_path := str(o.get("cert", root_dir.path_join("cert.pem")))
		var key_path := str(o.get("key", root_dir.path_join("key.pem")))
		if cert.load(cert_path) != OK or key.load(key_path) != OK:
			printerr("📊 [BenchServer] cannot load the TLS pair %s / %s (use --no-tls for ws)" % [cert_path, key_path])
			get_tree().quit(1)
			return
		tls_opts = TLSOptions.server(key, cert)
	var err := server.listen(port, "*")
	if err != OK:
		printerr("📊 [BenchServer] cannot listen on %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	started_ms = Time.get_ticks_msec()
	sec_start_ms = started_ms
	var info := {"kind": "start", "t": Time.get_unix_time_from_system(), "port": port, "tls": tls_opts != null,
		"fighters": fighters, "arrow_cap": arrow_cap, "godot": Engine.get_version_info().string,
		"cpu": _cpu_model(), "cores": OS.get_processor_count(), "host": OS.get_environment("HOSTNAME"),
		"net_thread": net_thread_on, "net_sleep_ms": net_sleep_us / 1000.0}
	server_log.store_line(JSON.stringify(info))
	server_log.flush()
	print("📊 [BenchServer] %s on %d, %d fighters, arrow cap %d, cpu %s x%d, network thread %s, results in %s" % [
		"wss" if tls_opts != null else "ws", port, fighters, arrow_cap, info["cpu"], info["cores"], "on" if net_thread_on else "off", out_dir])
	if net_thread_on:
		net_thread = Thread.new()
		net_thread.start(_net_loop)

func _args() -> Dictionary:
	var o := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = a[i]
		if k.begins_with("--"):
			k = k.substr(2)
			if "=" in k:
				o[k.get_slice("=", 0)] = k.get_slice("=", 1)
			elif i + 1 < a.size() and not a[i + 1].begins_with("--"):
				o[k] = a[i + 1]
				i += 1
			else:
				o[k] = true
		i += 1
	return o

# Sockets are also read between ticks (120 times a second), so a ping waits at
# most ~8 ms for an answer instead of a whole tick.
func _process(_dt: float) -> void:
	if server.is_listening() and not net_thread_on:
		_poll_clients()

func _physics_process(_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	if last_tick_usec > 0:
		interval_us.append(t0 - last_tick_usec)
	last_tick_usec = t0
	if not net_thread_on:
		_accept()
		_poll_clients()
	var t1 := Time.get_ticks_usec()
	sim.step()
	pending_events.append_array(sim.take_events())
	var t2 := Time.get_ticks_usec()
	if sim.tick % 2 == 0:
		sim.write_snapshot(buf, pending_events)
		pending_events.clear()
		var bytes: PackedByteArray = buf.data_array
		if net_thread_on:
			net_mutex.lock()
			net_out.append(bytes)
			net_tick = sim.tick
			net_mutex.unlock()
		else:
			_send_all(bytes)
	var t3 := Time.get_ticks_usec()
	tick_us.append(t3 - t0)
	sim_us_sum += t2 - t1
	send_us_sum += t3 - t2
	if Time.get_ticks_msec() - sec_start_ms >= 1000:
		_report_second()
	if seconds_limit > 0 and Time.get_ticks_msec() - started_ms >= seconds_limit * 1000:
		print("📊 [BenchServer] --seconds %d reached, stopping" % seconds_limit)
		_stop_net()
		server_log.flush()
		cards_log.flush()
		get_tree().quit(0)

func _accept() -> void:
	while server.is_connection_available():
		var tcp := server.take_connection()
		tcp.set_no_delay(true)
		var c := Client.new()
		c.id = next_client_id
		next_client_id += 1
		c.ip = tcp.get_connected_host()
		c.tcp = tcp
		c.since_ms = Time.get_ticks_msec()
		if tls_opts != null:
			c.tls = StreamPeerTLS.new()
			if c.tls.accept_stream(tcp, tls_opts) != OK:
				print("📊 [BenchServer] TLS accept failed from %s" % c.ip)
				continue
			c.state = 0
		else:
			_start_ws(c, tcp)
		clients.append(c)

func _start_ws(c: Client, stream: StreamPeer) -> void:
	c.ws = WebSocketPeer.new()
	c.ws.outbound_buffer_size = 1 << 20
	c.ws.inbound_buffer_size = 1 << 16
	c.ws.max_queued_packets = 4096
	c.ws.accept_stream(stream)
	c.state = 1

func _poll_clients() -> void:
	var now := Time.get_ticks_msec()
	for i in range(clients.size() - 1, -1, -1):
		var c: Client = clients[i]
		if c.state == 0:
			c.tls.poll()
			var st := c.tls.get_status()
			if st == StreamPeerTLS.STATUS_CONNECTED:
				_start_ws(c, c.tls)
			elif st != StreamPeerTLS.STATUS_HANDSHAKING or now - c.since_ms > 5000:
				print("📊 [BenchServer] TLS handshake failed from %s (status %d)" % [c.ip, st])
				clients.remove_at(i)
			continue
		c.ws.poll()
		var rs := c.ws.get_ready_state()
		if rs == WebSocketPeer.STATE_CLOSED:
			print("📊 [BenchServer] client %d %s (%s) left, code %d" % [c.id, c.name, c.ip, c.ws.get_close_code()])
			clients.remove_at(i)
			continue
		if rs != WebSocketPeer.STATE_OPEN:
			if now - c.since_ms > 8000:
				print("📊 [BenchServer] client %d (%s) never finished the websocket handshake" % [c.id, c.ip])
				clients.remove_at(i)
			continue
		while c.ws.get_available_packet_count() > 0:
			var pkt := c.ws.get_packet()
			c.bytes_in += pkt.size()
			bytes_in_sec += pkt.size()
			if c.ws.was_string_packet():
				_on_text(c, pkt.get_string_from_utf8())
			elif pkt.size() > 0:
				_on_binary(c, pkt)

func _on_binary(c: Client, pkt: PackedByteArray) -> void:
	if pkt[0] == P.T_INPUT:
		c.inputs += 1
	elif pkt[0] == P.T_PING and pkt.size() >= 9:
		c.rtt = pkt.decode_u16(5)
		c.gap = pkt.decode_u16(7)
		var out := PackedByteArray()
		out.resize(9)
		out[0] = P.T_PONG
		out.encode_u32(1, pkt.decode_u32(1))
		out.encode_u32(5, _pong_tick())
		c.ws.put_packet(out)
		c.bytes_out += 9
		bytes_out_sec += 9

func _on_text(c: Client, s: String) -> void:
	var d = JSON.parse_string(s)
	if typeof(d) != TYPE_DICTIONARY:
		return
	if d.get("kind", "") == "hello":
		c.name = str(d.get("name", ""))
		print("📊 [BenchServer] client %d from %s says hello: %s" % [c.id, c.ip, c.name])
	elif d.get("kind", "") == "bench_card":
		d["recv_t"] = Time.get_unix_time_from_system()
		d["ip"] = c.ip
		cards_log.store_line(JSON.stringify(d))
		cards_log.flush()
		print("📊 [BenchServer] card from %s: %s %s p95 %.1f ms p99 %.1f ms fps %.0f" % [
			c.name, d.get("tier", "?"), d.get("res", "?"), float(d.get("ft_p95", 0)), float(d.get("ft_p99", 0)), float(d.get("fps", 0))])

func _report_second() -> void:
	var now := Time.get_ticks_msec()
	var secs := (now - sec_start_ms) / 1000.0
	sec_start_ms = now
	var n := tick_us.size()
	var sorted := tick_us.duplicate()
	sorted.sort()
	var total := 0
	for v in tick_us:
		total += v
	var iv := interval_us.duplicate()
	iv.sort()
	var cpu := _cpu_percent(now)
	var per_client: Array
	var out_b := bytes_out_sec
	var in_b := bytes_in_sec
	var net_busy := 0
	if net_thread_on:
		net_mutex.lock()
		per_client = net_per_client.duplicate(true)
		out_b = net_out_pub
		in_b = net_in_pub
		net_busy = net_busy_pub
		net_out_pub = 0
		net_in_pub = 0
		net_busy_pub = 0
		net_mutex.unlock()
	else:
		per_client = _client_list()
	var rec := {
		"kind": "second", "t": Time.get_unix_time_from_system(), "up_s": (now - started_ms) / 1000.0,
		"clients": per_client.size(), "fighters": fighters, "arrows": sim.live_arrow_count(), "zones": sim.zones.size(),
		"ticks": n, "tick_mean_ms": (total / 1000.0 / n) if n > 0 else 0.0,
		"tick_p99_ms": (sorted[int(n * 0.99)] / 1000.0) if n > 0 else 0.0,
		"tick_max_ms": (sorted[n - 1] / 1000.0) if n > 0 else 0.0,
		"sim_mean_ms": (sim_us_sum / 1000.0 / n) if n > 0 else 0.0,
		"send_mean_ms": (send_us_sum / 1000.0 / n) if n > 0 else 0.0,
		"interval_p99_ms": (iv[int(iv.size() * 0.99)] / 1000.0) if iv.size() > 0 else 0.0,
		"interval_max_ms": (iv[iv.size() - 1] / 1000.0) if iv.size() > 0 else 0.0,
		"out_kbps": out_b / 1000.0 / secs, "in_kbps": in_b / 1000.0 / secs,
		"net_thread": net_thread_on, "net_busy_ms": net_busy / 1000.0 / secs,
		"cpu_pct": cpu, "rss_mb": _rss_mb(), "per_client": per_client,
	}
	server_log.store_line(JSON.stringify(rec))
	server_log.flush()
	var rtts: Array = []
	for pc in per_client:
		rtts.append("%s:%d" % [pc["name"] if pc["name"] != "" else str(pc["id"]), pc["rtt"]])
	print("📊 [BenchServer %3.0fs] clients=%d arrows=%d zones=%d | tick mean %.2f p99 %.2f max %.2f ms (sim %.2f send %.2f) | interval p99 %.1f max %.1f ms | out %.1f KB/s in %.1f KB/s | net thread %.1f ms/s | cpu %.1f%% rss %.0f MB | rtt %s" % [
		rec["up_s"], rec["clients"], rec["arrows"], rec["zones"], rec["tick_mean_ms"], rec["tick_p99_ms"], rec["tick_max_ms"],
		rec["sim_mean_ms"], rec["send_mean_ms"], rec["interval_p99_ms"], rec["interval_max_ms"], rec["out_kbps"], rec["in_kbps"],
		rec["net_busy_ms"], cpu, rec["rss_mb"], " ".join(rtts)])
	tick_us.clear()
	interval_us.clear()
	sim_us_sum = 0
	send_us_sum = 0
	if not net_thread_on:   # with the thread on, these belong to the network thread
		bytes_out_sec = 0
		bytes_in_sec = 0

func _cpu_percent(now_ms: int) -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return -1.0
	var s := f.get_line()   # /proc files report length 0, so read by line
	var fields := s.substr(s.rfind(")") + 2).split(" ")
	if fields.size() < 13:
		return -1.0
	var ticks := float(fields[11]) + float(fields[12])
	var pct := -1.0
	if cpu_last >= 0.0 and now_ms > cpu_last_ms:
		pct = (ticks - cpu_last) / 100.0 / ((now_ms - cpu_last_ms) / 1000.0) * 100.0
	cpu_last = ticks
	cpu_last_ms = now_ms
	return pct

func _rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return -1.0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			return float(line.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
	return -1.0

func _cpu_model() -> String:
	var f := FileAccess.open("/proc/cpuinfo", FileAccess.READ)
	if f == null:
		return "?"
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("model name"):
			return line.split(":")[1].strip_edges()
	return "?"

func _client_list() -> Array:
	var out: Array = []
	for c in clients:
		if c.state == 1:
			out.append({"id": c.id, "name": c.name, "ip": c.ip, "rtt": c.rtt, "gap": c.gap, "fail": c.send_fail})
	return out

func _send_all(bytes: PackedByteArray) -> void:
	for c in clients:
		if c.state == 1 and c.ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
			if c.ws.put_packet(bytes) == OK:
				c.bytes_out += bytes.size()
				bytes_out_sec += bytes.size()
			else:
				c.send_fail += 1

func _pong_tick() -> int:
	if not net_thread_on:
		return sim.tick
	net_mutex.lock()
	var t := net_tick
	net_mutex.unlock()
	return t

# ------------------------------------------------------------ network thread
# Owns the listening socket and every client: accepts, TLS and websocket
# handshakes, reading, pongs, cards and sending. The simulation thread only
# hands over finished snapshots. They share data only under net_mutex, and
# only for a moment, so a slow handshake never blocks a tick.
func _net_loop() -> void:
	var last_pub := 0
	while true:
		net_mutex.lock()
		var quit := net_quit
		var outs: Array = net_out
		net_out = []
		net_mutex.unlock()
		if quit:
			break
		var t0 := Time.get_ticks_usec()
		_accept()
		_poll_clients()
		for bytes in outs:
			_send_all(bytes)
		var busy := Time.get_ticks_usec() - t0
		var now := Time.get_ticks_msec()
		net_mutex.lock()
		net_busy_pub += busy
		net_out_pub += bytes_out_sec
		net_in_pub += bytes_in_sec
		if now - last_pub >= 200:
			net_per_client = _client_list()
			last_pub = now
		net_mutex.unlock()
		bytes_out_sec = 0
		bytes_in_sec = 0
		OS.delay_usec(net_sleep_us)   # 4 ms = check the sockets about 250 times a second

func _stop_net() -> void:
	if net_thread == null:
		return
	net_mutex.lock()
	net_quit = true
	net_mutex.unlock()
	net_thread.wait_to_finish()
	net_thread = null

func _exit_tree() -> void:
	_stop_net()

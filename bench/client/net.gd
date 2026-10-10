# The client's network side: the websocket to server/game_server.gd (or the
# benchmark's bench_server.gd), the hello with the version and the seat token,
# the JSON messages (a queue the client drains), snapshot decoding, a render
# clock 50 ms behind the server, interpolation between two snapshots, the event
# queue, pings, and the network numbers for the benchmark's cards.
extends RefCounted

const P = preload("res://sim/proto.gd")
const DELAY_TICKS := 3.0
const W := 1920.0
const H := 1080.0

var ws := WebSocketPeer.new()
var url := ""
var who := ""
var token := ""
var state := WebSocketPeer.STATE_CLOSED
var snaps: Array = []          # decoded snapshots, oldest first
var events: Array = []         # [tick, event]
var messages: Array = []       # JSON dictionaries from the server, oldest first
var tick_offset := 0.0
var have_clock := false
var client_tick := 0
var input_hist: Array = []
var last_rtt := 0
var worst_gap := 0.0
var last_snap_ms := 0.0
var next_ping_ms := 0.0
# the current measuring window
var rtts := PackedFloat32Array()
var gaps := PackedFloat32Array()
var bytes_in := 0
var win_start_ms := 0.0

func open(u: String, name: String, seat_token: String = "") -> void:
	url = u
	who = name
	token = seat_token
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 1 << 20
	var tls := TLSOptions.client_unsafe() if u.begins_with("wss") and OS.get_name() != "Web" else null
	ws.connect_to_url(u, tls)

func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0

func poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and state != WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify({"kind": "hello", "name": who, "version": P.VERSION, "token": token}))
		win_start_ms = now_ms()
		snaps.clear()
		have_clock = false
	state = st
	if st != WebSocketPeer.STATE_OPEN:
		return
	while ws.get_available_packet_count() > 0:
		var pkt := ws.get_packet()
		bytes_in += pkt.size()
		if pkt.size() == 0:
			continue
		if ws.was_string_packet():
			var d = JSON.parse_string(pkt.get_string_from_utf8())
			if typeof(d) == TYPE_DICTIONARY:
				messages.append(d)
			continue
		if pkt[0] == P.T_SNAP:
			_on_snapshot(pkt)
		elif pkt[0] == P.T_PONG and pkt.size() >= 9:
			var sent := pkt.decode_u32(1)
			last_rtt = int((int(now_ms()) & 0xFFFFFFFF) - sent) & 0xFFFFFFFF
			rtts.append(last_rtt)
	var t := now_ms()
	if t >= next_ping_ms:
		next_ping_ms = t + 500.0
		var out := PackedByteArray()
		out.resize(9)
		out[0] = P.T_PING
		out.encode_u32(1, int(t) & 0xFFFFFFFF)
		out.encode_u16(5, mini(last_rtt, 65535))
		out.encode_u16(7, mini(int(worst_gap), 65535))
		worst_gap = 0.0
		ws.put_packet(out)

# A JSON message to the server ({"kind": ...}).
func send(d: Dictionary) -> bool:
	if state != WebSocketPeer.STATE_OPEN:
		return false
	ws.send_text(JSON.stringify(d))
	return true

func take_messages() -> Array:
	var m := messages
	messages = []
	return m

# 60 times a second from _physics_process: the buttons (proto B_*) and the aim
# in 0.1 degree steps, with the 3 ticks before, so a late packet loses nothing.
func send_input(buttons: int, aim: int) -> void:
	if state != WebSocketPeer.STATE_OPEN:
		return
	client_tick += 1
	var one := PackedByteArray()
	one.resize(8)
	one[0] = P.T_INPUT
	one.encode_u32(1, client_tick)
	one[5] = buttons & 255
	one.encode_u16(6, aim & 0xFFFF)
	input_hist.append(one)
	if input_hist.size() > 4:
		input_hist.pop_front()
	var pkt := PackedByteArray()
	for h in input_hist:
		pkt.append_array(h)
	ws.put_packet(pkt)

# False when the server is not connected: the card is lost.
func send_card(d: Dictionary) -> bool:
	return send(d)

func _on_snapshot(pkt: PackedByteArray) -> void:
	var t := now_ms()
	if last_snap_ms > 0.0:
		var g := t - last_snap_ms
		gaps.append(g)
		worst_gap = maxf(worst_gap, g)
	last_snap_ms = t
	var b := StreamPeerBuffer.new()
	b.data_array = pkt
	b.seek(1)
	var s := {"tick": b.get_u32()}
	s["phase"] = b.get_u8()
	s["round"] = b.get_u8()
	s["left"] = b.get_u16()
	s["goal"] = b.get_u8()
	s["winner"] = b.get_u8()
	var nf := b.get_u8()
	var na := b.get_u16()
	var nz := b.get_u8()
	var ne := b.get_u16()
	var fighters: Array = []
	var by_id := {}
	for i in nf:
		var f := {"id": b.get_u8(), "state": b.get_u8(), "x": float(b.get_16()), "y": float(b.get_16()),
			"vx": b.get_8(), "vy": b.get_8(), "flags": b.get_u8(), "aim": b.get_u8() * TAU / 256.0,
			"arrows": b.get_u8(), "st": b.get_u8(), "points": b.get_u8(), "flags2": b.get_u8()}
		fighters.append(f)
		by_id[f["id"]] = f
	var arrows := {}
	for i in na:
		var id := b.get_u16()
		var ks := b.get_u8()
		arrows[id] = {"kind": ks & 15, "state": ks >> 4, "x": float(b.get_16()), "y": float(b.get_16()),
			"ang": b.get_u8() * TAU / 256.0}
	var zones: Array = []
	for i in nz:
		var z := {"kind": b.get_u8(), "x": float(b.get_16()), "y": float(b.get_16()), "size": float(b.get_u16()),
			"life": b.get_u8() / 255.0}
		b.get_u8()
		zones.append(z)
	for i in ne:
		events.append([s["tick"], [b.get_u8(), b.get_16(), b.get_16(), b.get_u8(), b.get_u8()]])
	s["fighters"] = fighters
	s["by_id"] = by_id
	s["arrows"] = arrows
	s["zones"] = zones
	snaps.append(s)
	while snaps.size() > 8:
		snaps.pop_front()
	var target: float = s["tick"] - t / 1000.0 * 60.0
	if not have_clock or absf(target - tick_offset) > 30.0:
		tick_offset = target
		have_clock = true
	else:
		tick_offset = lerpf(tick_offset, target, 0.05)

func render_tick() -> float:
	return now_ms() / 1000.0 * 60.0 + tick_offset - DELAY_TICKS

# The newest snapshot (empty before the first).
func newest() -> Dictionary:
	return snaps[snaps.size() - 1] if snaps.size() > 0 else {}

func take_events(rt: float) -> Array:
	var out: Array = []
	while events.size() > 0 and events[0][0] <= rt + 2.0:
		out.append(events.pop_front()[1])
	return out

static func _wlerp(a: float, b: float, t: float, size: float) -> float:
	var d := b - a
	if d > size * 0.5:
		d -= size
	elif d < -size * 0.5:
		d += size
	return fposmod(a + d * t, size)

# The world at render tick rt: {fighters: [..], arrows: {id: ..}, zones: [..]}.
# Fighters are matched by seat between the two snapshots. own_id >= 0: that
# fighter comes from the newest snapshot instead (your own, with less lag).
func sample(rt: float, own_id: int = -1) -> Dictionary:
	if snaps.is_empty():
		return {}
	var a: Dictionary = snaps[0]
	var b: Dictionary = snaps[0]
	for i in snaps.size():
		if snaps[i]["tick"] <= rt:
			a = snaps[i]
			b = snaps[mini(i + 1, snaps.size() - 1)]
	if rt < snaps[0]["tick"]:
		a = snaps[0]
		b = snaps[0]
	var span: float = b["tick"] - a["tick"]
	var t := clampf((rt - a["tick"]) / span, 0.0, 1.0) if span > 0.0 else 1.0
	var newest_snap: Dictionary = snaps[snaps.size() - 1]
	var fighters: Array = []
	for fb_raw in b["fighters"]:
		var fb: Dictionary = fb_raw
		if own_id >= 0 and fb["id"] == own_id and newest_snap["by_id"].has(own_id):
			fighters.append(newest_snap["by_id"][own_id].duplicate())
			continue
		var fa: Dictionary = a["by_id"].get(fb["id"], fb)
		var f := fb.duplicate()
		var jx := absf(fb["x"] - fa["x"])
		var jy := absf(fb["y"] - fa["y"])
		# a step, or a wrap across an edge, is smoothed; a respawn jumps
		var smooth: bool = fa["state"] != 2 and fb["state"] != 2 and (jx < 300.0 or jx > 1500.0) and (jy < 300.0 or jy > 800.0)
		if smooth:
			f["x"] = _wlerp(fa["x"], fb["x"], t, W)
			f["y"] = _wlerp(fa["y"], fb["y"], t, H)
		fighters.append(f)
	var arrows := {}
	for id in b["arrows"]:
		var ab: Dictionary = b["arrows"][id]
		if a["arrows"].has(id):
			var aa: Dictionary = a["arrows"][id]
			arrows[id] = {"kind": ab["kind"], "state": ab["state"], "x": _wlerp(aa["x"], ab["x"], t, W),
				"y": _wlerp(aa["y"], ab["y"], t, H), "ang": ab["ang"]}
		else:
			arrows[id] = ab
	return {"fighters": fighters, "arrows": arrows, "zones": b["zones"]}

# The network numbers since the last call, for a bench card.
func take_window() -> Dictionary:
	var t := now_ms()
	var secs := maxf(0.001, (t - win_start_ms) / 1000.0)
	var r := rtts.duplicate()
	r.sort()
	var g := gaps.duplicate()
	g.sort()
	var stalls := 0
	for v in gaps:
		if v > 150.0:
			stalls += 1
	var d := {
		"rtt_med": r[r.size() / 2] if r.size() > 0 else -1.0,
		"rtt_p95": r[int(r.size() * 0.95)] if r.size() > 0 else -1.0,
		"gap_p99": g[int(g.size() * 0.99)] if g.size() > 0 else -1.0,
		"gap_max": g[g.size() - 1] if g.size() > 0 else -1.0,
		"stalls_150ms": stalls,
		"kb_in_s": bytes_in / 1000.0 / secs,
		"snaps_per_s": gaps.size() / secs,
	}
	rtts.clear()
	gaps.clear()
	bytes_in = 0
	win_start_ms = t
	return d

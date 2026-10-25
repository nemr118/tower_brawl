# The client's network side: the websocket to server/game_server.gd (or the
# benchmark's bench_server.gd), the hello with the version and the seat token,
# the JSON messages (a queue the client drains), snapshot decoding, a render
# clock behind the server, interpolation between two snapshots, the event
# queue, pings, and the network numbers for the benchmark's cards.
# P2 (the feel): the predicted clock. Each input carries the server tick it is
# for, and the client runs ahead of the server so the input is there just before
# that tick. T_OWN (proto.gd) says how early the inputs came; ticks_now() adds or
# skips a tick to keep that margin at MARGIN_LO to MARGIN_HI. The draw delay for
# the others follows this client's own snapshot gaps (50 to 133 ms). The test
# knob lag (with jitter) holds every packet sent and got for lag/2 each way.
extends RefCounted

const P = preload("res://sim/proto.gd")
const BoilerScript = preload("res://sim/boiler.gd")
const DELAY_TICKS := 3.0       # the draw delay's floor: 50 ms (a steady phone)
const DELAY_MAX := 8.0         # its ceiling: 133 ms (the benchmark's Pixel needed about 100)
const GAP_KEEP := 150          # the snapshot gaps the draw delay looks at: the last 5 s
const MARGIN_LO := 1           # the predicted clock keeps your inputs 1 to 3 ticks early at the server
const MARGIN_HI := 3
const MARGIN_AIM := 2          # a change aims here
const ADJUST_EVERY := 4        # a slow change adds or skips one tick every 4 (0.75x to 1.25x speed)
const JUMP_TICKS := 20         # the clock is further off than this: jump (the first sync, a stall)
const W := 1920.0
const H := 1080.0
# the events whose a is a fighter (proto.gd); E_EXPLODE's a is the shooter, not the one hurt
const FIGHTER_EVENTS := [P.E_JUMP, P.E_LAND, P.E_DODGE, P.E_SHOOT, P.E_DEATH, P.E_CATCH, P.E_PICKUP,
	P.E_SPAWN, P.E_WALLJUMP, P.E_HURT, P.E_LEDGE, P.E_DRYFIRE]
const ARROW_EVENTS := [P.E_STICK, P.E_TINK]

var ws := WebSocketPeer.new()
var url := ""
var who := ""
var token := ""
var state := WebSocketPeer.STATE_CLOSED
var snaps: Array = []          # decoded snapshots, oldest first
var events: Array = []         # [tick, event]
var messages: Array = []       # JSON dictionaries from the server, oldest first
var owns: Array = []           # decoded T_OWN, oldest first (the client drains them)
var last_arena := 0            # the newest snapshot's arena (G5)
var tick_offset := 0.0
var have_clock := false
var client_tick := 0           # the benchmark's input counter (send_input with no tick)
var input_hist: Array = []
var last_rtt := 0
var worst_gap := 0.0
var last_snap_ms := 0.0
var next_ping_ms := 0.0
var delay_ticks := DELAY_TICKS
var delay_goal := DELAY_TICKS
var gap_hist := PackedFloat32Array()
var next_delay_ms := 0.0
var last_poll_ms := 0.0
# the predicted clock (P2)
var pred_tick := 0             # the newest tick run: the tick of the newest input sent
var synced := false
var jumped := false            # the clock jumped (the caller's prediction starts over); the caller clears it
var margins: Array = []        # [ms, margin] from T_OWN, the last 3 s
var change_wait_ms := 0.0      # no new change before this, and only margins from then on count:
                               # the last change must show in the margins first
var clock_debt := 0            # ticks still to add (> 0) or to skip (< 0), one every ADJUST_EVERY
var pay_now := false           # the debt is for late inputs: add it at once
var adjust_t := 0
var clock_changes := 0
var clock_jumps := 0
var late_total := 0            # from T_OWN: inputs that came after their tick
var margin_log := PackedInt32Array()   # every margin T_OWN reported (the probes read it)
# the test knob: lag and jitter in ms
var lag_ms := 0.0
var jitter_ms := 0.0
var _in_q: Array = []          # [due ms, packet, was a string]
var _out_q: Array = []         # [due ms, PackedByteArray or String]
var _in_due := 0.0
var _out_due := 0.0
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
	_in_q.clear()
	_out_q.clear()

func now_ms() -> float:
	return Time.get_ticks_usec() / 1000.0

func poll() -> void:
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN and state != WebSocketPeer.STATE_OPEN:
		_send_text(JSON.stringify({"kind": "hello", "name": who, "version": P.VERSION, "token": token}))
		win_start_ms = now_ms()
		snaps.clear()
		owns.clear()
		have_clock = false
		synced = false
		pred_tick = 0          # a new connection: the server takes any tick again
		margins.clear()
		clock_debt = 0
		pay_now = false
	state = st
	if st != WebSocketPeer.STATE_OPEN:
		return
	var t := now_ms()
	var lagged := lag_ms > 0.0 or jitter_ms > 0.0
	while ws.get_available_packet_count() > 0:
		var pkt := ws.get_packet()
		var was_text := ws.was_string_packet()
		if lagged:
			_in_due = maxf(_in_due, t + lag_ms * 0.5 + randf() * jitter_ms)
			_in_q.append([_in_due, pkt, was_text])
		else:
			_on_packet(pkt, was_text)
	while _in_q.size() > 0 and _in_q[0][0] <= t:
		var q: Array = _in_q.pop_front()
		_on_packet(q[1], q[2])
	while _out_q.size() > 0 and _out_q[0][0] <= t:
		var o = _out_q.pop_front()[1]
		if o is String:
			ws.send_text(o)
		else:
			ws.put_packet(o)
	if t >= next_ping_ms:
		next_ping_ms = t + 500.0
		var out := PackedByteArray()
		out.resize(9)
		out[0] = P.T_PING
		out.encode_u32(1, int(t) & 0xFFFFFFFF)
		out.encode_u16(5, mini(last_rtt, 65535))
		out.encode_u16(7, mini(int(worst_gap), 65535))
		worst_gap = 0.0
		_send_bin(out)
	_update_delay(t)

func _on_packet(pkt: PackedByteArray, was_text: bool) -> void:
	bytes_in += pkt.size()
	if pkt.size() == 0:
		return
	if was_text:
		var d = JSON.parse_string(pkt.get_string_from_utf8())
		if typeof(d) == TYPE_DICTIONARY:
			messages.append(d)
		return
	if pkt[0] == P.T_SNAP:
		_on_snapshot(pkt)
	elif pkt[0] == P.T_OWN and pkt.size() >= 16:
		_on_own(pkt)
	elif pkt[0] == P.T_PONG and pkt.size() >= 9:
		var sent := pkt.decode_u32(1)
		last_rtt = int((int(now_ms()) & 0xFFFFFFFF) - sent) & 0xFFFFFFFF
		rtts.append(last_rtt)

# Every packet out goes through here (the test knob holds it lag/2 + jitter).
func _send_bin(pkt: PackedByteArray) -> void:
	if lag_ms <= 0.0 and jitter_ms <= 0.0:
		ws.put_packet(pkt)
		return
	_out_due = maxf(_out_due, now_ms() + lag_ms * 0.5 + randf() * jitter_ms)
	_out_q.append([_out_due, pkt])

func _send_text(txt: String) -> void:
	if lag_ms <= 0.0 and jitter_ms <= 0.0:
		ws.send_text(txt)
		return
	_out_due = maxf(_out_due, now_ms() + lag_ms * 0.5 + randf() * jitter_ms)
	_out_q.append([_out_due, txt])

# A JSON message to the server ({"kind": ...}).
func send(d: Dictionary) -> bool:
	if state != WebSocketPeer.STATE_OPEN:
		return false
	_send_text(JSON.stringify(d))
	return true

func take_messages() -> Array:
	var m := messages
	messages = []
	return m

func take_owns() -> Array:
	var o := owns
	owns = []
	return o

# The buttons (proto B_*) and the aim in 0.1 degree steps for one tick, with the
# 3 ticks before, so a late packet loses nothing. The game passes the tick the
# input is for (ticks_now); the benchmark passes none and counts its own.
func send_input(buttons: int, aim: int, tick: int = -1) -> void:
	if state != WebSocketPeer.STATE_OPEN:
		return
	if tick < 0:
		client_tick += 1
		tick = client_tick
	var one := PackedByteArray()
	one.resize(8)
	one[0] = P.T_INPUT
	one.encode_u32(1, tick)
	one[5] = buttons & 255
	one.encode_u16(6, aim & 0xFFFF)
	input_hist.append(one)
	if input_hist.size() > 4:
		input_hist.pop_front()
	var pkt := PackedByteArray()
	for h in input_hist:
		pkt.append_array(h)
	_send_bin(pkt)

# False when the server is not connected: the card is lost.
func send_card(d: Dictionary) -> bool:
	return send(d)

# ------------------------------------------------------------------ the predicted clock (P2)
# The server's tick now, as well as this client can tell: the snapshots' clock
# (tick_offset follows when they arrive) plus half the round trip.
func server_now() -> float:
	return now_ms() / 1000.0 * 60.0 + tick_offset + last_rtt * 0.03

# The ticks to run on this physics tick, each with the buttons of now (60 times a
# second from _physics_process). One normally; while the clock pays a debt (the
# margins said too late or too early), one more or one fewer every ADJUST_EVERY
# ticks, or all at once for late inputs. The first sync, and a clock more than
# JUMP_TICKS behind (a tab that slept), jump: `jumped` turns true and the list
# holds the one new tick. Empty before the first snapshot.
func ticks_now() -> Array:
	if not have_clock or state != WebSocketPeer.STATE_OPEN:
		return []
	var now := now_ms()
	var want := int(server_now() + last_rtt * 0.03) + MARGIN_AIM
	if not synced or pred_tick < want - JUMP_TICKS:
		pred_tick = want
		synced = true
		jumped = true
		clock_jumps += 1
		clock_debt = 0
		pay_now = false
		change_wait_ms = now + last_rtt + 150.0
		return [pred_tick]
	if clock_debt == 0 and now >= change_wait_ms:
		_judge_margins(now)
	var n := 1
	adjust_t += 1
	if pay_now:
		n += clock_debt
		clock_debt = 0
		pay_now = false
	elif clock_debt != 0 and adjust_t >= ADJUST_EVERY:
		adjust_t = 0
		if clock_debt > 0:
			n = 2
			clock_debt -= 1
		else:
			n = 0
			clock_debt += 1
	var out: Array = []
	for i in n:
		pred_tick += 1
		out.append(pred_tick)
	return out

# The margins since the last change: one under 0 (a late input) adds the ticks
# at once; one under MARGIN_LO adds them slowly; all over MARGIN_HI for 1.5 s
# skips slowly. Each brings the margin to MARGIN_AIM.
func _judge_margins(now: float) -> void:
	var lo := 999
	var n := 0
	var first := now
	for m in margins:
		if m[0] >= change_wait_ms - 1.0:
			lo = mini(lo, m[1])
			n += 1
			first = minf(first, m[0])
	if n < 3:
		return
	if lo < MARGIN_LO:
		clock_debt = MARGIN_AIM - lo
		pay_now = lo < 0
	elif lo > MARGIN_HI and now - first >= 1500.0:
		clock_debt = MARGIN_AIM - lo
	else:
		return
	clock_changes += 1
	change_wait_ms = now + (0.0 if pay_now else absi(clock_debt) * ADJUST_EVERY * 16.7) + last_rtt + 150.0

func _on_own(pkt: PackedByteArray) -> void:
	var o := {"tick": pkt.decode_u32(1), "used": pkt.decode_u32(5), "margin": pkt.decode_s8(9),
		"late": pkt[10], "flags": pkt[11], "moves_from": pkt.decode_u32(12), "pkt": pkt, "at": 16,
		"arena": last_arena}   # the server sends the snapshot first, so this is the arena of its tick
	owns.append(o)
	while owns.size() > 64:
		owns.pop_front()
	late_total += int(o["late"])
	if int(o["margin"]) != P.NO_MARGIN:
		var t := now_ms()
		margins.append([t, int(o["margin"])])
		while margins.size() > 0 and margins[0][0] < t - 3000.0:
			margins.pop_front()
		margin_log.append(int(o["margin"]))

# ------------------------------------------------------------------ snapshots and the render clock
func _on_snapshot(pkt: PackedByteArray) -> void:
	var t := now_ms()
	if last_snap_ms > 0.0:
		var g := t - last_snap_ms
		gaps.append(g)
		gap_hist.append(g)
		if gap_hist.size() > GAP_KEEP:
			gap_hist.remove_at(0)
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
	var walls := b.get_u16()
	s["walls"] = float(walls & 0x7FFF)
	s["walls_deadly"] = (walls & P.WALLS_DEADLY_BIT) != 0
	s["arena"] = b.get_u8()
	last_arena = s["arena"]
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
		var st := (ks >> 4) & 3
		var big := (ks & 0x40) != 0     # p4.9 BIG ARROWS
		if st == P.S_STUCK or st == P.S_BODY:   # p4.10: an arrow in a body goes like a stuck one
			arrows[id] = {"kind": ks & 15, "state": st, "x": float(b.get_16()), "y": float(b.get_16()),
				"ang": b.get_u8() * TAU / 256.0, "big": big}
		else:
			var x := b.get_float()
			var y := b.get_float()
			var vx := b.get_float()
			var vy := b.get_float()
			arrows[id] = {"kind": ks & 15, "state": st, "x": x, "y": y, "vx": vx, "vy": vy,
				"ang": atan2(vy, vx), "age": b.get_u8(), "owner": b.get_u8(), "big": big}
	var zones: Array = []
	for i in nz:
		var z := {"kind": b.get_u8(), "x": float(b.get_16()), "y": float(b.get_16()), "size": float(b.get_u16()),
			"life": b.get_u8() / 255.0}
		b.get_u8()
		zones.append(z)
	for i in ne:
		events.append([s["tick"], [b.get_u8(), b.get_16(), b.get_16(), b.get_u8(), b.get_u8()]])
	_read_powers(b, s)
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

# p4.9 the snapshot's power-up part (proto.gd), when there is one: s["powers"]
# {seat: {bits, kind, left (s)}}, s["orbs"] [{state, kind, big, x, y, prog, for}],
# s["cats"] [{owner, target, x, y}], s["rain"] {owner, left (s)}.
func _read_powers(b: StreamPeerBuffer, s: Dictionary) -> void:
	var powers := {}
	var orbs: Array = []
	var cats: Array = []
	var rain := {"owner": P.NO_ONE, "left": 0.0}
	var ghosts: Array = []
	if b.get_available_bytes() > 0 and b.get_u8() == P.PW_TAG:
		for i in b.get_u8():
			var seat := b.get_u8()
			var bits := b.get_u16()
			var kb := b.get_u8()
			var left := b.get_u8() / 4.0
			var mk := b.get_u8()    # p4.12 GHOSTFACE: 1 it is, 2 down, 4 swinging, 8 the knife up
			powers[seat] = {"bits": bits, "kind": kb & 0x7F, "swarm": (kb & 0x80) != 0, "left": left, "mask": mk}
		for i in b.get_u8():
			orbs.append({"state": b.get_u8(), "kind": b.get_u8(), "big": b.get_u8() != 0, "x": float(b.get_16()),
				"y": float(b.get_16()), "prog": b.get_u8() / 255.0, "for": b.get_u8()})
		for i in b.get_u8():
			cats.append({"owner": b.get_u8(), "target": b.get_u8(), "x": float(b.get_16()), "y": float(b.get_16())})
		rain = {"owner": b.get_u8(), "left": b.get_u8() / 4.0}
		if b.get_available_bytes() > 0:      # p4.11 the ghosts
			for i in b.get_u8():
				ghosts.append({"seat": b.get_u8(), "x": float(b.get_16()), "y": float(b.get_16()), "flags": b.get_u8()})
		if b.get_available_bytes() > 0 and b.get_u8() == 1:   # p4.12 the black cat
			s["pet"] = {"x": float(b.get_16()), "y": float(b.get_16()), "dir": b.get_8(), "gone": b.get_u8()}
		if b.get_available_bytes() > 0:                        # a bat swarm
			var ph := b.get_u8()
			if ph != 255:
				s["bats"] = {"phase": ph, "x": float(b.get_16()), "y": float(b.get_16()), "dir": b.get_8()}
		if b.get_available_bytes() > 0 and b.get_u8() == 1:   # THE BOILER ROOM's state
			s["hazards"] = BoilerScript.read(b)
	s["powers"] = powers
	s["ghosts"] = ghosts
	s["orbs"] = orbs
	s["cats"] = cats
	s["rain"] = rain

# The draw delay follows the snapshot gaps of the last 5 s: their 99th
# percentile plus half a tick, from 3 to 8 ticks, moving 2 ticks a second at most
# so the others never jump.
func _update_delay(t: float) -> void:
	var dt := clampf((t - last_poll_ms) / 1000.0, 0.0, 0.1) if last_poll_ms > 0.0 else 0.0
	last_poll_ms = t
	if t >= next_delay_ms and gap_hist.size() >= 30:
		next_delay_ms = t + 1000.0
		var g := gap_hist.duplicate()
		g.sort()
		delay_goal = clampf(g[int(g.size() * 0.99)] / (1000.0 / 60.0) + 0.5, DELAY_TICKS, DELAY_MAX)
	delay_ticks = move_toward(delay_ticks, delay_goal, dt * 2.0)

func render_tick() -> float:
	return now_ms() / 1000.0 * 60.0 + tick_offset - delay_ticks

# The newest snapshot (empty before the first).
func newest() -> Dictionary:
	return snaps[snaps.size() - 1] if snaps.size() > 0 else {}

# The events due at render tick rt. P2: with own_id (you are predicted), your own
# fighter's events come at once, not at rt, and the kinds the prediction already
# showed (`predicted`, client/predict.gd PREDICTED) are dropped; a stomp's jump
# (E_JUMP with b = 1) is the server's and comes. The arrows' own events (a stick,
# a tink) come at once too: the arrows are drawn in the present (client/present.gd).
func take_events(rt: float, own_id: int = -1, predicted: Array = []) -> Array:
	var out: Array = []
	if own_id < 0:
		while events.size() > 0 and events[0][0] <= rt + 2.0:
			out.append(events.pop_front()[1])
		return out
	var keep: Array = []
	for item in events:
		var e: Array = item[1]
		if e[3] == own_id and FIGHTER_EVENTS.has(e[0]):
			if not predicted.has(e[0]) or (e[0] == P.E_JUMP and e[4] == 1):
				out.append(e)
		elif item[0] <= rt + 2.0 or ARROW_EVENTS.has(e[0]):
			out.append(e)
		else:
			keep.append(item)
	events = keep
	return out

static func _wlerp(a: float, b: float, t: float, size: float) -> float:
	var d := b - a
	if d > size * 0.5:
		d -= size
	elif d < -size * 0.5:
		d += size
	return fposmod(a + d * t, size)

# The world at render tick rt: {fighters: [..], arrows: {id: ..}, zones: [..],
# walls: each purple wall's width in px, walls_deadly}.
# Fighters are matched by seat between the two snapshots. own_id >= 0: that
# fighter comes from the newest snapshot instead (your own, with less lag).
# own (P2): your predicted fighter (client/predict.gd fighter_dict) in its place.
func sample(rt: float, own_id: int = -1, own: Dictionary = {}) -> Dictionary:
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
		if not own.is_empty() and fb["id"] == own["id"]:
			fighters.append(own)
			continue
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
				"y": _wlerp(aa["y"], ab["y"], t, H), "ang": ab["ang"], "big": ab.get("big", false)}
		else:
			arrows[id] = ab
	# p4.9: the ghost cats glide between the two snapshots (by their order: they only go, never come mid-list)
	var cats: Array = []
	var ca: Array = a.get("cats", [])
	for i in b.get("cats", []).size():
		var cb: Dictionary = b["cats"][i]
		if i < ca.size() and int(ca[i]["owner"]) == int(cb["owner"]):
			var c := cb.duplicate()
			c["x"] = _wlerp(ca[i]["x"], cb["x"], t, W)
			c["y"] = _wlerp(ca[i]["y"], cb["y"], t, H)
			cats.append(c)
		else:
			cats.append(cb)
	# p4.11: the ghosts glide too (matched by seat)
	var ghosts: Array = []
	var ga := {}
	for g in a.get("ghosts", []):
		ga[int(g["seat"])] = g
	for g in b.get("ghosts", []):
		var gd: Dictionary = g.duplicate()
		var g0: Dictionary = ga.get(int(g["seat"]), {})
		if not g0.is_empty() and absf(g0["x"] - g["x"]) < 300.0 and absf(g0["y"] - g["y"]) < 300.0:
			gd["x"] = _wlerp(g0["x"], g["x"], t, W)
			gd["y"] = _wlerp(g0["y"], g["y"], t, H)
		ghosts.append(gd)
	return {"fighters": fighters, "arrows": arrows, "zones": b["zones"], "arena": b.get("arena", 0),
		"walls": lerpf(a.get("walls", 0.0), b.get("walls", 0.0), t), "walls_deadly": b.get("walls_deadly", false),
		"powers": b.get("powers", {}), "orbs": b.get("orbs", []), "cats": cats, "rain": b.get("rain", {}), "ghosts": ghosts,
		"hazards": b.get("hazards", {}), "pet": _glide(a.get("pet", {}), b.get("pet", {}), t), "bats": _glide(a.get("bats", {}), b.get("bats", {}), t)}

# p4.12: the black cat or a bat swarm between two snapshots (by x; a jump stays a jump).
func _glide(da: Dictionary, db: Dictionary, t: float) -> Dictionary:
	if db.is_empty() or da.is_empty() or absf(da["x"] - db["x"]) > 300.0:
		return db
	var d := db.duplicate()
	d["x"] = lerpf(da["x"], db["x"], t)
	return d

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

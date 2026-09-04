# ==============================================================================
# WELCOME TO GLOBAL.GD! (The Networking Script)
# ==============================================================================
# This script is an "Autoload". That means it stays awake in the background
# forever while the game runs. 
# Its main job is sending invisible text messages (called JSON) over the 
# internet so that phones and PCs can talk to each other in real-time!
# ==============================================================================

extends Node

var is_mobile: bool = false
# Single source of truth for the game version. bump_build.sh rewrites this line,
# mirrors it into serve_game.py, and names the exported .pck after it
# (index_v0.0.1.pck) so browsers cannot serve a stale cached build.
const GAME_VERSION: String = "v0.0.19"
var version_canvas: CanvasLayer
var version_label: Label
var is_spectator: bool = true

# --- NET STATS (Phase 0 instrumentation) --------------------------------------
# Counts WebSocket payload bytes and packets in both directions, prints a
# summary line every NET_STATS_INTERVAL seconds and emits net_stats_updated so a
# HUD label can show it later. Payload only: WebSocket frame headers (2-6 bytes
# per packet) and TCP/TLS overhead are not included.
signal net_stats_updated(stats: Dictionary)
var net_stats_enabled: bool = true
const NET_STATS_INTERVAL: float = 5.0
var _ns_bytes_in: int = 0
var _ns_bytes_out: int = 0
var _ns_pkts_in: int = 0
var _ns_pkts_out: int = 0
var _ns_types_in: Dictionary = {}    # type -> [packets, bytes] for the current interval
var _ns_types_out: Dictionary = {}
var _ns_total_in: int = 0            # bytes since connect
var _ns_total_out: int = 0
var _ns_connected_at: int = 0        # msec tick
var _ns_last_rtt_ms: int = -1        # from the last pong (server echoes our ping timestamp)

# --- HEADLESS TEST HOOKS (non-web builds only) --------------------------------
# godot --headless --path . -- --autojoin [--name=X] [--class=N] [--server=ws://host:port] [--no-netstats] [--no-net]
#                                [--ai=<persona>] [--ai-seed=N] [--ai-difficulty=0..1] [--latency-ms=N] [--jitter-ms=N]
# --autojoin makes this instance join the lobby and lock in with no UI, so a
# headless Godot process can act as a real client for bandwidth measurements.
# --no-net skips connecting entirely (used by tools/check_scripts.gd).
# --ai attaches scripts/bot_brain.gd to the local fighter (arena.gd does it at
# spawn); the brain plays through the same input actions a human presses.
# --latency-ms delays every outgoing packet (bots on the server machine would
# otherwise see 0 ms; the harness fault knobs only cover the protocol bots).
var _autojoin: bool = false
var _autojoin_name: String = "Headless"
var _autojoin_class: int = 0
var _autojoin_class_given: bool = false
var _server_override: String = ""
var _no_net: bool = false
const BotBrainScript = preload("res://scripts/bot_brain.gd")
var ai_persona: String = ""          # "" = no brain; see bot_brain.gd PERSONAS
var ai_seed: int = 0                 # 0 = random
var ai_difficulty: float = 0.7       # 0 = slow and sloppy, 1 = sharp
var send_latency_ms: int = 0         # artificial delay on every outgoing packet
var send_jitter_ms: int = 0          # +/- random variation on that delay (order-preserving)
var _last_send_timer: SceneTreeTimer = null   # the previous delayed packet's timer: later packets never overtake it

# --- PUPPET JITTER TELEMETRY (Phase 3b) ---------------------------------------
# Every remote fighter reports, per physics frame, how much its rendered speed
# changed since the previous frame (px/s), whether it snapped (a jump over
# PUPPET_SNAP_PX in one frame) and whether it is starved of samples. Aggregated
# into the NetStats line so a fleet run with --latency-ms / --jitter-ms gives
# the interpolation a number instead of an impression.
const PUPPET_SNAP_PX := 80.0         # a teleport: more than this in one frame without crossing a seam
const PUPPET_STALL_SEC := 0.15       # no sample for 3 ticks while the sender was moving
# Snapshot interpolation (Phase 3b): puppets render this many ticks behind the
# newest sample so there is always a later sample to interpolate toward.
const RENDER_DELAY_TICKS := 2.0
const SNAP_RING := 16
const EXTRAP_MAX_TICKS := 4.0        # past the newest sample: follow the last velocity this long, then freeze
const TELEPORT_PX := 80.0            # a single-tick displacement beyond this renders as a step, not a glide
var _pj_deltas: PackedFloat32Array = PackedFloat32Array()   # |speed change| per frame, this interval
var _pj_snaps: int = 0
var _pj_wraps: int = 0
var _pj_stall_frames: int = 0
var _pj_extrap_frames: int = 0       # frames rendered past the newest sample (extrapolated or frozen)
var _pj_dips: int = 0                 # frames a puppet was drawn below its own floor sample
var _pj_frames: int = 0
var _pj_puppets: Dictionary = {}     # player_id -> true, seen this interval

# dipped = this frame the puppet was drawn below its newest "feet on the ground"
# sample, so it looked like it sank into the floor (v0.0.17 hotfix check).
func puppet_sample(p_id: int, speed_delta: float, snapped: bool, stalled: bool, wrapped: bool = false, extrapolated: bool = false, dipped: bool = false) -> void:
	if not net_stats_enabled:
		return
	_pj_puppets[p_id] = true
	_pj_frames += 1
	if extrapolated:
		_pj_extrap_frames += 1
	if wrapped:
		_pj_wraps += 1        # a seam crossing: expected, not jitter
	elif snapped:
		_pj_snaps += 1
	else:
		_pj_deltas.append(speed_delta)
	if stalled:
		_pj_stall_frames += 1
	if dipped:
		_pj_dips += 1

func _pj_summary() -> Dictionary:
	var out := {"puppets": _pj_puppets.size(), "frames": _pj_frames, "mean": 0.0, "p95": 0.0,
		"snaps": _pj_snaps, "wraps": _pj_wraps, "stall_pct": 0.0, "extrap_pct": 0.0, "dips": _pj_dips}
	if _pj_deltas.size() > 0:
		var sum := 0.0
		for d in _pj_deltas:
			sum += d
		out["mean"] = sum / _pj_deltas.size()
		var sorted := _pj_deltas.duplicate()
		sorted.sort()
		out["p95"] = sorted[mini(int(floor(sorted.size() * 0.95)), sorted.size() - 1)]
	if _pj_frames > 0:
		out["stall_pct"] = 100.0 * _pj_stall_frames / _pj_frames
		out["extrap_pct"] = 100.0 * _pj_extrap_frames / _pj_frames
	return out

func _pj_reset() -> void:
	_pj_deltas = PackedFloat32Array()
	_pj_snaps = 0
	_pj_wraps = 0
	_pj_stall_frames = 0
	_pj_extrap_frames = 0
	_pj_dips = 0
	_pj_frames = 0
	_pj_puppets.clear()

# --- BINARY MOVEMENT PACKETS (Phase 2) ----------------------------------------
# Movement is the only high-rate traffic, so it travels as a 9-byte binary frame
# instead of ~190 bytes of JSON. Layout (little-endian):
#   [0] type  (1 = sync_pos, 2 = spawn_projectile)
#   [1] sender slot (0 from the client; the server stamps the real slot)
#   sync_pos (11 B):   [2..3] tick u16  [4..5] x*10 s16  [6..7] y*10 s16  [8..9] aim angle 0.1 deg u16  [10] flags
#                      flags bits: 1 facing, 2 dash, 4 shield, 8 bear, 16 egg, 32 feet on the ground
#   spawn_projectile:  [2] weapon id    [3..4] x*10 s16  [5..6] y*10 s16  [7..8] dir angle 0.1 deg u16
# The tick is the sender's 20 Hz slot clock (wraps at 65536): it advances every
# 50 ms whether or not the slot is sent (idle suppression), so a receiver can
# order packets, place each sample in time and read a gap as "nothing changed".
# Everything else (lobby, deaths, rounds) stays JSON: rare, and readable in the logs.
# serve_game.py (BIN_TYPES) and tools/chaos_bots.py mirror this layout.
const BIN_SYNC_POS := 1
const BIN_SPAWN_PROJECTILE := 2
const BIN_SYNC_SIZE := 11
const BIN_PROJECTILE_SIZE := 9
const NET_TICK_HZ := 20.0            # movement samples per second (was 30)
const NET_TICK_INTERVAL := 1.0 / NET_TICK_HZ
const NET_IDLE_RESEND := 0.5         # an unchanged state is still repeated this often (keepalive for late joiners)
const BIN_WEAPONS: PackedStringArray = ["arrow", "firebolt", "kunai", "thorn"]
const FLAG_FACING := 1
const FLAG_DASH := 2
const FLAG_SHIELD := 4
const FLAG_BEAR := 8
const FLAG_EGG := 16
const FLAG_FLOOR := 32            # feet on the ground (v0.0.17: stops a landed puppet from sinking)

# Timers that replaced per-frame checks in _process (Phase 1).
var _ping_timer: Timer          # 1 Hz keepalive while connected
var _reconnect_timer: Timer     # one-shot 2 s, armed only from the CLOSED branch

## Global Game Manager & WebSocket Network Engine
## Central singleton for 4-Player Battle Royale, state sync, and class definitions.

signal net_connected(player_id)
signal net_player_joined(player_id, active_players)
signal net_player_left(player_id, active_players)
signal net_opponent_locked_in(player_id, class_type)
signal net_player_state_received(player_id, data)
signal net_projectile_spawned(data)
signal net_return_to_lobby
signal net_player_died(killer_id, victim_id, stock)
signal net_round_end(winner_id, scores, round_num, match_over)
signal net_new_round(round_num)
signal net_version_error(server_version)

enum ClassType {
	RANGER,
	KNIGHT,
	MAGE,
	ROGUE,
	DRUID
}

const CLASS_INFO = {
	ClassType.RANGER: {
		"name": "Ranger",
		"title": "Master Archer",
		"icon": "🏹",
		"icon_tex": "res://assets/icons/ranger.jpg",
		"primary_icon": "res://assets/icons/skill_ranger_1.jpg",
		"special_icon": "res://assets/icons/skill_ranger_2.jpg",
		"color": Color(0.2, 0.75, 0.35),
		"desc": "Precision multi-directional arrows, projectile catching, and recoil backflip shot."
	},
	ClassType.KNIGHT: {
		"name": "Knight",
		"title": "Iron Juggernaut",
		"icon": "⚔️",
		"icon_tex": "res://assets/icons/knight.jpg",
		"primary_icon": "res://assets/icons/skill_knight_1.jpg",
		"special_icon": "res://assets/icons/skill_knight_2.jpg",
		"color": Color(0.25, 0.55, 0.95),
		"desc": "Broadsword slash deflects projectiles, shield guard parries arrows and spells."
	},
	ClassType.MAGE: {
		"name": "Mage",
		"title": "Pyromancer",
		"icon": "🔮",
		"icon_tex": "res://assets/icons/pyro.jpg",
		"primary_icon": "res://assets/icons/skill_pyro_1.jpg",
		"special_icon": "res://assets/icons/skill_pyro_2.jpg",
		"color": Color(0.95, 0.55, 0.15),
		"desc": "Explosive firebolts that regenerate over time, and instantaneous void blink teleport."
	},
	ClassType.ROGUE: {
		"name": "Rogue",
		"title": "Shadow Assassin",
		"icon": "🗡️",
		"icon_tex": "res://assets/icons/rogue.jpg",
		"primary_icon": "res://assets/icons/skill_rogue_1.jpg",
		"special_icon": "res://assets/icons/skill_rogue_2.jpg",
		"color": Color(0.75, 0.3, 0.95),
		"desc": "Rapid throwing kunais, shadow dash ambushes through enemies."
	},
	ClassType.DRUID: {
		"name": "Druid",
		"title": "Shape Shifter",
		"icon": "🐻",
		"icon_tex": "res://assets/icons/druid.jpg",
		"primary_icon": "res://assets/icons/skill_druid_1.jpg",
		"special_icon": "res://assets/icons/skill_druid_2.jpg",
		"color": Color(0.6, 0.4, 0.1),
		"desc": "Throws thorns. Bear Form. Dash turns into a Storm Crow. Shield is Phoenix Egg."
	}
}

var player_configs = {
	1: {"class": ClassType.RANGER, "active": true},
	2: {"class": ClassType.KNIGHT, "active": true},
	3: {"class": ClassType.MAGE, "active": true},
	4: {"class": ClassType.ROGUE, "active": true}
}

var player_scores = {
	1: 0,
	2: 0,
	3: 0,
	4: 0
}

var max_stocks: int = 3
var match_score_limit: int = 5

# --- REAL-TIME WEBSOCKET RELAY ---
var ws: WebSocketPeer = WebSocketPeer.new()
var ws_connected: bool = false    # was `is_connected`, which shadowed Object.is_connected()
var is_connecting: bool = false   # guard: never open two sockets at once
var my_player_id: int = 0
var server_url: String = ""
var active_players: Array[int] = []    # every occupied slot (server's live roster)
var playing_players: Array[int] = []   # slots fighting in the CURRENT match; late joiners wait
var locked_opponents: Dictionary = {}
var player_names: Dictionary = {}
var my_player_name: String = ""
var current_round: int = 1
var arena_flips: int = 0               # platform half-turns this match (server counts activate_powerup)
var server_stocks: Dictionary = {1: 3, 2: 3, 3: 3, 4: 3}   # authoritative stocks (snapshots, player_died, new_round)
var rejoined_mid_match: bool = false   # assign_id said we resumed our own seat in a running match
var last_match_state: String = "LOBBY"

# --- SESSION IDENTITY / REJOIN (playtest fixes, v0.0.6) ------------------------
# A random token identifies this browser across reloads and reconnects. The
# server only honours a saved slot number together with the token that held it,
# so a fresh lobby fills 1 -> 2 -> 3 -> 4 and a page reload gets its seat back.
var client_token: String = ""
var _had_slot: int = 0            # slot held when the socket dropped (this page session)
var _rejoin_pending: bool = false # request_join sent automatically after a reconnect
const REJOIN_WINDOW_S: int = 120  # a saved slot younger than this is rejoined automatically

signal net_names_updated()
signal net_spawn_powerup(x, y)
signal net_activate_powerup(powerup_id)
signal net_force_start()

func _ready():

	is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	if OS.has_feature("web"):
		var ua = JavaScriptBridge.eval("/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);", true)
		if ua:
			is_mobile = true

	if not OS.has_feature("web"):
		_parse_test_args()
	client_token = _load_or_create_token()

	if net_stats_enabled:
		var stats_timer := Timer.new()
		stats_timer.name = "NetStatsTimer"
		stats_timer.wait_time = NET_STATS_INTERVAL
		stats_timer.autostart = true
		stats_timer.timeout.connect(_report_net_stats)
		add_child(stats_timer)

	_ping_timer = Timer.new()
	_ping_timer.name = "PingTimer"
	_ping_timer.wait_time = 1.0
	_ping_timer.autostart = false
	_ping_timer.timeout.connect(_send_ping)
	add_child(_ping_timer)

	_reconnect_timer = Timer.new()
	_reconnect_timer.name = "ReconnectTimer"
	_reconnect_timer.wait_time = 2.0
	_reconnect_timer.one_shot = true
	_reconnect_timer.autostart = false
	_reconnect_timer.timeout.connect(_determine_url_and_connect)
	add_child(_reconnect_timer)

	if _no_net:
		print("🔌 [Global] --no-net: skipping server connection")
		return
	_determine_url_and_connect()

func _determine_url_and_connect():
	if is_connecting or ws_connected:
		return
	is_connecting = true
	
	var host = "127.0.0.1"
	var is_ssl = false
	if OS.has_feature("web"):
		var js_host = str(JavaScriptBridge.eval("window.location.hostname", true))
		if js_host == "nemr118.github.io":
			server_url = "wss://towerbrawl-server.loca.lt"
		elif js_host and js_host != "":
			var host_str = js_host
			var js_port = JavaScriptBridge.eval("window.location.port", true)
			var port_str = ""
			if js_port and str(js_port) != "":
				port_str = ":" + str(js_port)
			var js_proto = JavaScriptBridge.eval("window.location.protocol", true)
			if str(js_proto) == "https:":
				server_url = "wss://" + host_str + port_str
			else:
				server_url = "ws://" + host_str + port_str
		else:
			server_url = "wss://towerbrawl-server.loca.lt"
	else:
		server_url = _server_override if _server_override != "" else "ws://127.0.0.1:8000"

	print("🔌 [Global] Connecting to: ", server_url)
	ws = WebSocketPeer.new()   # fresh socket, never reuse a closed one
	var err = ws.connect_to_url(server_url)
	if err != OK:
		print("⚠️ [Global] WebSocket connect error: ", err)
		is_connecting = false

func _save_player_id():
	# Persist our slot number so we can reclaim it after a page reload / reconnect
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){ try { localStorage.setItem('towerbrawl_pid', '" + str(my_player_id) + "'); } catch(e) {} })()", true)
	else:
		var f = FileAccess.open("user://towerbrawl_pid.sav", FileAccess.WRITE)
		if f:
			f.store_string(str(my_player_id))
			f.close()

func _load_saved_player_id() -> int:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("(function(){ try { return localStorage.getItem('towerbrawl_pid'); } catch(e) { return null; } })()", true)
		if val != null and str(val) != "null" and str(val) != "":
			return int(str(val))
	else:
		if FileAccess.file_exists("user://towerbrawl_pid.sav"):
			var f = FileAccess.open("user://towerbrawl_pid.sav", FileAccess.READ)
			if f:
				var val = f.get_as_text()
				f.close()
				if val != "":
					return int(val)
	return 0  # 0 = no saved ID

func _process(_delta):
	if _no_net:
		return
	# WebSocketPeer has no signals: poll() is what drives the socket, so this is
	# the one per-frame call that has to stay. Everything else is timer-driven.
	ws.poll()
	var state = ws.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not ws_connected:
			ws_connected = true
			is_connecting = false
			_ns_connected_at = Time.get_ticks_msec()
			_ping_timer.start()
			print("✅ [Global] Connected!")
			# Handshake done. Server will send spectator_state.

		while ws.get_available_packet_count() > 0:
			var pkt = ws.get_packet()
			_ns_pkts_in += 1
			_ns_bytes_in += pkt.size()
			_ns_total_in += pkt.size()
			if ws.was_string_packet():
				_handle_net_packet(pkt.get_string_from_utf8(), pkt.size())
			else:
				_handle_net_binary(pkt)

	elif state == WebSocketPeer.STATE_CLOSED:
		# Reconnect is scheduled ONCE from this branch on a one-shot timer. The old
		# code awaited inside _process (re-entered every frame while suspended) and
		# then called the connect routine unconditionally at the end of every frame.
		if ws_connected or is_connecting:
			ws_connected = false
			is_connecting = false
			_ping_timer.stop()
			if my_player_id > 0:
				_had_slot = my_player_id
			my_player_id = 0
			is_spectator = true
			print("❌ [Global] Disconnected. Reconnecting in 2s...")
			_reconnect_timer.start()
		elif _reconnect_timer.is_stopped():
			_reconnect_timer.start()

func _send_ping() -> void:
	# 1 Hz by construction. The old frame counter (% 60) gave 2.4 Hz on a 144 Hz
	# display and 0.5 Hz on a phone running at 30 fps.
	send_net_data({"type": "ping", "t": Time.get_ticks_msec()})

func send_net_data(dict: Dictionary):
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		dict["sender"] = my_player_id
		var json_str = JSON.stringify(dict)
		var delay := _send_delay_sec()
		if delay > 0.0:
			_delayed(delay).timeout.connect(_send_text_now.bind(json_str, str(dict.get("type", "?"))))
		else:
			_send_text_now(json_str, str(dict.get("type", "?")))

# Artificial latency (+/- jitter) for the headless test client. A packet's delay
# is never shorter than what is left on the previous packet's timer, so jitter
# delays but never reorders (TCP could not reorder either). Same model as the
# harness bots. The floor is taken from the timer itself, not the wall clock:
# SceneTree timers count down by frame delta, and a wall-clock due time could
# cross a timer by one frame (seen as oracle.movement-out-of-order in v0.0.14).
func _send_delay_sec() -> float:
	if send_latency_ms <= 0 and send_jitter_ms <= 0:
		return 0.0
	var delay := (send_latency_ms + randf_range(-send_jitter_ms, send_jitter_ms)) / 1000.0
	if _last_send_timer != null and _last_send_timer.time_left > 0.0:
		delay = maxf(delay, _last_send_timer.time_left)
	return maxf(delay, 0.0)

func _delayed(delay: float) -> SceneTreeTimer:
	_last_send_timer = get_tree().create_timer(delay)
	return _last_send_timer

func _send_text_now(json_str: String, type: String) -> void:
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	ws.send_text(json_str)
	if net_stats_enabled:
		var n := json_str.to_utf8_buffer().size()
		_ns_pkts_out += 1
		_ns_bytes_out += n
		_ns_total_out += n
		_ns_count(_ns_types_out, type, n)

func send_net_binary(buf: PackedByteArray) -> void:
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var delay := _send_delay_sec()
		if delay > 0.0:
			_delayed(delay).timeout.connect(_send_binary_now.bind(buf))
		else:
			_send_binary_now(buf)

func _send_binary_now(buf: PackedByteArray) -> void:
	if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	ws.send(buf, WebSocketPeer.WRITE_MODE_BINARY)
	if net_stats_enabled:
		_ns_pkts_out += 1
		_ns_bytes_out += buf.size()
		_ns_total_out += buf.size()
		_ns_count(_ns_types_out, _bin_type_name(buf), buf.size())

func _bin_type_name(buf: PackedByteArray) -> String:
	if buf.size() < 1:
		return "<bad-binary>"
	match buf.decode_u8(0):
		BIN_SYNC_POS: return "sync_pos"
		BIN_SPAWN_PROJECTILE: return "spawn_projectile"
		_: return "<bad-binary>"

func _dir_to_u16(v: Vector2) -> int:
	return int(round(fposmod(rad_to_deg(v.angle()), 360.0) * 10.0)) % 3600

func _u16_to_dir(a: int) -> Vector2:
	return Vector2.from_angle(deg_to_rad(a / 10.0))

func _q10(v: float) -> int:
	return clampi(roundi(v * 10.0), -32768, 32767)

func encode_sync_pos(tick: int, pos: Vector2, aim: Vector2, facing: bool, dash: bool, shield: bool, bear: bool, egg: bool, on_floor: bool = false) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(BIN_SYNC_SIZE)
	b.encode_u8(0, BIN_SYNC_POS)
	b.encode_u8(1, 0)
	b.encode_u16(2, tick & 0xFFFF)
	b.encode_s16(4, _q10(pos.x))
	b.encode_s16(6, _q10(pos.y))
	b.encode_u16(8, _dir_to_u16(aim))
	var flags := 0
	if facing: flags |= FLAG_FACING
	if dash: flags |= FLAG_DASH
	if shield: flags |= FLAG_SHIELD
	if bear: flags |= FLAG_BEAR
	if egg: flags |= FLAG_EGG
	if on_floor: flags |= FLAG_FLOOR
	b.encode_u8(10, flags)
	return b

func encode_projectile(weapon: String, pos: Vector2, dir: Vector2) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(BIN_PROJECTILE_SIZE)
	b.encode_u8(0, BIN_SPAWN_PROJECTILE)
	b.encode_u8(1, 0)
	b.encode_u8(2, maxi(BIN_WEAPONS.find(weapon), 0))
	b.encode_s16(3, _q10(pos.x))
	b.encode_s16(5, _q10(pos.y))
	b.encode_u16(7, _dir_to_u16(dir))
	return b

func _handle_net_binary(pkt: PackedByteArray) -> void:
	if pkt.size() < 2:
		if net_stats_enabled:
			_ns_count(_ns_types_in, "<bad-binary>", pkt.size())
		return
	var ptype := pkt.decode_u8(0)
	var sender := pkt.decode_u8(1)
	if ptype == BIN_SYNC_POS and pkt.size() == BIN_SYNC_SIZE:
		if net_stats_enabled:
			_ns_count(_ns_types_in, "sync_pos", pkt.size())
		if sender == my_player_id:
			return
		var flags := pkt.decode_u8(10)
		var aim := _u16_to_dir(pkt.decode_u16(8))
		emit_signal("net_player_state_received", sender, {
			"sender": sender,
			"tick": pkt.decode_u16(2),
			"x": pkt.decode_s16(4) / 10.0,
			"y": pkt.decode_s16(6) / 10.0,
			"aim_x": aim.x,
			"aim_y": aim.y,
			"facing": (flags & FLAG_FACING) != 0,
			"dash": (flags & FLAG_DASH) != 0,
			"shield": (flags & FLAG_SHIELD) != 0,
			"bear": (flags & FLAG_BEAR) != 0,
			"egg": (flags & FLAG_EGG) != 0,
			"floor": (flags & FLAG_FLOOR) != 0,
		})
	elif ptype == BIN_SPAWN_PROJECTILE and pkt.size() == BIN_PROJECTILE_SIZE:
		if net_stats_enabled:
			_ns_count(_ns_types_in, "spawn_projectile", pkt.size())
		if sender == my_player_id:
			return
		var wid := pkt.decode_u8(2)
		var dir := _u16_to_dir(pkt.decode_u16(7))
		emit_signal("net_projectile_spawned", {
			"sender": sender,
			"weapon": BIN_WEAPONS[wid] if wid < BIN_WEAPONS.size() else "arrow",
			"pos_x": pkt.decode_s16(3) / 10.0,
			"pos_y": pkt.decode_s16(5) / 10.0,
			"dir_x": dir.x,
			"dir_y": dir.y,
		})
	elif net_stats_enabled:
		_ns_count(_ns_types_in, "<bad-binary>", pkt.size())

func _handle_net_packet(msg_str: String, byte_size: int = 0):
	var data = JSON.parse_string(msg_str)
	if not data or typeof(data) != TYPE_DICTIONARY:
		if net_stats_enabled:
			_ns_count(_ns_types_in, "<bad-json>", byte_size)
		return

	var type = data.get("type", "")
	if net_stats_enabled:
		_ns_count(_ns_types_in, str(type), byte_size)

	if type == "pong":
		var t0 = data.get("t", null)
		if t0 != null:
			_ns_last_rtt_ms = Time.get_ticks_msec() - int(t0)

	if type == "version_error":
		# Server refused our request_join: this build is older/newer than the server.
		# Almost always the browser served a cached .pck (see CLAUDE.md rule 2).
		print("⛔ [Global] VERSION MISMATCH: this build is ", GAME_VERSION,
			" but the server expects ", data.get("server_version", "?"),
			". Reload the versioned URL from bump_build.sh.")
		emit_signal("net_version_error", str(data.get("server_version", "?")))

	if type == "spectator_state" and my_player_id == 0:
		if _autojoin:
			print("🤖 [Global] --autojoin: requesting slot")
			_rejoin_pending = true
			request_join(0)
		elif _should_auto_rejoin():
			var slot := _had_slot if _had_slot > 0 else _load_saved_player_id()
			print("🔁 [Global] Reconnected: asking for our seat P", slot, " back")
			_rejoin_pending = true
			request_join(slot)
	if type in ["version_error", "server_full"] and _rejoin_pending:
		_rejoin_pending = false
		_ensure_scene_for_state(last_match_state)

	if type == "spawn_powerup":
		emit_signal("net_spawn_powerup", data.get("x", 0.0), data.get("y", 0.0))
	elif type == "activate_powerup":
		emit_signal("net_activate_powerup", data.get("powerup_id", 0))
	if type == "force_start":
		emit_signal("net_force_start")
	
	if type == "scene_transition":
		# Everyone occupying a slot at this moment is in the match (mirrors _setup_match on the server).
		playing_players = active_players.duplicate()
		for k in server_stocks:
			server_stocks[k] = max_stocks
		get_tree().change_scene_to_file("res://scenes/arena.tscn")
	if type == "spectator_state":
		is_spectator = true
		
	if type in ["assign_id", "player_joined", "player_left", "name_update", "spectator_state"]:
		if data.has("active_players"):
			active_players.clear()
			var a_players = data.get("active_players", [])
			for x in a_players:
				active_players.append(int(x))
		if data.has("player_names"):
			player_names.clear()
			var p_names = data.get("player_names", {})
			for p_str in p_names:
				player_names[int(p_str)] = str(p_names[p_str])
		if data.has("playing_players"):
			playing_players.clear()
			for x in data.get("playing_players", []):
				playing_players.append(int(x))
		if data.has("locked_players"):
			# Classes of everyone already locked in, so a client that goes straight
			# to the arena (spectator or late joiner) draws the right champions.
			var locked_now = data.get("locked_players", {})
			for p_str in locked_now:
				var lp := int(p_str)
				var lc := int(locked_now[p_str])
				locked_opponents[lp] = lc
				if player_configs.has(lp):
					player_configs[lp]["class"] = lc
		if data.has("arena_flips"):
			arena_flips = int(data.get("arena_flips", 0))
		if data.has("stocks"):
			var st = data.get("stocks", {})
			for k in st:
				server_stocks[int(k)] = int(st[k])
		emit_signal("net_names_updated")

		if data.has("match_state"):
			last_match_state = str(data.get("match_state", "LOBBY"))
			# assign_id while PLAYING: (re)load the arena so our fighter spawns.
			# spectator_state: put us in the scene that matches the server, unless a
			# rejoin request is in flight (its assign_id decides the scene).
			if type == "assign_id" and last_match_state == "PLAYING":
				get_tree().change_scene_to_file("res://scenes/arena.tscn")
			elif not _rejoin_pending:
				_ensure_scene_for_state(last_match_state)
	if type == "assign_id":
		is_spectator = false
		_rejoin_pending = false
		_had_slot = 0
		my_player_id = int(data.get("id", 1))
		rejoined_mid_match = bool(data.get("rejoined", false))
		print("🎮 [Global] Assigned Player ID: ", my_player_id, " (rejoined)" if rejoined_mid_match else "")
		_save_player_id()   # persist so reconnects restore this slot
		_save_last_seen()
		if my_player_name != "":
			# The lobby confirms a saved name before JOIN is pressed; repeat it now
			# that we hold a slot so everyone else sees it too.
			send_net_data({"type": "set_name", "name": my_player_name})
		
		# Remap local gamepad inputs to accept any controller (device: -1)
		# This ensures phones with 1 connected controller (device 0) can play as P2, P3, or P4!
		var prefix = "p" + str(my_player_id) + "_"
		for action in InputMap.get_actions():
			if action.begins_with(prefix):
				var events = InputMap.action_get_events(action)
				InputMap.action_erase_events(action)
				for ev in events:
					if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
						ev.device = -1
					InputMap.action_add_event(action, ev)
		
		
		# Transfer PC Keyboard and Mouse binds to our assigned slot if we aren't P1
		if my_player_id >= 2:   # id 0 = still a spectator: no p0_* actions exist
			var prefix1 = "p1_"
			for action_suffix in ["left", "right", "up", "down", "jump", "dash", "attack", "special"]:
				var events1 = InputMap.action_get_events(prefix1 + action_suffix)
				var my_action = "p" + str(my_player_id) + "_" + action_suffix
				for ev in events1:
					if ev is InputEventKey or ev is InputEventMouseButton:
						InputMap.action_add_event(my_action, ev)

		if is_mobile:
			strip_mouse_binds()

		active_players.clear()
		for x in data.get("active_players", [1]):
			active_players.append(int(x))
		if not active_players.has(my_player_id):
			active_players.append(my_player_id)
			
		emit_signal("net_connected", my_player_id)
		emit_signal("net_player_joined", my_player_id, active_players)
		
		var locked_map = data.get("locked_players", {})
		for p_str in locked_map:
			var p_id = int(p_str)
			var c_type = int(locked_map[p_str])
			locked_opponents[p_id] = c_type
			if p_id != my_player_id:
				emit_signal("net_opponent_locked_in", p_id, c_type)

		if _autojoin:
			print("🤖 [Global] --autojoin: P", my_player_id, " naming + locking in class ", _autojoin_class)
			_save_player_name(_autojoin_name)
			send_net_data({"type": "set_name", "name": _autojoin_name})
			player_configs[my_player_id]["class"] = _autojoin_class
			locked_opponents[my_player_id] = _autojoin_class
			send_net_data({"type": "lock_in", "class": _autojoin_class})

	elif type == "player_joined":
		var p_id = int(data.get("id", 1))
		
		# Transfer PC Keyboard and Mouse binds to our assigned slot if we aren't P1
		if my_player_id >= 2:   # id 0 = still a spectator: no p0_* actions exist
			var prefix1 = "p1_"
			for action_suffix in ["left", "right", "up", "down", "jump", "dash", "attack", "special"]:
				var events1 = InputMap.action_get_events(prefix1 + action_suffix)
				var my_action = "p" + str(my_player_id) + "_" + action_suffix
				for ev in events1:
					if ev is InputEventKey or ev is InputEventMouseButton:
						InputMap.action_add_event(my_action, ev)

		active_players.clear()
		for x in data.get("active_players", []):
			active_players.append(int(x))
		if not active_players.has(p_id):
			active_players.append(p_id)
		emit_signal("net_player_joined", p_id, active_players)
		
	elif type == "player_left":
		var p_id = int(data.get("id", 1))
		
		# Transfer PC Keyboard and Mouse binds to our assigned slot if we aren't P1
		if my_player_id >= 2:   # id 0 = still a spectator: no p0_* actions exist
			var prefix1 = "p1_"
			for action_suffix in ["left", "right", "up", "down", "jump", "dash", "attack", "special"]:
				var events1 = InputMap.action_get_events(prefix1 + action_suffix)
				var my_action = "p" + str(my_player_id) + "_" + action_suffix
				for ev in events1:
					if ev is InputEventKey or ev is InputEventMouseButton:
						InputMap.action_add_event(my_action, ev)

		active_players.clear()
		for x in data.get("active_players", []):
			active_players.append(int(x))
		playing_players.erase(p_id)
		if locked_opponents.has(p_id):
			locked_opponents.erase(p_id)
		emit_signal("net_player_left", p_id, active_players)
		
	elif type == "lock_in":
		var p_id = int(data.get("sender", 1))
		var c_type = int(data.get("class", 0))
		locked_opponents[p_id] = c_type
		if player_configs.has(p_id):
			player_configs[p_id]["class"] = c_type
		emit_signal("net_opponent_locked_in", p_id, c_type)
		
	elif type == "return_to_lobby":
		is_spectator = false
		locked_opponents.clear()
		playing_players.clear()
		arena_flips = 0
		last_match_state = "LOBBY"
		reset_scores()
		emit_signal("net_return_to_lobby")
		if _autojoin:
			_autojoin_relock()
		
	elif type == "player_died":
		var victim = int(data.get("victim", 0))
		var killer = int(data.get("killer", 0))
		var stock = int(data.get("stock", 0))
		server_stocks[victim] = stock
		emit_signal("net_player_died", killer, victim, stock)
		
	elif type == "round_end":
		var winner = int(data.get("winner", 1))
		var scores = data.get("scores", {})
		var r_num = int(data.get("round", 1))
		var match_over = bool(data.get("match_over", false))
		emit_signal("net_round_end", winner, scores, r_num, match_over)
		
	elif type == "new_round":
		var r_num = int(data.get("round", 1))
		for k in server_stocks:
			server_stocks[k] = max_stocks
		emit_signal("net_new_round", r_num)


func is_host() -> bool:
	var lowest = 999
	for p_id in active_players:
		if p_id < lowest:
			lowest = p_id
	if active_players.size() == 0:
		return true
	return my_player_id == lowest

func _autojoin_relock() -> void:
	# v0.0.18. The story: a bot locked in only once, right when it got its seat.
	# After a match ended everyone went back to the lobby and the bot just sat
	# there, so the user had to restart the bots by hand. Now, a moment after
	# the lobby comes back, the bot says its name and locks in again.
	await get_tree().create_timer(1.5).timeout
	if my_player_id < 1 or last_match_state != "LOBBY":
		return
	print("🤖 [Global] --autojoin: P", my_player_id, " locking in again for the next match")
	send_net_data({"type": "set_name", "name": _autojoin_name})
	player_configs[my_player_id]["class"] = _autojoin_class
	locked_opponents[my_player_id] = _autojoin_class
	send_net_data({"type": "lock_in", "class": _autojoin_class})

func reset_scores():
	player_scores = {1: 0, 2: 0, 3: 0, 4: 0}

func _save_player_name(n: String):
	my_player_name = n
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){ try { localStorage.setItem('towerbrawl_name', '" + n.replace("'", "\'") + "'); } catch(e) {} })()", true)

func _load_saved_player_name() -> String:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("(function(){ try { return localStorage.getItem('towerbrawl_name'); } catch(e) { return null; } })()", true)
		if val != null and str(val) != "null" and str(val) != "":
			return str(val)
	return ""


# ==============================================================================
# NET STATS + HEADLESS TEST HOOKS
# ==============================================================================
func _parse_test_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--autojoin":
			_autojoin = true
		elif a.begins_with("--name="):
			_autojoin_name = a.substr(7)
		elif a.begins_with("--class="):
			_autojoin_class = clampi(int(a.substr(8)), 0, ClassType.size() - 1)
			_autojoin_class_given = true
		elif a.begins_with("--server="):
			_server_override = a.substr(9)
		elif a == "--no-netstats":
			net_stats_enabled = false
		elif a == "--no-net":
			_no_net = true
		elif a.begins_with("--ai="):
			ai_persona = a.substr(5).to_lower()
		elif a.begins_with("--ai-seed="):
			ai_seed = int(a.substr(10))
		elif a.begins_with("--ai-difficulty="):
			ai_difficulty = clampf(float(a.substr(16)), 0.0, 1.0)
		elif a.begins_with("--latency-ms="):
			send_latency_ms = maxi(int(a.substr(13)), 0)
		elif a.begins_with("--jitter-ms="):
			send_jitter_ms = maxi(int(a.substr(12)), 0)
	if ai_persona != "" and not ai_persona in BotBrainScript.PERSONAS:
		push_error("--ai=%s: unknown persona (one of %s)" % [ai_persona, ", ".join(BotBrainScript.PERSONAS)])
		ai_persona = ""
	if ai_persona != "" and not _autojoin_class_given:
		# A persona plays its natural class unless --class says otherwise
		# (wanderer: -1 = keep the default).
		var pref: int = BotBrainScript.DEFAULT_CLASS.get(ai_persona, -1)
		if pref >= 0:
			_autojoin_class = pref
	if send_latency_ms > 0 or send_jitter_ms > 0:
		print("⏱️ [Global] --latency-ms=", send_latency_ms, " --jitter-ms=", send_jitter_ms, ": every outgoing packet is delayed")

func _ns_count(table: Dictionary, type: String, bytes: int) -> void:
	if table.has(type):
		table[type][0] += 1
		table[type][1] += bytes
	else:
		table[type] = [1, bytes]

func _ns_format_types(table: Dictionary) -> String:
	var keys := table.keys()
	keys.sort_custom(func(a, b): return table[a][0] > table[b][0])
	var parts: PackedStringArray = []
	for k in keys:
		parts.append("%s=%d(%dB)" % [k, table[k][0], table[k][1]])
	return ", ".join(parts) if parts.size() > 0 else "-"

func _report_net_stats() -> void:
	if my_player_id > 0:
		_save_last_seen()
	if not ws_connected:
		return
	var secs := NET_STATS_INTERVAL
	var stats := {
		"interval": secs,
		"in_pps": _ns_pkts_in / secs,
		"in_bps": _ns_bytes_in / secs,
		"in_avg": float(_ns_bytes_in) / max(1, _ns_pkts_in),
		"out_pps": _ns_pkts_out / secs,
		"out_bps": _ns_bytes_out / secs,
		"out_avg": float(_ns_bytes_out) / max(1, _ns_pkts_out),
		"in_types": _ns_types_in.duplicate(true),
		"out_types": _ns_types_out.duplicate(true),
		"total_in": _ns_total_in,
		"total_out": _ns_total_out,
		"uptime": (Time.get_ticks_msec() - _ns_connected_at) / 1000.0,
		"rtt_ms": _ns_last_rtt_ms,
		"puppets": _pj_summary(),
	}
	var pj: Dictionary = stats["puppets"]
	print("📈 [NetStats %.0fs] P%d %s | IN %5.1f pkt/s %6.2f KB/s (avg %3.0f B) | OUT %5.1f pkt/s %6.2f KB/s (avg %3.0f B) | in: %s | out: %s | total in %.1f KB out %.1f KB over %.0fs | rtt %d ms | puppets=%d jitter=%.1f/%.1fpx/s snaps=%d wraps=%d stall=%.1f%% extrap=%.1f%% dips=%d pn=%d" % [
		secs, my_player_id, get_tree().current_scene.name if get_tree().current_scene else "?",
		stats["in_pps"], stats["in_bps"] / 1024.0, stats["in_avg"],
		stats["out_pps"], stats["out_bps"] / 1024.0, stats["out_avg"],
		_ns_format_types(_ns_types_in), _ns_format_types(_ns_types_out),
		_ns_total_in / 1024.0, _ns_total_out / 1024.0, stats["uptime"], _ns_last_rtt_ms,
		pj["puppets"], pj["mean"], pj["p95"], pj["snaps"], pj["wraps"], pj["stall_pct"], pj["extrap_pct"], pj["dips"], pj["frames"]])
	emit_signal("net_stats_updated", stats)
	_pj_reset()
	_ns_bytes_in = 0
	_ns_bytes_out = 0
	_ns_pkts_in = 0
	_ns_pkts_out = 0
	_ns_types_in.clear()
	_ns_types_out.clear()


# ==============================================================================
# SESSION IDENTITY, REJOIN, SCENE CORRECTION, INPUT SAFETY (v0.0.6)
# ==============================================================================
func request_join(reclaim_id: int) -> void:
	send_net_data({"type": "request_join", "reclaim_id": reclaim_id, "version": GAME_VERSION, "token": client_token})

func _should_auto_rejoin() -> bool:
	if _had_slot > 0:
		return true
	if _load_saved_player_id() <= 0:
		return false
	return int(Time.get_unix_time_from_system()) - _load_last_seen() < REJOIN_WINDOW_S

func _ensure_scene_for_state(state: String) -> void:
	# A client that reconnects after the match ended used to stay in the arena
	# forever (nothing ever moved it): match the scene to the server's state.
	var scene := get_tree().current_scene
	var path := scene.scene_file_path if scene != null else ""
	if state == "PLAYING" and path != "res://scenes/arena.tscn":
		get_tree().change_scene_to_file("res://scenes/arena.tscn")
	elif state == "LOBBY" and path == "res://scenes/arena.tscn":
		get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _storage_get(key: String) -> String:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("(function(){ try { return localStorage.getItem('" + key + "'); } catch(e) { return null; } })()", true)
		if val != null and str(val) != "null":
			return str(val)
		return ""
	var path := "user://" + key + ".sav"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var v := f.get_as_text()
			f.close()
			return v
	return ""

func _storage_set(key: String, value: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(function(){ try { localStorage.setItem('" + key + "', '" + value.replace("'", "") + "'); } catch(e) {} })()", true)
	else:
		var f := FileAccess.open("user://" + key + ".sav", FileAccess.WRITE)
		if f:
			f.store_string(value)
			f.close()

func _load_or_create_token() -> String:
	if _autojoin:
		# Headless test clients share one user:// directory; give each its own identity.
		return "headless-" + _autojoin_name
	var t := _storage_get("towerbrawl_token")
	if t == "":
		t = "%08x%08x" % [randi(), randi()]
		_storage_set("towerbrawl_token", t)
	return t

func _save_last_seen() -> void:
	_storage_set("towerbrawl_seen", str(int(Time.get_unix_time_from_system())))

func _load_last_seen() -> int:
	var v := _storage_get("towerbrawl_seen")
	return int(v) if v != "" else 0

func _notification(what: int) -> void:
	# A hidden or unfocused tab never receives the key-up for a key that was down
	# when focus left, so the fighter keeps running until focus returns. Release
	# every player action the moment focus is lost.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		for action in InputMap.get_actions():
			var a := str(action)
			if a.begins_with("p") and a.length() > 2 and a[1].is_valid_int():
				Input.action_release(action)

func strip_mouse_binds() -> void:
	# Godot emulates a mouse click from every touch, and the PC input map binds
	# mouse buttons to attack / special. On a touch device that made every tap on
	# the virtual joystick fire an arrow. Touch devices attack via the on-screen
	# buttons only.
	for action in InputMap.get_actions():
		var a := str(action)
		if not (a.begins_with("p") and a.length() > 2 and a[1].is_valid_int()):
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventMouseButton:
				InputMap.action_erase_event(action, ev)

# Combat state (ammo, form) is client-side; persist it so a page reload that
# rejoins the same fight (assign_id.rejoined) does not hand out a fresh quiver.
func save_combat_state(state: Dictionary) -> void:
	_storage_set("towerbrawl_combat", JSON.stringify(state))

func load_combat_state() -> Dictionary:
	var raw := _storage_get("towerbrawl_combat")
	if raw == "":
		return {}
	var parsed = JSON.parse_string(raw)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

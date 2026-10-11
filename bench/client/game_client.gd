# ==============================================================================
# The game's page (P1, the first playable). Joins server/game_server.gd, draws
# the match with the benchmark's look (client/world.gd, T2 unless look=), shows
# the lobby (client/lobby.gd), the HUD for 8 (client/hud.gd), the twin sticks
# on a phone (client/touch_sticks.gd), and reads the keyboard and the mouse on
# the PC: A D (or the arrows) run, W or space jumps, S is down (with jump: drop
# through a ledge), shift dodges the way you hold, hold the left mouse button
# to aim and let go to fire. P2: your own fighter is predicted (client/predict.gd:
# drawn on the tick you press, set right by the server's T_OWN), the arrows in the
# air are drawn on that same tick (client/present.gd), and the others 50 ms or
# more behind (client/net.gd, the draw delay follows your snapshot gaps).
# The look (P2's quality setting): LOW = T1, NORMAL = T2, HIGH = T3 (world.gd).
# An iPhone or iPad starts on LOW, an Android phone on NORMAL, the PC on HIGH; the
# lobby's LOOK button picks another, kept on the device. In a match, when more
# than 5% of the frames in 3 s take over 20 ms, it steps down one (never up by
# itself), before a phone halves its rate to 30, and says so at the bottom.
# Options (desktop: --key=value after --; web: ?key=value in the URL):
#   server=wss://host:8091  name=Ava  look=t2 (a test look, world.gd VARIANTS: no
#   setting, no step-down)  join  start
#   bots=N  info (the version, fps and ping at the bottom)  bench (the old
#   benchmark page instead, with its own options)  lag=MS jitter=MS (a test
#   knob: every packet sent and got waits MS/2, plus up to jitter, client/net.gd)
#   slow=MS (a test knob: every frame takes at least MS, for the step-down)
# ==============================================================================
extends Node

const P = preload("res://sim/proto.gd")
const Net = preload("res://client/net.gd")
const World = preload("res://client/world.gd")
const Hud = preload("res://client/hud.gd")
const Lobby = preload("res://client/lobby.gd")
const Sticks = preload("res://client/touch_sticks.gd")
const Predict = preload("res://client/predict.gd")
const Present = preload("res://client/present.gd")
const NAME_KEY := "towerbrawl_v2_name"
const TOKEN_KEY := "towerbrawl_v2_token"
const LOOK_KEY := "towerbrawl_v2_look"
const LOOKS := ["low", "normal", "high"]
const LOOK_TIER := {"low": 1, "normal": 2, "high": 3}
const SLOW_MS := 20.0          # a frame that takes longer counts as slow
const SLOW_SHARE := 0.05       # more than this share of slow frames in STEP_S: one step down
const STEP_S := 3.0
const STUCK_S := 5.0   # this long with no connection: the lobby says how to accept the game server's certificate
const KEYS := {"tb_left": [KEY_A, KEY_LEFT], "tb_right": [KEY_D, KEY_RIGHT], "tb_up": [KEY_W, KEY_UP],
	"tb_down": [KEY_S, KEY_DOWN], "tb_jump": [KEY_SPACE], "tb_dodge": [KEY_SHIFT]}

var opts := {}
var net
var pred
var present
var world
var sub: SubViewport
var display := TextureRect.new()
var hud
var lobby
var sticks
var server_url := ""
var my_seat := -1
var my_name := ""
var token := ""
var seats_msg := {}
var phase := -1
var retry_t := 0.0
var stuck_t := 0.0
var version_bad := false
var auto_join := false
var auto_start := false
var start_sent := false
var bots_sent := false
var aim_deg10 := 0
var shoot_held := false
var fps_frames := 0
var fps_t := 0.0
var fps_now := 0.0
var status := ""
var status_t := 0.0
var look := "high"
var look_test := false         # look= gave a test look: no setting, no step-down
var frame_gaps := PackedFloat32Array()   # the last STEP_S of frame gaps in a match (ms)
var frame_sum := 0.0
var frame_slow := 0
var last_frame_us := 0
var step_wait := 0.0
var slow_ms := 0.0

func _ready() -> void:
	opts = _read_opts()
	if opts.has("bench"):
		add_child(load("res://client/bench_client.tscn").instantiate())
		return
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.035))
	display.set_anchors_preset(Control.PRESET_FULL_RECT)
	display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	display.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(display)
	sub = SubViewport.new()
	sub.size = Vector2i(1920, 1080)
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(sub)
	world = World.new()
	sub.add_child(world)
	world.setup(Vector2i(1920, 1080), false, 1.0)
	look_test = opts.has("look") and world.set_variant(str(opts["look"]))
	if not look_test:
		look = _storage_get(LOOK_KEY)
		if not LOOKS.has(look):
			look = _device_look()
		world.set_tier(LOOK_TIER[look])
	slow_ms = float(opts.get("slow", 0))
	display.texture = sub.get_texture()
	hud = Hud.new()
	add_child(hud)
	lobby = Lobby.new()
	add_child(lobby)
	lobby.join_pressed.connect(_on_join)
	lobby.leave_pressed.connect(_on_leave)
	lobby.start_pressed.connect(_on_start)
	lobby.bots_changed.connect(_on_bots)
	lobby.look_pressed.connect(_on_look)
	lobby.set_look(str(opts["look"]) if look_test else look)
	sticks = Sticks.new()
	add_child(sticks)
	sticks.active = OS.has_feature("web_android") or OS.has_feature("web_ios") or OS.has_feature("mobile") \
		or DisplayServer.is_touchscreen_available()
	_setup_keys()
	my_name = str(opts.get("name", _storage_get(NAME_KEY)))
	token = _storage_get(TOKEN_KEY)
	if token == "":
		token = "%08x%08x" % [randi(), randi()]
		_storage_set(TOKEN_KEY, token)
	lobby.set_name_text(my_name)
	auto_join = opts.has("join")
	auto_start = opts.has("start")
	server_url = str(opts.get("server", ""))
	if server_url == "":
		if OS.has_feature("web"):
			server_url = "wss://%s:%d" % [str(JavaScriptBridge.eval("window.location.hostname", true)), P.PORT]
		else:
			server_url = "wss://127.0.0.1:%d" % P.PORT
	pred = Predict.new()
	present = Present.new()
	net = Net.new()
	net.lag_ms = float(opts.get("lag", 0))
	net.jitter_ms = float(opts.get("jitter", 0))
	net.open(server_url, my_name, token)
	get_viewport().size_changed.connect(_fit)
	_fit()
	print("🎮 [Client] %s, server %s, sticks %s, look %s" % [P.VERSION, server_url, "on" if sticks.active else "off",
		("%s (a test look)" % opts["look"]) if look_test else look])

func _read_opts() -> Dictionary:
	var o := {}
	var parts: Array = []
	for a in OS.get_cmdline_user_args():
		parts.append(a.trim_prefix("--"))
	if OS.has_feature("web"):
		var q := str(JavaScriptBridge.eval("window.location.search", true)).trim_prefix("?")
		for p in q.split("&", false):
			parts.append(p.uri_decode())
	for p in parts:
		if "=" in p:
			o[p.get_slice("=", 0)] = p.substr(p.find("=") + 1)
		elif p != "":
			o[p] = true
	return o

func _setup_keys() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.keycode = key
			InputMap.action_add_event(action, ev)

func _fit() -> void:
	var win := Vector2(get_viewport().get_visible_rect().size)
	hud.fit(win)
	lobby.fit(win)
	sticks.fit(win)

func _process(delta: float) -> void:
	if net == null:
		return
	net.poll()
	for m in net.take_messages():
		_on_message(m)
	for o in net.take_owns():
		pred.reconcile(o)
	pred.fade(delta)
	_keep_connected(delta)
	var s: Dictionary = net.newest()
	if not s.is_empty() and int(s["phase"]) != phase:
		_on_phase(int(s["phase"]), s)
	var rt: float = net.render_tick()
	var predicting: bool = pred.me != null and not s.is_empty()
	for e in pred.take_events():
		world.fx.on_event(e)
	for e in net.take_events(rt, my_seat if predicting else -1, Predict.PREDICTED):
		world.fx.on_event(e)
	var own: Dictionary = pred.fighter_dict(s["by_id"].get(my_seat, {})) if predicting else {}
	var view: Dictionary = net.sample(rt, -1, own)
	if predicting and not view.is_empty():
		view["arrows"] = present.arrows_at(s, pred.tick, pred.me, my_seat, view["fighters"], pred.sim.arrows, delta)
	world.render(view, delta)
	var aim_on := false
	var me: Dictionary = own if predicting else (s["by_id"].get(my_seat, {}) if not s.is_empty() else {})
	if shoot_held and not me.is_empty():
		aim_on = int(me["state"]) == P.F_NORMAL
		world.show_aim(Vector2(me["x"] + 18.0, me["y"] + 28.0), aim_deg10 * TAU / 3600.0, aim_on)
	if not aim_on:
		world.show_aim(Vector2.ZERO, 0.0, false)
	if predicting:   # the HUD shows your arrows as the prediction has them (a shot counts at once)
		s = s.duplicate()
		s["by_id"] = s["by_id"].duplicate()
		s["by_id"][my_seat] = own
	fps_frames += 1
	fps_t += delta
	if fps_t >= 0.5:
		fps_now = fps_frames / fps_t
		fps_frames = 0
		fps_t = 0.0
	if status_t > 0.0:
		status_t -= delta
		if status_t <= 0.0:
			status = ""
	var connected: bool = net.state == WebSocketPeer.STATE_OPEN
	stuck_t = 0.0 if connected else stuck_t + delta
	# a phone's browser drops a wss to a certificate it has not accepted, and never asks:
	# the page's own port (8443) was accepted, the game server's (8091) must be too
	var stuck_url := ""
	if stuck_t >= STUCK_S and server_url.begins_with("wss://") and not version_bad:
		stuck_url = "https://" + server_url.trim_prefix("wss://")
	if sticks.active != lobby.phone:
		lobby.set_phone(sticks.active)
	var show_lobby: bool = my_seat < 0 or phase < 0 or phase <= P.PH_COUNTDOWN or not connected
	_watch_frames(not show_lobby and phase >= P.PH_ROUND_START)
	hud.update(seats_msg, s, my_seat, delta, fps_now, net.last_rtt, opts.has("info"), show_lobby)
	lobby.visible = show_lobby
	sticks.visible = sticks.active and not show_lobby
	lobby.update(seats_msg, my_seat, phase, int(s.get("left", 0)), status, connected, version_bad, stuck_url)

# ------------------------------------------------------------------ the look (P2)
# The look a device starts on: an iPhone or iPad LOW (the benchmark's iPhone held
# T1 only; an iPad asks for the desktop page, so a touch Mac is one), an Android
# phone NORMAL, the PC HIGH.
func _device_look() -> String:
	if OS.has_feature("web_ios") or (OS.has_feature("web_macos") and DisplayServer.is_touchscreen_available()):
		return "low"
	if OS.has_feature("web_android") or OS.has_feature("mobile"):
		return "normal"
	return "high"

# The lobby's LOOK button: the next look, kept on this device.
func _on_look() -> void:
	if look_test:
		return
	look = LOOKS[(LOOKS.find(look) + 1) % LOOKS.size()]
	world.set_tier(LOOK_TIER[look])
	_storage_set(LOOK_KEY, look)
	lobby.set_look(look)
	_reset_frames(2.0)
	print("🎮 [Look] %s, picked in the lobby" % look)

# The step-down: the gaps between frames while a match is on screen. More than
# SLOW_SHARE of them over SLOW_MS in the last STEP_S: one look down (not kept on
# the device: the next visit starts on the picked look again).
func _watch_frames(in_match: bool) -> void:
	if slow_ms > 0.0:   # the test knob: this frame takes at least slow_ms
		var until := Time.get_ticks_usec() + int(slow_ms * 1000.0)
		while Time.get_ticks_usec() < until:
			pass
	var now := Time.get_ticks_usec()
	var gap := (now - last_frame_us) / 1000.0 if last_frame_us > 0 else 0.0
	last_frame_us = now
	if look_test or look == "low" or not in_match:
		_reset_frames(0.0)
		return
	if step_wait > 0.0:
		step_wait -= minf(gap, 1000.0) / 1000.0   # real time: Godot's delta reads short on a page that stalls
		return
	if gap <= 0.0 or gap > 1000.0:   # a tab that slept (seconds) is no slow frame; a long hitch is
		return
	frame_gaps.append(gap)
	frame_sum += gap
	if gap > SLOW_MS:
		frame_slow += 1
	while frame_sum - frame_gaps[0] >= STEP_S * 1000.0:
		frame_sum -= frame_gaps[0]
		if frame_gaps[0] > SLOW_MS:
			frame_slow -= 1
		frame_gaps.remove_at(0)
	if frame_sum >= STEP_S * 1000.0 - 50.0 and frame_slow > SLOW_SHARE * frame_gaps.size():
		var was := look
		look = LOOKS[LOOKS.find(look) - 1]
		world.set_tier(LOOK_TIER[look])
		lobby.set_look(look)
		hud.say("LOOK: %s · the game stepped down to stay smooth" % look.to_upper(), 4.0)
		print("🎮 [Look] step down %s -> %s: %d of %d frames over %d ms in %.0f s" % [
			was, look, frame_slow, frame_gaps.size(), int(SLOW_MS), STEP_S])
		_reset_frames(STEP_S)

func _reset_frames(wait_s: float) -> void:
	frame_gaps.clear()
	frame_sum = 0.0
	frame_slow = 0
	step_wait = maxf(step_wait, wait_s)

func _keep_connected(delta: float) -> void:
	if version_bad:
		return
	if net.state == WebSocketPeer.STATE_CLOSED:
		retry_t += delta
		if retry_t >= 2.0:
			retry_t = 0.0
			net.open(server_url, my_name, token)
	else:
		retry_t = 0.0

func _physics_process(_dt: float) -> void:
	if net == null or my_seat < 0 or net.state != WebSocketPeer.STATE_OPEN:
		shoot_held = false
		return
	var buttons := 0
	if sticks.active and sticks.visible:
		buttons = sticks.buttons()
		if sticks.aim_set:
			aim_deg10 = sticks.aim_deg10()
	# the keyboard and the mouse (the PC); a phone's touches never reach these
	if Input.is_action_pressed("tb_left"):
		buttons |= P.B_LEFT
	if Input.is_action_pressed("tb_right"):
		buttons |= P.B_RIGHT
	if Input.is_action_pressed("tb_up"):
		buttons |= P.B_UP | P.B_JUMP
	if Input.is_action_pressed("tb_down"):
		buttons |= P.B_DOWN
	if Input.is_action_pressed("tb_jump"):
		buttons |= P.B_JUMP
	if Input.is_action_pressed("tb_dodge"):
		buttons |= P.B_DODGE
	if not sticks.active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not lobby.visible:
		buttons |= P.B_SHOOT
		aim_deg10 = _mouse_aim()
	shoot_held = (buttons & P.B_SHOOT) != 0
	# P2: each tick the clock runs (one, or two or none while it catches up or falls
	# back): your fighter steps on it at once, and the input goes to the server for it
	var ticks: Array = net.ticks_now()
	if net.jumped:
		net.jumped = false
		if not ticks.is_empty():
			pred.jump_to(ticks[0] - 1)
	for t in ticks:
		pred.on_tick(t, buttons, aim_deg10)
		net.send_input(buttons, aim_deg10, t)

# The aim from the mouse: the angle from my bow (where I see myself) to the
# pointer, in world pixels.
func _mouse_aim() -> int:
	var at := Vector2.ZERO
	if pred.me != null:
		at = pred.drawn_pos()
	else:
		var s: Dictionary = net.newest()
		if s.is_empty() or not s["by_id"].has(my_seat):
			return aim_deg10
		at = Vector2(s["by_id"][my_seat]["x"], s["by_id"][my_seat]["y"])
	var win := Vector2(get_viewport().get_visible_rect().size)
	var k := minf(win.x / 1920.0, win.y / 1080.0)
	var off := (win - Vector2(1920, 1080) * k) * 0.5
	var mouse := (get_viewport().get_mouse_position() - off) / k
	var d := mouse - (at + Vector2(18.0, 28.0))
	if d.length() < 4.0:
		return aim_deg10
	return posmod(roundi(rad_to_deg(d.angle()) * 10.0), 3600)

func _on_phase(new_phase: int, s: Dictionary) -> void:
	phase = new_phase
	if new_phase == P.PH_ROUND_START:
		_reset_frames(2.0)   # a round's first moment (spawns, new sprites) is no measure
	hud.on_phase(new_phase, int(s["round"]))
	if new_phase == P.PH_LOBBY:
		start_sent = false

func _on_message(m: Dictionary) -> void:
	var kind := str(m.get("kind", ""))
	if kind == "welcome":
		my_seat = int(m.get("seat", -1))
		if pred.seat != my_seat:
			pred.seat = my_seat
			pred.me = null
		if my_seat < 0 and auto_join:
			auto_join = false
			_on_join(my_name)
		elif my_seat >= 0 and opts.has("bots") and not bots_sent:
			bots_sent = true
			net.send({"kind": "bots", "n": int(opts["bots"])})
	elif kind == "version_error":
		version_bad = true
		status = "WRONG VERSION: this page is %s, the server runs %s. Reload the page." % [m.get("yours", "?"), m.get("server", "?")]
		status_t = 0.0
		net.ws.close()
	elif kind == "full":
		_say("ALL 8 SEATS ARE TAKEN. Try again when someone leaves.", 4.0)
	elif kind == "note":
		_say(str(m.get("text", "")), 4.0)
	elif kind == "seats":
		seats_msg = m
		if auto_start and not start_sent and my_seat >= 0 and int(m.get("phase", 0)) == P.PH_LOBBY \
				and int(m.get("people", 0)) + int(m.get("bots", 0)) >= 2:
			start_sent = true
			net.send({"kind": "start"})
	elif kind == "round_end":
		hud.round_end(m)
	elif kind == "match_end":
		hud.match_end(m)

func _say(text: String, secs: float) -> void:
	status = text
	status_t = secs

func _on_join(name: String) -> void:
	my_name = name.strip_edges().substr(0, 12)
	_storage_set(NAME_KEY, my_name)
	net.send({"kind": "join", "name": my_name})

func _on_leave() -> void:
	net.send({"kind": "leave"})

func _on_start() -> void:
	net.send({"kind": "start"})

func _on_bots(n: int) -> void:
	net.send({"kind": "bots", "n": n})

# A saved value: localStorage on the web, user://tb_v2.cfg on the PC.
func _storage_get(key: String) -> String:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("window.localStorage.getItem(%s) || ''" % JSON.stringify(key), true)
		return str(v) if v != null else ""
	var cf := ConfigFile.new()
	if cf.load("user://tb_v2.cfg") == OK:
		return str(cf.get_value("v2", key, ""))
	return ""

func _storage_set(key: String, val: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.localStorage.setItem(%s, %s)" % [JSON.stringify(key), JSON.stringify(val)], true)
		return
	var cf := ConfigFile.new()
	cf.load("user://tb_v2.cfg")
	cf.set_value("v2", key, val)
	cf.save("user://tb_v2.cfg")

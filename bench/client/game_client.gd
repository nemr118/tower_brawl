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
#   bots=N  arena=N (the lobby's ARENA once seated: -1 MIX, 1 THE KEEP, 2 THE
#   BRIDGES, 0 the bench)  bolt_s=N (p4.9 test knob: each lightning bolt held N s)
#   info (the version, fps and ping at the bottom)  bench (the old
#   benchmark page instead, with its own options)  lag=MS jitter=MS (a test
#   knob: every packet sent and got waits MS/2, plus up to jitter, client/net.gd)
#   slow=MS (a test knob: every frame takes at least MS, for the step-down)
#   stick=old (p4.15: the phone stick as in p4.14: no pump or swing jumps, to compare)
# ==============================================================================
extends Node

const P = preload("res://sim/proto.gd")
const Net = preload("res://client/net.gd")
const Deathcam = preload("res://client/deathcam.gd")
const World = preload("res://client/world.gd")
const LevelScript = preload("res://sim/level.gd")
const Hud = preload("res://client/hud.gd")
const Lobby = preload("res://client/lobby.gd")
const Sticks = preload("res://client/touch_sticks.gd")
const Predict = preload("res://client/predict.gd")
const Present = preload("res://client/present.gd")
const PV = preload("res://client/powers_view.gd")
const Season = preload("res://client/season.gd")   # p4.18
const Music = preload("res://client/music.gd")     # p4.20: the songs (their own switch, off until picked)
const Sfx = preload("res://client/sfx.gd")         # p4.19: the sounds
const NAME_KEY := "towerbrawl_v2_name"
const TOKEN_KEY := "towerbrawl_v2_token"
const LOOK_KEY := "towerbrawl_v2_look"
const CONTROLS_KEY := "towerbrawl_v2_controls"   # p4.16: CLASSIC or BUTTONS, kept on the device
const HOWTO_KEY := "towerbrawl_v2_howto"         # p4.18: "1" once this device has seen HOW TO PLAY
const LOOKS := ["low", "normal", "high"]
const LOOK_TIER := {"low": 1, "normal": 2, "high": 3}
const PICKS := ["auto", "low", "normal", "high"]   # p4.6: the LOOK button; a picked look is kept, AUTO steps down
const PICKS_IOS := ["auto", "low", "normal"]      # p4.16: an iPhone or iPad ran HIGH at 15 to 17 fps (LOW 60): no HIGH there
const IOS_RES := 0.75          # p4.16 (iPhones at 15 to 30 fps at the gathering): iPhones and iPads draw the arena at this
                               # share of 1920 x 1080 (the picture scaled up to the screen); ?res=1 draws it full size
const SLOW_MS := 33.4          # a frame slower than 30 fps counts as slow (p4.6; it was 20 ms)
const SLOW_SHARE := 0.25       # more than this share of slow frames in STEP_S: one step down (p4.6; it was 5%)
const STEP_S := 5.0            # (p4.6; it was 3 s: a few hitches from explosions stepped a phone down)
const STUCK_S := 5.0   # this long with no connection: the lobby says how to accept the game server's certificate
const PROXY_S := 4.0   # p4.13: this long with no connection through the page's own address: try the game server's port
const KEYS := {"tb_left": [KEY_A, KEY_LEFT], "tb_right": [KEY_D, KEY_RIGHT], "tb_up": [KEY_W, KEY_UP],
	"tb_down": [KEY_S, KEY_DOWN], "tb_jump": [KEY_SPACE], "tb_dodge": [KEY_SHIFT], "tb_taunt": [KEY_G, KEY_T]}   # p4.19: G or T taunts

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
var direct_url := ""     # p4.13: the game server's own address (wss://host:8091), the second try
var ever_open := false   # the socket has opened at least once on server_url
# Bug 1 (the November review): a phone whose socket dropped came back to the lobby and
# had to tap JOIN. The server gives a held seat back by itself (the token in hello).
# When the seat is gone all the same (away longer than the hold), the page asks for a
# seat by itself, and for the one it had (the same colour) if nobody took it.
var had_seat := false        # this page had a seat when its socket went
var last_seat := -1          # that seat
var first_welcome := false   # the next welcome is the first on a new socket
var sock_open := false       # the socket was open on the last frame it was open or closed
var stuck_said := false      # the lobby shows ONE MORE STEP now (said once on the console)
var version_bad := false
var auto_join := false
var tv := false                   # p4.18 ?tv: THE BIG SCREEN (a TV: the match full screen, a QR code to join in the lobby)
var tv_asked := false
var auto_start := false
var start_sent := false
var bots_sent := false
var arena_sent := false
var aim_deg10 := 0
var shoot_held := false
var fps_frames := 0
# p4.7 (Night Log): a phone report to the server every REPORT_S, and at once when the
# look changes or the page logs an error (console.error, a script error): the look,
# the frame rate in matches, the ping, reconnects, step-downs, shots, errors.
const REPORT_S := 30.0
const REPORT_ERR_S := 5.0         # page errors go out at most this often
var rep_t := 0.0
var rep_err_t := 0.0
var rep_frames := 0               # frames, slow ones and their time since the last report (a match on screen)
var rep_slow := 0
var rep_time := 0.0
var rep_max_ms := 0.0
var rep_opens := 0                # the socket opened: the first time, then reconnects
var rep_was_open := false
var rep_step_downs := 0
var rep_errors := 0
var rep_mouse_shots := 0
var rep_ua := ""
var deathcam                      # p4.8: the match end's montage of the winner's kills
var music                         # p4.20: client/music.gd
var silly_now := 0                # p4.20: the silly round the seats message last named
var sfx                           # p4.19: the sounds (client/sfx.gd; sfx.set_on(true or false) for the lobby's SOUND button)
var match_msg := {}               # the match_end message, shown once the montage is done
var fps_t := 0.0
var fps_now := 0.0
var status := ""
var status_t := 0.0
var look := "high"              # the look in use: low, normal, high
var look_pick := "auto"         # p4.6: what the LOOK button picked (kept on the device): auto or a look
var world_res := 1.0            # p4.16: the arena's drawing size, a share of 1920 x 1080 (IOS_RES, ?res=)
var controls := "classic"       # p4.16: the phone controls (the lobby's CONTROLS; ?controls=buttons a test knob)
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
	world_res = clampf(float(opts.get("res", IOS_RES if _device() == "ios" else 1.0)), 0.5, 1.0)
	sub = SubViewport.new()
	sub.size = Vector2i(roundi(1920 * world_res), roundi(1080 * world_res))
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sub.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(sub)
	world = World.new()
	sub.add_child(world)
	world.setup(sub.size, false, 1.0)   # the camera zooms the 1920 x 1080 arena into it (p4.16: smaller on iPhones)
	look_test = opts.has("look") and world.set_variant(str(opts["look"]))
	if opts.has("bolt_s"):
		world.pview.bolt_s = float(opts["bolt_s"])   # p4.9 a test knob: the bolt held for pictures
	if not look_test:
		look_pick = _storage_get(LOOK_KEY)
		if look_pick == "high" and not _picks().has("high"):
			look_pick = "normal"   # p4.16: a HIGH kept from before, on an iPhone: NORMAL
		if not _picks().has(look_pick):
			look_pick = "auto"
		look = _device_look() if look_pick == "auto" else look_pick
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
	lobby.controls_pressed.connect(_on_controls)
	lobby.arena_pressed.connect(_on_arena)
	lobby.arena_picked.connect(func(n): net.send({"kind": "arena", "n": n}))   # 2026-10-26: a card in the picker
	lobby.bot_level_pressed.connect(_on_bot_level)
	lobby.power_pressed.connect(_on_power)
	lobby.season_picked.connect(func(pick): net.send({"kind": "season", "pick": pick}))   # p4.18
	lobby.look_picked.connect(_pick_look)          # p4.19 SETTINGS: a choice by name, not the next one
	lobby.controls_picked.connect(func(b): if b != (controls == "buttons"): _on_controls())
	world.pview.test_cream = opts.has("cream")   # p4.18 a test knob for pictures: PIE's cream on your own screen
	world.pview.test_phew = opts.has("phew")     # p4.19 a test knob for pictures: a PHEW on your own fighter every 3 s
	_show_look()
	sticks = Sticks.new()
	sticks.pump = str(opts.get("stick", "")) != "old"
	controls = str(opts.get("controls", _storage_get(CONTROLS_KEY)))
	if controls != "buttons":
		controls = "classic"
	sticks.buttons_mode = controls == "buttons"
	lobby.set_controls(sticks.buttons_mode)
	add_child(sticks)
	sticks.taunt_pressed.connect(_taunt)   # p4.19
	deathcam = Deathcam.new()
	add_child(deathcam)
	deathcam.skip_pressed.connect(func(): net.send({"kind": "skip"}))   # p4.8: back to the lobby for everyone
	sfx = Sfx.new()                # p4.19: a phone starts with sound off, a PC and THE BIG SCREEN with it on
	add_child(sfx)
	sfx.setup(self)
	lobby.set_sound(sfx.on, true)                  # SETTINGS has a SOUND row
	music = Music.new()                            # p4.20
	add_child(music)
	music.setup(self)
	lobby.set_music(music.on, true)
	lobby.music_picked.connect(func(v):
		music.set_on(v)
		lobby.set_music(music.on, true))
	lobby.sound_picked.connect(func(v):
		sfx.set_on(v)
		lobby.set_sound(sfx.on, true))
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
	tv = opts.has("tv")            # p4.18 THE BIG SCREEN: this page only watches
	if tv:
		auto_join = false
		token = ""                 # and it has no seat token: a player's tab in the same browser keeps its seat (the token is the browser's)
	auto_start = opts.has("start")
	server_url = str(opts.get("server", ""))
	if server_url == "":
		if OS.has_feature("web"):
			# p4.13: first through the page's own address (serve_game.py passes /v2ws on to the
			# game server), so the certificate the player accepted for the page is the only
			# one (an iPhone game on the Home Screen has no address bar for a second); the
			# game server's own port if that does not answer
			var host := str(JavaScriptBridge.eval("window.location.hostname", true))
			var port := str(JavaScriptBridge.eval("window.location.port", true))
			direct_url = "wss://%s:%d" % [host, P.PORT]
			server_url = direct_url
			if str(JavaScriptBridge.eval("window.location.protocol", true)) == "https:" and port != "":
				server_url = "wss://%s:%s/v2ws" % [host, port]
		else:
			server_url = "wss://127.0.0.1:%d" % P.PORT
	pred = Predict.new()
	present = Present.new()
	net = Net.new()
	net.lag_ms = float(opts.get("lag", 0))
	net.jitter_ms = float(opts.get("jitter", 0))
	net.open(server_url, my_name, token)
	_catch_page_errors()
	get_viewport().size_changed.connect(_fit)
	_fit()
	print("🎮 [Client] %s, server %s, sticks %s, arena drawn at %.2f, look %s" % [P.VERSION, server_url, "on" if sticks.active else "off", world_res,
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
	deathcam.fit(win)

func _process(delta: float) -> void:
	if net == null:
		return
	net.poll()
	if net.fresh:                # the socket opened (the first time, or again after a drop)
		net.fresh = false
		first_welcome = true
		pred.reset()             # bug 6: the prediction starts over with the new socket (a server started again counts from 0)
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
	var evs: Array = pred.take_events()
	evs.append_array(net.take_events(rt, my_seat if predicting else -1, Predict.PREDICTED))
	var own: Dictionary = pred.fighter_dict(s["by_id"].get(my_seat, {})) if predicting else {}
	var view: Dictionary = net.sample(rt, -1, own)
	if predicting and not view.is_empty():
		view["arrows"] = present.arrows_at(s, pred.tick, pred.me, my_seat, view["fighters"], pred.sim.arrows, delta)
	if deathcam.playing:
		# p4.8: the montage draws its recorded frames; the live ones wait
		var shot: Array = deathcam.step(delta)
		if deathcam.playing:
			for e in shot[1]:
				world.on_event(e)
			world.set_me(deathcam.winner, phase)
			world.replaying = true
			world.set_view_zoom(deathcam.zoom, deathcam.focus)
			world.render(shot[0], delta)
		else:
			world.set_view_zoom(1.0, Vector2(960, 540))
	else:
		world.replaying = false
		for e in evs:
			world.on_event(e)
			sfx.on_event(e, my_seat)   # p4.19
			_feel(e)
			if e[0] == P.E_PU_GET and e[3] == my_seat:
				hud.power_banner(e[4])   # p4.9: you took a power-up: what it is and what it does
			elif e[0] == P.E_TRICK and e[3] == my_seat and e[4] > 0 and e[4] < 4:   # p4.12: a trick: the small card
				hud.power_banner(P.PU_TRICK, P.trick_name(e[4], Season.now), P.TRICK_TIPS[e[4]], PV.TRICK_ICON + e[4] - 1)
			elif e[0] == P.E_CATCH_UP and e[3] == my_seat:   # p4.18: far behind: you start with a SHIELD
				hud.power_banner(P.PU_SHIELD, "SHIELD", "a head start: you're behind")
			elif e[0] == P.E_GHOST and e[3] == my_seat:
				hud.say("GHOST: fly anywhere, let go of shoot to BOO", 5.0)
		world.set_me(my_seat, phase)
		world.render(view, delta)
		deathcam.record(view, evs, delta)
	if not deathcam.playing and not match_msg.is_empty():
		hud.match_end(match_msg)   # after the montage (or with none): the winner's screen
		print("🏆 [Winner] %s: the winner's screen" % str(match_msg.get("name", "")))   # p4.17 (v2_shot.py --until)
		match_msg = {}
	var aim_on := false
	var me: Dictionary = own if predicting else (s["by_id"].get(my_seat, {}) if not s.is_empty() else {})
	if not me.is_empty():
		sticks.arrows_left = int(me["arrows"])
	# p4.16 BUTTONS: the DODGE button's cooldown sweep, from your predicted fighter (sim.gd DODGE_COOLDOWN 25 ticks after a dodge)
	sticks.dodge_wait = 1.0 if pred.me != null and pred.me.state == P.F_DODGE else (clampf(pred.me.dodge_cd / 25.0, 0.0, 1.0) if pred.me != null else 0.0)
	if shoot_held and not me.is_empty() and not deathcam.playing:
		aim_on = int(me["state"]) == P.F_NORMAL
		var from := Vector2(me["x"] + 18.0, me["y"] + 28.0)
		var empty: bool = int(me["arrows"]) <= 0
		if int(me["state"]) == P.F_DEAD:   # p4.11: your ghost aims its BOO
			for g in view.get("ghosts", []):
				if int(g["seat"]) == my_seat and (int(g["flags"]) & 1) == 0:
					from = Vector2(g["x"], g["y"])
					aim_on = true
					empty = false
		var armed: bool = sticks.aim_armed if (sticks.active and sticks.visible) else true   # the mouse held: armed
		world.show_aim(from, aim_deg10 * TAU / 3600.0, aim_on, armed, empty)
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
	_reports(delta, connected)
	stuck_t = 0.0 if connected else stuck_t + delta
	if connected:
		ever_open = true
	elif not ever_open and direct_url != "" and server_url != direct_url and stuck_t >= PROXY_S:
		print("🎮 [Client] no answer through %s: trying %s" % [server_url, direct_url])
		server_url = direct_url      # an older page server, or none: the game server's own port
		stuck_t = 0.0
		net.open(server_url, my_name, token)
	# a phone's browser drops a wss to a certificate it has not accepted, and never asks:
	# the page's own port (8443) was accepted, the game server's (8091) must be too
	# Only when the socket has never opened (the review's bug 11): once it has, the
	# certificate is fine, and 5 s without a connection is a Wi-Fi blip or a server that
	# is starting again. "ONE MORE STEP: open https://..." was wrong advice then, in every
	# lobby at once. The page says what it is doing instead, and keeps trying.
	var stuck_url := ""
	if stuck_t >= STUCK_S and server_url.begins_with("wss://") and not version_bad and not ever_open:
		stuck_url = "https://" + server_url.trim_prefix("wss://")
	if (stuck_url != "") != stuck_said:
		stuck_said = stuck_url != ""
		if stuck_said:
			print("🎮 [Client] ONE MORE STEP shown: no connection to %s yet, ever" % server_url)   # (tools/v2_drop_check.py reads it)
	if not connected and ever_open and not version_bad and status_t <= 0.0:
		status = "The connection dropped. Joining again by itself…"
		status_t = 0.5
	if sticks.active != lobby.phone:
		lobby.set_phone(sticks.active)
	var show_lobby: bool = my_seat < 0 or phase < 0 or phase <= P.PH_COUNTDOWN or not connected
	if tv:                        # THE BIG SCREEN has no seat: it shows every match
		show_lobby = phase < 0 or phase <= P.PH_COUNTDOWN or not connected
	_watch_frames(not show_lobby and phase >= P.PH_ROUND_START)
	hud.update(seats_msg, s, my_seat, delta, fps_now, net.last_rtt, opts.has("info"), show_lobby)
	lobby.visible = show_lobby
	lobby.tv_sound_hint = tv and (sfx.on or music.on) and not (sfx.unlocked or music.unlocked)   # p4.19: a browser plays no sound before one click
	music.set_scene(show_lobby, phase, P.PH_MATCH_END)   # p4.20: the lobby's song, the match's, the winner's
	sticks.visible = sticks.active and not show_lobby and not deathcam.playing and phase != P.PH_MATCH_END   # the winner's screen: nobody plays
	hud.visible = not deathcam.playing
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

# p4.19: a phone buzzes for a moment when something happens to YOU: knocked out, your
# shot lands, a pie in the face, a power-up, your shield goes, a PHEW. (Android only: an
# iPhone's browser cannot buzz, and nothing happens there.)
func _feel(e: Array) -> void:
	if my_seat < 0 or not sticks.active or not OS.has_feature("web"):
		return
	var t := int(e[0])
	var ms := 0
	if t == P.E_DEATH and e[3] == my_seat:
		ms = 90
	elif t == P.E_KILL and e[3] == my_seat and e[4] != my_seat:
		ms = 35
	elif t == P.E_PIED and e[3] == my_seat:
		ms = 60
	elif (t == P.E_PU_GET or t == P.E_SHIELD_POP or t == P.E_PHEW) and e[3] == my_seat:
		ms = 25
	if ms > 0:
		JavaScriptBridge.eval("if (navigator.vibrate) { try { navigator.vibrate(%d); } catch (e) {} }" % ms, true)

# p4.19 the GOBBLE button (a phone) or G (a PC): a taunt. The server says it to everyone
# (sim.gd taunt: at most one every 75 ticks; this page asks at most once a second).
var _taunt_ms := 0

func _taunt() -> void:
	var now := Time.get_ticks_msec()
	if my_seat < 0 or now - _taunt_ms < 1000:
		return
	_taunt_ms = now
	net.send({"kind": "taunt"})

# The lobby's LOOK button (p4.6): AUTO, LOW, NORMAL, HIGH, kept on this device. A
# picked look stays (the user: the look kept falling back to LOW after a round);
# AUTO starts on the device's guess and may step down.
# The lobby's CONTROLS button (p4.16, phones): CLASSIC (the stick jumps and dodges) or
# BUTTONS (a JUMP and a DODGE button), kept on this device.
func _on_controls() -> void:
	controls = "classic" if controls == "buttons" else "buttons"
	sticks.buttons_mode = controls == "buttons"
	_storage_set(CONTROLS_KEY, controls)
	lobby.set_controls(sticks.buttons_mode)
	print("🎮 [Controls] %s, picked in the lobby" % controls.to_upper())
	_send_report("look")

func _on_look() -> void:
	if look_test:
		return
	var picks := _picks()
	_pick_look(picks[(picks.find(look_pick) + 1) % picks.size()])

# p4.19: the look by name (SETTINGS): auto, low, normal or high.
func _pick_look(pick: String) -> void:
	if look_test or not _picks().has(pick) or pick == look_pick:
		return
	look_pick = pick
	look = _device_look() if look_pick == "auto" else look_pick
	world.set_tier(LOOK_TIER[look])
	_storage_set(LOOK_KEY, look_pick)
	_show_look()
	_reset_frames(2.0)
	print("🎮 [Look] %s, picked in the lobby" % _look_label())
	_send_report("look")

# The looks the LOOK button offers on this device (p4.16: no HIGH on an iPhone or iPad).
func _picks() -> Array:
	return PICKS_IOS if _device() == "ios" else PICKS

# The look on the lobby's button and in SETTINGS.
func _show_look() -> void:
	if look_test:
		lobby.set_look(str(opts["look"]))
	else:
		lobby.set_look(_look_label(), look_pick, not _picks().has("high"))

func _look_label() -> String:
	return ("AUTO · %s" % look.to_upper()) if look_pick == "auto" else look.to_upper()

# The step-down, on AUTO only (p4.6): the gaps between frames while a match is on
# screen. More than SLOW_SHARE of them over SLOW_MS in the last STEP_S: one look
# down (not kept on the device: the next visit starts on AUTO's guess again).
func _watch_frames(in_match: bool) -> void:
	if slow_ms > 0.0:   # the test knob: this frame takes at least slow_ms
		var until := Time.get_ticks_usec() + int(slow_ms * 1000.0)
		while Time.get_ticks_usec() < until:
			pass
	var now := Time.get_ticks_usec()
	var gap := (now - last_frame_us) / 1000.0 if last_frame_us > 0 else 0.0
	last_frame_us = now
	if in_match and gap > 0.0 and gap < 1000.0:   # p4.7: the phone report's frame numbers
		rep_frames += 1
		rep_time += gap
		rep_max_ms = maxf(rep_max_ms, gap)
		if gap > SLOW_MS:
			rep_slow += 1
	if look_test or look_pick != "auto" or look == "low" or not in_match:
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
		_show_look()
		hud.say("Picture set to %s to stay smooth. You can change it in SETTINGS." % look.to_upper(), 5.0)   # p4.19: plain words
		rep_step_downs += 1
		_send_report("step")
		print("🎮 [Look] step down %s -> %s: %d of %d frames over %d ms in %.0f s" % [
			was, look, frame_slow, frame_gaps.size(), int(SLOW_MS), STEP_S])
		_reset_frames(STEP_S)

# ------------------------------------------------------------------ the phone report (p4.7)
# Page errors (console.error, which Godot's own errors use, script errors, failed
# promises) go into a list on the page; each report takes up to 10 of them.
func _catch_page_errors() -> void:
	if not OS.has_feature("web"):
		return
	rep_ua = str(JavaScriptBridge.eval("navigator.userAgent", true)).substr(0, 140)
	JavaScriptBridge.eval("(function(){ if (window.__tbErrs) return; window.__tbErrs = []; var keep = function(s){ if (window.__tbErrs.length < 50) window.__tbErrs.push(String(s).slice(0, 240)); }; var ce = console.error; console.error = function(){ try { keep(Array.prototype.join.call(arguments, ' ')); } catch (e) {} return ce.apply(console, arguments); }; window.addEventListener('error', function(ev){ keep('script: ' + ev.message); }); window.addEventListener('unhandledrejection', function(ev){ keep('promise: ' + (ev.reason && ev.reason.message || ev.reason)); }); })()", true)

func _take_page_errors() -> Array:
	if not OS.has_feature("web"):
		return []
	var s = JavaScriptBridge.eval("(function(){ var e = window.__tbErrs || []; window.__tbErrs = []; return JSON.stringify(e.slice(0, 10)); })()", true)
	var a = JSON.parse_string(str(s)) if s != null else null
	return a if typeof(a) == TYPE_ARRAY else []

func _device() -> String:
	if OS.has_feature("web_ios") or (OS.has_feature("web_macos") and DisplayServer.is_touchscreen_available()):
		return "ios"
	if OS.has_feature("web_android") or OS.has_feature("mobile"):
		return "android"
	return "pc"

func _reports(delta: float, connected: bool) -> void:
	if connected and not rep_was_open:
		rep_opens += 1
		rep_t = REPORT_S - 3.0   # the first report 3 s after the socket opens (the hello goes first)
	rep_was_open = connected
	if not connected:
		return
	rep_t += delta
	rep_err_t += delta
	if rep_err_t >= REPORT_ERR_S:
		rep_err_t = 0.0
		var errs := _take_page_errors()
		if not errs.is_empty():
			rep_errors += errs.size()
			_send_report("error", errs)
			return
	if rep_t >= REPORT_S:
		_send_report("timer")

func _send_report(why: String, errs: Array = []) -> void:
	if net == null or net.state != WebSocketPeer.STATE_OPEN:
		return
	var win := get_viewport().get_visible_rect().size
	net.send({"kind": "report", "why": why, "device": _device(), "ua": rep_ua, "screen": "%dx%d" % [int(win.x), int(win.y)],
		"pick": "test" if look_test else look_pick, "look": look, "res": world_res,
		"fps": rep_frames * 1000.0 / rep_time if rep_time > 0.0 else 0.0,
		"slow_pct": 100.0 * rep_slow / rep_frames if rep_frames > 0 else 0.0, "frame_max_ms": rep_max_ms, "frames": rep_frames,
		"ping_ms": net.last_rtt, "reconnects": maxi(0, rep_opens - 1), "step_downs": rep_step_downs,
		"shots_armed": sticks.shots_armed, "shots_cancelled": sticks.shots_cancelled, "mouse_shots": rep_mouse_shots,
		"aim_taps": sticks.aim_taps,   # p4.16: right-side touches let go before they pulled (resting thumbs, taps)
		"controls": controls,          # p4.16: CLASSIC or BUTTONS
		"stick": "new" if sticks.pump else "old", "jumps": sticks.jumps, "rim_dodges": sticks.rim_dodges,
		"button_dodges": sticks.button_dodges,   # p4.15: how the phone's stick is used
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,   # p4.15: does a phone's memory
		"tex_mb": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,   # stay flat (the iPhone white screen)
		"late_pct": 100.0 * net.starved_frames / maxf(1.0, net.sampled_frames),   # p4.16 (the warping): frames with no newer
		"eased": net.eased, "eased_px": net.eased_max,   # snapshot, and the others' jumps eased out (Wi-Fi stalls)
		"errors": errs, "errors_total": rep_errors})
	rep_t = 0.0
	rep_frames = 0
	rep_slow = 0
	rep_time = 0.0
	rep_max_ms = 0.0

func _reset_frames(wait_s: float) -> void:
	frame_gaps.clear()
	frame_sum = 0.0
	frame_slow = 0
	step_wait = maxf(step_wait, wait_s)

func _keep_connected(delta: float) -> void:
	if version_bad:
		return
	if net.state == WebSocketPeer.STATE_CLOSED:
		if sock_open:
			sock_open = false
			retry_t = 1.7        # an open socket just closed: the first new try comes 0.3 s later (then every 2 s)
		retry_t += delta
		if retry_t >= 2.0:
			retry_t = 0.0
			net.open(server_url, my_name, token)
	else:
		retry_t = 0.0
		if net.state == WebSocketPeer.STATE_OPEN:
			sock_open = true

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
	if (Input.is_action_just_pressed("tb_taunt") or opts.has("taunt")) and not lobby.visible:   # ?taunt: a test knob, a taunt a second (pictures)
		_taunt()
	if not sticks.active and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not lobby.visible:
		buttons |= P.B_SHOOT
		aim_deg10 = _mouse_aim()
	if shoot_held and not (buttons & P.B_SHOOT) and not sticks.active:
		rep_mouse_shots += 1   # the phone report: a mouse shot let go
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
	sfx.on_phase(new_phase, s)     # p4.19: the countdown's beeps, FIGHT
	if new_phase == P.PH_ROUND_START:
		_reset_frames(2.0)   # a round's first moment (spawns, new sprites) is no measure
	hud.on_phase(new_phase, int(s["round"]))
	if new_phase == P.PH_ROUND_START and int(s["round"]) == 1:
		deathcam.clear()   # p4.8: a new match: the last match's kills go
	if new_phase == P.PH_LOBBY:
		start_sent = false
		deathcam.stop()    # the lobby is back: a montage still playing stops
		world.set_view_zoom(1.0, Vector2(960, 540))
		match_msg = {}

func _on_message(m: Dictionary) -> void:
	var kind := str(m.get("kind", ""))
	sfx.on_message(m, my_seat)     # p4.19: a round's end, the match's end, a player joins
	if kind == "tv":
		lobby.set_tv(m.get("urls", []), m.get("qr", []))
	elif kind == "welcome":
		if tv and not tv_asked:
			tv_asked = true
			net.send({"kind": "tv"})
		var first := first_welcome
		first_welcome = false
		my_seat = int(m.get("seat", -1))
		if pred.seat != my_seat:
			pred.seat = my_seat
			pred.me = null
		if my_seat >= 0:
			had_seat = true
			last_seat = my_seat
		elif not first:
			had_seat = false     # no seat on a socket that had one: I left, or the host took it. No asking again.
		if my_seat < 0 and auto_join:
			auto_join = false
			_on_join(my_name)
		elif my_seat < 0 and first and had_seat and not tv:
			# bug 1: back after a drop and the seat is gone: ask for one, no tap on JOIN
			print("🎮 [Client] back after a drop, the seat was given away: asking for seat %d again" % last_seat)
			net.send({"kind": "join", "name": my_name, "seat": last_seat})
		elif my_seat >= 0:
			# p4.18: this device's first seat ever: HOW TO PLAY opens by itself (not for the tests' pages: ?join, ?nohowto)
			if _storage_get(HOWTO_KEY) != "1" and not opts.has("join") and not opts.has("nohowto") and phase <= P.PH_COUNTDOWN:
				_storage_set(HOWTO_KEY, "1")
				lobby.open_howto()
			if opts.has("bots") and not bots_sent:
				bots_sent = true
				net.send({"kind": "bots", "n": int(opts["bots"])})
			if opts.has("arena") and not arena_sent:
				arena_sent = true
				net.send({"kind": "arena", "n": int(opts["arena"])})
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
		var sl := int(m.get("silly", 0))        # p4.20: a silly round starts: a ta-da, and a line for the tools
		if sl > 0 and sl != silly_now:
			sfx.play("lid")
			print("🎮 [Silly] %s" % P.silly_name(sl, str(m.get("season", Season.now))))
		silly_now = sl
		if m.has("season") and str(m["season"]) != Season.now:   # p4.18: the server's season dresses the page
			Season.now = str(m["season"])
			print("🎮 [Season] %s" % P.SEASON_LABEL.get(Season.now, "NONE"))
			_on_season()
		elif str(m.get("season_pick", "auto")) != lobby.season_pick:
			_on_season()       # the same season under another pick (AUTO to HARVEST in November): the button's words
		var seat_names: Array = []
		for st in m.get("seats", []):
			seat_names.append(str(st.get("name", "")))
		world.pview.names = seat_names   # p4.9: a BIG power-up's warning says whom it came for
		if auto_start and not start_sent and my_seat >= 0 and int(m.get("phase", 0)) == P.PH_LOBBY \
				and int(m.get("people", 0)) + int(m.get("bots", 0)) >= 2:
			start_sent = true
			net.send({"kind": "start"})
	elif kind == "round_end":
		hud.round_end(m)
		print("🏁 [Round] %s" % ("DRAW" if bool(m.get("draw", false)) else "%s wins the round" % str(m.get("name", ""))))
	elif kind == "match_end":
		var seat_names: Array = []
		for st in seats_msg.get("seats", []):
			seat_names.append(str(st.get("name", "")))
		match_msg = m
		deathcam.can_skip = my_seat >= 0
		if not opts.has("nocam"):   # p4.13 test knob ?nocam: straight to the winner's screen (pictures)
			deathcam.start(int(m.get("winner", -1)), seat_names)   # p4.8: the winner's kills first, if any
			print("🎬 [Replay] %s's kills: %s" % [str(m.get("name", "")), "on" if deathcam.playing else "none"])   # p4.17 (v2_shot.py --until)

func _say(text: String, secs: float) -> void:
	status = text
	status_t = secs

# p4.18: the season changed (the first seats message, or the lobby's SEASON button): the
# lobby and the banners take its dress.
func _on_season() -> void:
	lobby.set_season(Season.now, str(seats_msg.get("season_pick", "auto")))
	hud.set_season(Season.now)
	world.apply_season()

func _on_join(name: String) -> void:
	my_name = name.strip_edges().substr(0, 12)
	_storage_set(NAME_KEY, my_name)
	net.send({"kind": "join", "name": my_name})

func _on_leave() -> void:
	had_seat = false             # left on purpose: a later drop does not bring the seat back
	net.send({"kind": "leave"})

func _on_start() -> void:
	net.send({"kind": "start"})

# The lobby's ARENA button: MIX, then each arena of LevelScript.PLAY, then MIX (G5).
func _on_arena() -> void:
	var order: Array = [P.ARENA_MIX] + LevelScript.PLAY
	var i := order.find(int(seats_msg.get("arena", P.ARENA_MIX)))
	net.send({"kind": "arena", "n": order[(i + 1) % order.size()]})

func _on_bots(n: int) -> void:
	net.send({"kind": "bots", "n": n})

# The lobby's POWER-UPS button (p4.9; p4.5's power arrows before): the orbs on or off for everyone.
func _on_power() -> void:
	net.send({"kind": "power", "n": 0 if int(seats_msg.get("power", 0)) != 0 else 1})

# The lobby's bots level button: EASY, NORMAL, HARD, then EASY (G6).
func _on_bot_level() -> void:
	net.send({"kind": "bot_level", "n": 1 + int(seats_msg.get("bot_level", 2)) % 3})

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

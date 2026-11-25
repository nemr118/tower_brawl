# ==============================================================================
# The sounds (p4.19). One small player for the whole page. game_client.gd makes
# it and tells it three things: each event the server sends (on_event), each
# change of phase (on_phase) and each message (on_message). Which sound goes
# with which event is decided here, so the page's own file stays small.
#
# The sounds are made by tools/make_sfx.py (bench/assets/sfx/<name>.wav: cartoon
# sounds from plain maths, no recordings). On the web Godot plays them as
# "samples": the browser holds each one ready and starts it at once, with no
# delay (the project setting audio/general/default_playback_type.web is Sample
# unless someone changes it).
#
# ON or OFF: `on`. A phone starts OFF (8 phones in one room, and an iPhone is
# short of memory); a PC and THE BIG SCREEN (?tv) start ON. set_on() changes it
# and keeps the pick on the device. While it is off nothing is loaded and
# nothing runs: every call returns on its first line.
#
# One tap first: a browser lets a page play sound only after the player has
# tapped or clicked it. Until then `unlocked` is false and no sound is started
# (one started too early would wait, and they would all play at once on the
# first tap). bench/web/shell.html keeps the browser's sound machine in
# window.tbAudio and wakes it on the first tap anywhere on the page.
#
# The rules that keep it pleasant:
#   - at most VOICES sounds at once (the oldest one makes room),
#   - the same sound never twice within GAP_MS (8 fighters land 8 arrows),
#   - at most FRAME_MAX new sounds in one frame (a page that froze for a moment
#     gets all its late events at once: they must not all go off together),
#   - every play a little higher or lower (PITCH_SPREAD), so it is no machine,
#   - your own actions louder (OWN_DB) than everyone else's (OTHER_DB).
#
# Page options: ?sound=1 or ?sound=0 (a test knob: not kept on the device),
# ?sfxlog (a console line for each sound: tools/v2_sfx_check.py counts them).
# ==============================================================================
extends Node

const P = preload("res://sim/proto.gd")
const Season = preload("res://client/season.gd")
const DIR := "res://assets/sfx/"
const SOUND_KEY := "towerbrawl_v2_sound"   # "1" or "0" once picked on this device; nothing kept: the device's default
const VOICES := 8            # sounds at once, at most
const GAP_MS := 60           # the same sound not twice within this
const OWN_DB := -2.0         # how loud your own actions play (0 = as loud as the file is),
const OTHER_DB := -6.0       # and everyone else's (a full match's mix stayed under 0.7 of full scale: no clipping)
const PITCH_SPREAD := 0.04   # each play up to 4% higher or lower
const FRAME_MAX := 3         # new sounds in one frame, at most (the stings in KEEP always play)
const SEAT_PITCH := [0.76, 0.84, 0.92, 1.0, 1.09, 1.18, 1.28, 1.4]   # the taunt: one pitch a seat
const KEEP := ["fanfare", "draw", "round_win", "fight"]   # never cut short to make room for another
const WAIT_MS := 400         # a sound asked for just before the first tap woke the browser still plays
const E_PHEW := 45           # proto.gd's E_PHEW (the round's winner would have died after the call)
# every sound there is (tools/make_sfx.py SOUNDS; bench/tools/sfx_probe.gd checks the two lists match)
const NAMES := ["shoot", "thunk", "ko", "stomp", "dodge", "catch", "grab", "dry", "tink", "powerup", "shield_pop",
	"pop", "boom", "zap", "poof", "freeze", "count", "fight", "round_win", "draw", "fanfare", "phew", "taunt",
	"gobble", "gobble_startled", "splat", "wahwah", "lid", "crows", "gust", "peck", "meow", "bats", "furnace",
	"steam", "click", "join"]

var on := false
var unlocked := false        # the browser lets the page play now
var log_on := false          # ?sfxlog
var trace = null             # a test's list (bench/tools/sfx_probe.gd): the names asked for, and nothing plays
var client                   # game_client.gd: its options and its saved values
var streams := {}            # name -> the loaded sound (the first time it plays)
var players: Array = []      # the voices: VOICES AudioStreamPlayers, made when sound goes on
var started: Array = []      # for each voice: when its sound started (ms),
var busy_until: Array = []   # when it ends,
var kept: Array = []         # and whether it may be cut short
var last_ms := {}            # name -> when it last played
var beeps: Array = []        # the countdown's beeps still to come (ms)
var waiting: Array = []      # the last sound asked for while the browser was still locked
var lock_ms := -1000         # when the browser was last asked
var tapped := false          # the page saw a tap, a click or a key (an old shell with no window.tbAudio)
var last_phase := -1
var people := -1             # the people in the lobby, to hear one join
var frame_no := -1           # the frame the count below is for,
var frame_n := 0             # and the sounds started in it

# Called once by the page. Reads the pick: the page's option, else what this
# device kept, else the device's default (a phone OFF, a PC and the TV page ON).
func setup(c) -> void:
	client = c
	log_on = c.opts.has("sfxlog")
	var pick := str(c.opts.get("sound", c._storage_get(SOUND_KEY)))
	var want: bool = (c._device() == "pc" or c.opts.has("tv")) if pick == "" else (pick == "1" or pick == "true")
	set_process(false)
	set_process_input(false)
	set_on(want, false)
	if not on:
		print("🔊 [Sfx] sound OFF")

# The lobby's SOUND button calls this. keep: remember the pick on this device.
func set_on(v: bool, keep := true) -> void:
	if keep and client != null:
		client._storage_set(SOUND_KEY, "1" if v else "0")
	if v == on:
		return
	on = v
	set_process(on)
	set_process_input(on)
	if on:
		for i in VOICES:
			var p := AudioStreamPlayer.new()
			add_child(p)
			players.append(p)
			started.append(0)
			busy_until.append(0)
			kept.append(false)
		_watch_buttons()
		_ask_browser(Time.get_ticks_msec())
		if keep:
			_play("click", true)     # the button that turned it on is heard
	else:
		for p in players:
			p.queue_free()           # a freed voice stops
		players.clear()
		started.clear()
		busy_until.clear()
		kept.clear()
		streams.clear()
		last_ms.clear()
		beeps.clear()
		waiting = []
		if get_tree().node_added.is_connected(_on_node):
			get_tree().node_added.disconnect(_on_node)
	print("🔊 [Sfx] sound %s%s" % ["ON" if on else "OFF", "" if not on or unlocked else " (waiting for the first tap)"])

# Play a sound by name. own: it is this player's own action (a bit louder).
# x: where it is in the arena, 0..1920 (kept for a left-right pan; not used yet).
# seat: for "taunt", the seat whose pitch it plays at.
func play(name: String, own := false, x := -1.0, seat := -1) -> void:
	if not on:
		return
	_play(name, own, x, SEAT_PITCH[seat % SEAT_PITCH.size()] if seat >= 0 and name == "taunt" else 1.0)

func _play(name: String, own := false, x := -1.0, pitch := 1.0, db := 0.0) -> void:
	if trace != null:
		trace.append(name)
		return
	if not on:
		return
	var now := Time.get_ticks_msec()
	if now - int(last_ms.get(name, -100000)) < GAP_MS:
		return
	if not unlocked:
		_ask_browser(now)
		if not unlocked:
			waiting = [name, own, x, pitch, db, now]
			return
	if Engine.get_process_frames() != frame_no:
		frame_no = Engine.get_process_frames()
		frame_n = 0
	if frame_n >= FRAME_MAX and not KEEP.has(name):
		return
	var t0 := Time.get_ticks_usec()
	var first := not streams.has(name)
	if first:
		var path := DIR + name + ".wav"
		streams[name] = load(path) if ResourceLoader.exists(path) else null
		if streams[name] == null:
			print("🔊 [Sfx] no sound file for '%s'" % name)
	var st: AudioStream = streams[name]
	if st == null:
		return
	# a voice that is done, or else the one that started first
	var pick := -1
	for i in VOICES:
		if busy_until[i] <= now:
			pick = i
			break
	if pick < 0:
		for i in VOICES:
			if not kept[i] and (pick < 0 or started[i] < started[pick]):
				pick = i
		if pick < 0:
			return
	var p: AudioStreamPlayer = players[pick]
	p.stream = st
	p.pitch_scale = pitch * randf_range(1.0 - PITCH_SPREAD, 1.0 + PITCH_SPREAD)
	p.volume_db = (OWN_DB if own else OTHER_DB) + db
	p.play()
	frame_n += 1
	last_ms[name] = now
	started[pick] = now
	busy_until[pick] = now + int(st.get_length() * 1000.0 / p.pitch_scale) + 30
	kept[pick] = KEEP.has(name)
	if log_on:      # the name, then what this play cost the page (the first play of a sound loads it)
		print("🔊 [Sfx] %s %.2f ms%s%s" % [name, (Time.get_ticks_usec() - t0) / 1000.0, " first" if first else "", " own" if own else ""])

# ------------------------------------------------------------------ the events
# One event from the server: [type, x, y, a, b] (sim/proto.gd). me: this page's
# seat (-1: THE BIG SCREEN, or not seated).
func on_event(e: Array, me: int) -> void:
	if not on or not _watching():
		return
	var a: int = e[3]
	var b: int = e[4]
	var x: float = e[1]
	var own := a == me
	var harvest: bool = Season.now == "harvest"
	match int(e[0]):
		P.E_SHOOT:
			_play("shoot", own, x)
		P.E_STICK:
			_play("thunk", false, x)
		P.E_PIN:                      # an arrow pins a body to the wall: a deeper thunk
			_play("thunk", false, x, 0.8, 3.0)
		P.E_DODGE:
			_play("dodge", own, x)
		P.E_CATCH:
			_play("catch", own, x)
		P.E_PICKUP:                   # only your own: 8 fighters pick arrows up all the time
			if own:
				_play("grab", true, x)
		P.E_DRYFIRE:
			if own:
				_play("dry", true, x)
		P.E_TINK:
			_play("tink", false, x)
		P.E_JUMP:                     # only a stomp's bounce (b = 1); plain jumps are silent
			if b == 1:
				_play("stomp", own, x)
		P.E_DEATH:                    # a stomp has its boing; your own knockout you always hear
			if b != 3 or own:
				_play("ko", own, x)
		P.E_EXPLODE:                  # b: 8 a pie, 4 a seed or a popcorn kernel, 1 a BIG arrow's
			if (b & 8) != 0:
				_play("splat", own, x)
			elif (b & 4) != 0:
				_play("pop", false, x, 1.15)
			else:
				_play("boom", own, x, 0.85 if (b & 1) != 0 else 1.0)
		P.E_PIED:                     # cream on your own screen (THE BIG SCREEN hears everyone's)
			if own or me < 0:
				_play("wahwah", own, x)
		P.E_PU_GET:
			if b == P.PU_BATS:
				_play("crows" if harvest else "bats", own, x)
			else:
				_play("powerup", own, x)
		P.E_SHIELD_POP:
			_play("shield_pop", own, x)
		P.E_STRIKE:
			_play("zap", false, x)
		P.E_FREEZE:
			_play("freeze", own, x)
		P.E_MIASMA, P.E_SMOKE:
			_play("poof", false, x)
		P.E_CAT_POOF:
			_play("poof", false, x, 1.3)
		P.E_GHOST_POP:
			_play("pop", false, x)
		P.E_CAT_COME:                 # a = 1: the turkey, else the black cat
			_play("gobble" if a == 1 else "meow", false, x)
		P.E_PET:                      # b = 1: the turkey is caught, else the cat is petted
			_play("gobble_startled" if b == 1 else "meow", own, x, 1.0 if b == 1 else 1.25)
		P.E_CANDY_GET:                # a dish's lid in the Harvest season, a candy's wrapper otherwise
			_play("lid" if harvest else "powerup", own, x, 1.0 if harvest else 1.3)
		P.E_TRICK:                    # b 1..3: a silly trick (0 and 4 are treats: their power-up's sparkle follows)
			if b >= 1 and b <= 3 and (own or me < 0):
				_play("wahwah", own, x, 1.12)
		P.E_BATS:                     # a sweep comes: a gust of leaves on the barn, else crows or bats
			var barn: bool = client != null and client.world != null and client.world.level != null and client.world.level.theme == "barn"
			_play("gust" if barn else ("crows" if harvest else "bats"), false, x)
		P.E_KNIFE:                    # THE BIG TURKEY pecks; GHOSTFACE's knife swishes
			_play("peck" if harvest else "dodge", own, x, 1.0 if harvest else 1.5)
		P.E_MASK_DOWN:                # the costume is knocked down
			_play("gobble_startled" if harvest else "thunk", own, x, 0.85 if harvest else 0.7)
		P.E_FURNACE:
			_play("furnace", false, x)
		P.E_STEAM:
			_play("steam", false, x)
		E_PHEW:
			_play("phew", own, x)
		P.E_TAUNT:      # the GOBBLE button, or a bot gloating: each seat at its own pitch
			play("taunt", own, x, a)

# The phase changed (sim/proto.gd PH_*). s: the newest snapshot (its "left": the
# phase's ticks left, 60 a second).
func on_phase(ph: int, s: Dictionary) -> void:
	var was := last_phase
	last_phase = ph
	beeps.clear()
	if not on:
		return
	if ph == P.PH_COUNTDOWN:
		# a beep for the number on the screen now, then one as each smaller number
		# comes (the number n shows from n seconds left)
		var now := Time.get_ticks_msec()
		var left := int(s.get("left", 180))
		beeps.append(now)
		for n: int in range(ceili(left / 60.0) - 1, 0, -1):
			beeps.append(now + (left - n * 60) * 1000 / 60)
	elif ph == P.PH_PLAY and was == P.PH_ROUND_START and _watching():
		_play("fight", true)

# A message from the server ({"kind": ...}; server/game_server.gd lists them).
func on_message(m: Dictionary, me: int) -> void:
	if not on:
		return
	var kind := str(m.get("kind", ""))
	if kind == "round_end" and _watching():
		if bool(m.get("draw", false)):
			_play("draw", true)
		else:
			_play("round_win", int(m.get("winner", -1)) == me)
	elif kind == "match_end" and _watching():
		_play("fanfare", true)
	elif kind == "seats":
		var n := int(m.get("people", 0))
		if people >= 0 and n > people and int(m.get("phase", 0)) == P.PH_LOBBY:
			_play("join", false)
		people = n

# Is the match on this screen? Someone still in the lobby (no seat yet) sees no
# match, so they hear none: only the lobby's own sounds.
func _watching() -> bool:
	return client == null or not client.lobby.visible

# ------------------------------------------------------------------ the first tap, the countdown
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if not unlocked or now - lock_ms > 1000:
		_ask_browser(now)             # it can lock again (an iPhone's page in the background)
	if unlocked and not waiting.is_empty():
		var w := waiting
		waiting = []
		if now - int(w[5]) <= WAIT_MS:
			_play(w[0], w[1], w[2], w[3], w[4])
	while not beeps.is_empty() and now >= int(beeps[0]):
		beeps.pop_front()
		_play("count", true)

func _input(ev: InputEvent) -> void:
	if not tapped and ev.is_pressed() and (ev is InputEventMouseButton or ev is InputEventScreenTouch or ev is InputEventKey):
		tapped = true

# Is the browser's sound machine running? Asked at most every 100 ms.
func _ask_browser(now: int) -> void:
	if now - lock_ms < 100:
		return
	lock_ms = now
	var was := unlocked
	if not OS.has_feature("web"):
		unlocked = true               # a window on the PC plays at once
	else:
		var st = JavaScriptBridge.eval("(window.tbAudio && window.tbAudio.state) || ''", true)
		unlocked = tapped if (st == null or str(st) == "") else str(st) == "running"
	if unlocked != was and log_on:
		print("🔊 [Sfx] %s" % ("unlocked: the browser plays now" if unlocked else "locked: the browser stopped the sound"))

# ------------------------------------------------------------------ the buttons
# Every button in the page clicks (the lobby's, and any made later).
func _watch_buttons() -> void:
	for b in get_tree().root.find_children("*", "BaseButton", true, false):
		_on_node(b)
	if not get_tree().node_added.is_connected(_on_node):
		get_tree().node_added.connect(_on_node)

func _on_node(n: Node) -> void:
	if n is BaseButton and not n.pressed.is_connected(_click):
		n.pressed.connect(_click)

func _click() -> void:
	_play("click", true)

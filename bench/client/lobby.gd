# The lobby: your name, JOIN or LEAVE, the 8 seats, the arena (G5: MIX or one
# of them, for everyone), the look (LOW, NORMAL or HIGH: P2's quality setting,
# kept on the device), the bots and their level (G6: EASY, NORMAL, HARD, for
# everyone), the power-ups, START and the countdown, and a status line. Shown
# when you have no seat and between matches; the arena shows through behind it.
# The 2026-10-25 overhaul (the user: "plain and uninspiring"): a title with a
# glow, a gradient and a ribbon (client/lobby_logo.gd), the seats as a line-up of
# cards in each player's colour with the fighters standing in them
# (client/lobby_cards.gd), buttons with depth that glow when they are the next
# thing to press, a moving backdrop over the arena: mist, embers, bats and
# lightning in the Halloween dress (client/lobby_bg.gd), a 3, 2, 1 that punches
# in (client/lobby_count.gd). The parts rise in when the lobby comes up and drop
# away at the countdown's end. The dress (Halloween in October, else the castle
# at night) and the shared shapes: client/lobby_art.gd. LOW keeps the backdrop
# light. Built on a 1920 x 1080 frame scaled to fit the window and centred; the
# backdrop fills the whole window. The old lobby: git (bench/client/lobby.gd).
extends CanvasLayer

signal join_pressed(name: String)
signal leave_pressed
signal start_pressed
signal bots_changed(n: int)
signal look_pressed
signal arena_pressed
signal arena_picked(n: int)       # 2026-10-26: a card in the arena picker (lobby_arenas.gd)
signal controls_pressed           # p4.16: CONTROLS (CLASSIC or BUTTONS, kept on the device; phones only)
signal bot_level_pressed
signal power_pressed

const P = preload("res://sim/proto.gd")
const LevelScript = preload("res://sim/level.gd")
const Art = preload("res://client/lobby_art.gd")
const Bg = preload("res://client/lobby_bg.gd")
const Logo = preload("res://client/lobby_logo.gd")
const Cards = preload("res://client/lobby_cards.gd")
const Count = preload("res://client/lobby_count.gd")
const Arenas = preload("res://client/lobby_arenas.gd")
const Polish = preload("res://client/polish.gd")
const UI_ICONS := preload("res://assets/ui_icons.png")   # p4.17 (polish "ui_icons"): 128 px cells, tools/comfy/make_assets.py ICONS
const PU_ICONS := preload("res://assets/pu_icons.png")   # the power-up pictures: cell 13 the lightning, on POWER-UPS
enum { IC_BOTS, IC_LEVEL, IC_LOOK, IC_CONTROLS, IC_LEAVE, IC_CROWN }
const LEVEL_NAMES := ["OLD", "EASY", "NORMAL", "HARD"]   # sim/brain.gd NAMES
# The controls line: [kind, words]; kind "k" a key cap, "t" words, "-" a gap.
const HELP_PC := [["k", "A"], ["k", "D"], ["t", "RUN"], ["-", ""], ["k", "W"], ["t", "OR"], ["k", "SPACE"], ["t", "JUMP"], ["-", ""],
	["k", "S"], ["t", "DOWN (+ JUMP: DROP)"], ["-", ""], ["k", "SHIFT"], ["t", "DODGE"], ["-", ""], ["t", "HOLD"], ["k", "MOUSE"],
	["t", "TO AIM, LET GO TO FIRE"]]
const HELP_PHONE := [["t", "LEFT STICK RUNS, PUSH IT UP TO JUMP"], ["-", ""], ["t", "RIGHT THUMB: PULL BACK, LET GO TO FIRE"],
	["-", ""], ["k", "DODGE"], ["t", "OR FLICK THE STICK"]]
const HELP_BUTTONS := [["t", "LEFT STICK RUNS"], ["-", ""], ["k", "JUMP"], ["k", "DODGE"], ["t", "BOTTOM RIGHT"], ["-", ""],
	["t", "RIGHT THUMB: PULL BACK, LET GO TO FIRE"]]   # p4.16: the BUTTONS layout
# The frame's rows (y): the cards 244..608 (lobby_cards.gd), the status line,
# the settings, the name and the big button, the controls line.
const STATUS_Y := 616.0
const SET_Y := 684.0
const SET_H := 96.0
const ACT_Y := 798.0
const ACT_H := 154.0
const HELP_Y := 1030.0

var bg := Bg.new()
var root := Control.new()
var logo := Logo.new()
var cards := Cards.new()
var dock := _Dock.new()
var notice := _Notice.new()
var count := Count.new()
var corner := _Corner.new()
var name_edit := LineEdit.new()
var name_cap := Label.new()
var main_btn = Art.Btn.new()      # JOIN, START, the countdown, MATCH ON, CONNECTING
var leave_btn = Art.Btn.new()
var arena_btn = Art.Btn.new()
var arenas = Arenas.new()         # 2026-10-26 polish "arena_cards": the picker the ARENA button opens
var arena_pick: int = P.ARENA_MIX
var power_btn = Art.Btn.new()
var level_btn = Art.Btn.new()
var look_btn = Art.Btn.new()
var controls_btn = Art.Btn.new()  # p4.16: under LOOK, phones only
var buttons_mode := false
var bots_minus = Art.Btn.new()
var bots_plus = Art.Btn.new()
var notice_text := Label.new()
var seated := false
var bots_wanted := 7
var phone := false
var dress := "castle"
var pal: Dictionary = {}
var tier := 2
var t := 0.0
var intro := 0.0                  # seconds since the lobby came up (the parts rise in)
var was_shown := true
var bots_now := 0
var status := ""
var status_t := 9.0               # seconds since the status line changed (it pops)
var notice_title := ""
var help: Array = HELP_PC
var main_glow := 0                # 0 none, 1 pulse (the thing to press), 2 steady (the countdown)
var count_secs := 0
var count_left := 0.0             # the countdown's seconds left (the parts drop away at its end)
var count_arena := ""
var last_phase := -1
var slow := 1.0                   # the test knob ?lobby_slow=N (lobby_art.gd slow_knob)

class _Dock extends Control:
	var lobby
	func _draw() -> void:
		if lobby != null:
			lobby._paint_dock(self)

class _Notice extends Control:
	var lobby
	func _draw() -> void:
		if lobby != null:
			lobby._paint_notice(self)

class _Corner extends Control:
	var lobby
	func _draw() -> void:
		if lobby != null:
			lobby._paint_corner(self)

func _init() -> void:
	layer = 20
	Art.fonts_ready()
	dress = Art.pick_dress()
	slow = Art.slow_knob()
	pal = Art.DRESSES[dress]
	var hw := dress == "halloween"
	add_child(bg)
	bg.set_dress(pal, hw)
	bg.set_tier(tier)
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(root)
	root.add_child(logo)
	logo.set_dress(pal, hw)
	root.add_child(cards)
	cards.set_dress(pal, hw)
	for c in [dock, notice, corner]:
		c.lobby = self
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(1920, 1080)
	root.add_child(dock)
	# the settings row
	var face: Color = pal["button"]
	var ink: Color = pal["text"]
	_btn(arena_btn, face, ink, 40, Rect2(60, SET_Y, 520, SET_H), 5)
	arena_btn.pressed.connect(_on_arena_btn)
	_btn(power_btn, face, ink, 40, Rect2(596, SET_Y, 360, SET_H), 5)
	power_btn.pressed.connect(func(): power_pressed.emit())
	_btn(bots_minus, face.lightened(0.08), ink, 54, Rect2(1250, SET_Y + 8, 86, SET_H - 16), 6)
	bots_minus.pressed.connect(func(): bots_changed.emit(bots_wanted - 1))
	_btn(bots_plus, face.lightened(0.08), ink, 54, Rect2(1346, SET_Y + 8, 86, SET_H - 16), 7)
	bots_plus.pressed.connect(func(): bots_changed.emit(bots_wanted + 1))
	_btn(level_btn, face, ink, 40, Rect2(1458, SET_Y, 402, SET_H), 5)
	level_btn.pressed.connect(func(): bot_level_pressed.emit())
	# the name, LEAVE, and the big button (START covers the old START's spot,
	# 1230 x 854: tools/v2_shot.py taps there)
	_name_field(Rect2(60, ACT_Y, 820, ACT_H))
	_btn(leave_btn, pal["danger"], ink, 40, Rect2(656, ACT_Y + 14, 244, ACT_H - 28), 4)
	leave_btn.say("", "LEAVE")
	leave_btn.pressed.connect(func(): leave_pressed.emit())
	_btn(main_btn, pal["accent"], Color(0.13, 0.05, 0.0), 72, Rect2(920, ACT_Y, 940, ACT_H), 2)
	main_btn.glow_col = pal["accent_hi"]
	main_btn.pressed.connect(_on_main)
	root.add_child(notice)
	notice_text.position = Vector2(400, 392)
	notice_text.size = Vector2(1120, 190)
	notice_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice_text.add_theme_font_override("font", Art.BODY)
	notice_text.add_theme_font_size_override("font_size", 34)
	notice_text.add_theme_color_override("font_color", pal["text"])
	notice_text.add_theme_constant_override("outline_size", 6)
	notice_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	notice_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.add_child(notice_text)
	notice.visible = false
	root.add_child(corner)
	_btn(look_btn, face.darkened(0.2), ink, 30, Rect2(1540, 18, 320, 72), 5, corner)
	look_btn.pressed.connect(func(): look_pressed.emit())
	_btn(controls_btn, face.darkened(0.2), ink, 30, Rect2(1540, 100, 320, 72), 5, corner)
	controls_btn.pressed.connect(func(): controls_pressed.emit())
	controls_btn.visible = false
	if Polish.on("ui_icons"):
		power_btn.pic = PU_ICONS
		power_btn.pic_src = Rect2(13 * 64, 0, 64, 64)
		for pair in [[level_btn, IC_LEVEL], [leave_btn, IC_LEAVE], [look_btn, IC_LOOK], [controls_btn, IC_CONTROLS]]:
			pair[0].pic = UI_ICONS
			pair[0].pic_src = Rect2(pair[1] * 128, 0, 128, 128)
		leave_btn.glyph = 0            # the door in place of the back arrow
	set_controls(false)
	root.add_child(count)
	count.set_dress(pal)
	root.add_child(arenas)            # on top of everything in the lobby
	arenas.picked.connect(func(n): arena_picked.emit(n))
	visibility_changed.connect(_on_visibility)

# The ARENA button: the picker of painted cards (polish "arena_cards"), or the next arena as before.
func _on_arena_btn() -> void:
	if Polish.on("arena_cards"):
		arenas.open(arena_pick)
	else:
		arena_pressed.emit()

func _btn(b, face: Color, ink: Color, fsize: int, r: Rect2, icon: int, parent: Control = null) -> void:
	b.setup(face, ink, fsize)
	b.position = r.position
	b.size = r.size
	b.glyph = icon
	(parent if parent != null else dock).add_child(b)

func _name_field(r: Rect2) -> void:
	name_edit.position = r.position
	name_edit.size = r.size
	name_edit.max_length = 12
	name_edit.placeholder_text = "TYPE A NAME"
	name_edit.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var edge: Color = pal["panel_edge"]
	var accent: Color = pal["accent"]
	var n := _field_box(Color(0.02, 0.01, 0.04, 0.92), edge, Color(0, 0, 0, 0.5), 10)
	var f := _field_box(Color(0.03, 0.02, 0.06, 0.96), accent, Color(accent.r, accent.g, accent.b, 0.45), 18)
	var ro := _field_box(Color(pal["panel"], 0.9), Color(edge, 0.6), Color(0, 0, 0, 0.4), 8)
	name_edit.add_theme_stylebox_override("normal", n)
	name_edit.add_theme_stylebox_override("focus", f)
	name_edit.add_theme_stylebox_override("read_only", ro)
	name_edit.add_theme_font_override("font", Art.DISPLAY)
	name_edit.add_theme_font_size_override("font_size", 56)
	name_edit.add_theme_color_override("font_color", pal["text"])
	name_edit.add_theme_color_override("font_uneditable_color", Color(1.0, 0.97, 0.85))
	name_edit.add_theme_color_override("font_placeholder_color", Color(pal["faint"], 0.9))
	name_edit.add_theme_color_override("caret_color", accent)
	name_edit.add_theme_constant_override("caret_width", 4)
	name_edit.text_submitted.connect(func(_t): if not seated: _on_main())
	dock.add_child(name_edit)
	name_cap.text = "YOUR NAME"
	name_cap.position = Vector2(24, 6)
	name_cap.add_theme_font_override("font", Art.BODY)
	name_cap.add_theme_font_size_override("font_size", 28)
	name_cap.add_theme_color_override("font_color", pal["dim"])
	name_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_edit.add_child(name_cap)

func _field_box(fill: Color, edge: Color, sh: Color, sh_size: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(3)
	s.border_width_top = 5
	s.set_corner_radius_all(16)
	s.corner_detail = 6
	s.shadow_color = sh
	s.shadow_size = sh_size
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 44
	s.content_margin_bottom = 10
	return s

func _on_main() -> void:
	if seated:
		start_pressed.emit()
	else:
		join_pressed.emit(name_edit.text)

func _on_visibility() -> void:
	if visible and not was_shown:
		intro = 0.0
	was_shown = visible
	for part in [bg, logo, cards]:
		part.set_process(visible)   # a match on screen: the lobby's parts rest

# The window's size: the frame scaled to fit and centred; the backdrop fills it all.
func fit(win: Vector2) -> void:
	var k := minf(win.y / 1080.0, win.x / 1920.0)
	scale = Vector2.ONE * k
	offset = Vector2((win.x - 1920.0 * k) * 0.5, (win.y - 1080.0 * k) * 0.5)
	bg.position = -offset / k
	bg.size = win / k

func set_name_text(n: String) -> void:
	name_edit.text = n

# The look's name on its button: LOW, NORMAL, HIGH, AUTO · LOW (or a test look's
# name: t1 is LOW's, t3 HIGH's). LOW keeps the backdrop light.
func set_look(name: String) -> void:
	look_btn.say("", "LOOK: %s" % name.to_upper())
	var u := name.to_upper()
	tier = 1 if ("LOW" in u or u.begins_with("T1") or u.begins_with("L")) else (3 if ("HIGH" in u or u.begins_with("T3")) else 2)
	bg.set_tier(tier)
	logo.set_tier(tier)
	cards.tier = tier

func set_phone(on: bool) -> void:
	phone = on
	controls_btn.visible = on
	help = (HELP_BUTTONS if buttons_mode else HELP_PHONE) if on else HELP_PC
	dock.queue_redraw()

# p4.16: the phone controls in use (game_client.gd): CLASSIC (the stick jumps and dodges) or BUTTONS.
func set_controls(buttons: bool) -> void:
	buttons_mode = buttons
	controls_btn.say("", "CONTROLS: %s" % ("BUTTONS" if buttons else "CLASSIC"))
	if phone:
		help = HELP_BUTTONS if buttons else HELP_PHONE
	dock.queue_redraw()

# stuck_url: the game server's https address once the connection has failed for
# a while (game_client.gd STUCK_S), else "".
func update(m: Dictionary, my_seat: int, phase: int, left: int, status_in: String, connected: bool, version_bad: bool, stuck_url: String = "") -> void:
	seated = my_seat >= 0
	var list: Array = m.get("seats", [])
	var bots := int(m.get("bots", 0))
	var people := int(m.get("people", 0))
	bots_wanted = int(m.get("bots_wanted", bots_wanted))
	bots_now = bots
	var lvl: String = LEVEL_NAMES[clampi(int(m.get("bot_level", 2)), 0, 3)]
	cards.level_name = lvl
	cards.connected = connected
	cards.set_seats(list, my_seat, phase, bots, m.get("awards", []))
	var in_lobby := phase == P.PH_LOBBY
	var can_set := seated and in_lobby
	var pick := int(m.get("arena", P.ARENA_MIX))
	var now := int(m.get("arena_now", -1))
	arena_btn.say("ARENA" if pick != P.ARENA_MIX or now < 0 else "ARENA · NEXT: %s" % LevelScript.name_of(now),
		"MIX" if pick == P.ARENA_MIX else LevelScript.name_of(pick))
	arena_btn.disabled = not can_set
	if Polish.on("arena_cards") and (arena_btn.thumb == null or pick != arena_pick):
		arena_btn.thumb = Arenas.SHEET   # the pick's painting at the button's left
		arena_btn.thumb_src = Arenas.src(pick)
		arena_btn.queue_redraw()
	arena_pick = pick
	if not can_set and arenas.visible:
		arenas.close()
	power_btn.say("POWER-UPS", "ON" if int(m.get("power", 0)) != 0 else "OFF")
	power_btn.disabled = not can_set
	bots_minus.disabled = not can_set or bots_wanted <= 0
	bots_plus.disabled = not can_set or bots_wanted >= 7
	level_btn.say("BOT LEVEL", lvl)
	level_btn.disabled = not can_set
	name_edit.editable = not seated
	leave_btn.visible = seated
	name_edit.size.x = 580.0 if seated else 840.0
	leave_btn.disabled = not connected
	# the big button: what to do next
	main_glow = 0
	if version_bad:
		_main("RELOAD THE PAGE", 0, true)
	elif not connected:
		_main("CONNECTING", 3, true)
	elif not seated:
		var full := people >= 8
		_main("FULL" if full else "JOIN", 0 if full else 2, full)
		main_glow = 0 if full else 1
	elif phase == P.PH_COUNTDOWN:
		_main("GET READY", 0, true)
		main_glow = 2
	elif in_lobby or phase < 0:
		var ok := people + bots >= 2
		_main("START", 1, not ok)
		main_glow = 1 if ok else 0
	else:
		_main("MATCH ON", 0, true)
	# the status line
	var line := status_in
	if line == "":
		if version_bad:
			line = "Wrong version: reload the page."
		elif not connected:
			line = "Connecting to the server…"
		elif not seated:
			line = "Type your name and tap JOIN." if people < 8 else "All 8 seats are taken. JOIN when one frees up."
		elif phase == P.PH_COUNTDOWN:
			line = "Here we go."
		elif in_lobby:
			line = "Tap START when everyone is in." if people + bots >= 2 else "A match needs 2 fighters: add a bot or wait for a friend."
		else:
			line = "A match is on. You join at the next round."
	if line != status:
		status = line
		status_t = 0.0
	# a notice over the cards: the certificate step, or the wrong version
	var title := ""
	var body := ""
	if version_bad:
		title = "WRONG VERSION"
		body = status_in if status_in != "" else "This page is older or newer than the game server. Reload the page."
	elif not connected and stuck_url != "":
		title = "ONE MORE STEP"
		body = "Open %s in this browser once and accept the warning (an error page after that is fine), then come back here." % stuck_url
	notice.visible = title != ""
	if title != notice_title or notice_text.text != body:
		notice_title = title
		notice_text.text = body
		notice.queue_redraw()
	# the countdown (its end drops the parts away: someone who stays in the lobby,
	# a watcher with no seat, sees them rise in again)
	if last_phase == P.PH_COUNTDOWN and phase != P.PH_COUNTDOWN:
		intro = 0.0
	last_phase = phase
	cards.counting = phase == P.PH_COUNTDOWN
	count_secs = ceili(left / 60.0) if phase == P.PH_COUNTDOWN else 0
	count_left = left / 60.0 if phase == P.PH_COUNTDOWN else 9.0
	count_arena = LevelScript.name_of(now) if now >= 0 else ""

func _main(words: String, icon: int, off: bool) -> void:
	main_btn.say("", words)
	if main_btn.glyph != icon:
		main_btn.glyph = icon
		main_btn.queue_redraw()
	main_btn.disabled = off

func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	intro += delta / slow
	status_t += delta
	# the parts rise in when the lobby comes up, and drop away at the countdown's end
	var e := clampf((0.45 - count_left) / 0.45, 0.0, 1.0)
	cards.intro = intro
	cards.exit = e
	bg.fade = clampf(intro / 0.35, 0.0, 1.0)
	var lk := Art.ease_out_back(intro / 0.55)
	logo.scale = Vector2.ONE * (1.3 - 0.3 * lk)
	logo.position.y = sin(t * 1.6) * 5.0 - e * e * 320.0
	logo.modulate.a = clampf(intro / 0.3, 0.0, 1.0) * (1.0 - e)
	dock.position.y = (1.0 - Art.ease_out_back((intro - 0.15) / 0.5)) * 440.0 + e * e * 460.0
	corner.modulate.a = clampf((intro - 0.3) / 0.3, 0.0, 1.0) * (1.0 - e)
	var g := 0.0
	if main_glow == 1:
		g = 0.55 + 0.45 * sin(t * 4.5)
	elif main_glow == 2:
		g = 1.0
	main_btn.step(delta, g)
	main_btn.pivot_offset = main_btn.size * 0.5
	main_btn.scale = Vector2.ONE * (1.0 + (0.025 * sin(t * 4.5) if main_glow == 1 else 0.0))
	count.show_count(count_secs, count_arena, delta)
	dock.queue_redraw()

# The dock (behind its buttons): the status line, the bots box, the controls line.
func _paint_dock(c: Control) -> void:
	var txt: Color = pal["text"]
	var edge := Color(0.02, 0.01, 0.04)
	# the status line: a pill that pops when its words change (the countdown says it all)
	if count_secs <= 0:
		_status_pill(c, txt)
	# the bots box: BOTS, the number, then the - and + buttons (its own buttons)
	_bots_box(c, txt, edge)
	# the controls line
	_help_line(c, txt)

func _status_pill(c: Control, txt: Color) -> void:
	var fs := 32
	var tw := Art.BODY.get_string_size(status, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pw := minf(tw + 92.0, 1800.0)
	var pop := 1.0 + 0.08 * (1.0 - Art.ease_out(status_t / 0.3))
	var pc := Vector2(960, STATUS_Y + 26)
	c.draw_set_transform(pc, 0.0, Vector2.ONE * pop)
	Art.panel(c, Rect2(-pw * 0.5, -26, pw, 52), Color(pal["panel"], 0.9), Color(pal["panel_edge"], 0.8), 26, Color(0, 0, 0, 0.4), 8)
	var dot := 0.6 + 0.4 * sin(t * 5.0)
	c.draw_circle(Vector2(-pw * 0.5 + 30, 0), 8.0, Color(pal["accent"], dot))
	c.draw_string(Art.BODY, Vector2(-pw * 0.5 + 52, 11), status, HORIZONTAL_ALIGNMENT_LEFT, pw - 70.0, fs, txt)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _bots_box(c: Control, txt: Color, edge: Color) -> void:
	var bx := Rect2(972, SET_Y, 470, SET_H)
	var face: Color = pal["button"]
	c.draw_style_box(Art.box(face.darkened(0.35), face.darkened(0.7), 16, 3, 3, Color(0, 0, 0, 0.45), 10), bx)
	var on := seated
	var ix := 0.0                    # p4.17: the robot's room at the left (polish "ui_icons")
	if Polish.on("ui_icons"):
		c.draw_texture_rect_region(UI_ICONS, Rect2(bx.position.x + 12, bx.position.y + 16, 64, 64), Rect2(IC_BOTS * 128, 0, 128, 128),
			Color(1, 1, 1, 1.0 if on else 0.45))
		ix = 66.0
	c.draw_string(Art.BODY, Vector2(bx.position.x + 22 + ix, bx.position.y + 34), "BOTS", HORIZONTAL_ALIGNMENT_LEFT, -1, 26,
		Color(txt, 0.72 if on else 0.4))
	Art.text(c, Art.DISPLAY, Vector2(bx.position.x + 22 + ix, bx.position.y + 76), str(bots_now), 46, Color(txt, 1.0 if on else 0.45), 5, edge)
	c.draw_string(Art.BODY, Vector2(bx.position.x + 78 + ix, bx.position.y + 74), "· %s" % cards.level_name if bots_now > 0 else "NONE",
		HORIZONTAL_ALIGNMENT_LEFT, minf(170.0, 1244.0 - (bx.position.x + 78 + ix)), 26, Color(txt, 0.6 if on else 0.35))

# The controls line: key caps and words.
func _help_line(c: Control, txt: Color) -> void:
	var face: Color = pal["button"]
	var hs := 26
	var total := 0.0
	for seg in help:
		total += _seg_w(seg, hs)
	var x0 := 960.0 - total * 0.5
	var dim: Color = pal["dim"]
	# first every key cap and dot (plain rects), then every word: two draws in all
	var x := x0
	for seg in help:
		if seg[0] == "k":
			Art.keycap(c, x, HELP_Y, seg[1], hs, face.darkened(0.25))
		elif seg[0] == "-":
			c.draw_rect(Rect2(x + 14, HELP_Y - hs * 0.36 - 4, 8, 8), Color(dim, 0.6))
		x += _seg_w(seg, hs)
	x = x0
	for seg in help:
		if seg[0] == "k":
			Art.keycap_words(c, x, HELP_Y, seg[1], hs, txt)
		elif seg[0] == "t":
			c.draw_string(Art.BODY, Vector2(x, HELP_Y), seg[1], HORIZONTAL_ALIGNMENT_LEFT, -1, hs, dim)
		x += _seg_w(seg, hs)

func _seg_w(seg: Array, hs: int) -> float:
	if seg[0] == "-":
		return 36.0
	if seg[0] == "k":
		return Art.BODY.get_string_size(seg[1], HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x + hs * 0.9 + 10.0
	return Art.BODY.get_string_size(seg[1], HORIZONTAL_ALIGNMENT_LEFT, -1, hs).x + 10.0

# The notice over the cards (the certificate step, the wrong version).
func _paint_notice(c: Control) -> void:
	var r := Rect2(360, 280, 1200, 320)
	var accent: Color = pal["accent"]
	Art.panel(c, r, Color(pal["panel"], 0.97), accent, 22, Color(accent.r, accent.g, accent.b, 0.35), 24)
	Art.text(c, Art.DISPLAY, Vector2(r.position.x, r.position.y + 84), notice_title, 58, pal["accent_hi"], 8, Color(0.02, 0.01, 0.04),
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x)

# The top corners: the version on the left (the LOOK button sits on the right).
func _paint_corner(c: Control) -> void:
	c.draw_string(Art.BODY, Vector2(60, 60), P.VERSION, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(pal["faint"], 0.9))

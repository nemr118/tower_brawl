# The lobby: your name, JOIN or LEAVE, the 8 seats, the arena (G5: MIX or one
# of them, for everyone), the look (LOW, NORMAL or HIGH: P2's quality setting,
# kept on the device), the bots and their level (G6: EASY, NORMAL, HARD, for
# everyone), START and the countdown, and a status line. Built from Controls on a 1920 x 1080 design,
# scaled to the window's height and centred. Shown when you have no seat and
# between matches; the arena shows through behind it.
extends CanvasLayer

signal join_pressed(name: String)
signal leave_pressed
signal start_pressed
signal bots_changed(n: int)
signal look_pressed
signal arena_pressed
signal bot_level_pressed
signal power_pressed

const P = preload("res://sim/proto.gd")
const World = preload("res://client/world.gd")
const LevelScript = preload("res://sim/level.gd")
const LEVEL_NAMES := ["OLD", "EASY", "NORMAL", "HARD"]   # sim/brain.gd NAMES
const HELP_PC := "PC: A D run · W or space jumps · S down, S + jump drops through a ledge · shift dodges the way you hold · hold the mouse button to aim, let go to fire"
const HELP_PHONE := "Phone: left stick runs, push it up to jump, down + past the rim to drop · right thumb: pull back past the ring and let go to fire (the arrow flies the other way) · DODGE button, or flick the left stick past its rim"

var root := Control.new()
var title := Label.new()
var name_edit := LineEdit.new()
var join_btn := Button.new()
var rows: Array = []
var bots_label := Label.new()
var bots_minus := Button.new()
var bots_plus := Button.new()
var bot_level_btn := Button.new()
var start_btn := Button.new()
var look_btn := Button.new()
var arena_btn := Button.new()
var power_btn := Button.new()     # p4.9: POWER-UPS on or off (p4.5's POWER ARROWS before)
var status_label := Label.new()
var help := Label.new()
var awards_panel := _Awards.new()   # p4.11: the last match's awards, right of the lobby
var seated := false
var bots_wanted := 7
var phone := false

func _init() -> void:
	layer = 20
	root.size = Vector2(1920, 1080)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.03, 0.05, 0.84)
	bg.position = Vector2(410, 40)
	bg.size = Vector2(1100, 1000)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	_label(title, "TOWER BRAWL", Vector2(410, 56), Vector2(1100, 90), 72, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_CENTER)
	var sub := Label.new()
	_label(sub, "the new game · %s" % P.VERSION, Vector2(410, 136), Vector2(1100, 40), 24, Color(0.7, 0.7, 0.75), HORIZONTAL_ALIGNMENT_CENTER)
	var name_lab := Label.new()
	_label(name_lab, "YOUR NAME", Vector2(470, 186), Vector2(400, 36), 24, Color(0.8, 0.8, 0.85), HORIZONTAL_ALIGNMENT_LEFT)
	name_edit.position = Vector2(470, 224)
	name_edit.size = Vector2(520, 72)
	name_edit.max_length = 12
	name_edit.placeholder_text = "type a name"
	name_edit.add_theme_font_size_override("font_size", 36)
	name_edit.text_submitted.connect(func(_t): if not seated: _on_join_btn())
	root.add_child(name_edit)
	_button(join_btn, "JOIN", Vector2(1020, 224), Vector2(420, 72), 36)
	join_btn.pressed.connect(_on_join_btn)
	for i in 8:
		var y := 322.0 + i * 52.0
		var swatch := ColorRect.new()
		swatch.color = World.TEAM[i]
		swatch.position = Vector2(470, y + 6)
		swatch.size = Vector2(40, 40)
		swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(swatch)
		var lab := Label.new()
		_label(lab, "", Vector2(530, y), Vector2(910, 52), 32, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
		rows.append([swatch, lab])
	_button(arena_btn, "ARENA: MIX", Vector2(470, 742), Vector2(330, 64), 24)
	arena_btn.pressed.connect(func(): arena_pressed.emit())
	_button(power_btn, "POWER-UPS: ON", Vector2(810, 742), Vector2(200, 64), 22)
	power_btn.pressed.connect(func(): power_pressed.emit())
	_label(bots_label, "BOTS: 7", Vector2(470, 818), Vector2(220, 70), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_LEFT)
	_button(bots_minus, "-", Vector2(690, 818), Vector2(70, 70), 40)
	_button(bots_plus, "+", Vector2(770, 818), Vector2(70, 70), 40)
	bots_minus.pressed.connect(func(): bots_changed.emit(bots_wanted - 1))
	bots_plus.pressed.connect(func(): bots_changed.emit(bots_wanted + 1))
	_button(bot_level_btn, "NORMAL", Vector2(850, 818), Vector2(160, 70), 28)
	bot_level_btn.pressed.connect(func(): bot_level_pressed.emit())
	_button(look_btn, "LOOK", Vector2(1020, 742), Vector2(420, 64), 28)
	look_btn.pressed.connect(func(): look_pressed.emit())
	_button(start_btn, "START", Vector2(1020, 812), Vector2(420, 84), 44)
	start_btn.pressed.connect(func(): start_pressed.emit())
	_label(status_label, "", Vector2(470, 904), Vector2(980, 64), 28, Color(1, 0.9, 0.6), HORIZONTAL_ALIGNMENT_LEFT)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_label(help, HELP_PC, Vector2(470, 968), Vector2(980, 64), 19, Color(0.6, 0.6, 0.66), HORIZONTAL_ALIGNMENT_LEFT)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	awards_panel.position = Vector2(1524, 40)
	awards_panel.size = Vector2(380, 1000)
	awards_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(awards_panel)

# p4.11: the last match's awards, on a card right of the lobby (the seats message
# carries them until the next match starts).
class _Awards extends Control:
	var list: Array = []
	func _draw() -> void:
		if list.is_empty():
			return
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.05, 0.84))
		draw_string(font, Vector2(16, 44), "LAST MATCH AWARDS", HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 24, Color(1.0, 0.82, 0.3))
		var y := 92.0
		for aw in list.slice(0, 12):
			var seat := int(aw.get("seat", 0))
			draw_string(font, Vector2(16, y), str(aw.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 24, Color(1.0, 0.88, 0.45))
			draw_string(font, Vector2(16, y + 26), "%s · %s" % [aw.get("name", ""), aw.get("why", "")], HORIZONTAL_ALIGNMENT_LEFT, size.x - 32, 17,
				World.TEAM[seat % 8].lightened(0.35))
			y += 66.0

func _label(l: Label, text: String, pos: Vector2, size: Vector2, font_size: int, col: Color, align: int) -> void:
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)

func _button(b: Button, text: String, pos: Vector2, size: Vector2, font_size: int) -> void:
	b.text = text
	b.position = pos
	b.size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	root.add_child(b)

func fit(win: Vector2) -> void:
	var k := win.y / 1080.0
	scale = Vector2.ONE * k
	offset = Vector2((win.x - 1920.0 * k) * 0.5, 0.0)

func set_name_text(n: String) -> void:
	name_edit.text = n

# The look's name on its button: LOW, NORMAL, HIGH (or a test look's name).
func set_look(name: String) -> void:
	look_btn.text = "LOOK: %s" % name.to_upper()

func set_phone(on: bool) -> void:
	phone = on
	help.text = HELP_PHONE if on else HELP_PC

func _on_join_btn() -> void:
	if seated:
		leave_pressed.emit()
	else:
		join_pressed.emit(name_edit.text)

# stuck_url: the game server's https address once the connection has failed for
# a while (game_client.gd STUCK_S), else "".
func update(m: Dictionary, my_seat: int, phase: int, left: int, status: String, connected: bool, version_bad: bool, stuck_url: String = "") -> void:
	seated = my_seat >= 0
	var aw: Array = m.get("awards", [])
	if aw != awards_panel.list:
		awards_panel.list = aw
		awards_panel.queue_redraw()
	join_btn.text = "LEAVE" if seated else "JOIN"
	join_btn.disabled = not connected or version_bad
	name_edit.editable = not seated
	var list: Array = m.get("seats", [])
	var bots := int(m.get("bots", 0))
	var people := int(m.get("people", 0))
	bots_wanted = int(m.get("bots_wanted", bots_wanted))
	var free_seen := 0
	for i in 8:
		var swatch: ColorRect = rows[i][0]
		var lab: Label = rows[i][1]
		var st: Dictionary = list[i] if i < list.size() else {}
		var kind := int(st.get("kind", 0))
		var text := ""
		var col := Color.WHITE
		if kind == 1:
			text = str(st.get("name", ""))
			var pts := int(st.get("points", 0))
			if pts > 0:
				text += "   %d pt%s" % [pts, "" if pts == 1 else "s"]
			var crowns := int(st.get("crowns", 0))
			if crowns > 0:
				text += "   %d crown%s" % [crowns, "" if crowns == 1 else "s"]
			if not bool(st.get("on", true)):
				text += "   (away)"
			if i == my_seat:
				text += "   (you)"
				col = Color(1, 0.95, 0.7)
			elif phase > P.PH_COUNTDOWN and not bool(st.get("in", false)):
				text += "   (next round)"
		elif kind == 2:
			text = "BOT"
			col = Color(0.75, 0.75, 0.8)
		else:
			if free_seen < bots and phase <= P.PH_COUNTDOWN:
				text = "BOT (fills this seat)"
				col = Color(0.6, 0.6, 0.66)
			else:
				text = "empty"
				col = Color(0.4, 0.4, 0.45)
			free_seen += 1
		lab.text = text
		lab.add_theme_color_override("font_color", col)
		swatch.color = World.TEAM[i] if kind != 0 else World.TEAM[i].darkened(0.6)
	bots_label.text = "BOTS: %d" % bots
	var in_lobby := phase == P.PH_LOBBY
	bots_minus.disabled = not seated or not in_lobby or bots_wanted <= 0
	bots_plus.disabled = not seated or not in_lobby or bots_wanted >= 7
	bot_level_btn.text = LEVEL_NAMES[clampi(int(m.get("bot_level", 2)), 0, 3)]
	bot_level_btn.disabled = not seated or not in_lobby
	var pick := int(m.get("arena", P.ARENA_MIX))
	arena_btn.text = "ARENA: %s" % ("MIX" if pick == P.ARENA_MIX else LevelScript.name_of(pick))
	arena_btn.add_theme_font_size_override("font_size", 18 if arena_btn.text.length() > 18 else 24)   # p4.9: THE HAUNTED HOUSE fits
	arena_btn.disabled = not seated or not in_lobby
	power_btn.text = "POWER-UPS: %s" % ("ON" if int(m.get("power", 0)) != 0 else "OFF")
	power_btn.disabled = not seated or not in_lobby
	if phase == P.PH_COUNTDOWN:
		start_btn.text = "STARTING IN %d" % ceili(left / 60.0)
		start_btn.disabled = true
	elif in_lobby or phase < 0:
		start_btn.text = "START"
		start_btn.disabled = not seated or people + bots < 2 or not connected
	else:
		start_btn.text = "MATCH ON"
		start_btn.disabled = true
	var line := status
	if line == "":
		if version_bad:
			line = "Wrong version: reload the page."
		elif not connected and stuck_url != "":
			line = "Still connecting. Open %s in this browser once and accept the warning (an error page after that is fine), then come back here." % stuck_url
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
	status_label.text = line
	# the certificate hint takes two or three lines: it gets the help line's room
	help.visible = stuck_url == ""
	status_label.size.y = 64.0 if help.visible else 128.0

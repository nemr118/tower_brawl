# p4.19 SETTINGS (the user: "It should look app store quality with the UI, menus"). The
# lobby had a button in every corner (LOOK, CONTROLS, SEASON), each one stepping through
# its choices blind. Now one SETTINGS button opens this panel: every choice is a button
# you can see, and the one in use is lit.
# THIS DEVICE: LOOK (how fancy the picture is), CONTROLS (phones), SOUND.
# EVERYONE: SEASON (the server's: only someone with a seat, in the lobby, can change it).
# The lobby (lobby.gd) tells it what is picked; a tap on a choice sends a signal and the
# lobby does the work. DONE, or a tap outside the panel, closes it.
# Drawn on the lobby's 1920 x 1080 frame.
# p4.21 (polish "motion"): the panel grows in and shrinks away (client/motion.gd); its
# rows slide in one after another; the choice you pick jumps.
extends Control

signal look_picked(pick: String)
signal controls_picked(buttons: bool)
signal sound_picked(on: bool)
signal music_picked(on: bool)        # p4.20
signal leave_pressed                 # p4.20: the match's menu: LEAVE THE MATCH
signal season_picked(pick: String)
signal mode_picked(pick: String)     # TEAMS: the MODE row, "ffa" or "teams"

const Art = preload("res://client/lobby_art.gd")
const Motion = preload("res://client/motion.gd")
const CARD := Rect2(330, 70, 1260, 940)    # tall enough for four rows and DONE (a phone has CONTROLS too)
const ROW_H := 116.0
const SEG_X := 760.0              # where a row's choices start
const SEG_W := 780.0

var pal: Dictionary = Art.DRESSES["castle"]
var t := 0.0
# a row: its key, its words, its choices ([value, words]), the value in use, its buttons
var rows: Array = []
var done = Art.Btn.new()
var leave = Art.Btn.new()         # p4.20: only in a match's menu
var in_match := false             # p4.20: this panel is the match's MENU (no SEASON row; a LEAVE button; the match goes on)
var phone := false
var season_ok := false            # may this player change the season now?
var pane: Motion.Pane             # p4.21: its coming and going
var done_y := 0.0                 # where DONE rests (it rises in last)

func _init() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_row("look", "LOOK", "How fancy the picture is.", [["auto", "AUTO"], ["low", "LOW"], ["normal", "NORMAL"], ["high", "HIGH"]])
	_row("controls", "CONTROLS", "How you jump and dodge.", [["classic", "CLASSIC"], ["buttons", "BUTTONS"]])
	_row("sound", "SOUND", "Silly sounds, on this device.", [["off", "OFF"], ["on", "ON"]])
	_row("music", "MUSIC", "Songs, on this device.", [["off", "OFF"], ["on", "ON"]])   # p4.20
	_row("season", "SEASON", "The game's holiday.", [["auto", "AUTO"], ["off", "OFF"], ["halloween", "HALLOWEEN"], ["harvest", "HARVEST"]])
	_row("mode", "MODE", "Everyone alone, or two teams.", [["ffa", "FREE FOR ALL"], ["teams", "TEAMS"]])   # TEAMS: for everyone, like SEASON
	add_child(done)
	done.pressed.connect(close)
	add_child(leave)
	leave.visible = false
	leave.pressed.connect(func():
		close()
		leave_pressed.emit())
	pane = Motion.Pane.new(self, CARD.get_center(), 0.88)
	_layout()

func _row(key: String, label: String, hint: String, choices: Array) -> void:
	var row := {"key": key, "label": label, "hint": hint, "choices": choices, "value": "", "btns": [], "shown": key != "sound" and key != "music", "note": ""}
	for ch in choices:
		var b = Art.Btn.new()
		add_child(b)
		var v := str(ch[0])
		b.pressed.connect(func(): _picked(key, v))
		row["btns"].append(b)
	rows.append(row)

func _picked(key: String, v: String) -> void:
	match key:
		"look":
			look_picked.emit(v)
		"controls":
			controls_picked.emit(v == "buttons")
		"sound":
			sound_picked.emit(v == "on")
		"music":
			music_picked.emit(v == "on")
		"season":
			season_picked.emit(v)
		"mode":
			mode_picked.emit(v)

func _row_of(key: String) -> Dictionary:
	for r in rows:
		if r["key"] == key:
			return r
	return {}

# The rows that show, top to bottom, and each one's buttons in their places and colours.
func _layout() -> void:
	var y := CARD.position.y + 196.0
	var shown_n := 0
	for r in rows:
		if r["key"] == "season" or r["key"] == "mode":
			r["shown"] = not in_match      # the season and the mode are the lobby's to change
		if r["shown"]:
			shown_n += 1
	# more rows sit closer together: 5 (a PC: LOOK, SOUND, MUSIC, SEASON, MODE) and 6 (a phone has CONTROLS too)
	var row_h := ROW_H if shown_n <= 4 else (102.0 if shown_n == 5 else 90.0)
	var btn_h := 92.0 if shown_n <= 4 else (84.0 if shown_n == 5 else 74.0)
	for r in rows:
		var btns: Array = r["btns"]
		var live: Array = []
		for i in btns.size():
			var on: bool = r["shown"] and not (r["key"] == "look" and r.get("no_high", false) and str(r["choices"][i][0]) == "high")
			btns[i].visible = on
			if on:
				live.append(i)
		if not r["shown"]:
			continue
		if r["key"] == "season":
			y += 58.0 if shown_n <= 5 else 54.0     # room for the EVERYONE heading
		r["y"] = y
		var n := live.size()
		var w := (SEG_W - (n - 1) * 12.0) / n
		for k in n:
			var b = btns[live[k]]
			var picked: bool = str(r["choices"][live[k]][0]) == r["value"]
			if picked:
				b.setup(pal["accent"], Color(0.13, 0.05, 0.0), 38)
				if visible and r.has("lit") and str(r["lit"]) != str(r["value"]):
					b.pop()            # p4.21: the choice that was just picked jumps
			else:
				b.setup(Color(pal["button"]).darkened(0.25), Color(pal["text"], 0.9), 38)
			b.say("", str(r["choices"][live[k]][1]))
			b.position = Vector2(SEG_X + k * (w + 12.0), y)
			b.set_meta("x0", b.position.x)
			b.size = Vector2(w, btn_h)
			b.disabled = (r["key"] == "season" or r["key"] == "mode") and not season_ok and not picked   # (MODE: as SEASON, a seat in the lobby)
		r["lit"] = r["value"]
		y += row_h
	done.setup(pal["accent"], Color(0.13, 0.05, 0.0), 52 if not in_match else 44)
	done.say("", "DONE" if not in_match else "BACK TO THE GAME")
	done.position = Vector2(760, CARD.end.y - 124.0) if not in_match else Vector2(980, CARD.end.y - 124.0)
	done.size = Vector2(400, 100) if not in_match else Vector2(540, 100)
	leave.visible = in_match
	if in_match:
		leave.setup(pal["danger"], Color(pal["text"]), 40)
		leave.say("", "LEAVE THE MATCH")
		leave.position = Vector2(400, CARD.end.y - 124.0)
		leave.size = Vector2(520, 100)
	done_y = done.position.y
	_place()
	queue_redraw()

# p4.21: how far in row i is (0..1, a little past 1 on the way): each row starts a moment after the one above it.
func _row_k(i: int) -> float:
	return Motion.rise(pane.t, 0.04 + 0.045 * i, 0.3) if pane != null else 1.0

# The rows' buttons slide in from the right with their rows; DONE rises in last.
func _place() -> void:
	if pane == null:
		return
	var i := 0
	for r in rows:
		if not r["shown"]:
			continue
		var k := _row_k(i)
		r["k"] = k
		for b in r["btns"]:
			if b.visible and b.has_meta("x0"):
				b.position.x = float(b.get_meta("x0")) + (1.0 - k) * 46.0     # (a short way: it stays inside the card)
				b.modulate.a = clampf(k * 1.5, 0.0, 1.0)
		i += 1
	var dk := Motion.rise(pane.t, 0.1 + 0.045 * i, 0.32)
	for b in [done, leave]:
		b.position.y = done_y + (1.0 - dk) * 70.0
		b.modulate.a = clampf(dk * 1.5, 0.0, 1.0)

func set_dress(p: Dictionary) -> void:
	pal = p
	_layout()

# What is picked now (the lobby calls these whenever something changes).
func set_look(pick: String, now_label: String, no_high: bool) -> void:
	var r := _row_of("look")
	r["value"] = pick
	r["no_high"] = no_high
	r["note"] = ("AUTO picked %s." % now_label) if pick == "auto" else ""
	_layout()

func set_controls(buttons: bool, is_phone: bool) -> void:
	var r := _row_of("controls")
	r["value"] = "buttons" if buttons else "classic"
	r["shown"] = is_phone
	phone = is_phone
	_layout()

# shown false: this build has no sound (the row hides).
func set_sound(on: bool, shown: bool) -> void:
	var r := _row_of("sound")
	r["value"] = "on" if on else "off"
	r["shown"] = shown
	_layout()

func set_music(on: bool, shown: bool) -> void:
	var r := _row_of("music")
	r["value"] = "on" if on else "off"
	r["shown"] = shown
	_layout()

func set_season(pick: String, now_label: String, can_set: bool) -> void:
	var r := _row_of("season")
	if r["value"] == pick and season_ok == can_set and r["note"] == now_label:
		return
	r["value"] = pick
	r["note"] = now_label
	season_ok = can_set
	_layout()

# TEAMS: the MODE in use ("ffa" or "teams"). Who may change it: whoever may change the SEASON (set_season's can_set).
func set_mode(pick: String) -> void:
	var r := _row_of("mode")
	if r["value"] != pick:
		r["value"] = pick
		_layout()

func open() -> void:
	t = 0.0
	pane.open()
	_place()
	queue_redraw()

func close() -> void:
	pane.close()

func _process(delta: float) -> void:
	if not visible:
		return
	var moving := pane.step(delta)
	if moving or t < 0.3:
		t += delta
		_place()
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not e.pressed and t > 0.25 and not pane.closing() and not CARD.has_point(e.position):   # a tap outside the panel
			close()

func _draw() -> void:
	var a := roundf(clampf(t / 0.15, 0.0, 1.0) * 8.0) / 8.0   # the fade in steps: lobby_art.gd keeps every box it makes
	if pane.live:
		a = 1.0                    # (p4.21: the whole panel fades by itself)
	draw_rect(Rect2(-2000, -1000, 5920, 3080), Color(0.02, 0.01, 0.04, 0.86 * a))   # (wider than the frame: a long phone's sides too)
	var accent: Color = pal["accent"]
	Art.panel(self, CARD, Color(pal["panel"], 0.985), accent, 30, Color(accent.r, accent.g, accent.b, 0.3), 28)
	if in_match:
		draw_string(Art.BODY, Vector2(CARD.position.x, CARD.end.y - 150.0), "The match goes on while this is open.", HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x, 26,
			Color(pal["dim"], 0.95))
	Art.text(self, Art.DISPLAY, Vector2(CARD.position.x, CARD.position.y + 90.0), "SETTINGS" if not in_match else "MENU", 72, pal["accent_hi"], 8, Color(0.03, 0.01, 0.05),
		HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x)
	var dim: Color = pal["dim"]
	var txt: Color = pal["text"]
	var x := CARD.position.x + 60.0
	_heading(x, CARD.position.y + 158.0, "THIS DEVICE")
	for r in rows:
		if not r["shown"]:
			continue
		var y: float = r["y"]
		if r["key"] == "season":
			_heading(x, y - 20.0, "EVERYONE")
		var rk := float(r.get("k", 1.0))        # p4.21: the row's words slide in from the left as its buttons come from the right
		var ra := clampf(rk * 1.5, 0.0, 1.0)
		var rx := x - (1.0 - rk) * 44.0
		Art.text(self, Art.DISPLAY, Vector2(rx, y + 44.0), r["label"], 44, Color(txt, ra), 5, Color(0.03, 0.01, 0.05))
		var hint: String = r["hint"]
		if r["key"] == "look" and r["note"] != "":
			hint = r["note"]
		elif r["key"] == "season":
			hint = "Now: %s." % r["note"] if season_ok else "Take a seat to change it."
		elif r["key"] == "mode" and not season_ok:
			hint = "Take a seat to change it."
		draw_string(Art.BODY, Vector2(rx, y + 80.0), hint, HORIZONTAL_ALIGNMENT_LEFT, SEG_X - x - 24.0, 22, Color(dim, 0.95 * ra))

func _heading(x: float, y: float, words: String) -> void:
	draw_string(Art.BODY, Vector2(x, y), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(pal["accent_hi"], 0.9))
	var w := Art.BODY.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_rect(Rect2(x + w + 16.0, y - 10.0, CARD.end.x - 60.0 - (x + w + 16.0), 2), Color(pal["panel_edge"], 0.6))

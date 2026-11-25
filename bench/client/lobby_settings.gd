# p4.19 SETTINGS (the user: "It should look app store quality with the UI, menus"). The
# lobby had a button in every corner (LOOK, CONTROLS, SEASON), each one stepping through
# its choices blind. Now one SETTINGS button opens this panel: every choice is a button
# you can see, and the one in use is lit.
# THIS DEVICE: LOOK (how fancy the picture is), CONTROLS (phones), SOUND.
# EVERYONE: SEASON (the server's: only someone with a seat, in the lobby, can change it).
# The lobby (lobby.gd) tells it what is picked; a tap on a choice sends a signal and the
# lobby does the work. DONE, or a tap outside the panel, closes it.
# Drawn on the lobby's 1920 x 1080 frame.
extends Control

signal look_picked(pick: String)
signal controls_picked(buttons: bool)
signal sound_picked(on: bool)
signal season_picked(pick: String)

const Art = preload("res://client/lobby_art.gd")
const CARD := Rect2(330, 70, 1260, 940)    # tall enough for four rows and DONE (a phone has CONTROLS too)
const ROW_H := 116.0
const SEG_X := 760.0              # where a row's choices start
const SEG_W := 780.0

var pal: Dictionary = Art.DRESSES["castle"]
var t := 0.0
# a row: its key, its words, its choices ([value, words]), the value in use, its buttons
var rows: Array = []
var done = Art.Btn.new()
var phone := false
var season_ok := false            # may this player change the season now?

func _init() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_row("look", "LOOK", "How fancy the picture is.", [["auto", "AUTO"], ["low", "LOW"], ["normal", "NORMAL"], ["high", "HIGH"]])
	_row("controls", "CONTROLS", "How you jump and dodge.", [["classic", "CLASSIC"], ["buttons", "BUTTONS"]])
	_row("sound", "SOUND", "Silly sounds, on this device.", [["off", "OFF"], ["on", "ON"]])
	_row("season", "SEASON", "The game's holiday.", [["auto", "AUTO"], ["off", "OFF"], ["halloween", "HALLOWEEN"], ["harvest", "HARVEST"]])
	add_child(done)
	done.pressed.connect(close)
	_layout()

func _row(key: String, label: String, hint: String, choices: Array) -> void:
	var row := {"key": key, "label": label, "hint": hint, "choices": choices, "value": "", "btns": [], "shown": key != "sound", "note": ""}
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
		"season":
			season_picked.emit(v)

func _row_of(key: String) -> Dictionary:
	for r in rows:
		if r["key"] == key:
			return r
	return {}

# The rows that show, top to bottom, and each one's buttons in their places and colours.
func _layout() -> void:
	var y := CARD.position.y + 196.0
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
			y += 58.0             # room for the EVERYONE heading
		r["y"] = y
		var n := live.size()
		var w := (SEG_W - (n - 1) * 12.0) / n
		for k in n:
			var b = btns[live[k]]
			var picked: bool = str(r["choices"][live[k]][0]) == r["value"]
			if picked:
				b.setup(pal["accent"], Color(0.13, 0.05, 0.0), 38)
			else:
				b.setup(Color(pal["button"]).darkened(0.25), Color(pal["text"], 0.9), 38)
			b.say("", str(r["choices"][live[k]][1]))
			b.position = Vector2(SEG_X + k * (w + 12.0), y)
			b.size = Vector2(w, 92.0)
			b.disabled = r["key"] == "season" and not season_ok and not picked
		y += ROW_H
	done.setup(pal["accent"], Color(0.13, 0.05, 0.0), 52)
	done.say("", "DONE")
	done.position = Vector2(760, CARD.end.y - 124.0)
	done.size = Vector2(400, 100)
	queue_redraw()

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

func set_season(pick: String, now_label: String, can_set: bool) -> void:
	var r := _row_of("season")
	if r["value"] == pick and season_ok == can_set and r["note"] == now_label:
		return
	r["value"] = pick
	r["note"] = now_label
	season_ok = can_set
	_layout()

func open() -> void:
	t = 0.0
	visible = true
	queue_redraw()

func close() -> void:
	visible = false

func _process(delta: float) -> void:
	if visible and t < 0.3:
		t += delta
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not e.pressed and t > 0.25 and not CARD.has_point(e.position):   # a tap outside the panel
			close()

func _draw() -> void:
	var a := roundf(clampf(t / 0.15, 0.0, 1.0) * 8.0) / 8.0   # the fade in steps: lobby_art.gd keeps every box it makes
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.01, 0.04, 0.86 * a))
	var accent: Color = pal["accent"]
	Art.panel(self, CARD, Color(pal["panel"], 0.985), accent, 30, Color(accent.r, accent.g, accent.b, 0.3), 28)
	Art.text(self, Art.DISPLAY, Vector2(CARD.position.x, CARD.position.y + 90.0), "SETTINGS", 72, pal["accent_hi"], 8, Color(0.03, 0.01, 0.05),
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
			_heading(x, y - 28.0, "EVERYONE")
		Art.text(self, Art.DISPLAY, Vector2(x, y + 44.0), r["label"], 44, txt, 5, Color(0.03, 0.01, 0.05))
		var hint: String = r["hint"]
		if r["key"] == "look" and r["note"] != "":
			hint = r["note"]
		elif r["key"] == "season":
			hint = "Now: %s." % r["note"] if season_ok else "Take a seat to change it."
		draw_string(Art.BODY, Vector2(x, y + 80.0), hint, HORIZONTAL_ALIGNMENT_LEFT, SEG_X - x - 24.0, 22, Color(dim, 0.95))

func _heading(x: float, y: float, words: String) -> void:
	draw_string(Art.BODY, Vector2(x, y), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(pal["accent_hi"], 0.9))
	var w := Art.BODY.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
	draw_rect(Rect2(x + w + 16.0, y - 10.0, CARD.end.x - 60.0 - (x + w + 16.0), 2), Color(pal["panel_edge"], 0.6))

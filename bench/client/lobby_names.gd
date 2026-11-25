# p4.18 WHO ARE YOU? (the October logs: half the players never typed a name and played as
# "Player 3"). When JOIN is tapped with the name box empty, this picker shows the names
# the server has seen on other nights as big buttons, and SOMEONE NEW (the name box and
# the keyboard). A name that sits at the table right now is greyed out. A tap on a name
# joins with it (game_client.gd keeps it on the device); a tap anywhere else closes it.
# Drawn on the lobby's 1920 x 1080 frame.
# p4.21 (polish "motion"): it fades in; the names pop in one after another; the name
# under the finger squeezes.
extends Control

signal picked(name: String)
signal someone_new

const Art = preload("res://client/lobby_art.gd")
const Motion = preload("res://client/motion.gd")
const GOLD := Color(1.0, 0.82, 0.25)
const COLS := 4
const BTN := Vector2(400, 124)
const GAP := 28.0

var names: Array = []             # up to 12, the most played first
var taken: Array = []             # the names seated now
var t := 0.0
var pal: Dictionary = Art.DRESSES["castle"]   # p4.19: the lobby's dress (lobby.gd sets it)
var _press := -3                  # the button a press went down on (-1 SOMEONE NEW, -2 none, -3 no press)
var pane: Motion.Pane

func _init() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	pane = Motion.Pane.new(self, Vector2(960, 540), 0.95)

func open(list: Array, seated: Array) -> void:
	names = list.slice(0, 12)
	taken = seated
	t = 0.0
	_press = -3
	pane.open()
	queue_redraw()

func close() -> void:
	pane.close()

func _rect(i: int) -> Rect2:
	var rows := ceili(names.size() / float(COLS))
	var in_row := mini(COLS, names.size() - (i / COLS) * COLS)
	var row_w := in_row * BTN.x + (in_row - 1) * GAP
	var y0 := 250.0 + (3 - rows) * (BTN.y + GAP) * 0.5
	return Rect2(Vector2((1920.0 - row_w) * 0.5 + (i % COLS) * (BTN.x + GAP), y0 + (i / COLS) * (BTN.y + GAP)), BTN)

func _new_rect() -> Rect2:
	return Rect2(660, 800, 600, 120)

func _process(delta: float) -> void:
	if visible:
		t += delta
		pane.step(delta)
		queue_redraw()

# p4.21: a button's own size, about its middle (it pops in; it squeezes under the finger).
func _size_at(c: Vector2, k: float) -> void:
	draw_set_transform(c * (1.0 - k), 0.0, Vector2.ONE * k)

func _hit(p: Vector2) -> int:
	for i in names.size():
		if _rect(i).grow(8.0).has_point(p) and not taken.has(names[i]):
			return i
	return -1 if _new_rect().grow(8.0).has_point(p) else -2

func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if pane.closing():
		return
	var hit := _hit(e.position)
	if e.pressed:
		_press = hit
	elif _press != -3 and t > 0.3:
		if hit == _press and hit >= 0:
			picked.emit(str(names[hit]))
		elif hit == _press and hit == -1:
			someone_new.emit()
		close()
		_press = -3

func _text(at: Vector2, s: String, fs: int, col: Color) -> void:
	var p := at - Vector2(Art.DISPLAY.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 0.0)
	draw_string_outline(Art.DISPLAY, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, col.a * 0.9))
	draw_string(Art.DISPLAY, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw() -> void:
	var a := roundf(clampf(t / 0.15, 0.0, 1.0) * 8.0) / 8.0   # the fade in steps: lobby_art.gd keeps every box it makes
	if pane.live:
		a = 1.0                    # (p4.21: the whole picker fades by itself)
	draw_rect(Rect2(-2000, -1000, 5920, 3080), Color(0.02, 0.01, 0.05, 0.92 * a))   # (wider than the frame: it grows in)
	_size_at(Vector2(960, 150), 0.7 + 0.3 * Motion.rise(t, 0.0, 0.3))
	_text(Vector2(960, 170), "WHO ARE YOU?", 80, Color(GOLD, a))
	for i in names.size():
		var r := _rect(i)
		var off: bool = taken.has(names[i])
		var bk := Motion.rise(t, 0.05 + 0.03 * i, 0.3) * (0.95 if _press == i and not off and pane.live else 1.0)
		if bk <= 0.02:
			continue
		_size_at(r.get_center(), bk)
		var face: Color = Color(pal["button"]).lightened(0.06) if not off else Color(0.16, 0.16, 0.2)
		if _press == i and not off:
			face = face.lightened(0.18)       # p4.19: the button under the finger lights up
		draw_style_box(Art.box(Color(face, a), Color(face.darkened(0.6), a), 18, 3, 10, Color(0, 0, 0, 0.5 * a), 12), r)
		var fs := Art.fit_size(Art.DISPLAY, str(names[i]), 62, BTN.x - 40.0, 30)
		_text(r.get_center() + Vector2(0, fs * 0.34 - 4.0), str(names[i]), fs, Color(1, 1, 1, a) if not off else Color(0.6, 0.6, 0.66, a))
		if off:
			_text(Vector2(r.get_center().x, r.end.y - 14.0), "playing now", 22, Color(0.7, 0.7, 0.76, a))
	var nr := _new_rect()
	var nface: Color = pal["accent"]
	_size_at(nr.get_center(), maxf(0.02, Motion.rise(t, 0.12 + 0.03 * names.size(), 0.32)) * (0.95 if _press == -1 and pane.live else 1.0))
	draw_style_box(Art.box(Color(nface, a), Color(nface.darkened(0.65), a), 20, 3, 10, Color(nface.r, nface.g, nface.b, 0.35 * a), 16), nr)
	_text(nr.get_center() + Vector2(0, 18), "SOMEONE NEW", 54, Color(0.13, 0.05, 0.0, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_text(Vector2(960, 990), "Tap your name. New here? Tap SOMEONE NEW and type one.", 32, Color(0.85, 0.85, 0.95, 0.9 * a))

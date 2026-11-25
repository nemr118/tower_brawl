# 2026-10-26 the arena cards (ComfyUI paintings the user picked, tools/comfy/run_cards.py):
# the lobby's ARENA button opens this picker (polish "arena_cards"). A painted card for each
# arena and for MIX (the four in one), big enough for a kid's thumb: three on top, two under
# them. A tap on a card picks it for everyone, as the button's taps did (lobby.gd's
# arena_picked: game_client.gd sends {"kind": "arena", "n": ...}); a tap anywhere else
# closes it. The pick has a glowing gold frame. Drawn on the lobby's 1920 x 1080 frame.
# p4.21 (polish "motion"): it fades in; the cards rise in one after another; the card
# under the finger squeezes; the pick breathes.
extends Control

signal picked(n: int)

const P = preload("res://sim/proto.gd")
const LevelScript = preload("res://sim/level.gd")
const Art = preload("res://client/lobby_art.gd")
const Season = preload("res://client/season.gd")
const Motion = preload("res://client/motion.gd")
const SHEET := preload("res://assets/arena_cards.png")   # 400 x 225 a card: MIX, then LevelScript.PLAY's order
const CW := 400.0
const CH := 225.0
const CARD := Vector2(480, 270)
const GAP := 40.0
const GOLD := Color(1.0, 0.82, 0.25)

var current: int = P.ARENA_MIX
var t := 0.0
var _press := -2                   # the card a press went down on (-1: none, -2: no press)
var pane: Motion.Pane

func _init() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	pane = Motion.Pane.new(self, Vector2(960, 540), 0.95)

# The cards' order on screen: the arenas, then MIX.
static func order() -> Array:
	return LevelScript.PLAY + [P.ARENA_MIX]

# Arena n's card in the sheet (MIX is its first cell).
static func src(n: int) -> Rect2:
	var i := 0 if n == P.ARENA_MIX else LevelScript.PLAY.find(n) + 1
	if n == P.ARENA_MIX and Season.harvest():
		i = LevelScript.PLAY.size() + 1     # p4.18: the Harvest season's MIX (the keep, the bridges, the barn, the table), the sheet's last cell
	return Rect2(maxi(i, 0) * CW, 0, CW, CH)

func open(pick: int) -> void:
	current = pick
	t = 0.0
	_press = -2
	pane.open()
	queue_redraw()

func close() -> void:
	pane.close()

# Card i's place: five cards or fewer in rows of 3, more (p4.18: seven) in rows of 4, a little smaller.
func _rect(i: int) -> Rect2:
	var n := order().size()
	var per := 3 if n <= 5 else 4
	var card := CARD if n <= 5 else Vector2(416, 234)
	var row := i / per
	var in_row := mini(per, n - row * per)
	var row_w := in_row * card.x + (in_row - 1) * GAP
	var x := (1920.0 - row_w) * 0.5 + (i - row * per) * (card.x + GAP)
	return Rect2(Vector2(x, 200.0 + row * (card.y + 110.0)), card)

func _process(delta: float) -> void:
	if visible:
		t += delta
		pane.step(delta)
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT:
		return
	accept_event()
	if pane.closing():
		return
	var ord := order()
	var hit := -1
	for i in ord.size():
		if _rect(i).grow(12.0).has_point(e.position):
			hit = i
	if e.pressed:
		_press = hit
	elif _press != -2:
		if hit >= 0 and hit == _press:
			current = ord[hit]
			picked.emit(current)
		close()
		_press = -2

func _text(at: Vector2, s: String, fs: int, col: Color) -> void:
	var p := at - Vector2(Art.DISPLAY.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 0.0)
	draw_string_outline(Art.DISPLAY, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, col.a * 0.9))
	draw_string(Art.DISPLAY, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _draw() -> void:
	var a := clampf(t / 0.15, 0.0, 1.0)
	if pane.live:
		a = 1.0                    # (p4.21: the whole picker fades by itself)
	draw_rect(Rect2(-2000, -1000, 5920, 3080), Color(0.02, 0.01, 0.05, 0.88 * a))   # (wider than the frame: it grows in)
	_text(Vector2(960, 150), "PICK AN ARENA", 66, Color(GOLD, a))
	var ord := order()
	var a0 := a
	for i in ord.size():
		var n: int = ord[i]
		var on := n == current
		var r := _rect(i)
		if on:
			r.position.y -= 6.0
		# p4.21: each card rises in a moment after the one before it; the one under the finger squeezes,
		# the pick breathes
		var ck := Motion.rise(t, 0.03 + 0.04 * i, 0.32)
		a = a0 * clampf(ck * 1.6, 0.0, 1.0)
		if a <= 0.0:
			continue
		var cs := 1.0
		if pane.live:
			cs = 0.96 if _press == i else (1.0 + 0.012 * sin(t * 5.0) if on else 1.0)
		var cmid := r.get_center() + Vector2(0, 40)
		draw_set_transform(cmid * (1.0 - cs) + Vector2(0, (1.0 - ck) * 110.0), 0.0, Vector2.ONE * cs)
		draw_rect(r.grow(9.0), Color(0, 0, 0, 0.6 * a))
		draw_texture_rect_region(SHEET, r, src(n), Color(1, 1, 1, a))
		if on:
			draw_rect(r.grow(5.0), Color(GOLD, (0.75 + 0.25 * sin(t * 5.0)) * a), false, 7.0)
		else:
			draw_rect(r.grow(3.0), Color(0.9, 0.9, 1.0, 0.35 * a), false, 3.0)
		var name := "MIX" if n == P.ARENA_MIX else LevelScript.name_of(n)
		_text(Vector2(r.get_center().x, r.end.y + 54.0), name, 42, Color(GOLD, a) if on else Color(1, 1, 1, a))
		if n == P.ARENA_MIX:
			_text(Vector2(r.get_center().x, r.end.y + 92.0), "a new one every round", 26, Color(0.85, 0.85, 0.95, 0.85 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

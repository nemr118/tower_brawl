# p4.9 the Halloween look (THE HAUNTED HOUSE, sim/level.gd theme "halloween"). Behind
# the blocks: a big orange moon in the sky, the haunted house's dark shape with lit
# windows that flicker (it hides the backdrop's grey moon), bats flapping across the sky. In front
# (the threats layer, under the fighters, so the night never darkens them): the
# torches as jack-o'-lanterns with flickering faces, cobwebs in the top corners and
# a low purple mist. world.gd turns the night purple and hides the stone torches.
# Drawn by hand, on every look.
extends Node2D

const BOOST := 2.3               # the base layer is darkened by the night (world.gd's CanvasModulate):
                                 # colours over 1 come out as they should
const MOON := Vector2(1650, 330) # in the open sky right of the house
const BATS := 7

var on := false
var t := 0.0
var torches: Array = []
var front: Node2D

class _Front extends Node2D:
	var tv
	func _draw() -> void:
		if tv != null:
			tv._paint_front(self)

func setup(threats: Node2D) -> void:
	front = _Front.new()
	front.tv = self
	threats.add_child(front)
	threats.move_child(front, 0)  # first in the threats layer: under the fighters
	set_theme("", [])

func set_theme(theme: String, torch_list: Array) -> void:
	on = theme == "halloween"
	torches = torch_list
	visible = on
	if front != null:
		front.visible = on

func _process(delta: float) -> void:
	if not on:
		return
	t += delta
	queue_redraw()
	front.queue_redraw()

func _b(c: Color) -> Color:
	return Color(c.r * BOOST, c.g * BOOST, c.b * BOOST, c.a)

# ------------------------------------------------------------------ behind the blocks
func _draw() -> void:
	for i in 5:
		draw_circle(MOON, 190.0 - i * 26.0, _b(Color(1.0, 0.5, 0.15, 0.05 + i * 0.025)))
	draw_circle(MOON, 92.0, _b(Color(1.0, 0.6, 0.2)))
	draw_circle(MOON + Vector2(-26, -18), 16.0, _b(Color(0.92, 0.5, 0.16)))
	draw_circle(MOON + Vector2(30, 12), 22.0, _b(Color(0.92, 0.5, 0.16)))
	draw_circle(MOON + Vector2(-8, 40), 10.0, _b(Color(0.92, 0.5, 0.16)))
	# the house's shape: a body behind the house blocks, a steep roof, a crooked tower
	var shade := Color(0.05, 0.03, 0.09, 0.92)
	draw_rect(Rect2(570, 250, 780, 780), shade)
	draw_colored_polygon(PackedVector2Array([Vector2(530, 262), Vector2(960, 66), Vector2(1390, 262)]), shade)
	draw_rect(Rect2(600, 110, 80, 160), shade)
	draw_colored_polygon(PackedVector2Array([Vector2(586, 116), Vector2(646, 20), Vector2(696, 116)]), shade)
	# lit windows (a candle flickers in each)
	var wins := [Rect2(620, 150, 30, 44), Rect2(930, 150, 40, 50), Rect2(650, 470, 46, 64), Rect2(1225, 470, 46, 64),
		Rect2(700, 640, 46, 64), Rect2(1180, 640, 46, 64), Rect2(940, 700, 40, 56)]
	for i in wins.size():
		var r: Rect2 = wins[i]
		var k := 0.75 + 0.25 * sin(t * (5.0 + i) + i * 2.3)
		draw_rect(r, _b(Color(1.0, 0.75, 0.3, 0.55) * Color(k, k, k, 1.0)))
		draw_line(r.position + Vector2(r.size.x / 2.0, 0), r.position + Vector2(r.size.x / 2.0, r.size.y), shade, 3.0)
		draw_line(r.position + Vector2(0, r.size.y / 2.0), r.position + Vector2(r.size.x, r.size.y / 2.0), shade, 3.0)
	# bats: each on its own loop over the sky, wings flapping
	for i in BATS:
		var ph := i * 1.7
		var p := Vector2(fposmod(200.0 + i * 270.0 + t * (40.0 + i * 9.0), 2100.0) - 90.0,
			120.0 + i * 38.0 + sin(t * (1.1 + i * 0.13) + ph) * 60.0)
		_bat(p, 1.1 + 0.15 * (i % 3), t * 14.0 + ph)

func _bat(p: Vector2, s: float, ph: float) -> void:
	var flap := sin(ph) * 9.0 * s
	var col := Color(0.03, 0.02, 0.05, 0.95)
	var rim := _b(Color(0.45, 0.3, 0.6, 0.8))   # a faint rim: a black bat on the night sky
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array([p + Vector2(side * 4.0, 0) * s, p + Vector2(side * 22.0 * s, -6.0 * s - flap),
			p + Vector2(side * 16.0 * s, 4.0 * s - flap * 0.4), p + Vector2(side * 9.0 * s, 1.0 * s), p + Vector2(side * 4.0, 0) * s])
		draw_polyline(wing, rim, 2.5)
	for side in [-1.0, 1.0]:
		draw_colored_polygon(PackedVector2Array([p + Vector2(side * 4.0, 0) * s, p + Vector2(side * 22.0 * s, -6.0 * s - flap),
			p + Vector2(side * 16.0 * s, 4.0 * s - flap * 0.4), p + Vector2(side * 9.0 * s, 1.0 * s)]), col)
	draw_circle(p, 5.0 * s, col)
	draw_circle(p + Vector2(-2, -1) * s, 1.2 * s, _b(Color(1.0, 0.2, 0.15)))
	draw_circle(p + Vector2(2, -1) * s, 1.2 * s, _b(Color(1.0, 0.2, 0.15)))

# ------------------------------------------------------------------ in front, under the fighters
func _paint_front(n: Node2D) -> void:
	# a low purple mist along the floor
	var mist := PackedVector2Array([Vector2(0, 1080), Vector2(0, 985)])
	for i in 25:
		var x := i * 80.0
		mist.append(Vector2(x, 975.0 + sin(t * 0.7 + i * 0.9) * 12.0))
	mist.append(Vector2(1920, 985))
	mist.append(Vector2(1920, 1080))
	n.draw_colored_polygon(mist, Color(0.55, 0.35, 0.8, 0.18))
	# cobwebs in the top corners
	for corner in [[Vector2(60, 60), 1.0], [Vector2(1860, 60), -1.0]]:
		var c: Vector2 = corner[0]
		var sx: float = corner[1]
		var col := Color(0.85, 0.85, 0.95, 0.45)
		for k in 5:
			var a := k * PI / 8.0
			n.draw_line(c, c + Vector2(cos(a) * sx, sin(a)) * 110.0, col, 1.5)
		for ring in [40.0, 70.0, 100.0]:
			var pts := PackedVector2Array()
			for k in 5:
				var a := k * PI / 8.0
				pts.append(c + Vector2(cos(a) * sx, sin(a)) * ring * (0.92 if k % 2 == 1 else 1.0))
			n.draw_polyline(pts, col, 1.2)
	# jack-o'-lanterns where the torches were
	for i in torches.size():
		_pumpkin(n, torches[i] + Vector2(0, 6), i)

func _pumpkin(n: Node2D, p: Vector2, i: int) -> void:
	var orange := Color(0.95, 0.5, 0.1)
	var dark := Color(0.6, 0.28, 0.05)
	for k in [-1.0, 1.0]:
		n.draw_set_transform(p + Vector2(k * 9.0, 0), 0.0, Vector2(0.8, 1.0))
		n.draw_circle(Vector2.ZERO, 16.0, dark)
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	n.draw_set_transform(p, 0.0, Vector2(1.25, 1.0))
	n.draw_circle(Vector2.ZERO, 17.0, orange)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	n.draw_line(p + Vector2(0, -16), p + Vector2(3, -24), Color(0.25, 0.5, 0.15), 4.0)
	var glow := 0.75 + 0.25 * sin(t * 13.0 + i * 1.9) * sin(t * 7.0 + i)
	var face := Color(1.0, 0.92 * glow, 0.35 * glow)
	n.draw_colored_polygon(PackedVector2Array([p + Vector2(-11, -5), p + Vector2(-4, -5), p + Vector2(-7.5, -11)]), face)
	n.draw_colored_polygon(PackedVector2Array([p + Vector2(4, -5), p + Vector2(11, -5), p + Vector2(7.5, -11)]), face)
	n.draw_colored_polygon(PackedVector2Array([p + Vector2(-13, 2), p + Vector2(-8, 6), p + Vector2(-4, 3), p + Vector2(0, 7),
		p + Vector2(4, 3), p + Vector2(8, 6), p + Vector2(13, 2), p + Vector2(9, 10), p + Vector2(0, 12), p + Vector2(-9, 10)]), face)

# p4.9 the Halloween look (THE HAUNTED HOUSE, sim/level.gd theme "halloween"). Behind
# the blocks: a big orange moon in the sky, the haunted house's dark shape with lit
# windows that flicker (it hides the backdrop's grey moon), bats flapping across the sky. In front
# (the threats layer, under the fighters, so the night never darkens them): the
# torches as jack-o'-lanterns with flickering faces, cobwebs in the top corners and
# a low purple mist. world.gd turns the night purple and hides the stone torches.
# Drawn by hand, on every look.
# The polish of 2026-10-25 (client/polish.gd has a switch for each piece; with a
# switch off, the old drawing below it comes back): windows with frames, curtains and
# a ghost or a cat passing behind one; boards and shingles on the house; a shaded moon
# with clouds and a witch on a broom; soft mist; spiders on threads; ribbed
# jack-o'-lanterns; a dead tree's branches and gravestones in the yard. The parts that
# never move are drawn once (the `still` node), the rest every frame.
extends Node2D

const Polish = preload("res://client/polish.gd")
const HALO := preload("res://assets/fx_halo.png")
const BOOST := 2.3               # the base layer is darkened by the night (world.gd's CanvasModulate):
                                 # colours over 1 come out as they should
const MOON := Vector2(1650, 330) # in the open sky right of the house
const MOON_R := 92.0
const BATS := 7
const REDRAW_HZ := 30.0          # polish: the moving parts are drawn again 30 times a second, not every frame (cheaper on phones)
const SHADE := Color(0.05, 0.03, 0.09, 0.92)   # the house's dark shape
# the house's lit windows (a candle flickers in each)
const WINS := [Rect2(620, 150, 30, 44), Rect2(930, 150, 40, 50), Rect2(650, 470, 46, 64), Rect2(1225, 470, 46, 64),
	Rect2(700, 640, 46, 64), Rect2(1180, 640, 46, 64), Rect2(940, 700, 40, 56)]
# polish "hh_moon": the moon's craters [offset from the middle, radius]
const CRATERS := [[Vector2(-26, -18), 16.0], [Vector2(30, 12), 22.0], [Vector2(-8, 40), 10.0], [Vector2(42, -42), 8.0],
	[Vector2(-52, 22), 9.0], [Vector2(8, -56), 6.0], [Vector2(-34, -54), 5.0]]
# polish "hh_moon": clouds drifting over the moon [phase, height, size]
const CLOUDS := [[0.0, 300.0, 1.0], [0.37, 356.0, 0.8], [0.7, 262.0, 0.65]]
# polish "hh_yard": the dead tree's branches behind its trunk (the 2-wide pillar on the
# left) [from, to, width], and gravestones far behind the yard [x, kind, height]
const BRANCHES := [
	[Vector2(296, 700), Vector2(252, 604), 11.0], [Vector2(252, 604), Vector2(192, 548), 7.0], [Vector2(192, 548), Vector2(146, 530), 4.0],
	[Vector2(252, 604), Vector2(238, 548), 5.0], [Vector2(238, 548), Vector2(212, 506), 3.0], [Vector2(192, 548), Vector2(180, 512), 3.0],
	[Vector2(306, 700), Vector2(356, 612), 10.0], [Vector2(356, 612), Vector2(418, 566), 6.0], [Vector2(418, 566), Vector2(468, 556), 3.0],
	[Vector2(356, 612), Vector2(370, 556), 4.0], [Vector2(370, 556), Vector2(394, 516), 3.0], [Vector2(418, 566), Vector2(430, 532), 2.5],
	[Vector2(300, 700), Vector2(304, 640), 8.0], [Vector2(304, 640), Vector2(296, 590), 4.0]]
const GRAVES := [[612.0, 0, 34.0], [664.0, 1, 28.0], [1104.0, 2, 30.0], [1164.0, 0, 24.0], [1748.0, 1, 30.0]]
# polish "hh_pumpkins": the jack-o'-lantern's face (the same as the old one's)
const FACE_EYE_L := [Vector2(-11, -5), Vector2(-4, -5), Vector2(-7.5, -11)]
const FACE_EYE_R := [Vector2(4, -5), Vector2(11, -5), Vector2(7.5, -11)]
const FACE_MOUTH := [Vector2(-13, 2), Vector2(-8, 6), Vector2(-4, 3), Vector2(0, 7), Vector2(4, 3), Vector2(8, 6), Vector2(13, 2),
	Vector2(9, 10), Vector2(0, 12), Vector2(-9, 10)]

var on := false
var t := 0.0
var torches: Array = []
var front: Node2D
var still: Node2D                         # polish: the parts that never move, drawn once, behind this node's drawing
var moon_lit := PackedVector2Array()      # polish: the moon's lit side (the disc less a crescent of shadow)
var redraw_wait := 0.0

class _Front extends Node2D:
	var tv
	func _draw() -> void:
		if tv != null:
			tv._paint_front(self)

class _Still extends Node2D:
	var tv
	func _draw() -> void:
		if tv != null:
			tv._paint_still(self)

func setup(threats: Node2D) -> void:
	front = _Front.new()
	front.tv = self
	threats.add_child(front)
	threats.move_child(front, 0)  # first in the threats layer: under the fighters
	still = _Still.new()
	still.tv = self
	still.show_behind_parent = true
	add_child(still)
	var disc := _circle_points(MOON, MOON_R, 48)
	var lit := Geometry2D.intersect_polygons(disc, _circle_points(MOON + Vector2(17, -13), MOON_R * 1.03, 48))
	moon_lit = lit[0] if lit.size() > 0 else disc
	set_theme("", [])

func set_theme(theme: String, torch_list: Array) -> void:
	on = theme == "halloween"
	torches = torch_list
	visible = on
	if front != null:
		front.visible = on
	if still != null:
		still.queue_redraw()

func _process(delta: float) -> void:
	if not on:
		return
	t += delta
	redraw_wait -= delta
	if redraw_wait > 0.0:
		return
	redraw_wait = 1.0 / REDRAW_HZ
	queue_redraw()
	front.queue_redraw()

func _b(c: Color) -> Color:
	return Color(c.r * BOOST, c.g * BOOST, c.b * BOOST, c.a)

static func _circle_points(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		pts.append(c + Vector2.from_angle(TAU * k / n) * r)
	return pts

# An ellipse: a circle drawn through a stretched transform.
static func _ellipse(n: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	n.draw_set_transform(c, 0.0, Vector2(r.x / r.y, 1.0))
	n.draw_circle(Vector2.ZERO, r.y, col)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------------ behind the blocks
func _draw() -> void:
	if not Polish.on("hh_moon"):
		for i in 5:
			draw_circle(MOON, 190.0 - i * 26.0, _b(Color(1.0, 0.5, 0.15, 0.05 + i * 0.025)))
		draw_circle(MOON, 92.0, _b(Color(1.0, 0.6, 0.2)))
		draw_circle(MOON + Vector2(-26, -18), 16.0, _b(Color(0.92, 0.5, 0.16)))
		draw_circle(MOON + Vector2(30, 12), 22.0, _b(Color(0.92, 0.5, 0.16)))
		draw_circle(MOON + Vector2(-8, 40), 10.0, _b(Color(0.92, 0.5, 0.16)))
	else:
		_clouds()
		_witch()
	if not Polish.on("hh_house"):
		# the house's shape: a body behind the house blocks, a steep roof, a crooked tower
		_house_shape(self)
	if not Polish.on("hh_windows"):
		# lit windows (a candle flickers in each)
		for i in WINS.size():
			var r: Rect2 = WINS[i]
			var k := 0.75 + 0.25 * sin(t * (5.0 + i) + i * 2.3)
			draw_rect(r, _b(Color(1.0, 0.75, 0.3, 0.55) * Color(k, k, k, 1.0)))
			draw_line(r.position + Vector2(r.size.x / 2.0, 0), r.position + Vector2(r.size.x / 2.0, r.size.y), SHADE, 3.0)
			draw_line(r.position + Vector2(0, r.size.y / 2.0), r.position + Vector2(r.size.x, r.size.y / 2.0), SHADE, 3.0)
	else:
		for i in WINS.size():
			_window(WINS[i], i)
	# bats: each on its own loop over the sky, wings flapping
	for i in BATS:
		var ph := i * 1.7
		var p := Vector2(fposmod(200.0 + i * 270.0 + t * (40.0 + i * 9.0), 2100.0) - 90.0,
			120.0 + i * 38.0 + sin(t * (1.1 + i * 0.13) + ph) * 60.0)
		_bat(p, 1.1 + 0.15 * (i % 3), t * 14.0 + ph)

func _house_shape(n: CanvasItem) -> void:
	n.draw_rect(Rect2(570, 250, 780, 780), SHADE)
	n.draw_colored_polygon(PackedVector2Array([Vector2(530, 262), Vector2(960, 66), Vector2(1390, 262)]), SHADE)
	n.draw_rect(Rect2(600, 110, 80, 160), SHADE)
	n.draw_colored_polygon(PackedVector2Array([Vector2(586, 116), Vector2(646, 20), Vector2(696, 116)]), SHADE)

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

# ------------------------------------------------------------------ polish: drawn once, behind
func _paint_still(n: Node2D) -> void:
	if not on:
		return
	if Polish.on("hh_moon"):
		# a soft glow and three faint steps of it, a bright rim, the shadow side, the lit side
		n.draw_texture_rect(HALO, Rect2(MOON - Vector2(310, 310), Vector2(620, 620)), false, _b(Color(1.0, 0.42, 0.12, 0.32)))
		for i in 3:
			n.draw_circle(MOON, 156.0 - i * 22.0, _b(Color(1.0, 0.5, 0.15, 0.03 + i * 0.02)))
		n.draw_circle(MOON, MOON_R + 3.0, _b(Color(1.0, 0.78, 0.45, 0.6)))
		n.draw_circle(MOON, MOON_R, _b(Color(0.8, 0.4, 0.12)))
		n.draw_colored_polygon(moon_lit, _b(Color(1.0, 0.62, 0.22)))
		for c in CRATERS:   # each with a lit lower rim and a deeper middle
			var p: Vector2 = MOON + c[0]
			var r: float = c[1]
			n.draw_circle(p + Vector2(1.5, 2.0), r, _b(Color(1.0, 0.76, 0.42)))
			n.draw_circle(p, r, _b(Color(0.84, 0.44, 0.13)))
			n.draw_circle(p + Vector2(-r * 0.22, -r * 0.22), r * 0.6, _b(Color(0.76, 0.38, 0.11)))
	if Polish.on("hh_house"):
		_house_shape(n)
		# boards on the walls: faint lines a little lighter than the house, with gaps
		var board := Color(0.17, 0.11, 0.21, 0.6)
		for k in 30:
			var y := 268.0 + k * 26.0
			if y > 1016.0:
				break
			var x := 578.0 + float((k * 29) % 40)
			var s := k * 7
			while x < 1340.0:
				var x2 := minf(x + 80.0 + float((s * 37) % 150), 1342.0)
				n.draw_line(Vector2(x, y), Vector2(x2, y), board, 2.0)
				x = x2 + 12.0 + float((s * 13) % 34)
				s += 1
		# shingles on the roof: rows along the slope, each cut into tiles
		var sh := Color(0.16, 0.1, 0.2, 0.75)
		for row in 8:
			var y := 92.0 + row * 21.0
			var half := (y - 66.0) * 430.0 / 196.0 - 10.0
			n.draw_line(Vector2(960.0 - half, y), Vector2(960.0 + half, y), sh, 2.0)
			var x := 960.0 - half + (13.0 if row % 2 == 1 else 2.0)
			while x < 960.0 + half:
				n.draw_line(Vector2(x, y), Vector2(x, y + 11.0), sh, 2.0)
				x += 26.0
		# boards across the tower's window
		n.draw_line(Vector2(612, 160), Vector2(668, 182), Color(0.2, 0.13, 0.17), 5.0)
	if Polish.on("hh_yard"):
		var bark := Color(0.04, 0.025, 0.06, 0.96)
		for b in BRANCHES:
			n.draw_line(b[0], b[1], bark, b[2])
			n.draw_circle(b[1], b[2] * 0.5, bark)
		for g in GRAVES:
			_grave(n, Vector2(g[0], 1021.0), int(g[1]), g[2])

func _grave(n: Node2D, foot: Vector2, kind: int, h: float) -> void:
	var stone := Color(0.13, 0.11, 0.17, 0.96)
	var edge := Color(0.3, 0.26, 0.38, 0.85)
	var w := h * 0.62
	if kind == 1:   # a cross
		n.draw_rect(Rect2(foot.x - 3.5, foot.y - h, 7.0, h), stone)
		n.draw_rect(Rect2(foot.x - w * 0.5, foot.y - h * 0.72, w, 6.0), stone)
		n.draw_line(Vector2(foot.x - 3.5, foot.y - h), Vector2(foot.x + 3.5, foot.y - h), edge, 2.0)
		return
	var poly := PackedVector2Array([foot + Vector2(-w * 0.5, 0), foot + Vector2(-w * 0.5, -h + w * 0.5)])
	for k in 7:   # a rounded top
		poly.append(foot + Vector2(0, -h + w * 0.5) + Vector2.from_angle(PI + PI * k / 6.0) * w * 0.5)
	poly.append(foot + Vector2(w * 0.5, 0))
	if kind == 2:   # leaning over
		var lean := PackedVector2Array()
		for q in poly:
			lean.append(foot + (q - foot).rotated(0.22))
		poly = lean
	n.draw_colored_polygon(poly, stone)
	n.draw_polyline(poly.slice(1, poly.size() - 1), edge, 2.0)

# ------------------------------------------------------------------ polish: moving, behind
# Clouds drift across the moon (only near it: they never cross the house): soft dark
# wisps (the halo texture, stretched), with the edge the moon lights a little above.
func _clouds() -> void:
	for c in CLOUDS:
		var s: float = c[2]
		var u: float = fposmod(c[0] + t * 0.011 * (0.7 + s * 0.5), 1.0)
		var a := clampf(minf(u, 1.0 - u) * 8.0, 0.0, 1.0)   # it fades in and out at the ends of its path
		var p := Vector2(1390.0 + u * 640.0, c[1])
		var lobes := [[Vector2(0, 0), Vector2(62, 9)], [Vector2(-42, 5), Vector2(40, 7)], [Vector2(44, 4), Vector2(46, 7)], [Vector2(8, -6), Vector2(34, 8)]]
		for l in lobes:
			var r: Vector2 = l[1] * s * 2.0     # the texture fades out by half its size: draw it twice as big
			draw_texture_rect(HALO, Rect2(p + l[0] * s - r + Vector2(0, -4), r * 2.0), false, _b(Color(1.0, 0.58, 0.25, 0.2 * a)))
		for l in lobes:
			var r: Vector2 = l[1] * s * 2.0
			draw_texture_rect(HALO, Rect2(p + l[0] * s - r, r * 2.0), false, Color(0.08, 0.04, 0.12, 0.62 * a))

# A witch on a broom crosses the moon now and then (6.5 s across, every 21 s).
func _witch() -> void:
	var u := fmod(t + 5.0, 21.0) / 6.5
	if u >= 1.0:
		return
	var a := clampf(minf(u, 1.0 - u) * 10.0, 0.0, 1.0)
	var p := Vector2(lerpf(2010.0, 1400.0, u), MOON.y - 34.0 + sin(u * TAU) * 20.0 + u * 34.0)
	var col := Color(0.03, 0.015, 0.05, 0.97 * a)
	var rim := _b(Color(0.5, 0.32, 0.65, 0.55 * a))
	var flap := sin(t * 9.0) * 4.0
	draw_set_transform(p, 0.0, Vector2(1.35, 1.35))
	var cape := PackedVector2Array([Vector2(4, -21), Vector2(22 + flap, -15), Vector2(27 + flap, -5), Vector2(11, -2)])
	var cloak := PackedVector2Array([Vector2(-8, 0), Vector2(12, 0), Vector2(3, -24)])
	var hat := PackedVector2Array([Vector2(-6, -31), Vector2(6, -31), Vector2(12, -47)])
	var bristles := PackedVector2Array([Vector2(18, -4), Vector2(38, -12), Vector2(44, -2), Vector2(38, 8), Vector2(18, 3)])
	for poly in [cape, cloak, hat, bristles]:   # a faint rim first: a black witch on the night sky
		var ring: PackedVector2Array = poly.duplicate()
		ring.append(poly[0])
		draw_polyline(ring, rim, 3.0)
	draw_line(Vector2(-34, 2), Vector2(22, -1), rim, 5.0)
	draw_line(Vector2(-34, 2), Vector2(22, -1), col, 3.0)
	for poly in [cape, cloak, hat, bristles]:
		draw_colored_polygon(poly, col)
	draw_line(Vector2(-13, -31), Vector2(9, -31), col, 3.0)                # the hat's brim
	draw_circle(Vector2(-2, -27), 5.0, col)                                # the head
	draw_colored_polygon(PackedVector2Array([Vector2(-6, -28), Vector2(-11, -26), Vector2(-6, -25)]), col)   # the nose
	draw_line(Vector2(-3, -2), Vector2(-11, 7), col, 2.5)                  # a foot hanging down
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# A window: the glow it throws, a frame and a sill, candlelight brighter low in the
# glass, whoever walks behind it, the bars, torn curtains.
func _window(r: Rect2, i: int) -> void:
	var k := 0.75 + 0.25 * sin(t * (5.0 + i) + i * 2.3)
	var frame := Color(0.13, 0.08, 0.12)
	draw_texture_rect(HALO, r.grow_individual(34, 30, 34, 40), false, _b(Color(1.0, 0.5, 0.15, 0.17 * k)))
	draw_rect(r.grow(5), frame)
	draw_rect(Rect2(r.position.x - 9, r.end.y + 3, r.size.x + 18, 6), Color(0.22, 0.15, 0.21))
	var top := _b(Color(0.82, 0.36, 0.1)) * Color(k, k, k, 1.0)
	var low := _b(Color(1.0, 0.8, 0.38)) * Color(k, k, k, 1.0)
	draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, low, low]))
	_visitor(r, i, low)
	var mx := r.position.x + r.size.x / 2.0
	var my := r.position.y + r.size.y * 0.45
	draw_line(Vector2(mx, r.position.y), Vector2(mx, r.end.y), frame, 3.0)
	draw_line(Vector2(r.position.x, my), Vector2(r.end.x, my), frame, 3.0)
	var cur := Color(0.2, 0.05, 0.14, 0.96)
	var w := r.size.x
	var h := r.size.y
	var p := r.position
	draw_colored_polygon(PackedVector2Array([p, p + Vector2(w * 0.27, 0), p + Vector2(w * 0.14, h * 0.24), p + Vector2(w * 0.07, h * 0.44),
		p + Vector2(0, h * 0.58)]), cur)
	draw_colored_polygon(PackedVector2Array([p + Vector2(w, 0), p + Vector2(w, h * 0.58), p + Vector2(w * 0.93, h * 0.44),
		p + Vector2(w * 0.86, h * 0.24), p + Vector2(w * 0.73, 0)]), cur)

# Every 7 s one window gets a visitor: a ghost drifting across, or a cat that sits
# with glowing eyes and then slips away. Dark shapes against the candlelight.
func _visitor(r: Rect2, i: int, glass: Color) -> void:
	var slot := int(t / 7.0)
	if (slot * 3) % WINS.size() != i:
		return
	var u := fmod(t, 7.0) / 7.0
	var dark := Color(0.07, 0.02, 0.07, 0.93)
	var s := r.size.x / 46.0
	if slot % 2 == 0:
		if u < 0.1 or u > 0.7:
			return
		var c := Vector2(lerpf(r.position.x - 22.0 * s, r.end.x + 22.0 * s, (u - 0.1) / 0.6), r.position.y + r.size.y * 0.5 + sin(t * 3.0) * 3.0)
		var g := PackedVector2Array()
		for q in 9:   # the round head
			g.append(c + Vector2(0, -8) * s + Vector2.from_angle(PI + PI * q / 8.0) * 13.0 * s)
		for v in [Vector2(13, 22), Vector2(8, 16), Vector2(3, 22), Vector2(-3, 16), Vector2(-8, 22), Vector2(-13, 16)]:
			g.append(c + v * s)
		var rect := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		for piece in Geometry2D.intersect_polygons(g, rect):
			draw_colored_polygon(piece, dark)
		for e in [Vector2(-4, -11), Vector2(4, -11)]:   # the eye holes show the light through
			var ep: Vector2 = c + e * s
			if r.grow(-1).has_point(ep):
				draw_circle(ep, 2.2 * s, glass)
	else:
		if u < 0.12 or u > 0.8:
			return
		var f := Vector2(r.position.x + r.size.x * 0.5, r.end.y)
		_ellipse(self, f + Vector2(0, -9) * s, Vector2(9, 9) * s, dark)        # the body
		draw_circle(f + Vector2(-1, -21) * s, 6.5 * s, dark)                   # the head
		for side in [-1.0, 1.0]:                                               # the ears
			draw_colored_polygon(PackedVector2Array([f + Vector2(side * 2 - 1, -25) * s, f + Vector2(side * 6.5 - 1, -32) * s,
				f + Vector2(side * 6.5 - 1, -23) * s]), dark)
		draw_polyline(PackedVector2Array([f + Vector2(8, -3) * s, f + Vector2(15, -6) * s, f + Vector2(16, -14) * s, f + Vector2(13, -18) * s]),
			dark, 3.0 * s)                                                     # the tail
		if fmod(t + i, 2.6) > 0.18:                                            # the eyes, blinking
			for side in [-1.0, 1.0]:
				draw_circle(f + Vector2(side * 2.6 - 1, -22) * s, 1.6 * s, _b(Color(0.75, 1.0, 0.3)))

# ------------------------------------------------------------------ in front, under the fighters
func _paint_front(n: Node2D) -> void:
	if not Polish.on("hh_mist"):
		# a low purple mist along the floor
		n.draw_colored_polygon(_mist_band(), Color(0.55, 0.35, 0.8, 0.18))
	else:
		# a thin band, then soft puffs drifting both ways
		n.draw_colored_polygon(_mist_band(), Color(0.55, 0.35, 0.8, 0.07))
		for layer in 2:
			for i in 10:
				var sp := 8.0 + layer * 6.0 + (i % 3) * 2.0
				var x := fposmod(i * 211.0 + layer * 100.0 + t * sp * (1.0 if layer == 0 else -1.0), 2240.0) - 160.0
				var y := 1000.0 + layer * 24.0 + sin(t * 0.5 + i * 1.7) * 8.0
				var w := 220.0 + float((i * 53) % 120)
				var h := 64.0 + float((i * 31) % 36)
				n.draw_texture_rect(HALO, Rect2(x - w / 2.0, y - h / 2.0, w, h), false, Color(0.62, 0.44, 0.9, 0.13 if layer == 0 else 0.1))
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
		if Polish.on("hh_spiders"):
			_spider(n, c + Vector2(sx * 60.0, 58.0), 0 if sx > 0 else 1)
	# jack-o'-lanterns where the torches were
	for i in torches.size():
		if Polish.on("hh_pumpkins"):
			_pumpkin2(n, torches[i] + Vector2(0, 6), i)
		else:
			_pumpkin(n, torches[i] + Vector2(0, 6), i)

func _mist_band() -> PackedVector2Array:
	var mist := PackedVector2Array([Vector2(0, 1080), Vector2(0, 985)])
	for i in 25:
		var x := i * 80.0
		mist.append(Vector2(x, 975.0 + sin(t * 0.7 + i * 0.9) * 12.0))
	mist.append(Vector2(1920, 985))
	mist.append(Vector2(1920, 1080))
	return mist

# polish "hh_spiders": a spider lets itself down on a thread and climbs back up.
func _spider(n: Node2D, top: Vector2, i: int) -> void:
	var p := top + Vector2(0, 64.0 + 58.0 * (0.5 + 0.5 * sin(t * 0.55 + i * 2.1)))
	n.draw_line(top, p, Color(0.85, 0.85, 0.95, 0.5), 1.0)
	var body := Color(0.08, 0.05, 0.1)
	var rim := Color(0.55, 0.45, 0.7, 0.85)
	n.draw_set_transform(p, 0.0, Vector2(1.35, 1.35))
	for side in [-1.0, 1.0]:
		for k in 4:
			var wig := sin(t * 7.0 + k * 1.3 + i) * 1.2
			var leg := PackedVector2Array([Vector2(side * 4.0, -1.0 + k * 1.6), Vector2(side * (10.0 + k), -7.0 + k * 3.2 + wig),
				Vector2(side * (14.0 + k * 0.6), 2.0 + k * 3.6)])
			n.draw_polyline(leg, body, 2.0)
	n.draw_circle(Vector2(0, 3), 7.5, rim)
	n.draw_circle(Vector2(0, 3), 6.5, body)
	n.draw_circle(Vector2(0, -4), 4.0, body)
	n.draw_circle(Vector2(-1.5, -5), 1.3, Color(1.0, 0.25, 0.2))
	n.draw_circle(Vector2(1.5, -5), 1.3, Color(1.0, 0.25, 0.2))
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

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

# polish "hh_pumpkins": the same size and face, with a glow on the wall behind, five
# ribs, a shaded base, a highlight, the lid's cut, a curly stem and a face that glows
# hot in the middle.
func _pumpkin2(n: Node2D, p: Vector2, i: int) -> void:
	var glow := 0.75 + 0.25 * sin(t * 13.0 + i * 1.9) * sin(t * 7.0 + i)
	n.draw_texture_rect(HALO, Rect2(p - Vector2(72, 66), Vector2(144, 124)), false, Color(1.0, 0.55, 0.15, 0.24 * glow))
	_ellipse(n, p + Vector2(0, 5), Vector2(23, 13), Color(0.36, 0.14, 0.04))
	_ellipse(n, p + Vector2(-12, 0), Vector2(11, 16), Color(0.6, 0.27, 0.05))
	_ellipse(n, p + Vector2(12, 0), Vector2(11, 16), Color(0.6, 0.27, 0.05))
	_ellipse(n, p + Vector2(-6, 0), Vector2(11, 17), Color(0.85, 0.42, 0.08))
	_ellipse(n, p + Vector2(6, 0), Vector2(11, 17), Color(0.85, 0.42, 0.08))
	_ellipse(n, p, Vector2(10, 17), Color(0.98, 0.56, 0.12))
	_ellipse(n, p + Vector2(-8, -9), Vector2(4, 2.5), Color(1.0, 0.8, 0.45, 0.85))
	var cut := PackedVector2Array()
	for k in 7:
		cut.append(p + Vector2(-9.0 + k * 3.0, -12.0 - 3.0 * (k % 2)))
	n.draw_polyline(cut, Color(0.42, 0.17, 0.04), 1.5)
	n.draw_polyline(PackedVector2Array([p + Vector2(0, -13), p + Vector2(1, -19), p + Vector2(4, -24)]), Color(0.3, 0.46, 0.13), 4.0)
	n.draw_polyline(PackedVector2Array([p + Vector2(3, -19), p + Vector2(8, -20), p + Vector2(10, -17), p + Vector2(8, -15)]), Color(0.34, 0.52, 0.16), 1.5)
	var edge := Color(1.0, 0.5 * glow, 0.1 * glow)
	var hot := Color(1.0, 0.95 * glow, 0.5 * glow)
	for pass_i in 2:
		n.draw_set_transform(p, 0.0, Vector2.ONE * (1.2 if pass_i == 0 else 1.0))
		var col := edge if pass_i == 0 else hot
		for shape in [FACE_EYE_L, FACE_EYE_R, FACE_MOUTH]:
			n.draw_colored_polygon(PackedVector2Array(shape), col)
		n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

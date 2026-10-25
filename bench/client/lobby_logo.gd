# The lobby's title (2026-10-25): TOWER BRAWL in a heavy font, a dark edge, a
# coloured rim, a drop shadow, a soft glow behind it, letters filled with a
# gradient and a light that sweeps across them every few seconds (a small
# shader), and a ribbon under it with the dress's line (HALLOWEEN NIGHT). In the
# Halloween dress the O of TOWER is a jack-o'-lantern whose face flickers.
# Drawn in the lobby's 1920 x 1080 frame: the title's middle is at x 960.
extends Control

const Art = preload("res://client/lobby_art.gd")
const HALO := preload("res://assets/fx_halo.png")
const SIZE := 150                # the title's font size
const BASE := 168.0              # its baseline
const CX := 960.0

var pal: Dictionary = {}
var halloween := false
var tier := 2
var t := 0.0
var fill := _Fill.new()
var parts: Array = []            # [text, x] for each piece of the title
var pumpkin := Vector2.ZERO      # the pumpkin O: x of its middle, its width (0: none)

class _Fill extends Control:
	var logo
	func _draw() -> void:
		if logo != null:
			logo._paint_fill(self)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	size = Vector2(1920, 260)
	pivot_offset = Vector2(CX, 120)
	fill.logo = self
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.size = size
	fill.material = Art.grad_material(Color.WHITE, Color.WHITE, BASE - SIZE * 0.72, BASE, 1.0)
	add_child(fill)

func set_dress(p: Dictionary, hw: bool) -> void:
	pal = p
	halloween = hw
	var m: ShaderMaterial = fill.material
	m.set_shader_parameter("top_col", pal["logo_top"])
	m.set_shader_parameter("bot_col", pal["logo_bot"])
	_layout()
	queue_redraw()
	fill.queue_redraw()

func set_tier(n: int) -> void:
	tier = n
	var m: ShaderMaterial = fill.material
	m.set_shader_parameter("shine", 1.0 if n >= 2 else 0.0)
	queue_redraw()

# Where each piece of the title goes: "TOWER BRAWL" in one piece, or in the
# Halloween dress "T", the pumpkin, "WER BRAWL".
func _layout() -> void:
	Art.fonts_ready()
	var f := Art.DISPLAY
	parts.clear()
	pumpkin = Vector2.ZERO
	if halloween:
		var wt := f.get_string_size("T", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		var wo := f.get_string_size("O", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x * 1.12
		var wr := f.get_string_size("WER BRAWL", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		var x0 := CX - (wt + wo + wr) * 0.5
		parts.append(["T", x0])
		pumpkin = Vector2(x0 + wt + wo * 0.5, wo)
		parts.append(["WER BRAWL", x0 + wt + wo])
	else:
		var w := f.get_string_size("TOWER BRAWL", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
		parts.append(["TOWER BRAWL", CX - w * 0.5])

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta
	if halloween:
		queue_redraw()   # the pumpkin's face flickers

# Behind the letters: the glow, the shadow, the dark edge and the rim; the ribbon.
func _draw() -> void:
	if pal.is_empty():
		return
	var f := Art.DISPLAY
	if tier >= 2:
		var gc: Color = pal["logo_glow"]
		draw_texture_rect(HALO, Rect2(CX - 620, -10, 1240, 300), false, gc)
	if tier >= 2:
		for p in parts:
			draw_string_outline(f, Vector2(p[1], BASE + 11), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, 22, Color(0, 0, 0, 0.55))
	for p in parts:
		draw_string_outline(f, Vector2(p[1], BASE), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, 20, pal["logo_edge"])
	for p in parts:
		draw_string_outline(f, Vector2(p[1], BASE), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, 9, pal["logo_rim"])
	if pumpkin.y > 0.0:
		_pumpkin(Vector2(pumpkin.x, BASE - SIZE * 0.36), pumpkin.y)
	_ribbon(str(pal["tagline"]))

# The letters' fill (white: the shader turns it into the gradient and the light).
func _paint_fill(c: Control) -> void:
	for p in parts:
		c.draw_string(Art.DISPLAY, Vector2(p[1], BASE), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, Color.WHITE)

# A jack-o'-lantern as big as the letter O: ribs, a stem, a carved face lit from inside.
func _pumpkin(c: Vector2, w: float) -> void:
	var h := SIZE * 0.74
	var rx := w * 0.5
	var ry := h * 0.5
	var edge: Color = pal["logo_edge"]
	if tier >= 2:
		_oval(c + Vector2(0, 10), rx + 12, ry + 12, Color(0, 0, 0, 0.55))
	_oval(c, rx + 11, ry + 11, edge)
	if tier >= 2:
		_oval(c, rx + 5, ry + 5, pal["logo_rim"])
	var dark := Color(0.62, 0.22, 0.02)
	var mid := Color(0.95, 0.45, 0.06)
	var lit := Color(1.0, 0.62, 0.16)
	_oval(c, rx, ry, dark)
	_oval(c + Vector2(-rx * 0.42, 0), rx * 0.55, ry * 0.98, mid)
	_oval(c + Vector2(rx * 0.42, 0), rx * 0.55, ry * 0.98, mid)
	_oval(c + Vector2(0, -ry * 0.02), rx * 0.42, ry, lit)
	# the stem
	draw_colored_polygon(PackedVector2Array([c + Vector2(-7, -ry + 6), c + Vector2(6, -ry + 6), c + Vector2(13, -ry - 16),
		c + Vector2(2, -ry - 19)]), Color(0.25, 0.42, 0.12))
	draw_polyline(PackedVector2Array([c + Vector2(-7, -ry + 6), c + Vector2(2, -ry - 19), c + Vector2(13, -ry - 16),
		c + Vector2(6, -ry + 6)]), edge, 3.0)
	# the face: a candle inside flickers
	var k := 0.78 + 0.22 * sin(t * 11.0) * sin(t * 6.3 + 1.0)
	var face := Color(1.0, 0.95 * k, 0.45 * k)
	var s := w / 90.0
	var eye := PackedVector2Array([Vector2(-26, -8), Vector2(-8, -8), Vector2(-17, -27)])
	for side in [1.0, -1.0]:
		var pts := PackedVector2Array()
		for v in eye:
			pts.append(c + Vector2(v.x * side, v.y) * s)
		draw_colored_polygon(pts, face)
	var mouth := PackedVector2Array([Vector2(-30, 8), Vector2(-20, 15), Vector2(-12, 9), Vector2(-5, 16), Vector2(5, 9),
		Vector2(12, 16), Vector2(20, 9), Vector2(30, 8), Vector2(22, 26), Vector2(0, 33), Vector2(-22, 26)])
	var mp := PackedVector2Array()
	for v in mouth:
		mp.append(c + v * s)
	draw_colored_polygon(mp, face)

func _oval(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 28:
		var a := TAU * i / 28.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	draw_colored_polygon(pts, col)

# The ribbon under the title, its tails folded behind.
func _ribbon(s: String) -> void:
	var f := Art.DISPLAY
	var fs := 34
	var tw := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var w := tw + 90.0
	var y := BASE + 12.0
	var h := 50.0
	var x0 := CX - w * 0.5
	var x1 := CX + w * 0.5
	var rib: Color = pal["ribbon"]
	var dark: Color = pal["ribbon_dark"]
	for side in [-1.0, 1.0]:
		var xe := x0 if side < 0 else x1
		var tail := PackedVector2Array([Vector2(xe - side * 10, y + 12), Vector2(xe + side * 52, y + 12), Vector2(xe + side * 36, y + 12 + h * 0.5),
			Vector2(xe + side * 52, y + 12 + h), Vector2(xe - side * 10, y + 12 + h)])
		draw_colored_polygon(tail, dark)
		draw_colored_polygon(PackedVector2Array([Vector2(xe, y + h), Vector2(xe - side * 0.0, y + h + 12), Vector2(xe - side * 14, y + h)]),
			dark.darkened(0.4))
	draw_rect(Rect2(x0, y, w, h), rib)
	draw_rect(Rect2(x0, y, w, 4), rib.lightened(0.3))
	draw_rect(Rect2(x0, y + h - 5, w, 5), dark)
	Art.text(self, f, Vector2(x0, y + 38), s, fs, pal["ribbon_text"], 6, pal["logo_edge"], HORIZONTAL_ALIGNMENT_CENTER, w, false)

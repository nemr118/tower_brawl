# The lobby's title (2026-10-25): TOWER BRAWL in a heavy font, a dark edge, a
# coloured rim, a drop shadow, a soft glow behind it, letters filled with a
# gradient and a light that sweeps across them every few seconds (a small
# shader), and a ribbon under it with the dress's line (HALLOWEEN NIGHT). In the
# Halloween dress the O of TOWER is a jack-o'-lantern whose face flickers.
# Drawn in the lobby's 1920 x 1080 frame: the title's middle is at x 960.
# p4.22 the Christmas dress (the user: "snow on the letters and a wreath for the O of
# TOWER"): a cap of snow lies on every letter (drawn once and kept), the O is a wreath
# that swings a little from its top, a few sparkles come and go on the snow, and the
# ribbon counts the nights to Christmas ("12 SLEEPS TO CHRISTMAS": set_sleeps).
extends Control

const Art = preload("res://client/lobby_art.gd")
const HALO := preload("res://assets/fx_halo.png")
const PIE := preload("res://assets/harvest_pie.png")   # p4.18: the Harvest dress: the O of TOWER is a pumpkin pie (ComfyUI)
const WREATH := preload("res://assets/christmas_wreath.png")   # p4.22: the Christmas dress: the O is a wreath (256 x 256, its hole see-through)
const Xmas = preload("res://client/lobby_xmas.gd")
const XV = preload("res://client/christmas_view.gd")   # the sparkle
const WREATH_W := 138.0          # the wreath's picture on the title, px
const WREATH_K := WREATH_W / 256.0
# The wreath's berries, in its picture's own px (a light twinkles on one, then the next).
const BERRIES := [Vector2(127, 32), Vector2(192, 60), Vector2(215, 112), Vector2(197, 167), Vector2(60, 170), Vector2(40, 112), Vector2(62, 60)]
const SIZE := 150                # the title's font size
const BASE := 168.0              # its baseline
const CX := 960.0

var pal: Dictionary = {}
var halloween := false
var harvest := false             # p4.18: the Harvest dress (the O of TOWER is a pumpkin pie)
var christmas := false           # p4.22: the Christmas dress (snow on the letters, the O is a wreath)
var line := ""                   # p4.22: the ribbon's own words in place of the tagline (the countdown); "": the tagline
var frost := _Part.new()         # p4.22: the snow on the letters (drawn once, over the letters)
var wreath := _Wreath.new()      # the wreath: only its angle changes
var twinkle := _Part.new()       # the sparkles (drawn every frame: four small stars)
var caps: Array = []             # [x0, x1, y] of each cap of snow (where a sparkle may sit)
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

class _Part extends Control:
	var logo
	var which := 0
	func _draw() -> void:
		if logo != null:
			logo._paint_part(self, which)

# The wreath is a Node2D: a turn of a Node2D moves what it drew, a turn of a Control draws it again.
class _Wreath extends Node2D:
	var logo
	func _draw() -> void:
		if logo != null:
			logo._paint_part(self, 1)

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
	for part in [frost, wreath, twinkle]:     # p4.22: over the letters: the snow, the wreath, the sparkles
		part.logo = self
		part.visible = false
		add_child(part)
	twinkle.which = 2
	for part in [frost, twinkle]:
		part.mouse_filter = Control.MOUSE_FILTER_IGNORE
		part.size = size         # (a Control with no size at the frame's corner is taken for off the screen, and not drawn)

func set_dress(p: Dictionary, hw: bool) -> void:
	pal = p
	halloween = hw
	var m: ShaderMaterial = fill.material
	m.set_shader_parameter("top_col", pal["logo_top"])
	m.set_shader_parameter("bot_col", pal["logo_bot"])
	_layout()
	queue_redraw()
	fill.queue_redraw()
	for part in [frost, wreath, twinkle]:
		part.visible = christmas
		part.queue_redraw()

# p4.22: the nights left to Christmas Day (lobby.gd: the server's count, or the ?sleeps=
# test knob). The ribbon counts them down; under 0 (another day) it keeps the tagline.
func set_sleeps(n: int) -> void:
	var s := ""
	if christmas and n >= 0:
		s = "MERRY CHRISTMAS!" if n == 0 else ("1 SLEEP TO CHRISTMAS" if n == 1 else "%d SLEEPS TO CHRISTMAS" % n)
	if s != line:
		line = s
		queue_redraw()

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
	if halloween or harvest or christmas:
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
	caps.clear()
	if christmas:                # p4.22: where the snow lies, letter by letter (for the sparkles); the wreath hangs from its top
		for p in parts:
			caps.append_array(Xmas.word_caps(null, f, p[0], p[1], BASE, SIZE, Color(0, 0, 0, 0)))
		wreath.position = Vector2(pumpkin.x, BASE - SIZE * 0.36 - 104.0 * WREATH_K)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta
	if halloween or harvest:
		queue_redraw()   # the pumpkin's face flickers; the pie rocks
	elif christmas:      # p4.22: the wreath swings from its top (its angle only: nothing is drawn again but the sparkles)
		wreath.rotation = sin(t * 1.3) * 0.075
		twinkle.queue_redraw()

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
	if pumpkin.y > 0.0 and harvest:      # p4.18: a pumpkin pie, rocking a little
		var pw := pumpkin.y * 1.06
		draw_set_transform(Vector2(pumpkin.x, BASE - SIZE * 0.36), sin(t * 1.3) * 0.07, Vector2.ONE)
		draw_texture_rect(PIE, Rect2(-pw * 0.5, -pw * 0.5, pw, pw), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif pumpkin.y > 0.0 and not christmas:
		_pumpkin(Vector2(pumpkin.x, BASE - SIZE * 0.36), pumpkin.y)
	_ribbon(line if line != "" else str(pal["tagline"]))

# p4.22 the Christmas dress's parts over the letters. 0: the snow on each letter (drawn
# once). 1: the wreath, hanging from its own top so a turn swings it, a little snow on it.
# 2: sparkles on the snow and a light on the wreath's berries, one after another.
func _paint_part(c: CanvasItem, which: int) -> void:
	if not christmas or pal.is_empty():
		return
	if which == 0:
		for i in parts.size():
			Xmas.word_caps(c, Art.DISPLAY, parts[i][0], parts[i][1], BASE, SIZE, pal["logo_edge"], i * 11)
	elif which == 1:
		if tier >= 2:
			c.draw_texture_rect(WREATH, Rect2(-127.0 * WREATH_K, -8.0 * WREATH_K + 8.0, WREATH_W, WREATH_W), false, Color(0, 0, 0, 0.4))   # its shadow
		c.draw_texture_rect(WREATH, Rect2(-127.0 * WREATH_K, -8.0 * WREATH_K, WREATH_W, WREATH_W), false)
		Xmas.cap(c, -30.0, 30.0, 6.0, 11.0, 4, pal["logo_edge"], 9.0, 9.0)
	else:
		for k in (2 if tier <= 1 else 4):
			var u := t * 0.55 + k * 0.29
			var tw := sin(fposmod(u, 1.0) * PI)
			var n := int(u) * 7 + k * 3
			if k == 0:           # the wreath's berries, as it swings
				c.draw_set_transform(wreath.position, wreath.rotation, Vector2.ONE)
				XV.sparkle(c, (BERRIES[n % BERRIES.size()] - Vector2(127, 8)) * WREATH_K, 13.0 * tw, Color(1.0, 0.95, 0.6, tw))
				c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			elif not caps.is_empty():
				var cp: Array = caps[n % caps.size()]
				XV.sparkle(c, Vector2(lerpf(cp[0], cp[1], 0.2 + 0.6 * fposmod(n * 0.37, 1.0)), float(cp[2]) - 9.0), 12.0 * tw, Color(1, 1, 1, tw))

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
	# p4.22: in the Christmas dress the ribbon sits 6 px higher: in TEAMS the horns and the
	# halo on the two middle cards' flags reach up to it, and must stay under its words
	var y := BASE + (6.0 if christmas else 12.0)
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

# The lobby's moving backdrop (2026-10-25), drawn over the arena the page shows
# behind the lobby: a dark tint that keeps the middle clear, a vignette, mist in
# three layers drifting at three speeds (the near one fastest), embers rising,
# and in the Halloween dress bats and a lightning flash now and then. LOW keeps
# it cheap: one mist layer, a few embers, two bats, no lightning.
# It covers the whole window (lobby.gd sets its rect from fit()).
extends Control

var pal: Dictionary = {}
var tier := 2                    # 1 LOW, 2 NORMAL, 3 HIGH (the page's look)
var halloween := false
var t := 0.0
var fade := 1.0                  # 0..1: the lobby fading in (lobby.gd)
var flash := 0.0
var next_flash := 7.0
var bolt := PackedVector2Array()
var embers: Array = []           # [x, y, speed, sway phase, size, green]
var glow := _Glow.new()          # the embers, added on top (blend add)
var vignette: GradientTexture2D

class _Glow extends Control:
	var bg
	func _draw() -> void:
		if bg != null:
			bg._paint_glow(self)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	glow.bg = self
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = m
	add_child(glow)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0.05), Color(0, 0, 0, 0.75)])
	vignette = GradientTexture2D.new()
	vignette.gradient = g
	vignette.fill = GradientTexture2D.FILL_RADIAL
	vignette.fill_from = Vector2(0.5, 0.5)
	vignette.fill_to = Vector2(1.05, 1.05)
	vignette.width = 128
	vignette.height = 128

func set_dress(p: Dictionary, hw: bool) -> void:
	pal = p
	halloween = hw
	queue_redraw()

func set_tier(n: int) -> void:
	tier = n
	var want: int = [8, 34, 56][clampi(n, 1, 3) - 1]
	while embers.size() > want:
		embers.pop_back()
	while embers.size() < want:
		embers.append(_ember(randf() * 1080.0))

func _ember(y: float) -> Array:
	return [randf(), y, 30.0 + randf() * 50.0, randf() * TAU, 2.0 + randf() * 3.5, randf() < 0.3]

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta
	for e in embers:
		e[1] -= e[2] * delta
		if e[1] < -20.0:
			e.assign(_ember(1100.0))
	if halloween and tier >= 2:
		next_flash -= delta
		if next_flash <= 0.0:
			next_flash = 8.0 + randf() * 9.0
			flash = 1.0
			_make_bolt()
	flash = maxf(0.0, flash - delta * 2.6)
	queue_redraw()
	glow.queue_redraw()

func _make_bolt() -> void:
	bolt = PackedVector2Array()
	var x := size.x * (0.15 + randf() * 0.7)
	var y := 0.0
	bolt.append(Vector2(x, y))
	while y < 420.0:
		y += 30.0 + randf() * 40.0
		x += randf_range(-50.0, 50.0)
		bolt.append(Vector2(x, y))

func _draw() -> void:
	if pal.is_empty():
		return
	var w := size.x
	var h := size.y
	var a := fade
	# the tint: dark at the top and the bottom (the logo and the buttons), clearer in the middle
	var top: Color = pal["tint_top"]
	var mid: Color = pal["tint_mid"]
	var bot: Color = pal["tint_bot"]
	top.a *= a
	mid.a *= a
	bot.a *= a
	draw_primitive(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.45), Vector2(0, h * 0.45)]),
		PackedColorArray([top, top, mid, mid]), PackedVector2Array())
	draw_primitive(PackedVector2Array([Vector2(0, h * 0.45), Vector2(w, h * 0.45), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([mid, mid, bot, bot]), PackedVector2Array())
	draw_texture_rect(vignette, Rect2(0, 0, w, h), false, Color(1, 1, 1, a))
	# lightning: a bolt far away and the whole sky lit for a moment (twice, fast)
	if flash > 0.0:
		var k := flash * (0.6 + 0.4 * sin(flash * 40.0))
		var fc: Color = pal["flash"]
		draw_rect(Rect2(0, 0, w, h), Color(fc.r, fc.g, fc.b, 0.22 * k))
		if bolt.size() > 1:
			draw_polyline(bolt, Color(fc.r, fc.g, fc.b, 0.85 * k), 4.0)
	var mist: Color = pal["mist"]
	var layers := 1 if tier <= 1 else 3
	# the far mist, behind the seat cards
	if layers > 1:
		_mist(w, 470.0, 150.0, 0.45, 9.0, 0.7, Color(mist, mist.a * 0.6 * a))
	if halloween:
		var n := 2 if tier <= 1 else (5 if tier == 2 else 7)
		for i in n:
			var ph := i * 1.9
			var p := Vector2(fposmod(i * 410.0 + t * (55.0 + i * 11.0), w + 240.0) - 120.0,
				90.0 + (i % 4) * 120.0 + sin(t * (0.9 + i * 0.17) + ph) * 45.0)
			_bat(p, 1.3 + 0.3 * (i % 3), t * 15.0 + ph)
	_mist(w, 770.0, 120.0, 0.9, 16.0, 1.0, Color(mist, mist.a * a))
	if layers > 1:
		_mist(w, 930.0, 90.0, 1.6, 26.0, 1.3, Color(mist, mist.a * 1.2 * a))

# A band of mist: its top edge waves and fades out, the bottom is thickest.
func _mist(w: float, y: float, depth: float, speed: float, wave: float, freq: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := 24
	var clear := Color(col.r, col.g, col.b, 0.0)
	for i in n + 1:
		var x := w * i / n
		pts.append(Vector2(x, y + sin(t * speed * 0.6 + i * freq) * wave + sin(t * speed * 0.23 + i * 2.1) * wave * 0.6))
		cols.append(clear)
	for i in range(n, -1, -1):
		var x := w * i / n
		pts.append(Vector2(x, y + depth + sin(t * speed * 0.4 + i * 1.3) * wave * 0.5))
		cols.append(col)
	draw_polygon(pts, cols)

# A bat: one shape (both wings, the body, the ears), a faint purple copy a little
# bigger behind it (a black bat on the night), two red eyes.
func _bat(p: Vector2, s: float, ph: float) -> void:
	var flap := sin(ph) * 9.0
	var pts := PackedVector2Array([Vector2(0, 7), Vector2(-5, 3), Vector2(-10, 1), Vector2(-17, 4 - flap * 0.4),
		Vector2(-24, -7 - flap), Vector2(-9, -3), Vector2(-5, -6), Vector2(-3, -9), Vector2(-1, -5), Vector2(1, -5),
		Vector2(3, -9), Vector2(5, -6), Vector2(9, -3), Vector2(24, -7 - flap), Vector2(17, 4 - flap * 0.4),
		Vector2(10, 1), Vector2(5, 3)])
	var body := PackedVector2Array()
	var rim := PackedVector2Array()
	for v in pts:
		body.append(p + v * s)
		rim.append(p + v * s * 1.18 + Vector2(0, -0.5) * s)
	draw_colored_polygon(rim, Color(0.62, 0.42, 0.9, 0.6 * fade))
	draw_colored_polygon(body, Color(0.03, 0.01, 0.05, 0.95 * fade))
	draw_rect(Rect2(p + Vector2(-3.2, -3.5) * s, Vector2(1.6, 1.6) * s), Color(1.0, 0.3, 0.15, fade))
	draw_rect(Rect2(p + Vector2(1.6, -3.5) * s, Vector2(1.6, 1.6) * s), Color(1.0, 0.3, 0.15, fade))

# The embers (added light): they rise, sway and fade near the top.
func _paint_glow(c: Control) -> void:
	if pal.is_empty():
		return
	var w := size.x
	var e1: Color = pal["ember"]
	var e2: Color = pal["ember2"]
	for e in embers:
		var y: float = e[1]
		var x: float = e[0] * w + sin(t * 1.3 + e[3]) * 26.0
		var k := clampf(y / 700.0, 0.0, 1.0) * fade
		var col: Color = e2 if e[5] else e1
		var s: float = e[4]
		c.draw_rect(Rect2(x - s * 1.5, y - s * 1.5, s * 3.0, s * 3.0), Color(col.r, col.g, col.b, 0.16 * k))
		c.draw_rect(Rect2(x - s * 0.5, y - s * 0.5, s, s), Color(col.r, col.g, col.b, 0.9 * k))

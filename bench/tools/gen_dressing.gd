# ==============================================================================
# The look polish of 2026-10-25: new art as PNG files in res://assets/. Our own
# pixel art, drawn by code, so nothing from TowerFall is copied:
#   bg_castle_far.png  480 x 270 (drawn x4): the castle arenas' night sky: stars, a
#                      small moon with craters, thin clouds, far hills and towers with lit windows
#   bg_castle_mid.png  960 x 540 (drawn x2): the hall's arcade: brick pillars and arches,
#                      red banners with a gold tower, ivy
#   fx_arrows2.png     32 x 40: the arrows, one 32 x 8 row a kind, the same layout as
#                      fx_arrows.png (normal, fire, bomb, poison, smoke): a pointed steel
#                      head, an outlined shaft, fletching in the kind's colour
#   godot --headless --path bench --script res://tools/gen_dressing.gd
# The old art (tools/gen_assets.gd) is untouched. The game picks with the switches in
# client/polish.gd. The backdrop is darkened by the night (world.gd: about x0.24 red,
# x0.25 green, x0.43 blue), so these colours look much brighter here than in the game:
# it is kept darker than the blocks, so the play space still stands out.
# ==============================================================================
extends SceneTree

const OUT := "res://assets/"
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]

var img: Image
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.seed = 2510
	_far()
	_save("bg_castle_far.png")
	_mid()
	_save("bg_castle_mid.png")
	_arrows()
	_save("fx_arrows2.png")
	print("gen_dressing: bg_castle_far.png, bg_castle_mid.png, fx_arrows2.png written")
	quit()

func _save(name: String) -> void:
	img.save_png(ProjectSettings.globalize_path(OUT + name))

func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)

func _blend(x: int, y: int, c: Color, a: float) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		var o := img.get_pixel(x, y)
		img.set_pixel(x, y, Color(lerpf(o.r, c.r, a), lerpf(o.g, c.g, a), lerpf(o.b, c.b, a), maxf(o.a, a)))

func _rect(x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			_px(x, y, c)

func _disc(cx: float, cy: float, r: float, c: Color) -> void:
	for y in range(int(cy - r) - 1, int(cy + r) + 2):
		for x in range(int(cx - r) - 1, int(cx + r) + 2):
			if Vector2(x + 0.5 - cx, y + 0.5 - cy).length() <= r:
				_px(x, y, c)

func _dither(x: int, y: int) -> float:
	return (BAYER[(y % 4) * 4 + (x % 4)] + 0.5) / 16.0

# ------------------------------------------------------------------ the far sky
func _far() -> void:
	img = Image.create_empty(480, 270, false, Image.FORMAT_RGBA8)
	var sky := [Color(0.07, 0.06, 0.16), Color(0.09, 0.08, 0.2), Color(0.11, 0.11, 0.25), Color(0.13, 0.15, 0.3),
		Color(0.16, 0.2, 0.34), Color(0.2, 0.27, 0.4)]
	var moon := Vector2(400, 95)
	for y in 270:
		for x in 480:
			var f := clampf(y / 250.0, 0.0, 1.0) * 5.0
			var k := int(f)
			var c: Color = sky[mini(k + (1 if f - k > _dither(x, y) else 0), 5)]
			var d := Vector2(x, y).distance_to(moon)   # the sky brightens near the moon, in dithered steps
			if d < 32.0:
				var g := (1.0 - d / 32.0) * 0.9
				if g > _dither(x + 1, y + 2):
					c = c.lerp(Color(0.26, 0.3, 0.44), 0.35)
			img.set_pixel(x, y, c)
	for i in 170:   # stars, thicker high up
		var x := rng.randi_range(0, 479)
		var y := int(pow(rng.randf(), 1.6) * 200.0)
		var b := rng.randf_range(0.32, 0.85)
		if Vector2(x, y).distance_to(moon) > 20.0:
			_px(x, y, Color(b, b, b * 1.08))
	for i in 9:     # a few bright ones, with a cross
		var x := rng.randi_range(8, 470)
		var y := rng.randi_range(6, 120)
		if Vector2(x, y).distance_to(moon) < 30.0:
			continue
		_px(x, y, Color(1, 1, 1))
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			_blend(x + o.x, y + o.y, Color(0.75, 0.8, 0.95), 0.75)
	# thin clouds: long soft bands, lighter on top near the moon
	for band in [[150.0, 70.0, 210.0], [330.0, 118.0, 150.0], [70.0, 150.0, 120.0], [430.0, 60.0, 90.0]]:
		var cx: float = band[0]
		var cy: float = band[1]
		var half: float = band[2] * 0.5
		for x in range(int(cx - half), int(cx + half)):
			var t := (x - (cx - half)) / (half * 2.0)
			var th := sin(t * PI) * 3.5 + 1.0
			for y in range(int(cy - th), int(cy + th) + 1):
				if _dither(x, y) < 0.8:
					var top := y < cy - th + 1.5
					_blend(x, y, Color(0.24, 0.26, 0.38) if top else Color(0.1, 0.1, 0.19), 0.85)
	# the moon: a lit disc, a shadow crescent low left, craters with lit rims, a bright edge
	_disc(moon.x, moon.y, 12.5, Color(0.6, 0.62, 0.66))
	for y in range(int(moon.y) - 13, int(moon.y) + 14):
		for x in range(int(moon.x) - 13, int(moon.x) + 14):
			var p := Vector2(x + 0.5, y + 0.5)
			if p.distance_to(moon) <= 11.5 and p.distance_to(moon + Vector2(2.5, -2.0)) <= 11.0:
				_px(x, y, Color(0.9, 0.9, 0.82))
	for cr in [[Vector2(-4, -3), 2.6], [Vector2(4, 3), 3.2], [Vector2(-1, 6), 1.8], [Vector2(5, -6), 1.5], [Vector2(-7, 3), 1.4]]:
		var p: Vector2 = moon + cr[0]
		_disc(p.x + 0.6, p.y + 0.6, cr[1], Color(0.97, 0.97, 0.9))
		_disc(p.x, p.y, cr[1], Color(0.72, 0.73, 0.72))
	# far hills, then the far towers on them, with a few lit windows
	for x in 480:
		var h := 222.0 + sin(x * 0.021) * 9.0 + sin(x * 0.057 + 1.3) * 4.0 + sin(x * 0.13) * 1.5
		for y in range(int(h), 270):
			_px(x, y, Color(0.06, 0.075, 0.13) if y > h + 1 else Color(0.11, 0.13, 0.2))
	for tw in [[18, 34, 14, 1], [64, 52, 10, 0], [104, 28, 12, 2], [180, 44, 9, 0], [214, 62, 13, 1], [262, 36, 10, 2],
			[318, 50, 12, 0], [360, 30, 9, 1], [446, 46, 13, 0]]:
		var x0: int = tw[0]
		var hh: int = tw[1]
		var w: int = tw[2]
		var base := 230
		var top := base - hh
		var body := Color(0.045, 0.055, 0.1)
		_rect(x0, top, w, hh + 40, body)
		_rect(x0, top, 1, hh + 40, Color(0.09, 0.1, 0.17))   # a faint edge on the moon's side
		if int(tw[3]) == 1:   # a pointed roof, narrower each row up
			for r in range(0, w / 2 + 2):
				_rect(x0 - 1 + r, top - 1 - r, w + 2 - 2 * r, 1, body)
		elif int(tw[3]) == 2:   # battlements
			for m in range(0, w, 4):
				_rect(x0 + m, top - 3, 2, 3, body)
		for wdw in 2:   # lit windows
			if rng.randf() < 0.75:
				var wx := x0 + rng.randi_range(2, maxi(2, w - 3))
				var wy := top + rng.randi_range(5, maxi(5, hh - 8))
				_rect(wx, wy, 1, 2, Color(1.0, 0.72, 0.36))

# ------------------------------------------------------------------ the hall's arcade
const MORTAR := Color(0.06, 0.065, 0.11)
const RIM := Color(0.22, 0.23, 0.31)

func _brick_tone(seed_v: int) -> Color:
	var r := RandomNumberGenerator.new()
	r.seed = seed_v * 7919 + 13
	var k := r.randf_range(-0.025, 0.025)
	return Color(0.135 + k, 0.14 + k, 0.205 + k * 1.2)

func _mid() -> void:
	img = Image.create_empty(960, 540, false, Image.FORMAT_RGBA8)
	var spring := 92          # where the arches start
	var pw := 36              # a pillar's width
	var pillars: Array = []
	for k in 6:
		pillars.append(62 + 160 * k)
	# the wall above the arches (bricks), then the arch openings cut out of it
	for y in range(0, spring):
		for x in 960:
			_stone(x, y, 0)
	for k in range(-1, 6):
		var left: int = (62 + 160 * k) + pw
		var right: int = 62 + 160 * (k + 1)
		var cx := (left + right) / 2.0
		var r := (right - left) / 2.0
		for y in range(0, spring + 1):
			for x in range(maxi(0, left), mini(960, right)):
				var d := Vector2(x + 0.5 - cx, y + 0.5 - spring).length()
				if d < r:
					img.set_pixel(x, y, Color(0, 0, 0, 0))
				elif d < r + 11.0:   # the arch's stones: lighter, with joints that point to its middle
					var ang := atan2(y + 0.5 - spring, x + 0.5 - cx)
					var joint := fposmod(ang * 180.0 / PI, 11.0) < 1.2 or d > r + 10.0
					var c := MORTAR if joint else Color(0.155, 0.16, 0.23)
					if d < r + 1.5:
						c = RIM   # the inner edge catches the light
					img.set_pixel(x, y, c)
	# the pillars: bricks, a lit left edge, a shaded right side, a capital at the spring
	for k in 6:
		var x0: int = pillars[k]
		for y in range(spring, 540):
			for x in range(x0, x0 + pw):
				_stone(x, y, k + 1)
				var lx := x - x0
				if lx < 2:
					img.set_pixel(x, y, RIM)
				elif lx >= pw - 5:
					var o := img.get_pixel(x, y)
					img.set_pixel(x, y, o.darkened(0.35))
		_rect(x0 - 5, spring - 2, pw + 10, 7, Color(0.17, 0.175, 0.25))   # the capital
		_rect(x0 - 5, spring - 2, pw + 10, 1, RIM)
		_rect(x0 - 5, spring + 4, pw + 10, 1, MORTAR)
		_rect(x0 - 3, spring + 5, pw + 6, 3, Color(0.11, 0.115, 0.17))
	# banners on four pillars, ivy on two
	for k in [0, 2, 3, 5]:
		_banner(pillars[k] + pw / 2, spring + 14, k % 2)
	for k in [1, 4]:
		_ivy(pillars[k], pw, spring + 60 + k * 17)

func _stone(x: int, y: int, part: int) -> void:
	var row := y / 7
	var off := 0 if row % 2 == 0 else 8
	var col := (x + off) / 16
	if y % 7 == 6 or (x + off) % 16 == 15:
		img.set_pixel(x, y, MORTAR)
	else:
		img.set_pixel(x, y, _brick_tone(row * 131 + col * 17 + part * 1009))

func _banner(cx: int, top: int, kind: int) -> void:
	var w := 26
	var h := 112
	var x0 := cx - w / 2
	var red := Color(0.44, 0.07, 0.1)
	var red_hi := Color(0.52, 0.1, 0.12)
	var red_lo := Color(0.32, 0.05, 0.08)
	var gold := Color(0.66, 0.48, 0.17)
	_rect(x0 - 4, top - 2, w + 8, 2, Color(0.1, 0.08, 0.08))       # the rod
	_px(x0 - 5, top - 2, gold)
	_px(x0 + w + 4, top - 2, gold)
	for y in range(top, top + h):
		var cut := 0
		if y > top + h - 14:   # a swallowtail end: a notch that grows to the bottom
			cut = y - (top + h - 14)
		for x in range(x0, x0 + w):
			var lx := x - x0
			var mid := absi(lx - w / 2)
			if y > top + h - 14 and mid < cut:
				continue
			var fold := (lx / 4) % 3
			var c := red_hi if fold == 0 else (red if fold == 1 else red_lo)
			if lx < 2 or lx >= w - 2 or y < top + 2:
				c = gold
			elif y > top + h - 14 and mid < cut + 2:
				c = gold   # the trim follows the cut
			_px(x, y, c)
	# the emblem: a small gold tower with battlements (kind 0) or a gold crown (kind 1)
	var ey := top + 30
	if kind == 0:
		_rect(cx - 5, ey, 10, 14, gold)
		for m in [-5, -1, 3]:
			_rect(cx + m, ey - 3, 2, 3, gold)
		_rect(cx - 1, ey + 8, 2, 6, red_lo)   # the door
	else:
		_rect(cx - 7, ey + 6, 14, 6, gold)
		for m in [-7, -1, 5]:
			_rect(cx + m, ey, 2, 6, gold)
		_px(cx, ey + 8, red_lo)
	_rect(cx - 8, ey + 22, 16, 1, gold)   # a line under it

func _ivy(x0: int, pw: int, top: int) -> void:
	var leaf_a := Color(0.16, 0.3, 0.15)
	var leaf_b := Color(0.22, 0.4, 0.19)
	var stem := Color(0.12, 0.2, 0.1)
	for side in [0, 1]:
		var phase := float(side) * 2.0
		for y in range(top + side * 30, 540):
			var x := x0 + (4 if side == 0 else pw - 6) + int(sin(y * 0.09 + phase) * 3.0)
			_px(x, y, stem)
			if y % 5 == 0 and rng.randf() < 0.85:
				var lx := x + (rng.randi_range(-3, 1))
				var c := leaf_b if rng.randf() < 0.45 else leaf_a
				_rect(lx, y, 3, 2, c)
				_px(lx + 1, y - 1, c)

# ------------------------------------------------------------------ the arrows
const KIND := [   # [fletching, fletching shade, head, head light, head dark]
	[Color(0.93, 0.92, 0.88), Color(0.7, 0.7, 0.72), Color(0.78, 0.82, 0.88), Color(0.97, 0.98, 1.0), Color(0.48, 0.52, 0.6)],
	[Color(1.0, 0.55, 0.18), Color(0.8, 0.25, 0.08), Color(1.0, 0.7, 0.2), Color(1.0, 0.95, 0.6), Color(0.85, 0.3, 0.08)],
	[Color(0.95, 0.3, 0.25), Color(0.6, 0.12, 0.12), Color(0.2, 0.18, 0.24), Color(0.45, 0.42, 0.5), Color(0.08, 0.07, 0.1)],
	[Color(0.62, 0.3, 0.95), Color(0.36, 0.14, 0.6), Color(0.55, 0.85, 0.35), Color(0.8, 1.0, 0.6), Color(0.3, 0.5, 0.2)],
	[Color(0.75, 0.77, 0.82), Color(0.5, 0.52, 0.58), Color(0.46, 0.48, 0.54), Color(0.7, 0.72, 0.78), Color(0.28, 0.29, 0.34)],
]
const INK := Color(0.08, 0.06, 0.09)

func _arrows() -> void:
	img = Image.create_empty(32, 40, false, Image.FORMAT_RGBA8)
	for k in 5:
		var oy := k * 8
		var kc: Array = KIND[k]
		# the shaft, outlined, with a lighter top
		_rect(4, oy + 2, 21, 1, INK)
		_rect(4, oy + 5, 21, 1, INK)
		_rect(4, oy + 3, 21, 1, Color(0.8, 0.58, 0.32))
		_rect(4, oy + 4, 21, 1, Color(0.55, 0.36, 0.18))
		# the fletching: two slanted vanes and the nock
		for v in [[oy + 1, 1], [oy + 6, -1]]:
			var y: int = v[0]
			_rect(1, y, 7, 1, kc[0])
			_rect(3, y - int(v[1]), 6, 1, kc[1])
		_rect(0, oy + 3, 2, 2, INK)
		match k:
			0:   # a steel head: a point with barbs, lit on top
				_head(oy, kc)
			1:   # fire: a glowing head and a lick of flame
				_head(oy, kc)
				_px(27, oy + 1, Color(1.0, 0.85, 0.3))
				_px(25, oy, Color(1.0, 0.6, 0.15))
			2:   # a bomb: a round black head, a fuse with a spark
				_rect(25, oy + 2, 5, 4, kc[2])
				_rect(26, oy + 1, 3, 6, kc[2])
				_px(26, oy + 2, kc[3])
				_px(29, oy + 1, Color(0.6, 0.45, 0.3))
				_px(30, oy, Color(1.0, 0.9, 0.4))
			3:   # poison: a glass vial with green inside
				_rect(25, oy + 1, 6, 6, INK)
				_rect(26, oy + 2, 4, 4, kc[2])
				_px(26, oy + 2, kc[3])
				_rect(30, oy + 3, 2, 2, Color(0.7, 0.55, 0.4))
			4:   # smoke: a grey canister with a band
				_rect(24, oy + 1, 7, 6, INK)
				_rect(25, oy + 2, 5, 4, kc[2])
				_rect(25, oy + 2, 5, 1, kc[3])
				_rect(27, oy + 2, 1, 4, kc[4])

func _head(oy: int, kc: Array) -> void:
	# rows from the middle out: the point is 2 px thick at the tip (x 31)
	_rect(23, oy + 3, 9, 1, kc[3])
	_rect(23, oy + 4, 8, 1, kc[2])
	_rect(23, oy + 2, 6, 1, kc[2])
	_rect(23, oy + 5, 6, 1, kc[4])
	_rect(23, oy + 1, 3, 1, kc[4])
	_rect(23, oy + 6, 3, 1, kc[4])
	_px(31, oy + 4, INK)
	_px(29, oy + 2, INK)
	_px(29, oy + 5, INK)

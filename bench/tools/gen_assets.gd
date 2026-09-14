# ==============================================================================
# Makes the benchmark's stand-in art as PNG files in res://assets/. Our own
# pixel art, drawn by code, so nothing from TowerFall or Dead Cells is copied:
#   fighter_p0..7.png  13 frames x 128 px, a 90 px hooded archer per player colour
#   fighter_n.png      the normal map for those frames (shared)
#   tiles.png, tiles_n.png   stone, mossy stone tops, plank ledges (30 px) + normals
#   bg_far.png (480 x 270, drawn x4), bg_mid.png (960 x 540, drawn x2)
#   fx_*.png           particles, glows, arrows, a torch, a scorch mark, noise
#   godot --headless --path bench --script res://tools/gen_assets.gd
# The look: hard pixels, a dark outline, 2-3 tones per colour, glowing eyes,
# saturated player colours on a cool, dark castle.
# ==============================================================================
extends SceneTree

const CELL := 128
const FEET := 122
const OUT := "res://assets/"
const TEAM := [Color("e8413c"), Color("3c8ce8"), Color("5fd35a"), Color("f2c230"),
	Color("a85ae8"), Color("f08a2c"), Color("35d6d0"), Color("f06aa8")]
const OUTLINE := Color(0.05, 0.04, 0.08)
const CLOTH := Color("2e3350")
const CLOTH_D := Color("1e2136")
const SKIN := Color("e0a37c")
const LEATHER := Color("7a4a2a")
const LEATHER_D := Color("51301c")
const METAL := Color("c3cad6")
const WOOD := Color("a8743e")
const EYE := Color("fff6a8")
const FACE := Color("140f1e")

# The frames, 16 a row, 2 rows (2048 x 256). A pose: hip (offset of the hips),
# tilt (degrees the body leans forward, negative = back), lf / rf (feet, from the
# centre of the cell's floor), cape (where the hem swings), bow / back (the two
# arms' angles, degrees), no_bow, hands ("up" = hanging, "fwd" = pulling up).
# Special frames: roll (a ball, turned 90 degrees a frame) and dead (lying).
const COLS := 16
const FRAMES := [
	{"lf": Vector2(-8, 0), "rf": Vector2(8, 0), "bow": 0},                                                  # 0 idle
	{"hip": Vector2(0, 1), "lf": Vector2(-8, 0), "rf": Vector2(8, 0), "cape": Vector2(-2, 1), "bow": 4},    # 1 idle
	{"hip": Vector2(0, -2), "tilt": 8, "lf": Vector2(-16, -3), "rf": Vector2(14, 0), "cape": Vector2(-8, -5), "bow": 10},   # 2 run
	{"hip": Vector2(0, -3), "tilt": 10, "lf": Vector2(-6, -8), "rf": Vector2(6, 0), "cape": Vector2(-10, -7), "bow": 14},   # 3 run
	{"hip": Vector2(0, -1), "tilt": 8, "lf": Vector2(8, -2), "rf": Vector2(-12, -4), "cape": Vector2(-9, -4), "bow": 8},    # 4 run
	{"hip": Vector2(0, -2), "tilt": 8, "lf": Vector2(14, 0), "rf": Vector2(-16, -3), "cape": Vector2(-8, -5), "bow": 10},   # 5 run
	{"hip": Vector2(0, -3), "tilt": 10, "lf": Vector2(6, 0), "rf": Vector2(-6, -8), "cape": Vector2(-10, -7), "bow": 14},   # 6 run
	{"hip": Vector2(0, -1), "tilt": 8, "lf": Vector2(-12, -4), "rf": Vector2(8, -2), "cape": Vector2(-9, -4), "bow": 8},    # 7 run
	{"hip": Vector2(0, -4), "lf": Vector2(-10, -14), "rf": Vector2(10, -10), "cape": Vector2(-4, 8), "bow": -12},           # 8 jump
	{"hip": Vector2(0, -2), "lf": Vector2(-12, 2), "rf": Vector2(12, -2), "cape": Vector2(-2, -14), "bow": 20},             # 9 fall
	{"lf": Vector2(-10, 0), "rf": Vector2(10, 0), "cape": Vector2(-3, 0), "bow": -35},                                     # 10 aim
	{"hip": Vector2(-4, -2), "tilt": -26, "lf": Vector2(-16, -4), "rf": Vector2(10, 0), "cape": Vector2(10, -8), "bow": -70, "back": -125},  # 11 hit
	{"hip": Vector2(0, 5), "tilt": -12, "lf": Vector2(-13, 0), "rf": Vector2(12, 0), "cape": Vector2(5, -4), "bow": 35, "back": 70},         # 12 hit, flinch
	{"hip": Vector2(0, -12), "tilt": 60, "lf": Vector2(-32, -22), "rf": Vector2(-22, -32), "cape": Vector2(-28, -18), "bow": 0, "back": 10}, # 13 air dash
	{"roll": 0}, {"roll": 1}, {"roll": 2}, {"roll": 3},                                                                     # 14-17 roll
	# -- second row --
	{"hip": Vector2(0, 2), "tilt": 10, "lf": Vector2(-6, 0), "rf": Vector2(15, -14), "cape": Vector2(-4, -16), "bow": -25, "back": -45},     # 16 -> index 18 wall slide
	{"hip": Vector2(4, -6), "tilt": -18, "lf": Vector2(-22, -6), "rf": Vector2(-14, -18), "cape": Vector2(8, -10), "bow": 20, "back": -100}, # 19 wall jump
	{"lf": Vector2(-4, 0), "rf": Vector2(5, 2), "cape": Vector2(-2, 2), "no_bow": true, "hands": "up"},                                    # 20 ledge hang
	{"hip": Vector2(0, -18), "tilt": 35, "lf": Vector2(-8, -8), "rf": Vector2(10, -22), "cape": Vector2(-6, -4), "no_bow": true, "hands": "fwd"},  # 21 ledge pull
	{"tilt": -36, "lf": Vector2(-18, -6), "rf": Vector2(12, -2), "cape": Vector2(10, -12), "bow": -80, "back": -150, "no_bow": true},       # 22 death: hit
	{"hip": Vector2(0, -16), "tilt": -72, "lf": Vector2(-24, -30), "rf": Vector2(-8, -38), "cape": Vector2(16, -20), "bow": -130, "back": 160, "no_bow": true},  # 23 death: thrown
	{"hip": Vector2(6, -22), "tilt": -96, "lf": Vector2(-34, -34), "rf": Vector2(-30, -24), "cape": Vector2(18, -24), "bow": 170, "back": -170, "no_bow": true}, # 24 death: falling
	{"dead": true, "bounce": 7},                                                                                                            # 25 death: impact
	{"dead": true},                                                                                                                         # 26 dead
	{"hip": Vector2(0, 9), "lf": Vector2(-13, 0), "rf": Vector2(13, 0), "cape": Vector2(0, 3), "bow": 25},                                  # 27 spawn crouch
]

var img: Image

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var t0 := Time.get_ticks_msec()
	var normal_done := false
	var rows := int(ceil(FRAMES.size() / float(COLS)))
	for team_i in TEAM.size():
		img = Image.create_empty(CELL * COLS, CELL * rows, false, Image.FORMAT_RGBA8)
		for fi in FRAMES.size():
			var ox := (fi % COLS) * CELL
			var oy := (fi / COLS) * CELL
			_draw_fighter(ox, oy, FRAMES[fi], TEAM[team_i])
			_outline_and_shade(ox, oy)
		_save("fighter_p%d.png" % team_i)
		if not normal_done:
			_save_image(_normals_from_alpha(img, 5.0, CELL), "fighter_n.png")
			normal_done = true
	_make_tiles()
	_make_backgrounds()
	_make_fx()
	print("🎨 [GenAssets] %d frames, done in %d ms -> %s" % [FRAMES.size(), Time.get_ticks_msec() - t0, ProjectSettings.globalize_path(OUT)])
	quit()

func _save(name: String) -> void:
	_save_image(img, name)

func _save_image(i: Image, name: String) -> void:
	var err := i.save_png(ProjectSettings.globalize_path(OUT + name))
	if err != OK:
		printerr("cannot save ", name, " error ", err)

# --------------------------------------------------------------- drawing kit
func _px(x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)

func _rect(x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(xx, yy, c)

func _ellipse(cx: int, cy: int, rx: int, ry: int, c: Color) -> void:
	for y in range(-ry, ry + 1):
		for x in range(-rx, rx + 1):
			if float(x * x) / float(rx * rx) + float(y * y) / float(ry * ry) <= 1.0:
				_px(cx + x, cy + y, c)

func _ellipse_r(center: Vector2, rx: float, ry: float, ang: float, c: Color) -> void:
	var m := int(ceil(maxf(rx, ry)))
	for y in range(-m, m + 1):
		for x in range(-m, m + 1):
			var q := Vector2(x, y).rotated(-ang)
			if q.x * q.x / (rx * rx) + q.y * q.y / (ry * ry) <= 1.0:
				_px(int(round(center.x)) + x, int(round(center.y)) + y, c)

func _thick(a: Vector2, b: Vector2, r: float, c: Color) -> void:
	var steps := int(a.distance_to(b)) + 1
	var ri := int(ceil(r))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if dx * dx + dy * dy <= r * r:
					_px(int(round(p.x)) + dx, int(round(p.y)) + dy, c)

func _poly(points: Array, c: Color) -> void:
	var pv := PackedVector2Array(points)
	var r := Rect2(pv[0], Vector2.ZERO)
	for p in pv:
		r = r.expand(p)
	for y in range(int(r.position.y) - 1, int(r.end.y) + 2):
		for x in range(int(r.position.x) - 1, int(r.end.x) + 2):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pv):
				_px(x, y, c)

func _sq(p: Vector2, size: int, c: Color) -> void:
	_rect(int(round(p.x)), int(round(p.y)), size, size, c)

# --------------------------------------------------------------- the archer
func _draw_fighter(ox: int, oy: int, fr: Dictionary, team: Color) -> void:
	var bx := ox + 64
	var floor_y := oy + FEET
	var team_d := team.darkened(0.38)
	var team_l := team.lightened(0.3)
	if fr.has("dead"):
		_draw_dead(bx, floor_y - int(fr.get("bounce", 0)), team, team_d)
		return
	if fr.has("roll"):
		_draw_roll(ox, oy, int(fr["roll"]), team, team_d, team_l)
		return
	var tilt := deg_to_rad(float(fr.get("tilt", 0)))
	var hip := Vector2(bx - 2, floor_y - 36) + (fr.get("hip", Vector2.ZERO) as Vector2)
	var up := Vector2(0, -1).rotated(tilt)
	var right := Vector2(-up.y, up.x)
	var sh := hip + up * 26.0
	var L := func(u: float, v: float) -> Vector2: return hip + right * u + up * v
	var cape: Vector2 = fr.get("cape", Vector2.ZERO)
	# the cape hangs from the shoulders, behind everything
	_poly([L.call(-8, 32), L.call(8, 30), hip + Vector2(-2 + cape.x * 0.5, 22 + cape.y), hip + Vector2(-24 + cape.x * 1.6, 18 + cape.y * 1.2)], team_d)
	_poly([L.call(-8, 32), L.call(-2, 31), hip + Vector2(-14 + cape.x, 20 + cape.y)], team_d.darkened(0.2))
	# the quiver and its fletchings
	_poly([L.call(-17, 30), L.call(-10, 30), L.call(-10, 6), L.call(-17, 6)], LEATHER_D)
	_poly([L.call(-18, 36), L.call(-15, 36), L.call(-15, 30), L.call(-18, 30)], team_l)
	_poly([L.call(-14, 37), L.call(-11, 37), L.call(-11, 30), L.call(-14, 30)], METAL)
	# legs, the back one darker
	_leg(hip - right * 5.0, Vector2(bx, floor_y) + (fr.get("lf", Vector2(-8, 0)) as Vector2), CLOTH_D)
	_leg(hip + right * 5.0, Vector2(bx, floor_y) + (fr.get("rf", Vector2(8, 0)) as Vector2), CLOTH)
	# the body, the chest stripe, the belt
	_poly([L.call(-13, 27), L.call(13, 27), L.call(12, -5), L.call(-12, -5)], CLOTH)
	_poly([L.call(-3, 26), L.call(4, 26), L.call(3, -4), L.call(-3, -4)], team)
	_poly([L.call(-13, 3), L.call(13, 3), L.call(13, -2), L.call(-13, -2)], LEATHER)
	_poly([L.call(-2, 3), L.call(3, 3), L.call(3, -2), L.call(-2, -2)], METAL)
	var hands: String = fr.get("hands", "")
	var no_bow: bool = fr.get("no_bow", false)
	var bow_ang := deg_to_rad(float(fr.get("bow", 0)))
	var back_ang := deg_to_rad(float(fr.get("back", fr.get("bow", 0))))
	var hand := sh + Vector2(21, 7).rotated(bow_ang)
	var back_hand := sh + Vector2(11, 9).rotated(back_ang)
	if hands == "up":
		hand = sh + up * 30.0 + right * 7.0
		back_hand = sh + up * 30.0 - right * 6.0
	elif hands == "fwd":
		hand = sh + up * 16.0 + right * 16.0
		back_hand = sh + up * 12.0 + right * 10.0
	# the back arm
	_thick(sh - right * 2.0 - up * 4.0, back_hand, 3.0, CLOTH_D)
	if hands != "":
		_sq(back_hand - Vector2(2, 2), 5, SKIN)
	# the hood and the face
	var head := sh + up * 14.0 + right * 3.0
	_poly([head - right * 8.0 + up * 10.0, head + up * 13.0, head - right * 22.0 - up * 4.0], team)
	_ellipse_r(head - right * 3.0 - up * 1.0, 11, 12, tilt, team_d)
	_ellipse_r(head, 13, 14, tilt, team)
	_ellipse_r(head + right * 6.0 - up * 2.0, 7, 9, tilt, FACE)
	_sq(head + right * 4.0 - up * 1.0, 2, EYE)
	_sq(head + right * 9.0 - up * 1.0, 2, EYE)
	_poly([head - right * 8.0 + up * 9.0, head - right * 2.0 + up * 9.0, head - right * 2.0 + up * 7.0, head - right * 8.0 + up * 7.0], team_l)
	# the bow arm and the bow (or a dropped / slung bow)
	_thick(sh + right * 6.0 - up * 2.0, hand, 3.2, CLOTH)
	if not no_bow:
		_bow(hand, bow_ang)
	else:
		_thick(L.call(-16, 34), L.call(6, -2), 1.4, WOOD)
	_sq(hand - Vector2(2, 2), 5, SKIN)

func _leg(hip: Vector2, foot: Vector2, c: Color) -> void:
	var mid := (hip + foot) * 0.5 + Vector2(4, 0)
	_thick(hip, mid, 4.5, c)
	_thick(mid, foot + Vector2(0, -7), 4.0, c)
	_rect(int(foot.x) - 5, int(foot.y) - 9, 11, 9, LEATHER)
	_rect(int(foot.x) + 4, int(foot.y) - 5, 4, 5, LEATHER_D)

func _bow(hand: Vector2, ang: float) -> void:
	var prev := Vector2.ZERO
	var tip_a := Vector2.ZERO
	var tip_b := Vector2.ZERO
	for i in 27:
		var yy := -26.0 + i * 2.0
		var p := hand + Vector2(7.0 - yy * yy / 110.0, yy).rotated(ang)
		if i > 0:
			_thick(prev, p, 1.6, WOOD)
		prev = p
		if i == 0:
			tip_a = p
		tip_b = p
	_sq(tip_a - Vector2(1, 1), 3, METAL)
	_sq(tip_b - Vector2(1, 1), 3, METAL)
	var steps := int(tip_a.distance_to(tip_b))
	for i in steps:
		var p := tip_a.lerp(tip_b, float(i) / steps) + Vector2(-2, 0).rotated(ang)
		_px(int(p.x), int(p.y), Color(0.9, 0.9, 0.85))

# A roll: the archer curled into a ball, drawn once on a small image and turned
# 90 degrees per frame, its bottom on the floor line.
func _draw_roll(ox: int, oy: int, turn: int, team: Color, team_d: Color, team_l: Color) -> void:
	var sheet := img
	img = Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	_ellipse(32, 32, 24, 23, team_d)
	_ellipse(30, 34, 18, 16, CLOTH)
	_rect(14, 34, 34, 4, LEATHER)
	_ellipse(22, 44, 7, 6, LEATHER)
	_ellipse(34, 48, 7, 5, LEATHER_D)
	_ellipse(42, 22, 13, 12, team)
	_ellipse(46, 25, 6, 7, FACE)
	_rect(44, 24, 2, 2, EYE)
	_rect(49, 24, 2, 2, EYE)
	_rect(36, 12, 6, 2, team_l)
	_thick(Vector2(12, 50), Vector2(50, 54), 1.5, WOOD)
	for _i in turn:
		img.rotate_90(CLOCKWISE)
	var ball := img
	img = sheet
	img.blend_rect(ball, Rect2i(0, 0, 64, 64), Vector2i(ox + 32, oy + FEET - 58))

func _draw_dead(bx: int, floor_y: int, team: Color, team_d: Color) -> void:
	var y := floor_y - 8
	_poly([Vector2(bx - 34, y + 6), Vector2(bx + 26, y + 2), Vector2(bx + 30, y + 8), Vector2(bx - 30, y + 8)], team_d)
	_rect(bx - 44, y - 2, 16, 8, CLOTH_D)
	_rect(bx - 50, y - 3, 8, 10, LEATHER)
	_rect(bx - 28, y - 7, 44, 13, CLOTH)
	_rect(bx - 6, y - 7, 5, 13, team)
	_ellipse(bx + 28, y - 1, 12, 9, team)
	_ellipse(bx + 32, y, 6, 5, FACE)
	_rect(bx + 30, y - 1, 3, 1, EYE.darkened(0.5))
	_thick(Vector2(bx + 4, y + 8), Vector2(bx + 40, y + 2), 1.5, WOOD)

func _outline_and_shade(ox: int, oy: int) -> void:
	var src := img.get_region(Rect2i(ox, oy, CELL, CELL))
	for y in CELL:
		for x in CELL:
			var c := src.get_pixel(x, y)
			if c.a > 0.5:
				var up := src.get_pixel(x, y - 1).a if y > 0 else 0.0
				var left := src.get_pixel(x - 1, y).a if x > 0 else 0.0
				var down := src.get_pixel(x, y + 1).a if y < CELL - 1 else 0.0
				var right := src.get_pixel(x + 1, y).a if x < CELL - 1 else 0.0
				if up < 0.5 or left < 0.5:
					c = c.lightened(0.22)
				elif down < 0.5 or right < 0.5:
					c = c.darkened(0.25)
				img.set_pixel(ox + x, oy + y, c)
			else:
				var n := 0.0
				if y > 0: n += src.get_pixel(x, y - 1).a
				if y < CELL - 1: n += src.get_pixel(x, y + 1).a
				if x > 0: n += src.get_pixel(x - 1, y).a
				if x < CELL - 1: n += src.get_pixel(x + 1, y).a
				if n > 0.5:
					img.set_pixel(ox + x, oy + y, OUTLINE)

# A pillow normal map from the alpha: the distance to the edge is the height.
func _normals_from_alpha(src: Image, depth: float, cell: int) -> Image:
	var w := src.get_width()
	var h := src.get_height()
	var dist := PackedFloat32Array()
	dist.resize(w * h)
	for y in h:
		for x in w:
			dist[y * w + x] = 999.0 if src.get_pixel(x, y).a > 0.5 else 0.0
	for _pass in 2:
		for y in h:
			for x in w:
				var i := y * w + x
				if dist[i] == 0.0:
					continue
				var d := dist[i]
				if x % cell > 0: d = minf(d, dist[i - 1] + 1.0)
				if y % cell > 0: d = minf(d, dist[i - w] + 1.0)
				dist[i] = d
		for y in range(h - 1, -1, -1):
			for x in range(w - 1, -1, -1):
				var i := y * w + x
				if dist[i] == 0.0:
					continue
				var d := dist[i]
				if x % cell < cell - 1: d = minf(d, dist[i + 1] + 1.0)
				if y % cell < cell - 1: d = minf(d, dist[i + w] + 1.0)
				dist[i] = d
	var out := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var i := y * w + x
			if dist[i] == 0.0:
				out.set_pixel(x, y, Color(0.5, 0.5, 1.0, 0.0))
				continue
			var hl := minf(dist[i - 1] if x % cell > 0 else 0.0, depth) / depth
			var hr := minf(dist[i + 1] if x % cell < cell - 1 else 0.0, depth) / depth
			var hu := minf(dist[i - w] if y % cell > 0 else 0.0, depth) / depth
			var hd := minf(dist[i + w] if y % cell < cell - 1 else 0.0, depth) / depth
			var n := Vector3((hl - hr) * 2.0, (hd - hu) * 2.0, 1.0).normalized()
			out.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	return out

# --------------------------------------------------------------- tiles
func _make_tiles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	img = Image.create_empty(120, 90, false, Image.FORMAT_RGBA8)
	var height := Image.create_empty(120, 90, false, Image.FORMAT_RGBA8)
	var stone := Color("2a3047")
	var mortar := Color("141827")
	for v in 4:
		for top in 2:
			var ox := v * 30
			var oy := top * 30
			for y in 30:
				for x in 30:
					var row := y / 15
					var off := (v * 7 + row * 11) % 30
					var bxp := (x + off) % 15
					var edge := y % 15 == 0 or bxp == 0
					var c := mortar if edge else stone
					var hgt := 0.0 if edge else 1.0
					if not edge:
						if y % 15 == 1 or bxp == 1:
							c = stone.lightened(0.18)
						elif y % 15 == 14 or bxp == 14:
							c = stone.darkened(0.25)
						var r := rng.randf()
						if r < 0.07:
							c = c.lightened(0.12)
						elif r < 0.14:
							c = c.darkened(0.15)
						if v >= 2 and rng.randf() < 0.10 and y > 12:
							c = Color("2f6b5c").darkened(rng.randf() * 0.3)
					if top == 1 and y < 5:
						c = Color("4fae7d") if (y < 3 or rng.randf() < 0.5) else Color("2f6b5c")
						if y == 0:
							c = Color("8fe0a8")
						hgt = 1.0
					if top == 1 and y >= 5 and y < 9 and rng.randf() < 0.18:
						c = Color("3d8a66")
					img.set_pixel(ox + x, oy + y, c)
					height.set_pixel(ox + x, oy + y, Color(hgt, hgt, hgt, 1.0))
	for v in 4:
		var ox := v * 30
		for y in 30:
			for x in 30:
				var c := Color(0, 0, 0, 0)
				var hgt := 0.0
				if y < 12:
					c = Color("8a5a32")
					if y == 0:
						c = Color("c98f55")
					elif y == 1:
						c = Color("a8743e")
					elif y == 11:
						c = Color("4a2c18")
					elif (x + v * 5) % 10 == 0:
						c = Color("5e3a20")
					elif rng.randf() < 0.1:
						c = c.darkened(0.15)
					if (x == 4 or x == 25) and y == 5:
						c = METAL
					hgt = 1.0
				elif v == 3 and x > 10 and x < 20 and y < 12 + (20 - x):
					c = Color("3a3f52")
					hgt = 0.6
				img.set_pixel(ox + x, 60 + y, c)
				height.set_pixel(ox + x, 60 + y, Color(hgt, hgt, hgt, 1.0 if c.a > 0.0 else 0.0))
	_save("tiles.png")
	var nm := Image.create_empty(120, 90, false, Image.FORMAT_RGBA8)
	for y in 90:
		for x in 120:
			var hl := height.get_pixel(maxi(x - 1, 0), y).r
			var hr := height.get_pixel(mini(x + 1, 119), y).r
			var hu := height.get_pixel(x, maxi(y - 1, 0)).r
			var hd := height.get_pixel(x, mini(y + 1, 89)).r
			var n := Vector3((hl - hr) * 1.5, (hd - hu) * 1.5, 1.0).normalized()
			nm.set_pixel(x, y, Color(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5, 1.0))
	_save_image(nm, "tiles_n.png")

# --------------------------------------------------------------- backgrounds
func _make_backgrounds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	img = Image.create_empty(480, 270, false, Image.FORMAT_RGBA8)
	var top := Color("0a0718")
	var mid := Color("1d1640")
	var hor := Color("1f4a5e")
	for y in 270:
		for x in 480:
			var t := y / 269.0
			var c := top.lerp(mid, t * 1.6) if t < 0.6 else mid.lerp(hor, (t - 0.6) / 0.4)
			var b: int = bayer[(y % 4) * 4 + x % 4]
			c = c.lightened(0.04) if b > 10 and (y % 23 < 11) else c
			img.set_pixel(x, y, c)
	for i in 90:
		var sx := rng.randi() % 480
		var sy := rng.randi() % 150
		img.set_pixel(sx, sy, Color(0.8, 0.85, 1.0).darkened(rng.randf() * 0.5))
	for y in range(-40, 41):
		for x in range(-40, 41):
			var d := sqrt(float(x * x + y * y))
			var mx := 320 + x     # between two pillars of bg_mid, below its arches
			var my := 120 + y
			if mx < 0 or my < 0 or mx >= 480 or my >= 270:
				continue
			var b: int = bayer[(my % 4) * 4 + mx % 4]
			if d < 18.0:
				img.set_pixel(mx, my, Color("e8e6c8") if d < 16.0 or b > 6 else Color("b8b89c"))
			elif d < 40.0 and b < int((40.0 - d) / 22.0 * 16.0) and b % 2 == 0:
				img.set_pixel(mx, my, img.get_pixel(mx, my).lerp(Color("6a6a8a"), 0.35))
	var sil := Color("0c1024")
	var x := 0
	while x < 480:
		var w := rng.randi_range(18, 46)
		var hgt := rng.randi_range(40, 110)
		for yy in range(270 - hgt, 270):
			for xx in range(x, mini(x + w, 480)):
				img.set_pixel(xx, yy, sil)
		for cx in range(x, mini(x + w, 480), 6):
			for yy in range(270 - hgt - 4, 270 - hgt):
				for xx in range(cx, mini(cx + 3, 480)):
					img.set_pixel(xx, yy, sil)
		if rng.randf() < 0.7:
			img.set_pixel(x + w / 2, 270 - hgt + 12, Color("f0b060"))
			img.set_pixel(x + w / 2, 270 - hgt + 13, Color("c07a30"))
		x += w + rng.randi_range(2, 20)
	_save("bg_far.png")
	img = Image.create_empty(960, 540, false, Image.FORMAT_RGBA8)
	var arch := Color(0.03, 0.035, 0.08, 1.0)
	for i in 6:
		var cx := 80 + i * 160
		for yy in range(60, 540):
			for xx in range(cx - 18, cx + 18):
				img.set_pixel(xx, yy, arch)
		for yy in range(0, 120):
			for xx in range(cx, mini(cx + 160, 960)):
				var ax := float(xx - cx - 80) / 80.0
				var ay := float(yy) / 120.0
				if ay > 0.35 + 0.65 * sqrt(maxf(0.0, 1.0 - ax * ax)) - 0.3 and ay < 0.35 + 0.65 * sqrt(maxf(0.0, 1.0 - ax * ax)):
					img.set_pixel(xx, yy + 20, arch)
		for yy in range(140, 250):
			for xx in range(cx - 10, cx + 10):
				if (xx + yy) % 5 != 0:
					img.set_pixel(xx, yy, Color(0.35, 0.08, 0.12, 1.0) if yy < 240 else arch)
	_save("bg_mid.png")

# --------------------------------------------------------------- effects
func _make_fx() -> void:
	img = Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_save("fx_px.png")
	img = Image.create_empty(8, 8, false, Image.FORMAT_RGBA8)
	_ellipse(4, 4, 3, 3, Color.WHITE)
	_save("fx_dot.png")
	img = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var d := Vector2(x - 7.5, y - 7.5).length()
			if d < 5.5 or (d < 7.5 and (x + y) % 2 == 0):
				img.set_pixel(x, y, Color.WHITE)
	_save("fx_smoke.png")
	img = Image.create_empty(8, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		var half := int(round(3.5 * sin(PI * minf(1.0, (y + 1) / 10.0)) * (1.0 - y / 16.0)))
		for x in range(4 - half, 4 + half):
			img.set_pixel(x, y, Color.WHITE if y > 3 else Color(1, 1, 1, 0.75))
	_save("fx_flame.png")
	img = Image.create_empty(2, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_save("fx_spark.png")
	for spec in [["fx_halo.png", 64, 2.2], ["fx_light.png", 256, 1.6]]:
		var size: int = spec[1]
		img = Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
		for y in size:
			for x in size:
				var d := Vector2(x - size / 2.0 + 0.5, y - size / 2.0 + 0.5).length() / (size / 2.0)
				var a := pow(clampf(1.0 - d, 0.0, 1.0), spec[2])
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_save(spec[0])
	img = Image.create_empty(32, 40, false, Image.FORMAT_RGBA8)
	for k in 5:
		var y := k * 8 + 3
		_rect(4, y, 20, 2, WOOD)
		_rect(1, y - 1, 5, 1, Color("e8e8e8"))
		_rect(1, y + 2, 5, 1, Color("e8e8e8"))
		if k == 0:
			_rect(24, y - 1, 5, 4, METAL)
			_px(29, y, METAL)
			_px(29, y + 1, METAL)
		elif k == 1:
			_rect(22, y - 2, 8, 6, Color("ff9a2a"))
			_rect(24, y - 1, 5, 4, Color("fff0a0"))
		elif k == 2:
			_ellipse(26, y + 1, 4, 3, Color("241c2a"))
			_rect(24, y, 5, 2, Color("e8413c"))
			_px(30, y - 3, Color("ffe070"))
		elif k == 3:
			_rect(22, y - 2, 7, 6, Color("5a2a8a"))
			_rect(23, y - 1, 5, 4, Color("c070ff"))
		else:
			_rect(21, y - 2, 9, 6, Color("4a4e58"))
			_rect(22, y - 1, 7, 1, Color("9aa2b0"))
			_rect(24, y + 1, 3, 2, Color("d8dde6"))
			_px(30, y - 3, Color("c8ccd4"))
			_px(31, y - 4, Color("a0a6b0"))
	_save("fx_arrows.png")
	img = Image.create_empty(12, 20, false, Image.FORMAT_RGBA8)
	_rect(4, 6, 4, 14, Color("5e3a20"))
	_rect(1, 4, 10, 3, METAL.darkened(0.3))
	_rect(2, 2, 8, 2, Color("3a3f52"))
	_save("fx_torch.png")
	img = Image.create_empty(48, 12, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for y in 12:
		for x in 48:
			var d := Vector2((x - 23.5) / 24.0, (y - 5.5) / 6.0).length()
			if d < 1.0 and rng.randf() < 1.1 - d:
				img.set_pixel(x, y, Color(0.02, 0.01, 0.02, 0.85 - d * 0.5))
	_save("fx_scorch.png")
	img = Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 16.0
			var keep := 1.0 - d * d
			if keep > float(bayer[(y % 4) * 4 + x % 4]) / 16.0:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	_save("fx_smokebig.png")
	img = Image.create_empty(2, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		img.set_pixel(0, y, Color(1, 1, 1, y / 16.0))
		img.set_pixel(1, y, Color(1, 1, 1, y / 20.0))
	_save("fx_streak.png")
	var noise := FastNoiseLite.new()
	noise.seed = 9
	noise.frequency = 0.06
	img = Image.create_empty(128, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 128:
			var v := 0.0
			for dy in [0, 64]:
				for dx in [0, 128]:
					var wx := 1.0 - absf(x - dx) / 128.0 if dx > 0 else 1.0 - x / 128.0
					var wy := 1.0 - absf(y - dy) / 64.0 if dy > 0 else 1.0 - y / 64.0
					v += noise.get_noise_2d(x - dx, y - dy) * wx * wy
			v = clampf(v * 0.5 + 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	_save("fx_noise.png")

# p4.18 the Harvest season's pictures (ComfyUI: tools/comfy/run_harvest.py, then
# make_assets.py harvest), and how they are drawn. powers_view.gd calls these in the
# Harvest season (client/season.gd) in place of Halloween's: the covered dish for the
# candy, the season's badges, the turkey you chase, the hopping turkey of TURKEY TIME,
# THE BIG TURKEY (GHOSTFACE's place: the same rules), crows for bats, a gust of leaves.
# PIE's badge is the same in every season.
extends RefCounted

const P = preload("res://sim/proto.gd")
const ICONS := preload("res://assets/harvest_icons.png")   # 128 px a cell (make_assets.py HARVEST_ICONS)
const BIRDS := preload("res://assets/harvest_birds.png")   # 256 px a cell, the feet on its line 250, facing right
enum { IC_DISH, IC_PIE, IC_POPCORN, IC_CROWS, IC_TURKEY_TIME, IC_TOO_MUCH_PIE, IC_PEA, IC_BIG_TURKEY }
enum { B_RUN, B_JUMP, B_STAND, B_PECK, B_DOWN }
const LEAF_COLS := [Color(0.95, 0.5, 0.1), Color(0.85, 0.22, 0.1), Color(0.98, 0.78, 0.2), Color(0.7, 0.3, 0.08)]
const SMALL_H := 66.0            # the turkey you chase, px tall
const BIG_H := 118.0             # THE BIG TURKEY

# The season's badge for a power-up kind or a trick's icon kind (trick0: powers_view's
# TRICK_ICON); -1: none, the usual picture.
static func icon_cell(kind: int, trick0: int, harvest: bool) -> int:
	if kind == P.PU_PIE:
		return IC_PIE
	if not harvest:
		return -1
	if kind == P.PU_TRICK:
		return IC_DISH
	if kind == P.PU_PUMPKIN:
		return IC_POPCORN
	if kind == P.PU_BATS:
		return IC_CROWS
	if kind == P.PU_MASK:
		return IC_BIG_TURKEY
	if kind >= trick0 and kind <= trick0 + 2:
		return IC_TURKEY_TIME + kind - trick0
	return -1

# A badge: cell, its middle at c, half its side s * 1.25 (as powers_view's other pictures), bobbing.
static func icon(ci: CanvasItem, c: Vector2, cell: int, s: float, a: float, tt: float) -> void:
	var th := s * 1.25
	var bob := sin(tt * 3.0 + cell) * s * 0.05
	ci.draw_texture_rect_region(ICONS, Rect2(c + Vector2(-th, -th + bob), Vector2(th, th) * 2.0), Rect2(cell * 128, 0, 128, 128), Color(1, 1, 1, a))

# A bird: its cell, the middle of its feet, h px tall, facing dir (1 right, -1 left),
# tilted rot, squashed sq (1: none).
static func bird(ci: CanvasItem, cell: int, feet: Vector2, h: float, dir: float, a: float, rot: float = 0.0, sq: float = 1.0) -> void:
	ci.draw_set_transform(feet, rot * dir, Vector2(dir, sq))
	ci.draw_texture_rect_region(BIRDS, Rect2(-h * 0.5, -h * 250.0 / 256.0, h, h), Rect2(cell * 256, 0, 256, 256), Color(1, 1, 1, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The turkey you chase (the black cat's place): running with a bob and a wobble, wings
# out in the air and when it flies off; CATCH ME over it. pd: the snapshot's pet; air:
# it is off the floor.
static func pet(ci: CanvasItem, pd: Dictionary, tt: float, air: bool, font: Font) -> void:
	var feet := Vector2(pd["x"], pd["y"])
	var dir := float(pd["dir"])
	var gone := int(pd.get("gone", 0))
	var a := clampf(gone / 40.0, 0.0, 1.0) if gone > 0 else 1.0
	ci.draw_circle(feet + Vector2(0, -26), 40.0, Color(1.0, 0.75, 0.3, 0.10 * a))      # a soft light round it
	if gone > 0 or air:
		bird(ci, B_JUMP, feet, SMALL_H * 1.06, dir, a, sin(tt * 26.0) * 0.12)
	else:
		bird(ci, B_RUN, feet + Vector2(0, -absf(sin(tt * 17.0)) * 5.0), SMALL_H, dir, a, sin(tt * 17.0) * 0.07)
	if gone == 0:
		var bob := sin(tt * 3.0) * 3.0
		var at := feet + Vector2(0, -SMALL_H - 16.0 + bob)
		var s := "CATCH ME!"
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ci.draw_string_outline(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.9))
		ci.draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.9, 0.5))

# TURKEY TIME (the pumpkin trick's place): the fighter is a hopping turkey for a moment.
# f: the fighter as drawn; tc: its seat's colour (a ring, so everyone can tell whose).
static func trick_turkey(ci: CanvasItem, f: Dictionary, tc: Color, a: float, tt: float) -> void:
	var feet := Vector2(f["x"] + 18.0, f["y"] + 63.0)
	var dir := 1.0 if (int(f["flags"]) & 1) != 0 else -1.0
	ci.draw_arc(feet + Vector2(0, -30), 40.0, 0.0, TAU, 28, Color(tc, 0.85 * a), 4.0, true)
	bird(ci, B_RUN, feet, 76.0, dir, a, sin(tt * 16.0) * 0.08)

# THE BIG TURKEY (GHOSTFACE's place, the same rules: no bow, a peck, down 2 s, a hit
# while down ends it). f: the fighter as drawn; pw: its power-up row (mask: 1 it is,
# 2 down, 4 pecking, 8 winding up); tc: its seat's colour, a disc behind it; peck_at: when
# (t) it last pecked.
static func big_turkey(ci: CanvasItem, f: Dictionary, pw: Dictionary, a: float, tt: float, tc: Color, peck_at: float) -> void:
	var feet := Vector2(f["x"] + 18.0, f["y"] + 63.0)
	var dir := 1.0 if (int(f["flags"]) & 1) != 0 else -1.0
	var mk := int(pw.get("mask", 0))
	var dead: bool = f["state"] == P.F_DEAD
	ci.draw_circle(feet + Vector2(0, -BIG_H * 0.46), BIG_H * 0.52, Color(tc, (0.2 if dead else 0.42) * a))
	ci.draw_arc(feet + Vector2(0, -BIG_H * 0.46), BIG_H * 0.52, 0.0, TAU, 36, Color(tc.lightened(0.2), (0.4 if dead else 0.95) * a), 4.0, true)
	if dead or (mk & 2) != 0:
		bird(ci, B_DOWN, feet, BIG_H * 0.92, dir, a * (0.75 if dead else 1.0), 0.0 if dead else sin(tt * 9.0) * 0.04)
		return
	var since := tt - peck_at
	if (mk & 4) != 0 or since < 0.24:                 # the peck: a lunge forward and back
		var k := clampf(since / 0.24, 0.0, 1.0)
		bird(ci, B_PECK, feet + Vector2(dir * 22.0 * sin(k * PI), 0), BIG_H * 0.96, dir, a, 0.10 * sin(k * PI))
	elif (mk & 8) != 0:                               # shoot held: it leans back, ready
		bird(ci, B_STAND, feet, BIG_H, dir, a, -0.12, 0.96)
	else:
		var moving := absf(float(f.get("vx", 0.0))) > 0.6 and (int(f["flags"]) & 2) != 0
		bird(ci, B_STAND, feet + Vector2(0, -absf(sin(tt * 13.0)) * 4.0 if moving else 0.0), BIG_H, dir, a,
			sin(tt * 13.0) * 0.05 if moving else 0.0, 1.0 + (0.0 if moving else sin(tt * 3.0) * 0.015))

# The covered dish (the candy's place): cd: the snapshot's candy; it bobs and wiggles
# at rest, turns while it falls, blinks in its last 2 seconds.
static func dish(ci: CanvasItem, cd: Dictionary, tt: float) -> void:
	var rest: bool = (int(cd["flags"]) & 1) != 0
	var a := 1.0
	if int(cd["life"]) < 120 and int(tt * 8.0) % 2 == 0:
		a = 0.35
	var c := Vector2(cd["x"], cd["y"])
	var rot := sin(tt * 9.0) * 0.5
	if rest:
		c.y += sin(tt * 3.0 + c.x * 0.05) * 3.0 - 6.0
		rot = sin(tt * 5.0 + c.x) * 0.16
	ci.draw_circle(c, 36.0, Color(1.0, 0.85, 0.5, 0.12 * a))
	var pulse := fmod(tt * 0.9 + c.x * 0.003, 1.0)       # a ring that grows and fades: something to grab
	ci.draw_arc(c, 20.0 + 26.0 * pulse, 0.0, TAU, 28, Color(1.0, 0.85, 0.45, (1.0 - pulse) * 0.6 * a), 2.5, true)
	ci.draw_set_transform(c, rot, Vector2.ONE)
	ci.draw_texture_rect_region(ICONS, Rect2(-27, -27, 54, 54), Rect2(IC_DISH * 128, 0, 128, 128), Color(1, 1, 1, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# A crow (a bat's place): the badge's crow, small, flapping (squashed up and down).
static func crow(ci: CanvasItem, p: Vector2, s: float, ph: float, a: float) -> void:
	var h := 30.0 * s
	ci.draw_set_transform(p, 0.0, Vector2(1.0, 0.7 + 0.3 * sin(ph)))
	ci.draw_texture_rect_region(ICONS, Rect2(-h * 0.5, -h * 0.5, h, h), Rect2(IC_CROWS * 128, 0, 128, 128), Color(1, 1, 1, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# A leaf: at p, s times its size, turned rot, flipping (flip -1..1).
static func leaf(ci: CanvasItem, p: Vector2, s: float, rot: float, flip: float, col: Color) -> void:
	ci.draw_set_transform(p, rot, Vector2(s, s * (0.55 + 0.45 * flip)))
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-11, 0), Vector2(-4, -6), Vector2(6, -5), Vector2(13, 0), Vector2(6, 5), Vector2(-4, 6)]), col)
	ci.draw_line(Vector2(-11, 0), Vector2(11, 0), Color(col.darkened(0.45), col.a), 1.5)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# A gust of leaves (the bat swarm's place on THE HARVEST BARN): the warning (wind lines
# at the edge it comes in from), then a band of leaves w x h sweeping across at cx, y.
static func gust(ci: CanvasItem, phase: int, cx: float, y: float, dir: float, w: float, h: float, tt: float) -> void:
	if phase == 0:
		var ex := 40.0 if dir > 0 else 1880.0
		ci.draw_rect(Rect2(0, y - h * 0.5, 1920, h), Color(1.0, 0.75, 0.3, 0.06 + 0.05 * sin(tt * 20.0)))
		for k in 4:
			var zy := y - h * 0.36 + k * h * 0.24
			var zx := ex + dir * fmod(tt * 300.0 + k * 70.0, 220.0)
			ci.draw_line(Vector2(zx, zy), Vector2(zx + dir * 90.0, zy), Color(1.0, 0.9, 0.7, 0.75), 4.0, true)
		return
	for k in 7:      # a warm haze: soft blobs
		var bx := cx + (k - 3) * w * 0.14 + sin(tt * 2.0 + k) * 10.0
		ci.draw_circle(Vector2(bx, y + sin(tt * 3.0 + k * 1.7) * 12.0), h * (0.42 if k % 3 == 0 else 0.34), Color(0.5, 0.25, 0.05, 0.13))
	for i in 56:
		var hx := fposmod(i * 97.0 + tt * 60.0 * (1.0 + (i % 3) * 0.3), w) - w * 0.5
		var hy := fposmod(i * 53.0, h) - h * 0.5 + sin(tt * 5.0 + i) * 10.0
		var col: Color = LEAF_COLS[i % LEAF_COLS.size()]
		leaf(ci, Vector2(cx + hx * dir, y + hy), 1.2 + (i % 4) * 0.22, tt * (3.0 + i % 3) + i, sin(tt * 6.0 + i), Color(col, 0.95))

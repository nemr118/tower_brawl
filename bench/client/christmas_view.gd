# p4.22 the Christmas season's pictures (ComfyUI: tools/comfy/run_christmas.py, then
# make_assets.py christmas), and how they are drawn. powers_view.gd calls these in the
# Christmas season (client/season.gd) in place of Halloween's: the wrapped present for
# the candy (on a parachute when it comes from the sky), the season's badges, the reindeer
# you ride, the hopping snowman of the SNOWMAN trick, a fighter packed in snow, KRAMPUS
# (GHOSTFACE's place: the same rules) with his sack, snowflakes for bats, the sleigh that
# drops the giant present where the lightning struck. SNOWBALLS' badge is the same in every season.
extends RefCounted

const P = preload("res://sim/proto.gd")
const ICONS := preload("res://assets/christmas_icons.png")       # 128 px a cell (make_assets.py XMAS_ICONS)
const SPRITES := preload("res://assets/christmas_sprites.png")   # 256 px a cell, the feet on its line 250, facing right (XMAS_SPRITES)
const SLEIGH := preload("res://assets/christmas_sleigh.png")     # 512 x 256, flying to the right
enum { IC_PRESENT, IC_SNOWBALL, IC_ORNAMENT, IC_FLURRY, IC_BLIZZARD, IC_SNOWMAN, IC_BRAIN_FREEZE, IC_ELF, IC_KRAMPUS, IC_REINDEER, IC_COAL }
enum { S_K_STAND, S_K_SWING, S_K_DOWN, S_DEER_TROT, S_DEER_FLY, S_SNOWMAN, S_SNOWMAN_HOP, S_GIFT_BIG, S_GIFT_OPEN, S_GIFT_CHUTE }
const DEER_H := 78.0             # the reindeer on its floor, px tall
const MOUNT_H := 84.0            # under a rider
const KRAMPUS_H := 124.0
const SNOWMAN_H := 88.0
const RIBBONS := [Color(0.9, 0.15, 0.15), Color(0.15, 0.7, 0.25), Color(1.0, 0.85, 0.3), Color(1, 1, 1), Color(0.2, 0.55, 1.0)]
const LIGHTS := [Color(1.0, 0.25, 0.2), Color(0.25, 0.9, 0.35), Color(1.0, 0.85, 0.25), Color(0.3, 0.6, 1.0), Color(1.0, 0.45, 0.85)]
const SLEIGH_Y := 168.0          # the sleigh's height on the screen (under the HUD's cards)
const DROP_AT := 0.72            # of a drop's warning: the sleigh is over the spot and lets the present go

# The season's badge for a power-up kind or a trick's icon kind (trick0: powers_view's
# TRICK_ICON); -1: none, the usual picture.
static func icon_cell(kind: int, trick0: int, xmas: bool) -> int:
	if kind == P.PU_SNOWBALL:
		return IC_SNOWBALL
	if not xmas:
		return -1
	if kind == P.PU_TRICK:
		return IC_PRESENT
	if kind == P.PU_PUMPKIN:
		return IC_ORNAMENT
	if kind == P.PU_BATS:
		return IC_FLURRY
	if kind == P.PU_RAIN:
		return IC_BLIZZARD
	if kind == P.PU_MASK:
		return IC_KRAMPUS
	if kind >= trick0 and kind <= trick0 + 2:
		return IC_SNOWMAN + kind - trick0
	return -1

# A badge: cell, its middle at c, half its side s * 1.25 (as powers_view's other pictures), bobbing.
static func icon(ci: CanvasItem, c: Vector2, cell: int, s: float, a: float, tt: float) -> void:
	var th := s * 1.25
	var bob := sin(tt * 3.0 + cell) * s * 0.05
	ci.draw_texture_rect_region(ICONS, Rect2(c + Vector2(-th, -th + bob), Vector2(th, th) * 2.0), Rect2(cell * 128, 0, 128, 128), Color(1, 1, 1, a))

# A sprite: its cell, the middle of its feet, h px tall, facing dir (1 right, -1 left),
# tilted rot, squashed sq (1: none).
static func sprite(ci: CanvasItem, cell: int, feet: Vector2, h: float, dir: float, a: float, rot: float = 0.0, sq: float = 1.0) -> void:
	ci.draw_set_transform(feet, rot * dir, Vector2(dir, sq))
	ci.draw_texture_rect_region(SPRITES, Rect2(-h * 0.5, -h * 250.0 / 256.0, h, h), Rect2(cell * 256, 0, 256, 256), Color(1, 1, 1, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# A sparkle: a little four-point star.
static func sparkle(ci: CanvasItem, p: Vector2, r: float, col: Color) -> void:
	if r < 0.8:
		return        # (a star with no size cannot be filled)
	ci.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r), p + Vector2(r * 0.28, -r * 0.28), p + Vector2(r, 0), p + Vector2(r * 0.28, r * 0.28),
		p + Vector2(0, r), p + Vector2(-r * 0.28, r * 0.28), p + Vector2(-r, 0), p + Vector2(-r * 0.28, -r * 0.28)]), col)

# The reindeer on its floor (the black cat's place): trotting with a bob, its bells
# twinkling, RIDE ME! over it; when its time is up it leaps up and away. pd: the snapshot's pet.
static func pet(ci: CanvasItem, pd: Dictionary, tt: float, font: Font) -> void:
	var feet := Vector2(pd["x"], pd["y"])
	var dir := float(pd["dir"])
	var gone := int(pd.get("gone", 0))
	var a := clampf(gone / 40.0, 0.0, 1.0) if gone > 0 else 1.0
	ci.draw_circle(feet + Vector2(0, -34), 46.0, Color(1.0, 0.9, 0.55, 0.10 * a))      # a soft warm light round it
	if gone > 0:
		sprite(ci, S_DEER_FLY, feet, DEER_H * 1.08, dir, a, -0.22)
	else:
		sprite(ci, S_DEER_TROT, feet + Vector2(0, -absf(sin(tt * 11.0)) * 5.0), DEER_H, dir, a, sin(tt * 11.0) * 0.05)
		for i in 2:      # the bells twinkle
			var tw := fposmod(tt * 1.3 + i * 0.5, 1.0)
			sparkle(ci, feet + Vector2(dir * (8.0 - i * 20.0), -30.0 - i * 9.0), 7.0 * sin(tw * PI), Color(1.0, 0.92, 0.5, sin(tw * PI) * a))
		var bob := sin(tt * 3.0) * 3.0
		var at := feet + Vector2(0, -DEER_H - 14.0 + bob)
		var s := "RIDE ME!"
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		ci.draw_string_outline(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.9))
		ci.draw_string(font, at - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.9, 0.5))

# The reindeer under its rider (the fighter is drawn by world.gd: the reindeer covers its
# legs). f: the fighter as drawn. It gallops through the air, sparkles trailing behind.
static func mount(ci: CanvasItem, f: Dictionary, a: float, tt: float) -> void:
	var dir := 1.0 if (int(f["flags"]) & 1) != 0 else -1.0
	var feet := Vector2(f["x"] + 18.0 - dir * 4.0, f["y"] + 63.0 + 16.0 + sin(tt * 9.0 + float(f["id"])) * 3.0)
	for i in 4:
		var k := fposmod(tt * 1.6 + i * 0.25, 1.0)
		sparkle(ci, feet + Vector2(-dir * (34.0 + k * 46.0), -30.0 + sin(i * 2.1) * 14.0 + k * 10.0), 6.0 * (1.0 - k), Color(1.0, 0.95, 0.6, (1.0 - k) * 0.9 * a))
	sprite(ci, S_DEER_FLY, feet, MOUNT_H, dir, a, sin(tt * 9.0 + float(f["id"])) * 0.06)

# A reindeer leaving after a ride (age s since the ride's end, from at, flying dir): up and away, fading.
static func fly_off(ci: CanvasItem, at: Vector2, dir: float, age: float) -> void:
	var k := clampf(age / 0.8, 0.0, 1.0)
	sprite(ci, S_DEER_FLY, at + Vector2(dir * 420.0 * age, -360.0 * age - 180.0 * age * age), MOUNT_H * (1.0 - 0.3 * k), dir, 1.0 - k * k, -0.3)

# SNOWMAN (the pumpkin trick's place): the fighter is a hopping snowman for a moment.
# f: the fighter as drawn; tc: its seat's colour (a ring, so everyone can tell whose).
static func trick_snowman(ci: CanvasItem, f: Dictionary, tc: Color, a: float, tt: float) -> void:
	var feet := Vector2(f["x"] + 18.0, f["y"] + 63.0)
	var dir := 1.0 if (int(f["flags"]) & 1) != 0 else -1.0
	ci.draw_arc(feet + Vector2(0, -36), 46.0, 0.0, TAU, 28, Color(tc, 0.85 * a), 4.0, true)
	var up := (int(f["flags"]) & 2) == 0
	sprite(ci, S_SNOWMAN_HOP if up else S_SNOWMAN, feet, SNOWMAN_H, dir, a, sin(tt * 14.0) * 0.07, 1.0 if up else 0.94 + 0.06 * sin(tt * 14.0))

# Packed in snow (frozen, in the season): the fighter is a snowman that shivers; its seat's
# colour in a ring and on a little scarf mark, so everyone can tell whose it is. left: 0..1 of the snow left.
static func snowed(ci: CanvasItem, f: Dictionary, tc: Color, a: float, tt: float) -> void:
	var feet := Vector2(f["x"] + 18.0, f["y"] + 63.0)
	var dir := 1.0 if (int(f["flags"]) & 1) != 0 else -1.0
	ci.draw_arc(feet + Vector2(0, -38), 48.0, 0.0, TAU, 28, Color(tc, 0.9 * a), 4.0, true)
	sprite(ci, S_SNOWMAN, feet + Vector2(sin(tt * 38.0) * 1.5, 0), SNOWMAN_H, dir, a)
	ci.draw_circle(feet + Vector2(0, -80.0), 7.0, Color(0.05, 0.05, 0.1, 0.8 * a))      # a dot of its colour on top
	ci.draw_circle(feet + Vector2(0, -80.0), 5.0, Color(tc, a))

# KRAMPUS (GHOSTFACE's place, the same rules: no bow, a swing, down 2 s, a hit while down
# ends it). f: the fighter as drawn; pw: its power-up row (mask: 1 it is, 2 down, 4 swinging,
# 8 winding up); tc: its seat's colour, a disc behind it; swing_at: when (t) it last swung;
# sacked: the seat colours of those it put in its sack this round (their boots stick out).
static func krampus(ci: CanvasItem, f: Dictionary, pw: Dictionary, a: float, tt: float, tc: Color, swing_at: float, sacked: Array) -> void:
	var feet := Vector2(f["x"] + 18.0, f["y"] + 63.0)
	var dir := 1.0 if (int(f["flags"]) & 1) != 0 else -1.0
	var mk := int(pw.get("mask", 0))
	var dead: bool = f["state"] == P.F_DEAD
	ci.draw_circle(feet + Vector2(0, -KRAMPUS_H * 0.46), KRAMPUS_H * 0.52, Color(tc, (0.2 if dead else 0.42) * a))
	ci.draw_arc(feet + Vector2(0, -KRAMPUS_H * 0.46), KRAMPUS_H * 0.52, 0.0, TAU, 36, Color(tc.lightened(0.2), (0.4 if dead else 0.95) * a), 4.0, true)
	if dead or (mk & 2) != 0:
		sprite(ci, S_K_DOWN, feet, KRAMPUS_H * 0.92, dir, a * (0.75 if dead else 1.0), 0.0 if dead else sin(tt * 9.0) * 0.04)
		return
	var since := tt - swing_at
	var lean := 0.0
	if (mk & 4) != 0 or since < 0.24:                 # the swing: a lunge forward and back
		var k := clampf(since / 0.24, 0.0, 1.0)
		sprite(ci, S_K_SWING, feet + Vector2(dir * 22.0 * sin(k * PI), 0), KRAMPUS_H * 0.98, dir, a, 0.10 * sin(k * PI))
		for i in 3:                                   # the sticks' swish
			var sa := -1.1 + k * 2.0 + i * 0.22
			ci.draw_arc(feet + Vector2(dir * 34.0, -KRAMPUS_H * 0.5), 58.0 + i * 7.0, (sa if dir > 0 else PI - sa - 0.5), (sa + 0.5 if dir > 0 else PI - sa), 8,
				Color(1, 1, 1, (0.55 - i * 0.15) * (1.0 - k) * a), 4.0, true)
	elif (mk & 8) != 0:                               # shoot held: he leans back, ready
		lean = -0.12
		sprite(ci, S_K_STAND, feet, KRAMPUS_H, dir, a, lean, 0.96)
	else:
		var moving := absf(float(f.get("vx", 0.0))) > 0.6 and (int(f["flags"]) & 2) != 0
		sprite(ci, S_K_STAND, feet + Vector2(0, -absf(sin(tt * 13.0)) * 4.0 if moving else 0.0), KRAMPUS_H, dir, a,
			sin(tt * 13.0) * 0.05 if moving else 0.0, 1.0 + (0.0 if moving else sin(tt * 3.0) * 0.015))
	# the sack on his back: a pair of kicking boots for each one he caught (three at most are shown)
	for i in mini(sacked.size(), 3):
		var bc: Color = sacked[i]
		var base := feet + Vector2(-dir * (30.0 + i * 9.0), -KRAMPUS_H * 0.62 - i * 5.0)
		for side in [-1.0, 1.0]:
			var kick := sin(tt * 15.0 + i * 2.0 + side) * 6.0
			var tip := base + Vector2(side * 6.0 + kick * 0.4, -16.0 - absf(kick))
			ci.draw_line(base + Vector2(side * 4.0, 0), tip, Color(0.05, 0.04, 0.08, a), 7.0)
			ci.draw_line(base + Vector2(side * 4.0, 0), tip, Color(bc, a), 4.0)
			ci.draw_circle(tip, 4.5, Color(0.05, 0.04, 0.08, a))
			ci.draw_circle(tip, 3.0, Color(0.35, 0.22, 0.12, a))

# One knocked out by KRAMPUS flies into his sack (age s since; from its body to his back): a
# small ball in its colour, shrinking, then a pop of dust at the sack.
static func into_sack(ci: CanvasItem, from: Vector2, to: Vector2, col: Color, age: float) -> void:
	var k := clampf(age / 0.38, 0.0, 1.0)
	var p := from.lerp(to, k) + Vector2(0, -70.0 * sin(k * PI))
	if k < 1.0:
		ci.draw_circle(p, 16.0 * (1.0 - 0.6 * k), Color(0.05, 0.04, 0.08, 0.9))
		ci.draw_circle(p, 13.0 * (1.0 - 0.6 * k), col)
	else:
		var pk := clampf((age - 0.38) / 0.25, 0.0, 1.0)
		ci.draw_arc(to, 10.0 + 30.0 * pk, 0.0, TAU, 20, Color(0.85, 0.75, 0.6, 1.0 - pk), 4.0, true)

# The present (the candy's place): cd: the snapshot's candy. From the sky it floats down on
# a little parachute, swaying; at rest it bobs and wiggles; it blinks in its last 2 seconds.
static func present(ci: CanvasItem, cd: Dictionary, tt: float) -> void:
	var rest: bool = (int(cd["flags"]) & 1) != 0
	var sky: bool = (int(cd["flags"]) & 2) != 0
	var a := 1.0
	if int(cd["life"]) < 120 and int(tt * 8.0) % 2 == 0:
		a = 0.35
	var c := Vector2(cd["x"], cd["y"])
	if sky and not rest:
		var sway := sin(tt * 2.6 + c.x * 0.02)
		ci.draw_set_transform(c + Vector2(sway * 6.0, 0), sway * 0.16, Vector2.ONE)
		ci.draw_texture_rect_region(SPRITES, Rect2(-48, -78, 96, 96), Rect2(S_GIFT_CHUTE * 256, 0, 256, 256), Color(1, 1, 1, a))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	var rot := sin(tt * 9.0) * 0.5
	if rest:
		c.y += sin(tt * 3.0 + c.x * 0.05) * 3.0 - 6.0
		rot = sin(tt * 5.0 + c.x) * 0.16
	ci.draw_circle(c, 36.0, Color(1.0, 0.9, 0.6, 0.12 * a))
	var pulse := fmod(tt * 0.9 + c.x * 0.003, 1.0)       # a ring that grows and fades: something to grab
	ci.draw_arc(c, 20.0 + 26.0 * pulse, 0.0, TAU, 28, Color(1.0, 0.9, 0.55, (1.0 - pulse) * 0.6 * a), 2.5, true)
	ci.draw_set_transform(c, rot, Vector2.ONE)
	ci.draw_texture_rect_region(ICONS, Rect2(-27, -27, 54, 54), Rect2(IC_PRESENT * 128, 0, 128, 128), Color(1, 1, 1, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tw := fposmod(tt * 1.1 + c.x * 0.01, 1.0)
	sparkle(ci, c + Vector2(20.0, -22.0), 8.0 * sin(tw * PI), Color(1, 1, 0.8, sin(tw * PI) * a))

# A snowflake (a bat's place: SNOW FLURRY circling its fighter): six arms, turning.
static func flake(ci: CanvasItem, p: Vector2, s: float, ph: float, a: float) -> void:
	var r := 9.0 * s
	ci.draw_circle(p, r * 0.9, Color(0.75, 0.9, 1.0, 0.25 * a))
	for i in 3:
		var d := Vector2.from_angle(ph * 0.25 + i * PI / 3.0) * r
		ci.draw_line(p - d, p + d, Color(1, 1, 1, a), 2.2, true)
	ci.draw_circle(p, r * 0.3, Color(1, 1, 1, a))

# BLIZZARD (RAIN's place) over the whole arena: a pale veil and snow blowing sideways. drops:
# powers_view's rain streaks (their places).
static func blizzard(ci: CanvasItem, drops: Array, tt: float) -> void:
	ci.draw_rect(Rect2(0, 0, 1920, 1080), Color(0.75, 0.86, 1.0, 0.13))
	for i in drops.size():
		var d: Vector2 = drops[i]
		var p := Vector2(fposmod(d.x * 3.0 - d.y * 1.4 + sin(tt * 2.0 + i) * 12.0, 2000.0) - 40.0, d.y)
		ci.draw_circle(p, 2.0 + (i % 3), Color(1, 1, 1, 0.7))
		ci.draw_line(p, p + Vector2(16.0, 3.0), Color(1, 1, 1, 0.25), 2.0)

# The sleigh in the sky while a drop is warned (prog 0..1 of the warning; spot: the orb's
# middle): it flies in from the left, is over the spot at DROP_AT and lets a giant present
# go, which falls to the spot as the warning ends. The danger's disc and its count are
# powers_view's own (the rule is the lightning's: stand back).
static func sleigh_x(prog: float, spot_x: float) -> float:
	return lerpf(-330.0, spot_x, prog / DROP_AT)       # past DROP_AT it flies on at the same speed

static func sleigh(ci: CanvasItem, x: float, tt: float, a: float) -> void:
	var y := SLEIGH_Y + sin(tt * 2.2) * 10.0
	for i in 5:      # sparkles behind it
		var k := fposmod(tt * 1.4 + i * 0.2, 1.0)
		sparkle(ci, Vector2(x - 120.0 - k * 110.0, y + 16.0 + sin(i * 1.7) * 22.0), 9.0 * (1.0 - k), Color(1.0, 0.95, 0.6, (1.0 - k) * a))
	ci.draw_set_transform(Vector2(x, y), sin(tt * 2.2 + 1.0) * 0.04, Vector2.ONE)
	ci.draw_texture_rect(SLEIGH, Rect2(-160, -80, 320, 160), false, Color(1, 1, 1, a))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The giant present on its way down (k 0..1: let go .. lands on spot), its shadow growing on the floor.
static func drop_gift(ci: CanvasItem, spot: Vector2, floor_y: float, k: float, tt: float) -> void:
	var y := lerpf(SLEIGH_Y + 30.0, spot.y, k * k)
	ci.draw_set_transform(Vector2(spot.x, floor_y), 0.0, Vector2(1.0, 0.28))
	ci.draw_circle(Vector2.ZERO, 26.0 + 44.0 * k, Color(0.0, 0.0, 0.05, 0.25 + 0.3 * k))
	ci.draw_set_transform(Vector2(spot.x, y), sin(tt * 7.0) * 0.12 * (1.0 - k), Vector2.ONE)
	ci.draw_texture_rect_region(SPRITES, Rect2(-62, -62, 124, 124), Rect2(S_GIFT_BIG * 256, 0, 256, 256))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# It landed (age s since): squashed flat for a moment, then it bursts open, and the orb is there.
static func landed_gift(ci: CanvasItem, spot: Vector2, floor_y: float, age: float) -> void:
	if age < 0.14:
		var q := sin(age / 0.14 * PI)
		ci.draw_set_transform(Vector2(spot.x, floor_y), 0.0, Vector2(1.0 + 0.5 * q, 1.0 - 0.45 * q))
		ci.draw_texture_rect_region(SPRITES, Rect2(-62, -124, 124, 124), Rect2(S_GIFT_BIG * 256, 0, 256, 256))
	else:
		var k := clampf((age - 0.14) / 0.4, 0.0, 1.0)
		ci.draw_set_transform(Vector2(spot.x, floor_y), 0.0, Vector2.ONE * (1.0 + 0.25 * k))
		ci.draw_texture_rect_region(SPRITES, Rect2(-66, -128, 132, 132), Rect2(S_GIFT_OPEN * 256, 0, 256, 256), Color(1, 1, 1, 1.0 - k * k))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Squashed by the present (a body the lightning's rule knocked out, in the season): little
# stars circle over it for a moment.
static func stars(ci: CanvasItem, c: Vector2, tt: float, a: float) -> void:
	for i in 4:
		var ang := tt * 5.0 + i * TAU / 4.0
		sparkle(ci, c + Vector2(cos(ang) * 26.0, -44.0 + sin(ang) * 8.0), 7.0, Color(1.0, 0.9, 0.3, a))

# A snowball in the air (world.gd draws a white ball on the arrow's node; this is a snowball
# for the PHEW gag and the badges that want one drawn in code): at p, r wide.
static func snowball(ci: CanvasItem, p: Vector2, r: float, a: float) -> void:
	ci.draw_circle(p, r + 2.5, Color(0.1, 0.14, 0.25, a))
	ci.draw_circle(p, r, Color(0.8, 0.9, 1.0, a))
	ci.draw_circle(p + Vector2(-r * 0.2, -r * 0.2), r * 0.72, Color(1, 1, 1, a))

# A breath in the cold: a small puff rising from a fighter's head (k 0..1 of its life).
static func breath(ci: CanvasItem, head: Vector2, dir: float, k: float) -> void:
	var p := head + Vector2(dir * (12.0 + 16.0 * k), -4.0 - 14.0 * k)
	ci.draw_circle(p, 4.0 + 7.0 * k, Color(1, 1, 1, 0.34 * (1.0 - k)))
	ci.draw_circle(p + Vector2(dir * 6.0, -4.0), 3.0 + 5.0 * k, Color(1, 1, 1, 0.22 * (1.0 - k)))

# p4.22 WINTER HATS (the Christmas update; the owner: "a hat on every fighter in the seat's
# colour", and "Pick your hat: a button on your lobby card cycles a Santa hat, elf hat,
# antlers, earmuffs, a pom beanie, or a snowman's top hat. The server keeps it with your
# name."). Until now a seat was only a colour: this is the first bit of "pick your character".
# This file is ALL of the hats' look and motion, and it is drawn in code: no pictures.
#   - the six hats (body, tail): each in its wearer's seat colour, with cream trim and a
#     thick dark rim, so a hat belongs to its fighter and still reads as what it is;
#   - where a hat sits on each of the fighter's poses (HEAD: one line per frame of the sheet);
#   - how it moves (Swing): the Santa hat's tip, the elf's bell and the pom lag behind a run
#     and swing back, every hat dips on a landing, flips with the facing, leans in a run;
#   - the arena (Arena, a node client/world.gd adds over its fighters): a hat follows its
#     fighter's sprite, hides when the sprite hides, and pops off on a knockout: it flies
#     up, falls, and lies beside the body until the next round;
#   - the lobby's seat cards (on_card, card_change), the match's seat cards (on_hud), the
#     winner's screen (on_podium, on_hero);
#   - the HAT button on your own lobby card (Pick): a tap puts on the next hat.
# Hats show only in the Christmas season (Season.now == "christmas": the server says it) and
# with the polish switch "hats" on (?polish_off=hats: no hats, no button).
# The special looks: TINY: a tiny hat. INVISIBLE, in bats, in smoke: hidden with the fighter
# (your own faint fighter: a faint hat). FROZEN: icy blue with the fighter, and it holds
# still. The costume (GHOSTFACE, THE BIG TURKEY) and the trick forms (a hopping pumpkin or
# turkey): no hat, it comes back with the archer. A ghost: no hat (it lies by the body).
# The memory rule (p4.21): shapes, transforms and modulate only. No text at a new size, no
# box through lobby_art.gd box, no texture. In the arena a hat's shapes are drawn ONCE and
# then only moved, so a match makes no new drawing work each frame for them.
# A restyle only needs this file: change body() and tail(), or HEAD.
extends RefCounted

const P = preload("res://sim/proto.gd")
const Art = preload("res://client/lobby_art.gd")
const Polish = preload("res://client/polish.gd")
const Season = preload("res://client/season.gd")

enum { SANTA, ELF, ANTLERS, MUFFS, BEANIE, TOPHAT }
const COUNT := 6                  # (server/hat_book.gd COUNT is the same number: tools/hat_probe.gd checks it)
const NAMES := ["SANTA HAT", "ELF HAT", "ANTLERS", "EARMUFFS", "POM BEANIE", "TOP HAT"]

const RIM := Color(0.06, 0.04, 0.09)        # the dark rim around every shape
const CREAM := Color(1.0, 0.96, 0.87)       # fur, cuffs, poms
const GOLD := Color(1.0, 0.8, 0.2)          # the elf's bell
const LEAF := Color(0.17, 0.62, 0.27)       # the holly's leaves
const BERRY := Color(0.93, 0.16, 0.16)
const OW := 2.4                             # the rim's width, in fighter pixels (a fighter's body is 36 x 63 of them)

# A hat's own frame: its origin is the top of the wearer's hood, x points the way the
# fighter faces, y points down, and one unit is one pixel of the fighter's sheet. Under the
# origin the hood widens like a ball: 10 units to each side 4 under its top, 13 at 8, 16 at
# 12. The eyes are at (8, 16).
# Where the hood's top is on each frame of the fighter's sheet (assets/fighter_p*.png, 128 px
# cells, the fighter facing right): [x from the feet, y from the feet, the head's tilt in
# degrees]. Measured from the sheet (the eyes' place in every frame). Frames 14 to 17 are the
# roll: the hat rides on top of the ball, tipped forward. 22 to 26 are the knocked-out
# poses: the hat is off by then.
const HEAD := [
	[0.5, -90.0, 0.0], [0.5, -89.0, 0.0],                                     # 0, 1 standing (breathing)
	[5.5, -90.5, 4.0], [7.5, -90.5, 4.0], [5.5, -89.5, 4.0],                  # 2 to 7 running
	[5.5, -90.5, 4.0], [7.5, -90.5, 4.0], [5.5, -89.5, 4.0],
	[0.5, -94.0, 0.0], [0.5, -92.0, 0.0], [0.5, -90.0, 0.0],                  # 8 jumping, 9 falling, 10 the bow raised
	[-28.0, -86.5, -28.0], [-10.0, -85.0, -10.0],                             # 11, 12 knocked back
	[43.5, -74.0, 45.0],                                                      # 13 a dodge through the air
	[2.0, -47.0, 16.0], [2.0, -47.0, 16.0], [2.0, -47.0, 16.0], [2.0, -47.0, 16.0],   # 14 to 17 rolling
	[7.5, -85.5, 0.0],                                                        # 18 sliding down a wall
	[-11.5, -95.0, -13.0],                                                    # 19 aiming
	[0.5, -90.0, 0.0], [19.5, -98.0, 10.0],                                   # 20 hanging from a ledge, 21 pulling up
	[-28.0, -86.5, -28.0], [-28.0, -86.5, -28.0], [-28.0, -86.5, -28.0],      # 22 to 26 knocked out (no hat)
	[-28.0, -86.5, -28.0], [-28.0, -86.5, -28.0],
	[0.5, -81.0, 0.0],                                                        # 27 landing
]
# Each hat's dangling part (its tail) turns about this point of the hat's frame.
const SNOWMAN_TOP := 76.0        # p4.22 where a hat sits on a snowman (christmas_view.gd SNOWMAN_H 88: its head top is 84 px over its feet; a quarter of the way down the head)
const SNOWMAN_HAT := 1.5         # and a hat's size there (a round head about 35 px wide; a hood is about 20)
const PIVOT := [Vector2(-3, -11.5), Vector2(0, -18), Vector2(0, 0), Vector2(0, 0), Vector2(0, -5), Vector2(0, 8.5)]
const TAIL_BEHIND := [false, false, true, false, false, true]   # is the tail drawn under the body? (antlers under the band, the top hat's crown under its brim)
# How the tail answers the head's speed: a share of LIMIT for a full run forward (+: it turns
# clockwise, as the fighter faces right), and for a fall.
const RUN_GAIN := [1.0, -0.9, -0.6, 0.0, -1.0, -0.8]
const FALL_GAIN := [0.8, -0.6, 0.0, 0.0, 0.0, 0.0]
const LIMIT := [0.8, 0.75, 0.2, 0.0, 0.7, 0.22]                  # the farthest a tail turns from rest (radians)
const LIFT := [15.0, 27.0, 28.0, 3.0, 22.0, 16.0]                # how far each hat stands over a bare hood (the marks over a head go up by this)
const FOOT := [13.0, 13.0, 16.0, 28.0, 13.0, 12.5]               # each hat's lowest edge under its origin: a hat on the floor rests on it (the earmuffs' muff hangs low)

# ------------------------------------------------------------------ what the page knows
static var seat_hat: Array = []     # each seat's hat as the server's newest seats message said (-1: none)

# game_client.gd calls this with every seats message. Out of the season the server sends no hats.
static func read(m: Dictionary) -> void:
	seat_hat.clear()
	for st in m.get("seats", []):
		var v = st.get("hat", -1) if typeof(st) == TYPE_DICTIONARY else -1
		seat_hat.append(int(v) if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT else -1)

# Are hats worn now? Only in the Christmas season, and with the polish switch on.
static func on() -> bool:
	return Season.now == "christmas" and Polish.on("hats")

# A seat's hat (0 to COUNT - 1), or -1: no hat is drawn.
static func of(seat: int) -> int:
	if seat < 0 or seat >= seat_hat.size() or not on():
		return -1
	var h := int(seat_hat[seat])
	return h if h >= 0 and h < COUNT else -1

# How far a seat's hat stands over its bare hood: the crown and the badges over a head
# (powers_view.gd) and the team flag (teams_view.gd) go up by this, so they clear the hat.
static func lift(seat: int) -> float:
	var h := of(seat)
	return float(LIFT[h]) if h >= 0 else 0.0

# ------------------------------------------------------------------ the shapes
# A filled shape with the dark rim around it.
static func _shape(ci: CanvasItem, pts: PackedVector2Array, col: Color, ow: float, tint: Color) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	loop.append(pts[1])          # (one step past the start: the rim's first corner is joined too)
	ci.draw_polyline(loop, RIM * tint, ow * 2.0, true)
	ci.draw_colored_polygon(pts, col * tint)

static func _ball(ci: CanvasItem, c: Vector2, r: float, col: Color, ow: float, tint: Color) -> void:
	ci.draw_circle(c, r + ow, RIM * tint)
	ci.draw_circle(c, r, col * tint)

# A band with round ends, from x0 to x1 and y0 to y1.
static func _pill(x0: float, y0: float, x1: float, y1: float) -> PackedVector2Array:
	var r := (y1 - y0) * 0.5
	var pts := PackedVector2Array()
	for k in 5:
		var a := PI * 0.5 + PI * k / 4.0
		pts.append(Vector2(x0 + r + cos(a) * r, y0 + r + sin(a) * r))
	for k in 5:
		var a := -PI * 0.5 + PI * k / 4.0
		pts.append(Vector2(x1 - r + cos(a) * r, y0 + r + sin(a) * r))
	return pts

# A band over the hood, along its top edge (the antlers' headband, the earmuffs' band):
# from the back of the head to the front. back, front: how many of its points to leave out.
static func _over(back: int = 0, front: int = 0) -> PackedVector2Array:
	var all := [Vector2(-20.0, 15.5), Vector2(-15.5, 10.5), Vector2(-10.5, 5.5), Vector2(-5.5, 1.0), Vector2(0.5, -1.5),
		Vector2(6.5, -0.5), Vector2(11.5, 3.0), Vector2(14.5, 8.0), Vector2(15.5, 13.5)]
	return PackedVector2Array(all.slice(back, all.size() - front))

# A fluffy ball: a round shape with a bumpy edge.
static func _fluff(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in 28:
		var a := TAU * k / 28.0
		pts.append(c + Vector2.from_angle(a) * (r + cos(a * 7.0) * r * 0.11))
	return pts

# A thick line with the rim.
static func _band(ci: CanvasItem, pts: PackedVector2Array, w: float, col: Color, ow: float, tint: Color) -> void:
	ci.draw_polyline(pts, RIM * tint, w + ow * 2.0, true)
	ci.draw_polyline(pts, col * tint, w, true)

# One antler, standing on the band (side 1: the one towards the face; -1: the other).
static func _antler(side: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for v in [Vector2(4.5, 2.5), Vector2(10.5, 2.5), Vector2(11.5, -6.5), Vector2(18.5, -9.5), Vector2(19.5, -15), Vector2(14.5, -14),
			Vector2(12.5, -12.5), Vector2(13.5, -19.5), Vector2(18, -23.5), Vector2(15.5, -27.5), Vector2(9, -23.5), Vector2(7, -13), Vector2(5.5, -6)]:
		pts.append(Vector2(v.x * side + 1.0, v.y))
	return pts

# The part of a hat that sits still on the head. front: the wearer faces us (the winner's
# painted hero): the earmuffs show both muffs. detail off (the LOW look): fewer small parts.
static func body(ci: CanvasItem, kind: int, col: Color, tint: Color = Color.WHITE, detail: bool = true, ow: float = OW, front: bool = false) -> void:
	match kind:
		SANTA:
			_shape(ci, PackedVector2Array([Vector2(-14, 8), Vector2(-13.5, -1), Vector2(-9, -10), Vector2(-2, -14.5), Vector2(5, -11.5),
				Vector2(10.5, -3.5), Vector2(14, 8)]), col, ow, tint)
			if detail:
				ci.draw_polyline(PackedVector2Array([Vector2(4, -7.5), Vector2(8.5, -1)]), col.lightened(0.4) * tint, 2.4, true)
			_shape(ci, _pill(-17.5, 3.5, 17.5, 13.0), CREAM, ow, tint)       # the fur
		ELF:
			_shape(ci, PackedVector2Array([Vector2(-13.5, 8), Vector2(-11, -5), Vector2(-6, -16.5), Vector2(0, -21), Vector2(6, -15.5),
				Vector2(11, -4), Vector2(13.5, 8)]), col, ow, tint)
			if detail:
				ci.draw_polyline(PackedVector2Array([Vector2(4, -10.5), Vector2(8, -2.5)]), col.lightened(0.4) * tint, 2.4, true)
			# the collar: a cream band with teeth
			_shape(ci, PackedVector2Array([Vector2(-16.5, 2.5), Vector2(16.5, 2.5), Vector2(16.5, 8.5), Vector2(12.4, 13), Vector2(8.25, 8.5),
				Vector2(4.1, 13), Vector2(0, 8.5), Vector2(-4.1, 13), Vector2(-8.25, 8.5), Vector2(-12.4, 13), Vector2(-16.5, 8.5)]), CREAM, ow, tint)
		ANTLERS:
			_band(ci, _over(), 4.4, CREAM, ow, tint)
		MUFFS:      # a band in the seat's colour, a fluffy cream muff over the ear
			if front:
				_band(ci, PackedVector2Array([Vector2(-20, 20), Vector2(-18, 9), Vector2(-11, 0), Vector2(0, -3), Vector2(11, 0), Vector2(18, 9),
					Vector2(20, 20)]), 5.5, col.lightened(0.3), ow, tint)
				for sx in [-1.0, 1.0]:
					_shape(ci, _fluff(Vector2(sx * 20.5, 25.0), 9.5), CREAM, ow, tint)
			else:
				_band(ci, PackedVector2Array([Vector2(-12.5, 11.0), Vector2(-10.5, 5.5), Vector2(-5.5, 1.0), Vector2(0.5, -1.5),
					Vector2(6.5, -0.5), Vector2(11.5, 3.0), Vector2(13.5, 6.5)]), 5.0, col.lightened(0.3), ow, tint)
				_shape(ci, _fluff(Vector2(-9.0, 18.0), 9.5), CREAM, ow, tint)
				if detail:
					ci.draw_arc(Vector2(-9.0, 18.0), 4.6, PI * 0.15, PI * 0.75, 6, Color(RIM, 0.2) * tint, 1.6, true)
		BEANIE:
			var dome := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				dome.append(Vector2(cos(a) * 16.0, 9.0 + sin(a) * 18.0))
			_shape(ci, dome, col, ow, tint)
			# a knitted stripe
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-11.6, -3.5), Vector2(11.6, -3.5), Vector2(14.0, 0.5), Vector2(-14.0, 0.5)]), CREAM * tint)
			_shape(ci, _pill(-17.5, 4.0, 17.5, 13.0), col.lightened(0.42), ow, tint)     # the cuff
			if detail:
				for x in [-10.5, -5.25, 0.0, 5.25, 10.5]:
					ci.draw_line(Vector2(x, 6.2), Vector2(x, 10.8), Color(RIM, 0.3) * tint, 1.3, true)
		TOPHAT:
			_shape(ci, _pill(-19.5, 5.5, 19.5, 12.5), col, ow, tint)         # the brim
			if detail:
				ci.draw_line(Vector2(-14.5, 7.7), Vector2(14.5, 7.7), col.lightened(0.4) * tint, 1.6, true)

# The part that dangles or wobbles, drawn in its own frame: its origin is PIVOT[kind].
static func tail(ci: CanvasItem, kind: int, col: Color, tint: Color = Color.WHITE, detail: bool = true, ow: float = OW) -> void:
	match kind:
		SANTA:      # the floppy end, and the pom at its tip
			_shape(ci, PackedVector2Array([Vector2(5, -2), Vector2(-3, -5), Vector2(-13, -3), Vector2(-19, 4), Vector2(-20, 11),
				Vector2(-15, 11), Vector2(-11, 5), Vector2(-4, 4), Vector2(4, 5)]), col, ow, tint)
			_ball(ci, Vector2(-17.5, 14.0), 5.8, CREAM, ow, tint)
		ELF:        # the tip curls forward; a bell hangs from it
			_shape(ci, PackedVector2Array([Vector2(-5, 2), Vector2(5, 3), Vector2(9, -2), Vector2(16, -3), Vector2(17, -6), Vector2(8, -9),
				Vector2(-1, -8), Vector2(-5, -4)]), col, ow, tint)
			_ball(ci, Vector2(17.5, 0.5), 4.6, GOLD, ow, tint)
			if detail:
				ci.draw_line(Vector2(15.0, 1.6), Vector2(20.0, 1.6), RIM * tint, 1.4, true)
		ANTLERS:
			for side in [-1.0, 1.0]:
				_shape(ci, _antler(side), col.lightened(0.12), ow, tint)
			for side in [-1.0, 1.0]:       # snow on the tips
				for tip in [Vector2(17.6, -13.0), Vector2(15.8, -25.2)]:
					ci.draw_circle(Vector2(tip.x * side + 1.0, tip.y), 2.6, CREAM * tint)
		BEANIE:
			_ball(ci, Vector2(0, -10.0), 6.8, CREAM, ow, tint)
			if detail:
				ci.draw_arc(Vector2(0, -10.0), 4.0, PI * 0.1, PI * 0.7, 6, Color(RIM, 0.22) * tint, 1.6, true)
		TOPHAT:     # the crown, its band, the holly
			_shape(ci, PackedVector2Array([Vector2(-12, -1), Vector2(-13.5, -23), Vector2(13.5, -23), Vector2(12, -1)]), col, ow, tint)
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-12.5, -9.5), Vector2(12.5, -9.5), Vector2(12.2, -3), Vector2(-12.2, -3)]), CREAM * tint)
			if detail:
				ci.draw_line(Vector2(8.5, -20), Vector2(8.0, -12), col.lightened(0.4) * tint, 2.0, true)
			var hc := Vector2(3.0, -6.0)
			ci.draw_colored_polygon(PackedVector2Array([hc, hc + Vector2(-9.5, -3), hc + Vector2(-7, -8.5), hc + Vector2(-1, -5)]), LEAF * tint)
			ci.draw_colored_polygon(PackedVector2Array([hc, hc + Vector2(9.5, -3), hc + Vector2(7, -8.5), hc + Vector2(1, -5)]), LEAF * tint)
			ci.draw_circle(hc + Vector2(0, -0.5), 3.1, BERRY * tint)

# One whole hat on any canvas. xf: where the hat's own frame is on that canvas. swing: its
# tail's angle. The caller sets its own transform again afterwards.
static func draw(ci: CanvasItem, kind: int, col: Color, xf: Transform2D, swing: float = 0.0, tint: Color = Color.WHITE,
		detail: bool = true, ow: float = OW, front: bool = false) -> void:
	if kind < 0 or kind >= COUNT:
		return
	var txf := xf * Transform2D(swing, PIVOT[kind])
	if TAIL_BEHIND[kind]:
		ci.draw_set_transform_matrix(txf)
		tail(ci, kind, col, tint, detail, ow)
	ci.draw_set_transform_matrix(xf)
	body(ci, kind, col, tint, detail, ow, front)
	if not TAIL_BEHIND[kind]:
		ci.draw_set_transform_matrix(txf)
		tail(ci, kind, col, tint, detail, ow)

# The rim's width for a hat drawn s times bigger: a big hat's rim grows, but less than the hat.
static func rim_for(s: float) -> float:
	return OW / pow(maxf(s, 0.2), 0.45)

# The hat's frame on a fighter drawn at `feet` (the sprite's own place), `s` times its sheet's
# size, on `frame` of the sheet, facing dir (1 right, -1 left). sw: its motion (or null).
static func frame_xf(feet: Vector2, s: float, frame: int, dir: float, sw = null) -> Transform2D:
	var h: Array = HEAD[clampi(frame, 0, HEAD.size() - 1)]
	var bob: float = sw.bob if sw != null else 0.0
	var lean: float = sw.lean if sw != null else 0.0
	var top := feet + Vector2(float(h[0]) * dir, float(h[1]) + bob) * s
	return Transform2D((deg_to_rad(float(h[2])) + lean) * dir, Vector2(dir * s * (1.0 + bob * 0.02), s * (1.0 - bob * 0.035)), 0.0, top)

# ------------------------------------------------------------------ the motion
# One hat's motion: the tail's angle (a small spring: it lags behind a run and swings back),
# the dip on a landing (another spring), the lean in a run. step() is called once a frame
# with where the hood's top is, in fighter pixels.
class Swing extends RefCounted:
	const W := 15.0            # the tail's spring: about 2.4 swings a second,
	const Z := 0.26            # and it dies out after two or three
	const BW := 24.0           # the dip's spring: quicker,
	const BZ := 0.38
	const FULL := 420.0        # a full run, in fighter pixels a second
	var a := 0.0               # the tail's angle from rest (radians)
	var av := 0.0
	var bob := 0.0             # the whole hat pressed down on the head (fighter pixels)
	var bv := 0.0
	var lean := 0.0            # the whole hat tipped back in a run (radians)
	var vel := Vector2.ZERO    # the head's speed, smoothed
	var last := Vector2.ZERO
	var has := false           # has it a place from the frame before?
	var ground := true
	var dir := 1.0
	var at := -1.0             # the caller's clock at the last step (step_at)

	func reset() -> void:
		a = 0.0
		av = 0.0
		bob = 0.0
		bv = 0.0
		lean = 0.0
		vel = Vector2.ZERO
		has = false

	# The same, for a caller with a clock of its own (seconds) in place of a frame time.
	func step_at(now: float, pos: Vector2, on_ground: bool, facing: float, kind: int) -> void:
		var dt := now - at if at >= 0.0 else 0.0
		at = now
		step(pos, on_ground, facing, dt, kind)

	func step(pos: Vector2, on_ground: bool, facing: float, dt: float, kind: int) -> void:
		if dt <= 0.0:
			return
		var v := Vector2.ZERO
		if has:
			var d := pos - last
			if d.length() < 90.0:      # (farther in one frame: around the arena's edge, or a new round's spot: no speed)
				v = (d / dt).limit_length(1400.0)
			if facing != dir:
				av += 8.0 * signf(RUN_GAIN[kind])      # the facing flips: the tail is flung over
			if on_ground and not ground:
				bv += 130.0                            # a landing: the hat dips
			elif ground and not on_ground and v.y < 0.0:
				bv += 60.0                             # a jump: it is pressed on for a moment
		vel = vel.lerp(v, clampf(dt * 18.0, 0.0, 1.0))
		last = pos
		has = true
		ground = on_ground
		dir = facing
		var run := clampf(vel.x * facing / FULL, -1.0, 1.0)
		var lim: float = LIMIT[kind]
		var want: float = clampf(run * RUN_GAIN[kind] + clampf(vel.y / FULL, -1.0, 1.0) * FALL_GAIN[kind], -1.0, 1.0) * lim
		lean = lerpf(lean, -0.11 * run, clampf(dt * 10.0, 0.0, 1.0))
		var left := minf(dt, 0.1)      # (a page that stalls: no more than a tenth of a second is played)
		while left > 0.0:
			var h := minf(left, 1.0 / 120.0)
			left -= h
			av += (W * W * (want - a) - 2.0 * Z * W * av) * h
			a += av * h
			bv += (-BW * BW * bob - 2.0 * BZ * BW * bv) * h
			bob += bv * h
		var low := -lim * (0.5 if kind == SANTA else 1.0)      # (the Santa hat's pom does not swing far under its fur)
		if a > lim or a < low:
			a = clampf(a, low, lim)
			av = 0.0
		bob = clampf(bob, -3.0, 5.5)

static var _swings := {}      # the hats drawn outside the arena: "card3", "podium", "hero" -> its Swing

static func _swing(key: String) -> Swing:
	if not _swings.has(key):
		_swings[key] = Swing.new()
	return _swings[key]

# ------------------------------------------------------------------ the arena
# One seat's hat in the arena: its body is this node, its tail a child. Their shapes are
# drawn once (dress) and then only moved (follow), tinted and shown or hidden.
class Worn extends Node2D:
	var hats = load("res://client/hats.gd")   # this file's own functions (a class in a file cannot call them by name)
	var kind := -1
	var col := Color.WHITE
	var detail := true
	var part := Node2D.new()
	var swing := Swing.new()
	var on_head := false        # it was on its fighter's head on the last frame
	var loose := false          # knocked off: it flies, falls, lies
	var rest := false
	var vel := Vector2.ZERO
	var spin := 0.0
	var air := 0.0
	var seat := 0
	var facing := 1.0           # 1: its fighter faces right, -1: left
	var big := 1.0              # its size (a TINY fighter's hat is small)
	var at := Vector2.ZERO      # where its origin is (the arena's pixels)
	var turn := 0.0             # how far it is turned

	func _init() -> void:
		visible = false
		add_child(part)
		part.draw.connect(func():
			if kind >= 0:
				hats.tail(part, kind, col, Color.WHITE, detail))

	func _draw() -> void:
		if kind >= 0:
			hats.body(self, kind, col, Color.WHITE, detail)

	# Which hat, in which colour: drawn again only when one of them changes.
	func dress(k: int, c: Color, with_detail: bool) -> void:
		if k == kind and c == col and with_detail == detail:
			return
		kind = k
		col = c
		detail = with_detail
		part.position = hats.PIVOT[k]
		part.show_behind_parent = hats.TAIL_BEHIND[k]
		queue_redraw()
		part.queue_redraw()

	func hide_now() -> void:
		visible = false
		on_head = false
		loose = false
		swing.reset()

	# f: the fighter as drawn this frame; spr: its sprite (world.gd set its place, frame,
	# facing, size and tint just before); frozen: FREEZE holds the hat still.
	func follow(f: Dictionary, spr: Sprite2D, frozen: bool, delta: float, level) -> void:
		if int(f["state"]) == P.F_DEAD:
			if on_head and visible and not loose:
				_pop(f)
			on_head = false
			if not loose:
				visible = false
				return
			_fly(delta, level)
			return
		loose = false
		if not spr.visible or spr.modulate.a < 0.02:
			hide_now()             # out of sight, a costume, a trick's form: no hat
			return
		var frame := int(spr.region_rect.position.x / 128.0) + 16 * int(spr.region_rect.position.y / 128.0)
		facing = -1.0 if spr.flip_h else 1.0
		big = spr.scale.x
		var h: Array = hats.HEAD[clampi(frame, 0, hats.HEAD.size() - 1)]
		if not frozen:
			swing.step(spr.position / maxf(big, 0.1) + Vector2(float(h[0]) * facing, float(h[1])), (int(f["flags"]) & 2) != 0, facing, delta, kind)
		transform = hats.frame_xf(spr.position, big, frame, facing, swing)
		at = transform.origin
		turn = (deg_to_rad(float(h[2])) + swing.lean) * facing
		part.rotation = swing.a
		modulate = spr.modulate
		visible = true
		on_head = true

	# p4.22 packed into a snowman (christmas_view.gd snowed: the fighter's sprite is hidden): the hat sits
	# on the snowman's head, a little bigger (a round head, 84 px over its feet, about 35 px wide),
	# and its tail holds still (a snowman can still fall). A knockout from there pops it off as usual (on_head).
	func on_snowman(f: Dictionary, spr: Sprite2D) -> void:
		if not spr.visible:
			hide_now()             # out of sight for this page (invisible, in bats, your smoke)
			return
		loose = false
		facing = 1.0 if (int(f["flags"]) & 1) != 0 else -1.0
		big = SNOWMAN_HAT
		swing.reset()
		transform = Transform2D(0.0, Vector2(facing * big, big), 0.0, spr.position - Vector2(0.0, SNOWMAN_TOP))   # (the sprite stands on the snowman's feet)
		at = transform.origin
		turn = 0.0
		part.rotation = 0.0
		modulate = Color.WHITE
		visible = true
		on_head = true

	# A knockout: the hat pops off, away from the hit.
	func _pop(f: Dictionary) -> void:
		loose = true
		rest = false
		air = 0.0
		var side := signf(float(f["vx"]))
		if side == 0.0:
			side = 1.0 if seat % 2 == 0 else -1.0
		vel = Vector2(side * randf_range(70.0, 150.0), -randf_range(340.0, 430.0))
		spin = side * randf_range(5.0, 9.0)

	# It flies, falls, bounces once and lies on the first floor under it (around the
	# arena's edges, as the fighters go). Lost after 6 s in the air.
	func _fly(delta: float, level) -> void:
		if not rest:
			air += delta
			if air > 6.0 or level == null:
				visible = false
				loose = false
				return
			var left := minf(delta, 0.1)
			while left > 0.0 and not rest:
				var h := minf(left, 1.0 / 90.0)
				left -= h
				vel.y = minf(vel.y + 1500.0 * h, 1100.0)
				var np := at + vel * h
				if int(level.cell_at(np.x, at.y)) == 1:      # a wall beside it
					vel.x = -vel.x * 0.4
					np.x = at.x
				var low: float = float(hats.FOOT[kind]) * big
				var foot: float = np.y + low
				if vel.y > 0.0 and int(level.cell_at(np.x, foot)) != 0 and int(level.cell_at(np.x, at.y + low - 1.0)) == 0:
					np.y = floorf(foot / 30.0) * 30.0 - low
					if vel.y > 280.0:
						vel = Vector2(vel.x * 0.5, -vel.y * 0.3)       # one small bounce
						spin *= 0.4
					else:
						rest = true
				at = Vector2(fposmod(np.x, 1920.0), fposmod(np.y, 1080.0))
				turn += spin * h
		else:
			turn = lerp_angle(turn, 0.0, clampf(delta * 12.0, 0.0, 1.0))       # it lies upright
		part.rotation = lerpf(part.rotation, 0.0, clampf(delta * 7.0, 0.0, 1.0))
		transform = Transform2D(turn, Vector2(facing * big, big), 0.0, at)

# The hats over the fighters (world.gd adds one of these on top of its fighters and calls
# show_view every frame, after it has set the sprites).
class Arena extends Node2D:
	var hats = load("res://client/hats.gd")
	var colors: Array = []
	var worn: Array = []          # by seat: a Worn, or null until that seat first wears a hat

	func setup(seat_colors: Array) -> void:
		colors = seat_colors

	# fl: the fighters as drawn this frame; sprites: world.gd's slots ([sprite, ...] by seat);
	# powers: the snapshot's power-ups by seat; low: the LOW look (fewer small parts).
	func show_view(fl: Array, sprites: Array, powers: Dictionary, delta: float, level, low: bool) -> void:
		var live: bool = hats.on() and not colors.is_empty()
		if not live and worn.is_empty():
			return
		var by := {}
		for f in fl:
			by[int(f["id"])] = f
		var n := mini(sprites.size(), hats.seat_hat.size()) if live else 0
		for i in maxi(n, worn.size()):
			var k: int = hats.of(i) if i < n else -1
			var w: Worn = worn[i] if i < worn.size() else null
			if k < 0 or not by.has(i):
				if w != null and w.visible:
					w.hide_now()
				continue
			if w == null:
				w = Worn.new()
				w.seat = i
				while worn.size() <= i:
					worn.append(null)
				worn[i] = w
				add_child(w)
			w.dress(k, colors[i % colors.size()], not low)
			var pw: Dictionary = powers.get(i, {})
			var bits := int(pw.get("bits", 0))
			# p4.22: in the Christmas season a frozen fighter is drawn as a snowman (powers_view.gd), not as a
			# costume or a trick's form: its hat goes on the snowman's head
			if Season.now == "christmas" and (bits & P.PW_FROZEN) != 0 and (bits & P.PW_PUMPKIN) == 0 \
					and (int(pw.get("mask", 0)) & P.PX_MASK) == 0 and int(by[i]["state"]) != P.F_DEAD:
				w.on_snowman(by[i], sprites[i][0])
			else:
				w.follow(by[i], sprites[i][0], (bits & P.PW_FROZEN) != 0, delta, level)

# ------------------------------------------------------------------ the lobby's seat cards
# A faded fighter (a bot to come, someone away) wears a faded hat: darker, not see-through
# (a see-through hat would show its rim through its fill).
static func _faded(mod: Color) -> Color:
	return Color(mod.r * mod.a, mod.g * mod.a, mod.b * mod.a, 1.0)

# lobby_cards.gd calls this for each seat with every seats message (c: the card; live: the
# card shows a person or a bot; settled: the lobby is up and the motion polish is on). A new
# hat drops onto the head; a changed one also pops the card, with a hop and sparks.
static func card_change(cards, c: Dictionary, i: int, live: bool, settled: bool) -> void:
	var now := of(i)
	var had := int(c.get("hat", -9))
	if now == had:
		return
	c["hat"] = now
	if not settled or had == -9 or now < 0 or not live:
		c["hat_at"] = -9.0
		return
	c["hat_at"] = float(cards.t) + (0.05 * i if had < 0 else 0.0)     # (the season just came on: one after another)
	if had >= 0:
		c["hat_new"] = float(cards.t)        # (a pick: the card's award ribbon stays out of the way for a moment, award_fold)
		c["pop"] = 0.0
		c["hop"] = 0.0
		cards._sparks(c, i)

# After a match a card's award hangs as a ribbon right where its fighter's hat is. So
# with hats on they take turns: the ribbon shows for one turn (lobby_cards.gd AWARD_S, 3.2 s),
# then folds away for one and the hat shows. A hat that just changed shows at once, for 4 s.
# The award's round picture beside the fighter stays. Without a hat: as it always was.
static func award_share(i: int) -> int:
	return 2 if of(i) >= 0 else 1

# sy: the ribbon's height as lobby_cards.gd has it (1 full, small while it flips).
static func award_fold(cards, c: Dictionary, i: int, sy: float) -> float:
	if of(i) < 0:
		return sy
	var turn: float = cards.AWARD_S
	var ph := fmod(float(cards.t), turn)
	if int(float(cards.t) / turn) % 2 == 1 or float(cards.t) - float(c.get("hat_new", -9.0)) < 4.0:
		return 0.001             # folded away (a ribbon this thin cannot be seen)
	return clampf(minf(ph / 0.18, (turn - ph) / 0.18), 0.001, 1.0)

# The hat on a seat card's little fighter (lobby_cards.gd calls this right after it drew
# the fighter; xf: where the card is, [its middle, its scale]).
static func on_card(n: CanvasItem, cards, i: int, xf: Array, seat_col: Color) -> void:
	var k := of(i)
	if k < 0:
		return
	var c: Dictionary = cards.cards[i]
	var kind := int(c["kind"])
	if kind == 0 and not c["fill"]:
		return                   # an open seat is a dark shape: no hat
	var age: float = float(cards.t) - float(c.get("hat_at", -9.0))
	if age < 0.0:
		return                   # (its turn to drop on has not come yet)
	var hop: float = c["hop"]
	var lift := -sin(PI * clampf(hop / 0.36, 0.0, 1.0)) * 70.0 if hop < 0.36 else 0.0   # (as lobby_cards.gd _fighter)
	var dir := 1.0 if i < 4 else -1.0
	var s: float = cards.SCALE
	var frame: int = cards._frame(i)
	var h: Array = HEAD[clampi(frame, 0, HEAD.size() - 1)]
	var sw := _swing("card%d" % i)
	sw.step_at(float(cards.t), Vector2(float(h[0]) * dir, float(h[1]) + lift / s), lift == 0.0, dir, k)
	var feet := Vector2(0.0, float(cards.FEET) + lift)
	var grow := 1.0
	if age < 0.4:                # a new hat drops on from above and settles with a small bounce
		feet.y += (Art.ease_out_back(age / 0.4) - 1.0) * 70.0
		grow = 1.0 + 0.3 * sin(PI * age / 0.4)
	var tint := Color.WHITE
	if kind == 2:
		tint = Color(0.88, 0.88, 0.95)
	elif kind == 0:
		tint = _faded(Color(0.62, 0.62, 0.72, 0.85))
	if c["away"]:
		tint = _faded(Color(0.6, 0.6, 0.65, 0.9))
	var card_xf := Transform2D(0.0, Vector2.ONE * float(xf[1]), 0.0, xf[0])
	var hat_xf := frame_xf(feet, s, frame, dir, sw)
	hat_xf = hat_xf * Transform2D(0.0, Vector2.ONE * grow, 0.0, Vector2.ZERO)
	draw(n, k, seat_col, card_xf * hat_xf, sw.a, tint, int(cards.tier) > 1, rim_for(s))

# ------------------------------------------------------------------ the match's seat cards (the HUD)
# A small hat on the head in a seat's card at the top of a match (hud.gd draws the head of
# the sheet's first frame into `tile`, 4 px in from its edges). dim: knocked out or waiting.
static func on_hud(c: CanvasItem, seat: int, tile: Rect2, seat_col: Color, dim: float) -> void:
	var k := of(seat)
	if k < 0:
		return
	var z := (tile.size.x - 8.0) / 38.0                  # the head's size in the tile (hud.gd HEAD_SRC is 38 px wide)
	var top := tile.position + Vector2(4.0, 4.0) + Vector2(17.5, 7.5) * z     # the hood's top in that picture, a little lower: the hat sits deep
	var s := z * 0.72                                    # smaller than the head's own size: the card is the screen's top edge
	draw(c, k, seat_col, Transform2D(0.0, Vector2(s, s), 0.0, top), 0.0, Color(dim, dim, dim), false, rim_for(s) * 0.85)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

# ------------------------------------------------------------------ the winner's screen
# The hat on the fighter that drops onto the podium (winner_view.gd, when the painted hero
# is off): feet: where its feet are; s: its size; frame: its pose.
static func on_podium(c: CanvasItem, seat: int, feet: Vector2, s: float, frame: int, t: float, seat_col: Color) -> void:
	var k := of(seat)
	if k < 0:
		return
	var sw := _swing("podium")
	var h: Array = HEAD[clampi(frame, 0, HEAD.size() - 1)]
	sw.step_at(t, feet / s + Vector2(float(h[0]), float(h[1])), frame != 9, 1.0, k)
	draw(c, k, seat_col, frame_xf(feet, s, frame, 1.0, sw), sw.a, Color.WHITE, true, rim_for(s))
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

# Where a hat sits on each seat's painted hero (assets/heroes/hero_<seat>.png, 540 x 720):
# [x, y of the hat's origin in the picture, the tilt in degrees]. The hood there is a
# pointed cowl seen from the front: the hat covers its point.
const HERO_TOP := [[227, 171, -5.0], [226, 155, -5.0], [234, 159, -5.0], [228, 167, -5.0],
	[226, 170, -5.0], [228, 170, -5.0], [228, 153, -5.0], [229, 170, -5.0]]
const HERO_SIZE := 4.2
const HERO_RIM := 1.9             # the rim on the painting: bold, like its ink lines
const HERO_DIR := [1.0, -1.0, 1.0, 1.0, 1.0, 1.0]     # the elf hat's tip curls away from the hero's bow

# The hat on the winner's painted hero (winner_view.gd; r: where the picture is drawn, its
# top left corner and its size before the podium cuts it; alpha: the screen's fade in).
static func on_hero(c: CanvasItem, seat: int, r: Rect2, t: float, seat_col: Color, alpha: float) -> void:
	var k := of(seat)
	if k < 0 or alpha < 0.99:
		return
	var a: Array = HERO_TOP[posmod(seat, HERO_TOP.size())]
	var dir: float = HERO_DIR[k]
	var top := r.position + Vector2(float(a[0]), float(a[1]))
	var sw := _swing("hero")
	sw.step_at(t, top / HERO_SIZE, true, dir, k)
	var xf := Transform2D(deg_to_rad(float(a[2])) + sw.lean * dir, Vector2(dir * HERO_SIZE, HERO_SIZE * (1.0 - sw.bob * 0.035)), 0.0,
		top + Vector2(0, sw.bob * HERO_SIZE))
	draw(c, k, seat_col, xf, sw.a, Color.WHITE, true, HERO_RIM, true)
	c.draw_set_transform_matrix(Transform2D.IDENTITY)

# ------------------------------------------------------------------ the HAT button
# The button on your own lobby card (lobby.gd adds one over the cards and calls place every
# frame). It shows the hat you wear and six dots, one lit. A tap asks the server for the
# next hat ({"kind": "hat", "hat": n}); the server says so in its next seats message, and
# every phone shows it. It is a lobby_art.gd Btn: it squeezes under the finger, springs
# back and jumps (polish "motion"); only its face is drawn here.
class Pick extends Art.Btn:
	signal picked(hat: int)
	var hats = load("res://client/hats.gd")
	var seat := -1
	var seat_col := Color.WHITE
	var worn := -1              # the hat my seat wears (the server's word)
	var asked := -1             # the hat my last tap asked for, until the server says it
	var asked_ms := 0
	var tapped := false         # tapped once this visit: it stops breathing
	var grow := 1.0             # my card's own size now (it pops)
	var _cards = null           # the seat cards (lobby_cards.gd) my card is on

	func _init() -> void:
		super()
		visible = false
		pressed.connect(_on_tap)

	# The hat the dots and the picture show: the one asked for, while the answer is on its way.
	func shown() -> int:
		return asked if asked >= 0 else worn

	func _on_tap() -> void:
		var from := shown()
		if from < 0:
			return
		asked = (from + 1) % hats.COUNT
		asked_ms = Time.get_ticks_msec()
		tapped = true
		pop()
		queue_redraw()
		picked.emit(asked)

	# Where my card is now (cards: lobby_cards.gd), or hidden when there is no hat to pick.
	func place(cards, my_seat: int, can_pick: bool) -> void:
		var now: int = hats.of(my_seat) if can_pick else -1
		visible = now >= 0
		if not visible:
			asked = -1
			return
		if now != worn or my_seat != seat:
			worn = now
			seat = my_seat
			seat_col = cards.World.TEAM[my_seat % 8]
			queue_redraw()
		if asked >= 0 and (asked == worn or Time.get_ticks_msec() - asked_ms > 1500):
			asked = -1             # the server said it (or never did): the dots follow the server again
			queue_redraw()
		_cards = cards
		_follow()
		# And once more at the end of this frame. game_client.gd calls place() before the cards
		# move (lobby_cards.gd _process comes after it), so without this the button is one frame
		# behind its card: on a page that draws 3 frames a second, the card's name slid under the
		# button while the card popped.
		_follow.call_deferred()

	# Sit at the bottom of my card as the card is now, and grow and shrink with it.
	func _follow() -> void:
		if not visible or seat < 0 or not is_instance_valid(_cards):
			return
		var xf: Array = _cards._xf(seat)
		grow = float(xf[1])
		size = Vector2(float(_cards.W) - 14.0, 68.0)
		position = xf[0] + Vector2(0.0, float(_cards.FEET) + 101.0) * grow - size * 0.5
		pulse = grow * (1.0 if tapped else 1.0 + 0.03 * sin(float(_cards.t) * 4.5))     # it breathes until the first tap
		apply_size()

	# A thumb's target bigger than the face: the card's whole width, from the name down.
	func _has_point(point: Vector2) -> bool:
		return Rect2(-8.0, -38.0, size.x + 16.0, size.y + 44.0).has_point(point)

	func _draw() -> void:
		var down := get_draw_mode() == DRAW_PRESSED or get_draw_mode() == DRAW_HOVER_PRESSED
		var top := 8.0 if down else 3.0
		var mid := (top + size.y - (4.0 if down else 11.0)) * 0.5
		if not down:
			draw_rect(Rect2(16, top + 2, size.x - 32, 2), Color(1, 1, 1, 0.26))
		var k := shown()
		if k < 0:
			return
		# the hat, in my colour, at the left
		var at: Vector2 = ICON_AT[k]
		hats.draw(self, k, seat_col, Transform2D(0.0, Vector2(0.9, 0.9), 0.0, Vector2(32.0 + at.x, mid + at.y * 1.12)), 0.0, Color.WHITE, true, 2.3)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# HAT, in the letters the lobby's other buttons already use (size 40, made smaller here: no new sheet of letters)
		draw_set_transform(Vector2(62.0, mid + 10.5), 0.0, Vector2(0.75, 0.75))
		draw_string_outline(Art.DISPLAY, Vector2.ZERO, "HAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, 5, Color(face.darkened(0.7), 0.85))
		draw_string(Art.DISPLAY, Vector2.ZERO, "HAT", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, ink)
		draw_set_transform_matrix(Transform2D.IDENTITY)
		# six dots, the hat I wear lit
		for d in hats.COUNT:
			var dc := Vector2(122.0 + d * 12.4, mid)
			if d == k:
				draw_circle(dc, 5.6, Color(RIM, 0.9))
				draw_circle(dc, 4.3, seat_col.lightened(0.3))
			else:
				draw_circle(dc, 2.9, Color(ink, 0.45))

	# Where each hat's origin goes so its picture sits in the middle of the button's left end.
	const ICON_AT := [Vector2(3.5, 0.8), Vector2(-1.5, 5.6), Vector2(-1.0, 4.8), Vector2(2.5, -9.4), Vector2(0, 3.6), Vector2(0, 1.0)]

# ------------------------------------------------------------------ a test page
# ?hatsheet on the page's address (game_client.gd): the six hats big, then every seat in
# every hat at the game's size and at a phone's size. ?hatsheet=N: hat N on every pose.
# ?hatsheet=hero: the eight painted heroes in hats. ?hatsheet=move: six fighters, one in
# each hat, run, jump, land, turn, roll, aim and are knocked out, again and again, with the
# arena's own hat code (Arena): for a film of the motion (tools/v2_motion_clip.py --script
# hatmove; ?slowmo=N slows it). For pictures; it joins no server.
class Sheet extends Control:
	const COLORS := [Color("e8413c"), Color("3c8ce8"), Color("5fd35a"), Color("f2c230"),
		Color("a85ae8"), Color("f08a2c"), Color("35d6d0"), Color("f06aa8")]     # world.gd TEAM
	const POSES := [0, 3, 8, 9, 19, 13, 14, 20, 21, 11, 12, 27, 18, 10]
	const FLOOR := 360.0          # the moving stage's floor, in the stage's own pixels (a whole number of 30 px cells, as an arena's floors)
	const ZOOM := 2.25            # the stage is drawn this much bigger than the 1920 x 1080 design's pixels
	const LOOP := 13.0            # the moving stage's routine, seconds
	var hats = load("res://client/hats.gd")
	var tex: Array = []
	var heroes: Array = []
	var mode := ""
	var t := 0.0
	var base := Transform2D.IDENTITY      # the 1920 x 1080 design on the window
	var stage: Node2D                     # ?hatsheet=move: the sprites and the arena's hat layer
	var layer
	var sprites: Array = []

	# The moving stage's ground: solid under FLOOR (the arena's hat code asks a level for its cells).
	class _Ground extends RefCounted:
		func cell_at(_x: float, y: float) -> int:
			return 1 if y >= 360.0 else 0

	func _init(what: String = "", slow: float = 1.0) -> void:
		mode = what
		set_anchors_preset(Control.PRESET_FULL_RECT)
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		for i in 8:
			tex.append(load("res://assets/fighter_p%d.png" % i))
		if mode == "hero":
			for i in 8:
				heroes.append(load("res://assets/heroes/hero_%d.png" % i))
		if mode == "move":
			Engine.time_scale = 1.0 / clampf(slow, 1.0, 20.0)
			hats.Season.now = "christmas"
			hats.seat_hat = [0, 1, 2, 3, 4, 5]
			stage = Node2D.new()
			add_child(stage)
			for i in 6:
				var spr := Sprite2D.new()
				spr.texture = tex[i]
				spr.region_enabled = true
				spr.offset = Vector2(0, -58)          # (as world.gd: the sprite's place is its feet)
				stage.add_child(spr)
				sprites.append([spr])
			layer = hats.Arena.new()
			stage.add_child(layer)
			layer.setup(COLORS)

	func _process(delta: float) -> void:
		t += delta
		if mode == "move":
			_move(delta)
		queue_redraw()

	# One fighter's part in the routine at time u (seconds into the loop): [x from its
	# start, y over the floor, the frame, facing right?, on the ground?, the state].
	func _part(u: float, i: int) -> Array:
		if u < 0.8:
			return [0.0, 0.0, int(u * 2.2) % 2, true, true, P.F_NORMAL]
		if u < 2.1:                    # a run to the right
			return [(u - 0.8) * 405.0, 0.0, 2 + int(u * 12.0 + i) % 6, true, true, P.F_NORMAL]
		if u < 2.6:
			return [526.0, 0.0, 0, true, true, P.F_NORMAL]
		if u < 3.4:                    # a jump on the spot
			var a := u - 2.6
			var y := 560.0 * a - 700.0 * a * a
			return [526.0, y, 8 if a < 0.4 else 9, true, false, P.F_NORMAL]
		if u < 3.56:
			return [526.0, 0.0, 27, true, true, P.F_NORMAL]
		if u < 4.3:                    # a turn
			return [526.0, 0.0, 0, u < 3.9, true, P.F_NORMAL]
		if u < 5.6:                    # a run back
			return [526.0 - (u - 4.3) * 405.0, 0.0, 2 + int(u * 12.0 + i) % 6, false, true, P.F_NORMAL]
		if u < 6.0:
			return [0.0, 0.0, 1, false, true, P.F_NORMAL]
		if u < 6.5:                    # a dodge roll
			return [-(u - 6.0) * 420.0, 0.0, 14 + int((u - 6.0) * 20.0) % 4, false, true, P.F_DODGE]
		if u < 7.3:
			return [-210.0, 0.0, 0, u >= 6.9, true, P.F_NORMAL]
		if u < 8.4:                    # aiming
			return [-210.0, 0.0, 19, true, true, P.F_NORMAL]
		if u < 11.6:                   # knocked out: thrown back, then lying
			var a := u - 8.4
			var back := minf(a, 0.35) * 260.0
			var up := maxf(0.0, 150.0 * a - 430.0 * a * a)
			return [-210.0 - back, up, 22 if a < 0.1 else (23 if a < 0.22 else (24 if a < 0.35 else (25 if a < 0.45 else 26))), true, a >= 0.35, P.F_DEAD]
		return [-210.0 + (u - 11.6) * 150.0, 0.0, 2 + int(u * 12.0 + i) % 6, true, true, P.F_NORMAL]     # the next round: back to the start

	func _move(delta: float) -> void:
		var k := minf(size.x / 1920.0, size.y / 1080.0)
		stage.scale = Vector2(k, k) * ZOOM
		var fl: Array = []
		for i in 6:
			var u := fposmod(t - 0.18 * i, LOOP)
			var part := _part(u, i)
			var spr: Sprite2D = sprites[i][0]
			var frame: int = part[2]
			spr.position = Vector2(150.0 + i * 118.0 + float(part[0]) * 0.42, FLOOR - float(part[1]) * 0.6)
			spr.region_rect = Rect2((frame % 16) * 128, (frame / 16) * 128, 128, 128)
			spr.flip_h = not part[3]
			fl.append({"id": i, "state": part[5], "flags": (1 if part[3] else 0) | (2 if part[4] else 0), "vx": -1 if int(part[5]) == P.F_DEAD else 0, "vy": 0})
		layer.show_view(fl, sprites, {}, delta, _ground, false)

	var _ground := _Ground.new()

	func _fighter(feet: Vector2, s: float, seat: int, frame: int, dir: float, kind: int, swing: float, detail: bool) -> void:
		var fs := 128.0 * s
		var dst := Rect2(feet.x - fs * 0.5, feet.y - 122.0 * s, fs, fs)
		if dir < 0.0:
			dst.size.x = -dst.size.x
		draw_set_transform_matrix(base)
		draw_texture_rect_region(tex[seat], dst, Rect2((frame % 16) * 128, (frame / 16) * 128, 128, 128))
		hats.draw(self, kind, COLORS[seat], base * hats.frame_xf(feet, s, frame, dir), swing, Color.WHITE, detail, hats.rim_for(s))
		draw_set_transform_matrix(base)

	func _draw() -> void:
		var k := minf(size.x / 1920.0, size.y / 1080.0)
		base = Transform2D(0.0, Vector2(k, k), 0.0, Vector2.ZERO)
		draw_set_transform_matrix(base)
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.09, 0.09, 0.15))
		if mode == "move":            # the stage: a night sky, a stone floor; the fighters and their hats are nodes over it
			draw_rect(Rect2(0, 0, 1920, 1080), Color(0.11, 0.12, 0.2))
			draw_rect(Rect2(0, FLOOR * ZOOM, 1920, 1080 - FLOOR * ZOOM), Color(0.2, 0.22, 0.3))
			draw_rect(Rect2(0, FLOOR * ZOOM, 1920, 8), Color(0.34, 0.37, 0.47))
			return
		if mode == "hero":
			for i in 8:
				var at := base * Transform2D(0.0, Vector2(0.75, 0.75), 0.0, Vector2(20 + (i % 4) * 475, 10 + (i / 4) * 535))
				draw_set_transform_matrix(at)
				draw_texture_rect(heroes[i], Rect2(0, 0, 540, 720), false)
				var a: Array = hats.HERO_TOP[i]
				var kind: int = (i + int(t / 3.0)) % hats.COUNT
				var dir: float = hats.HERO_DIR[kind]
				hats.draw(self, kind, COLORS[i], at * Transform2D(deg_to_rad(float(a[2])), Vector2(dir * hats.HERO_SIZE, hats.HERO_SIZE), 0.0,
					Vector2(float(a[0]), float(a[1]))), 0.0, Color.WHITE, true, hats.HERO_RIM, true)
			return
		if mode.is_valid_int():       # one hat on every pose, big (its tail swinging); then at the game's size
			var kind := clampi(int(mode), 0, hats.COUNT - 1)
			var big := [0, 3, 9, 19, 13, 14, 21, 0, 0, 0, 0, 11, 20, 27]
			for j in big.size():       # (the standing ones of the second row: the tail at its two ends and half way)
				var sw: float = [-1.0, -0.5, 0.5, 1.0][j - 7] * hats.LIMIT[kind] if j >= 7 and j < 11 else 0.0
				_fighter(Vector2(130.0 + (j % 7) * 265.0, 320.0 + (j / 7) * 330.0), 2.6, j % 8, big[j], 1.0, kind, sw, true)
			draw_rect(Rect2(0, 700, 1920, 380), Color(0.3, 0.33, 0.42))
			for j in POSES.size():
				_fighter(Vector2(80.0 + j * 132.0, 860.0), 1.0, j % 8, POSES[j], 1.0 if j % 2 == 0 else -1.0, kind, 0.0, true)
				_fighter(Vector2(80.0 + j * 132.0, 1040.0), 1.0, (j + 3) % 8, POSES[j], 1.0 if j % 2 == 0 else -1.0, kind, 0.0, false)
			return
		for kind in hats.COUNT:
			_fighter(Vector2(170.0 + kind * 310.0, 400.0), 3.2, kind, 0, 1.0, kind, 0.0, true)
		draw_rect(Rect2(0, 640, 1920, 220), Color(0.3, 0.33, 0.42))
		for seat in 8:
			for kind in hats.COUNT:
				_fighter(Vector2(60.0 + (seat * 6 + kind) * 38.5, 540.0), 1.0, seat, 0, 1.0, kind, 0.0, true)
				_fighter(Vector2(60.0 + (seat * 6 + kind) * 38.5, 760.0), 1.0, seat, 3, -1.0, kind, 0.0, false)
				_fighter(Vector2(40.0 + (seat * 6 + kind) * 39.0, 940.0), 0.36, seat, 0, 1.0, kind, 0.0, false)
				_fighter(Vector2(40.0 + (seat * 6 + kind) * 39.0, 1020.0), 0.5, seat, 3, 1.0, kind, 0.0, false)

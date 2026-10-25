# p4.12 GHOSTFACE (the user's daughter's favourite Halloween character), drawn by
# powers_view.gd in place of the archer (world.gd hides the archer's sprite while the
# power-up row's mask byte has bit 1). The look: a black hooded robe that flows (its
# ragged hem trails behind a run and billows up in a fall), the white ghost mask (a long
# face, big black eyes that droop at the outer corners, the long open mouth), a black
# glove and a hunting knife. The knife comes up while shoot is held (mask bit 8) and
# swings down in front on the let-go (E_KNIFE: a white swoosh follows the blade);
# knocked down (mask bit 2) it falls on its back, and on E_MASK_UP it rises.
# Every shape is drawn in the figure's own frame: its feet at (0, 0), up is -y.
extends RefCounted

const P = preload("res://sim/proto.gd")
const BLACK := Color(0.035, 0.03, 0.045)
const FOLD := Color(0.19, 0.18, 0.24)
const WHITE := Color(0.97, 0.96, 0.93)
const SHADE := Color(0.66, 0.66, 0.72)
const HOLE := Color(0.015, 0.012, 0.02)
const STEEL := Color(0.86, 0.89, 0.94)
const GLOVE_EDGE := Color(0.32, 0.32, 0.38)
const SWING_S := 0.23        # the swing on the page (sim KNIFE_TICKS / 60)
const RAISED := -2.0         # the knife arm held up (radians from straight ahead, the way it faces; up is minus)
const DONE := 0.95           # the arm at the end of the swing: down in front
const IDLE := 0.7            # the arm at rest: low, the knife pointing down
const BLADE_TURN := 0.9      # the blade points this much further round than the arm (the fist holds it blade-down)

# A filled shape with a smooth edge (a filled polygon has no smoothing of its own).
static func _shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, edge: Color, w: float) -> void:
	ci.draw_colored_polygon(pts, fill)
	var ring := pts.duplicate()
	ring.append(pts[0])
	ci.draw_polyline(ring, edge, w, true)

# The mask alone, its middle at c, s = 1 for 22 px tall; dir turns it a little the way
# it faces (0: straight on, for the banner's icon).
static func face(ci: CanvasItem, c: Vector2, s: float, dir: float, a: float) -> void:
	var egg := PackedVector2Array()
	for i in 28:
		var th := TAU * i / 28.0
		var sn := sin(th)
		var rx := 7.4 * (1.0 - 0.24 * maxf(0.0, sn)) * (1.0 - 0.06 * absf(dir))   # the chin narrower
		var ry := 9.6 if sn < 0.0 else 12.4                                       # and longer
		egg.append(c + Vector2(cos(th) * rx, sn * ry) * s)
	_shape(ci, egg, Color(WHITE, a), Color(SHADE, a), 1.2 * s)
	var fc := c + Vector2(dir * 1.3, 0.0) * s
	ci.draw_line(fc + Vector2(-5.2, -4.4) * s, fc + Vector2(5.2, -4.4) * s, Color(SHADE, 0.35 * a), 1.0 * s, true)   # the brow
	for side in [-1.0, 1.0]:
		var ec: Vector2 = fc + Vector2(side * 3.7, -2.4) * s
		var ax := Vector2(side * cos(0.55), sin(0.55))      # its long way: down and out
		var ay := Vector2(-ax.y, ax.x)
		var eye := PackedVector2Array()
		for i in 16:
			var th := TAU * i / 16.0
			var along := cos(th)
			var w := 1.9 * (1.0 + 0.3 * along)              # a little wider at the outer end
			eye.append(ec + (ax * along * 3.7 + ay * sin(th) * w) * s)
		_shape(ci, eye, Color(HOLE, a), Color(HOLE, a), 0.8 * s)
	var mouth := PackedVector2Array()
	for i in 18:
		var th := TAU * i / 18.0
		var sn := sin(th)
		mouth.append(fc + Vector2(cos(th) * 2.1 * (1.0 + 0.25 * maxf(0.0, sn)), 5.4 + sn * 4.7) * s)
	_shape(ci, mouth, Color(HOLE, a), Color(HOLE, a), 0.8 * s)

# A sleeve from the shoulder to the hand: narrow at the shoulder, wide at the cuff.
static func _sleeve(ci: CanvasItem, sh: Vector2, hand: Vector2, a: float, edge: Color) -> void:
	var d := hand - sh
	if d.length() < 1.0:
		return
	var n := Vector2(-d.y, d.x).normalized()
	_shape(ci, PackedVector2Array([sh + n * 4.5, hand + n * 6.0, hand - n * 6.0, sh - n * 4.5]), Color(BLACK, a), edge, 1.2)

# The whole figure. f: the fighter as drawn this frame; pw: its power-up row; tc: its
# seat's colour (a thin rim round the robe, so everyone can tell who it is); knife_at,
# down_at, up_at: when (t) it last swung, fell and got up.
static func draw(ci: CanvasItem, f: Dictionary, pw: Dictionary, a: float, t: float, tc: Color, knife_at: float, down_at: float, up_at: float) -> void:
	var mk: int = pw.get("mask", 0)
	var flags: int = f["flags"]
	var dir := 1.0 if (flags & 1) != 0 else -1.0
	var feet := Vector2(f["x"] + 18.0, f["y"] + 63.0)
	var dead: bool = f["state"] == P.F_DEAD
	var down := (mk & 2) != 0
	var pinned := dead and (flags & 4) != 0
	var vx := float(f["vx"])
	var vy := float(f["vy"])
	var ground := (flags & 2) != 0
	# how far over it lies: 0 standing .. 1 on its back (it falls fast and rises slower)
	var lie := 0.0
	if dead and not pinned:
		lie = 1.0
	elif down:
		lie = clampf((t - down_at) / 0.22, 0.0, 1.0)
	elif t - up_at < 0.35:
		lie = 1.0 - clampf((t - up_at) / 0.35, 0.0, 1.0)
	var lean := 0.0
	if pinned:
		lean = -dir * 0.14
	elif lie == 0.0 and ground and absf(vx) >= 2.0:
		lean = dir * 0.1
	elif lie == 0.0 and not ground:
		lean = clampf(vx * 0.015, -0.12, 0.12)
	var xf := Transform2D(-dir * PI * 0.5 * lie + lean, feet + Vector2(dir * 30.0 * lie, -14.0 * lie))
	if f["state"] == P.F_DODGE and (flags & 32) != 0:   # a roll: it spins round its middle
		xf = Transform2D(dir * float(f["st"]) * 0.55, feet + Vector2(0, -31)) * Transform2D(0.0, Vector2(0, 31))
	if (int(pw.get("bits", 0)) & P.PW_TINY) != 0:
		xf = xf * Transform2D(0.0, Vector2(0.55, 0.55), 0.0, Vector2.ZERO)
	ci.draw_set_transform_matrix(xf)
	var rim := Color(tc, 0.6 * a)
	var still := lie > 0.0 or dead
	var sway := 0.0 if still else clampf(-vx * 1.1, -10.0, 10.0)                       # the hem trails a run
	var lift := 0.0 if still or ground else clampf(vy * 0.9, -4.0, 9.0)                 # and billows in a fall
	var flut := 0.5 if still else minf(1.6 + absf(vx) * 0.25, 3.2)
	# the arm at the back: a hanging sleeve
	var bsh := Vector2(-dir * 9.0, -40.0)
	var bhand := Vector2(-dir * 12.5 + sway * 0.25, -21.0 + sin(t * 2.0) * 0.8)
	_sleeve(ci, bsh, bhand, a, rim)
	ci.draw_circle(bhand + Vector2(0, 2.5), 3.2, Color(BLACK, a))
	# the robe: shoulders, down the sides, a ragged hem that flutters (the sides go with the
	# hem as it trails and lifts, so the outline never crosses itself)
	var side_y := -30.0 - lift * 0.6
	var robe := PackedVector2Array([Vector2(-12.5, -43.0), Vector2(-15.0 + sway * 0.6, side_y)])
	var half := 21.0 + lift * 0.5
	for i in 9:
		var u := i / 8.0
		var x := lerpf(-half, half, u) + sway * (0.8 + 0.2 * sin(t * 3.0 + u * 4.0))
		var y := -1.5 - lift - (6.5 if i % 2 == 1 else 0.0) + sin(t * 9.0 + u * 11.0) * flut
		robe.append(Vector2(x, y))
	robe.append(Vector2(15.0 + sway * 0.6, side_y))
	robe.append(Vector2(12.5, -43.0))
	robe.append(Vector2(0.0, -46.0))
	_shape(ci, robe, Color(BLACK, a), rim, 1.5)
	for k in 3:   # folds catching a little light
		var x0 := -6.0 + k * 5.5
		ci.draw_polyline(PackedVector2Array([Vector2(x0, -40.0), Vector2(x0 * 1.3 + sway * 0.4, -22.0),
			Vector2(x0 * 1.6 + sway * 0.8 + sin(t * 9.0 + k) * flut, -7.0 - lift)]), Color(FOLD, a), 1.4, true)
	# the hood, coming to a soft point at the top, a little back
	var hood := PackedVector2Array()
	for i in 20:
		var th := TAU * i / 20.0
		var p := Vector2(cos(th) * 16.0, sin(th) * 17.0)
		if sin(th) < -0.85:
			p += Vector2(-dir * 2.0, -4.5)
		hood.append(Vector2(0.0, -56.0) + p)
	_shape(ci, hood, Color(BLACK, a), rim, 1.5)
	face(ci, Vector2(dir * 2.0, -55.0), 1.13, dir, a)
	# the knife arm: at rest low, held up while shoot is held, swinging down on the let-go
	var sh := Vector2(dir * 6.5, -40.0)
	var phi := IDLE + sin(t * 2.0) * 0.05
	var since := t - knife_at
	var swinging := not still and since < SWING_S + 0.08
	if still:
		phi = 1.25
	elif swinging:
		var p := clampf(since / SWING_S, 0.0, 1.0)
		phi = lerpf(RAISED, DONE, 1.0 - pow(1.0 - p, 3.0))   # fast down, then it stops
	elif (mk & 8) != 0:
		phi = RAISED + sin(t * 31.0) * 0.03                   # held up, shaking a little
	if swinging and phi - RAISED > 0.15:   # the swoosh behind the blade's tip
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var fade := clampf(1.0 - since / (SWING_S + 0.08), 0.0, 1.0)
		for k in 10:
			var q := lerpf(RAISED, phi, k / 9.0)
			pts.append(_tip(sh, q, dir, 19.0))
			cols.append(Color(1, 1, 1, 0.85 * fade * a * k / 9.0))
		for k in range(9, -1, -1):
			var q := lerpf(RAISED, phi, k / 9.0)
			pts.append(_tip(sh, q, dir, 8.0))
			cols.append(Color(0.85, 0.9, 1.0, 0.3 * fade * a * k / 9.0))
		ci.draw_polygon(pts, cols)
	var arm := Vector2(dir * cos(phi), sin(phi))
	var hand := sh + arm * 16.0
	_sleeve(ci, sh, hand, a, rim)
	if not dead:   # a dead GHOSTFACE has dropped it
		var bd := Vector2(dir * cos(phi + BLADE_TURN), sin(phi + BLADE_TURN))
		var bn := Vector2(-bd.y, bd.x)
		ci.draw_line(hand - bd * 5.0, hand + bd * 1.5, Color(0.08, 0.06, 0.05, a), 3.6, true)          # the handle
		ci.draw_line(hand + bd * 1.8 + bn * 2.6, hand + bd * 1.8 - bn * 2.6, Color(0.55, 0.56, 0.6, a), 1.6, true)   # the guard
		_shape(ci, PackedVector2Array([hand + bd * 2.2 + bn * 1.7, hand + bd * 18.0, hand + bd * 12.0 - bn * 1.9, hand + bd * 2.2 - bn * 1.9]),
			Color(STEEL, a), Color(0.5, 0.53, 0.6, a), 0.9)
		ci.draw_line(hand + bd * 3.0 + bn * 0.9, hand + bd * 15.0 + bn * 0.2, Color(1, 1, 1, 0.7 * a), 0.8, true)    # its shine
	ci.draw_circle(hand, 3.8, Color(BLACK, a))
	ci.draw_arc(hand, 3.8, 0.0, TAU, 14, Color(GLOVE_EDGE, a), 1.0, true)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)

# Where the blade's point (along = 19) or its middle (8) is, the arm at angle q.
static func _tip(sh: Vector2, q: float, dir: float, along: float) -> Vector2:
	var hand := sh + Vector2(dir * cos(q), sin(q)) * 16.0
	return hand + Vector2(dir * cos(q + BLADE_TURN), sin(q + BLADE_TURN)) * along

# The banner's picture: the hood and the mask, bobbing.
static func icon(ci: CanvasItem, c: Vector2, s: float, a: float, tt: float) -> void:
	var cc := c + Vector2(0, sin(tt * 2.5) * s * 0.06)
	ci.draw_circle(cc + Vector2(0, s * 0.05), s * 0.98, Color(BLACK, a))
	face(ci, cc + Vector2(0, s * 0.08), s / 14.0, 0.0, a)

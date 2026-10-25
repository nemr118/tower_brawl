# p4.9 the power-ups on the page, on every look (LOW too: they are part of play).
# An orb's warning: the electricity builds up over its spot, a ring closes in on the
# spot as the bolt comes (when it closes, the bolt strikes), the power-up's name over
# it. The lightning: the bench test's bolt, a flash, a shock ring. A body the bolt
# killed: the electricity runs through it (arcs, the body flickers: world.gd asks
# zapped()). The orbs, bobbing, their name under them; a BIG one gold. The pop when
# someone takes one (its name rises over them). The ghost cats, the rain, and what
# each fighter has: a shield bubble, wings, an umbrella, ice, spikes, speed lines.
# All drawn by hand (_draw), no particles. A child node on the glow layer adds the
# light: the bolt, the sparks, the glow of the orbs and cats, the flash.
extends Node2D

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const COLORS := {P.PU_FIRE: Color(1.0, 0.55, 0.15), P.PU_BOMB: Color(1.0, 0.32, 0.25), P.PU_POISON: Color(0.72, 0.4, 1.0),
	P.PU_SMOKE: Color(0.8, 0.82, 0.88), P.PU_SHIELD: Color(0.35, 0.85, 1.0), P.PU_INF: Color(1.0, 0.85, 0.3),
	P.PU_FLY: Color(0.95, 0.97, 1.0), P.PU_BIG: Color(0.5, 1.0, 0.45), P.PU_CATS: Color(0.55, 1.0, 0.6),
	P.PU_RAIN: Color(0.45, 0.65, 1.0), P.PU_INVIS: Color(0.85, 0.85, 1.0), P.PU_FREEZE: Color(0.6, 0.9, 1.0),
	P.PU_SPIKES: Color(1.0, 0.72, 0.3), P.PU_SPEED: Color(1.0, 0.95, 0.35)}
const GOLD := Color(1.0, 0.82, 0.25)
const BOLT_COL := Color(0.62, 0.78, 1.0)
const ZAP_S := 1.8                 # the electricity runs through a body this long
const PV_WHITE := Color(1, 1, 1)

var world                          # the arena (its fx: flashes, lights, shake)
var glow_node: Node2D
var font: Font
var t := 0.0
var view := {}
var me := -1
var team: Array = []
var fighters := {}                 # seat -> the fighter as drawn this frame
var powers := {}                   # seat -> {bits, kind, left}
var zaps := {}                     # seat -> seconds of electricity left
var bolts: Array = []              # [to, secs left, big, points]
var pops: Array = []               # [pos, text, colour, secs left, secs, big, what it does]
var rings: Array = []              # [pos, max r, colour, secs, secs left]
var flash := 0.0                   # the arena lights up (a strike, a freeze), 1 .. 0
var flash_col := Color.WHITE
var drops: Array = []              # the rain's streaks
var jag_t := 0.0                   # the electricity is redrawn this often (it crackles)
var arcs := {}                     # key -> [PackedVector2Array]: the warnings' and the bodies' arcs
var blind := false                 # your fighter stands in smoke: the others are out of sight
var bolt_s := 0.4                  # a bolt shows this long (a test knob: the page's bolt_s= holds it for pictures)
var names: Array = []              # the seats' names (the game client sets them), for a BIG warning's "for"

class _Glow extends Node2D:
	var pv
	func _draw() -> void:
		if pv != null:
			pv._paint_glow(self)

func setup(w, glow_parent: Node2D, add_mat: Material, colors: Array) -> void:
	world = w
	team = colors
	font = ThemeDB.fallback_font
	z_index = 5                     # over the arrows and clouds of the threats layer
	glow_node = _Glow.new()
	glow_node.pv = self
	glow_node.material = add_mat
	glow_parent.add_child(glow_node)
	for i in 110:
		drops.append(Vector2(randf() * 2000.0, randf() * 1080.0))

func raining() -> bool:
	return int(view.get("rain", {}).get("owner", P.NO_ONE)) != P.NO_ONE

func zapped(seat: int) -> bool:
	return zaps.has(seat)

# This frame's view (net.gd sample, or a deathcam frame) and your seat.
func show_view(s: Dictionary, delta: float, my_seat: int) -> void:
	t += delta
	view = s
	me = my_seat
	fighters.clear()
	for f in s.get("fighters", []):
		fighters[int(f["id"])] = f
	powers = s.get("powers", {})
	var mine: Dictionary = fighters.get(me, {})
	blind = not mine.is_empty() and mine["state"] != P.F_DEAD and (int(mine["flags"]) & 128) != 0
	for k in zaps.keys():
		zaps[k] -= delta
		if zaps[k] <= 0.0:
			zaps.erase(k)
	for b in bolts:
		b[1] -= delta
	bolts = bolts.filter(func(b): return b[1] > 0.0)
	for p in pops:
		p[3] -= delta
	pops = pops.filter(func(p): return p[3] > 0.0)
	for r in rings:
		r[4] -= delta
	rings = rings.filter(func(r): return r[4] > 0.0)
	flash = maxf(0.0, flash - delta * 3.0)
	if raining():
		for i in drops.size():
			var d: Vector2 = drops[i] + Vector2(-5.0, 30.0) * delta * 60.0
			if d.y > 1090.0:
				d = Vector2(randf() * 2000.0, -20.0)
			drops[i] = d
	jag_t -= delta
	if jag_t <= 0.0:
		jag_t = 0.06
		_new_arcs()
	queue_redraw()
	if glow_node != null:
		glow_node.queue_redraw()

# The electricity crackles: new arcs for each warning, each zapped body, each bolt.
func _new_arcs() -> void:
	arcs.clear()
	for o in view.get("orbs", []):
		if int(o["state"]) != P.ORB_WARN:
			continue
		var c := Vector2(o["x"], o["y"])
		var list: Array = []
		var n := 2 + int(float(o["prog"]) * 4.0)
		for i in n:
			var a := randf() * TAU
			var r := SimScript.STRIKE_R * randf_range(0.5, 1.1)
			list.append(_jag(c + Vector2.from_angle(a) * 8.0, c + Vector2.from_angle(a) * r, 5, 9.0))
		arcs["w%d:%d" % [int(o["x"]), int(o["y"])]] = list
	for seat in zaps:
		var f: Dictionary = fighters.get(seat, {})
		if f.is_empty():
			continue
		var c := Vector2(f["x"] + 18.0, f["y"] + 31.0)
		var list: Array = []
		for i in 4:
			var a := randf() * TAU
			list.append(_jag(c + Vector2.from_angle(a) * 6.0, c + Vector2.from_angle(a + randf_range(-0.8, 0.8)) * randf_range(26.0, 48.0), 4, 7.0))
		arcs["z%d" % seat] = list
	for b in bolts:
		b[3] = _bolt_points(b[0], b[2])

func _jag(a: Vector2, b: Vector2, n: int, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a])
	var nrm := (b - a).orthogonal().normalized()
	for i in range(1, n):
		pts.append(a.lerp(b, float(i) / n) + nrm * randf_range(-amp, amp))
	pts.append(b)
	return pts

func _bolt_points(to: Vector2, big: bool) -> PackedVector2Array:
	var x := to.x + randf_range(-60.0, 60.0)
	var pts := PackedVector2Array([Vector2(x, -20.0)])
	var y := -20.0
	while y < to.y - 70.0:
		y += randf_range(50.0, 110.0)
		x += randf_range(-55.0, 55.0) * (1.4 if big else 1.0)
		x = lerpf(x, to.x, clampf(y / maxf(1.0, to.y), 0.0, 1.0) * 0.35)
		pts.append(Vector2(x, minf(y, to.y - 30.0)))
	pts.append(to)
	return pts

func on_event(e: Array) -> void:
	var pos := Vector2(e[1], e[2])
	var type: int = e[0]
	if type == P.E_STRIKE:
		var big: bool = e[4] == 1
		bolts.append([pos, bolt_s, big, _bolt_points(pos, big)])
		flash = 1.0
		flash_col = Color(0.8, 0.88, 1.0)
		rings.append([pos, SimScript.STRIKE_R * (2.6 if big else 2.0), BOLT_COL, 0.45, 0.45])
		world.fx.flash(pos, 9.0, Color(0.8, 0.9, 1.0), 0.35, true)
		world.fx.light_burst(pos, Color(0.7, 0.8, 1.0), 3.5, 5.0, 0.4)
		world.fx.shake = maxf(world.fx.shake, 14.0 if big else 10.0)
		world.fx.aberration = 1.0
	elif type == P.E_DEATH and e[4] == 7:
		zaps[int(e[3])] = ZAP_S
	elif type == P.E_PU_GET:
		var k: int = e[4]
		var col: Color = COLORS.get(k, Color.WHITE)
		pops.append([pos + Vector2(0, -24), P.PU_NAMES.get(k, "") + "!", col, 2.4, 2.4, k >= P.PU_CATS, P.PU_HELP.get(k, "")])
		rings.append([pos + Vector2(0, 30), 110.0 if k >= P.PU_CATS else 80.0, col, 0.4, 0.4])
		world.fx.flash(pos + Vector2(0, 30), 4.0, col, 0.25, true)
	elif type == P.E_SHIELD_POP:
		rings.append([pos, 70.0, Color(0.45, 0.9, 1.0), 0.3, 0.3])
		pops.append([pos + Vector2(0, -26), "BLOCKED!", Color(0.55, 0.95, 1.0), 0.9, 0.9, false, ""])
		world.fx.flash(pos, 3.5, Color(0.5, 0.9, 1.0), 0.2, true)
	elif type == P.E_FREEZE:
		flash = 0.8
		flash_col = Color(0.55, 0.85, 1.0)
		rings.append([pos, 1100.0, Color(0.65, 0.92, 1.0), 0.7, 0.7])
	elif type == P.E_CAT_POOF:
		rings.append([pos, 60.0, Color(0.6, 1.0, 0.65), 0.3, 0.3])
		if e[4] == 1:
			pops.append([pos + Vector2(0, -20), "CAUGHT!", Color(0.7, 1.0, 0.7), 0.9, 0.9, false, ""])
	elif type == P.E_PU_GONE:
		rings.append([pos, 46.0, Color(1, 1, 1, 0.7), 0.3, 0.3])

# ------------------------------------------------------------------ the main layer (never darkened)
func _draw() -> void:
	if raining():
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.12, 0.16, 0.3, 0.18))
		for d in drops:
			draw_line(d, d + Vector2(-4.0, 22.0), Color(0.7, 0.8, 1.0, 0.45), 2.0)
	for o in view.get("orbs", []):
		if int(o["state"]) == P.ORB_WARN:
			_draw_warning(o)
		else:
			_draw_orb(o)
	for seat in fighters:
		var f: Dictionary = fighters[seat]
		if f["state"] == P.F_DEAD or not powers.has(seat):
			continue
		var bits: int = powers[seat]["bits"]
		if seat != me and ((bits & P.PW_INVIS) != 0 or blind):
			continue
		_draw_kit(f, powers[seat], 0.35 if (bits & P.PW_INVIS) != 0 else 1.0)
	for c in view.get("cats", []):
		_draw_cat(c)
	for r in rings:
		var k: float = 1.0 - r[4] / r[3]
		var col: Color = r[2]
		col.a *= 1.0 - k
		draw_arc(r[0], r[1] * (0.2 + 0.8 * k), 0.0, TAU, 40, col, 5.0 * (1.0 - k) + 2.0)
	for p in pops:
		var k: float = p[3] / p[4]
		var size := 40 if p[5] else 30
		var at: Vector2 = p[0] + Vector2(0, -70.0 * (1.0 - k))
		var col: Color = p[2]
		col.a = clampf(k * 2.0, 0.0, 1.0)
		_text_c(at, p[1], size, col)
		if p[6] != "":
			_text_c(at + Vector2(0, 26), p[6], 18, Color(1, 1, 1, col.a))
	if blind:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.5, 0.52, 0.58, 0.32))
		var mine: Dictionary = fighters.get(me, {})
		if not mine.is_empty():
			_text_c(Vector2(mine["x"] + 18.0, mine["y"] - 30.0), "IN THE SMOKE: YOU CAN'T SEE ANYONE", 22, Color(1, 1, 1, 0.9))

func _draw_warning(o: Dictionary) -> void:
	var c := Vector2(o["x"], o["y"])
	var prog: float = o["prog"]
	var feet := c + Vector2(0, SimScript.ORB_UP)
	var col: Color = COLORS.get(int(o["kind"]), Color.WHITE)
	var big: bool = o["big"]
	var R: float = SimScript.STRIKE_R
	# the danger: a pale disc where the bolt kills, and a ring closing in on it
	draw_circle(c, R, Color(0.6, 0.8, 1.0, 0.06 + 0.12 * prog))
	draw_arc(c, R, 0.0, TAU, 40, Color(0.75, 0.88, 1.0, 0.5 + 0.4 * prog), 3.0)
	draw_arc(c, R * (1.0 + 2.2 * (1.0 - prog)), 0.0, TAU, 48, Color(0.75, 0.88, 1.0, 0.25 + 0.6 * prog), 4.0)
	var pulse := 0.5 + 0.5 * sin(t * (10.0 + 20.0 * prog))
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.28))
	draw_arc(Vector2.ZERO, R * 0.9, 0.0, TAU, 32, Color(0.85, 0.93, 1.0, 0.4 + 0.5 * pulse), 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# what it will drop, over it: its picture, its name, and whom a BIG one is for
	var a := 0.55 + 0.45 * prog
	var ic := c + Vector2(0, -R - 92.0)
	draw_circle(ic, 24.0, Color(0.05, 0.05, 0.1, 0.8 * a))
	draw_circle(ic, 20.0, Color(col.darkened(0.25), a))
	draw_arc(ic, 20.0, 0.0, TAU, 24, Color(PV_WHITE if not big else GOLD, a), 3.0)
	draw_icon(self, ic, int(o["kind"]), 13.0, Color(0.08, 0.06, 0.12, a), t)
	var label: String = P.PU_NAMES.get(int(o["kind"]), "")
	if big:
		label = "BIG: " + label
		var who := int(o.get("for", 255))
		var line := "for anyone behind the leader"
		if who >= 0 and who < names.size() and str(names[who]) != "":
			line = "for %s (or anyone behind)" % names[who]
		_text_c(c + Vector2(0, -R - 14.0), line, 20, Color(GOLD, a))
	_text_c(c + Vector2(0, -R - 40.0), label, 30 if big else 26, Color(col.lerp(Color.WHITE, 0.3), a))

func _draw_orb(o: Dictionary) -> void:
	var big: bool = o["big"]
	var r := 30.0 if big else 22.0
	var c := Vector2(o["x"], o["y"] + sin(t * 3.0 + o["x"] * 0.01) * 5.0)
	var col: Color = COLORS.get(int(o["kind"]), Color.WHITE)
	var a := 1.0
	if float(o["prog"]) > 0.8 and int(t * 8.0) % 2 == 0:
		a = 0.35                     # about to fade: it blinks
	draw_circle(c, r + 4.0, Color(0.05, 0.05, 0.1, 0.8 * a))
	draw_circle(c, r, Color(col.darkened(0.25), a))
	draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.35, Color(1, 1, 1, 0.55 * a))
	draw_arc(c, r, 0.0, TAU, 32, Color(1, 1, 1, 0.9 * a), 3.0)
	draw_icon(self, c, int(o["kind"]), r * 0.62, Color(0.08, 0.06, 0.12, a), t)
	if big:
		for i in 8:
			var a0 := t * 1.5 + i * TAU / 8.0
			draw_arc(c, r + 12.0, a0, a0 + 0.45, 6, Color(GOLD, a), 5.0)
		_text_c(c + Vector2(0, -r - 22.0), "BIG", 26, Color(GOLD, a))
	_text_c(c + Vector2(0, r + 30.0), P.PU_SHORT.get(int(o["kind"]), ""), 22, Color(col.lerp(Color.WHITE, 0.4), a))

# A picture of each power-up (the web font has no symbols), moving so it reads at a
# glance: the flame flickers, the bomb's fuse sparks, poison bubbles, smoke drifts,
# the shield shines, a dot runs round INFINITE's loop, wings flap, the BIG arrow
# grows, the cat's ears twitch, rain falls under the umbrella, the eye blinks, the
# snowflake turns, the spikes bob, the bolt flashes. ci: any canvas; tt: seconds.
static func draw_icon(ci: CanvasItem, c: Vector2, kind: int, s: float, col: Color, tt: float) -> void:
	if kind == P.PU_FIRE:
		var f := 1.0 + 0.15 * sin(tt * 18.0)
		var sway := sin(tt * 9.0) * s * 0.15
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(sway, -s * f), c + Vector2(s * 0.6, s * 0.2), c + Vector2(s * 0.3, s * 0.8),
			c + Vector2(-s * 0.3, s * 0.8), c + Vector2(-s * 0.6, s * 0.2)]), col)
	elif kind == P.PU_BOMB:
		ci.draw_circle(c + Vector2(0, s * 0.15), s * 0.65, col)
		ci.draw_line(c + Vector2(s * 0.3, -s * 0.35), c + Vector2(s * 0.6, -s * 0.8), col, 3.0)
		if int(tt * 10.0) % 2 == 0:
			for i in 4:
				ci.draw_line(c + Vector2(s * 0.62, -s * 0.85), c + Vector2(s * 0.62, -s * 0.85) + Vector2.from_angle(i * PI / 2.0 + tt) * s * 0.3, Color(1.0, 0.9, 0.3, col.a), 2.0)
	elif kind == P.PU_POISON:
		ci.draw_circle(c + Vector2(0, -s * 0.1), s * 0.55, col)
		ci.draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.25), Vector2(s * 0.6, s * 0.4)), col)
		for i in 2:
			var k := fmod(tt * 0.9 + i * 0.5, 1.0)
			ci.draw_circle(c + Vector2((i * 2 - 1) * s * 0.45, -s * 0.4 - k * s * 0.6), s * 0.14 * (1.0 - k), col)
	elif kind == P.PU_SMOKE:
		for i in 3:
			var p: Vector2 = [Vector2(-0.4, 0.1), Vector2(0.35, 0.15), Vector2(0, -0.25)][i]
			ci.draw_circle(c + p * s + Vector2(sin(tt * 2.0 + i * 2.0) * s * 0.12, 0), s * (0.38 + 0.06 * sin(tt * 3.0 + i)), col)
	elif kind == P.PU_SHIELD or kind == P.PU_SPIKES:
		var shield := PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.7), c + Vector2(s * 0.7, -s * 0.7),
			c + Vector2(s * 0.6, s * 0.2), c + Vector2(0, s * 0.85), c + Vector2(-s * 0.6, s * 0.2)])
		ci.draw_colored_polygon(shield, col)
		var sh := fmod(tt * 0.8, 1.0)
		ci.draw_line(c + Vector2(-s * 0.7 + sh * s * 1.4, -s * 0.7), c + Vector2(-s * 0.9 + sh * s * 1.4, s * 0.3), Color(1, 1, 1, 0.6 * col.a), 3.0)
		if kind == P.PU_SPIKES:
			var bob := sin(tt * 6.0) * s * 0.1
			for i in 3:
				var x := (i - 1) * s * 0.5
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(x - s * 0.18, -s * 0.7), c + Vector2(x, -s * 1.15 + bob), c + Vector2(x + s * 0.18, -s * 0.7)]), col)
	elif kind == P.PU_INF:
		ci.draw_arc(c + Vector2(-s * 0.38, 0), s * 0.36, 0.0, TAU, 16, col, 4.0)
		ci.draw_arc(c + Vector2(s * 0.38, 0), s * 0.36, 0.0, TAU, 16, col, 4.0)
		var a := tt * 4.0
		var side := 1.0 if fmod(a, TAU * 2.0) < TAU else -1.0
		ci.draw_circle(c + Vector2(side * s * 0.38, 0) + Vector2.from_angle(a * side) * s * 0.36, s * 0.13, Color(1, 1, 1, col.a))
	elif kind == P.PU_FLY:
		var flap := sin(tt * 12.0) * s * 0.35
		for side in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2(side * s, -s * 0.5 + flap), c + Vector2(side * s * 0.8, s * 0.15 + flap * 0.4),
				c + Vector2(side * s * 0.4, s * 0.4)]), col)
	elif kind == P.PU_BIG:
		var g := 0.8 + 0.25 * (0.5 + 0.5 * sin(tt * 5.0))
		ci.draw_line(c + Vector2(-s * 0.8, s * 0.5) * g, c + Vector2(s * 0.6, -s * 0.4) * g, col, 5.0 * g)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.9, -s * 0.6) * g, c + Vector2(s * 0.2, -s * 0.6) * g, c + Vector2(s * 0.7, 0.0) * g]), col)
	elif kind == P.PU_CATS:
		ci.draw_circle(c + Vector2(0, s * 0.1), s * 0.55, col)
		var tw := sin(tt * 7.0) * s * 0.08
		for side in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(side * s * 0.5, -s * 0.15), c + Vector2(side * (s * 0.55 + tw), -s * 0.85), c + Vector2(side * s * 0.1, -s * 0.4)]), col)
		if fmod(tt, 2.0) > 0.15:
			for side in [-1.0, 1.0]:
				ci.draw_circle(c + Vector2(side * s * 0.22, s * 0.02), s * 0.1, Color(0.5, 1.0, 0.4, col.a))
	elif kind == P.PU_RAIN:
		ci.draw_arc(c + Vector2(0, -s * 0.05), s * 0.8, PI, TAU, 16, col, 5.0)
		ci.draw_line(c + Vector2(0, -s * 0.05), c + Vector2(0, s * 0.6), col, 3.0)
		for i in 3:
			var k := fmod(tt * 1.5 + i * 0.33, 1.0)
			ci.draw_line(c + Vector2((i - 1) * s * 0.7, -s * 1.0 + k * s * 0.5), c + Vector2((i - 1) * s * 0.7, -s * 0.85 + k * s * 0.5), col, 2.0)
	elif kind == P.PU_INVIS:
		var open := 0.15 if fmod(tt, 1.6) < 0.25 else 1.0
		ci.draw_set_transform(c, 0.0, Vector2(1.0, open))
		ci.draw_arc(Vector2.ZERO, s * 0.75, 0.0, TAU, 20, col, 3.0)
		ci.draw_circle(Vector2.ZERO, s * 0.28, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif kind == P.PU_FREEZE:
		for i in 3:
			var a := i * PI / 3.0 + tt * 0.8
			ci.draw_line(c - Vector2.from_angle(a) * s * 0.85, c + Vector2.from_angle(a) * s * 0.85, col, 4.0)
	elif kind == P.PU_SPEED:
		var j := Vector2(sin(tt * 30.0), 0) * s * 0.06
		ci.draw_colored_polygon(PackedVector2Array([c + j + Vector2(s * 0.2, -s * 0.9), c + j + Vector2(-s * 0.5, s * 0.1), c + j + Vector2(0, s * 0.1),
			c + j + Vector2(-s * 0.2, s * 0.9), c + j + Vector2(s * 0.5, -s * 0.1), c + j + Vector2(0, -s * 0.1)]), col)

# What a fighter has, drawn on it (a = 0.35 on your own page while you are invisible).
func _draw_kit(f: Dictionary, pw: Dictionary, a: float) -> void:
	var bits: int = pw["bits"]
	var c := Vector2(f["x"] + 18.0, f["y"] + 31.0)
	var top := Vector2(c.x, f["y"])
	var seat := int(f["id"])
	var tc: Color = team[seat % team.size()] if team.size() > 0 else Color.WHITE
	if (bits & P.PW_FLY) != 0:
		var flap := sin(t * 14.0 + seat) * 0.35
		for side in [-1.0, 1.0]:
			var base := c + Vector2(-side * 6.0, -10.0)
			var tip := base + Vector2(side * 38.0, -26.0 + flap * 30.0)
			draw_colored_polygon(PackedVector2Array([base, tip, base + Vector2(side * 30.0, 4.0 + flap * 14.0), base + Vector2(side * 12.0, 14.0)]),
				Color(1, 1, 1, 0.85 * a))
			draw_polyline(PackedVector2Array([base, tip, base + Vector2(side * 30.0, 4.0 + flap * 14.0)]), Color(0.6, 0.7, 0.9, a), 2.0)
	if (bits & P.PW_FROZEN) != 0:
		var r := Rect2(f["x"] - 9.0, f["y"] - 9.0, 54.0, 81.0)
		draw_rect(r, Color(0.7, 0.9, 1.0, 0.42 * a))
		draw_rect(r, Color(0.92, 0.98, 1.0, 0.9 * a), false, 3.0)
		draw_line(r.position + Vector2(8, 10), r.position + Vector2(22, 4), Color(1, 1, 1, 0.8 * a), 3.0)
		draw_line(r.position + Vector2(8, 20), r.position + Vector2(14, 16), Color(1, 1, 1, 0.6 * a), 2.0)
	if (bits & P.PW_SHIELD) != 0:
		draw_circle(c, 46.0, Color(0.4, 0.88, 1.0, 0.1 * a))
		draw_arc(c, 46.0, 0.0, TAU, 36, Color(0.5, 0.92, 1.0, (0.7 + 0.2 * sin(t * 5.0)) * a), 3.0)
	if (bits & P.PW_SPIKES) != 0:
		if (bits & P.PW_SPIKE_UP) != 0:
			draw_circle(c, 50.0, Color(GOLD, 0.1 * a))
			draw_arc(c, 50.0, 0.0, TAU, 36, Color(GOLD, 0.85 * a), 3.0)
		for i in 3:
			var x := top.x + (i - 1) * 13.0
			var y: float = top.y - 2.0
			draw_colored_polygon(PackedVector2Array([Vector2(x - 6, y), Vector2(x, y - 17), Vector2(x + 6, y)]), Color(0.85, 0.85, 0.9, a))
			draw_polyline(PackedVector2Array([Vector2(x - 6, y), Vector2(x, y - 17), Vector2(x + 6, y)]), Color(0.2, 0.2, 0.25, a), 1.5)
	if (bits & P.PW_UMBRELLA) != 0:
		var uc := top + Vector2(0, -22)
		var pts := PackedVector2Array()
		for i in 13:
			pts.append(uc + Vector2.from_angle(PI + PI * i / 12.0) * 34.0)
		for i in 4:
			pts.append(uc + Vector2(34.0 - (i + 1) * 17.0, 4.0 if i % 2 == 0 else 0.0))
		draw_colored_polygon(pts, Color(tc.lightened(0.15), 0.95 * a))
		draw_line(uc, uc + Vector2(0, 30), Color(0.25, 0.2, 0.15, a), 3.0)
		draw_arc(uc + Vector2(5, 30), 5.0, 0.0, PI, 8, Color(0.25, 0.2, 0.15, a), 3.0)
	if (bits & P.PW_SPEED) != 0:
		var back := -1.0 if (int(f["flags"]) & 1) != 0 else 1.0
		for i in 3:
			var y: float = f["y"] + 14.0 + i * 16.0
			var x0: float = c.x + back * 22.0
			draw_line(Vector2(x0, y), Vector2(x0 + back * (24.0 + 14.0 * ((i + int(t * 20.0)) % 3)), y), Color(1.0, 0.95, 0.4, 0.75 * a), 3.0)
	if (bits & P.PW_SLOW) != 0:
		for i in 2:
			var k := fmod(t * 1.3 + i * 0.5, 1.0)
			var p := top + Vector2(-12.0 + i * 24.0, 6.0 + 30.0 * k)
			draw_circle(p, 4.0, Color(0.55, 0.75, 1.0, (1.0 - k) * a))
	# badges over the head for what has no look of its own: the arrow kind, INFINITE, BIG
	var badges: Array = []
	if int(pw["kind"]) > 0:
		badges.append(int(pw["kind"]))
	if (bits & P.PW_INF) != 0:
		badges.append(P.PU_INF)
	if (bits & P.PW_BIG) != 0:
		badges.append(P.PU_BIG)
	var by: float = top.y - (30.0 if (bits & (P.PW_SPIKES | P.PW_UMBRELLA)) != 0 else 16.0) - (34.0 if (bits & P.PW_UMBRELLA) != 0 else 0.0)
	for i in badges.size():
		var bc := Vector2(c.x + (i - (badges.size() - 1) / 2.0) * 26.0, by)
		var col: Color = COLORS.get(badges[i], Color.WHITE)
		draw_circle(bc, 12.0, Color(0.05, 0.05, 0.1, 0.8 * a))
		draw_circle(bc, 10.0, Color(col.darkened(0.2), a))
		draw_icon(self, bc, badges[i], 6.5, Color(0.08, 0.06, 0.12, a), t)

# A ghost cat (the user's daughter's idea): a pale glowing cat with big green eyes
# and a wavy ghost's tail instead of legs, outlined so it shows on the dark arena,
# facing the one it hunts.
func _draw_cat(cd: Dictionary) -> void:
	var c := Vector2(cd["x"], cd["y"] + sin(t * 6.0 + cd["x"] * 0.02) * 4.0)
	var tgt: Dictionary = fighters.get(int(cd["target"]), {})
	var dir := 1.0
	if not tgt.is_empty():
		dir = 1.0 if SimScript.wrap_d(c.x, tgt["x"] + 18.0, 1920.0) >= 0.0 else -1.0
	var body := Color(0.86, 0.98, 0.92, 0.92)
	var line := Color(0.1, 0.25, 0.15, 0.95)
	var pts := PackedVector2Array()
	for i in 13:                      # the back, an arc over the top
		var a := PI + PI * i / 12.0
		pts.append(c + Vector2(cos(a) * 30.0, sin(a) * 18.0))
	for i in 7:                       # the ghost's wavy hem underneath
		var x := 30.0 - i * 10.0
		pts.append(c + Vector2(x, 10.0 + (6.0 if i % 2 == 0 else 0.0) + sin(t * 9.0 + i) * 2.0))
	draw_colored_polygon(pts, body)
	pts.append(pts[0])
	draw_polyline(pts, line, 2.5)
	var head := c + Vector2(dir * 24.0, -16.0)
	for side in [-1.0, 1.0]:
		var ear := PackedVector2Array([head + Vector2(side * 14.0 - 3.0, -6.0), head + Vector2(side * 13.0, -27.0 + sin(t * 7.0 + side) * 2.0), head + Vector2(side * 3.0, -14.0)])
		draw_colored_polygon(ear, body)
		ear.append(ear[0])
		draw_polyline(ear, line, 2.0)
	draw_circle(head, 17.0, line)
	draw_circle(head, 15.0, body)
	for side in [-1.0, 1.0]:
		var eye := head + Vector2(dir * 4.0 + side * 6.5, -2.0)
		draw_circle(eye, 4.6, Color(0.35, 1.0, 0.3))
		draw_circle(eye + Vector2(dir * 1.2, 0), 2.0, Color(0.05, 0.05, 0.05))
	draw_circle(head + Vector2(dir * 7.0, 5.0), 2.0, Color(1.0, 0.55, 0.65))
	for side in [-1.0, 1.0]:          # whiskers
		draw_line(head + Vector2(dir * 9.0, 6.0), head + Vector2(dir * 24.0, 3.0 + side * 4.0), line, 1.5)
	var tail := PackedVector2Array()
	for i in 8:
		tail.append(c + Vector2(-dir * (26.0 + i * 5.0), -6.0 - i * 4.0 + sin(t * 8.0 + i * 0.8) * 4.0))
	draw_polyline(tail, line, 8.0)
	draw_polyline(tail, body, 5.0)

func _text_c(at: Vector2, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := Vector2(clampf(at.x - w / 2.0, 12.0, maxf(12.0, 1908.0 - w)), clampf(at.y, 30.0, 1070.0))   # on screen
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(4, size / 7), Color(0, 0, 0, 0.85 * col.a))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

# ------------------------------------------------------------------ the glow layer (added light)
func _paint_glow(g: Node2D) -> void:
	if flash > 0.0:
		g.draw_rect(Rect2(0, 0, 1920, 1080), Color(flash_col, flash * 0.45))
	for o in view.get("orbs", []):
		var c := Vector2(o["x"], o["y"])
		var col: Color = COLORS.get(int(o["kind"]), Color.WHITE)
		if int(o["state"]) == P.ORB_WARN:
			var prog: float = o["prog"]
			# a column of light from the sky, brighter as the bolt comes
			for i in 3:
				var w := 46.0 - i * 14.0
				g.draw_rect(Rect2(c.x - w / 2.0, 0.0, w, c.y + 20.0), Color(0.45, 0.6, 1.0, (0.05 + 0.13 * prog) * (i + 1) * 0.6))
			g.draw_circle(c, 26.0 + 18.0 * prog, Color(0.55, 0.7, 1.0, 0.18 + 0.3 * prog))
			for pts in arcs.get("w%d:%d" % [int(o["x"]), int(o["y"])], []):
				g.draw_polyline(pts, Color(0.7, 0.85, 1.0, 0.65 + 0.35 * prog), 3.0)
		else:
			var r := 30.0 if o["big"] else 22.0
			g.draw_circle(c, r * 2.3, Color(col, 0.16))
			g.draw_circle(c, r * 1.5, Color(col, 0.22))
			if o["big"]:
				g.draw_circle(c, r * 3.0, Color(GOLD, 0.12))
	for b in bolts:
		var k: float = clampf(b[1] / 0.4, 0.0, 1.0)
		g.draw_polyline(b[3], Color(BOLT_COL, k), 16.0 if b[2] else 12.0)
		g.draw_polyline(b[3], Color(1, 1, 1, k), 5.0)
		g.draw_circle(b[0], 50.0 * k + 20.0, Color(0.7, 0.85, 1.0, 0.6 * k))
	for seat in zaps:
		var f: Dictionary = fighters.get(seat, {})
		if f.is_empty():
			continue
		var c := Vector2(f["x"] + 18.0, f["y"] + 31.0)
		var k: float = zaps[seat] / ZAP_S
		g.draw_circle(c, 40.0, Color(0.5, 0.7, 1.0, 0.25 * k))
		for pts in arcs.get("z%d" % seat, []):
			g.draw_polyline(pts, Color(0.75, 0.9, 1.0, k), 3.0)
	for cd in view.get("cats", []):
		g.draw_circle(Vector2(cd["x"], cd["y"] - 6.0), 46.0, Color(0.45, 1.0, 0.55, 0.16))
		g.draw_circle(Vector2(cd["x"], cd["y"] - 6.0), 28.0, Color(0.55, 1.0, 0.65, 0.2))

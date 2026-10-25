# THE BOILER ROOM's look (theme "nightmare", sim/level.gd layout 4), drawn from the
# snapshot's hazard state (sim/boiler.gd write/read) and the fighters. world.gd makes
# one (behind the tiles), calls setup once, set_theme on each arena, show_view each
# frame and on_event for each event. What goes where:
#   this node (the lit world, behind the blocks): the back wall (assets/boiler_back.png,
#     tools/make_boiler_art.py), the big fan's blades, the chains at the back, and the
#     giant shadow that rises behind the great boiler before the nightmare surge;
#   front (a sprite in the lit world, right after the tile layers, which it replaces): the
#     blocks and ledges (assets/boiler_front.png with its normal map);
#   mid (the lit world, over the blocks): the caged bulbs, the pipes' nozzles and floor
#     grates, drips and little steam leaks;
#   top (the threats layer, over the fighters: never darkened): the fire, the steam, a
#     pipe's bulge and gauge, the hook and its chain, the lockers' doors, the bed sheets
#     and the hands, the smoke;
#   glow (the glow layer, added light): the furnaces' doors and mouths, the fire's light,
#     sparks, the bulbs' light, the surge's red heartbeat;
#   shade (the glow layer, plain): the tall shadow seen in a furnace's light while the
#     lights are out.
# The lights going out and the surge change world.dark_base (the night's colour) and the
# bulbs' lights (world.torches); set_theme undoes all of it on another arena. Drawn by
# hand, on every look (LOW too: the warnings and the fire are part of play); the furnaces
# get real lights only where the look has them (NORMAL, HIGH).
extends Node2D

const P = preload("res://sim/proto.gd")
const B = preload("res://sim/boiler.gd")
const BACK := preload("res://assets/boiler_back.png")
const FRONT := preload("res://assets/boiler_front.png")
const FRONT_N := preload("res://assets/boiler_front_n.png")
const PARTS_TEX := preload("res://assets/boiler_parts.png")
const HALO := preload("res://assets/fx_halo.png")
const LIGHT := preload("res://assets/fx_light.png")
# the moving parts in assets/boiler_parts.png (tools/make_boiler_art.py PARTS), art pixels
const PARTS := {"hook": Rect2(0, 0, 22, 30), "link_a": Rect2(24, 0, 6, 8), "link_b": Rect2(32, 0, 2, 8),
	"door": Rect2(36, 0, 30, 60), "hand_open": Rect2(68, 0, 18, 28), "hand_shut": Rect2(88, 0, 18, 28),
	"shadow": Rect2(108, 0, 56, 124), "bulb": Rect2(166, 0, 12, 16), "wheel": Rect2(180, 0, 18, 18)}
const DARK := Color(0.66, 0.54, 0.52)        # the boiler room's night (world.dark_base)
const DARK_OUT := Color(0.24, 0.17, 0.18)    # with the lights out (the platforms still show, faintly)
const DARK_SURGE := Color(0.95, 0.3, 0.22)   # the surge's red
const BULB := Color(1.0, 0.8, 0.52)
const FIRE_HOT := Color(1.0, 0.95, 0.7)
const FIRE := Color(1.0, 0.62, 0.18)
const FIRE_RED := Color(0.9, 0.22, 0.06)
const STEAM := Color(0.9, 0.93, 0.97)
# each furnace's door (its middle, px) and the slots of its grate the fire shows through
const DOORS := [Vector2(104, 690), Vector2(1814, 780), Vector2(960, 970)]
const FAN := Vector2(1536, 264)
const HOOK_S := 2.4                         # the hook and chain are drawn this many times their art
const LOCKER_Y := 420.0                      # the side passages: rows 14-17
const LOCKER_W := 60.0
const LOCKER_H := 120.0
const DRIPS := [Vector2(600, 272), Vector2(1320, 242), Vector2(1532, 662), Vector2(1112, 470), Vector2(330, 798)]

var world
var on := false
var t := 0.0
var rng := RandomNumberGenerator.new()
var front := Sprite2D.new()
var mid: _Layer
var top: _Layer
var glow: _Layer
var shade: _Layer
var flights: Array = []          # the furnaces' real lights (NORMAL, HIGH)
var hz := {}                     # the newest hazard state (sim/boiler.gd read)
var age := 0.0                   # ticks since it came (the page runs it on between snapshots)
var fighters: Array = []
var bulbs: Array = []            # [bulb's place, wire's top, phase]
var bright: Array = []           # each bulb's brightness now, 0..1
var hook_prev := 0.0             # the hook's angle in the last snapshot (its swing's trail)
var hook_ang := 0.0
var hook_len := 110.0
var hook_vel := 0.0
var doors := [0.0, 0.0]          # each locker's door: 0 shut, 1 wide open
var door_in := [false, false]    # someone was inside it last frame
var last_y := {}                 # seat -> y last frame (a fall through a bed comes out of the top)
var puffs: Array = []            # [pos, secs left, kind]: 0 feathers out of a bed's top opening, 1 a locker's dust, 2 soot
var sparks: Array = []           # [pos, vel, secs left, colour]
var drops: Array = []            # [pos, speed, floor y, splash secs]
var drip_t: Array = []
var darkness := 0.0              # how dark the room is now (the lights out), 0..1
var flap := [0.0, 0.0]           # each bed's torn sheets flap after someone drops out of it, 1..0
var surge_k := 0.0               # the surge's warning, 0..1

class _Layer extends Node2D:
	var bv
	var which := 0
	func _draw() -> void:
		if bv != null and bv.on:
			bv._paint(self, which)

func setup(w) -> void:
	world = w
	rng.seed = 1984
	visible = false
	var ct := CanvasTexture.new()
	ct.diffuse_texture = FRONT
	ct.normal_texture = FRONT_N
	front.texture = ct
	front.centered = false
	front.scale = Vector2(2, 2)
	front.visible = false
	world.add_child(front)
	world.move_child(front, world.tiles_lit.get_index() + 1)
	mid = _new_layer(1, world, front.get_index() + 1)
	top = _new_layer(2, world.threats, -1)
	top.z_index = 3
	glow = _new_layer(3, world.glow, -1)
	glow.material = world.add_mat
	shade = _new_layer(4, world.glow, -1)
	for i in B.FURNACES.size():
		var l := PointLight2D.new()
		l.texture = LIGHT
		l.color = Color(1.0, 0.5, 0.18)
		l.texture_scale = 2.4
		l.height = 60.0
		l.position = B.FURNACES[i][0] + B.DIRS[B.FURNACES[i][1]] * 60.0
		l.enabled = false
		world.add_child(l)
		flights.append(l)
	for i in DRIPS.size():
		drip_t.append(randf_range(0.5, 3.0))

func _new_layer(which: int, parent: Node, at: int) -> _Layer:
	var n := _Layer.new()
	n.bv = self
	n.which = which
	n.visible = false
	parent.add_child(n)
	if at >= 0:
		parent.move_child(n, at)
	return n

# Another arena: on the boiler room the back wall and the blocks are ours (the castle's
# backdrops, tiles and torches hide), the night turns warm; elsewhere all of it goes back.
func set_theme(level) -> void:
	var was := on
	on = level.theme == "nightmare"
	visible = on
	for n in [front, mid, top, glow, shade]:
		n.visible = on
	var dyn: bool = world.parts.get("dyn_lights", false)
	for l in flights:
		l.enabled = on and dyn
	if on:
		world.dark_base = DARK
		world.dark.color = DARK
		world.bg_far.visible = false
		world.bg_mid.visible = false
		world.tiles_plain.visible = false
		world.tiles_lit.visible = false
		for tr in world.torches:
			tr[0].visible = false     # the stone torches: our caged bulbs take their places (their lights stay)
			tr[2].visible = false
			tr[2].emitting = false
			tr[3].visible = false
			tr[1].color = BULB
		_find_bulbs(level)
		hz = {}
	elif was:
		world.bg_far.visible = true
		world.bg_mid.visible = true
		var lit: bool = world.parts.get("lit", false)
		world.tiles_plain.visible = not lit
		world.tiles_lit.visible = lit
		var fx_on: bool = world.parts.get("particles", false)
		for tr in world.torches:
			tr[3].visible = fx_on

# Each torch spot gets a caged bulb on a wire from the block above it (or the ceiling).
func _find_bulbs(level) -> void:
	bulbs.clear()
	bright.clear()
	for i in level.torches.size():
		var p: Vector2 = level.torches[i] + Vector2(0, -24)
		var top_y := 60.0
		var cy := int(p.y / 30.0) - 1
		while cy > 1:
			if level.cell(int(p.x / 30.0), cy) != 0:
				top_y = (cy + 1) * 30.0
				break
			cy -= 1
		bulbs.append([p, maxf(top_y, p.y - 190.0), i * 1.37])
		bright.append(1.0)

# ------------------------------------------------------------------ each frame
func show_view(s: Dictionary, delta: float) -> void:
	if not on:
		return
	t += delta
	var h: Dictionary = s.get("hazards", {})
	if not h.is_empty() and not is_same(h, hz):
		var hk: Dictionary = h.get("hook", {})
		hook_prev = hook_ang
		hook_ang = float(hk.get("ang", 0.0))
		hook_len = float(hk.get("len", B.HOOK_SHORT))
		hook_vel = hook_ang - hook_prev
		hz = h
		age = 0.0
	else:
		age = minf(age + delta * 60.0, 6.0)
	fighters = s.get("fighters", [])
	_update_lights(delta)
	_update_lockers(delta)
	_update_bits(delta)
	queue_redraw()
	for n in [mid, top, glow, shade]:
		n.queue_redraw()

# A hazard's phase and its ticks in it (run on between snapshots), from the state.
func _ph(list: String, i: int) -> Array:
	var l: Array = hz.get(list, [])
	if i >= l.size():
		return [B.IDLE, 0.0, false]
	var e: Array = l[i]
	var tt: float = float(e[1]) + (age if e[0] != B.IDLE else 0.0)
	return [int(e[0]), tt, e[2] if e.size() > 2 else false]

# How far along a furnace's warning is (0..1; the surge's warning is longer).
func _warn_k(f: Array) -> float:
	return clampf(f[1] / float(B.SURGE_WARN_T if f[2] else B.FURNACE_WARN), 0.0, 1.0)

# The bulbs flicker and go out with the lights; the night darkens; the surge turns red.
func _update_lights(delta: float) -> void:
	var ls: Array = hz.get("lights", [B.LIGHTS_ON, 0])
	var state: int = ls[0]
	var lt: float = float(ls[1]) + age
	var sum := 0.0
	for i in bulbs.size():
		var b := 1.0
		var n := sin(t * (13.0 + i * 1.7) + i * 2.3) * sin(t * (7.1 + i) + i)
		if state == B.LIGHTS_ON:
			b = 1.0 if n > -0.93 else 0.35          # now and then a bulb dips
		elif state == B.LIGHTS_FLICKER:
			var k := lt / float(B.LIGHTS_STEPS[1])
			b = 0.0 if n < -0.9 + k * 1.5 else 1.0
		elif state == B.LIGHTS_DARK:
			b = 0.0
		else:
			b = 1.0 if n < -1.0 + 2.2 * lt / float(B.LIGHTS_STEPS[3]) else 0.0
		bright[i] = move_toward(bright[i], b, delta * 30.0)
		sum += bright[i]
	var lit := sum / maxf(1.0, bulbs.size())
	darkness = move_toward(darkness, 1.0 - lit, delta * 6.0)
	var sg: Array = hz.get("surge", [B.SURGE_IDLE, 0])
	var sk := 0.0
	if sg[0] == B.SURGE_WARN:
		sk = clampf((float(sg[1]) + age) / float(B.SURGE_WARN_T), 0.0, 1.0)
	surge_k = move_toward(surge_k, sk, delta * 3.0)
	var beat := _heartbeat()
	var base := DARK.lerp(DARK_OUT, darkness * (0.9 if world.parts.get("dyn_lights", false) else 0.7))   # (LOW has fewer lights: less deep)
	base = base.lerp(DARK_SURGE, surge_k * (0.55 + 0.25 * beat))
	world.dark_base = base
	for i in mini(bulbs.size(), world.torches.size()):
		var c := BULB.lerp(Color(1.0, 0.25, 0.15), surge_k)
		world.torches[i][1].color = c * bright[i]
	var dyn: bool = world.parts.get("dyn_lights", false)
	for i in flights.size():
		var l: PointLight2D = flights[i]
		l.enabled = dyn
		if not dyn:
			continue
		var f := _ph("f", i)
		var e := 0.45 + 0.12 * sin(t * 9.0 + i)
		if f[0] == B.WARN:
			e = lerpf(0.5, 1.8, _warn_k(f)) + 0.25 * sin(t * 30.0)
		elif f[0] == B.BLAST:
			e = 2.6 + 0.4 * sin(t * 40.0 + i)
		elif f[0] == B.COOL:
			e = lerpf(1.6, 0.5, clampf(f[1] / float(B.FURNACE_COOL), 0.0, 1.0))
		l.energy = e
		if (world.fx.shake < 3.0) and f[0] == B.WARN and _warn_k(f) > 0.6:
			world.fx.shake = maxf(world.fx.shake, 2.0 * _warn_k(f))   # the rumble (HIGH shakes the view)

# The surge's heartbeat: two beats, then a rest, faster as it comes (0..1).
func _heartbeat() -> float:
	if surge_k <= 0.0:
		return 0.0
	var period := lerpf(1.0, 0.5, surge_k)
	var x := fmod(t, period) / period
	return maxf(exp(-pow((x - 0.08) / 0.05, 2.0)), 0.8 * exp(-pow((x - 0.3) / 0.05, 2.0)))

# Each locker's door: it swings open as someone walks up to it, slams once they are deep
# inside, and on the other side bursts open as they come out (the passage wraps).
func _update_lockers(delta: float) -> void:
	for side in 2:
		var open := false
		var slam := false
		var burst := false
		var inside := false
		for f in fighters:
			if int(f["state"]) == P.F_DEAD:
				continue
			var fy: float = f["y"]
			if fy + 63.0 < LOCKER_Y + 20.0 or fy > LOCKER_Y + LOCKER_H - 10.0:
				continue
			var cx: float = f["x"] + 18.0
			var vx: float = f["vx"]
			var d: float = cx if side == 0 else 1920.0 - cx      # how far from the outer edge
			var out_v: float = -vx if side == 0 else vx          # moving toward the outer edge (in)
			if d < LOCKER_W + 4.0:
				inside = true
				if out_v < -0.5:
					open = true                                  # coming out into the room
					if not door_in[side]:
						burst = true
				elif out_v > 0.5 and d < 34.0:
					slam = true                                  # deep inside, going through
				else:
					open = true
			elif d < 170.0 and out_v > 0.5:
				open = true                                      # walking up to it
		if burst and doors[side] < 0.9:
			doors[side] = 1.0
			puffs.append([Vector2(LOCKER_W + 6.0 if side == 0 else 1920.0 - LOCKER_W - 6.0, LOCKER_Y + LOCKER_H - 10.0), 0.5, 1])
			world.fx.shake = maxf(world.fx.shake, 3.0)
		if open:
			doors[side] = move_toward(doors[side], 1.0, delta * 7.0)
		elif slam:
			doors[side] = move_toward(doors[side], 0.0, delta * 16.0)
		else:
			doors[side] = move_toward(doors[side], 0.0, delta * 2.5)
		door_in[side] = inside

# Sparks, puffs, drips, and a fall through a bed coming out of the opening above.
func _update_bits(delta: float) -> void:
	for f in fighters:
		var seat := int(f["id"])
		var y: float = f["y"]
		var cx: float = f["x"] + 18.0
		if last_y.has(seat) and last_y[seat] > 930.0 and y < 140.0:
			for b in B.BEDS:
				if cx > b[0] - 10 and cx < b[1] + 10:
					puffs.append([Vector2(cx, 84.0), 1.2, 0])   # (under the page's seat bar, which covers the ceiling)
					flap[0 if cx < 960.0 else 1] = 1.0
		last_y[seat] = y
	for bi in 2:
		flap[bi] = maxf(0.0, flap[bi] - delta * 1.2)
	for i in range(puffs.size() - 1, -1, -1):
		puffs[i][1] -= delta
		if puffs[i][1] <= 0.0:
			puffs.remove_at(i)
	for i in range(sparks.size() - 1, -1, -1):
		var sp: Array = sparks[i]
		sp[2] -= delta
		sp[1].y += 600.0 * delta
		sp[0] += sp[1] * delta
		if sp[2] <= 0.0:
			sparks.remove_at(i)
	# the furnaces spit sparks as they warm up and while they burn
	for i in B.FURNACES.size():
		var f := _ph("f", i)
		var rate := 0.0
		if f[0] == B.WARN:
			rate = 6.0 + 40.0 * _warn_k(f)
		elif f[0] == B.BLAST:
			rate = 50.0
		if rate > 0.0 and sparks.size() < 90 and rng.randf() < rate * delta:
			var spec: Array = B.FURNACES[i]
			var dir: Vector2 = B.DIRS[spec[1]]
			var p: Vector2 = spec[0] + Vector2(dir.y, dir.x).abs() * rng.randf_range(-30.0, 30.0)
			var v: Vector2 = dir * rng.randf_range(120.0, 420.0) + Vector2(rng.randf_range(-80, 80), rng.randf_range(-260, -60))
			sparks.append([p, v, rng.randf_range(0.3, 0.8), FIRE_HOT.lerp(FIRE, rng.randf())])
	# drips from the pipes, down to the surface under each
	for i in DRIPS.size():
		drip_t[i] -= delta
		if drip_t[i] <= 0.0:
			drip_t[i] = rng.randf_range(1.2, 3.5)
			drops.append([DRIPS[i], 0.0, _floor_under(DRIPS[i]), 0.0])
	for i in range(drops.size() - 1, -1, -1):
		var d: Array = drops[i]
		if d[3] > 0.0:
			d[3] -= delta
			if d[3] <= 0.0:
				drops.remove_at(i)
			continue
		d[1] += 1500.0 * delta
		d[0] = d[0] + Vector2(0, d[1] * delta)
		if d[0].y >= d[2]:
			d[0].y = d[2]
			d[3] = 0.25

func _floor_under(p: Vector2) -> float:
	var lv = world.level
	var cy := int(p.y / 30.0) + 1
	while cy < 36:
		if lv.cell(int(p.x / 30.0), cy) != 0:
			return cy * 30.0
		cy += 1
	return 1080.0

func on_event(e: Array) -> void:
	if not on:
		return
	var pos := Vector2(e[1], e[2])
	if e[0] == P.E_FURNACE:
		var dir: Vector2 = B.DIRS[int(e[4]) % 4]
		world.fx.flash(pos + dir * 60.0, 7.0, Color(1.0, 0.6, 0.2), 0.3, true)
		world.fx.light_burst(pos + dir * 90.0, Color(1.0, 0.5, 0.15), 3.2, 4.0, 0.6)
		world.fx.shake = maxf(world.fx.shake, 9.0)
		world.fx.aberration = maxf(world.fx.aberration, 0.6)
	elif e[0] == P.E_STEAM:
		var dir: Vector2 = B.DIRS[int(e[4]) % 4]
		world.fx.ring(pos + dir * 30.0, 120.0, Color(0.9, 0.95, 1.0), 0.35)
		world.fx.flash(pos + dir * 20.0, 4.0, Color(0.85, 0.9, 1.0), 0.15, true)
		world.fx.shake = maxf(world.fx.shake, 4.0)
	elif e[0] == P.E_DEATH and e[4] == 10:
		puffs.append([pos, 1.4, 2])           # soot and embers rise off the body (no gore)
		for k in 14:
			sparks.append([pos + Vector2(rng.randf_range(-14, 14), rng.randf_range(-20, 20)),
				Vector2(rng.randf_range(-120, 120), rng.randf_range(-380, -120)), rng.randf_range(0.4, 1.0), FIRE])

# ------------------------------------------------------------------ the drawing
func _draw() -> void:
	if not on:
		return
	draw_texture_rect(BACK, Rect2(0, 0, 1920, 1080), false)
	_draw_fan(self)
	_draw_chains(self)
	if surge_k > 0.01:   # the giant shadow rises on the wall behind the great boiler, in a red glow
		var k := smoothstep(0.0, 0.8, surge_k)
		var beat := _heartbeat()
		var glow_c := Color(2.6, 0.75, 0.45, (0.55 + 0.25 * beat) * k)   # (over 1: the night darkens this layer)
		draw_texture_rect(HALO, Rect2(960 - 560, 60, 1120, 900), false, glow_c)
		draw_texture_rect(HALO, Rect2(960 - 320, 160, 640, 620), false, Color(2.4, 1.0, 0.55, 0.6 * k))
		var r: Rect2 = PARTS["shadow"]
		var hgt := 720.0 * (0.8 + 0.2 * surge_k)
		var wid := hgt * r.size.x / r.size.y
		var sway := sin(t * 1.3) * 10.0
		draw_texture_rect_region(PARTS_TEX, Rect2(960.0 - wid / 2.0 + sway, 800.0 - hgt, wid, hgt), r,
			Color(0.02, 0.0, 0.0, 0.92 * k))

func _paint(n: Node2D, which: int) -> void:
	if which == 1:
		_paint_mid(n)
	elif which == 2:
		_paint_top(n)
	elif which == 3:
		_paint_glow(n)
	elif which == 4:
		_paint_shade(n)

func _part(n: Node2D, name: String, pos: Vector2, scale: float = 2.0, col: Color = Color.WHITE, flip: bool = false) -> void:
	var r: Rect2 = PARTS[name]
	var size := r.size * scale
	n.draw_texture_rect_region(PARTS_TEX, Rect2(pos, Vector2(-size.x if flip else size.x, size.y)), r, col)

# The fan's four blades turn (slower with the lights out, fast in the surge) over a dim
# light from outside; the chains at the back sway, harder when the hook swings.
func _draw_fan(n: Node2D) -> void:
	n.draw_circle(FAN, 78.0, Color(0.32, 0.36, 0.4, 0.5))
	var spin := t * lerpf(1.8, 0.5, darkness) + surge_k * t * 5.0
	for k in 4:
		var a := spin + k * PI / 2.0
		var p0 := FAN + Vector2.from_angle(a - 0.12) * 10.0
		var p1 := FAN + Vector2.from_angle(a - 0.3) * 76.0
		var p2 := FAN + Vector2.from_angle(a + 0.22) * 76.0
		n.draw_colored_polygon(PackedVector2Array([p0, p1, p2]), Color(0.06, 0.05, 0.06))
	n.draw_circle(FAN, 12.0, Color(0.2, 0.18, 0.18))
	n.draw_circle(FAN, 5.0, Color(0.4, 0.36, 0.34))

func _draw_chains(n: Node2D) -> void:
	var hk: Dictionary = hz.get("hook", {})
	var shake := 1.0 + (2.5 if int(hk.get("phase", 0)) == B.BLAST else 0.0) + surge_k * 3.0
	for c in [[300.0, 140.0, 0.3], [640.0, 210.0, 1.9], [1250.0, 170.0, 3.1], [1700.0, 120.0, 4.4]]:
		var a: float = sin(t * 1.1 + c[2]) * 0.05 * shake
		var pts := PackedVector2Array()
		var ln: float = c[1]
		for k in 12:
			var u := k / 11.0
			pts.append(Vector2(c[0] + sin(a) * ln * u, 60.0 + cos(a) * ln * u))
		n.draw_polyline(pts, Color(0.16, 0.13, 0.13), 5.0)
		for k in range(0, 12, 2):
			n.draw_circle(pts[k], 2.0, Color(0.3, 0.26, 0.25))

# ---------------------------------------------- the lit world, over the blocks
func _paint_mid(n: Node2D) -> void:
	# the caged bulbs on their wires (dark glass when off)
	for i in bulbs.size():
		var b: Array = bulbs[i]
		var sway := sin(t * 1.2 + b[2]) * (2.0 + surge_k * 6.0)
		var p: Vector2 = b[0] + Vector2(sway, 0)
		n.draw_line(Vector2(b[0].x, b[1]), p + Vector2(0, -12), Color(0.08, 0.07, 0.07), 2.0)
		_part(n, "bulb", p - Vector2(12, 14))
		if bright[i] < 0.9:
			n.draw_circle(p + Vector2(0, 2), 6.0, Color(0.15, 0.13, 0.12, 1.0 - bright[i]))
	# the steam pipes' nozzles out of the boiler, and the floor vents' grates
	for i in B.PIPES.size():
		var spec: Array = B.PIPES[i]
		var v: Vector2 = spec[0]
		if spec[1] == 3:
			var r: Rect2 = spec[2]
			n.draw_rect(Rect2(r.position.x + 4, 1012, r.size.x - 8, 9), Color(0.1, 0.09, 0.09))
			for x in range(int(r.position.x) + 8, int(r.end.x) - 6, 8):
				n.draw_rect(Rect2(x, 1013, 4, 7), Color(0.3, 0.29, 0.3))
			n.draw_rect(Rect2(r.position.x + 4, 1012, r.size.x - 8, 2), Color(0.55, 0.53, 0.52))
		else:
			var d := -1.0 if spec[1] == 2 else 1.0
			var x0: float = v.x
			n.draw_rect(Rect2(minf(x0, x0 + d * 30.0), v.y - 13, 30, 26), Color(0.26, 0.24, 0.24))
			n.draw_rect(Rect2(minf(x0, x0 + d * 30.0), v.y - 13, 30, 5), Color(0.5, 0.47, 0.45))
			n.draw_rect(Rect2(minf(x0 + d * 30.0, x0 + d * 40.0), v.y - 8, 10, 16), Color(0.2, 0.18, 0.18))
			n.draw_rect(Rect2(minf(x0 + d * 6.0, x0 + d * 12.0), v.y - 16, 6, 32), Color(0.16, 0.15, 0.15))
	# torn sheets hang from the openings over the beds (low enough to show under the page's
	# seat bar); they flap when someone drops out of the bed above
	for bi in B.BEDS.size():
		var b: Array = B.BEDS[bi]
		var f: float = flap[bi]
		for j in 4:
			var x: float = b[0] + 10.0 + j * 33.0
			var ln := 52.0 + (j * 37) % 30
			var sw := sin(t * 1.6 + j * 1.3 + bi) * 3.0 + sin(t * 18.0 + j) * 10.0 * f
			var pts := PackedVector2Array([Vector2(x, 54), Vector2(x + 14, 54), Vector2(x + 12 + sw, 54 + ln * 0.7),
				Vector2(x + 7 + sw * 1.4, 54 + ln), Vector2(x + 2 + sw, 54 + ln * 0.8)])
			n.draw_colored_polygon(pts, Color(0.62, 0.58, 0.52))
			n.draw_polyline(PackedVector2Array([pts[0], pts[4], pts[3]]), Color(0.3, 0.27, 0.24), 1.5)
	# drips, and their splashes
	for d in drops:
		if d[3] > 0.0:
			var k: float = d[3] / 0.25
			n.draw_line(d[0] + Vector2(-6 * (1.0 - k), -2), d[0] + Vector2(-9 * (1.0 - k), -6 * k), Color(0.55, 0.7, 0.8, k), 2.0)
			n.draw_line(d[0] + Vector2(6 * (1.0 - k), -2), d[0] + Vector2(9 * (1.0 - k), -6 * k), Color(0.55, 0.7, 0.8, k), 2.0)
		else:
			n.draw_line(d[0], d[0] + Vector2(0, -7), Color(0.6, 0.75, 0.85, 0.9), 2.0)

# ---------------------------------------------- the threats layer, over the fighters
func _paint_top(n: Node2D) -> void:
	for i in B.FURNACES.size():
		var f := _ph("f", i)
		if f[0] == B.WARN:
			_draw_furnace_warn(n, i, _warn_k(f))
		elif f[0] == B.BLAST:
			_draw_fire(n, i, f[1])
		elif f[0] == B.COOL:
			_draw_smoke(n, i, f[1] / float(B.FURNACE_COOL))
	for i in B.PIPES.size():
		var p := _ph("p", i)
		if p[0] == B.WARN:
			_draw_bulge(n, i, clampf(p[1] / float(B.PIPE_WARN), 0.0, 1.0))
		elif p[0] == B.BLAST:
			_draw_steam(n, i, p[1])
		else:
			_draw_gauge(n, i, 0.15 + 0.03 * sin(t * 2.0 + i))
	_draw_hook(n)
	_draw_lockers(n)
	_draw_beds(n)
	for pf in puffs:
		var k: float = pf[1]
		if pf[2] == 0:        # feathers and dust burst out of a bed's top opening and drift down
			var u := 1.0 - k / 1.2
			n.draw_texture_rect(HALO, Rect2(pf[0] - Vector2(70, 40) * (1.0 + u), Vector2(140, 90) * (1.0 + u)), false, Color(0.85, 0.82, 0.78, 0.55 * k))
			for j in 16:
				var sway := sin(j * 2.1 + u * 7.0) * (16.0 + 60.0 * u) + (j - 7.5) * 6.0 * u
				var p: Vector2 = pf[0] + Vector2(sway, -10.0 + u * (50.0 + (j % 5) * 26.0))
				var a := 1.0 if j % 3 else 0.7
				n.draw_set_transform(p, sin(u * 9.0 + j) * 1.2, Vector2.ONE)
				n.draw_rect(Rect2(-5, -2, 10, 4), Color(0.95, 0.93, 0.88, k * a))
				n.draw_rect(Rect2(-5, -2, 10, 1), Color(1, 1, 1, k * a))
				n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif pf[2] == 1:      # a locker's door bursts open: dust
			n.draw_texture_rect(HALO, Rect2(pf[0] - Vector2(40, 30), Vector2(80, 50)), false, Color(0.6, 0.6, 0.58, k))
		else:                 # soot off a body the fire caught
			var u := 1.0 - k / 1.4
			for j in 3:
				var p: Vector2 = pf[0] + Vector2(sin(j * 2.0 + t * 2.0) * 10.0, -u * (50.0 + j * 30.0))
				var r := 18.0 + u * 30.0 + j * 6.0
				n.draw_texture_rect(HALO, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.12, 0.1, 0.1, 0.7 * k / 1.4))

# A furnace warms up: its fire licks out of the mouth more and more, the walkway in
# front of it glows red, the heat shimmers over the area.
func _draw_furnace_warn(n: Node2D, i: int, k: float) -> void:
	var spec: Array = B.FURNACES[i]
	var r: Rect2 = spec[2]
	var d: int = spec[1]
	var pulse := 0.5 + 0.5 * sin(t * lerpf(6.0, 26.0, k))
	n.draw_rect(r, Color(1.0, 0.25, 0.08, 0.05 + 0.12 * k * pulse))
	# the hot edge of the area along its floor (or its sides, upward)
	var edge := Color(1.0, 0.45, 0.1, 0.35 + 0.55 * k * pulse)
	if d == 3:
		n.draw_rect(Rect2(r.position.x, r.end.y - 6, r.size.x, 6), edge)
	else:
		n.draw_rect(Rect2(r.position.x, r.end.y - 4, r.size.x, 4), edge)
		n.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3), Color(edge, edge.a * 0.6))
	# tongues of fire out of the mouth (longer as it comes)
	if k > 0.25:
		var m: Vector2 = spec[0]
		var dir: Vector2 = B.DIRS[d]
		var side := Vector2(dir.y, dir.x).abs()
		var reach := 18.0 + 70.0 * (k - 0.25) / 0.75
		var span := (r.size.y if d != 3 else r.size.x) * 0.4
		for j in 5:
			var o := side * (span * (j - 2) / 2.5)
			var ln := reach * (0.6 + 0.4 * sin(t * 17.0 + j * 1.9))
			var w := 7.0 + 4.0 * sin(t * 11.0 + j)
			var tip := m + o + dir * ln + side * sin(t * 9.0 + j) * 6.0
			n.draw_colored_polygon(PackedVector2Array([m + o - side * w, tip, m + o + side * w]), Color(FIRE, 0.85))
			n.draw_colored_polygon(PackedVector2Array([m + o - side * w * 0.5, m + o + dir * ln * 0.6, m + o + side * w * 0.5]), Color(FIRE_HOT, 0.9))

# The fire: a roaring jet out of the mouth over the whole area (it grows out in
# FURNACE_GROW ticks): a ball of fire bursts out first, then the jet roars, its edges
# flickering, tongues curling up off its top, a white-hot core, smoke over its far end.
func _draw_fire(n: Node2D, i: int, tt: float) -> void:
	var r := B.fire_rect(i, int(tt))
	var spec: Array = B.FURNACES[i]
	var d: int = spec[1]
	if d == 3:
		_draw_fire_up(n, r, tt)
		return
	var dir: Vector2 = B.DIRS[d]
	var m: Vector2 = spec[0]
	var ln := r.size.x
	var half := r.size.y * 0.5
	var cy := r.get_center().y
	var top_pts := PackedVector2Array()
	var bot_pts := PackedVector2Array()
	var core_t := PackedVector2Array()
	var core_b := PackedVector2Array()
	var steps := 20
	for k in steps + 1:
		var u := float(k) / steps
		var x: float = m.x + dir.x * (ln + 14.0) * u
		var swell := 0.62 + 0.45 * sin(u * PI * 0.85 + 0.2)
		var flick := sin(t * 23.0 + u * 11.0 + i) * 8.0 + sin(t * 41.0 - u * 17.0) * 5.0
		var lick := maxf(0.0, sin(u * 31.0 - t * 18.0)) * 16.0 * u      # tongues running up its top
		var hgt := half * swell + flick
		top_pts.append(Vector2(x, cy - hgt - lick))
		bot_pts.append(Vector2(x, cy + hgt * 0.85))
		var ch := hgt * 0.48 * (1.0 - u * 0.55)
		core_t.append(Vector2(x, cy - ch))
		core_b.append(Vector2(x, cy + ch * 0.8))
	var outer := top_pts.duplicate()
	var cpts := core_t.duplicate()
	for k in range(steps, -1, -1):
		outer.append(bot_pts[k])
		cpts.append(core_b[k])
	n.draw_colored_polygon(outer, Color(FIRE_RED, 0.93))
	var mid_pts := PackedVector2Array()
	for k in outer.size():
		mid_pts.append(outer[k].lerp(Vector2(outer[k].x, cy), 0.3))
	n.draw_colored_polygon(mid_pts, Color(FIRE, 0.96))
	n.draw_colored_polygon(cpts, Color(FIRE_HOT, 0.96))
	# rolls of flame along the jet, and flames curling up and away off its top
	for k in 10:
		var u := fmod(t * 2.4 + k / 10.0, 1.0)
		var p := Vector2(m.x + dir.x * ln * u, cy + sin(t * 7.0 + k * 3.0) * half * 0.3)
		var rr := half * (0.4 + 0.6 * u)
		n.draw_texture_rect(HALO, Rect2(p - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(1.0, 0.5 + 0.35 * (1.0 - u), 0.12, 0.6 * (1.0 - u * 0.5)))
	for k in 7:
		var u := fmod(t * 1.7 + k / 7.0, 1.0)
		var x: float = m.x + dir.x * ln * (0.15 + 0.8 * fmod(k * 0.37, 1.0))
		var p := Vector2(x + sin(t * 5.0 + k) * 8.0, cy - half * 0.7 - u * 70.0)
		var s := 16.0 * (1.0 - u) + 4.0
		n.draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 0.6, s * 0.5), p + Vector2(0, -s * 1.3), p + Vector2(s * 0.6, s * 0.5)]),
			Color(FIRE.lerp(FIRE_RED, u), 0.85 * (1.0 - u)))
	var end := Vector2(m.x + dir.x * ln, cy)
	for k in 3:
		var u := fmod(t * 0.9 + k / 3.0, 1.0)
		var p := end + Vector2(dir.x * 20.0 + sin(t * 2.0 + k) * 12.0, -40.0 - u * 110.0)
		var rr := 24.0 + 40.0 * u
		n.draw_texture_rect(HALO, Rect2(p - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(0.1, 0.08, 0.08, 0.5 * (1.0 - u)))
	if tt < 10.0:   # the ball of fire it bursts out with
		var k := tt / 10.0
		var rr := 40.0 + 70.0 * k
		var c := m + dir * (30.0 + 60.0 * k)
		n.draw_texture_rect(HALO, Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(1.0, 0.85, 0.5, 0.9 * (1.0 - k)))

func _draw_fire_up(n: Node2D, r: Rect2, tt: float) -> void:
	# the firebox's fire comes up through its grate as a wall of flame filling the tunnel
	var cols := 11
	var base_y := r.end.y
	n.draw_rect(Rect2(r.position.x, base_y - 14, r.size.x, 14), Color(FIRE, 0.85))
	for k in cols:
		var u := (k + 0.5) / cols
		var x := r.position.x + r.size.x * u
		var hgt := r.size.y * (0.8 + 0.22 * sin(t * 19.0 + k * 1.7)) * clampf(tt / float(B.FURNACE_GROW), 0.2, 1.0)
		var w := r.size.x / cols * 0.95
		var sway := sin(t * 13.0 + k) * 10.0
		n.draw_colored_polygon(PackedVector2Array([Vector2(x - w, base_y), Vector2(x - w * 0.4 + sway * 0.5, base_y - hgt * 0.6),
			Vector2(x + sway, base_y - hgt - 8.0), Vector2(x + w * 0.4 + sway * 0.5, base_y - hgt * 0.6), Vector2(x + w, base_y)]), Color(FIRE_RED, 0.93))
		n.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.7, base_y), Vector2(x + sway * 0.8, base_y - hgt * 0.8),
			Vector2(x + w * 0.7, base_y)]), Color(FIRE, 0.96))
		n.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.35, base_y), Vector2(x + sway * 0.5, base_y - hgt * 0.5),
			Vector2(x + w * 0.35, base_y)]), Color(FIRE_HOT, 0.96))
	# it hits the boiler's belly and spreads along it
	var lick := PackedVector2Array([Vector2(r.position.x - 10, r.position.y), Vector2(r.end.x + 10, r.position.y)])
	for k in 13:
		var u := 1.0 - k / 12.0
		lick.append(Vector2(r.position.x - 10 + (r.size.x + 20) * u, r.position.y + 14.0 + sin(t * 21.0 + k * 1.3) * 7.0))
	n.draw_colored_polygon(lick, Color(FIRE, 0.85))
	for k in 6:
		var u := fmod(t * 2.0 + k / 6.0, 1.0)
		var p := Vector2(r.position.x + r.size.x * fmod(k * 0.41 + 0.1, 1.0), base_y - u * r.size.y)
		var rr := 20.0 + 30.0 * u
		n.draw_texture_rect(HALO, Rect2(p - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(1.0, 0.7, 0.3, 0.55 * (1.0 - u)))

func _draw_smoke(n: Node2D, i: int, k: float) -> void:
	var spec: Array = B.FURNACES[i]
	var m: Vector2 = spec[0] + B.DIRS[spec[1]] * 30.0
	for j in 5:
		var u := clampf(k + j * 0.1, 0.0, 1.0)
		var p := m + Vector2(sin(j * 1.7 + t) * 18.0 + B.DIRS[spec[1]].x * j * 14.0, -u * (90.0 + j * 24.0))
		var rr := 22.0 + 44.0 * u
		n.draw_texture_rect(HALO, Rect2(p - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(0.15, 0.12, 0.12, 0.6 * (1.0 - k)))

# A pressure pipe bulges: the pipe's end swells like a barrel and shakes, it reddens with
# the pressure, its rivets bulge out, wisps hiss from its joints, its gauge climbs into
# the red; a floor vent's grate rattles and steam seeps up through it.
func _draw_bulge(n: Node2D, i: int, k: float) -> void:
	var spec: Array = B.PIPES[i]
	var v: Vector2 = spec[0]
	var shake := Vector2(sin(t * 60.0), cos(t * 53.0)) * (3.0 * k * k)
	if spec[1] == 3:
		var r: Rect2 = spec[2]
		n.draw_rect(Rect2(r.position.x + 4 + shake.x, 1008 + shake.y * 0.5, r.size.x - 8, 6), Color(0.95, 0.97, 1.0, 0.3 + 0.55 * k * (0.5 + 0.5 * sin(t * 30.0))))
		for j in 6:
			var u := fmod(t * 1.8 + j / 6.0, 1.0)
			var p := Vector2(r.position.x + 12 + fmod(j * 0.37, 1.0) * (r.size.x - 24), 1010 - u * (40.0 + 80.0 * k))
			var rr := 12.0 + 18.0 * u
			n.draw_texture_rect(HALO, Rect2(p - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(STEAM, (0.3 + 0.45 * k) * (1.0 - u)))
	else:
		var d := -1.0 if spec[1] == 2 else 1.0
		var x0 := v.x + shake.x
		var cy := v.y + shake.y
		var len := 58.0
		var r0 := 14.0
		var rm := 14.0 + 17.0 * k
		var col := Color(0.42, 0.37, 0.34).lerp(Color(0.72, 0.3, 0.2), k * k)
		var top := PackedVector2Array()
		var bot := PackedVector2Array()
		for j in 13:
			var u := j / 12.0
			var rr := r0 + (rm - r0) * pow(sin(PI * clampf(u * 1.1, 0.0, 1.0)), 0.8)
			var x := x0 + d * len * u
			top.append(Vector2(x, cy - rr))
			bot.append(Vector2(x, cy + rr))
		var body := top.duplicate()
		for j in range(12, -1, -1):
			body.append(bot[j])
		n.draw_colored_polygon(body, col)
		var hi := PackedVector2Array()
		for j in 13:
			hi.append(top[j].lerp(Vector2(top[j].x, cy), 0.25))
		for j in range(12, -1, -1):
			hi.append(top[j].lerp(Vector2(top[j].x, cy), 0.55))
		n.draw_colored_polygon(hi, Color(1, 1, 1, 0.22 + 0.15 * k))
		var lo := PackedVector2Array()
		for j in 13:
			lo.append(bot[j].lerp(Vector2(bot[j].x, cy), 0.45))
		for j in range(12, -1, -1):
			lo.append(bot[j])
		n.draw_colored_polygon(lo, Color(0, 0, 0, 0.35))
		n.draw_polyline(body, Color(0.1, 0.08, 0.08), 2.0)
		for u in [0.2, 0.5, 0.8]:   # rivet rings stretched by the swelling
			var j := int(u * 12.0)
			n.draw_line(top[j], bot[j], Color(0.18, 0.15, 0.14), 2.0)
			n.draw_circle(top[j].lerp(bot[j], 0.2), 2.0, Color(0.85, 0.8, 0.7))
		n.draw_rect(Rect2(minf(x0 + d * len, x0 + d * (len + 10.0)), cy - 7, 10, 14), Color(0.16, 0.14, 0.14))   # the nozzle
		for j in 6:   # wisps hiss out of its joints, more as it swells
			var u := fmod(t * 2.6 + j / 6.0, 1.0)
			var up := -1.0 if j % 2 == 0 else 1.0
			var p := Vector2(x0 + d * (6.0 + (j / 2) * 22.0), cy + up * (rm + u * (20.0 + 34.0 * k)) + sin(t * 9.0 + j) * 3.0)
			var rr := 7.0 + 15.0 * u * (0.5 + k)
			n.draw_texture_rect(HALO, Rect2(p - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(STEAM, (0.35 + 0.45 * k) * (1.0 - u)))
	_draw_gauge(n, i, 0.15 + 0.85 * k + (sin(t * 40.0) * 0.04 if k > 0.7 else 0.0))

# A pipe's pressure gauge (over its nozzle, or beside its floor vent): the needle climbs
# into the red before the steam goes.
func _draw_gauge(n: Node2D, i: int, k: float) -> void:
	var spec: Array = B.PIPES[i]
	var v: Vector2 = spec[0]
	var c := v + Vector2(-24 if spec[1] == 2 else 24, -40)
	if spec[1] == 3:
		c = Vector2(spec[2].position.x - 18.0 if i == 2 else spec[2].end.x + 18.0, 986.0)
	n.draw_line(c + Vector2(0, 12), c + Vector2(0, 22), Color(0.2, 0.18, 0.18), 4.0)
	n.draw_circle(c, 14.0, Color(0.1, 0.08, 0.08))
	n.draw_circle(c, 12.0, Color(0.62, 0.48, 0.2))
	n.draw_circle(c, 10.0, Color(0.88, 0.85, 0.76))
	n.draw_arc(c, 7.5, PI * 0.75 + PI * 1.5 * 0.75, PI * 0.75 + PI * 1.5, 8, Color(0.85, 0.15, 0.1), 3.0)
	var a := PI * 0.75 + PI * 1.5 * clampf(k, 0.0, 1.0)
	n.draw_line(c, c + Vector2.from_angle(a) * 9.0, Color(0.7, 0.08, 0.06), 2.0)
	n.draw_circle(c, 2.0, Color(0.15, 0.12, 0.1))

# The steam: a white blast pours out of the nozzle along the jet (up from a floor vent),
# its puffs growing and fading, streaks showing its speed; it reaches its full length in
# PIPE_GROW ticks and dies away at the end.
func _draw_steam(n: Node2D, i: int, tt: float) -> void:
	var spec: Array = B.PIPES[i]
	var r: Rect2 = spec[2]
	var d: int = spec[1]
	var dir: Vector2 = B.DIRS[d]
	var v: Vector2 = spec[0]
	var grow := clampf(tt / float(B.PIPE_GROW), 0.0, 1.0)
	var fade := clampf((float(B.PIPE_VENT) - tt) / 20.0, 0.0, 1.0)
	var full := r.size.x if d != 3 else r.size.y
	var ln := full * grow
	var wid := r.size.y if d != 3 else r.size.x
	var side := Vector2(dir.y, dir.x).abs()
	var start := v + dir * 54.0 if d != 3 else Vector2(r.get_center().x, r.end.y)   # (the nozzle's tip)
	var count := 22 if d != 3 else 26
	for k in count:
		var u := fmod(t * 2.1 + k / float(count), 1.0)
		if u * full > ln:
			continue
		var p := start + dir * u * full + side * sin(t * 6.0 + k * 2.3) * wid * 0.25
		var rr := wid * (0.42 + 0.7 * u)
		n.draw_texture_rect(HALO, Rect2(p - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(STEAM, 0.88 * (1.0 - u * 0.6) * fade))
	for k in 6:   # speed streaks
		var u := fmod(t * 3.3 + k / 6.0, 1.0)
		var o := side * (sin(k * 2.7) * wid * 0.35)
		var a0 := start + o + dir * u * ln
		var a1 := start + o + dir * minf(ln, (u + 0.25) * ln)
		n.draw_line(a0, a1, Color(1, 1, 1, 0.5 * fade * (1.0 - u)), 3.0)
	n.draw_texture_rect(HALO, Rect2(start - Vector2(wid, wid) * 0.6, Vector2(wid, wid) * 1.2), false, Color(1, 1, 1, 0.7 * fade))

# The hook on its chain from the ceiling: links down to the hook; the chain shakes in the
# warning; swinging, a faint trail follows it.
func _draw_hook(n: Node2D) -> void:
	var hk: Dictionary = hz.get("hook", {})
	var phase := int(hk.get("phase", B.IDLE))
	var ang := hook_ang + hook_vel * (age / 2.0)
	var ln := hook_len
	var rattle := 0.0
	if phase == B.WARN:
		rattle = clampf((float(hk.get("t", 0)) + age) / float(B.HOOK_WARN), 0.0, 1.0)
	if phase == B.BLAST:
		for g in [[3.0, 0.2], [6.0, 0.1]]:
			var ga: float = ang - hook_vel * g[0] / 2.0
			var gp := B.HOOK_PIVOT + Vector2(sin(ga), cos(ga)) * ln
			n.draw_set_transform(gp, -ga, Vector2.ONE * HOOK_S)
			n.draw_texture_rect_region(PARTS_TEX, Rect2(-11, -21, 22, 30), PARTS["hook"], Color(1, 1, 1, g[1]))
	n.draw_set_transform(B.HOOK_PIVOT, -ang, Vector2.ONE * HOOK_S)
	var eye := ln / HOOK_S - 21.0       # (art px) the hook's bend sits on its point (sim/boiler.gd hook_x, hook_y)
	var steps := int(eye / 7.0)
	for k in steps:
		var y := k * 7.0
		var jx := sin(t * 47.0 + k * 1.3) * 1.2 * rattle
		if k % 2 == 0:
			n.draw_texture_rect_region(PARTS_TEX, Rect2(-3 + jx, y, 6, 8), PARTS["link_a"])
		else:
			n.draw_texture_rect_region(PARTS_TEX, Rect2(-1 + jx, y, 2, 8), PARTS["link_b"])
	n.draw_texture_rect_region(PARTS_TEX, Rect2(-11, eye, 22, 30), PARTS["hook"])
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	n.draw_rect(Rect2(B.HOOK_PIVOT.x - 14, B.HOOK_PIVOT.y - 4, 28, 10), Color(0.2, 0.18, 0.18))
	n.draw_rect(Rect2(B.HOOK_PIVOT.x - 14, B.HOOK_PIVOT.y - 4, 28, 2), Color(0.5, 0.46, 0.44))

# The lockers over the side passages: the cabinet's frame, and its door (shut it hides
# whoever is inside; open it swings out toward the room).
func _draw_lockers(n: Node2D) -> void:
	var dim := _ambient()
	for side in 2:
		var x0 := 0.0 if side == 0 else 1920.0 - LOCKER_W
		var hinge := LOCKER_W if side == 0 else 1920.0 - LOCKER_W
		var sgn := 1.0 if side == 0 else -1.0
		var cab := Color(0.34, 0.45, 0.4) * dim
		var cab_l := Color(0.55, 0.68, 0.6) * dim
		var cab_d := Color(0.14, 0.19, 0.17) * dim
		var cx0 := x0 - (8.0 if side == 1 else 0.0)
		n.draw_rect(Rect2(cx0, LOCKER_Y - 16, LOCKER_W + 8, 16), cab)                  # its cap, with vents
		n.draw_rect(Rect2(cx0, LOCKER_Y - 16, LOCKER_W + 8, 2), cab_l)
		for k in 4:
			n.draw_rect(Rect2(cx0 + 10 + k * 12, LOCKER_Y - 11, 8, 2), cab_d)
		n.draw_rect(Rect2(cx0, LOCKER_Y + LOCKER_H, LOCKER_W + 8, 5), cab_d)           # its kick plate
		var px0 := hinge - (8.0 if side == 0 else 0.0)
		n.draw_rect(Rect2(px0, LOCKER_Y - 16, 8, LOCKER_H + 21), cab)                  # the side panel by the room
		n.draw_rect(Rect2(px0 + (6.0 if side == 0 else 0.0), LOCKER_Y - 16, 2, LOCKER_H + 21), cab_l)
		for hy in [LOCKER_Y + 14.0, LOCKER_Y + LOCKER_H - 22.0]:                         # hinges
			n.draw_rect(Rect2(hinge - 3, hy, 6, 10), Color(0.6, 0.6, 0.56) * dim)
		var th: float = doors[side] * deg_to_rad(150.0)
		var free_x := hinge - sgn * LOCKER_W * cos(th)
		var lift := 10.0 * sin(th)
		var pts := PackedVector2Array([Vector2(hinge, LOCKER_Y), Vector2(free_x, LOCKER_Y - lift),
			Vector2(free_x, LOCKER_Y + LOCKER_H + lift), Vector2(hinge, LOCKER_Y + LOCKER_H)])
		var r: Rect2 = PARTS["door"]
		var tw := 256.0
		var thh := 128.0
		var u0 := r.position.x / tw
		var u1 := r.end.x / tw
		var v1 := r.end.y / thh
		if cos(th) > 0.02:
			var uvs := PackedVector2Array([Vector2(u1 if side == 0 else u0, 0), Vector2(u0 if side == 0 else u1, 0),
				Vector2(u0 if side == 0 else u1, v1), Vector2(u1 if side == 0 else u0, v1)])
			var lit := Color(dim.r * 1.35, dim.g * 1.35, dim.b * 1.35, 1.0)
			var cols := PackedColorArray([lit, lit, lit, lit])
			n.draw_polygon(pts, cols, uvs, PARTS_TEX)
		else:
			n.draw_colored_polygon(pts, Color(0.26, 0.33, 0.3) * dim)                    # the door's inside
			n.draw_polyline(PackedVector2Array([pts[1], pts[2]]), Color(0.55, 0.66, 0.6) * dim, 3.0)
			var mid := (pts[1] + pts[2]) * 0.5
			n.draw_rect(Rect2(mid.x - 3 * sgn, mid.y - 6, 4 * sgn, 12), Color(0.7, 0.7, 0.64) * dim)

# How bright the room's own light is now (the threats layer is never darkened, so the
# lockers and the sheets are dimmed by hand to sit in the room).
func _ambient() -> Color:
	var b: Color = world.dark_base
	var k := clampf((b.r + b.g + b.b) / 3.0 * 1.5, 0.25, 1.0)
	return Color(k * 1.05, k, k * 0.98, 1.0)

# A bed holding someone: the sheet rises around their legs with the striped blanket,
# thin pale arms come up out of it and grip them with long fingers, then pull them down;
# after the drop the arms sink back and the sheet settles with a ripple. Under each bed the
# pit stays dark over everything, so whoever sinks into it is swallowed.
func _draw_beds(n: Node2D) -> void:
	var dim := _ambient()
	for b in B.BEDS:      # the dark under the beds
		var x0: float = b[0]
		var w: float = b[1] - b[0]
		n.draw_polygon(PackedVector2Array([Vector2(x0, 1018), Vector2(x0 + w, 1018), Vector2(x0 + w, 1080), Vector2(x0, 1080)]),
			PackedColorArray([Color(0.03, 0.02, 0.02, 0.75), Color(0.03, 0.02, 0.02, 0.75), Color(0.01, 0.0, 0.0, 1.0), Color(0.01, 0.0, 0.0, 1.0)]))
	var bl: Array = hz.get("beds", [])
	for bi in bl.size():
		var seat: int = bl[bi][0]
		if seat < 0:
			continue
		var bt: float = float(bl[bi][1]) + age
		var b: Array = B.BEDS[bi]
		var f: Dictionary = {}
		for c in fighters:
			if int(c["id"]) == seat:
				f = c
				break
		var cx: float = (b[0] + b[1]) / 2.0
		var fy := 960.0
		if not f.is_empty() and bt < B.BED_HOLD + 2:
			cx = f["x"] + 18.0
			fy = f["y"]
		var held := bt < B.BED_HOLD
		var rise := clampf(bt / 4.0, 0.0, 1.0) if held else clampf(1.0 - (bt - B.BED_HOLD) / 14.0, 0.0, 1.0)
		var top_y := lerpf(1006.0, minf(fy + 30.0, 990.0), rise)
		var w := 70.0
		var sheet := PackedVector2Array()
		for k in 15:
			var u := k / 14.0
			var bump := pow(sin(u * PI), 0.75)
			var ripple := sin(t * 18.0 + u * 10.0) * 2.5 * (1.0 - rise) * (0.0 if held else 1.0)
			sheet.append(Vector2(cx - w + 2.0 * w * u, 1007.0 - (1007.0 - top_y) * bump + ripple))
		sheet.append(Vector2(cx + w, 1019))
		sheet.append(Vector2(cx - w, 1019))
		n.draw_colored_polygon(sheet, Color(0.8, 0.76, 0.69) * dim)
		# the blanket pulled up with it, over the foot side
		var foot := 1.0 if bi == 0 else -1.0
		var blank := PackedVector2Array()
		for k in 8:
			var p: Vector2 = sheet[7 + k * int(foot)] if foot > 0 else sheet[7 - k]
			blank.append(p + Vector2(0, 3))
		blank.append(Vector2(cx + foot * w, 1019))
		blank.append(Vector2(cx + foot * 6.0, 1019))
		n.draw_colored_polygon(blank, Color(0.55, 0.13, 0.11) * dim)
		for k in 4:
			var x := cx + foot * (10.0 + k * 15.0)
			n.draw_line(Vector2(x, 1018), Vector2(x - foot * 4.0, lerpf(1018.0, top_y + 12.0, 0.8 - k * 0.15)), Color(0.13, 0.36, 0.19) * dim, 6.0)
		for k in 5:   # folds pulled toward the grip
			var x := cx - 52.0 + k * 26.0
			n.draw_line(Vector2(x, 1016), Vector2(lerpf(x, cx, 0.6), lerpf(1016.0, top_y + 10.0, 0.85)), Color(0.52, 0.48, 0.42) * dim, 2.0)
		n.draw_polyline(sheet.slice(0, 15), Color(0.95, 0.92, 0.85) * dim, 2.0)
		# the arms and their long fingers
		var reach := clampf(bt / 5.0, 0.0, 1.0) if held else clampf(1.0 - (bt - B.BED_HOLD) / 4.0, 0.0, 1.0)
		if reach <= 0.0:
			continue
		var curl := clampf((bt - 4.0) / 4.0, 0.0, 1.0)
		var pull := maxf(0.0, bt - 6.0) * 1.0
		var skin := Color(0.72, 0.76, 0.7) * dim
		var line := Color(0.16, 0.18, 0.16) * dim
		for a in [[-36.0, -12.0, 42.0], [-2.0, 4.0, 26.0], [30.0, 14.0, 46.0]]:
			var base := Vector2(cx + a[0], 1006.0 - (1006.0 - top_y) * 0.55)
			var grip := Vector2(cx + a[1], fy + a[2] + pull)
			var hand := base.lerp(grip, reach)
			var dirv := (hand - base).normalized()
			var side := Vector2(-dirv.y, dirv.x)
			var arm := PackedVector2Array([base - side * 6.0, hand - side * 4.0, hand + side * 4.0, base + side * 6.0])
			n.draw_colored_polygon(arm, line)
			n.draw_colored_polygon(PackedVector2Array([base - side * 4.5, hand - side * 2.8, hand + side * 2.8, base + side * 4.5]), skin)
			n.draw_circle(hand, 6.0, line)
			n.draw_circle(hand, 4.8, skin)
			for k in 4:   # four long thin fingers curling over them, and a thumb
				var spread := (k - 1.5) * 0.32
				var d1 := dirv.rotated(spread)
				var d2 := d1.rotated((0.9 if a[0] < 0.0 else -0.9) * curl)
				var j1 := hand + d1 * 9.0
				var j2 := j1 + d2 * (9.0 + 2.0 * (1.5 - absf(k - 1.5)))
				n.draw_polyline(PackedVector2Array([hand, j1, j2]), line, 4.0)
				n.draw_polyline(PackedVector2Array([hand, j1, j2]), skin, 2.0)
			var th := dirv.rotated(-1.4 if a[0] < 0.0 else 1.4)
			n.draw_line(hand, hand + th * 8.0, line, 4.0)
			n.draw_line(hand, hand + th * 8.0, skin, 2.0)

# ---------------------------------------------- the glow layer (added light)
func _paint_glow(n: Node2D) -> void:
	# the bulbs: a halo and a soft cone of light under each
	for i in bulbs.size():
		var b: float = bright[i]
		if b <= 0.02:
			continue
		var p: Vector2 = bulbs[i][0] + Vector2(sin(t * 1.2 + bulbs[i][2]) * (2.0 + surge_k * 6.0), 2)
		var c := BULB.lerp(Color(1.0, 0.3, 0.2), surge_k)
		n.draw_texture_rect(HALO, Rect2(p - Vector2(34, 34), Vector2(68, 68)), false, Color(c, 0.55 * b))
		n.draw_polygon(PackedVector2Array([p + Vector2(-8, 6), p + Vector2(8, 6), p + Vector2(110, 300), p + Vector2(-110, 300)]),
			PackedColorArray([Color(c, 0.09 * b), Color(c, 0.09 * b), Color(c, 0.0), Color(c, 0.0)]))
	# the furnaces: the grate glows through its slots, brighter as the fire comes; the
	# mouth glows; the fire throws its light around
	for i in B.FURNACES.size():
		var f := _ph("f", i)
		var heat := 0.32 + 0.08 * sin(t * 7.0 + i * 2.0) + 0.05 * sin(t * 23.0 + i)
		if f[0] == B.WARN:
			heat = lerpf(0.45, 1.0, _warn_k(f)) * (0.85 + 0.15 * sin(t * 30.0))
		elif f[0] == B.BLAST:
			heat = 1.0
		elif f[0] == B.COOL:
			heat = lerpf(0.9, 0.35, clampf(f[1] / float(B.FURNACE_COOL), 0.0, 1.0))
		heat = maxf(heat, surge_k * 0.9)
		var dc: Vector2 = DOORS[i]
		var col := FIRE.lerp(FIRE_HOT, maxf(0.0, heat - 0.6) / 0.4)
		if i < 2:
			for k in 4:
				n.draw_rect(Rect2(dc.x - 12 + k * 8, dc.y - 18, 4, 36), Color(col, 0.35 + 0.6 * heat))
			n.draw_texture_rect(HALO, Rect2(dc - Vector2(50, 50) * (0.8 + heat), Vector2(100, 100) * (0.8 + heat)), false, Color(col, 0.35 * heat))
		else:
			for x in range(884, 1040, 10):
				n.draw_rect(Rect2(x, 940, 6, 60), Color(col, 0.3 + 0.6 * heat))
			n.draw_texture_rect(HALO, Rect2(dc - Vector2(110, 60) * (0.8 + heat), Vector2(220, 120) * (0.8 + heat)), false, Color(col, 0.3 * heat))
		var m: Vector2 = B.FURNACES[i][0]
		n.draw_texture_rect(HALO, Rect2(m - Vector2(40, 40) * (0.6 + heat), Vector2(80, 80) * (0.6 + heat)), false, Color(FIRE, 0.4 * heat))
		if f[0] == B.BLAST:
			var r := B.fire_rect(i, int(f[1]))
			var c := r.get_center()
			var big := maxf(r.size.x, r.size.y)
			n.draw_texture_rect(HALO, Rect2(c - Vector2(big, big) * 0.9, Vector2(big, big) * 1.8), false, Color(1.0, 0.5, 0.15, 0.55))
			n.draw_texture_rect(HALO, Rect2(c - Vector2(big, big) * 0.5, Vector2(big, big) * 1.0), false, Color(1.0, 0.8, 0.4, 0.5))
	for i in B.PIPES.size():   # a bulging pipe glows red-hot, pulsing faster as it comes
		var p := _ph("p", i)
		var spec: Array = B.PIPES[i]
		if p[0] == B.WARN and spec[1] != 3:
			var k := clampf(p[1] / float(B.PIPE_WARN), 0.0, 1.0)
			var c: Vector2 = spec[0] + Vector2((-1.0 if spec[1] == 2 else 1.0) * 30.0, 0)
			var pulse := 0.6 + 0.4 * sin(t * lerpf(8.0, 30.0, k))
			n.draw_texture_rect(HALO, Rect2(c - Vector2(60, 60) * (0.6 + k), Vector2(120, 120) * (0.6 + k)), false,
				Color(1.0, 0.3, 0.15, 0.5 * k * pulse))
	for sp in sparks:
		var a: float = clampf(sp[2] / 0.3, 0.0, 1.0)
		n.draw_rect(Rect2(sp[0], Vector2(4, 4)), Color(sp[3], a))
	# the surge: a red heartbeat at the edges of the room
	if surge_k > 0.01:
		var beat := _heartbeat()
		var a2 := surge_k * (0.18 + 0.32 * beat)
		var red := Color(1.0, 0.1, 0.05)
		for e in [[Rect2(0, 0, 1920, 140), 0], [Rect2(0, 940, 1920, 140), 1], [Rect2(0, 0, 220, 1080), 2], [Rect2(1700, 0, 220, 1080), 3]]:
			var rr: Rect2 = e[0]
			var cs := PackedColorArray()
			var full := Color(red, a2)
			var none := Color(red, 0.0)
			match int(e[1]):
				0: cs = PackedColorArray([full, full, none, none])
				1: cs = PackedColorArray([none, none, full, full])
				2: cs = PackedColorArray([full, none, none, full])
				_: cs = PackedColorArray([none, full, full, none])
			n.draw_polygon(PackedVector2Array([rr.position, Vector2(rr.end.x, rr.position.y), rr.end, Vector2(rr.position.x, rr.end.y)]), cs)
	# the tall shadow's furnace light (the shadow itself is drawn plain, over it)
	var fig: int = hz.get("fig", -1)
	if fig >= 0 and fig < B.FIGURE_AT.size():
		var fa := _fig_alpha()
		var fp: Vector2 = B.FIGURE_AT[fig]
		n.draw_texture_rect(HALO, Rect2(fp - Vector2(130, 230), Vector2(260, 260)), false, Color(1.0, 0.45, 0.12, 0.55 * fa))

# How much of the tall shadow shows: it fades in once the lights are out and away before
# they come back; it is drawn over the fighters (in the furnace's light), so it fades to
# a trace whenever a fighter comes near it (nobody is ever hidden behind it).
func _fig_alpha() -> float:
	var ls: Array = hz.get("lights", [B.LIGHTS_ON, 0])
	if ls[0] != B.LIGHTS_DARK:
		return 0.0
	var lt: float = float(ls[1]) + age
	var k := clampf(lt / 24.0, 0.0, 1.0) * clampf((float(B.LIGHTS_STEPS[2]) - lt) / 30.0, 0.0, 1.0)
	var fig: int = hz.get("fig", -1)
	if fig >= 0 and fig < B.FIGURE_AT.size():
		var fp: Vector2 = B.FIGURE_AT[fig]
		var r := Rect2(fp.x - 70.0, fp.y - 190.0, 140.0, 200.0)
		for f in fighters:
			if int(f["state"]) != P.F_DEAD and r.intersects(Rect2(f["x"], f["y"], 36, 63)):
				k *= 0.2
				break
	return k

# ---------------------------------------------- the glow layer, plain
func _paint_shade(n: Node2D) -> void:
	var fig: int = hz.get("fig", -1)
	if fig < 0 or fig >= B.FIGURE_AT.size():
		return
	var fa := _fig_alpha()
	if fa <= 0.0:
		return
	var fp: Vector2 = B.FIGURE_AT[fig]
	var r: Rect2 = PARTS["shadow"]
	var s := 1.3 + 0.02 * sin(t * 2.0)
	var size := r.size * s
	var flip := fig == 1
	var sway := sin(t * 1.7) * 3.0
	n.draw_texture_rect_region(PARTS_TEX, Rect2(Vector2(fp.x + sway - size.x / 2.0 * (-1.0 if flip else 1.0), fp.y - size.y),
		Vector2(-size.x if flip else size.x, size.y)), r, Color(0.02, 0.0, 0.0, 0.9 * fa))

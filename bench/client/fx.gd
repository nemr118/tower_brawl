# The bench's effects: every simulation event becomes pixel particles, flashes,
# shock rings, afterimages, short-lived lights, scorch marks and screen shake.
# Pools only: nothing is created during play, so the numbers measure drawing,
# not node creation. Added effects go on the glow layer (no darkening), solid
# ones (dust, smoke, debris) on the lit layer, where the lights reach them.
extends Node2D

const P = preload("res://sim/proto.gd")
const Factory = preload("res://client/fx_factory.gd")
const HALO := preload("res://assets/fx_halo.png")
const LIGHT := preload("res://assets/fx_light.png")
const SCORCH := preload("res://assets/fx_scorch.png")
const ONE_SHOT := {"dust_jump": 8, "dust_land": 8, "wall_dust": 4, "dodge_ring": 6, "spark": 10, "debris": 8,
	"flame_burst": 6, "blast_sparks": 4, "blast_fire": 4, "blast_smoke": 4, "blast_debris": 4,
	"miasma_burst": 4, "catch_star": 4, "pickup": 6, "death_burst": 6, "soul": 6, "spawn_beam": 6,
	"smoke_burst": 4, "hurt_spark": 6, "ledge_dust": 4}
const KIND_COLOR := [Color(0.85, 0.95, 1.0), Color(1.0, 0.6, 0.15), Color(1.0, 0.35, 0.25), Color(0.75, 0.35, 1.0), Color(0.78, 0.8, 0.84)]

var cpu := false
var mult := 1.0
var ratio := 1.0
var all_emitters: Array = []
var enabled := false
var lights_enabled := false
var team: Array = []
var lit: Node2D
var glow: Node2D
var pools := {}
var pool_i := {}
var free_loops := {}
var shake := 0.0
var aberration := 0.0
var rings: Array = []
var flashes: Array = []
var flash_i := 0
var lights: Array = []
var light_i := 0
var decals: Array = []
var decal_i := 0
var ghosts: Array = []
var ghost_i := 0
var add_mat := CanvasItemMaterial.new()

func setup(lit_parent: Node2D, glow_parent: Node2D, colors: Array, cpu_mode: bool, amount_mult: float = 1.0) -> void:
	lit = lit_parent
	glow = glow_parent
	team = colors
	cpu = cpu_mode
	mult = amount_mult
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = add_mat
	for kind in ONE_SHOT:
		var arr: Array = []
		for i in ONE_SHOT[kind]:
			var e := Factory.make(kind, cpu, mult)
			(glow if Factory.SPEC[kind]["add"] else lit).add_child(e)
			e.position = Vector2(-4000, -4000)
			arr.append(e)
			all_emitters.append(e)
		pools[kind] = arr
		pool_i[kind] = 0
	for i in 12:
		var s := Sprite2D.new()
		s.texture = HALO
		s.material = add_mat
		s.visible = false
		glow.add_child(s)
		flashes.append([s, 0.0, 0.0, 1.0])
	for i in (16 if mult > 1.0 else 8):
		var l := PointLight2D.new()
		l.texture = LIGHT
		l.enabled = false
		l.height = 60.0
		lit.add_child(l)
		lights.append([l, 0.0, 0.0, 0.0])
	for i in 16:
		var d := Sprite2D.new()
		d.texture = SCORCH
		d.scale = Vector2(3, 3)
		d.visible = false
		lit.add_child(d)
		decals.append([d, 0.0])
	for i in 32:
		var g := Sprite2D.new()
		g.material = add_mat
		g.visible = false
		glow.add_child(g)
		ghosts.append([g, 0.0])

# The first burst of every kind, where nobody sees it, so shaders compile at load.
func prewarm(at: Vector2) -> void:
	var was := enabled
	enabled = true
	for kind in pools:
		_burst(kind, at)
	enabled = was

func set_tier(fx_on: bool, lights_on: bool) -> void:
	enabled = fx_on
	lights_enabled = lights_on
	for kind in pools:
		for e in pools[kind]:
			e.visible = fx_on
	for l in lights:
		l[0].enabled = false
		l[1] = 0.0

# A looping emitter (trail, ground fire, bubbles) to follow something.
func take_loop(kind: String) -> Node2D:
	var free: Array = free_loops.get(kind, [])
	var e: Node2D
	if free.size() > 0:
		e = free.pop_back()
	else:
		e = Factory.make(kind, cpu, mult)
		(glow if Factory.SPEC[kind]["add"] else lit).add_child(e)
		all_emitters.append(e)
		if "amount_ratio" in e:
			e.amount_ratio = ratio
	e.visible = true
	e.emitting = true
	return e

func give_loop(kind: String, e: Node2D) -> void:
	e.emitting = false
	if not free_loops.has(kind):
		free_loops[kind] = []
	free_loops[kind].append(e)

# The limit test's dial: the share of every emitter's particles that is drawn.
func set_ratio(r: float) -> void:
	ratio = clampf(r, 0.05, 1.0)
	for e in all_emitters:
		if "amount_ratio" in e:
			e.amount_ratio = ratio

func _burst(kind: String, pos: Vector2, color := Color.WHITE, rot := 0.0) -> void:
	if not enabled:
		return
	var arr: Array = pools[kind]
	var i: int = pool_i[kind]
	pool_i[kind] = (i + 1) % arr.size()
	var e: Node2D = arr[i]
	e.global_position = pos
	e.rotation = rot
	e.modulate = color
	e.restart()

func flash(pos: Vector2, size: float, color: Color, secs: float) -> void:
	if not enabled:
		return
	var f: Array = flashes[flash_i]
	flash_i = (flash_i + 1) % flashes.size()
	f[0].global_position = pos
	f[0].modulate = color
	f[0].visible = true
	f[1] = secs
	f[2] = secs
	f[3] = size

func light_burst(pos: Vector2, color: Color, energy: float, scale_: float, secs: float) -> void:
	if not lights_enabled:
		return
	var l: Array = lights[light_i]
	light_i = (light_i + 1) % lights.size()
	l[0].global_position = pos
	l[0].color = color
	l[0].texture_scale = scale_
	l[0].energy = energy
	l[0].enabled = true
	l[1] = secs
	l[2] = secs
	l[3] = energy

func ring(pos: Vector2, max_r: float, color: Color, secs: float) -> void:
	rings.append([pos, 0.0, max_r, color, secs])

func scorch(pos: Vector2) -> void:
	if not enabled:
		return
	var d: Array = decals[decal_i]
	decal_i = (decal_i + 1) % decals.size()
	d[0].global_position = pos
	d[0].visible = true
	d[0].modulate.a = 1.0
	d[1] = 8.0

func ghost(tex: Texture2D, region: Rect2, pos: Vector2, flip: bool, color: Color) -> void:
	if not enabled:
		return
	var g: Array = ghosts[ghost_i]
	ghost_i = (ghost_i + 1) % ghosts.size()
	g[0].texture = tex
	g[0].region_enabled = true
	g[0].region_rect = region
	g[0].flip_h = flip
	g[0].global_position = pos
	g[0].modulate = color
	g[0].visible = true
	g[1] = 0.25

# Runs at every tier: rings, shake and colour split feed the fog and the post
# shader, and short lights are their own part. The particle, flash, scorch and
# ring drawing checks `enabled` itself (the split test turns them off alone).
func on_event(e: Array) -> void:
	var pos := Vector2(e[1], e[2])
	var type: int = e[0]
	if type == P.E_JUMP:
		_burst("dust_jump", pos)
		if e[4] == 1:
			_burst("spark", pos)
			flash(pos, 2.0, Color(1, 1, 0.8), 0.1)
	elif type == P.E_LAND:
		if e[4] >= 6:
			_burst("dust_land", pos)
	elif type == P.E_WALLJUMP:
		_burst("wall_dust", pos, Color.WHITE, PI if e[4] == 1 else 0.0)
	elif type == P.E_DODGE:
		var c: Color = team[e[3] % team.size()]
		_burst("dodge_ring", pos, c)
		flash(pos, 2.5, c, 0.12)
	elif type == P.E_SHOOT:
		var kc: Color = KIND_COLOR[e[4] % 5]
		_burst("spark", pos, kc)
		flash(pos, 1.2, kc, 0.08)
	elif type == P.E_STICK:
		_burst("debris", pos)
		_burst("spark", pos, KIND_COLOR[e[3] % 5])
	elif type == P.E_EXPLODE:
		flash(pos, 5.0, Color(1, 0.9, 0.6), 0.16)
		ring(pos, 230.0, Color(1, 0.75, 0.35), 0.35)
		ring(pos, 150.0, Color(1, 1, 0.9), 0.2)
		_burst("blast_fire", pos)
		_burst("blast_sparks", pos)
		_burst("blast_smoke", pos)
		_burst("blast_debris", pos)
		light_burst(pos, Color(1, 0.6, 0.25), 3.0, 3.5, 0.45)
		scorch(pos + Vector2(0, 12))
		shake = maxf(shake, 16.0)
		aberration = 1.0
	elif type == P.E_IGNITE:
		_burst("flame_burst", pos)
		flash(pos, 4.0, Color(1, 0.6, 0.2), 0.15)
		light_burst(pos, Color(1, 0.55, 0.2), 1.8, 2.2, 0.3)
		scorch(pos + Vector2(0, 4))
	elif type == P.E_MIASMA:
		_burst("miasma_burst", pos)
		ring(pos, 170.0, Color(0.75, 0.35, 1.0), 0.4)
		flash(pos, 5.0, Color(0.7, 0.3, 1.0), 0.18)
		shake = maxf(shake, 5.0)
	elif type == P.E_DEATH:
		var c: Color = team[e[3] % team.size()]
		_burst("death_burst", pos, c)
		_burst("soul", pos)
		flash(pos, 4.0, Color(1, 1, 1), 0.12)
		shake = maxf(shake, 6.0)
		if e[4] == 4:
			_burst("flame_burst", pos)
		elif e[4] == 5 or e[4] == 6:
			_burst("miasma_burst", pos)
	elif type == P.E_CATCH:
		_burst("catch_star", pos)
		flash(pos, 3.0, Color(1, 0.95, 0.6), 0.15)
		ring(pos, 60.0, Color(1, 1, 1), 0.18)
	elif type == P.E_PICKUP:
		_burst("pickup", pos, team[e[3] % team.size()])
	elif type == P.E_SPAWN:
		var c: Color = team[e[3] % team.size()]
		_burst("spawn_beam", pos, c)
		ring(pos + Vector2(0, -30), 70.0, c, 0.3)
	elif type == P.E_TINK:
		_burst("spark", pos)
	elif type == P.E_HURT:
		_burst("hurt_spark", pos)
		flash(pos, 2.2, Color(1, 1, 1), 0.08)
		shake = maxf(shake, 4.0)
	elif type == P.E_LEDGE:
		_burst("ledge_dust", pos)
	elif type == P.E_SMOKE:
		_burst("smoke_burst", pos)
		ring(pos, 200.0, Color(0.8, 0.82, 0.88), 0.45)
		flash(pos, 3.0, Color(0.9, 0.9, 1.0), 0.1)
		shake = maxf(shake, 3.0)
	elif type == P.E_DRYFIRE:
		_burst("hurt_spark", pos, Color(0.7, 0.7, 0.7))

func _process(delta: float) -> void:
	shake = maxf(0.0, shake - delta * 60.0)
	aberration = maxf(0.0, aberration - delta * 3.0)
	for f in flashes:
		if f[1] > 0.0:
			f[1] -= delta
			var k: float = clampf(f[1] / f[2], 0.0, 1.0)
			f[0].scale = Vector2.ONE * f[3] * (1.4 - 0.4 * k)
			f[0].modulate.a = k
			if f[1] <= 0.0:
				f[0].visible = false
	for l in lights:
		if l[1] > 0.0:
			l[1] -= delta
			l[0].energy = l[3] * clampf(l[1] / l[2], 0.0, 1.0)
			if l[1] <= 0.0:
				l[0].enabled = false
	for d in decals:
		if d[1] > 0.0:
			d[1] -= delta
			d[0].modulate.a = clampf(d[1] / 3.0, 0.0, 1.0)
			if d[1] <= 0.0:
				d[0].visible = false
	for g in ghosts:
		if g[1] > 0.0:
			g[1] -= delta
			g[0].modulate.a = clampf(g[1] / 0.25, 0.0, 1.0) * 0.7
			if g[1] <= 0.0:
				g[0].visible = false
	for i in range(rings.size() - 1, -1, -1):
		rings[i][1] += delta
		if rings[i][1] >= rings[i][4]:
			rings.remove_at(i)
	queue_redraw()

func _draw() -> void:
	if not enabled:
		return
	for r in rings:
		var k: float = r[1] / r[4]
		var col: Color = r[3]
		col.a = 1.0 - k
		draw_arc(r[0], r[2] * (0.25 + 0.75 * k), 0.0, TAU, 28, col, 6.0 * (1.0 - k) + 3.0)

# Emitters that are shown and emitting now (the split test's proof that particles are on or off).
func count_drawn() -> int:
	var n := 0
	for e in all_emitters:
		if e.emitting and e.is_visible_in_tree():
			n += 1
	return n

func count_active() -> int:
	var n := 0
	for kind in pools:
		for e in pools[kind]:
			if e.emitting:
				n += 1
	for kind in free_loops:
		n -= 0
	return n

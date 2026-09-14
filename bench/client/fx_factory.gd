# Builds the bench's particle emitters from one table, as GPU particles or (with
# cpu = true) CPU particles. Every effect is pixel art: small square textures,
# corners snapped to a 3 px grid by the shaders, colours in hard steps.
extends RefCounted

const TEX := {
	"px": preload("res://assets/fx_px.png"), "dot": preload("res://assets/fx_dot.png"),
	"smoke": preload("res://assets/fx_smoke.png"), "flame": preload("res://assets/fx_flame.png"),
	"spark": preload("res://assets/fx_spark.png"), "halo": preload("res://assets/fx_halo.png"),
	"smokebig": preload("res://assets/fx_smokebig.png"), "streak": preload("res://assets/fx_streak.png"),
}
const ADD := preload("res://shaders/px_add.gdshader")
const MIX := preload("res://shaders/px_mix.gdshader")

# amount, life, one_shot, explos, tex, add, dir, spread, v (min,max), gravity,
# damp, scale (min,max), colors, box (half extents) or radius, angvel
const SPEC := {
	"dust_jump": {"amount": 10, "life": 0.35, "one_shot": true, "explos": 1.0, "tex": "px", "add": false,
		"dir": Vector2(0, -1), "spread": 70.0, "v": Vector2(60, 180), "gravity": Vector2(0, 300), "damp": Vector2(200, 300),
		"scale": Vector2(1.0, 2.0), "colors": [Color(0.85, 0.82, 0.76, 0.9), Color(0.55, 0.52, 0.55, 0.5)], "box": Vector2(14, 2)},
	"dust_land": {"amount": 16, "life": 0.45, "one_shot": true, "explos": 1.0, "tex": "px", "add": false,
		"dir": Vector2(0, -1), "spread": 88.0, "v": Vector2(80, 260), "gravity": Vector2(0, 400), "damp": Vector2(250, 350),
		"scale": Vector2(1.0, 2.5), "colors": [Color(0.8, 0.78, 0.72, 0.9), Color(0.5, 0.5, 0.55, 0.4)], "box": Vector2(18, 2)},
	"wall_dust": {"amount": 10, "life": 0.3, "one_shot": true, "explos": 1.0, "tex": "px", "add": false,
		"dir": Vector2(1, -0.3), "spread": 40.0, "v": Vector2(80, 220), "gravity": Vector2(0, 300), "damp": Vector2(200, 300),
		"scale": Vector2(1.0, 2.0), "colors": [Color(0.85, 0.82, 0.76, 0.9), Color(0.5, 0.5, 0.55, 0.3)], "box": Vector2(2, 20)},
	"dodge_ring": {"amount": 20, "life": 0.3, "one_shot": true, "explos": 1.0, "tex": "px", "add": true,
		"dir": Vector2(1, 0), "spread": 180.0, "v": Vector2(220, 320), "gravity": Vector2.ZERO, "damp": Vector2(600, 800),
		"scale": Vector2(1.0, 1.5), "colors": [Color(1, 1, 1, 1), Color(0.5, 0.8, 1.0, 0.0)], "radius": 10.0},
	"spark": {"amount": 8, "life": 0.25, "one_shot": true, "explos": 1.0, "tex": "spark", "add": true,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(150, 380), "gravity": Vector2(0, 600), "damp": Vector2(100, 200),
		"scale": Vector2(1.0, 1.5), "colors": [Color(1, 0.95, 0.7, 1), Color(1, 0.6, 0.2, 0.0)], "radius": 3.0},
	"debris": {"amount": 8, "life": 0.5, "one_shot": true, "explos": 1.0, "tex": "px", "add": false,
		"dir": Vector2(0, -1), "spread": 80.0, "v": Vector2(80, 220), "gravity": Vector2(0, 900), "damp": Vector2(0, 30),
		"scale": Vector2(0.8, 1.6), "colors": [Color(0.45, 0.47, 0.6, 1), Color(0.25, 0.27, 0.38, 1)], "radius": 4.0},
	"flame_burst": {"amount": 28, "life": 0.6, "one_shot": true, "explos": 0.9, "tex": "flame", "add": true,
		"dir": Vector2(0, -1), "spread": 35.0, "v": Vector2(80, 260), "gravity": Vector2(0, -120), "damp": Vector2(60, 120),
		"scale": Vector2(1.5, 3.0), "colors": [Color(1, 1, 0.75, 1), Color(1, 0.62, 0.15, 0.95), Color(0.9, 0.2, 0.08, 0.7), Color(0.3, 0.05, 0.05, 0.0)], "box": Vector2(40, 4)},
	"fire_ground": {"amount": 36, "life": 0.7, "one_shot": false, "explos": 0.0, "tex": "flame", "add": true,
		"dir": Vector2(0, -1), "spread": 12.0, "v": Vector2(50, 150), "gravity": Vector2(0, -60), "damp": Vector2(20, 60),
		"scale": Vector2(1.2, 2.8), "colors": [Color(1, 1, 0.75, 1), Color(1, 0.62, 0.15, 0.95), Color(0.9, 0.2, 0.08, 0.7), Color(0.3, 0.05, 0.05, 0.0)], "box": Vector2(75, 3)},
	"embers": {"amount": 12, "life": 1.4, "one_shot": false, "explos": 0.0, "tex": "px", "add": true,
		"dir": Vector2(0, -1), "spread": 25.0, "v": Vector2(40, 120), "gravity": Vector2(0, -20), "damp": Vector2(0, 10),
		"scale": Vector2(0.5, 1.0), "colors": [Color(1, 0.85, 0.4, 1), Color(1, 0.4, 0.1, 0.8), Color(0.6, 0.1, 0.05, 0.0)], "box": Vector2(75, 3)},
	"trail_fire": {"amount": 24, "life": 0.35, "one_shot": false, "explos": 0.0, "tex": "flame", "add": true,
		"dir": Vector2(0, -1), "spread": 30.0, "v": Vector2(10, 60), "gravity": Vector2(0, -80), "damp": Vector2(0, 20),
		"scale": Vector2(1.0, 2.0), "colors": [Color(1, 1, 0.7, 1), Color(1, 0.55, 0.12, 0.9), Color(0.7, 0.12, 0.05, 0.0)], "radius": 4.0},
	"trail_miasma": {"amount": 16, "life": 0.6, "one_shot": false, "explos": 0.0, "tex": "dot", "add": false,
		"dir": Vector2(0, 1), "spread": 40.0, "v": Vector2(10, 50), "gravity": Vector2(0, 120), "damp": Vector2(0, 20),
		"scale": Vector2(0.6, 1.2), "colors": [Color(0.75, 0.35, 1.0, 1), Color(0.35, 0.1, 0.5, 0.0)], "radius": 3.0},
	"trail_fuse": {"amount": 10, "life": 0.25, "one_shot": false, "explos": 0.0, "tex": "px", "add": true,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(40, 140), "gravity": Vector2(0, 200), "damp": Vector2(0, 50),
		"scale": Vector2(0.4, 0.8), "colors": [Color(1, 1, 0.6, 1), Color(1, 0.5, 0.1, 0.0)], "radius": 2.0},
	"trail_plain": {"amount": 8, "life": 0.18, "one_shot": false, "explos": 0.0, "tex": "px", "add": true,
		"dir": Vector2(0, 0), "spread": 180.0, "v": Vector2(0, 10), "gravity": Vector2.ZERO, "damp": Vector2.ZERO,
		"scale": Vector2(0.4, 0.7), "colors": [Color(0.8, 0.9, 1.0, 0.6), Color(0.5, 0.6, 0.8, 0.0)], "radius": 1.0},
	"blast_sparks": {"amount": 48, "life": 0.5, "one_shot": true, "explos": 1.0, "tex": "spark", "add": true,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(300, 900), "gravity": Vector2(0, 700), "damp": Vector2(300, 600),
		"scale": Vector2(1.0, 2.5), "colors": [Color(1, 1, 0.85, 1), Color(1, 0.7, 0.2, 1), Color(0.9, 0.2, 0.05, 0.0)], "radius": 20.0},
	"blast_fire": {"amount": 30, "life": 0.45, "one_shot": true, "explos": 1.0, "tex": "smoke", "add": true,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(80, 380), "gravity": Vector2(0, -100), "damp": Vector2(400, 700),
		"scale": Vector2(2.0, 4.5), "colors": [Color(1, 1, 0.8, 1), Color(1, 0.6, 0.15, 0.9), Color(0.6, 0.12, 0.05, 0.0)], "radius": 30.0},
	"blast_smoke": {"amount": 16, "life": 1.4, "one_shot": true, "explos": 0.8, "tex": "smoke", "add": false,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(40, 160), "gravity": Vector2(0, -60), "damp": Vector2(60, 120),
		"scale": Vector2(2.5, 5.0), "colors": [Color(0.3, 0.27, 0.3, 0.85), Color(0.16, 0.14, 0.18, 0.5), Color(0.1, 0.1, 0.12, 0.0)], "radius": 40.0},
	"blast_debris": {"amount": 24, "life": 0.9, "one_shot": true, "explos": 1.0, "tex": "px", "add": false,
		"dir": Vector2(0, -1), "spread": 120.0, "v": Vector2(200, 600), "gravity": Vector2(0, 1400), "damp": Vector2(0, 40),
		"scale": Vector2(0.8, 2.0), "colors": [Color(0.45, 0.47, 0.6, 1), Color(0.2, 0.18, 0.2, 1)], "radius": 20.0},
	"miasma_burst": {"amount": 30, "life": 0.9, "one_shot": true, "explos": 0.9, "tex": "smoke", "add": false,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(60, 260), "gravity": Vector2(0, -40), "damp": Vector2(200, 300),
		"scale": Vector2(2.0, 4.0), "colors": [Color(0.8, 0.45, 1.0, 0.95), Color(0.4, 0.12, 0.6, 0.7), Color(0.15, 0.03, 0.22, 0.0)], "radius": 30.0},
	"miasma_bubbles": {"amount": 14, "life": 1.1, "one_shot": false, "explos": 0.0, "tex": "dot", "add": true,
		"dir": Vector2(0, -1), "spread": 30.0, "v": Vector2(20, 70), "gravity": Vector2(0, -30), "damp": Vector2(0, 10),
		"scale": Vector2(0.6, 1.4), "colors": [Color(0.85, 0.5, 1.0, 0.9), Color(0.4, 0.1, 0.6, 0.0)], "radius": 110.0},
	"catch_star": {"amount": 16, "life": 0.4, "one_shot": true, "explos": 1.0, "tex": "spark", "add": true,
		"dir": Vector2(1, 0), "spread": 180.0, "v": Vector2(120, 260), "gravity": Vector2.ZERO, "damp": Vector2(400, 500),
		"scale": Vector2(1.0, 2.0), "colors": [Color(1, 1, 1, 1), Color(1, 0.9, 0.4, 1), Color(1, 0.7, 0.2, 0.0)], "radius": 6.0},
	"pickup": {"amount": 8, "life": 0.5, "one_shot": true, "explos": 0.8, "tex": "px", "add": true,
		"dir": Vector2(0, -1), "spread": 25.0, "v": Vector2(80, 160), "gravity": Vector2.ZERO, "damp": Vector2(150, 200),
		"scale": Vector2(0.6, 1.0), "colors": [Color(1, 1, 0.8, 1), Color(0.6, 0.9, 1.0, 0.0)], "radius": 10.0},
	"death_burst": {"amount": 36, "life": 0.7, "one_shot": true, "explos": 1.0, "tex": "px", "add": false,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(150, 520), "gravity": Vector2(0, 1100), "damp": Vector2(40, 100),
		"scale": Vector2(1.0, 2.2), "colors": [Color(1, 1, 1, 1), Color(0.9, 0.9, 0.9, 1)], "radius": 12.0},
	"soul": {"amount": 10, "life": 1.0, "one_shot": true, "explos": 0.3, "tex": "dot", "add": true,
		"dir": Vector2(0, -1), "spread": 15.0, "v": Vector2(60, 140), "gravity": Vector2(0, -40), "damp": Vector2(0, 20),
		"scale": Vector2(0.8, 1.6), "colors": [Color(0.8, 0.95, 1.0, 1), Color(0.4, 0.7, 1.0, 0.0)], "radius": 8.0},
	"spawn_beam": {"amount": 24, "life": 0.6, "one_shot": true, "explos": 0.6, "tex": "px", "add": true,
		"dir": Vector2(0, -1), "spread": 5.0, "v": Vector2(200, 500), "gravity": Vector2.ZERO, "damp": Vector2(100, 200),
		"scale": Vector2(0.6, 1.2), "colors": [Color(1, 1, 1, 1), Color(0.6, 0.9, 1.0, 0.0)], "box": Vector2(20, 4)},
	"torch": {"amount": 14, "life": 0.5, "one_shot": false, "explos": 0.0, "tex": "flame", "add": true,
		"dir": Vector2(0, -1), "spread": 10.0, "v": Vector2(30, 90), "gravity": Vector2(0, -60), "damp": Vector2(0, 30),
		"scale": Vector2(1.0, 2.0), "colors": [Color(1, 1, 0.75, 1), Color(1, 0.6, 0.15, 0.9), Color(0.8, 0.15, 0.05, 0.0)], "radius": 3.0},
	"smoke_burst": {"amount": 40, "life": 1.6, "one_shot": true, "explos": 0.85, "tex": "smokebig", "add": false,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(80, 320), "gravity": Vector2(0, -30), "damp": Vector2(150, 250),
		"scale": Vector2(1.5, 3.5), "colors": [Color(0.78, 0.8, 0.84, 0.95), Color(0.55, 0.57, 0.62, 0.85), Color(0.36, 0.37, 0.41, 0.55), Color(0.22, 0.22, 0.25, 0.0)], "radius": 40.0},
	"smoke_cloud": {"amount": 36, "life": 3.2, "one_shot": false, "explos": 0.0, "tex": "smokebig", "add": false,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(5, 40), "gravity": Vector2(0, -8), "damp": Vector2(0, 10),
		"scale": Vector2(2.5, 5.0), "colors": [Color(0.58, 0.6, 0.65, 0.0), Color(0.58, 0.6, 0.65, 0.75), Color(0.46, 0.47, 0.52, 0.6), Color(0.3, 0.3, 0.33, 0.0)], "radius": 150.0},
	"trail_smoke": {"amount": 14, "life": 0.8, "one_shot": false, "explos": 0.0, "tex": "smoke", "add": false,
		"dir": Vector2(0, -1), "spread": 60.0, "v": Vector2(10, 40), "gravity": Vector2(0, -40), "damp": Vector2(0, 10),
		"scale": Vector2(1.0, 2.2), "colors": [Color(0.8, 0.82, 0.86, 0.8), Color(0.55, 0.56, 0.6, 0.5), Color(0.35, 0.35, 0.38, 0.0)], "radius": 3.0},
	"rain": {"amount": 500, "life": 0.9, "one_shot": false, "explos": 0.0, "tex": "streak", "add": false, "align": true,
		"dir": Vector2(0.22, 1), "spread": 3.0, "v": Vector2(1300, 1700), "gravity": Vector2.ZERO, "damp": Vector2.ZERO,
		"scale": Vector2(1.0, 2.0), "colors": [Color(0.7, 0.8, 1.0, 0.0), Color(0.7, 0.8, 1.0, 0.5), Color(0.7, 0.8, 1.0, 0.35)], "box": Vector2(1150, 10)},
	"rain_splash": {"amount": 90, "life": 0.25, "one_shot": false, "explos": 0.0, "tex": "px", "add": false,
		"dir": Vector2(0, -1), "spread": 60.0, "v": Vector2(40, 130), "gravity": Vector2(0, 500), "damp": Vector2.ZERO,
		"scale": Vector2(0.5, 1.0), "colors": [Color(0.75, 0.85, 1.0, 0.7), Color(0.75, 0.85, 1.0, 0.0)], "box": Vector2(900, 2)},
	"hurt_spark": {"amount": 18, "life": 0.3, "one_shot": true, "explos": 1.0, "tex": "spark", "add": true,
		"dir": Vector2(0, -1), "spread": 180.0, "v": Vector2(200, 480), "gravity": Vector2(0, 900), "damp": Vector2(200, 300),
		"scale": Vector2(1.0, 2.0), "colors": [Color(1, 1, 1, 1), Color(1, 0.85, 0.3, 1), Color(1, 0.5, 0.1, 0.0)], "radius": 8.0},
	"ledge_dust": {"amount": 8, "life": 0.35, "one_shot": true, "explos": 1.0, "tex": "px", "add": false,
		"dir": Vector2(0, 1), "spread": 50.0, "v": Vector2(30, 90), "gravity": Vector2(0, 300), "damp": Vector2(50, 100),
		"scale": Vector2(0.8, 1.6), "colors": [Color(0.8, 0.78, 0.72, 0.9), Color(0.5, 0.5, 0.55, 0.0)], "box": Vector2(12, 2)},
	"ambient_embers": {"amount": 40, "life": 6.0, "one_shot": false, "explos": 0.0, "tex": "px", "add": true,
		"dir": Vector2(0.3, -1), "spread": 30.0, "v": Vector2(20, 70), "gravity": Vector2(0, -5), "damp": Vector2.ZERO,
		"scale": Vector2(0.4, 0.9), "colors": [Color(1, 0.7, 0.3, 0.0), Color(1, 0.7, 0.3, 0.9), Color(1, 0.4, 0.2, 0.0)], "box": Vector2(960, 20)},
	"ambient_motes": {"amount": 50, "life": 8.0, "one_shot": false, "explos": 0.0, "tex": "px", "add": false,
		"dir": Vector2(1, 0), "spread": 180.0, "v": Vector2(5, 25), "gravity": Vector2.ZERO, "damp": Vector2.ZERO,
		"scale": Vector2(0.4, 0.8), "colors": [Color(0.7, 0.85, 1.0, 0.0), Color(0.7, 0.85, 1.0, 0.5), Color(0.7, 0.85, 1.0, 0.0)], "box": Vector2(960, 540)},
}

static func make(kind: String, cpu: bool, mult: float = 1.0) -> Node2D:
	var s: Dictionary = SPEC[kind]
	var g := GPUParticles2D.new()
	g.amount = maxi(1, int(s["amount"] * mult))
	g.lifetime = s["life"]
	g.one_shot = s["one_shot"]
	g.explosiveness = s["explos"]
	g.randomness = 0.3
	g.texture = TEX[s["tex"]]
	g.emitting = not s["one_shot"]
	g.local_coords = false
	g.visibility_rect = Rect2(-1200, -1200, 2400, 2400)
	var cm := ShaderMaterial.new()
	cm.shader = ADD if s["add"] else MIX
	g.material = cm
	var m := ParticleProcessMaterial.new()
	m.particle_flag_disable_z = true
	m.particle_flag_align_y = s.get("align", false)
	var d: Vector2 = s["dir"]
	m.direction = Vector3(d.x, d.y, 0.0)
	m.spread = s["spread"]
	m.initial_velocity_min = s["v"].x
	m.initial_velocity_max = s["v"].y
	m.gravity = Vector3(s["gravity"].x, s["gravity"].y, 0.0)
	m.damping_min = s["damp"].x
	m.damping_max = s["damp"].y
	m.scale_min = s["scale"].x
	m.scale_max = s["scale"].y
	var grad := Gradient.new()
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	var cols: Array = s["colors"]
	var offs := PackedFloat32Array()
	for i in cols.size():
		offs.append(float(i) / cols.size())
	grad.offsets = offs
	grad.colors = PackedColorArray(cols)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	gt.width = 32
	m.color_ramp = gt
	if s.has("box"):
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		m.emission_box_extents = Vector3(s["box"].x, s["box"].y, 1.0)
	else:
		m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		m.emission_sphere_radius = s["radius"]
	g.process_material = m
	if not cpu:
		return g
	var c := CPUParticles2D.new()
	c.convert_from_particles(g)
	c.material = cm
	c.emitting = g.emitting
	g.free()
	return c

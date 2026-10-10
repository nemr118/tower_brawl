# The arena as the phone draws it, inside the render SubViewport. Layers:
# 0 the lit world (background, tiles, torches, back fog, fighters, dust and
# smoke, lights), 1 threats (arrows, miasma clouds, the purple walls, the 3D
# fighters: never darkened), 2 glow (added fire, sparks, flashes, front fog, shafts, rain,
# lightning, spirit lights), 3 the post shader. set_tier() switches what a
# ladder tier asks for, set_variant() a split-test step (one part on or off),
# set_level() turns the limit test's dial, render() draws.
extends Node2D

const P = preload("res://sim/proto.gd")
const LevelScript = preload("res://sim/level.gd")
const FX = preload("res://client/fx.gd")
const F3D = preload("res://client/fighter3d.gd")
const TEAM := [Color("e8413c"), Color("3c8ce8"), Color("5fd35a"), Color("f2c230"),
	Color("a85ae8"), Color("f08a2c"), Color("35d6d0"), Color("f06aa8")]
const FIGHTER_TEX := [preload("res://assets/fighter_p0.png"), preload("res://assets/fighter_p1.png"),
	preload("res://assets/fighter_p2.png"), preload("res://assets/fighter_p3.png"), preload("res://assets/fighter_p4.png"),
	preload("res://assets/fighter_p5.png"), preload("res://assets/fighter_p6.png"), preload("res://assets/fighter_p7.png")]
const FIGHTER_N := preload("res://assets/fighter_n.png")
const TILES := preload("res://assets/tiles.png")
const TILES_N := preload("res://assets/tiles_n.png")
const BG_FAR := preload("res://assets/bg_far.png")
const BG_MID := preload("res://assets/bg_mid.png")
const ARROWS := preload("res://assets/fx_arrows.png")
const TORCH := preload("res://assets/fx_torch.png")
const NOISE := preload("res://assets/fx_noise.png")
const HALO := preload("res://assets/fx_halo.png")
const LIGHT := preload("res://assets/fx_light.png")
const PX := preload("res://assets/fx_px.png")
const SH_FIGHTER := preload("res://shaders/fighter.gdshader")
const SH_FOG := preload("res://shaders/fog_dynamic.gdshader")
const SH_SHAFT := preload("res://shaders/shaft.gdshader")
const SH_MIASMA := preload("res://shaders/miasma.gdshader")
const SH_WALLS := preload("res://shaders/walls.gdshader")
const SH_POST := preload("res://shaders/post.gdshader")
const SH_WISP := preload("res://shaders/wisp.gdshader")
const TRAIL := {0: "trail_plain", 1: "trail_fire", 2: "trail_fuse", 3: "trail_miasma", 4: "trail_smoke"}
# fog layers: density, ground, scale, wind, tint, pixel
const FOG_LAYERS := [
	[0.5, 0.35, 1.0, Vector2(0.010, 0.002), Color(0.40, 0.50, 0.66, 0.65), 6.0],
	[0.12, 0.55, 1.6, Vector2(-0.016, 0.001), Color(0.50, 0.60, 0.75, 0.55), 8.0],
	[0.25, 0.2, 0.6, Vector2(0.02, -0.004), Color(0.36, 0.45, 0.62, 0.5), 10.0],
	[0.2, 0.3, 2.4, Vector2(-0.03, 0.006), Color(0.45, 0.5, 0.7, 0.45), 4.0],
	[0.3, 0.8, 1.2, Vector2(0.006, 0.0), Color(0.5, 0.55, 0.7, 0.5), 6.0],
]
const MAX_WISPS := 40
# The split test (2026-09-14): a step is a tier with some parts changed.
# lights_draw: "all", "base" (only T1's 4 torches are drawn) or "none". A light
# that is not drawn is hidden but stays enabled, so the fog still gets it.
const VARIANTS := {
	"t1": [1, {}, "T1"],
	"t1.particles": [1, {"particles": true}, "T1 +particles"],
	"t1.fog": [1, {"fog": 1, "torch_lights": 8, "dyn_lights": true, "lights_draw": "base"}, "T1 +fog"],
	"t1.fogplain": [1, {"fog": 1, "fog_loops": false}, "T1 +fog plain"],
	"t1.shafts": [1, {"shafts": true}, "T1 +shafts"],
	"t1.lights": [1, {"torch_lights": 8, "dyn_lights": true}, "T1 +T2 lights"],
	"t2": [2, {}, "T2"],
	"l4": [1, {}, "lights 4"],
	"l8": [1, {"torch_lights": 8}, "lights 8"],
	"l16": [1, {"torch_lights": 8, "grid_lights": 8}, "lights 16"],
	"l24": [1, {"torch_lights": 8, "grid_lights": 16}, "lights 24"],
	"l32": [1, {"torch_lights": 8, "grid_lights": 24}, "lights 32"],
	"t3": [3, {}, "T3"],
	"t3-fog1": [3, {"fog": 1}, "T3 1 fog layer"],
	"t3-fog": [3, {"fog": 0}, "T3 -fog"],
	"t3-lights": [3, {"lights_draw": "none"}, "T3 -lights"],
	"t3-particles": [3, {"particles": false}, "T3 -particles"],
	"t3-post": [3, {"post": false}, "T3 -post"],
}
const GRID_LIGHTS := 24

var level
var tier := -1
var parts := {}
var grid_lights: Array = []
var fog_nl := 0              # lights the fog got on its last update
var boost := 1.0
var fx
var f3d
var f3d_ok := false
var cam := Camera2D.new()
var dark := CanvasModulate.new()
var dark_base := Color(0.36, 0.36, 0.5)
var threat_layer := CanvasLayer.new()
var glow_layer := CanvasLayer.new()
var post_layer := CanvasLayer.new()
var threats := Node2D.new()
var glow := Node2D.new()
var post := ColorRect.new()
var tiles_plain := TileMapLayer.new()
var tiles_lit := TileMapLayer.new()
var bg_far := Sprite2D.new()
var bg_mid := Sprite2D.new()
var fogs: Array = []
var fog_on := 0
var shafts: Array = []
var ambient: Array = []
var torches: Array = []      # [sprite, light, flame, halo]
var extra_lights: Array = []
var wisps: Array = []        # [sprite, light, phase, base]
var wisp_on := 0
var rain: Node2D
var splash: Node2D
var bolt := Line2D.new()
var storm := false
var storm_t := 4.0
var flash := 0.0
var bloom_on := false
var distort_on := false
var copies := 1
var fighters: Array = []     # [sprite, material, plain tex, lit tex, ghost timer, ground tick when dead]
var aim_pointer := Line2D.new()
var walls_l := Sprite2D.new()   # the purple walls, left and right (a 4 px square scaled to the width)
var walls_r := Sprite2D.new()
var arrows := {}             # id -> [sprite, trail node, trail kind, light]
var zones := {}              # key -> [kind, nodes...]
var zone_seen := {}
var time := 0.0
var shake_on := false
var add_mat := CanvasItemMaterial.new()
var fighter_count := 0
var _light_free: Array = []
var _dist := PackedVector4Array()
var _vel := PackedVector4Array()
var _lights := PackedVector4Array()
var _lcol := PackedVector4Array()
var _smoke := PackedVector4Array()
var _shock := PackedVector4Array()
var _heat := PackedVector4Array()

func setup(render_size: Vector2i, cpu: bool, amount_boost: float = 1.0) -> void:
	level = LevelScript.new()
	boost = amount_boost
	for arr in [[_dist, 32], [_vel, 32], [_lights, 32], [_lcol, 32], [_smoke, 16], [_shock, 8], [_heat, 16]]:
		arr[0].resize(arr[1])
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add_mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	cam.position = Vector2(960, 540)
	cam.zoom = Vector2.ONE * (render_size.y / 1080.0)
	add_child(cam)
	cam.make_current()
	dark.color = dark_base
	add_child(dark)
	for layer in [[threat_layer, 1, threats], [glow_layer, 2, glow]]:
		layer[0].layer = layer[1]
		layer[0].follow_viewport_enabled = true
		add_child(layer[0])
		layer[0].add_child(layer[2])
	post_layer.layer = 3
	add_child(post_layer)
	post.size = Vector2(render_size)
	var pm := ShaderMaterial.new()
	pm.shader = SH_POST
	pm.set_shader_parameter("size", Vector2(render_size))
	post.material = pm
	post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_layer.add_child(post)
	bg_far.texture = BG_FAR
	bg_far.scale = Vector2(4, 4)
	bg_far.position = Vector2(960, 540)
	add_child(bg_far)
	bg_mid.texture = BG_MID
	bg_mid.scale = Vector2(2, 2)
	bg_mid.position = Vector2(960, 560)
	bg_mid.modulate = Color(1, 1, 1, 0.9)
	add_child(bg_mid)
	for i in 3:
		var sh := Polygon2D.new()
		var x := 420.0 + i * 540.0
		sh.polygon = PackedVector2Array([Vector2(x - 40, 60), Vector2(x + 40, 60), Vector2(x + 190, 900), Vector2(x - 110, 900)])
		sh.uv = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		var m := ShaderMaterial.new()
		m.shader = SH_SHAFT
		m.set_shader_parameter("phase", i * 2.1)
		sh.material = m
		glow.add_child(sh)
		shafts.append(sh)
	_build_tiles(tiles_plain, TILES)
	var ct := CanvasTexture.new()
	ct.diffuse_texture = TILES
	ct.normal_texture = TILES_N
	_build_tiles(tiles_lit, ct)
	add_child(tiles_plain)
	add_child(tiles_lit)
	fx = FX.new()
	glow.add_child(fx)
	var fx_lit := Node2D.new()
	add_child(fx_lit)
	fx.setup(fx_lit, glow, TEAM, cpu, boost)
	for i in level.torches.size():
		var p: Vector2 = level.torches[i]
		var s := Sprite2D.new()
		s.texture = TORCH
		s.scale = Vector2(3, 3)
		s.position = p
		add_child(s)
		var l := PointLight2D.new()
		l.texture = LIGHT
		l.color = Color(1.0, 0.62, 0.3)
		l.texture_scale = 2.6
		l.height = 80.0
		l.position = p + Vector2(0, -30)
		l.set_meta("base", i < 4)
		add_child(l)
		var flame: Node2D = fx.take_loop("torch")
		flame.position = p + Vector2(0, -34)
		var halo := Sprite2D.new()
		halo.texture = HALO
		halo.material = add_mat
		halo.modulate = Color(1, 0.55, 0.2, 0.55)
		halo.scale = Vector2(2.2, 2.2)
		halo.position = p + Vector2(0, -32)
		glow.add_child(halo)
		torches.append([s, l, flame, halo])
	for i in 8:
		var l := PointLight2D.new()
		l.texture = LIGHT
		l.color = TEAM[i]
		l.texture_scale = 1.8
		l.height = 60.0
		l.position = Vector2(240 + i * 206, 300 + (i % 3) * 250)
		add_child(l)
		extra_lights.append(l)
	# the split test's lights: torch-sized, on a 6 x 4 grid, taken in a stride of 7 so any first N spread out
	for k in GRID_LIGHTS:
		var j := (k * 7) % GRID_LIGHTS
		var l := PointLight2D.new()
		l.texture = LIGHT
		l.color = Color(1.0, 0.62, 0.3)
		l.texture_scale = 2.6
		l.height = 80.0
		l.position = Vector2(160 + (j % 6) * 320, 135 + (j / 6) * 270)
		l.enabled = false
		add_child(l)
		grid_lights.append(l)
	var e1: Node2D = fx.take_loop("ambient_embers")
	e1.position = Vector2(960, 1090)
	var e2: Node2D = fx.take_loop("ambient_motes")
	e2.position = Vector2(960, 540)
	ambient = [e1, e2]
	for i in FOG_LAYERS.size():
		var spec: Array = FOG_LAYERS[i]
		var r := ColorRect.new()
		r.size = Vector2(1920, 1080)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = SH_FOG
		m.set_shader_parameter("noise", NOISE)
		m.set_shader_parameter("density", spec[0])
		m.set_shader_parameter("ground", spec[1])
		m.set_shader_parameter("scale", spec[2])
		m.set_shader_parameter("wind", spec[3])
		m.set_shader_parameter("tint", spec[4])
		m.set_shader_parameter("pixel", spec[5])
		r.material = m
		r.visible = false
		if i == 0:
			add_child(r)
		else:
			glow.add_child(r)
		fogs.append(r)
	for i in 32:
		var s := Sprite2D.new()
		s.region_enabled = true
		s.offset = Vector2(0, -58)
		var m := ShaderMaterial.new()
		m.shader = SH_FIGHTER
		var lit_tex := CanvasTexture.new()
		lit_tex.diffuse_texture = FIGHTER_TEX[i % 8]
		lit_tex.normal_texture = FIGHTER_N
		add_child(s)
		fighters.append([s, m, FIGHTER_TEX[i % 8], lit_tex, 0.0, -1])
	rain = fx.take_loop("rain")
	rain.position = Vector2(860, -60)
	splash = fx.take_loop("rain_splash")
	splash.position = Vector2(960, 1018)
	for i in MAX_WISPS:
		var sp := Sprite2D.new()
		sp.texture = PX
		sp.scale = Vector2(12, 12)
		var wm := ShaderMaterial.new()
		wm.shader = SH_WISP
		wm.set_shader_parameter("phase", i * 1.7)
		sp.material = wm
		var c: Color = [Color(0.5, 0.85, 1.0), Color(0.75, 0.55, 1.0), Color(0.6, 1.0, 0.7), Color(1.0, 0.8, 0.5)][i % 4]
		sp.modulate = c
		var base := Vector2(120 + (i * 377) % 1680, 90 + (i * 211) % 880)
		sp.position = base
		glow.add_child(sp)
		var wl := PointLight2D.new()
		wl.texture = LIGHT
		wl.color = c
		wl.energy = 0.9
		wl.texture_scale = 1.3
		wl.height = 50.0
		wl.position = base
		add_child(wl)
		wisps.append([sp, wl, i * 1.7, base])
	bolt.width = 6.0
	bolt.default_color = Color(0.85, 0.9, 1.0, 1.0)
	bolt.material = add_mat
	bolt.visible = false
	glow.add_child(bolt)
	f3d = F3D.new()
	threats.add_child(f3d)
	f3d_ok = f3d.setup(render_size, TEAM)
	aim_pointer.width = 4.0
	aim_pointer.default_color = Color(1.0, 0.95, 0.6, 0.85)
	aim_pointer.visible = false
	threats.add_child(aim_pointer)
	for i in 2:
		var wall: Sprite2D = [walls_l, walls_r][i]
		wall.texture = PX
		wall.centered = false
		wall.visible = false
		var wm := ShaderMaterial.new()
		wm.shader = SH_WALLS
		wm.set_shader_parameter("noise", NOISE)
		wm.set_shader_parameter("side", float(i))
		wall.material = wm
		threats.add_child(wall)
	fx.prewarm(Vector2(960, 1200))

# Your own aim while you hold shoot: a short line from the bow (the game client).
func show_aim(pos: Vector2, ang: float, on: bool) -> void:
	aim_pointer.visible = on
	if on:
		var d := Vector2.from_angle(ang)
		aim_pointer.points = PackedVector2Array([pos + d * 34.0, pos + d * 110.0])

func _build_tiles(layer: TileMapLayer, tex: Texture2D) -> void:
	var ts := TileSet.new()
	ts.tile_size = Vector2i(30, 30)
	var src := TileSetAtlasSource.new()
	src.texture = tex
	src.texture_region_size = Vector2i(30, 30)
	for y in 3:
		for x in 4:
			src.create_tile(Vector2i(x, y))
	ts.add_source(src, 0)
	layer.tile_set = ts
	for cy in level.ROWS:
		for cx in level.COLS:
			var c: int = level.cell(cx, cy)
			if c == 0:
				continue
			var h: int = (cx * 7 + cy * 13) % 4
			if c == 2:
				layer.set_cell(Vector2i(cx, cy), 0, Vector2i(h, 2))
			elif level.cell(cx, cy - 1) != 1:
				layer.set_cell(Vector2i(cx, cy), 0, Vector2i(h, 1))
			else:
				layer.set_cell(Vector2i(cx, cy), 0, Vector2i(h, 0))

# 0 plain sprites; 1 + normal maps, 4 lights; 2 + particles, 8+ lights, back
# fog, shafts, embers; 3 + fighter shader, post, shake, front fog; 4 = 3 with
# 3D fighters; 5 = 3 with 16 fighters; 6 max: everything, boosted, 3 fog layers,
# rain, lightning, spirit lights, bloom, shock ripples, heat; 7 = 6 + the dial.
func set_tier(t: int) -> bool:
	return apply_parts(parts_for_tier(t))

# A split-test step by name (VARIANTS). False for an unknown name.
func set_variant(id: String) -> bool:
	if not VARIANTS.has(id):
		return false
	var p := parts_for_tier(VARIANTS[id][0])
	p.merge(VARIANTS[id][1], true)
	p["variant"] = id
	return apply_parts(p)

static func variant_label(id: String) -> String:
	return VARIANTS[id][2] if VARIANTS.has(id) else id

static func parts_for_tier(t: int) -> Dictionary:
	return {"tier": t, "lit": t >= 1, "torch_lights": 0 if t < 1 else (4 if t < 2 else 8), "grid_lights": 0,
		"dyn_lights": t >= 2, "particles": t >= 2, "fog": 3 if t >= 6 else (2 if t >= 3 else (1 if t >= 2 else 0)),
		"fog_loops": true, "shafts": t >= 2, "lights_draw": "all", "fighter_shader": t >= 3, "post": t >= 3,
		"shake": t >= 3}

func apply_parts(p: Dictionary) -> bool:
	var t: int = p["tier"]
	if t == 4 and not f3d_ok:
		return false
	tier = t
	parts = p
	var lights_on: bool = p["lit"]
	var fx_on: bool = p["particles"]
	var max_on := t >= 6
	dark.visible = lights_on
	tiles_plain.visible = not lights_on
	tiles_lit.visible = lights_on
	for i in torches.size():
		torches[i][1].enabled = i < int(p["torch_lights"])
		torches[i][2].visible = fx_on
		torches[i][2].emitting = fx_on
		torches[i][3].visible = fx_on
	for i in grid_lights.size():
		grid_lights[i].enabled = i < int(p["grid_lights"])
	for l in extra_lights:
		l.enabled = t == 5
	for n in shafts:
		n.visible = p["shafts"]
	for a in ambient:
		a.visible = fx_on
		a.emitting = fx_on
	_set_fog_layers(int(p["fog"]))
	fog_nl = 0
	rain.visible = max_on
	rain.emitting = max_on
	splash.visible = max_on
	splash.emitting = max_on
	_set_wisps(16 if max_on else 0)
	storm = max_on
	bloom_on = max_on
	distort_on = max_on
	post.visible = p["post"]
	post.material.set_shader_parameter("bloom", 1.0 if max_on else 0.0)
	shake_on = p["shake"]
	copies = 2 if t == 5 else 1
	fx.set_tier(fx_on, p["dyn_lights"])
	fx.set_ratio(0.6 if max_on else 1.0)
	for f in fighters:
		f[0].texture = f[3] if lights_on else f[2]
		f[0].material = f[1] if p["fighter_shader"] else null
		f[0].modulate = Color.WHITE
	f3d.set_active(t == 4)
	_clear_dynamic()
	for group in [get_children(), fx.lit.get_children()]:
		for c in group:
			if c is PointLight2D:
				_show_light(c)
	return true

# Draw this light or only feed it to the fog (lights_draw, see VARIANTS).
func _show_light(l: PointLight2D) -> void:
	var mode: String = parts.get("lights_draw", "all")
	l.visible = mode == "all" or (mode == "base" and l.get_meta("base", false))

# The limit test (T7), level 1..10: more particles, fog layers, spirit lights
# and fighters with every level. Returns what this level draws.
func set_level(lv: int) -> Dictionary:
	fx.set_ratio(0.6 + 0.04 * lv)
	_set_fog_layers(mini(5, 2 + lv / 3 + 1))
	_set_wisps(mini(MAX_WISPS, 8 + lv * 3))
	copies = mini(4, 1 + lv / 3)
	return {"particles": fx.ratio * boost, "fog_layers": fog_on, "wisps": wisp_on, "copies": copies}

func _set_fog_layers(n: int) -> void:
	fog_on = n
	for i in fogs.size():
		fogs[i].visible = i < n

func _set_wisps(n: int) -> void:
	wisp_on = n
	for i in wisps.size():
		wisps[i][0].visible = i < n
		wisps[i][1].enabled = i < n

func _clear_dynamic() -> void:
	for id in arrows.keys():
		_free_arrow(id)
	for key in zones.keys():
		_free_zone(key)

func render(s: Dictionary, delta: float) -> void:
	time += delta
	if s.is_empty():
		return
	if copies > 1:
		s = _copied(s, copies)
	var fl: Array = s["fighters"]
	fighter_count = mini(fl.size(), fighters.size())
	if tier == 4:
		f3d.update(fl)
	# The game: slot = seat, so a fighter keeps its colour whatever seats are
	# taken. The benchmark's copies (T5, T7) repeat the seats, so they go by index.
	var by_seat := copies == 1
	for i in fighters.size():
		var slot: Array = fighters[i]
		var spr: Sprite2D = slot[0]
		var f: Dictionary = {}
		if not by_seat:
			if i < fl.size():
				f = fl[i]
		else:
			for cand in fl:
				if int(cand["id"]) == i:
					f = cand
					break
		if f.is_empty() or tier == 4:
			spr.visible = false
			continue
		spr.visible = true
		spr.position = Vector2(f["x"] + 18.0, f["y"] + 63.0)
		spr.flip_h = (f["flags"] & 1) == 0
		var frame := _frame(f, slot, i)
		spr.region_rect = Rect2((frame % 16) * 128, (frame / 16) * 128, 128, 128)
		var burn := 1.0 if (f["flags"] & 8) != 0 else 0.0
		var poison := 1.0 if (f["flags"] & 16) != 0 else 0.0
		if parts["fighter_shader"]:
			slot[1].set_shader_parameter("burn", burn)
			slot[1].set_shader_parameter("poison", poison)
			var hit_flash: bool = (f["state"] == P.F_HURT or f["state"] == P.F_DEAD) and f["st"] < 4
			slot[1].set_shader_parameter("flash", 1.0 if hit_flash or (f["state"] == P.F_DODGE and f["st"] < 2) else 0.0)
		else:
			spr.modulate = Color(1, 0.75, 0.55) if burn > 0.0 else (Color(0.85, 0.7, 1.0) if poison > 0.0 else Color.WHITE)
		if parts["particles"] and f["state"] == P.F_DODGE:
			slot[4] -= delta
			if slot[4] <= 0.0:
				slot[4] = 0.035
				fx.ghost(FIGHTER_TEX[i % 8], spr.region_rect, spr.position + Vector2(0, -58), spr.flip_h, TEAM[i % 8])
	_render_arrows(s["arrows"])
	_render_zones(s["zones"])
	_render_walls(s)
	for t in torches:
		if t[1].enabled:
			t[1].energy = 1.1 + 0.18 * sin(time * 17.0 + t[0].position.x) + 0.1 * sin(time * 7.3)
	for l in grid_lights:
		if l.enabled:
			l.energy = 1.1 + 0.18 * sin(time * 17.0 + l.position.x) + 0.1 * sin(time * 7.3 + l.position.y)
	for i in wisp_on:
		var w: Array = wisps[i]
		var p: Vector2 = w[3] + Vector2(sin(time * 0.4 + w[2]) * 90.0, cos(time * 0.31 + w[2] * 1.3) * 50.0)
		w[0].position = p
		w[1].position = p
	if tier >= 2:
		bg_mid.position.x = 960.0 + sin(time * 0.07) * 14.0
		bg_far.position.x = 960.0 + sin(time * 0.05) * 5.0
	_update_storm(delta)
	if shake_on and fx.shake > 0.0:
		cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * fx.shake
	else:
		cam.offset = Vector2.ZERO
	if fog_on > 0:
		_update_fog(s)
	if post.visible:
		_update_post(s)

func _frame(f: Dictionary, slot: Array, i: int) -> int:
	var st: int = f["st"]
	var flags: int = f["flags"]
	var ground := (flags & 2) != 0
	if f["state"] != P.F_DEAD:
		slot[5] = -1
	if f["state"] == P.F_DEAD:
		if not ground or st < 4:
			return 22 if st < 6 else (23 if st < 14 else 24)
		if slot[5] < 0:
			slot[5] = st
		return 25 if st - slot[5] < 6 else 26
	if f["state"] == P.F_HURT:
		return 11 if st < 6 else 12
	if f["state"] == P.F_LEDGE:
		return 21 if (flags & 32) != 0 else 20
	if f["state"] == P.F_DODGE:
		return 14 + (st / 3) % 4 if (flags & 32) != 0 else 13
	if (flags & 64) != 0:
		return 19
	if not ground:
		if (flags & 4) != 0:
			return 18
		return 8 if f["vy"] < 0 else 9
	if st < 8 and f["vx"] == 0 and f["vy"] == 0:
		return 27
	if absi(f["vx"]) >= 2:
		return 2 + (int(time * 12.0) + i) % 6
	return int(time * 2.0 + i * 0.3) % 2

func _copied(s: Dictionary, n: int) -> Dictionary:
	var fl: Array = s["fighters"].duplicate()
	var ar: Dictionary = s["arrows"].duplicate()
	var zl: Array = s["zones"].duplicate()
	for c in range(1, n):
		var ox := 1920.0 * c / n
		var oy := 270.0 * c
		for f in s["fighters"]:
			var d: Dictionary = f.duplicate()
			d["x"] = fposmod(d["x"] + ox, 1920.0)
			d["y"] = fposmod(d["y"] + oy, 1080.0)
			fl.append(d)
		for id in s["arrows"]:
			var d: Dictionary = s["arrows"][id].duplicate()
			d["x"] = fposmod(d["x"] + ox, 1920.0)
			d["y"] = fposmod(d["y"] + oy, 1080.0)
			ar[id + 100000 * c] = d
		for z in s["zones"]:
			var d: Dictionary = z.duplicate()
			d["x"] = fposmod(d["x"] + ox, 1920.0)
			zl.append(d)
	return {"fighters": fl, "arrows": ar, "zones": zl}

func _update_storm(delta: float) -> void:
	flash = maxf(0.0, flash - delta * 4.0)
	if storm:
		storm_t -= delta
		if storm_t <= 0.0:
			storm_t = randf_range(4.0, 8.0)
			flash = 1.0
			var x := randf_range(200.0, 1720.0)
			var pts := PackedVector2Array([Vector2(x, 0)])
			var y := 0.0
			var bx := x
			while y < 900.0:
				y += randf_range(60.0, 130.0)
				bx += randf_range(-70.0, 70.0)
				pts.append(Vector2(bx, y))
			bolt.points = pts
			bolt.visible = true
			fx.light_burst(Vector2(bx, y), Color(0.7, 0.8, 1.0), 3.0, 5.0, 0.35)
			fx.shake = maxf(fx.shake, 8.0)
		if storm_t < 0.1 or storm_t > 3.9:
			flash = maxf(flash, 0.6)
	bolt.visible = flash > 0.3 and storm
	bolt.modulate.a = flash
	dark.color = dark_base.lerp(Color(0.95, 1.0, 1.25), flash * 0.8) if storm else dark_base

func _update_fog(s: Dictionary) -> void:
	var nd := 0
	for f in s["fighters"]:
		if nd >= 32:
			break
		if f["state"] == P.F_DEAD:
			continue
		_dist[nd] = Vector4(f["x"] + 18.0, f["y"] + 31.0, 95.0, 0.9)
		_vel[nd] = Vector4(f["vx"], f["vy"], 0.0, 0.0)
		nd += 1
	for id in s["arrows"]:
		if nd >= 32:
			break
		var a: Dictionary = s["arrows"][id]
		if a["state"] != P.S_FLY:
			continue
		_dist[nd] = Vector4(a["x"], a["y"], 45.0, 0.5)
		_vel[nd] = Vector4(cos(a["ang"]) * 18.0, sin(a["ang"]) * 18.0, 0.0, 0.0)
		nd += 1
	for r in fx.rings:
		if nd >= 32:
			break
		var k: float = r[1] / r[4]
		_dist[nd] = Vector4(r[0].x, r[0].y, r[2] * (0.25 + 0.75 * k) + 40.0, 1.0 - k * 0.5)
		_vel[nd] = Vector4.ZERO
		nd += 1
	var nl := 0
	for group in [get_children(), fx.lit.get_children()]:
		for c in group:
			if nl >= 32:
				break
			if c is PointLight2D and c.enabled:
				_lights[nl] = Vector4(c.position.x, c.position.y, c.texture_scale * 120.0, c.energy * 0.28)
				_lcol[nl] = Vector4(c.color.r, c.color.g, c.color.b, 1.0)
				nl += 1
	var ns := 0
	for z in s["zones"]:
		if ns >= 16:
			break
		if z["kind"] == P.Z_SMOKE:
			_smoke[ns] = Vector4(z["x"], z["y"], z["size"] * 1.15, 0.95 * clampf(z["life"] * 3.0, 0.0, 1.0))
			ns += 1
	if not parts.get("fog_loops", true):
		# plain fog (split test): the same layer without its stir, light and smoke loops
		nd = 0
		nl = 0
		ns = 0
	fog_nl = nl
	for i in fog_on:
		var m: ShaderMaterial = fogs[i].material
		m.set_shader_parameter("n_dist", nd)
		m.set_shader_parameter("dist", _dist)
		m.set_shader_parameter("dist_vel", _vel)
		m.set_shader_parameter("n_lights", nl)
		m.set_shader_parameter("lights", _lights)
		m.set_shader_parameter("light_col", _lcol)
		m.set_shader_parameter("n_smoke", ns)
		m.set_shader_parameter("smoke", _smoke)
		m.set_shader_parameter("flash", flash if storm else 0.0)

func _update_post(s: Dictionary) -> void:
	var m: ShaderMaterial = post.material
	m.set_shader_parameter("aberration", fx.aberration)
	m.set_shader_parameter("flash", flash if storm else 0.0)
	if not distort_on:
		m.set_shader_parameter("n_shock", 0)
		m.set_shader_parameter("n_heat", 0)
		return
	var sc := Vector2(post.size) / Vector2(1920.0, 1080.0)
	var ns := 0
	for r in fx.rings:
		if ns >= 8:
			break
		var k: float = r[1] / r[4]
		_shock[ns] = Vector4(r[0].x * sc.x, r[0].y * sc.y, r[2] * (0.25 + 0.75 * k) * sc.y, 1.0 - k)
		ns += 1
	var nh := 0
	for z in s["zones"]:
		if nh >= 16:
			break
		if z["kind"] == P.Z_FIRE:
			_heat[nh] = Vector4(z["x"] * sc.x, z["y"] * sc.y, z["size"] * sc.x, clampf(z["life"] * 4.0, 0.0, 1.0))
			nh += 1
	m.set_shader_parameter("n_shock", ns)
	m.set_shader_parameter("shock", _shock)
	m.set_shader_parameter("n_heat", nh)
	m.set_shader_parameter("heat", _heat)

func _render_arrows(al: Dictionary) -> void:
	for id in arrows.keys():
		if not al.has(id):
			_free_arrow(id)
	for id in al:
		var a: Dictionary = al[id]
		var e: Array = arrows.get(id, [])
		if e.is_empty():
			var spr := Sprite2D.new()
			spr.texture = ARROWS
			spr.region_enabled = true
			spr.region_rect = Rect2(0, a["kind"] * 8, 32, 8)
			spr.offset = Vector2(-12, 0)
			threats.add_child(spr)
			e = [spr, null, "", null]
			arrows[id] = e
		var spr: Sprite2D = e[0]
		spr.position = Vector2(a["x"], a["y"])
		spr.rotation = a["ang"]
		var flying: bool = a["state"] == P.S_FLY
		if parts["particles"] and flying and e[1] == null:
			var k: String = TRAIL.get(a["kind"], "trail_plain")
			e[1] = fx.take_loop(k)
			e[2] = k
		if e[1] != null:
			if not flying:
				fx.give_loop(e[2], e[1])
				e[1] = null
			else:
				e[1].global_position = spr.position
		if parts["dyn_lights"] and a["kind"] == P.A_FIRE and e[3] == null and flying:
			e[3] = _take_light(Color(1, 0.6, 0.2), 1.2, 1.4)
		if e[3] != null:
			e[3].position = spr.position
			if not flying:
				_give_light(e[3])
				e[3] = null

func _free_arrow(id) -> void:
	var e: Array = arrows[id]
	if e[1] != null:
		fx.give_loop(e[2], e[1])
	if e[3] != null:
		_give_light(e[3])
	e[0].queue_free()
	arrows.erase(id)

func _take_light(c: Color, energy: float, sc: float) -> PointLight2D:
	var l: PointLight2D
	if _light_free.size() > 0:
		l = _light_free.pop_back()
	else:
		l = PointLight2D.new()
		l.texture = LIGHT
		l.height = 60.0
		add_child(l)
	l.color = c
	l.energy = energy
	l.texture_scale = sc
	l.enabled = true
	_show_light(l)
	return l

func _give_light(l: PointLight2D) -> void:
	l.enabled = false
	_light_free.append(l)

# The purple walls: each one walls px wide at its edge of the arena.
func _render_walls(s: Dictionary) -> void:
	var w: float = s.get("walls", 0.0)
	var on := w >= 1.0
	walls_l.visible = on
	walls_r.visible = on
	if not on:
		return
	walls_l.scale = Vector2(w, 1080.0) / 4.0
	walls_r.scale = walls_l.scale
	walls_r.position = Vector2(1920.0 - w, 0.0)
	var deadly := 1.0 if s.get("walls_deadly", false) else 0.0
	for wall in [walls_l, walls_r]:
		wall.material.set_shader_parameter("deadly", deadly)
		wall.material.set_shader_parameter("size_px", Vector2(w, 1080.0))

func _render_zones(zl: Array) -> void:
	zone_seen.clear()
	var fxp: bool = parts["particles"]
	var dl: bool = parts["dyn_lights"]
	if not (fxp or dl):
		return
	# e = [kind, flames / cloud / smoke, embers / bubbles, halo, light]: parts that are off stay null
	for z in zl:
		var key := "%d:%d:%d" % [z["kind"], int(z["x"]), int(z["y"])]
		zone_seen[key] = true
		var e: Array = zones.get(key, [])
		var pos := Vector2(z["x"], z["y"])
		if e.is_empty():
			e = [z["kind"], null, null, null, null]
			if z["kind"] == P.Z_FIRE:
				if fxp:
					var flames: Node2D = fx.take_loop("fire_ground")
					var embers: Node2D = fx.take_loop("embers")
					flames.global_position = pos
					embers.global_position = pos
					var halo := Sprite2D.new()
					halo.texture = HALO
					halo.material = add_mat
					halo.modulate = Color(1, 0.5, 0.15, 0.5)
					halo.scale = Vector2(z["size"] / 40.0, 1.6)
					halo.position = pos + Vector2(0, -10)
					glow.add_child(halo)
					e[1] = flames
					e[2] = embers
					e[3] = halo
				if dl:
					e[4] = _take_light(Color(1, 0.55, 0.2), 1.5, 2.0)
					e[4].position = pos + Vector2(0, -30)
			elif z["kind"] == P.Z_MIASMA:
				if fxp:
					var cloud := Sprite2D.new()
					cloud.texture = NOISE
					cloud.region_enabled = true
					cloud.region_rect = Rect2(0, 0, 64, 64)
					cloud.scale = Vector2.ONE * (z["size"] * 2.2 / 64.0)
					cloud.position = pos
					var m := ShaderMaterial.new()
					m.shader = SH_MIASMA
					m.set_shader_parameter("noise", NOISE)
					m.set_shader_parameter("seed", fmod(pos.x * 0.013, 1.0))
					cloud.material = m
					threats.add_child(cloud)
					var bubbles: Node2D = fx.take_loop("miasma_bubbles")
					bubbles.global_position = pos
					e[1] = cloud
					e[2] = bubbles
				if dl:
					e[4] = _take_light(Color(0.7, 0.3, 1.0), 1.2, 2.2)
					e[4].position = pos
			elif fxp:
				var smoke: Node2D = fx.take_loop("smoke_cloud")
				smoke.global_position = pos
				e[1] = smoke
			zones[key] = e
		if z["kind"] == P.Z_FIRE:
			if e[4] != null:
				e[4].energy = 1.3 + 0.3 * sin(time * 21.0 + pos.x) if z["life"] > 0.1 else 0.3
		elif z["kind"] == P.Z_MIASMA:
			if e[1] != null:
				e[1].material.set_shader_parameter("life", z["life"])
		elif e[1] != null:
			e[1].emitting = z["life"] > 0.15
	for key in zones.keys():
		if not zone_seen.has(key):
			_free_zone(key)

func _free_zone(key) -> void:
	var e: Array = zones[key]
	if e[0] == P.Z_FIRE:
		if e[1] != null:
			fx.give_loop("fire_ground", e[1])
			fx.give_loop("embers", e[2])
			e[3].queue_free()
	elif e[0] == P.Z_MIASMA:
		if e[1] != null:
			e[1].queue_free()
			fx.give_loop("miasma_bubbles", e[2])
	elif e[1] != null:
		fx.give_loop("smoke_cloud", e[1])
	if e[4] != null:
		_give_light(e[4])
	zones.erase(key)

# Lights that really draw (enabled and not hidden); light_count() also counts
# the hidden ones the fog still gets.
func lights_drawn() -> int:
	var n := 0
	for group in [get_children(), fx.lit.get_children()]:
		for c in group:
			if c is PointLight2D and c.enabled and c.visible:
				n += 1
	return n

func light_count() -> int:
	var n := 0
	for group in [get_children(), fx.lit.get_children()]:
		for c in group:
			if c is PointLight2D and c.enabled:
				n += 1
	return n

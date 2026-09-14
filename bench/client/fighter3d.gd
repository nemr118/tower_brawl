# Tier T4: the 3D prototype's archer (bench/untracked, not committed) drawn live
# for every fighter, through one transparent 3D viewport the size of the render
# target, with a toon material, the prototype's texture and its outline shader.
extends Node2D

const MODEL := "res://untracked/archer_lp1200.glb"

var vp: SubViewport
var models: Array = []
var players: Array = []
var current: Array = []

func setup(size: Vector2i, colors: Array) -> bool:
	if not ResourceLoader.exists(MODEL):
		return false
	var scene: PackedScene = load(MODEL)
	if scene == null:
		return false
	vp = SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 10.8
	cam.position = Vector3(9.6, -5.4, 30.0)
	vp.add_child(cam)
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -40, 0)
	sun.light_energy = 1.3
	vp.add_child(sun)
	var tex: Texture2D = load("res://untracked/archer_lp1200_tex.png")
	var outline := ShaderMaterial.new()
	outline.shader = load("res://untracked/outline.gdshader")
	for i in 16:
		var m: Node3D = scene.instantiate()
		vp.add_child(m)
		# A plain toon material with the prototype's texture and outline pass: the
		# same kind of GPU work as its hero shader, which drew noise here (it picks
		# its texture from the prototype's vertex colours).
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		var c: Color = colors[i % colors.size()]
		mat.albedo_color = Color(0.75 + c.r * 0.25, 0.75 + c.g * 0.25, 0.75 + c.b * 0.25)
		mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.next_pass = outline
		var height := 0.0
		for mi in m.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat
			height = maxf(height, mi.get_aabb().size.y)
		if height > 0.0:
			m.scale = Vector3.ONE * (0.9 / height)
		var aps := m.find_children("*", "AnimationPlayer", true, false)
		players.append(aps[0] if aps.size() > 0 else null)
		models.append(m)
		current.append("")
	var spr := Sprite2D.new()
	spr.texture = vp.get_texture()
	spr.centered = false
	spr.scale = Vector2(1920.0 / size.x, 1080.0 / size.y)
	add_child(spr)
	visible = false
	return true

func set_active(on: bool) -> void:
	visible = on
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED

func _clip(ap: AnimationPlayer, name: String) -> String:
	if ap.has_animation(name):
		return name
	return name.replace("-loop", "")

func update(fighters: Array) -> void:
	for i in models.size():
		var m: Node3D = models[i]
		if i >= fighters.size() or (fighters[i]["state"] == 2 and fighters[i]["st"] > 70):
			m.visible = false
			continue
		var f: Dictionary = fighters[i]
		m.visible = true
		m.position = Vector3((f["x"] + 18.0) / 100.0, -(f["y"] + 63.0) / 100.0, 0.0)
		m.rotation_degrees.y = 90.0 if (f["flags"] & 1) != 0 else -90.0
		var ap: AnimationPlayer = players[i]
		if ap == null:
			continue
		var want := "idle-loop"
		if f["state"] == 2:
			want = "death"
		elif f["state"] == 1:
			want = "dash-loop"
		elif (f["flags"] & 2) == 0:
			want = "jump"
		elif absi(f["vx"]) >= 2:
			want = "run-loop"
		if want != current[i]:
			current[i] = want
			var clip := _clip(ap, want)
			if ap.has_animation(clip):
				ap.play(clip, 0.1)

extends SceneTree
## The duck probe (v0.1.4). A fighter stands on a solid floor, p1_down is held,
## and is_on_floor / is_ducking / the look timer print per physics frame. It
## found the v0.1.3 duck flicker: a collision shape change costs one floor
## frame at exact rest, so the duck went off the next frame, on again the one
## after, and the look-down never came. With DUCK_GRACE_S (player.gd) the duck
## holds and look_t climbs. Run it after touching the duck, the shapes or
## move_and_slide:
##   godot --headless --path . --script tools/duck_probe.gd -- --no-net
## Expect: duck=true on every line from f1 and look_t rising past 0.6 at f40.
var probe: Node = null

func _process(_delta: float) -> bool:
	if probe == null:
		root.get_node("Global").my_player_id = 1
		probe = Probe.new()
		root.add_child(probe)
		return false
	return probe.done

class Probe extends Node2D:
	var done := false
	var frame := 0
	var p = null
	var bad := 0

	func _ready() -> void:
		var body := StaticBody2D.new()
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(200.0, 10.0)
		cs.shape = rect
		body.position = Vector2(0.0, 100.0)
		body.collision_layer = 1
		body.add_child(cs)
		add_child(body)
		p = load("res://scenes/player.tscn").instantiate()
		p.player_id = 1
		p.position = Vector2(0.0, 80.0)
		add_child(p)

	func _physics_process(_delta: float) -> void:
		frame += 1
		if frame == 60:
			print("--- solid floor: hold p1_down (floor=", p.is_on_floor(), " y=", snappedf(p.position.y, 0.1), ")")
			Input.action_press("p1_down", 1.0)
		elif frame > 60 and frame <= 100:
			if not p.is_ducking:
				bad += 1
			if frame <= 66 or frame % 10 == 0:
				print("  f", frame - 60, " floor=", p.is_on_floor(), " duck=", p.is_ducking, " vy=", snappedf(p.velocity.y, 0.1), " y=", snappedf(p.position.y, 0.01), " look_t=", snappedf(p._look_down_t, 0.01))
		elif frame == 101:
			Input.action_release("p1_down")
			if bad == 0 and p._look_down_t > 0.6:
				print("✅ duck_probe: the duck held for 40 frames, look_t=", snappedf(p._look_down_t, 0.01))
			else:
				printerr("❌ duck_probe: the duck dropped on ", bad, " of 40 frames, look_t=", snappedf(p._look_down_t, 0.01))
			done = true

import re

with open("scripts/arena.gd", "r") as f:
    code = f.read()

# Add variables for PowerUp
vars_block = """@onready var platforms_node = $Platforms
var powerup_node: Area2D = null
var is_arena_rotating: bool = false
"""
code = code.replace("var hud_panels = {}", vars_block + "var hud_panels = {}")

# Connect signals
ready_block = """	Global.connect("net_spawn_powerup", Callable(self, "_on_net_spawn_powerup"))
	Global.connect("net_activate_powerup", Callable(self, "_on_net_activate_powerup"))
	
	if Global.my_player_id == 1:
		var pt = Timer.new()
		pt.wait_time = 15.0
		pt.autostart = true
		pt.connect("timeout", Callable(self, "_host_spawn_powerup"))
		add_child(pt)
"""
code = code.replace('	Global.connect("net_new_round", Callable(self, "_on_net_new_round"))', '	Global.connect("net_new_round", Callable(self, "_on_net_new_round"))\n' + ready_block)

# Add PowerUp functions
funcs_block = """
func _host_spawn_powerup():
	if not is_instance_valid(powerup_node) and not is_arena_rotating:
		Global.send_net_data({"type": "spawn_powerup", "x": 320.0, "y": 40.0})
		_spawn_powerup(320.0, 40.0)

func _on_net_spawn_powerup(x: float, y: float):
	if Global.my_player_id != 1:
		_spawn_powerup(x, y)

func _spawn_powerup(px: float, py: float):
	if is_instance_valid(powerup_node):
		return
		
	powerup_node = Area2D.new()
	powerup_node.global_position = Vector2(px, py)
	
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 16.0
	col.shape = shape
	powerup_node.add_child(col)
	
	var vis = ColorRect.new()
	vis.color = Color(1.0, 0.8, 0.0)
	vis.custom_minimum_size = Vector2(24, 24)
	vis.position = Vector2(-12, -12)
	powerup_node.add_child(vis)
	
	var lbl = Label.new()
	lbl.text = "🔄"
	lbl.position = Vector2(-10, -12)
	lbl.add_theme_font_size_override("font_size", 16)
	powerup_node.add_child(lbl)
	
	add_child(powerup_node)
	powerup_node.connect("body_entered", Callable(self, "_on_powerup_body_entered"))

func _on_powerup_body_entered(body: Node2D):
	if body.is_in_group("players") and body.player_id == Global.my_player_id:
		Global.send_net_data({"type": "activate_powerup", "powerup_id": 1})
		_activate_rotation()

func _on_net_activate_powerup(pid: int):
	_activate_rotation()
	
func _activate_rotation():
	if is_instance_valid(powerup_node):
		powerup_node.queue_free()
		powerup_node = null
		
	if is_arena_rotating:
		return
		
	is_arena_rotating = true
	var banner = $HUD/RoundBanner
	banner.text = "🌀 ARENA SHIFT! 🌀"
	banner.visible = true
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(platforms_node, "rotation", platforms_node.rotation + PI, 2.5)
	
	await get_tree().create_timer(2.5).timeout
	banner.visible = false
	is_arena_rotating = false
"""

# Append to file
code += funcs_block

with open("scripts/arena.gd", "w") as f:
    f.write(code)

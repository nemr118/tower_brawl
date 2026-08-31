import os

with open("scripts/player.gd", "r") as f:
    code = f.read()

# Replace send_net_data
old_net = """	if is_local_player:
		Global.send_net_data({
			"type": "player_hit",
			"killer": killer_id,
			"victim": player_id
		})"""
		
new_net = """	if is_local_player:
		Global.send_net_data({
			"type": "player_died",
			"killer": killer_id,
			"victim": player_id
		})"""
code = code.replace(old_net, new_net)

# Add force_die method
force_die = """
func force_die():
	if is_dead: return
	is_dead = true
	visible = false
	collision_shape.set_deferred("disabled", true)
	var splat = load("res://scenes/blood_splatter.tscn").instantiate()
	get_parent().add_child(splat)
	splat.global_position = global_position
"""
code = code.replace("func respawn(pos: Vector2):", force_die + "\nfunc respawn(pos: Vector2):")

# Remove local player_died signal emission since the server handles it now
code = code.replace('emit_signal("player_died", killer_id, player_id)', '')

with open("scripts/player.gd", "w") as f:
    f.write(code)


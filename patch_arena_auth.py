import os

with open("scripts/arena.gd", "r") as f:
    code = f.read()

# Connect the new signal
code = code.replace('Global.connect("net_player_hit", Callable(self, "_on_network_player_hit"))',
                    'Global.connect("net_player_died", Callable(self, "_on_net_player_died"))\n\t\tGlobal.connect("net_player_hit", Callable(self, "_on_network_player_hit"))')

# Replace _on_player_died and _check_round_end
death_logic = """
func _on_net_player_died(killer_id: int, victim_id: int, new_stock: int):
	player_stocks[victim_id] = new_stock
	if victim_id in player_instances and is_instance_valid(player_instances[victim_id]):
		player_instances[victim_id].force_die()
		
	var victim_name = Global.player_names.get(victim_id, "Player " + str(victim_id))
	var killer_name = Global.player_names.get(killer_id, "Player " + str(killer_id))
	
	if killer_id == victim_id:
		_show_banner(victim_name + " fell!", 1.0)
	else:
		_show_banner(killer_name + " knocked out " + victim_name + "!", 1.0)
		
	_update_hud()
	
	if new_stock > 0:
		await get_tree().create_timer(1.2).timeout
		if not is_round_over and victim_id in player_instances:
			var spawn_pos = spawn_points[victim_id - 1]
			player_instances[victim_id].respawn(spawn_pos)

# Obsolete: We don't check round end locally anymore! The server does it!
func _check_round_end():
	pass
"""

# Extract the block to replace
start_idx = code.find("func _on_player_died")
end_idx = code.find("func _on_round_end_sync")

if start_idx != -1 and end_idx != -1:
    code = code[:start_idx] + death_logic + "\n" + code[end_idx:]

with open("scripts/arena.gd", "w") as f:
    f.write(code)


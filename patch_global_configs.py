import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

old_assign = """	if type == "assign_id":
		my_player_id = int(data.get("id", 1))
		
		var m_state = data.get("match_state", "LOBBY")
		var playing = data.get("playing_players", [])
		
		active_players.clear()
		if m_state == "PLAYING":
			# Only players actually playing are considered active by the game logic
			for x in playing:
				active_players.append(int(x))
			is_spectator = not active_players.has(my_player_id)
		else:
			is_spectator = false
			for x in data.get("active_players", []):
				active_players.append(int(x))
				
		var names_map = data.get("player_names", {})
		for p_str in names_map:
			player_names[int(p_str)] = str(names_map[p_str])
			
		if data.has("locked_players"):
			var locked_map = data.get("locked_players", {})
			for p_str in locked_map:
				var p_id = int(p_str)
				var c_type = int(locked_map[p_str])
				locked_opponents[p_id] = c_type
				if p_id != my_player_id:
					emit_signal("net_opponent_locked", p_id, c_type)
					
		emit_signal("net_connected", my_player_id)"""
		
new_assign = """	if type == "assign_id":
		my_player_id = int(data.get("id", 1))
		
		var m_state = data.get("match_state", "LOBBY")
		var playing = data.get("playing_players", [])
		
		active_players.clear()
		if m_state == "PLAYING":
			# Only players actually playing are considered active by the game logic
			for x in playing:
				active_players.append(int(x))
			is_spectator = not active_players.has(my_player_id)
		else:
			is_spectator = false
			for x in data.get("active_players", []):
				active_players.append(int(x))
				
		var names_map = data.get("player_names", {})
		for p_str in names_map:
			player_names[int(p_str)] = str(names_map[p_str])
			
		if data.has("locked_players"):
			var locked_map = data.get("locked_players", {})
			for p_str in locked_map:
				var p_id = int(p_str)
				var c_type = int(locked_map[p_str])
				locked_opponents[p_id] = c_type
				
				# Ensure player_configs is populated for spectators skipping char select
				player_configs[p_id] = {"active": true, "class": c_type}
				
				if p_id != my_player_id:
					emit_signal("net_opponent_locked", p_id, c_type)
					
		# Ensure inactive players are marked as inactive
		for i in range(1, 5):
			if not active_players.has(i):
				player_configs[i]["active"] = false
					
		emit_signal("net_connected", my_player_id)"""
code = code.replace(old_assign, new_assign)

with open("scripts/global.gd", "w") as f:
    f.write(code)


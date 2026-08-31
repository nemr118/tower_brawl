import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

# Add is_spectator variable
code = code.replace("var is_mobile: bool = false", "var is_mobile: bool = false\nvar is_spectator: bool = false")

# Add net_return_to_lobby signal
code = code.replace("signal net_player_died(killer_id, victim_id, stock)", "signal net_return_to_lobby\nsignal net_player_died(killer_id, victim_id, stock)")

# Update assign_id handling
old_assign = """	if type == "assign_id":
		my_player_id = int(data.get("id", 1))
		
		active_players.clear()
		for x in data.get("active_players", []):
			active_players.append(int(x))"""
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
				active_players.append(int(x))"""
code = code.replace(old_assign, new_assign)

# Add return_to_lobby handling
old_died = """	elif type == "player_died":"""
new_died = """	elif type == "return_to_lobby":
		is_spectator = false
		emit_signal("net_return_to_lobby")
		
	elif type == "player_died":"""
code = code.replace(old_died, new_died)

with open("scripts/global.gd", "w") as f:
    f.write(code)


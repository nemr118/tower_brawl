import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

old_assign = """		# Ensure inactive players are marked as inactive
		for i in range(1, 5):
			if not active_players.has(i):
				player_configs[i]["active"] = false
					
		emit_signal("net_connected", my_player_id)"""
		
new_assign = """		# Ensure inactive players are marked as inactive
		for i in range(1, 5):
			if not active_players.has(i):
				player_configs[i]["active"] = false
				
		if data.has("scores"):
			var sm = data.get("scores")
			for i in range(1, 5):
				player_scores[i] = int(sm.get(str(i), 0))
				
		# We'll store stocks in a temporary global var for arena.gd to read, or arena.gd can just rely on defaults until they die
		# Actually, just reading scores is good enough for HUD.
					
		emit_signal("net_connected", my_player_id)"""
code = code.replace(old_assign, new_assign)

with open("scripts/global.gd", "w") as f:
    f.write(code)


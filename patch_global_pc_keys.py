import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

pc_key_remap = """		
		# Transfer PC Keyboard and Mouse binds to our assigned slot if we aren't P1
		if not OS.has_feature("web") and my_player_id != 1:
			var prefix1 = "p1_"
			for action_suffix in ["left", "right", "up", "down", "jump", "dash", "attack", "special"]:
				var events1 = InputMap.action_get_events(prefix1 + action_suffix)
				var my_action = prefix + action_suffix
				for ev in events1:
					if ev is InputEventKey or ev is InputEventMouseButton:
						InputMap.action_add_event(my_action, ev)
"""

old_active_players = "		active_players.clear()"
code = code.replace(old_active_players, pc_key_remap + "\n" + old_active_players)

with open("scripts/global.gd", "w") as f:
    f.write(code)


with open("scripts/global.gd", "r") as f:
    code = f.read()

bad_input = """		var prefix = "p" + str(my_player_id) + "_"
		for action in InputMap.get_actions():
			if action.begins_with(prefix):
				var events = InputMap.action_get_events(action)
				for ev in events:
					if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
						ev.device = -1"""

good_input = """		var prefix = "p" + str(my_player_id) + "_"
		for action in InputMap.get_actions():
			if action.begins_with(prefix):
				var events = InputMap.action_get_events(action)
				InputMap.action_erase_events(action)
				for ev in events:
					if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
						ev.device = -1
					InputMap.action_add_event(action, ev)"""

code = code.replace(bad_input, good_input)

with open("scripts/global.gd", "w") as f:
    f.write(code)

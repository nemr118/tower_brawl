with open("scripts/global.gd", "r") as f:
    code = f.read()

gamepad_fix = """		my_player_id = int(data.get("id", 1))
		print("🎮 [Global] Assigned Player ID: ", my_player_id)
		_save_player_id()   # persist so reconnects restore this slot
		
		# Remap local gamepad inputs to accept any controller (device: -1)
		# This ensures phones with 1 connected controller (device 0) can play as P2, P3, or P4!
		var prefix = "p" + str(my_player_id) + "_"
		for action in InputMap.get_actions():
			if action.begins_with(prefix):
				var events = InputMap.action_get_events(action)
				for ev in events:
					if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
						ev.device = -1"""

code = code.replace("""		my_player_id = int(data.get("id", 1))
		print("🎮 [Global] Assigned Player ID: ", my_player_id)
		_save_player_id()   # persist so reconnects restore this slot""", gamepad_fix)

with open("scripts/global.gd", "w") as f:
    f.write(code)

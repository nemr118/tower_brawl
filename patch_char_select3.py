import os

with open("scripts/character_select.gd", "r") as f:
    code = f.read()

bad = """	if local_player_id == 1 and force_start_btn:
	force_start_btn.visible = (locked_count >= 2 and locked_count < active_count and not is_revealing)"""
good = """	if local_player_id == 1 and force_start_btn:
		force_start_btn.visible = (locked_count >= 2 and locked_count < active_count and not is_revealing)"""
code = code.replace(bad, good)

with open("scripts/character_select.gd", "w") as f:
    f.write(code)


import os

with open("scripts/player.gd", "r") as f:
    code = f.read()

old_mouse = """		var raw_aim = Vector2.ZERO
		if is_local_player and not OS.has_feature("web"):
			raw_aim = get_global_mouse_position() - global_position"""

new_mouse = """		var raw_aim = Vector2.ZERO
		if is_local_player and not Global.is_mobile:
			raw_aim = get_global_mouse_position() - global_position"""
			
code = code.replace(old_mouse, new_mouse)

with open("scripts/player.gd", "w") as f:
    f.write(code)


import os

with open("scripts/global.gd", "r") as f:
    code = f.read()

old_died = """	elif type == "return_to_lobby":
		is_spectator = false
		emit_signal("net_return_to_lobby")"""
new_died = """	elif type == "return_to_lobby":
		is_spectator = false
		locked_opponents.clear()
		reset_scores()
		emit_signal("net_return_to_lobby")"""
code = code.replace(old_died, new_died)

with open("scripts/global.gd", "w") as f:
    f.write(code)


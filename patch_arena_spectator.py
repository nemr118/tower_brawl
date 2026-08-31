import os

with open("scripts/arena.gd", "r") as f:
    code = f.read()

# Add signal connection
code = code.replace('Global.connect("net_new_round", Callable(self, "_on_new_round_sync"))', 'Global.connect("net_new_round", Callable(self, "_on_new_round_sync"))\n\tGlobal.connect("net_return_to_lobby", Callable(self, "_on_return_to_lobby"))')

# Add the return to lobby function and spectator UI check
new_func = """
func _on_return_to_lobby():
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")
"""
code = code.replace("func _start_new_match():", new_func + "\nfunc _start_new_match():")

# Display spectator text if applicable
spec_ui = """	_show_banner("ROUND " + str(current_round) + " - FIGHT!", 1.5)
	if Global.is_spectator:
		await get_tree().create_timer(1.5).timeout
		_show_banner("SPECTATING... WAITING FOR ROUND END", 999.0)
"""
code = code.replace('_show_banner("ROUND " + str(current_round) + " - FIGHT!", 1.5)', spec_ui)

with open("scripts/arena.gd", "w") as f:
    f.write(code)


with open("scripts/arena.gd", "r") as f:
    code = f.read()

timer_code = """
	Global.connect("net_spawn_powerup", Callable(self, "_on_net_spawn_powerup"))
	Global.connect("net_activate_powerup", Callable(self, "_on_net_activate_powerup"))
	
	if Global.my_player_id == 1:
		var pt = Timer.new()
		pt.wait_time = 15.0
		pt.autostart = true
		pt.connect("timeout", Callable(self, "_host_spawn_powerup"))
		add_child(pt)"""

code = code.replace("	_start_new_match()", timer_code + "\n\t_start_new_match()")

with open("scripts/arena.gd", "w") as f:
    f.write(code)


with open("scripts/arena.gd", "r") as f:
    code = f.read()

bad_input_code = """func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			Global.reset_scores()
		
	Global.connect("net_spawn_powerup", Callable(self, "_on_net_spawn_powerup"))
	Global.connect("net_activate_powerup", Callable(self, "_on_net_activate_powerup"))
	
	if Global.my_player_id == 1:
		var pt = Timer.new()
		pt.wait_time = 15.0
		pt.autostart = true
		pt.connect("timeout", Callable(self, "_host_spawn_powerup"))
		add_child(pt)
	_start_new_match()"""

good_input_code = """func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			Global.reset_scores()
			_start_new_match()"""

code = code.replace(bad_input_code, good_input_code)

with open("scripts/arena.gd", "w") as f:
    f.write(code)

with open("scripts/player.gd", "r") as f:
    code = f.read()

old_aim = """	var raw_aim = Vector2(input_x, input_y)
	if raw_aim.length_squared() > 0.08:
		aim_direction = raw_aim.normalized()
		if input_x > 0.15:
			is_facing_right = true
		elif input_x < -0.15:
			is_facing_right = false
	else:
		aim_direction = Vector2.RIGHT if is_facing_right else Vector2.LEFT"""

new_aim = """	var raw_aim = Vector2.ZERO
	if is_local_player and not OS.has_feature("web"):
		raw_aim = get_global_mouse_position() - global_position
		if raw_aim.length_squared() > 0.08:
			aim_direction = raw_aim.normalized()
			is_facing_right = raw_aim.x > 0
	else:
		raw_aim = Vector2(input_x, input_y)
		if raw_aim.length_squared() > 0.08:
			aim_direction = raw_aim.normalized()
			if input_x > 0.15:
				is_facing_right = true
			elif input_x < -0.15:
				is_facing_right = false
		else:
			aim_direction = Vector2.RIGHT if is_facing_right else Vector2.LEFT"""

code = code.replace(old_aim, new_aim)

with open("scripts/player.gd", "w") as f:
    f.write(code)

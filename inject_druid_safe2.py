import os

with open("scripts/player.gd", "r") as f:
    code = f.read()

def replace_once(source, old, new):
    if code.count(old) != 1:
        print(f"Warning: '{old.strip()}' found {code.count(old)} times!")
    return source.replace(old, new, 1)

attack_druid = """		Global.ClassType.DRUID:
			if is_bear_form:
				attack_cooldown = 0.5
				_squash_and_stretch(1.2, 0.8)
				_execute_shadow_slash()
			else:
				attack_cooldown = 0.35
				var spawn_pos = global_position + aim_dir * 18.0
				var thorn = ThornScene.instantiate()
				get_parent().add_child(thorn)
				thorn.init(player_id, spawn_pos, aim_dir)
				_squash_and_stretch(0.9, 1.1)"""
old_attack_rogue = """		Global.ClassType.ROGUE:
			if rogue_kunai > 0:"""
code = replace_once(code, old_attack_rogue, attack_druid + "\n" + old_attack_rogue)


old_speed = """	if input_x != 0.0:
		velocity.x = move_toward(velocity.x, input_x * SPEED, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)"""

new_speed = """	var current_speed = SPEED
	if is_bear_form:
		current_speed = SPEED * 0.55
	
	if input_x != 0.0:
		velocity.x = move_toward(velocity.x, input_x * current_speed, ACCELERATION * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)"""

# I need to find the exact speed logic string! Let's just do it line by line:
# The lines are inside `_physics_process`:
code = code.replace("	if input_x != 0.0:\n		velocity.x = move_toward(velocity.x, input_x * SPEED, ACCELERATION * delta)\n	else:\n		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)", new_speed)


druid_draw = """		Global.ClassType.DRUID:
			if is_egg:
				draw_circle(Vector2(0, -7), 9.0, Color(1.0, 0.8, 0.4))
				draw_circle(Vector2(0, -7), 6.0, Color(1.0, 0.4, 0.1))
			elif is_bear_form:
				draw_circle(Vector2(0, -14), 16.0, Color(0.35, 0.25, 0.15)) # Bear body
				draw_circle(Vector2(12 * (1 if is_facing_right else -1), -22), 5.0, Color(0.2, 0.1, 0.05)) # Ear
			else:
				draw_colored_polygon(PackedVector2Array([Vector2(-8, -17 + breath), Vector2(0, -28 + breath), Vector2(8, -17 + breath)]), Color(0.2, 0.6, 0.2))
				draw_circle(Vector2(0, -28 + breath), 4.0, Color(0.8, 0.9, 0.2))
				
				# Little floating orb / leaf
				draw_circle(Vector2(-12, -20 + sin(Time.get_ticks_msec()*0.005)*3), 3.0, Color(0.4, 0.9, 0.4))"""

old_draw_rogue = """		Global.ClassType.ROGUE:
			draw_colored_polygon([Vector2(-7, -20 + breath), Vector2(0, -25 + breath), Vector2(7, -20 + breath), Vector2(7, -11 + breath), Vector2(-7, -11 + breath)], Color(0.18, 0.12, 0.25))"""
code = replace_once(code, old_draw_rogue, druid_draw + "\n" + old_draw_rogue)


with open("scripts/player.gd", "w") as f:
    f.write(code)


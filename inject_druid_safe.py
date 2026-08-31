import os

with open("scripts/player.gd", "r") as f:
    code = f.read()

def replace_once(source, old, new):
    if code.count(old) != 1:
        print(f"Warning: '{old}' found {code.count(old)} times!")
    return source.replace(old, new, 1)

# 1. Add ThornScene
code = replace_once(code, 'const KunaiScene = preload("res://scenes/kunai.tscn")',
                    'const KunaiScene = preload("res://scenes/kunai.tscn")\nconst ThornScene = preload("res://scenes/thorn.tscn")')

# 2. State variables
code = replace_once(code, 'var is_shielding: bool = false',
                    'var is_shielding: bool = false\nvar is_bear_form: bool = false\nvar is_egg: bool = false\nvar egg_timer: float = 0.0')

# 3. Physics process egg logic (Find exactly inside _physics_process)
egg_logic = """	if is_egg:
		egg_timer -= delta
		if egg_timer <= 0.0:
			is_egg = false
			spawn_invuln_timer = 1.0
			_squash_and_stretch(1.5, 1.5)
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.y += GRAVITY * delta
		move_and_slide()
		_sync_network_state(delta)
		queue_redraw()
		return
		
	if spawn_invuln_timer > 0.0:"""
code = replace_once(code, '	if spawn_invuln_timer > 0.0:\n		spawn_invuln_timer -= delta\n	if shield_timer > 0.0:', 
                    egg_logic + '\n		spawn_invuln_timer -= delta\n	if shield_timer > 0.0:')

# 4. Sync variables
code = replace_once(code, '"shield": is_shielding\n		})',
                    '"shield": is_shielding,\n			"bear": is_bear_form,\n			"egg": is_egg\n		})')
code = replace_once(code, 'is_shielding = bool(data.get("shield", false))',
                    'is_shielding = bool(data.get("shield", false))\n		is_bear_form = bool(data.get("bear", false))\n		is_egg = bool(data.get("egg", false))')

# 5. Attack (Target _perform_attack specifically)
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
			rogue_kunai = 4
			_start_dash(aim_dir.x, aim_dir.y)"""
code = replace_once(code, old_attack_rogue, attack_druid + "\n" + old_attack_rogue)

# 6. Special (Target _perform_special specifically)
special_druid = """		Global.ClassType.DRUID:
			special_cooldown = 1.0
			if is_on_floor():
				is_bear_form = not is_bear_form
				_squash_and_stretch(1.5, 0.7)
			else:
				is_shielding = true
				shield_timer = 1.5
				velocity = Vector2.ZERO
				_squash_and_stretch(0.8, 1.2)"""
old_special_rogue = """		Global.ClassType.ROGUE:
			special_cooldown = 1.1
			_start_dash(aim_dir.x, aim_dir.y)
			_execute_shadow_slash()"""
code = replace_once(code, old_special_rogue, special_druid + "\n" + old_special_rogue)

# 7. Take Hit
hit_logic = """	if is_shielding:
		if class_type == Global.ClassType.DRUID:
			is_shielding = false
			is_egg = true
			egg_timer = 3.0
			velocity = Vector2.ZERO
			_squash_and_stretch(1.4, 0.7)
		return"""
old_hit = """	if is_dead or spawn_invuln_timer > 0.0 or is_dashing or is_shielding:
		return"""
new_hit = """	if is_dead or spawn_invuln_timer > 0.0 or is_dashing:
		return
		
""" + hit_logic
code = replace_once(code, old_hit, new_hit)

# 8. Reset on death
code = replace_once(code, '	is_shielding = false\n	spawn_invuln_timer = 1.0',
                    '	is_shielding = false\n	is_egg = false\n	is_bear_form = false\n	spawn_invuln_timer = 1.0')

# 9. Speed reduction for bear
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
code = replace_once(code, old_speed, new_speed)

# 10. Dash drawing
old_dash = """	if is_dashing:
		draw_circle(-dash_dir * 12.0, 10.0, Color(base_col.r, base_col.g, base_col.b, 0.45))
		draw_circle(-dash_dir * 22.0, 7.0, Color(base_col.r, base_col.g, base_col.b, 0.25))"""
new_dash = """	if is_dashing:
		if class_type == Global.ClassType.DRUID:
			draw_circle(Vector2(0,-12), 10.0, Color(0.15, 0.15, 0.2)) # Crow body
			var wing = 18.0 if sin(Time.get_ticks_msec() * 0.02) > 0 else 4.0
			draw_line(Vector2(-wing, -12), Vector2(wing, -12), Color(0.2, 0.2, 0.25), 6.0) # Wings
		else:
			draw_circle(-dash_dir * 12.0, 10.0, Color(base_col.r, base_col.g, base_col.b, 0.45))
			draw_circle(-dash_dir * 22.0, 7.0, Color(base_col.r, base_col.g, base_col.b, 0.25))"""
code = replace_once(code, old_dash, new_dash)

# 11. Normal drawing
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
			draw_colored_polygon(PackedVector2Array([Vector2(-7, -20 + breath), Vector2(0, -25 + breath), Vector2(7, -20 + breath), Vector2(7, -11 + breath), Vector2(-7, -11 + breath)]), Color(0.18, 0.12, 0.25))
			draw_circle(Vector2(0, -20 + breath), 4.0, Color(0.8, 0.4, 0.9))"""
code = replace_once(code, old_draw_rogue, druid_draw + "\n" + old_draw_rogue)


with open("scripts/player.gd", "w") as f:
    f.write(code)


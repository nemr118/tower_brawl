import os

with open("scripts/player.gd", "r") as f:
    lines = f.readlines()

draw_start = -1
for i, line in enumerate(lines):
    if line.startswith("func _draw():"):
        draw_start = i
        break

draw_code = """func _draw():
	if is_dead:
		return

	var class_info = Global.CLASS_INFO[class_type]
	var base_col: Color = class_info["color"]

	var facing_mul = 1.0 if is_facing_right else -1.0
	var run_cycle = sin(anim_time) * 2.5 if abs(velocity.x) > 20.0 and is_on_floor() else 0.0
	var breath = sin(anim_time * 0.4) * 0.8
	
	if spawn_invuln_timer > 0.0:
		draw_arc(Vector2.ZERO, 18.0 + breath, 0.0, TAU, 20, Color(1.0, 0.9, 0.3, 0.6), 2.0)
		draw_circle(Vector2.ZERO, 16.0, Color(1.0, 1.0, 0.6, 0.25))
		
	# --- DRUID SHAPESHIFTING OVERRIDES ---
	var is_druid_special = (class_type == Global.ClassType.DRUID) and (is_bear_form or is_egg or is_dashing or is_shielding)
	
	if is_druid_special:
		if is_egg:
			# Large patterned egg
			draw_circle(Vector2(0, -9), 11.0, Color(0.9, 0.8, 0.6))
			draw_circle(Vector2(0, -11), 8.0, Color(0.95, 0.9, 0.8)) # Highlight
			draw_line(Vector2(-8, -9), Vector2(8, -9), Color(0.8, 0.4, 0.2), 3.0) # Pattern
			draw_line(Vector2(-6, -4), Vector2(6, -4), Color(0.8, 0.4, 0.2), 3.0)
		elif is_shielding:
			# Phoenix Form
			var flap = sin(Time.get_ticks_msec() * 0.015) * 8.0
			# Body core
			draw_circle(Vector2(0, -12 + breath), 8.0, Color(1.0, 0.5, 0.1))
			draw_circle(Vector2(0, -12 + breath), 5.0, Color(1.0, 0.8, 0.2))
			# Flaming wings
			var wing_pts = PackedVector2Array([
				Vector2(-4, -12 + breath),
				Vector2(-24, -16 + breath + flap),
				Vector2(-14, -6 + breath + flap * 0.5)
			])
			draw_colored_polygon(wing_pts, Color(0.9, 0.3, 0.1, 0.8))
			var wing_pts2 = PackedVector2Array([
				Vector2(4, -12 + breath),
				Vector2(24, -16 + breath + flap),
				Vector2(14, -6 + breath + flap * 0.5)
			])
			draw_colored_polygon(wing_pts2, Color(0.9, 0.3, 0.1, 0.8))
			# Tail feathers
			draw_line(Vector2(0, -8 + breath), Vector2(-6, 2 + breath), Color(1.0, 0.4, 0.1), 3.0)
			draw_line(Vector2(0, -8 + breath), Vector2(6, 2 + breath), Color(1.0, 0.4, 0.1), 3.0)
			# Beak
			draw_colored_polygon(PackedVector2Array([
				Vector2(4 * facing_mul, -14 + breath),
				Vector2(12 * facing_mul, -12 + breath),
				Vector2(4 * facing_mul, -10 + breath)
			]), Color(1.0, 0.9, 0.2))
			# Eye
			draw_circle(Vector2(3 * facing_mul, -14 + breath), 1.5, Color(1.0, 1.0, 1.0))
		elif is_dashing:
			# Storm Crow
			var flap = 14.0 if sin(Time.get_ticks_msec() * 0.03) > 0 else -4.0
			draw_circle(Vector2(0, -12), 9.0, Color(0.15, 0.15, 0.2)) # Body
			draw_circle(Vector2(6 * facing_mul, -14), 5.0, Color(0.15, 0.15, 0.2)) # Head
			draw_colored_polygon(PackedVector2Array([
				Vector2(9 * facing_mul, -16),
				Vector2(16 * facing_mul, -13),
				Vector2(9 * facing_mul, -12)
			]), Color(0.8, 0.7, 0.2)) # Beak
			draw_circle(Vector2(7 * facing_mul, -15), 1.0, Color(0.8, 0.1, 0.1)) # Red eye
			draw_line(Vector2(-12, -12), Vector2(-12, -12 + flap), Color(0.1, 0.1, 0.15), 6.0) # Wing back
			draw_line(Vector2(0, -12), Vector2(0, -12 + flap), Color(0.2, 0.2, 0.25), 6.0) # Wing front
			draw_line(Vector2(-8 * facing_mul, -10), Vector2(-16 * facing_mul, -8), Color(0.15, 0.15, 0.2), 4.0) # Tail
		elif is_bear_form:
			# Heavy Bear Form
			var bear_col = Color(0.4, 0.25, 0.15)
			var belly_col = Color(0.5, 0.35, 0.2)
			# Back leg
			draw_rect(Rect2(-8 - run_cycle, -6, 6, 8), Color(0.25, 0.15, 0.1), true)
			draw_rect(Rect2(4 + run_cycle, -6, 6, 8), Color(0.25, 0.15, 0.1), true)
			# Main Body (Huge Oval)
			draw_circle(Vector2(0, -15 + breath * 0.5), 16.0, bear_col)
			draw_circle(Vector2(-2, -12 + breath * 0.5), 12.0, belly_col)
			# Front leg
			draw_rect(Rect2(-12 + run_cycle, -4, 6, 8), bear_col, true)
			draw_rect(Rect2(8 - run_cycle, -4, 6, 8), bear_col, true)
			# Head
			draw_circle(Vector2(12 * facing_mul, -20 + breath * 0.5), 10.0, bear_col)
			# Snout
			draw_circle(Vector2(18 * facing_mul, -18 + breath * 0.5), 5.0, belly_col)
			draw_circle(Vector2(21 * facing_mul, -19 + breath * 0.5), 2.0, Color(0.1, 0.1, 0.1)) # Nose
			# Ears
			draw_circle(Vector2(6 * facing_mul, -28 + breath * 0.5), 4.0, bear_col)
			draw_circle(Vector2(6 * facing_mul, -28 + breath * 0.5), 2.0, Color(0.2, 0.1, 0.05))
			# Eye
			draw_circle(Vector2(14 * facing_mul, -22 + breath * 0.5), 1.5, Color(1.0, 1.0, 1.0))
			draw_circle(Vector2((14 * facing_mul) + (1 * facing_mul), -22 + breath * 0.5), 0.8, Color(0.0, 0.0, 0.0))
		return
		
	# --- NORMAL HUMANOID DRAWING ---

	if is_shielding and class_type == Global.ClassType.KNIGHT:
		draw_circle(Vector2.ZERO, 19.0, Color(0.3, 0.6, 1.0, 0.45))
		draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 24, Color(0.8, 0.95, 1.0), 3.0)
		
	if is_dashing:
		draw_circle(-dash_dir * 12.0, 10.0, Color(base_col.r, base_col.g, base_col.b, 0.45))
		draw_circle(-dash_dir * 22.0, 7.0, Color(base_col.r, base_col.g, base_col.b, 0.25))

	var aim_len = 36.0
	var laser_start = aim_direction * 14.0
	var laser_end = aim_direction * aim_len
	draw_line(laser_start, laser_end, Color(1.0, 1.0, 1.0, 0.3), 1.0)
	draw_circle(laser_end, 2.0, Color(1.0, 0.9, 0.3, 0.75))

	var cape_col = Color(base_col.r * 0.6, base_col.g * 0.6, base_col.b * 0.6)
	var cape_wave = sin(anim_time * 0.8) * 3.0 - (velocity.x * 0.03)
	var cape_pts = PackedVector2Array([
		Vector2(-4 * facing_mul, -8),
		Vector2(2 * facing_mul, -8),
		Vector2((-9 * facing_mul) + cape_wave, 8),
		Vector2((-14 * facing_mul) + cape_wave * 1.3, 7)
	])
	draw_colored_polygon(cape_pts, cape_col)

	var foot_l = Vector2(-4, 9 + run_cycle)
	var foot_r = Vector2(4, 9 - run_cycle)
	draw_rect(Rect2(foot_l.x - 2, foot_l.y - 2, 4, 3), Color(0.18, 0.12, 0.1), true)
	draw_rect(Rect2(foot_r.x - 2, foot_r.y - 2, 4, 3), Color(0.18, 0.12, 0.1), true)

	draw_rect(Rect2(-7, -10 + breath, 14, 18), base_col, true)
	draw_rect(Rect2(-7, -10 + breath, 14, 18), Color(0.08, 0.08, 0.12), false, 1.5)
	draw_rect(Rect2(-7, -2 + breath, 14, 3), Color(0.3, 0.2, 0.1), true)
	draw_rect(Rect2(-2, -3 + breath, 4, 5), Color(0.95, 0.8, 0.2), true)
	
	draw_rect(Rect2(-6, -18 + breath, 12, 10), Color(0.98, 0.85, 0.72), true)
	draw_rect(Rect2(-6, -18 + breath, 12, 10), Color(0.1, 0.08, 0.1), false, 1.0)
	
	var eye_x = 2 * facing_mul
	draw_rect(Rect2(eye_x, -15 + breath, 2, 3), Color(0.1, 0.1, 0.2), true)
	draw_rect(Rect2(eye_x + (1 if is_facing_right else 0), -15 + breath, 1, 1), Color(1.0, 1.0, 1.0), true)
	
	match class_type:
		Global.ClassType.RANGER:
			draw_colored_polygon(PackedVector2Array([Vector2(-8, -17 + breath), Vector2(0, -24 + breath), Vector2(8, -17 + breath)]), Color(0.15, 0.55, 0.25))
			draw_line(Vector2(2 * facing_mul, -22 + breath), Vector2(7 * facing_mul, -28 + breath), Color(0.95, 0.2, 0.2), 2.5)
			var bow_pos = aim_direction * 12.0
			var bow_angle = aim_direction.angle()
			var bow_t = Transform2D(bow_angle, bow_pos)
			var b1 = bow_t * Vector2(-2, -10)
			var b2 = bow_t * Vector2(5, 0)
			var b3 = bow_t * Vector2(-2, 10)
			draw_line(b1, b2, Color(0.55, 0.35, 0.15), 2.5)
			draw_line(b2, b3, Color(0.55, 0.35, 0.15), 2.5)
			draw_line(b1, b3, Color(0.9, 0.9, 0.9, 0.8), 1.0)
		Global.ClassType.KNIGHT:
			draw_rect(Rect2(-7, -21 + breath, 14, 9), Color(0.7, 0.75, 0.8), true)
			draw_rect(Rect2(-7, -21 + breath, 14, 9), Color(0.2, 0.2, 0.25), false, 1.2)
			draw_line(Vector2(-4, -16 + breath), Vector2(4, -16 + breath), Color(0.1, 0.1, 0.15), 2.0)
			draw_line(Vector2(0, -21 + breath), Vector2(0, -28 + breath), Color(0.95, 0.2, 0.2), 3.5)
			var sword_pos = aim_direction * 10.0
			var sword_end = sword_pos + aim_direction * 18.0
			draw_line(sword_pos, sword_end, Color(0.9, 0.92, 0.98), 3.0)
			draw_line(sword_pos - aim_direction.orthogonal() * 5.0, sword_pos + aim_direction.orthogonal() * 5.0, Color(0.85, 0.7, 0.2), 2.5)
		Global.ClassType.MAGE:
			draw_colored_polygon(PackedVector2Array([Vector2(-9, -17 + breath), Vector2(0, -29 + breath), Vector2(9, -17 + breath)]), Color(0.25, 0.12, 0.45))
			draw_circle(Vector2(0, -29 + breath), 3.0, Color(1.0, 0.8, 0.2))
			var staff_end = aim_direction * 16.0
			draw_line(Vector2.ZERO, staff_end, Color(0.4, 0.25, 0.15), 2.0)
			draw_circle(staff_end, 4.5, Color(1.0, 0.5, 0.1, 0.9))
			draw_circle(staff_end, 2.5, Color(1.0, 0.9, 0.5))
		Global.ClassType.DRUID:
			# Normal human druid details
			draw_colored_polygon(PackedVector2Array([Vector2(-8, -17 + breath), Vector2(0, -28 + breath), Vector2(8, -17 + breath)]), Color(0.2, 0.6, 0.2))
			draw_circle(Vector2(0, -28 + breath), 4.0, Color(0.8, 0.9, 0.2))
			draw_circle(Vector2(-12, -20 + sin(Time.get_ticks_msec()*0.005)*3), 3.0, Color(0.4, 0.9, 0.4))
		Global.ClassType.ROGUE:
			draw_colored_polygon(PackedVector2Array([Vector2(-7, -20 + breath), Vector2(0, -25 + breath), Vector2(7, -20 + breath), Vector2(7, -11 + breath), Vector2(-7, -11 + breath)]), Color(0.18, 0.12, 0.25))
			draw_rect(Rect2(eye_x, -16 + breath, 3, 2), Color(0.85, 0.3, 1.0), true)
			var d1 = aim_direction * 14.0
			var d2 = aim_direction * 10.0 + aim_direction.orthogonal() * 6.0
			draw_line(Vector2.ZERO, d1, Color(0.9, 0.95, 1.0), 2.0)
			draw_line(Vector2.ZERO, d2, Color(0.9, 0.95, 1.0), 2.0)

	if class_type == Global.ClassType.RANGER:
		for i in range(max_arrows):
			var ax = -8 + i * 8
			var col = Color(1.0, 0.85, 0.2) if i < current_arrows else Color(0.3, 0.3, 0.3, 0.5)
			draw_line(Vector2(ax, -30 + breath), Vector2(ax, -36 + breath), col, 2.5)
			draw_line(Vector2(ax - 2, -34 + breath), Vector2(ax, -36 + breath), col, 1.5)
	elif class_type == Global.ClassType.MAGE:
		for i in range(3):
			var mx = -8 + i * 8
			var col = Color(1.0, 0.5, 0.1) if i < mage_charges else Color(0.3, 0.3, 0.3, 0.5)
			draw_circle(Vector2(mx, -32 + breath), 3.0, col)
	elif class_type == Global.ClassType.ROGUE:
		for i in range(4):
			var kx = -9 + i * 6
			var col = Color(0.85, 0.35, 1.0) if i < rogue_kunai else Color(0.3, 0.3, 0.3, 0.5)
			draw_circle(Vector2(kx, -32 + breath), 2.5, col)
"""

new_lines = lines[:draw_start] + [draw_code]
with open("scripts/player.gd", "w") as f:
    f.writelines(new_lines)


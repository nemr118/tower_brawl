import os

with open("scripts/touch_controls.gd", "r") as f:
    code = f.read()

# Add active_right_touches dictionary
code = code.replace("var max_radius: float = 45.0\n", "var max_radius: float = 45.0\nvar active_right_touches = {}\n")

# In _ready, set MOUSE_FILTER_IGNORE so buttons are purely visual
ready_inj = """
	btn_jump.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_attack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_special.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn_dash.mouse_filter = Control.MOUSE_FILTER_IGNORE
"""
code = code.replace("visible = is_mobile", "visible = is_mobile\n" + ready_inj)

# Replace the entire _input function with a robust multi-touch handler
input_func = """func _input(event):
	if not visible:
		return
		
	if event is InputEventScreenTouch:
		if event.pressed:
			# Left half of screen -> Joystick
			if event.position.x < (get_viewport().get_visible_rect().size.x / 2.0) and joy_touch_index == -1:
				joy_touch_index = event.index
				is_touching_joystick = true
				joystick_base.global_position = event.position - joystick_base.size / 2.0
				_update_base_center()
				_handle_joystick_move(event.position)
			else:
				# Right side -> Buttons
				var action = _get_action_at_pos(event.position)
				if action != "":
					active_right_touches[event.index] = action
					Input.action_press(my_input_prefix + action)
		else:
			if event.index == joy_touch_index:
				is_touching_joystick = false
				joy_touch_index = -1
				joystick_thumb.position = joystick_base.size / 2.0 - joystick_thumb.size / 2.0
				_simulate_move(Vector2.ZERO)
			elif active_right_touches.has(event.index):
				var action = active_right_touches[event.index]
				if action != "":
					Input.action_release(my_input_prefix + action)
				active_right_touches.erase(event.index)
				
	elif event is InputEventScreenDrag:
		if event.index == joy_touch_index and is_touching_joystick:
			_handle_joystick_move(event.position)
		else:
			var new_action = _get_action_at_pos(event.position)
			var old_action = active_right_touches.get(event.index, "")
			if new_action != old_action:
				if old_action != "":
					Input.action_release(my_input_prefix + old_action)
				if new_action != "":
					Input.action_press(my_input_prefix + new_action)
				active_right_touches[event.index] = new_action

func _get_action_at_pos(pos: Vector2) -> String:
	# Add a little padding to the rects to make them easier to hit on mobile
	var padding = 20.0
	if btn_jump.get_global_rect().grow(padding).has_point(pos): return "jump"
	if btn_attack.get_global_rect().grow(padding).has_point(pos): return "attack"
	if btn_special.get_global_rect().grow(padding).has_point(pos): return "special"
	if btn_dash.get_global_rect().grow(padding).has_point(pos): return "dash"
	return ""
"""

# Extract everything up to _input
start_idx = code.find("func _input(event):")
end_idx = code.find("func _handle_joystick_move")

if start_idx != -1 and end_idx != -1:
    code = code[:start_idx] + input_func + "\n" + code[end_idx:]

with open("scripts/touch_controls.gd", "w") as f:
    f.write(code)


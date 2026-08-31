import os

with open("scripts/character_select.gd", "r") as f:
    code = f.read()

old_input = """	if not is_locked_in:
		if event.is_action_pressed(prefix + "left") or event.is_action_pressed("ui_left"):
			_cycle_selection(-1)
		elif event.is_action_pressed(prefix + "right") or event.is_action_pressed("ui_right"):
			_cycle_selection(1)
		elif event.is_action_pressed(prefix + "jump") or event.is_action_pressed(prefix + "attack") or event.is_action_pressed("ui_accept"):
			_lock_in_champion()"""

new_input = """	if not is_locked_in:
		if event.is_action_pressed(prefix + "left") or event.is_action_pressed("ui_left"):
			_cycle_selection(-1)
		elif event.is_action_pressed(prefix + "right") or event.is_action_pressed("ui_right"):
			_cycle_selection(1)
		elif event.is_action_pressed(prefix + "jump") or event.is_action_pressed(prefix + "attack") or event.is_action_pressed("ui_accept"):
			# Ignore mouse clicks for shortcuts so they don't instantly lock when clicking 'Next'
			if not (event is InputEventMouseButton):
				_lock_in_champion()"""

code = code.replace(old_input, new_input)

# Also fix the indentation bug in _on_btn_next_pressed!
bad_indent = """func _on_btn_next_pressed():
	if not is_locked_in:
		_cycle_selection(1)


	# Force Start button for Host
	force_start_btn = Button.new()"""

good_indent = """func _on_btn_next_pressed():
	if not is_locked_in:
		_cycle_selection(1)"""

# The bad indent bug is because I injected code badly before. I'll search and replace the whole block if needed.
# Actually let's just find `force_start_btn = Button.new()` and fix its indentation.
lines = code.split('\n')
new_lines = []
in_next = False
for line in lines:
	if line.startswith("func _on_btn_next_pressed():"):
		in_next = True
	elif in_next and "force_start_btn = Button.new()" in line:
		# We found the block! Let's unindent the rest of the lines
		pass
# It's easier to just use string replace.
code = code.replace("	# Force Start button for Host", "# Force Start button for Host")
code = code.replace("\tforce_start_btn = Button.new()", "force_start_btn = Button.new()")
code = code.replace("\tforce_start_btn.text = \"FORCE START\"", "force_start_btn.text = \"FORCE START\"")
code = code.replace("\tforce_start_btn.add_theme_font_size_override", "force_start_btn.add_theme_font_size_override")
code = code.replace("\tforce_start_btn.custom_minimum_size", "force_start_btn.custom_minimum_size")
code = code.replace("\tforce_start_btn.set_anchors_preset", "force_start_btn.set_anchors_preset")
code = code.replace("\tforce_start_btn.position", "force_start_btn.position")
code = code.replace("\tforce_start_btn.add_theme_color_override", "force_start_btn.add_theme_color_override")
code = code.replace("\tforce_start_btn.visible", "force_start_btn.visible")
code = code.replace("\tadd_child(force_start_btn)", "add_child(force_start_btn)")
code = code.replace("\tforce_start_btn.connect(\"pressed\"", "force_start_btn.connect(\"pressed\"")

with open("scripts/character_select.gd", "w") as f:
    f.write(code)


import os

with open("scripts/character_select.gd", "r") as f:
    code = f.read()

# Remove the broken top-level lines
bad_lines = """# Force Start button for Host
force_start_btn = Button.new()
force_start_btn.text = "FORCE START"
force_start_btn.add_theme_font_size_override("font_size", 18)
force_start_btn.custom_minimum_size = Vector2(200, 45)
force_start_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
force_start_btn.position = Vector2(640 - 210, 360 - 55)
force_start_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
force_start_btn.visible = false
add_child(force_start_btn)
force_start_btn.connect("pressed", Callable(self, "_on_force_start_pressed"))
"""

code = code.replace(bad_lines, "")

good_lines = """	# Force Start button for Host
	force_start_btn = Button.new()
	force_start_btn.text = "FORCE START"
	force_start_btn.add_theme_font_size_override("font_size", 18)
	force_start_btn.custom_minimum_size = Vector2(200, 45)
	force_start_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	force_start_btn.position = Vector2(640 - 210, 360 - 55)
	force_start_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	force_start_btn.visible = false
	add_child(force_start_btn)
	force_start_btn.connect("pressed", Callable(self, "_on_force_start_pressed"))
"""

code = code.replace("_update_roster()\n\nfunc _on_connected", "_update_roster()\n\n" + good_lines + "\nfunc _on_connected")

with open("scripts/character_select.gd", "w") as f:
    f.write(code)


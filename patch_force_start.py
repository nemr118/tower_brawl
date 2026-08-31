with open("scripts/character_select.gd", "r") as f:
    code = f.read()

code = code.replace("var name_input_ui: Control", """var name_input_ui: Control
var force_start_btn: Button""")

code = code.replace("""	Global.connect("net_opponent_locked_in", Callable(self, "_on_opponent_locked_in"))""", """	Global.connect("net_opponent_locked_in", Callable(self, "_on_opponent_locked_in"))
	Global.connect("net_force_start", Callable(self, "_on_net_force_start"))""")

code = code.replace("""func _setup_name_input_ui():""", """
	# Force Start button for Host
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

func _setup_name_input_ui():""")

code = code.replace("""func _check_all_ready():
	var active_count = 0
	var locked_count = 0
	
	for p_id in active_player_ids:
		active_count += 1
		if p_id in locked_players:
			locked_count += 1
			
	print("📊 Lobby Status: ", locked_count, "/", active_count, " locked in.")
	
	if active_count >= 2 and locked_count >= active_count and not is_revealing:
		is_revealing = true
		_start_reveal_countdown(active_count)""", """func _check_all_ready():
	var active_count = 0
	var locked_count = 0
	
	for p_id in active_player_ids:
		active_count += 1
		if p_id in locked_players:
			locked_count += 1
			
	print("📊 Lobby Status: ", locked_count, "/", active_count, " locked in.")
	
	if local_player_id == 1 and force_start_btn:
		force_start_btn.visible = (locked_count >= 2 and locked_count < active_count and not is_revealing)
	
	if active_count >= 2 and locked_count >= active_count and not is_revealing:
		_trigger_start(active_count)

func _on_force_start_pressed():
	Global.send_net_data({"type": "force_start"})
	_trigger_start(locked_players.size())

func _on_net_force_start():
	if not is_revealing:
		_trigger_start(locked_players.size())

func _trigger_start(player_count: int):
	is_revealing = true
	if force_start_btn:
		force_start_btn.visible = false
		
	# Kick inactive players who didn't lock in
	var final_active = []
	for p_id in active_player_ids:
		if p_id in locked_players:
			final_active.append(p_id)
		else:
			Global.player_configs[p_id]["active"] = false
			
	active_player_ids = final_active
	_update_roster()
	_start_reveal_countdown(player_count)""")

with open("scripts/character_select.gd", "w") as f:
    f.write(code)

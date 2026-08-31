import re

# 1. Update global.gd
with open("scripts/global.gd", "r") as f:
    g_code = f.read()

g_code = g_code.replace("var locked_opponents: Dictionary = {}", """var locked_opponents: Dictionary = {}
var player_names: Dictionary = {}
var my_player_name: String = ""

signal net_names_updated()""")

# In _handle_net_packet
g_code = g_code.replace("""	if type == "assign_id":""", """	if type in ["assign_id", "player_joined", "player_left", "name_update"]:
		if data.has("player_names"):
			player_names.clear()
			var p_names = data.get("player_names", {})
			for p_str in p_names:
				player_names[int(p_str)] = str(p_names[p_str])
		emit_signal("net_names_updated")
		
	if type == "assign_id":""")

g_code += """
func _save_player_name(n: String):
	my_player_name = n
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('towerbrawl_name', '" + n.replace("'", "\\'") + "')", true)

func _load_saved_player_name() -> String:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("localStorage.getItem('towerbrawl_name')", true)
		if val != null and str(val) != "null" and str(val) != "":
			return str(val)
	return ""
"""

with open("scripts/global.gd", "w") as f:
    f.write(g_code)


# 2. Update serve_game.py
with open("serve_game.py", "r") as f:
    s_code = f.read()

s_code = s_code.replace("player_locked = {}", """player_locked = {}
player_names  = {}""")

s_code = s_code.replace("""        if hello_msg:
            hello = json.loads(hello_msg)
            if hello.get("type") == "hello":
                reclaim_id = int(hello.get("reclaim_id", 0))""", """        if hello_msg:
            hello = json.loads(hello_msg)
            if hello.get("type") == "hello":
                reclaim_id = int(hello.get("reclaim_id", 0))
                if "name" in hello and hello["name"]:
                    with lobby_lock:
                        player_names[reclaim_id] = str(hello["name"])[:12]""")

s_code = s_code.replace("""    with lobby_lock:
        active = [i+1 for i in range(4) if player_slots[i]]
        locked = {str(k): v for k, v in player_locked.items()}""", """    with lobby_lock:
        active = [i+1 for i in range(4) if player_slots[i]]
        locked = {str(k): v for k, v in player_locked.items()}
        names  = {str(k): v for k, v in player_names.items()}""")

s_code = s_code.replace("""        "active_players": active,
        "locked_players": locked,
    }))""", """        "active_players": active,
        "locked_players": locked,
        "player_names": names,
    }))""")

s_code = s_code.replace("""        "active_players": active,
    }), exclude=sock)""", """        "active_players": active,
        "player_names": names,
    }), exclude=sock)""")

s_code = s_code.replace("""            try:
                data = json.loads(msg)
                if data.get("type") == "lock_in":""", """            try:
                data = json.loads(msg)
                if data.get("type") == "set_name":
                    with lobby_lock:
                        player_names[assigned_id] = str(data.get("name", ""))[:12]
                    broadcast(json.dumps({
                        "type": "name_update",
                        "player_names": {str(k): v for k, v in player_names.items()}
                    }))
                    continue
                if data.get("type") == "lock_in":""")

s_code = s_code.replace("""        if player_slots[assigned_id - 1] and player_slots[assigned_id - 1]["sock"] is sock:
            player_slots[assigned_id - 1] = None
        player_locked.pop(assigned_id, None)""", """        if player_slots[assigned_id - 1] and player_slots[assigned_id - 1]["sock"] is sock:
            player_slots[assigned_id - 1] = None
        player_locked.pop(assigned_id, None)
        player_names.pop(assigned_id, None)""")


with open("serve_game.py", "w") as f:
    f.write(s_code)


# 3. Update character_select.gd
with open("scripts/character_select.gd", "r") as f:
    c_code = f.read()

c_code = c_code.replace("var is_revealing: bool = false", """var is_revealing: bool = false
var is_name_set: bool = false
var name_input_ui: Control""")

c_code = c_code.replace("""	Global.connect("net_opponent_locked_in", Callable(self, "_on_opponent_locked_in"))""", """	Global.connect("net_opponent_locked_in", Callable(self, "_on_opponent_locked_in"))
	Global.connect("net_names_updated", Callable(self, "_update_roster"))
	_setup_name_input_ui()""")

c_code = c_code.replace("""func _input(event):
	if is_revealing:
		return""", """func _input(event):
	if not is_name_set or is_revealing:
		return""")

c_code = c_code.replace("""func _update_player_card(card: Control, p_id: int):""", """func _update_player_card(card: Control, p_id: int):
	var display_name = Global.player_names.get(p_id, "Player " + str(p_id))""")

c_code = c_code.replace("""	if not is_active:
		card.color = Color(0.08, 0.08, 0.12, 0.4)
		name_lbl.text = "Player " + str(p_id)""", """	if not is_active:
		card.color = Color(0.08, 0.08, 0.12, 0.4)
		name_lbl.text = "Player " + str(p_id)""") # keep as is

c_code = c_code.replace("""	card.color = Color(0.15, 0.15, 0.22, 0.9)
	name_lbl.modulate = Color(1.0, 1.0, 1.0)
	name_lbl.text = "Player " + str(p_id) + (" (You)" if p_id == local_player_id else "")""", """	card.color = Color(0.15, 0.15, 0.22, 0.9)
	name_lbl.modulate = Color(1.0, 1.0, 1.0)
	name_lbl.text = display_name + (" (You)" if p_id == local_player_id else "")""")

c_code += """
func _setup_name_input_ui():
	var saved_name = Global._load_saved_player_name()
	if saved_name != "":
		_confirm_name(saved_name)
		return

	is_name_set = false
	name_input_ui = ColorRect.new()
	name_input_ui.color = Color(0, 0, 0, 0.85)
	name_input_ui.set_anchors_preset(PRESET_FULL_RECT)
	add_child(name_input_ui)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.set_anchors_preset(PRESET_CENTER)
	name_input_ui.add_child(vbox)

	var lbl = Label.new()
	lbl.text = "ENTER YOUR NAME:"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 24)
	vbox.add_child(lbl)

	var edit = LineEdit.new()
	edit.placeholder_text = "Player"
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.custom_minimum_size = Vector2(240, 40)
	edit.max_length = 12
	vbox.add_child(edit)
	edit.grab_focus()

	var btn = Button.new()
	btn.text = "JOIN BRAWL"
	btn.custom_minimum_size = Vector2(240, 50)
	vbox.add_child(btn)

	btn.connect("pressed", Callable(self, "_on_name_submit").bind(edit))
	edit.connect("text_submitted", Callable(self, "_on_name_submit_text"))

func _on_name_submit_text(t: String):
	_on_name_submit(name_input_ui.get_node("VBoxContainer/LineEdit"))

func _on_name_submit(edit: LineEdit):
	var n = edit.text.strip_edges()
	if n == "":
		n = "Player"
	_confirm_name(n)
	if name_input_ui:
		name_input_ui.queue_free()
		name_input_ui = null

func _confirm_name(n: String):
	is_name_set = true
	Global._save_player_name(n)
	Global.send_net_data({"type": "set_name", "name": n})
	_update_roster()
"""
with open("scripts/character_select.gd", "w") as f:
    f.write(c_code)

# 4. Update arena.gd
with open("scripts/arena.gd", "r") as f:
    a_code = f.read()

a_code = a_code.replace("""	var victim_name = "Player " + str(victim_id)
	var killer_name = "Player " + str(killer_id)""", """	var victim_name = Global.player_names.get(victim_id, "Player " + str(victim_id))
	var killer_name = Global.player_names.get(killer_id, "Player " + str(killer_id))""")

a_code = a_code.replace("""		var txt = "👑 " + ("YOU WON THE MATCH!" if is_me else "PLAYER " + str(winner_id) + " (" + winner_class + ") WINS THE MATCH!") + " 👑"
	else:
		var txt = "👑 " + ("YOU WON ROUND " + str(current_round) + "!" if is_me else "PLAYER " + str(winner_id) + " (" + winner_class + ") WINS ROUND " + str(current_round) + "!") + " 👑\"""", """		var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
		var txt = "👑 " + ("YOU WON THE MATCH!" if is_me else w_name + " (" + winner_class + ") WINS THE MATCH!") + " 👑"
	else:
		var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
		var txt = "👑 " + ("YOU WON ROUND " + str(current_round) + "!" if is_me else w_name + " (" + winner_class + ") WINS ROUND " + str(current_round) + "!") + " 👑\"""")

a_code = a_code.replace("""	name_lbl.text = "P" + str(p_id) + (" (You)" if p_id == Global.my_player_id else "") + " " + c_info["icon"]""", """	var disp_name = Global.player_names.get(p_id, "P" + str(p_id))
	name_lbl.text = disp_name + (" (You)" if p_id == Global.my_player_id else "") + " " + c_info["icon"]""")


with open("scripts/arena.gd", "w") as f:
    f.write(a_code)

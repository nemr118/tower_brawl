# ==============================================================================
# CHARACTER_SELECT.GD (The Waiting Room)
# ==============================================================================
# This script powers the menu screen you see before the fight starts.
# It uses UI (User Interface) elements like Labels and Buttons.
# When everyone is "locked in", it tells Godot to switch to the Arena scene!
# ==============================================================================

extends Control

## Dynamic 4-Player Secret Character Selection Draft Screen

var local_player_id: int = 1
var selected_class_idx: int = 0
var is_locked_in: bool = false
var locked_players = {}
var active_player_ids: Array[int] = []
var is_revealing: bool = false
var is_name_set: bool = false
var name_input_ui: Control
var force_start_btn: Button

@onready var title_label = $CardShowcase/ChampionTitle
@onready var name_label = $CardShowcase/ChampionName
@onready var desc_label = $CardShowcase/ChampionDesc
@onready var primary_label = $CardShowcase/Skills/PrimaryLabel
@onready var special_label = $CardShowcase/Skills/SpecialLabel
@onready var lock_btn = $CardShowcase/LockInButton
@onready var banner_label = $RevealBanner/BannerLabel

@onready var p1_card = $Roster/P1Card
@onready var p2_card = $Roster/P2Card
@onready var p3_card = $Roster/P3Card
@onready var p4_card = $Roster/P4Card

const CHAMPION_KEYS = [
	Global.ClassType.RANGER,
	Global.ClassType.KNIGHT,
	Global.ClassType.MAGE,
	Global.ClassType.ROGUE,
	Global.ClassType.DRUID
]

const SKILL_DETAILS = {
	Global.ClassType.RANGER: {
		"primary": "🏹 Precision Bow (3 Arrows - Pluck to reload, dash to catch)",
		"special": "💨 Backflip Retreat Shot (Vaults backward while shooting forward)"
	},
	Global.ClassType.KNIGHT: {
		"primary": "⚔️ Broadsword Slash (Heavy melee arc destroys projectiles)",
		"special": "🛡️ Shield Parry (Reflects incoming arrows & firebolts at attacker)"
	},
	Global.ClassType.MAGE: {
		"primary": "🔮 Arcane Firebolt (3 Exploding fire charges)",
		"special": "Void Blink (Instantaneous 95px teleport in aim direction)"
	},
	Global.ClassType.ROGUE: {
		"primary": "🗡️ Thrown Kunai (4 Rapid throwing blades)",
		"special": "🌑 Shadow Ambush (Hyper-dash slices through all enemies)"
	},
	Global.ClassType.DRUID: {
		"primary": "🌿 Nature's Thorns / Bear Swipe",
		"special": "🐻 Toggle Bear Form (Ground) / 🥚 Phoenix Shield (Air)"
	}
}

func _ready():
	# UI Hooks for IconTex
	var show_tr = TextureRect.new()
	show_tr.name = "IconTex"
	show_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	show_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	show_tr.size = Vector2(40, 40)
	show_tr.position = Vector2(20, 2)
	name_label.get_parent().add_child(show_tr)
	name_label.get_parent().move_child(show_tr, name_label.get_index())

	for p_card in [$Roster/P1Card, $Roster/P2Card, $Roster/P3Card, $Roster/P4Card]:
		var old_icon = p_card.get_node("Icon")
		var tr = TextureRect.new()
		tr.name = "IconTex"
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.position = old_icon.position
		tr.size = Vector2(30, 30)
		p_card.add_child(tr)
		old_icon.visible = false

	local_player_id = Global.my_player_id
	active_player_ids = Global.active_players.duplicate()
	locked_players = Global.locked_opponents.duplicate()
	
	Global.connect("net_connected", Callable(self, "_on_connected_to_server"))
	Global.connect("net_player_joined", Callable(self, "_on_player_joined"))
	Global.connect("net_player_left", Callable(self, "_on_player_left"))
	Global.connect("net_opponent_locked_in", Callable(self, "_on_opponent_locked_in"))
	Global.connect("net_force_start", Callable(self, "_on_net_force_start"))
	Global.connect("net_names_updated", Callable(self, "_update_roster"))
	_setup_name_input_ui()
	
	_sync_global_configs()
	_update_showcase()
	_update_roster()

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

func _on_connected_to_server(p_id: int):
	local_player_id = p_id
	print("🎯 Local player assigned to Slot P", local_player_id)
	_sync_global_configs()
	_update_roster()

func _on_player_joined(p_id: int, active_list):
	print("👋 Player ", p_id, " joined the match room! Active: ", active_list)
	active_player_ids.clear()
	for x in active_list:
		active_player_ids.append(int(x))
	if not active_player_ids.has(local_player_id):
		active_player_ids.append(local_player_id)
		
	_sync_global_configs()
	_update_roster()
	_check_all_ready()

func _on_player_left(p_id: int, active_list):
	print("🚪 Player ", p_id, " left the room. Active: ", active_list)
	active_player_ids.clear()
	for x in active_list:
		active_player_ids.append(int(x))
	if not active_player_ids.has(local_player_id):
		active_player_ids.append(local_player_id)
		
	if p_id in locked_players:
		locked_players.erase(p_id)
		
	_sync_global_configs()
	_update_roster()
	_check_all_ready()

func _sync_global_configs():
	for p_id in range(1, 5):
		Global.player_configs[p_id]["active"] = (p_id in active_player_ids or p_id == local_player_id)

func _on_opponent_locked_in(opp_id: int, opp_class: int):
	print("🔒 Opponent P", opp_id, " locked in secretly with class: ", opp_class)
	Global.player_configs[opp_id]["class"] = opp_class
	locked_players[opp_id] = opp_class
	_update_roster()
	_check_all_ready()

func _input(event):
	if not is_name_set or is_revealing:
		return
		
	var prefix = "p" + str(local_player_id) + "_"
	
	if not is_locked_in:
		if event.is_action_pressed(prefix + "left") or event.is_action_pressed("ui_left"):
			_cycle_selection(-1)
		elif event.is_action_pressed(prefix + "right") or event.is_action_pressed("ui_right"):
			_cycle_selection(1)
		elif event.is_action_pressed(prefix + "jump") or event.is_action_pressed(prefix + "attack") or event.is_action_pressed("ui_accept"):
			# Ignore mouse clicks for shortcuts so they don't instantly lock when clicking 'Next'
			if not (event is InputEventMouseButton):
				_lock_in_champion()

func _cycle_selection(dir: int):
	selected_class_idx = (selected_class_idx + dir + CHAMPION_KEYS.size()) % CHAMPION_KEYS.size()
	_update_showcase()

func _update_showcase():
	var c_type = CHAMPION_KEYS[selected_class_idx]
	var c_info = Global.CLASS_INFO[c_type]
	var s_info = SKILL_DETAILS[c_type]
	
	name_label.text = c_info["name"].to_upper()
	if c_info.has("icon_tex"):
		name_label.get_parent().get_node("IconTex").texture = load(c_info["icon_tex"])
	name_label.modulate = c_info["color"]
	desc_label.text = c_info["desc"]
	primary_label.text = s_info["primary"]
	special_label.text = s_info["special"]

func _lock_in_champion():
	is_locked_in = true
	var chosen_class = CHAMPION_KEYS[selected_class_idx]
	Global.player_configs[local_player_id]["class"] = chosen_class
	locked_players[local_player_id] = chosen_class
	
	lock_btn.text = "CHAMPION LOCKED IN!"
	lock_btn.disabled = true
	lock_btn.modulate = Color(0.4, 0.9, 0.4)
	
	Global.send_net_data({
		"type": "lock_in",
		"class": chosen_class
	})
	
	_update_roster()
	_check_all_ready()

func _update_roster():
	_update_player_card(p1_card, 1)
	_update_player_card(p2_card, 2)
	_update_player_card(p3_card, 3)
	_update_player_card(p4_card, 4)

func _update_player_card(card: Control, p_id: int):
	var is_active = (p_id in active_player_ids or p_id == local_player_id)
	
	var display_name = Global.player_names.get(p_id, "Player " + str(p_id))
	if p_id == local_player_id and Global.my_player_name != "":
		display_name = Global.my_player_name
		
	var name_lbl = card.get_node("Name")
	var status_lbl = card.get_node("Status")
	var icon_lbl = card.get_node_or_null("Icon")
	
	if not is_active:
		card.color = Color(0.08, 0.08, 0.12, 0.4)
		name_lbl.text = "Player " + str(p_id)
		name_lbl.modulate = Color(0.4, 0.4, 0.4)
		if card.has_node("IconTex"): card.get_node("IconTex").texture = load("res://assets/icons/empty.jpg")
		status_lbl.text = "Empty Slot"
		status_lbl.modulate = Color(0.35, 0.35, 0.35)
		return
		
	card.color = Color(0.15, 0.15, 0.22, 0.9)
	name_lbl.modulate = Color(1.0, 1.0, 1.0)
	name_lbl.text = display_name + (" (You)" if p_id == local_player_id else "")
	
	if p_id in locked_players:
		if p_id == local_player_id or is_revealing:
			var c_type = locked_players[p_id]
			var c_info = Global.CLASS_INFO[c_type]
			if card.has_node("IconTex"): card.get_node("IconTex").texture = load(c_info["icon_tex"])
			status_lbl.text = c_info["name"].to_upper()
			status_lbl.modulate = c_info["color"]
		else:
			if card.has_node("IconTex"): card.get_node("IconTex").texture = load("res://assets/icons/locked.jpg")
			status_lbl.text = "READY (SECRET)"
			status_lbl.modulate = Color(1.0, 0.85, 0.3)
	else:
		if p_id == local_player_id:
			var cur_c_type = CHAMPION_KEYS[selected_class_idx]
			var cur_c_info = Global.CLASS_INFO[cur_c_type]
			if card.has_node("IconTex"): card.get_node("IconTex").texture = load(cur_c_info["icon_tex"])
			status_lbl.text = "Selecting..."
			status_lbl.modulate = Color(0.9, 0.9, 0.9)
		else:
			if card.has_node("IconTex"): card.get_node("IconTex").texture = load("res://assets/icons/waiting.jpg")
			status_lbl.text = "Choosing..."
			status_lbl.modulate = Color(0.6, 0.6, 0.6)

func _check_all_ready():
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
	var final_active: Array[int] = []
	for p_id in active_player_ids:
		if p_id in locked_players:
			final_active.append(p_id)
		else:
			Global.player_configs[p_id]["active"] = false
			
	active_player_ids = final_active
	_update_roster()
	_start_reveal_countdown(player_count)

func _start_reveal_countdown(player_count: int):
	banner_label.visible = true
	var count_str = str(player_count) + "-PLAYER BATTLE"
	banner_label.text = "" + count_str + " READY! ⚡\nRevealing Champions in 3..."
	await get_tree().create_timer(1.0).timeout
	banner_label.text = "" + count_str + " READY! ⚡\nRevealing Champions in 2..."
	await get_tree().create_timer(1.0).timeout
	banner_label.text = "" + count_str + " READY! ⚡\nRevealing Champions in 1..."
	await get_tree().create_timer(1.0).timeout
	
	banner_label.text = "CHAMPIONS REVEALED! ENTERING ARENA! 💥"
	_update_roster()
	
	await get_tree().create_timer(1.6).timeout
	get_tree().change_scene_to_file("res://scenes/arena.tscn")

func _on_lock_in_button_pressed():
	if not is_locked_in:
		_lock_in_champion()

func _on_btn_prev_pressed():
	if not is_locked_in:
		_cycle_selection(-1)

func _on_btn_next_pressed():
	if not is_locked_in:
		_cycle_selection(1)



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
	_confirm_name_and_close(t)

func _on_name_submit(edit: LineEdit):
	_confirm_name_and_close(edit.text)
	
func _confirm_name_and_close(text_val: String):
	var n = text_val.strip_edges()
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

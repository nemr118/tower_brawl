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
		"primary": "Precision Bow (3 Arrows - Pluck to reload, dash to catch)",
		"special": "Backflip Retreat Shot (Vaults backward while shooting forward)"
	},
	Global.ClassType.KNIGHT: {
		"primary": "Broadsword Slash (Heavy melee arc destroys projectiles)",
		"special": "Shield Parry (Reflects incoming arrows & firebolts at attacker)"
	},
	Global.ClassType.MAGE: {
		"primary": "Arcane Firebolt (3 Exploding fire charges)",
		"special": "Void Blink (Instantaneous 95px teleport in aim direction)"
	},
	Global.ClassType.ROGUE: {
		"primary": "Thrown Kunai (4 Rapid throwing blades)",
		"special": "Shadow Ambush (Hyper-dash slices through all enemies)"
	},
	Global.ClassType.DRUID: {
		"primary": "Nature's Thorns / Bear Swipe",
		"special": "Toggle Bear Form (Ground) / Phoenix Shield (Air)"
	}
}

# Global signal -> handler. Connected in _ready, disconnected in _exit_tree so a
# lobby that has been replaced by the arena (removed, not yet freed) never handles
# a packet on a node with no tree. Same pattern as arena.gd.
const NET_SIGNAL_HANDLERS = {
	"net_connected": "_on_connected_to_server",
	"net_player_joined": "_on_player_joined",
	"net_player_left": "_on_player_left",
	"net_opponent_locked_in": "_on_opponent_locked_in",
	"net_force_start": "_on_net_force_start",
	"net_names_updated": "_update_roster",
	"net_version_error": "_on_net_version_error",
	"net_harness_status": "_on_harness_status",
	"net_join_locked": "_on_join_locked",
}

const HarnessTickerScript = preload("res://scripts/harness_ticker.gd")
const FontWarmupScript = preload("res://scripts/font_warmup.gd")

# v0.1.2 (cut 1): every icon this screen can show, loaded once with the script.
# The story: _update_player_card() called load() on a 1024 px icon every time the
# roster changed. An icon no card held yet (the "locked" one at the first lock,
# the other player's class at the reveal) was read out of the .pck and pushed to
# the GPU on that frame: the S25 Ultra's 21 to 35 ms lobby frames and its two
# 50 ms+ hitches at the locks. Now the icons are 256 px (assets/icons/*.import,
# size_limit) and already in memory, and a card's texture is only swapped when
# it changes.
const ICON_TEX := {
	"res://assets/icons/empty.jpg": preload("res://assets/icons/empty.jpg"),
	"res://assets/icons/locked.jpg": preload("res://assets/icons/locked.jpg"),
	"res://assets/icons/waiting.jpg": preload("res://assets/icons/waiting.jpg"),
	"res://assets/icons/ranger.jpg": preload("res://assets/icons/ranger.jpg"),
	"res://assets/icons/knight.jpg": preload("res://assets/icons/knight.jpg"),
	"res://assets/icons/pyro.jpg": preload("res://assets/icons/pyro.jpg"),
	"res://assets/icons/rogue.jpg": preload("res://assets/icons/rogue.jpg"),
	"res://assets/icons/druid.jpg": preload("res://assets/icons/druid.jpg"),
	"res://assets/icons/primary.jpg": preload("res://assets/icons/primary.jpg"),
	"res://assets/icons/special.jpg": preload("res://assets/icons/special.jpg"),
	"res://assets/icons/skill_ranger_1.jpg": preload("res://assets/icons/skill_ranger_1.jpg"),
	"res://assets/icons/skill_ranger_2.jpg": preload("res://assets/icons/skill_ranger_2.jpg"),
	"res://assets/icons/skill_knight_1.jpg": preload("res://assets/icons/skill_knight_1.jpg"),
	"res://assets/icons/skill_knight_2.jpg": preload("res://assets/icons/skill_knight_2.jpg"),
	"res://assets/icons/skill_mage_1.jpg": preload("res://assets/icons/skill_mage_1.jpg"),
	"res://assets/icons/skill_mage_2.jpg": preload("res://assets/icons/skill_mage_2.jpg"),
	"res://assets/icons/skill_pyro_1.jpg": preload("res://assets/icons/skill_pyro_1.jpg"),
	"res://assets/icons/skill_pyro_2.jpg": preload("res://assets/icons/skill_pyro_2.jpg"),
	"res://assets/icons/skill_rogue_1.jpg": preload("res://assets/icons/skill_rogue_1.jpg"),
	"res://assets/icons/skill_rogue_2.jpg": preload("res://assets/icons/skill_rogue_2.jpg"),
	"res://assets/icons/skill_druid_1.jpg": preload("res://assets/icons/skill_druid_1.jpg"),
	"res://assets/icons/skill_druid_2.jpg": preload("res://assets/icons/skill_druid_2.jpg"),
}


func _tex(path: String) -> Texture2D:
	if path in ICON_TEX:
		return ICON_TEX[path]
	push_warning("character_select: icon not in ICON_TEX, loading now: " + path)
	return load(path)


func _set_tex(node: TextureRect, path: String) -> void:
	var t := _tex(path)
	if node.texture != t:
		node.texture = t

func _exit_tree():
	for sig_name in NET_SIGNAL_HANDLERS:
		var sig := Signal(Global, sig_name)
		var handler := Callable(self, NET_SIGNAL_HANDLERS[sig_name])
		if sig.is_connected(handler):
			sig.disconnect(handler)

func _ready():

	# Primary Icon
	var p_icon = TextureRect.new()
	p_icon.name = "PrimaryIcon"
	p_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	p_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	p_icon.size = Vector2(18, 18)
	p_icon.position = Vector2(-28, -2)
	_set_tex(p_icon, "res://assets/icons/primary.jpg")
	primary_label.add_child(p_icon)

	# Special Icon
	var s_icon = TextureRect.new()
	s_icon.name = "SpecialIcon"
	s_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	s_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	s_icon.size = Vector2(18, 18)
	s_icon.position = Vector2(-28, -2)
	_set_tex(s_icon, "res://assets/icons/special.jpg")
	special_label.add_child(s_icon)
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
	
	for sig_name in NET_SIGNAL_HANDLERS:
		Global.connect(sig_name, Callable(self, NET_SIGNAL_HANDLERS[sig_name]))
	_setup_name_input_ui()
	
	_sync_global_configs()
	_update_showcase()
	_update_roster()
	# v0.1.2 (cut 1): draw the glyphs the lobby's labels use once, off-screen, now.
	if Global.warm_enabled:
		add_child(FontWarmupScript.new([[16, 4], [10, 2], [18, 0], [16, 0]]))

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
	
	# Unobtrusive Join Button
	var join_btn = Button.new()
	join_btn.name = "JoinBtn"
	join_btn.text = "JOIN MATCH"
	join_btn.add_theme_font_size_override("font_size", 32)
	join_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	join_btn.custom_minimum_size = Vector2(250, 60)
	join_btn.connect("pressed", Callable(self, "_on_join_pressed"))
	join_btn.z_index = 100
	add_child(join_btn)
	
	var spectate_btn = Button.new()
	spectate_btn.name = "SpectateBtn"
	spectate_btn.text = "Spectate"
	spectate_btn.add_theme_font_size_override("font_size", 24)
	spectate_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	spectate_btn.connect("pressed", Callable(self, "_on_spectate_pressed"))
	spectate_btn.z_index = 100
	add_child(spectate_btn)

	# v0.0.19: change your name without reloading the page.
	var name_btn = Button.new()
	name_btn.name = "ChangeNameBtn"
	name_btn.text = "CHANGE NAME"
	name_btn.add_theme_font_size_override("font_size", 14)
	name_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	name_btn.position = Vector2(0, 64)
	name_btn.custom_minimum_size = Vector2(130, 30)
	name_btn.connect("pressed", Callable(self, "_on_change_name_pressed"))
	name_btn.z_index = 100
	add_child(name_btn)
	
	# v0.0.23: the test ticker sits where JOIN MATCH sits. Only one of them shows.
	var ticker = HarnessTickerScript.new(false)
	ticker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ticker.position = Vector2(0, 0)
	ticker.custom_minimum_size = Vector2(250, 60)
	add_child(ticker)

	_update_roster()

func _on_harness_status(_info: Dictionary):
	# The gate closed or opened: show or hide JOIN MATCH and LOCK IN.
	_update_roster()

func _on_join_locked(_demoted: bool, _old_id: int):
	# The server kept our seat for the tests. We are a spectator now.
	local_player_id = 0
	_sync_global_configs()
	_update_roster()

func _on_connected_to_server(p_id: int):
	local_player_id = p_id
	print("🎯 Local player assigned to Slot P", local_player_id)
	_sync_global_configs()
	_update_roster()

func _on_player_joined(p_id: int, active_list):
	print("👋 Player ", p_id, " joined the match room! Active: ", active_list)
	_sync_global_configs()
	_update_roster()
	_check_all_ready()

func _on_player_left(p_id: int, active_list):
	print("🚪 Player ", p_id, " left the room. Active: ", active_list)
	_sync_global_configs()
	_update_roster()
	_check_all_ready()

func _sync_global_configs():
	for p_id in range(1, 5):
		Global.player_configs[p_id]["active"] = (p_id in Global.active_players)

var version_error_label: Label = null

func _on_net_version_error(server_version: String):
	# The server refused request_join: this browser is running a cached .pck.
	# Say so on screen; the console line alone is invisible on a phone.
	if version_error_label == null:
		version_error_label = Label.new()
		version_error_label.name = "VersionErrorLabel"
		version_error_label.add_theme_font_size_override("font_size", 16)
		version_error_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
		version_error_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		version_error_label.add_theme_constant_override("outline_size", 4)
		version_error_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		version_error_label.position = Vector2(20, 66)
		version_error_label.size = Vector2(600, 60)
		version_error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		version_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		version_error_label.z_index = 200
		add_child(version_error_label)
	version_error_label.text = ("UPDATE REQUIRED: this build is " + Global.GAME_VERSION
		+ " but the server runs " + server_version + ".\nReload the page to get the new version.")
	version_error_label.visible = true
	var j_btn = get_node_or_null("JoinBtn")
	if j_btn:
		j_btn.text = "RELOAD TO JOIN"
		j_btn.disabled = true

func _on_opponent_locked_in(opp_id: int, opp_class: int):
	print("🔒 Opponent P", opp_id, " locked in secretly with class: ", opp_class)
	Global.player_configs[opp_id]["class"] = opp_class
	Global.locked_opponents[opp_id] = opp_class
	_update_roster()
	_check_all_ready()

func _input(event):
	if not is_name_set or is_revealing or local_player_id <= 0:
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
		_set_tex(name_label.get_parent().get_node("IconTex"), c_info["icon_tex"])
	name_label.modulate = c_info["color"]
	desc_label.text = c_info["desc"]
	primary_label.text = s_info["primary"]
	special_label.text = s_info["special"]
	
	var p_icon = primary_label.get_node_or_null("PrimaryIcon")
	if p_icon and c_info.has("primary_icon"):
		_set_tex(p_icon, c_info["primary_icon"])
		
	var s_icon = special_label.get_node_or_null("SpecialIcon")
	if s_icon and c_info.has("special_icon"):
		_set_tex(s_icon, c_info["special_icon"])

func _lock_in_champion():
	if local_player_id <= 0:
		return
	is_locked_in = true
	var chosen_class = CHAMPION_KEYS[selected_class_idx]
	Global.player_configs[local_player_id]["class"] = chosen_class
	Global.locked_opponents[local_player_id] = chosen_class
	
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
	var j_btn = get_node_or_null("JoinBtn")
	var s_btn = get_node_or_null("SpectateBtn")
	var seated := not Global.is_spectator and Global.my_player_id > 0 and Global.my_player_id in Global.active_players
	var locked := bool(Global.harness_info.get("active", false))   # v0.0.23: tests running, JOIN hidden
	if seated:
		if j_btn: j_btn.visible = false
		if s_btn: s_btn.visible = true
	else:
		if j_btn: j_btn.visible = not locked
		if s_btn: s_btn.visible = false
		
	if lock_btn:
		lock_btn.visible = seated and not locked
		
	_update_player_card(p1_card, 1)
	_update_player_card(p2_card, 2)
	_update_player_card(p3_card, 3)
	_update_player_card(p4_card, 4)

func _update_player_card(card: Control, p_id: int):
	var is_active = (p_id in Global.active_players)
	
	# The server owns the names (v0.0.19): if your name was taken it comes back
	# as "Tav-2", and you should see that too. Your typed name is only the
	# fallback until the server has answered.
	var display_name = Global.player_names.get(p_id, "Player " + str(p_id))
	if p_id == local_player_id and Global.my_player_name != "" and not Global.player_names.has(p_id):
		display_name = Global.my_player_name
		
	var name_lbl = card.get_node("Name")
	var status_lbl = card.get_node("Status")
	var icon_lbl = card.get_node_or_null("Icon")
	
	if not is_active:
		card.color = Color(0.08, 0.08, 0.12, 0.4)
		name_lbl.text = "Player " + str(p_id)
		name_lbl.modulate = Color(0.4, 0.4, 0.4)
		if card.has_node("IconTex"): _set_tex(card.get_node("IconTex"), "res://assets/icons/empty.jpg")
		status_lbl.text = "Empty Slot"
		status_lbl.modulate = Color(0.35, 0.35, 0.35)
		return
		
	card.color = Color(0.15, 0.15, 0.22, 0.9)
	name_lbl.modulate = Color(1.0, 1.0, 1.0)
	name_lbl.text = display_name + (" (You)" if (p_id == local_player_id and not Global.is_spectator) else "")
	
	if p_id in Global.locked_opponents:
		if (p_id == local_player_id and not Global.is_spectator) or is_revealing:
			var c_type = Global.locked_opponents[p_id]
			var c_info = Global.CLASS_INFO[c_type]
			if card.has_node("IconTex"): _set_tex(card.get_node("IconTex"), c_info["icon_tex"])
			status_lbl.text = c_info["name"].to_upper()
			status_lbl.modulate = c_info["color"]
		else:
			if card.has_node("IconTex"): _set_tex(card.get_node("IconTex"), "res://assets/icons/locked.jpg")
			status_lbl.text = "READY (SECRET)"
			status_lbl.modulate = Color(1.0, 0.85, 0.3)
	else:
		if p_id == local_player_id and not Global.is_spectator:
			var cur_c_type = CHAMPION_KEYS[selected_class_idx]
			var cur_c_info = Global.CLASS_INFO[cur_c_type]
			if card.has_node("IconTex"): _set_tex(card.get_node("IconTex"), cur_c_info["icon_tex"])
			status_lbl.text = "Selecting..."
			status_lbl.modulate = Color(0.9, 0.9, 0.9)
		else:
			if card.has_node("IconTex"): _set_tex(card.get_node("IconTex"), "res://assets/icons/waiting.jpg")
			status_lbl.text = "Choosing..."
			status_lbl.modulate = Color(0.6, 0.6, 0.6)

func _check_all_ready():
	var active_count = 0
	var locked_count = 0
	
	for p_id in Global.active_players:
		active_count += 1
		if p_id in Global.locked_opponents:
			locked_count += 1
			
	print("📊 Lobby Status: ", locked_count, "/", active_count, " locked in.")
	
	if local_player_id == 1 and force_start_btn:
		force_start_btn.visible = (locked_count >= 2 and locked_count < active_count and not is_revealing)
	
	if active_count >= 2 and locked_count >= active_count and not is_revealing:
		_trigger_start(active_count)

func _on_force_start_pressed():
	Global.send_net_data({"type": "force_start"})
	_trigger_start(Global.locked_opponents.size())

func _on_net_force_start():
	if not is_revealing:
		_trigger_start(Global.locked_opponents.size())

func _trigger_start(player_count: int):
	is_revealing = true
	if force_start_btn:
		force_start_btn.visible = false
		
	# Kick inactive players who didn't lock in
	var final_active: Array[int] = []
	for p_id in Global.active_players:
		if p_id in Global.locked_opponents:
			final_active.append(p_id)
			Global.player_configs[p_id]["active"] = true
		else:
			Global.player_configs[p_id]["active"] = false
			
	Global.active_players = final_active
	_update_roster()
	_start_reveal_countdown(player_count)

func _start_reveal_countdown(player_count: int):
	banner_label.visible = true
	var count_str = str(player_count) + "-PLAYER BATTLE"
	banner_label.text = "" + count_str + " READY!\nRevealing Champions in 3..."
	await get_tree().create_timer(1.0).timeout
	banner_label.text = "" + count_str + " READY!\nRevealing Champions in 2..."
	await get_tree().create_timer(1.0).timeout
	banner_label.text = "" + count_str + " READY!\nRevealing Champions in 1..."
	await get_tree().create_timer(1.0).timeout
	
	banner_label.text = "CHAMPIONS REVEALED! ENTERING ARENA! "
	_update_roster()
	
	await get_tree().create_timer(1.6).timeout
	
	Global.send_net_data({"type": "match_started"})
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
	_open_name_sheet("", false)

func _open_name_sheet(prefill: String, can_cancel: bool):
	# The name sheet. On the first visit it is the only thing on the screen.
	# v0.0.19: the CHANGE NAME button opens the same sheet again, with your
	# current name filled in and a CANCEL button. While the sheet is open the
	# class-cycling keys are paused (is_name_set is false).
	if name_input_ui:
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
	edit.text = prefill
	vbox.add_child(edit)
	edit.grab_focus()
	edit.caret_column = prefill.length()

	var btn = Button.new()
	btn.text = "SAVE NAME" if can_cancel else "JOIN BRAWL"
	btn.custom_minimum_size = Vector2(240, 50)
	vbox.add_child(btn)

	btn.connect("pressed", Callable(self, "_on_name_submit").bind(edit))
	edit.connect("text_submitted", Callable(self, "_on_name_submit_text"))

	if can_cancel:
		var cancel = Button.new()
		cancel.text = "CANCEL"
		cancel.custom_minimum_size = Vector2(240, 40)
		vbox.add_child(cancel)
		cancel.connect("pressed", Callable(self, "_on_name_cancel"))

func _on_change_name_pressed():
	_open_name_sheet(Global.my_player_name, true)

func _on_name_cancel():
	# Keep the old name. The keys work again.
	is_name_set = true
	if name_input_ui:
		name_input_ui.queue_free()
		name_input_ui = null

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

func _on_join_pressed():
	Global.request_join(Global._load_saved_player_id())

func _on_spectate_pressed():
	Global.send_net_data({"type": "leave_slot"})
	Global.my_player_id = 0
	local_player_id = 0
	
	var j_btn = get_node_or_null("JoinBtn")
	if j_btn:
		j_btn.visible = true
		
	var s_btn = get_node_or_null("SpectateBtn")
	if s_btn:
		s_btn.visible = false
	_update_roster()

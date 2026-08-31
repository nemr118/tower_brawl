extends Control

## Secret Character Selection Draft Screen
## Synchronized in Real-Time over WebSockets across Phones, Tablets, and PCs!

var local_player_id: int = 1
var selected_class_idx: int = 0
var is_locked_in: bool = false
var locked_players = {}
var is_revealing: bool = false

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
	Global.ClassType.ROGUE
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
		"special": "⚡ Void Blink (Instantaneous 95px teleport in aim direction)"
	},
	Global.ClassType.ROGUE: {
		"primary": "🗡️ Thrown Kunai (4 Rapid throwing blades)",
		"special": "🌑 Shadow Ambush (Hyper-dash slices through all enemies)"
	}
}

func _ready():
	local_player_id = NetworkManager.my_player_id
	NetworkManager.connect("connected_to_server", Callable(self, "_on_connected_to_server"))
	NetworkManager.connect("opponent_locked_in", Callable(self, "_on_opponent_locked_in"))
	
	_update_showcase()
	_update_roster()

func _on_connected_to_server(p_id: int):
	local_player_id = p_id
	print("🎯 Character Select updated local_player_id to: ", local_player_id)
	_update_roster()

func _on_opponent_locked_in(opp_id: int, opp_class: int):
	print("🔒 Opponent P", opp_id, " locked in secretly with class: ", opp_class)
	Global.player_configs[opp_id]["class"] = opp_class
	locked_players[opp_id] = opp_class
	_update_roster()
	_check_all_ready()

func _input(event):
	if is_revealing:
		return
		
	var prefix = "p" + str(local_player_id) + "_"
	
	if not is_locked_in:
		if event.is_action_pressed(prefix + "left") or event.is_action_pressed("ui_left"):
			_cycle_selection(-1)
		elif event.is_action_pressed(prefix + "right") or event.is_action_pressed("ui_right"):
			_cycle_selection(1)
		elif event.is_action_pressed(prefix + "jump") or event.is_action_pressed(prefix + "attack") or event.is_action_pressed("ui_accept"):
			_lock_in_champion()

func _cycle_selection(dir: int):
	selected_class_idx = (selected_class_idx + dir + CHAMPION_KEYS.size()) % CHAMPION_KEYS.size()
	_update_showcase()

func _update_showcase():
	var c_type = CHAMPION_KEYS[selected_class_idx]
	var c_info = Global.CLASS_INFO[c_type]
	var s_info = SKILL_DETAILS[c_type]
	
	name_label.text = c_info["icon"] + " " + c_info["name"].to_upper()
	name_label.modulate = c_info["color"]
	title_label.text = "« " + c_info["title"] + " »"
	desc_label.text = c_info["desc"]
	
	primary_label.text = s_info["primary"]
	special_label.text = s_info["special"]

func _lock_in_champion():
	is_locked_in = true
	var chosen_class = CHAMPION_KEYS[selected_class_idx]
	Global.player_configs[local_player_id]["class"] = chosen_class
	locked_players[local_player_id] = chosen_class
	
	lock_btn.text = "✅ CHAMPION LOCKED IN!"
	lock_btn.disabled = true
	lock_btn.modulate = Color(0.4, 0.9, 0.4)
	
	# Broadcast secret lock-in over WebSocket!
	NetworkManager.send_data({
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
	if not Global.player_configs[p_id]["active"]:
		card.visible = false
		return
		
	card.visible = true
	var name_lbl = card.get_node("Name")
	var status_lbl = card.get_node("Status")
	var icon_lbl = card.get_node("Icon")
	
	name_lbl.text = "Player " + str(p_id) + (" (You)" if p_id == local_player_id else "")
	
	if p_id in locked_players:
		if p_id == local_player_id or is_revealing:
			var c_type = locked_players[p_id]
			var c_info = Global.CLASS_INFO[c_type]
			icon_lbl.text = c_info["icon"]
			status_lbl.text = c_info["name"].to_upper()
			status_lbl.modulate = c_info["color"]
		else:
			icon_lbl.text = "🔒"
			status_lbl.text = "READY (SECRET)"
			status_lbl.modulate = Color(1.0, 0.85, 0.3)
	else:
		if p_id == local_player_id:
			var cur_c_type = CHAMPION_KEYS[selected_class_idx]
			var cur_c_info = Global.CLASS_INFO[cur_c_type]
			icon_lbl.text = cur_c_info["icon"]
			status_lbl.text = "Selecting..."
			status_lbl.modulate = Color(0.9, 0.9, 0.9)
		else:
			icon_lbl.text = "⏳"
			status_lbl.text = "Choosing..."
			status_lbl.modulate = Color(0.6, 0.6, 0.6)

func _check_all_ready():
	var all_ready = true
	for p_id in Global.player_configs:
		if Global.player_configs[p_id]["active"] and p_id not in locked_players:
			all_ready = false
			break
			
	if all_ready and not is_revealing:
		is_revealing = true
		_start_reveal_countdown()

func _start_reveal_countdown():
	banner_label.visible = true
	banner_label.text = "⚡ ALL PLAYERS LOCKED IN! ⚡\nRevealing Champions in 3..."
	await get_tree().create_timer(1.0).timeout
	banner_label.text = "⚡ ALL PLAYERS LOCKED IN! ⚡\nRevealing Champions in 2..."
	await get_tree().create_timer(1.0).timeout
	banner_label.text = "⚡ ALL PLAYERS LOCKED IN! ⚡\nRevealing Champions in 1..."
	await get_tree().create_timer(1.0).timeout
	
	banner_label.text = "💥 CHAMPIONS REVEALED! ENTERING ARENA! 💥"
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

# ==============================================================================
# WELCOME TO ARENA.GD! (The Game World Script)
# ==============================================================================
# This script is like the "Game Master" or Referee.
# It doesn't control a single player. Instead, it builds the arena, decides 
# where everyone spawns, keeps score, and drops power-ups from the sky.
# ==============================================================================

extends Node2D

@onready var platforms_node = $Platforms
var powerup_node: Area2D = null
var is_arena_rotating: bool = false

const PlayerScene = preload("res://scenes/player.tscn")

# HUD textures resolved once at load. _update_panel used to call load() for every
# icon on every HUD refresh (each a resource-cache lookup); these are plain constants.
const HEART_TEX = preload("res://assets/icons/heart.jpg")
const CROWN_TEX = preload("res://assets/icons/crown.jpg")
const PICKUP_TEX = preload("res://assets/icons/pickup.jpg")
const CLASS_ICON_TEX = {
	Global.ClassType.RANGER: preload("res://assets/icons/ranger.jpg"),
	Global.ClassType.KNIGHT: preload("res://assets/icons/knight.jpg"),
	Global.ClassType.MAGE: preload("res://assets/icons/pyro.jpg"),
	Global.ClassType.ROGUE: preload("res://assets/icons/rogue.jpg"),
	Global.ClassType.DRUID: preload("res://assets/icons/druid.jpg"),
}

var spawn_points = [
	Vector2(110, 200),
	Vector2(530, 200),
	Vector2(170, 100),
	Vector2(470, 100)
]

var player_stocks = {}
var player_instances = {}
var is_round_over: bool = false
var current_round: int = 1
var pause_overlay: ColorRect

# Global signal -> handler. Connected in _ready, disconnected in _exit_tree.
const NET_SIGNAL_HANDLERS = {
	"net_player_died": "_on_net_player_died",
	"net_round_end": "_on_round_end_sync",
	"net_new_round": "_on_new_round_sync",
	"net_return_to_lobby": "_on_return_to_lobby",
	"net_spawn_powerup": "_on_net_spawn_powerup",
	"net_activate_powerup": "_on_net_activate_powerup",
	"net_version_error": "_on_net_version_error",
	"net_player_joined": "_on_net_player_joined",
}

@onready var hud = $HUD
@onready var banner_label = $HUD/CenterBanner/BannerLabel
@onready var p1_panel = $HUD/TopBar/P1Panel
@onready var p2_panel = $HUD/TopBar/P2Panel
@onready var p3_panel = $HUD/TopBar/P3Panel
@onready var p4_panel = $HUD/TopBar/P4Panel
@onready var touch_controls = $TouchControls


# ------------------------------------------------------------------------------
# SETUP TIME!
# _ready() is a special Godot function that runs exactly ONCE when the 
# level first loads. It's like setting up a board game before you start playing.
# ------------------------------------------------------------------------------
func _ready():
	var leave_btn = Button.new()
	leave_btn.text = "LEAVE MATCH"
	leave_btn.add_theme_font_size_override("font_size", 16)
	leave_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	leave_btn.position = Vector2(get_viewport_rect().size.x - 120, 10)
	leave_btn.connect("pressed", Callable(self, "_on_leave_match_pressed"))
	leave_btn.z_index = 100
	$HUD.add_child(leave_btn)
	if Global.my_player_id == 0:
		leave_btn.visible = false

	for sig_name in NET_SIGNAL_HANDLERS:
		Global.connect(sig_name, Callable(self, NET_SIGNAL_HANDLERS[sig_name]))

	if Global.my_player_id == 1:
		var pt = Timer.new()
		pt.wait_time = 15.0
		pt.autostart = true
		pt.connect("timeout", Callable(self, "_host_spawn_powerup"))
		add_child(pt)
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0, 0, 0, 0.8)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.z_index = 100
	pause_overlay.visible = false
	add_child(pause_overlay)
	
	var spectate_btn = Button.new()
	spectate_btn.text = "SPECTATE (LEAVE MATCH)"
	spectate_btn.add_theme_font_size_override("font_size", 48)
	spectate_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	spectate_btn.connect("pressed", Callable(self, "_on_spectate_pressed"))
	pause_overlay.add_child(spectate_btn)
	
	var join_btn = Button.new()
	join_btn.name = "JoinBtn"
	join_btn.text = "JOIN NEXT MATCH"
	join_btn.add_theme_font_size_override("font_size", 24)
	join_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	join_btn.connect("pressed", Callable(self, "_on_arena_join_pressed"))
	join_btn.z_index = 100
	add_child(join_btn)
	
	if Global.my_player_id > 0:
		join_btn.visible = false
	
	# Platforms the right way up for a client arriving mid-match (spectator
	# reconnect, late joiner): the server counts the flips for us.
	platforms_node.rotation = Global.arena_flips * PI
	_start_new_match()

func _exit_tree():
	# change_scene_to_file() removes this scene immediately but frees it at the end
	# of the frame. Any packet handled in between used to reach a node with no tree
	# and crash on get_tree() (the return_to_lobby null-tree crash). Drop the
	# subscriptions the moment we leave the tree.
	for sig_name in NET_SIGNAL_HANDLERS:
		var sig := Signal(Global, sig_name)
		var handler := Callable(self, NET_SIGNAL_HANDLERS[sig_name])
		if sig.is_connected(handler):
			sig.disconnect(handler)

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			Global.reset_scores()


func _on_net_player_joined(p_id: int, _active_list):
	# A fighter came back to its seat (reload): its movement sequence starts over.
	if p_id in player_instances and is_instance_valid(player_instances[p_id]):
		player_instances[p_id].reset_net_sequence()

func _on_return_to_lobby():
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _on_net_version_error(server_version: String):
	# The server refused our JOIN NEXT MATCH: the browser is running a cached build.
	_show_banner("UPDATE REQUIRED: this build is " + Global.GAME_VERSION + ", the server runs "
		+ server_version + ".\nReload the page to get the new version.", 999.0)
	var j_btn = get_node_or_null("JoinBtn")
	if j_btn:
		j_btn.text = "RELOAD THE PAGE TO JOIN"
		j_btn.disabled = true

func _start_new_match():
	current_round = Global.current_round
	_start_round()


# ------------------------------------------------------------------------------
# ROUND START
# We use this function to clear out old projectiles, put players on their
# starting platforms, and reset everyone's health.
# ------------------------------------------------------------------------------
func _on_leave_match_pressed():
	Global.send_net_data({"type": "leave_slot"})
	Global.my_player_id = 0
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _start_round():
	is_round_over = false
	_clear_projectiles()
	
	if touch_controls:
		touch_controls.my_input_prefix = "p" + str(Global.my_player_id) + "_"
	
	# Fighters exist only for the slots the server says are in this match. A client
	# that arrives straight from scene_transition, or joins mid-match, never ran the
	# lobby countdown, so the default configs (all four active) cannot be trusted.
	var roster: Array[int] = Global.playing_players.duplicate()
	if roster.is_empty():
		roster = Global.active_players.duplicate()
	for p_id in Global.player_configs:
		Global.player_configs[p_id]["active"] = p_id in roster
	for p_id in player_instances.keys():
		if not p_id in roster and is_instance_valid(player_instances[p_id]):
			player_instances[p_id].queue_free()
			player_instances.erase(p_id)

	for p_id in roster:
		if p_id < 1 or p_id > 4:
			continue
		# Stocks come from the server (snapshot / player_died / new_round), so a client
		# that rejoins mid-round shows the real count instead of a fresh 3.
		player_stocks[p_id] = Global.server_stocks.get(p_id, Global.max_stocks)
		var spawn_pos = spawn_points[p_id - 1]
		if p_id in player_instances and is_instance_valid(player_instances[p_id]):
			player_instances[p_id].respawn(spawn_pos)
		else:
			var p = PlayerScene.instantiate()
			p.player_id = p_id
			p.class_type = Global.player_configs[p_id]["class"]
			add_child(p)
			p.respawn(spawn_pos)
			player_instances[p_id] = p
			if Global.rejoined_mid_match and p_id == Global.my_player_id:
				# Same fight after a reload: no free quiver.
				p.restore_combat_state(Global.load_combat_state())
				Global.rejoined_mid_match = false

	_update_hud()
	_show_banner("ROUND " + str(current_round) + " - FIGHT!", 1.5)
	var queued := Global.my_player_id > 0 and not Global.my_player_id in roster
	if Global.is_spectator or queued:
		await get_tree().create_timer(1.5).timeout
		if not is_inside_tree():
			return
		if queued:
			_show_banner("YOU'RE IN THE QUEUE: NEXT MATCH STARTS AFTER THIS ROUND", 999.0)
		else:
			_show_banner("SPECTATING... WAITING FOR ROUND END", 999.0)


func _clear_projectiles():
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()

func _on_net_player_died(killer_id: int, victim_id: int, new_stock: int):
	player_stocks[victim_id] = new_stock
	if victim_id in player_instances and is_instance_valid(player_instances[victim_id]):
		player_instances[victim_id].force_die()
		
	var victim_name = Global.player_names.get(victim_id, "Player " + str(victim_id))
	var killer_name = Global.player_names.get(killer_id, "Player " + str(killer_id))
	
	if killer_id == victim_id:
		_show_banner(victim_name + " fell!", 1.0)
	else:
		_show_banner(killer_name + " knocked out " + victim_name + "!", 1.0)
		
	_update_hud()
	
	if new_stock > 0:
		await get_tree().create_timer(1.2).timeout
		if not is_inside_tree():
			return
		if not is_round_over and victim_id in player_instances and is_instance_valid(player_instances[victim_id]):
			var spawn_pos = spawn_points[victim_id - 1]
			player_instances[victim_id].respawn(spawn_pos)

# Obsolete: We don't check round end locally anymore! The server does it!
func _check_round_end():
	pass

func _on_round_end_sync(winner_id: int, scores: Dictionary, round_num: int, match_over: bool = false):
	if is_round_over:
		return # Ignore duplicate network triggers

	is_round_over = true
	current_round = round_num

	# Sync the scores from the server
	for p_id in scores:
		Global.player_scores[int(p_id)] = int(scores[p_id])

	_update_hud()
	_display_round_winner(winner_id, match_over)

func _display_round_winner(winner_id: int, match_over: bool = false):
	if winner_id <= 0:
		_show_banner("*** NO SURVIVORS: ROUND " + str(current_round) + " IS A DRAW ***", 2.2)
		return
	var winner_class = Global.CLASS_INFO[Global.player_configs[winner_id]["class"]]["name"]
	var is_me = (winner_id == Global.my_player_id)

	# The server decides when the match is won (5 crowns) and sends match_over;
	# it returns everyone to the lobby a few seconds later.
	if match_over:
		var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
		var txt = "*** " + ("YOU WON THE MATCH!" if is_me else w_name + " (" + winner_class + ") WINS THE MATCH!") + " ***\nReturning to lobby..."
		_show_banner(txt, 999.0)
	else:
		var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
		var txt = "*** " + ("YOU WON ROUND " + str(current_round) + "!" if is_me else w_name + " (" + winner_class + ") WINS ROUND " + str(current_round) + "!") + " ***"
		_show_banner(txt, 2.2)
		# The next round starts ONLY when the server sends new_round (see
		# _on_new_round_sync). The old local 2.6 s timer here made every client
		# start the round twice and let the round counter drift.

func _on_new_round_sync(round_num: int):
	current_round = round_num
	_start_round()

func _show_banner(text: String, duration: float):
	banner_label.text = text
	banner_label.visible = true
	var tween = create_tween()
	banner_label.modulate.a = 0.0
	tween.tween_property(banner_label, "modulate:a", 1.0, 0.15)
	if duration < 900.0:
		await get_tree().create_timer(duration).timeout
		if not is_inside_tree():
			return
		if banner_label.text == text:
			var fade = create_tween()
			fade.tween_property(banner_label, "modulate:a", 0.0, 0.25)

func _update_hud():
	_update_panel(p1_panel, 1)
	_update_panel(p2_panel, 2)
	_update_panel(p3_panel, 3)
	_update_panel(p4_panel, 4)

func _update_panel(panel: Control, p_id: int):
	if not Global.player_configs[p_id]["active"]:
		panel.visible = false
		return
		
	panel.visible = true
	var c_type = Global.player_configs[p_id]["class"]
	var c_info = Global.CLASS_INFO[c_type]
	
	var name_lbl = panel.get_node("NameLabel")
	var stock_lbl = panel.get_node("StockLabel")
	var score_lbl = panel.get_node("ScoreLabel")
	
	var disp_name = Global.player_names.get(p_id, "P" + str(p_id))
	if p_id == Global.my_player_id and Global.my_player_name != "":
		disp_name = Global.my_player_name
		
	var class_icon = name_lbl.get_node_or_null("ClassIcon")
	if not class_icon:
		class_icon = TextureRect.new()
		class_icon.name = "ClassIcon"
		class_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		class_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		class_icon.size = Vector2(16, 16)
		class_icon.position = Vector2(0, 2)
		name_lbl.add_child(class_icon)
	class_icon.texture = CLASS_ICON_TEX.get(c_type)
	name_lbl.text = "   " + disp_name + (" (You)" if p_id == Global.my_player_id else "")
	name_lbl.modulate = c_info["color"]
	
	var stocks = player_stocks.get(p_id, Global.max_stocks)
	var stock_icon = stock_lbl.get_node_or_null("StockIcon")
	if not stock_icon:
		stock_icon = TextureRect.new()
		stock_icon.name = "StockIcon"
		stock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stock_icon.size = Vector2(16, 16)
		stock_icon.position = Vector2(0, 2)
		stock_lbl.add_child(stock_icon)
	stock_icon.texture = HEART_TEX
	stock_lbl.text = "   x " + str(stocks)
	
	var score_icon = score_lbl.get_node_or_null("ScoreIcon")
	if not score_icon:
		score_icon = TextureRect.new()
		score_icon.name = "ScoreIcon"
		score_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		score_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		score_icon.size = Vector2(16, 16)
		score_icon.position = Vector2(0, 2)
		score_lbl.add_child(score_icon)
	score_icon.texture = CROWN_TEX
	score_lbl.text = "   " + str(Global.player_scores[p_id])

func _host_spawn_powerup():
	if not is_instance_valid(powerup_node) and not is_arena_rotating:
		Global.send_net_data({"type": "spawn_powerup", "x": 320.0, "y": 40.0})
		_spawn_powerup(320.0, 40.0)

func _on_net_spawn_powerup(x: float, y: float):
	if Global.my_player_id != 1:
		_spawn_powerup(x, y)

func _spawn_powerup(px: float, py: float):
	if is_instance_valid(powerup_node):
		return
		
	powerup_node = Area2D.new()
	powerup_node.global_position = Vector2(px, py)
	powerup_node.collision_mask = 2
	
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 16.0
	col.shape = shape
	powerup_node.add_child(col)
	
	var tex = Sprite2D.new()
	tex.texture = PICKUP_TEX
	tex.scale = Vector2(0.12, 0.12)  # Scale a 256x256 image to ~30x30
	powerup_node.add_child(tex)
	
	add_child(powerup_node)
	powerup_node.connect("body_entered", Callable(self, "_on_powerup_body_entered"))

func _on_powerup_body_entered(body: Node2D):
	if body.is_in_group("players") and body.player_id == Global.my_player_id:
		Global.send_net_data({"type": "activate_powerup", "powerup_id": 1})
		_activate_rotation()

func _on_net_activate_powerup(pid: int):
	_activate_rotation()
	
func _activate_rotation():
	if is_instance_valid(powerup_node):
		powerup_node.queue_free()
		powerup_node = null
		
	if is_arena_rotating:
		return
		
	is_arena_rotating = true
	Global.arena_flips += 1
	_show_banner("** ARENA SHIFT! **", 2.5)
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(platforms_node, "rotation", platforms_node.rotation + PI, 2.5)

	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree():
		return
	is_arena_rotating = false

func _on_arena_join_pressed():
	Global.request_join(Global._load_saved_player_id())
	var j_btn = get_node_or_null("JoinBtn")
	if j_btn:
		j_btn.text = "QUEUED FOR LOBBY..."
		j_btn.disabled = true

func _on_spectate_pressed():
	if pause_overlay:
		pause_overlay.visible = false
	Global.send_net_data({"type": "leave_slot"})
	var p_node = get_node_or_null("Player" + str(Global.my_player_id))
	if p_node:
		p_node.queue_free()
	Global.my_player_id = 0

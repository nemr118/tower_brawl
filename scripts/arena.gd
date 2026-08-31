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
	Global.connect("net_player_died", Callable(self, "_on_net_player_died"))
	Global.connect("net_player_hit", Callable(self, "_on_network_player_hit"))
	Global.connect("net_round_end", Callable(self, "_on_round_end_sync"))
	Global.connect("net_new_round", Callable(self, "_on_new_round_sync"))
	Global.connect("net_return_to_lobby", Callable(self, "_on_return_to_lobby"))

	Global.connect("net_spawn_powerup", Callable(self, "_on_net_spawn_powerup"))
	Global.connect("net_activate_powerup", Callable(self, "_on_net_activate_powerup"))
	
	if Global.my_player_id == 1:
		var pt = Timer.new()
		pt.wait_time = 15.0
		pt.autostart = true
		pt.connect("timeout", Callable(self, "_host_spawn_powerup"))
		add_child(pt)
	_start_new_match()

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			Global.reset_scores()
			_start_new_match()


func _on_return_to_lobby():
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _start_new_match():
	current_round = 1
	_start_round()


# ------------------------------------------------------------------------------
# ROUND START
# We use this function to clear out old projectiles, put players on their
# starting platforms, and reset everyone's health.
# ------------------------------------------------------------------------------
func _start_round():
	is_round_over = false
	_clear_projectiles()
	
	if touch_controls:
		touch_controls.my_input_prefix = "p" + str(Global.my_player_id) + "_"
	
	for p_id in Global.player_configs:
		if Global.player_configs[p_id]["active"]:
			player_stocks[p_id] = Global.max_stocks
			
	for p_id in Global.player_configs:
		if not Global.player_configs[p_id]["active"]:
			continue
			
		var spawn_pos = spawn_points[p_id - 1]
		if p_id in player_instances and is_instance_valid(player_instances[p_id]):
			player_instances[p_id].respawn(spawn_pos)
		else:
			var p = PlayerScene.instantiate()
			p.player_id = p_id
			p.class_type = Global.player_configs[p_id]["class"]
			add_child(p)
			p.respawn(spawn_pos)
			p.connect("player_died", Callable(self, "_on_player_died"))
			player_instances[p_id] = p
			
	_update_hud()
	_show_banner("ROUND " + str(current_round) + " - FIGHT!", 1.5)
	if Global.is_spectator:
		await get_tree().create_timer(1.5).timeout
		_show_banner("SPECTATING... WAITING FOR ROUND END", 999.0)


func _clear_projectiles():
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()

func _on_network_player_hit(killer_id: int, victim_id: int):
	if victim_id in player_instances and is_instance_valid(player_instances[victim_id]):
		if not player_instances[victim_id].is_dead:
			player_instances[victim_id].take_hit(killer_id, Vector2.ZERO)


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
		if not is_round_over and victim_id in player_instances:
			var spawn_pos = spawn_points[victim_id - 1]
			player_instances[victim_id].respawn(spawn_pos)

# Obsolete: We don't check round end locally anymore! The server does it!
func _check_round_end():
	pass

func _on_round_end_sync(winner_id: int, scores: Dictionary, round_num: int):
	if is_round_over:
		return # Ignore duplicate network triggers
		
	is_round_over = true
	current_round = round_num
	
	# Sync the scores from the host
	for p_id in scores:
		Global.player_scores[int(p_id)] = int(scores[p_id])
		
	_update_hud()
	_display_round_winner(winner_id)

func _display_round_winner(winner_id: int):
	var winner_class = Global.CLASS_INFO[Global.player_configs[winner_id]["class"]]["name"]
	var is_me = (winner_id == Global.my_player_id)
	
	if Global.player_scores[winner_id] >= Global.match_score_limit:
		var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
		var txt = "*** " + ("YOU WON THE MATCH!" if is_me else w_name + " (" + winner_class + ") WINS THE MATCH!") + " ***"
		_show_banner(txt, 999.0)
	else:
		var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
		var txt = "*** " + ("YOU WON ROUND " + str(current_round) + "!" if is_me else w_name + " (" + winner_class + ") WINS ROUND " + str(current_round) + "!") + " ***"
		_show_banner(txt, 2.2)
		await get_tree().create_timer(2.6).timeout
		current_round += 1
		_start_round()

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
		
	name_lbl.text = disp_name + (" (You)" if p_id == Global.my_player_id else "") + " [" + c_info["name"] + "]"
	name_lbl.modulate = c_info["color"]
	
	var stocks = player_stocks.get(p_id, Global.max_stocks)
	var hearts = ""
	for i in range(Global.max_stocks):
		if i < stocks:
			hearts += "* "
		else:
			hearts += "  "
	stock_lbl.text = "LIVES: " + str(stocks)
	
	score_lbl.text = "SCORE: " + str(Global.player_scores[p_id])

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
	
	var vis = ColorRect.new()
	vis.color = Color(1.0, 0.8, 0.0)
	vis.custom_minimum_size = Vector2(24, 24)
	vis.position = Vector2(-12, -12)
	powerup_node.add_child(vis)
	
	var lbl = Label.new()
	lbl.text = "+"
	lbl.position = Vector2(-10, -12)
	lbl.add_theme_font_size_override("font_size", 16)
	powerup_node.add_child(lbl)
	
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
	_show_banner("** ARENA SHIFT! **", 2.5)
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(platforms_node, "rotation", platforms_node.rotation + PI, 2.5)
	
	await get_tree().create_timer(2.5).timeout
	is_arena_rotating = false

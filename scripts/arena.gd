extends Node2D

const PlayerScene = preload("res://scenes/player.tscn")

var spawn_points = [
	Vector2(90, 260),
	Vector2(550, 260),
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

func _ready():
	NetworkManager.connect("player_hit_event", Callable(self, "_on_network_player_hit"))
	NetworkManager.connect("round_end_sync", Callable(self, "_on_round_end_sync"))
	NetworkManager.connect("new_round_sync", Callable(self, "_on_new_round_sync"))
	_start_new_match()

func _input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			Global.reset_scores()
			_start_new_match()

func _start_new_match():
	current_round = 1
	_start_round()

func _start_round():
	is_round_over = false
	_clear_projectiles()
	
	if touch_controls:
		touch_controls.my_input_prefix = "p" + str(NetworkManager.my_player_id) + "_"
	
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
	_show_banner("ROUND " + str(current_round) + " - 4-PLAYER BATTLE!", 1.5)

func _clear_projectiles():
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()

func _on_network_player_hit(killer_id: int, victim_id: int):
	if victim_id in player_instances and is_instance_valid(player_instances[victim_id]):
		if not player_instances[victim_id].is_dead:
			player_instances[victim_id].take_hit(killer_id, Vector2.ZERO)

func _on_player_died(killer_id: int, victim_id: int):
	if victim_id in player_stocks:
		player_stocks[victim_id] -= 1
		
	var victim_name = "Player " + str(victim_id)
	var killer_name = "Player " + str(killer_id)
	
	if killer_id == victim_id:
		_show_banner(victim_name + " fell!", 1.0)
	else:
		_show_banner(killer_name + " knocked out " + victim_name + "!", 1.0)
		
	_update_hud()
	
	if player_stocks[victim_id] > 0:
		await get_tree().create_timer(1.2).timeout
		if not is_round_over and victim_id in player_instances:
			var spawn_pos = spawn_points[victim_id - 1]
			player_instances[victim_id].respawn(spawn_pos)
	else:
		_check_round_end()

func _check_round_end():
	var alive_players = []
	for p_id in player_stocks:
		if player_stocks[p_id] > 0:
			alive_players.append(p_id)
			
	if alive_players.size() <= 1 and not is_round_over:
		is_round_over = true
		var winner_id = alive_players[0] if alive_players.size() == 1 else 0
		
		if winner_id > 0:
			Global.player_scores[winner_id] += 1
			_update_hud()
			
			# Broadcast authoritative round end to all 4 players
			NetworkManager.send_data({
				"type": "round_end",
				"winner": winner_id,
				"scores": Global.player_scores,
				"round": current_round
			})
			
			_display_round_winner(winner_id)
		else:
			_show_banner("DRAW ROUND!", 2.0)
			await get_tree().create_timer(2.2).timeout
			current_round += 1
			_start_round()

func _on_round_end_sync(winner_id: int, s1: int, s2: int, round_num: int):
	is_round_over = true
	current_round = round_num
	_update_hud()
	_display_round_winner(winner_id)

func _display_round_winner(winner_id: int):
	var winner_class = Global.CLASS_INFO[Global.player_configs[winner_id]["class"]]["name"]
	var is_me = (winner_id == NetworkManager.my_player_id)
	
	if Global.player_scores[winner_id] >= Global.match_score_limit:
		var txt = "👑 " + ("YOU WON THE MATCH!" if is_me else "PLAYER " + str(winner_id) + " (" + winner_class + ") WINS THE MATCH!") + " 👑"
		_show_banner(txt, 999.0)
	else:
		var txt = "👑 " + ("YOU WON ROUND " + str(current_round) + "!" if is_me else "PLAYER " + str(winner_id) + " (" + winner_class + ") WINS ROUND " + str(current_round) + "!") + " 👑"
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
	
	name_lbl.text = "P" + str(p_id) + (" (You)" if p_id == NetworkManager.my_player_id else "") + " " + c_info["icon"]
	name_lbl.modulate = c_info["color"]
	
	var stocks = player_stocks.get(p_id, Global.max_stocks)
	var hearts = ""
	for i in range(Global.max_stocks):
		if i < stocks:
			hearts += "❤️"
		else:
			hearts += "🖤"
	stock_lbl.text = hearts
	
	score_lbl.text = "👑 " + str(Global.player_scores[p_id])

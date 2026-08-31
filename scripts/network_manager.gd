extends Node

## Network Manager for TowerBrawl
## Handles real-time WebSocket communication for multi-screen, multi-device gameplay.

signal connected_to_server(player_id)
signal player_joined_room(p_id, active_players)
signal player_left_room(p_id, active_players)
signal opponent_locked_in(p_id, class_type)
signal player_state_received(p_id, data)
signal projectile_spawned(data)
signal player_hit_event(killer_id, victim_id)
signal round_end_sync(winner_id, p1_score, p2_score, round_num)
signal new_round_sync(round_num)

var ws: WebSocketPeer = WebSocketPeer.new()
var is_connected: bool = false
var my_player_id: int = 1
var server_url: String = ""
var active_players: Array[int] = [1]
var locked_opponents: Dictionary = {}

func _ready():
	_determine_url_and_connect()

func _determine_url_and_connect():
	var host = "127.0.0.1"
	var is_ssl = false
	if OS.has_feature("web"):
		var js_host = JavaScriptBridge.eval("window.location.hostname", true)
		if js_host and str(js_host) != "":
			host = str(js_host)
		var js_proto = JavaScriptBridge.eval("window.location.protocol", true)
		if str(js_proto) == "https:":
			is_ssl = true
	else:
		host = "127.0.0.1"
		
	if is_ssl:
		server_url = "wss://" + str(host) + ":8444"
	else:
		server_url = "ws://" + str(host) + ":8081"
		
	_connect_to_server()

func _connect_to_server():
	print("🔌 Connecting to WebSocket Relay: ", server_url)
	var err = ws.connect_to_url(server_url)
	if err != OK:
		print("⚠️ WebSocket connect error: ", err)

func _process(_delta):
	ws.poll()
	var state = ws.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			print("✅ Connected to TowerBrawl Relay Server!")
			
		while ws.get_available_packet_count() > 0:
			var pkt = ws.get_packet()
			var msg = pkt.get_string_from_utf8()
			_handle_packet(msg)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected:
			is_connected = false
			print("❌ Disconnected from Relay Server. Reconnecting in 1.5s...")
			await get_tree().create_timer(1.5).timeout
			_connect_to_server()

func send_data(dict: Dictionary):
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		dict["sender"] = my_player_id
		var json_str = JSON.stringify(dict)
		ws.send_text(json_str)

func _handle_packet(msg_str: String):
	var data = JSON.parse_string(msg_str)
	if not data or typeof(data) != TYPE_DICTIONARY:
		return
		
	var type = data.get("type", "")
	
	if type == "assign_id":
		my_player_id = int(data.get("id", 1))
		print("🎮 Assigned Player ID: ", my_player_id)
		
		active_players.clear()
		for x in data.get("active_players", [1]):
			active_players.append(int(x))
		if not active_players.has(my_player_id):
			active_players.append(my_player_id)
			
		emit_signal("connected_to_server", my_player_id)
		emit_signal("player_joined_room", my_player_id, active_players)
		
		var locked_map = data.get("locked_players", {})
		for p_str in locked_map:
			var p_id = int(p_str)
			var c_type = int(locked_map[p_str])
			locked_opponents[p_id] = c_type
			if p_id != my_player_id:
				emit_signal("opponent_locked_in", p_id, c_type)
				
	elif type == "player_joined":
		var p_id = int(data.get("id", 1))
		active_players.clear()
		for x in data.get("active_players", []):
			active_players.append(int(x))
		if not active_players.has(p_id):
			active_players.append(p_id)
		emit_signal("player_joined_room", p_id, active_players)
		
	elif type == "player_left":
		var p_id = int(data.get("id", 1))
		active_players.clear()
		for x in data.get("active_players", []):
			active_players.append(int(x))
		if locked_opponents.has(p_id):
			locked_opponents.erase(p_id)
		emit_signal("player_left_room", p_id, active_players)
		
	elif type == "lock_in":
		var p_id = int(data.get("sender", 1))
		var c_type = int(data.get("class", 0))
		locked_opponents[p_id] = c_type
		emit_signal("opponent_locked_in", p_id, c_type)
		
	elif type == "sync_pos":
		var p_id = int(data.get("sender", 1))
		if p_id != my_player_id:
			emit_signal("player_state_received", p_id, data)
			
	elif type == "spawn_projectile":
		var p_id = int(data.get("sender", 1))
		if p_id != my_player_id:
			emit_signal("projectile_spawned", data)
			
	elif type == "player_hit":
		var killer = int(data.get("killer", 1))
		var victim = int(data.get("victim", 1))
		emit_signal("player_hit_event", killer, victim)
		
	elif type == "round_end":
		var winner = int(data.get("winner", 1))
		var s1 = int(data.get("p1_score", 0))
		var s2 = int(data.get("p2_score", 0))
		var r_num = int(data.get("round", 1))
		emit_signal("round_end_sync", winner, s1, s2, r_num)
		
	elif type == "new_round":
		var r_num = int(data.get("round", 1))
		emit_signal("new_round_sync", r_num)

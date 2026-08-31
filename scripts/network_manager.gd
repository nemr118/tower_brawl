extends Node

## Network Manager for TowerBrawl
## Handles real-time WebSocket communication for multi-screen, multi-device gameplay.

signal connected_to_server(player_id)
signal opponent_locked_in(p_id, class_type)
signal player_state_received(p_id, data)
signal projectile_spawned(data)
signal player_hit_event(killer_id, victim_id)
signal round_start_event(round_num)

var ws: WebSocketPeer = WebSocketPeer.new()
var is_connected: bool = false
var my_player_id: int = 1
var server_url: String = ""

func _ready():
	# Determine server host IP
	var host = "127.0.0.1"
	if OS.has_feature("web"):
		# In web browser, connect back to window.location.hostname
		host = JavaScriptBridge.eval("window.location.hostname", true)
		if not host or host == "":
			host = "127.0.0.1"
	else:
		host = "127.0.0.1"
		
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
			print("❌ Disconnected from Relay Server. Reconnecting in 2s...")
			await get_tree().create_timer(2.0).timeout
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
		emit_signal("connected_to_server", my_player_id)
		
	elif type == "lock_in":
		var p_id = int(data.get("sender", 1))
		var c_type = int(data.get("class", 0))
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
		
	elif type == "start_round":
		var r_num = int(data.get("round", 1))
		emit_signal("round_start_event", r_num)

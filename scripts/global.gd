extends Node

## Global Game Manager & WebSocket Network Engine
## Central singleton for 4-Player Battle Royale, state sync, and class definitions.

signal net_connected(player_id)
signal net_player_joined(player_id, active_players)
signal net_player_left(player_id, active_players)
signal net_opponent_locked_in(player_id, class_type)
signal net_player_state_received(player_id, data)
signal net_projectile_spawned(data)
signal net_player_hit(killer_id, victim_id)
signal net_round_end(winner_id, p1_score, p2_score, round_num)
signal net_new_round(round_num)

enum ClassType {
	RANGER,
	KNIGHT,
	MAGE,
	ROGUE
}

const CLASS_INFO = {
	ClassType.RANGER: {
		"name": "Ranger",
		"title": "Master Archer",
		"icon": "🏹",
		"color": Color(0.2, 0.75, 0.35),
		"desc": "Precision multi-directional arrows, projectile catching, and recoil backflip shot."
	},
	ClassType.KNIGHT: {
		"name": "Knight",
		"title": "Iron Juggernaut",
		"icon": "⚔️",
		"color": Color(0.25, 0.55, 0.95),
		"desc": "Broadsword slash deflects projectiles, shield guard parries arrows and spells."
	},
	ClassType.MAGE: {
		"name": "Mage",
		"title": "Pyromancer",
		"icon": "🔮",
		"color": Color(0.95, 0.55, 0.15),
		"desc": "Explosive firebolts that regenerate over time, and instantaneous void blink teleport."
	},
	ClassType.ROGUE: {
		"name": "Rogue",
		"title": "Shadow Assassin",
		"icon": "🗡️",
		"color": Color(0.75, 0.3, 0.95),
		"desc": "Rapid throwing kunais, shadow dash ambushes through enemies."
	}
}

var player_configs = {
	1: {"class": ClassType.RANGER, "active": true},
	2: {"class": ClassType.KNIGHT, "active": true},
	3: {"class": ClassType.MAGE, "active": true},
	4: {"class": ClassType.ROGUE, "active": true}
}

var player_scores = {
	1: 0,
	2: 0,
	3: 0,
	4: 0
}

var max_stocks: int = 3
var match_score_limit: int = 5

# --- REAL-TIME WEBSOCKET RELAY ---
var ws: WebSocketPeer = WebSocketPeer.new()
var is_connected: bool = false
var is_connecting: bool = false   # guard: never open two sockets at once
var my_player_id: int = 1
var server_url: String = ""
var active_players: Array[int] = []
var locked_opponents: Dictionary = {}
var player_names: Dictionary = {}
var my_player_name: String = ""

signal net_names_updated()
signal net_force_start()

func _ready():
	_determine_url_and_connect()

func _determine_url_and_connect():
	if is_connecting or is_connected:
		return
	is_connecting = true
	
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
		
	print("🔌 [Global] Connecting to: ", server_url)
	ws = WebSocketPeer.new()   # fresh socket, never reuse a closed one
	var err = ws.connect_to_url(server_url)
	if err != OK:
		print("⚠️ [Global] WebSocket connect error: ", err)
		is_connecting = false

func _save_player_id():
	# Persist our slot number so we can reclaim it after a page reload / reconnect
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('towerbrawl_pid', '" + str(my_player_id) + "')", true)

func _load_saved_player_id() -> int:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("localStorage.getItem('towerbrawl_pid')", true)
		if val != null and str(val) != "null" and str(val) != "":
			return int(str(val))
	return 0  # 0 = no saved ID

func _process(_delta):
	ws.poll()
	var state = ws.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if not is_connected:
			is_connected = true
			is_connecting = false
			print("✅ [Global] Connected!")
			# Send hello immediately — server uses reclaim_id to restore our slot
			var saved_id = _load_saved_player_id()
			send_net_data({"type": "hello", "reclaim_id": saved_id})
			
		while ws.get_available_packet_count() > 0:
			var pkt = ws.get_packet()
			var msg = pkt.get_string_from_utf8()
			_handle_net_packet(msg)
			
	elif state == WebSocketPeer.STATE_CLOSED:
		if is_connected or is_connecting:
			is_connected = false
			is_connecting = false
			print("❌ [Global] Disconnected. Reconnecting in 2s...")
			await get_tree().create_timer(2.0).timeout
			_determine_url_and_connect()

func send_net_data(dict: Dictionary):
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		dict["sender"] = my_player_id
		var json_str = JSON.stringify(dict)
		ws.send_text(json_str)

func _handle_net_packet(msg_str: String):
	var data = JSON.parse_string(msg_str)
	if not data or typeof(data) != TYPE_DICTIONARY:
		return
		
	var type = data.get("type", "")
	
	if type == "force_start":
		emit_signal("net_force_start")
	
	if type in ["assign_id", "player_joined", "player_left", "name_update"]:
		if data.has("player_names"):
			player_names.clear()
			var p_names = data.get("player_names", {})
			for p_str in p_names:
				player_names[int(p_str)] = str(p_names[p_str])
		emit_signal("net_names_updated")
		
	if type == "assign_id":
		my_player_id = int(data.get("id", 1))
		print("🎮 [Global] Assigned Player ID: ", my_player_id)
		_save_player_id()   # persist so reconnects restore this slot
		
		active_players.clear()
		for x in data.get("active_players", [1]):
			active_players.append(int(x))
		if not active_players.has(my_player_id):
			active_players.append(my_player_id)
			
		emit_signal("net_connected", my_player_id)
		emit_signal("net_player_joined", my_player_id, active_players)
		
		var locked_map = data.get("locked_players", {})
		for p_str in locked_map:
			var p_id = int(p_str)
			var c_type = int(locked_map[p_str])
			locked_opponents[p_id] = c_type
			if p_id != my_player_id:
				emit_signal("net_opponent_locked_in", p_id, c_type)
				
	elif type == "player_joined":
		var p_id = int(data.get("id", 1))
		active_players.clear()
		for x in data.get("active_players", []):
			active_players.append(int(x))
		if not active_players.has(p_id):
			active_players.append(p_id)
		emit_signal("net_player_joined", p_id, active_players)
		
	elif type == "player_left":
		var p_id = int(data.get("id", 1))
		active_players.clear()
		for x in data.get("active_players", []):
			active_players.append(int(x))
		if locked_opponents.has(p_id):
			locked_opponents.erase(p_id)
		emit_signal("net_player_left", p_id, active_players)
		
	elif type == "lock_in":
		var p_id = int(data.get("sender", 1))
		var c_type = int(data.get("class", 0))
		locked_opponents[p_id] = c_type
		emit_signal("net_opponent_locked_in", p_id, c_type)
		
	elif type == "sync_pos":
		var p_id = int(data.get("sender", 1))
		if p_id != my_player_id:
			emit_signal("net_player_state_received", p_id, data)
			
	elif type == "spawn_projectile":
		var p_id = int(data.get("sender", 1))
		if p_id != my_player_id:
			emit_signal("net_projectile_spawned", data)
			
	elif type == "player_hit":
		var killer = int(data.get("killer", 1))
		var victim = int(data.get("victim", 1))
		emit_signal("net_player_hit", killer, victim)
		
	elif type == "round_end":
		var winner = int(data.get("winner", 1))
		var s1 = int(data.get("p1_score", 0))
		var s2 = int(data.get("p2_score", 0))
		var r_num = int(data.get("round", 1))
		emit_signal("net_round_end", winner, s1, s2, r_num)
		
	elif type == "new_round":
		var r_num = int(data.get("round", 1))
		emit_signal("net_new_round", r_num)

func reset_scores():
	player_scores = {1: 0, 2: 0, 3: 0, 4: 0}

func _save_player_name(n: String):
	my_player_name = n
	if OS.has_feature("web"):
		JavaScriptBridge.eval("localStorage.setItem('towerbrawl_name', '" + n.replace("'", "\'") + "')", true)

func _load_saved_player_name() -> String:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("localStorage.getItem('towerbrawl_name')", true)
		if val != null and str(val) != "null" and str(val) != "":
			return str(val)
	return ""

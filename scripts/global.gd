# ==============================================================================
# WELCOME TO GLOBAL.GD! (The Networking Script)
# ==============================================================================
# This script is an "Autoload". That means it stays awake in the background
# forever while the game runs. 
# Its main job is sending invisible text messages (called JSON) over the 
# internet so that phones and PCs can talk to each other in real-time!
# ==============================================================================

extends Node

var is_mobile: bool = false
var is_spectator: bool = false

## Global Game Manager & WebSocket Network Engine
## Central singleton for 4-Player Battle Royale, state sync, and class definitions.

signal net_connected(player_id)
signal net_player_joined(player_id, active_players)
signal net_player_left(player_id, active_players)
signal net_opponent_locked_in(player_id, class_type)
signal net_player_state_received(player_id, data)
signal net_projectile_spawned(data)
signal net_player_hit(killer_id, victim_id)
signal net_return_to_lobby
signal net_player_died(killer_id, victim_id, stock)
signal net_round_end(winner_id, scores, round_num)
signal net_new_round(round_num)

enum ClassType {
	RANGER,
	KNIGHT,
	MAGE,
	ROGUE,
	DRUID
}

const CLASS_INFO = {
	ClassType.RANGER: {
		"name": "Ranger",
		"title": "Master Archer",
		"icon": "🏹",
		"icon_tex": "res://assets/icons/ranger.jpg",
		"primary_icon": "res://assets/icons/skill_ranger_1.jpg",
		"special_icon": "res://assets/icons/skill_ranger_2.jpg",
		"color": Color(0.2, 0.75, 0.35),
		"desc": "Precision multi-directional arrows, projectile catching, and recoil backflip shot."
	},
	ClassType.KNIGHT: {
		"name": "Knight",
		"title": "Iron Juggernaut",
		"icon": "⚔️",
		"icon_tex": "res://assets/icons/knight.jpg",
		"primary_icon": "res://assets/icons/skill_knight_1.jpg",
		"special_icon": "res://assets/icons/skill_knight_2.jpg",
		"color": Color(0.25, 0.55, 0.95),
		"desc": "Broadsword slash deflects projectiles, shield guard parries arrows and spells."
	},
	ClassType.MAGE: {
		"name": "Mage",
		"title": "Pyromancer",
		"icon": "🔮",
		"icon_tex": "res://assets/icons/pyro.jpg",
		"primary_icon": "res://assets/icons/skill_pyro_1.jpg",
		"special_icon": "res://assets/icons/skill_pyro_2.jpg",
		"color": Color(0.95, 0.55, 0.15),
		"desc": "Explosive firebolts that regenerate over time, and instantaneous void blink teleport."
	},
	ClassType.ROGUE: {
		"name": "Rogue",
		"title": "Shadow Assassin",
		"icon": "🗡️",
		"icon_tex": "res://assets/icons/rogue.jpg",
		"primary_icon": "res://assets/icons/skill_rogue_1.jpg",
		"special_icon": "res://assets/icons/skill_rogue_2.jpg",
		"color": Color(0.75, 0.3, 0.95),
		"desc": "Rapid throwing kunais, shadow dash ambushes through enemies."
	},
	ClassType.DRUID: {
		"name": "Druid",
		"title": "Shape Shifter",
		"icon": "🐻",
		"icon_tex": "res://assets/icons/druid.jpg",
		"primary_icon": "res://assets/icons/skill_druid_1.jpg",
		"special_icon": "res://assets/icons/skill_druid_2.jpg",
		"color": Color(0.6, 0.4, 0.1),
		"desc": "Throws thorns. Bear Form. Dash turns into a Storm Crow. Shield is Phoenix Egg."
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
var my_player_id: int = 0
var server_url: String = ""
var active_players: Array[int] = []
var locked_opponents: Dictionary = {}
var player_names: Dictionary = {}
var my_player_name: String = ""

signal net_names_updated()
signal net_spawn_powerup(x, y)
signal net_activate_powerup(powerup_id)
signal net_force_start()

func _ready():

	is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()
	if OS.has_feature("web"):
		var ua = JavaScriptBridge.eval("/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);", true)
		if ua:
			is_mobile = true

	_determine_url_and_connect()

func _determine_url_and_connect():
	if is_connecting or is_connected:
		return
	is_connecting = true
	
	var host = "127.0.0.1"
	var is_ssl = false
	if OS.has_feature("web"):
		var js_host = str(JavaScriptBridge.eval("window.location.hostname", true))
		if js_host == "nemr118.github.io":
			server_url = "wss://towerbrawl-server.loca.lt"
		elif js_host and js_host != "":
			var host_str = js_host
			var js_port = JavaScriptBridge.eval("window.location.port", true)
			var port_str = ""
			if js_port and str(js_port) != "":
				port_str = ":" + str(js_port)
			var js_proto = JavaScriptBridge.eval("window.location.protocol", true)
			if str(js_proto) == "https:":
				server_url = "wss://" + host_str + port_str
			else:
				server_url = "ws://" + host_str + port_str
		else:
			server_url = "wss://towerbrawl-server.loca.lt"
	else:
		server_url = "ws://127.0.0.1:8000" 
		
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
	else:
		var f = FileAccess.open("user://towerbrawl_pid.sav", FileAccess.WRITE)
		if f:
			f.store_string(str(my_player_id))
			f.close()

func _load_saved_player_id() -> int:
	if OS.has_feature("web"):
		var val = JavaScriptBridge.eval("localStorage.getItem('towerbrawl_pid')", true)
		if val != null and str(val) != "null" and str(val) != "":
			return int(str(val))
	else:
		if FileAccess.file_exists("user://towerbrawl_pid.sav"):
			var f = FileAccess.open("user://towerbrawl_pid.sav", FileAccess.READ)
			if f:
				var val = f.get_as_text()
				f.close()
				if val != "":
					return int(val)
	return 0  # 0 = no saved ID

func _process(_delta):
	ws.poll()
	var state = ws.get_ready_state()
	
	if state == WebSocketPeer.STATE_OPEN:
		if Engine.get_process_frames() % 60 == 0:
			send_net_data({"type": "ping"})
		if not is_connected:
			is_connected = true
			is_connecting = false
			print("✅ [Global] Connected!")
			# Send hello immediately — server uses reclaim_id to restore our slot
			# Handshake done. Server will send spectator_state.
			
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
	
	if type == "spawn_powerup":
		emit_signal("net_spawn_powerup", data.get("x", 0.0), data.get("y", 0.0))
	elif type == "activate_powerup":
		emit_signal("net_activate_powerup", data.get("powerup_id", 0))
	if type == "force_start":
		emit_signal("net_force_start")
	
	if type in ["assign_id", "player_joined", "player_left", "name_update", "spectator_state"]:
		if data.has("active_players"):
			active_players.clear()
			var a_players = data.get("active_players", [])
			for x in a_players:
				active_players.append(int(x))
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
		
		# Remap local gamepad inputs to accept any controller (device: -1)
		# This ensures phones with 1 connected controller (device 0) can play as P2, P3, or P4!
		var prefix = "p" + str(my_player_id) + "_"
		for action in InputMap.get_actions():
			if action.begins_with(prefix):
				var events = InputMap.action_get_events(action)
				InputMap.action_erase_events(action)
				for ev in events:
					if ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
						ev.device = -1
					InputMap.action_add_event(action, ev)
		
		
		# Transfer PC Keyboard and Mouse binds to our assigned slot if we aren't P1
		if my_player_id != 1:
			var prefix1 = "p1_"
			for action_suffix in ["left", "right", "up", "down", "jump", "dash", "attack", "special"]:
				var events1 = InputMap.action_get_events(prefix1 + action_suffix)
				var my_action = "p" + str(my_player_id) + "_" + action_suffix
				for ev in events1:
					if ev is InputEventKey or ev is InputEventMouseButton:
						InputMap.action_add_event(my_action, ev)

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
		
		# Transfer PC Keyboard and Mouse binds to our assigned slot if we aren't P1
		if my_player_id != 1:
			var prefix1 = "p1_"
			for action_suffix in ["left", "right", "up", "down", "jump", "dash", "attack", "special"]:
				var events1 = InputMap.action_get_events(prefix1 + action_suffix)
				var my_action = "p" + str(my_player_id) + "_" + action_suffix
				for ev in events1:
					if ev is InputEventKey or ev is InputEventMouseButton:
						InputMap.action_add_event(my_action, ev)

		active_players.clear()
		for x in data.get("active_players", []):
			active_players.append(int(x))
		if not active_players.has(p_id):
			active_players.append(p_id)
		emit_signal("net_player_joined", p_id, active_players)
		
	elif type == "player_left":
		var p_id = int(data.get("id", 1))
		
		# Transfer PC Keyboard and Mouse binds to our assigned slot if we aren't P1
		if my_player_id != 1:
			var prefix1 = "p1_"
			for action_suffix in ["left", "right", "up", "down", "jump", "dash", "attack", "special"]:
				var events1 = InputMap.action_get_events(prefix1 + action_suffix)
				var my_action = "p" + str(my_player_id) + "_" + action_suffix
				for ev in events1:
					if ev is InputEventKey or ev is InputEventMouseButton:
						InputMap.action_add_event(my_action, ev)

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
		
	elif type == "return_to_lobby":
		is_spectator = false
		locked_opponents.clear()
		reset_scores()
		emit_signal("net_return_to_lobby")
		
	elif type == "player_died":
		var victim = int(data.get("victim", 0))
		var killer = int(data.get("killer", 0))
		var stock = int(data.get("stock", 0))
		emit_signal("net_player_died", killer, victim, stock)
		
	elif type == "round_end":
		var winner = int(data.get("winner", 1))
		var scores = data.get("scores", {})
		var r_num = int(data.get("round", 1))
		emit_signal("net_round_end", winner, scores, r_num)
		
	elif type == "new_round":
		var r_num = int(data.get("round", 1))
		emit_signal("net_new_round", r_num)


func is_host() -> bool:
	var lowest = 999
	for p_id in active_players:
		if p_id < lowest:
			lowest = p_id
	if active_players.size() == 0:
		return true
	return my_player_id == lowest

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

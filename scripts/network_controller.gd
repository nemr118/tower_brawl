extends Node

## Network Controller Bridge
## Receives UDP input packets from mobile web controllers and maps them to Player 2 / 3 / 4

var udp_server: PacketPeerUDP

func _ready():
	udp_server = PacketPeerUDP.new()
	var err = udp_server.bind(9090, "0.0.0.0")
	if err == OK:
		print("📡 Mobile Controller Server listening on UDP port 9090")
	else:
		print("⚠️ Failed to bind UDP port 9090: ", err)

func _process(_delta):
	if not udp_server:
		return
		
	while udp_server.get_available_packet_count() > 0:
		var pkt = udp_server.get_packet()
		var msg = pkt.get_string_from_utf8()
		_handle_input_message(msg)

func _handle_input_message(msg: String):
	# JSON packet: {"p": 2, "action": "btn_down", "btn": "jump"}
	var json = JSON.parse_string(msg)
	if json and typeof(json) == TYPE_DICTIONARY:
		var p_id = int(json.get("p", 2))
		var prefix = "p" + str(p_id) + "_"
		var action = json.get("action", "")
		
		if action == "move":
			var x = float(json.get("x", 0.0))
			var y = float(json.get("y", 0.0))
			_simulate_axis(prefix + "left", prefix + "right", x)
			_simulate_axis(prefix + "up", prefix + "down", y)
		elif action == "press":
			var btn = json.get("btn", "")
			Input.action_press(prefix + btn)
		elif action == "release":
			var btn = json.get("btn", "")
			Input.action_release(prefix + btn)
		elif action == "switch_hero":
			var arena = get_tree().current_scene
			if arena and arena.has_method("_cycle_player_class"):
				arena._cycle_player_class(p_id)
		elif action == "restart":
			var arena = get_tree().current_scene
			if arena and arena.has_method("_start_new_match"):
				Global.reset_scores()
				arena._start_new_match()

func _simulate_axis(neg_action: String, pos_action: String, val: float):
	if val > 0.15:
		Input.action_press(pos_action, abs(val))
		Input.action_release(neg_action)
	elif val < -0.15:
		Input.action_press(neg_action, abs(val))
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)

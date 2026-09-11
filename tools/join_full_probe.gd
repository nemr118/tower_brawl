extends SceneTree
## The JOIN buttons on a full server (v0.1.7, backlog 33). The server answers a
## request_join with server_full when all 4 seats are taken. Before v0.1.7 the
## arena's button stayed a grey "QUEUED FOR LOBBY..." until a reload and the
## lobby showed nothing. Now both show "ALL SEATS TAKEN" for 2 s, then a live
## button. It also checks a socket drop while the arena's button waits, and a
## press with no socket. Run it after touching the JOIN buttons or server_full:
##   godot --headless --path . --script tools/join_full_probe.gd -- --no-net
##       the signals into both scenes, no server
##   godot --headless --path . --script tools/join_full_probe.gd -- --live --server=ws://127.0.0.1:8081 --no-netstats
##       a real press on a live server whose 4 seats are taken in a running match (tbbot add, 4 times)
## Expect: "✅ join_full_probe: N/N checks" (exit 0).
var started := false
var checks := 0
var failed: Array = []
var g: Node = null
var full_packets := 0

func _process(_delta: float) -> bool:
	if not started:
		started = true
		g = root.get_node("Global")   # not Global: this file compiles before the autoload exists
		g.connect("net_server_full", func(): full_packets += 1)
		if "--live" in OS.get_cmdline_user_args():
			_live()
		else:
			_offline()
	return false

func _check(what: String, ok: bool, got: String = "") -> void:
	checks += 1
	print("  ", "ok   " if ok else "FAIL ", what, "" if ok else "  (got: " + got + ")")
	if not ok:
		failed.append(what)

func _btn() -> Button:
	# the arena keeps it on its HUD layer, the lobby at the top
	return current_scene.find_child("JoinBtn", true, false) as Button if current_scene != null else null

func _state(b: Button) -> String:
	return "no button" if b == null else "%s, %s" % [b.text, "grey" if b.disabled else "live"]

func _is(b: Button, text: String, live: bool) -> bool:
	return b != null and b.text == text and b.disabled == (not live)

func _load_scene(path: String) -> Button:
	change_scene_to_file(path)
	for i in 60:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == path and _btn() != null:
			break
	return _btn()

func _offline() -> void:
	print("🧪 join_full_probe: the signals into both scenes, no server")
	var b := await _load_scene("res://scenes/arena.tscn")
	_check("arena: there is a JoinBtn", b != null)
	if b != null:
		b.text = "QUEUED FOR LOBBY..."
		b.disabled = true
		g.emit_signal("net_server_full")
		_check("arena: server_full turns a waiting button into a grey ALL SEATS TAKEN", _is(b, "ALL SEATS TAKEN", false), _state(b))
		await create_timer(1.0).timeout
		_check("arena: still ALL SEATS TAKEN after 1 s", _is(b, "ALL SEATS TAKEN", false), _state(b))
		await create_timer(1.3).timeout
		_check("arena: a live JOIN NEXT MATCH after 2 s", _is(b, "JOIN NEXT MATCH", true), _state(b))
		b.text = "RELOAD THE PAGE TO JOIN"
		b.disabled = true
		g.emit_signal("net_server_full")
		await create_timer(2.3).timeout
		_check("arena: server_full leaves RELOAD THE PAGE TO JOIN alone", _is(b, "RELOAD THE PAGE TO JOIN", false), _state(b))
		b.text = "JOIN NEXT MATCH"
		b.disabled = false
		g.emit_signal("net_server_full")
		_check("arena: server_full with no press (an auto-rejoin) leaves the button alone", _is(b, "JOIN NEXT MATCH", true), _state(b))
		b.text = "QUEUED FOR LOBBY..."
		b.disabled = true
		g.emit_signal("net_disconnected")
		_check("arena: a socket drop gives a waiting button back", _is(b, "JOIN NEXT MATCH", true), _state(b))
		b.emit_signal("pressed")
		_check("arena: a press with no socket leaves the button live", _is(b, "JOIN NEXT MATCH", true), _state(b))
	b = await _load_scene("res://scenes/character_select.tscn")
	_check("lobby: there is a JoinBtn reading JOIN MATCH", _is(b, "JOIN MATCH", true), _state(b))
	if b != null:
		g.emit_signal("net_server_full")
		_check("lobby: server_full shows a grey ALL SEATS TAKEN", _is(b, "ALL SEATS TAKEN", false), _state(b))
		await create_timer(2.3).timeout
		_check("lobby: a live JOIN MATCH after 2 s", _is(b, "JOIN MATCH", true), _state(b))
		b.text = "RELOAD TO JOIN"
		b.disabled = true
		g.emit_signal("net_server_full")
		await create_timer(2.3).timeout
		_check("lobby: server_full leaves RELOAD TO JOIN alone", _is(b, "RELOAD TO JOIN", false), _state(b))
	_finish()

func _live() -> void:
	print("🧪 join_full_probe: a real press on the live server")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		await process_frame
		if g.ws_connected and g.last_match_state == "PLAYING" and current_scene != null \
				and current_scene.scene_file_path == "res://scenes/arena.tscn" and _btn() != null:
			break
	var b := _btn()
	_check("connected, the match is PLAYING, the arena is loaded", b != null and g.ws_connected and g.last_match_state == "PLAYING",
		"connected=%s state=%s scene=%s" % [g.ws_connected, g.last_match_state, current_scene.scene_file_path if current_scene else "-"])
	if b == null:
		_finish()
		return
	await create_timer(1.5).timeout   # an automatic rejoin, if any, gets its answer first
	b = _btn()
	_check("all 4 seats are taken and we are a spectator", g.active_players.size() == 4 and g.my_player_id == 0,
		"seats=%s me=%d" % [str(g.active_players), g.my_player_id])
	_check("the button is a live JOIN NEXT MATCH", _is(b, "JOIN NEXT MATCH", true), _state(b))
	var fulls_before := full_packets
	b.emit_signal("pressed")
	_check("the press turns it into a grey QUEUED FOR LOBBY...", _is(b, "QUEUED FOR LOBBY...", false), _state(b))
	var seen: Array = [b.text]
	var at: Array = [0]
	var p0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - p0 < 6000:
		await process_frame
		b = _btn()
		if b == null:
			break
		if b.text != seen[-1]:
			seen.append(b.text)
			at.append(Time.get_ticks_msec() - p0)
		if _is(b, "JOIN NEXT MATCH", true):
			break
	var steps: Array = []
	for i in seen.size():
		steps.append("%s @%d ms" % [seen[i], at[i]])
	print("  the button: ", " -> ".join(steps))
	_check("a real server_full came back", full_packets > fulls_before, str(full_packets - fulls_before))
	var i_full := seen.find("ALL SEATS TAKEN")
	_check("server_full turned it into ALL SEATS TAKEN", i_full > 0, str(seen))
	var back_ms: int = at[-1] - at[i_full] if i_full > 0 else -1
	_check("then a live JOIN NEXT MATCH 2 s later", _is(b, "JOIN NEXT MATCH", true) and back_ms >= 1900 and back_ms <= 2600,
		"%s after %d ms" % [_state(b), back_ms])
	_check("still a spectator", g.my_player_id == 0, str(g.my_player_id))
	_finish()

func _finish() -> void:
	if failed.is_empty():
		print("✅ join_full_probe: %d/%d checks" % [checks, checks])
	else:
		printerr("❌ join_full_probe: %d/%d checks, failed: %s" % [checks - failed.size(), checks, ", ".join(failed)])
	quit(0 if failed.is_empty() else 1)

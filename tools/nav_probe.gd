extends SceneTree
## The nav probe (v0.1.5). The real tower (the same bodies arena.gd builds from
## arena_layouts.gd), one real fighter, one bot brain told to walk to a spot
## (goal_override), and a list of trips from one surface to another: first the
## stacked spots where the soaks deadlocked, then random pairs. A trip passes
## when the fighter stands on the goal surface; it fails after TRIP_S seconds.
## Run it after touching bot_brain.gd, bot_nav.gd, the layout or the movement:
##   godot --headless --path . --fixed-fps 60 --script tools/nav_probe.gd -- --no-net [--trips=40] [--seed=5] [--difficulty=0.7]
## Debug: --only=N runs trip N alone and traces it; --drop-test checks down + jump on a ledge by hand, no brain.
## Expect: "✅ nav_probe: N/N trips" (exit 0). A failed trip prints where it ended (exit 1).
var probe: Node = null

var frames := 0

func _process(_delta: float) -> bool:
	frames += 1
	if frames > 60 * 60 * 30:   # a hard stop: never hang a terminal
		printerr("❌ nav_probe: still running after 30 simulated minutes")
		quit(1)
		return true
	if probe == null:
		var g = root.get_node("Global")
		g.my_player_id = 1
		g.is_spectator = false
		probe = Probe.new()
		root.add_child(probe)
		return false
	if probe.done:
		quit(probe.exit_code)
	return false

class Probe extends Node2D:
	# Scripts are loaded in _ready, not preloaded: a preload compiles player.gd and
	# bot_brain.gd before the Global autoload exists, and both fail.
	const TRIP_S := 30.0
	const HOLD_FRAMES := 6          # on the goal surface this many frames in a row = arrived
	# where the soaks deadlocked (2026-09-08 and 2026-09-10): [from surface, x, to surface]
	const FIXED := [["L800b", 405.0, "L590"], ["L590", 392.0, "L90b"], ["L90b", 387.0, "L800b"],
		["B870L", 7.0, "B520L"], ["B520L", 11.0, "B870L"], ["FloorLeft", 40.0, "B160R"]]

	var layout := {}                # the brain reads arena.layout: this node stands in for the arena
	var done := false
	var exit_code := 0
	var p = null
	var brain = null
	var nav = null
	var rng := RandomNumberGenerator.new()
	var trips: Array = []           # [from, x, to]
	var trip := -1
	var frames := 0
	var held := 0
	var times: Array = []
	var failed: Array = []
	var misses_before := 0
	var ledge_layer := 6
	var only := -1                  # --only=N: that trip alone, traced
	var drop_test := false
	var dt_frame := 0
	var dt_results: Array = []
	var trace_key := ""

	func _ready() -> void:
		var seed_n := 5
		var count := 40
		var difficulty := 0.7
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--trips="):
				count = int(a.get_slice("=", 1))
			elif a.begins_with("--seed="):
				seed_n = int(a.get_slice("=", 1))
			elif a.begins_with("--difficulty="):
				difficulty = float(a.get_slice("=", 1))
			elif a.begins_with("--only="):
				only = int(a.get_slice("=", 1))
			elif a == "--drop-test":
				drop_test = true
		rng.seed = seed_n
		var player_script = load("res://scripts/player.gd")
		ledge_layer = player_script.LEDGE_LAYER
		layout = load("res://scripts/arena_layouts.gd").get_layout("tower")
		player_script.arena_w = float(layout["width"])
		player_script.arena_h = float(layout["height"])
		for piece in layout["pieces"]:   # as arena.gd _build_layout, without the visuals
			var w := float(piece["w"])
			var h := float(piece["h"])
			var body := StaticBody2D.new()
			body.name = str(piece["name"])
			body.position = Vector2(float(piece["x"]) + w / 2.0, float(piece["y"]) + h / 2.0)
			var shape := CollisionShape2D.new()
			shape.shape = RectangleShape2D.new()
			shape.shape.size = Vector2(w, h)
			if str(piece["kind"]) == "ledge":
				body.collision_layer = 1 << (ledge_layer - 1)
				shape.one_way_collision = true
				shape.one_way_collision_margin = 6.0
			else:
				body.collision_layer = 1
			body.collision_mask = 0
			body.add_child(shape)
			add_child(body)
		p = load("res://scenes/player.tscn").instantiate()
		if not ("player_id" in p):
			printerr("❌ nav_probe: player.gd did not load")
			exit_code = 1
			done = true
			return
		p.player_id = 1
		p.position = Vector2(130.0, 292.0)
		add_child(p)
		brain = load("res://scripts/bot_brain.gd").new()
		brain.setup("chaser", seed_n, difficulty)
		p.add_child(brain)
		nav = brain._nav
		if nav == null:
			printerr("❌ nav_probe: the brain built no route map")
			exit_code = 1
			done = true
			return
		var bad: Array = nav.unreachable()
		var move_count := 0
		for list in nav.moves:
			move_count += list.size()
		print("🧭 nav_probe: ", nav.surfaces.size(), " surfaces, ", move_count, " moves, unreachable pairs ", bad.size(), " ", bad.slice(0, 5))
		if bad.size() > 0:
			exit_code = 1
		var names := {}
		for i in nav.surfaces.size():
			names[nav.surface_name(i)] = i
		for t in FIXED:
			trips.append([names[t[0]], t[1], names[t[2]]])
		while trips.size() < FIXED.size() + count:
			var a: int = rng.randi() % nav.surfaces.size()
			var b: int = rng.randi() % nav.surfaces.size()
			if a != b:
				var s: Dictionary = nav.surfaces[a]
				trips.append([a, rng.randf_range(s["x0"] + 10.0, s["x1"] - 10.0), b])
		if drop_test:
			brain.set_physics_process(false)
			print("🧭 nav_probe: drop test on L660b, no brain")
			return
		if only >= 0:
			trips = [trips[only]]
		print("🧭 nav_probe: difficulty ", difficulty, ", seed ", seed_n, ", ", trips.size(), " trips")
		_next_trip()

	func _next_trip() -> void:
		trip += 1
		if trip >= trips.size():
			_finish()
			return
		var t: Array = trips[trip]
		var s: Dictionary = nav.surfaces[t[0]]
		var g: Dictionary = nav.surfaces[t[2]]
		p.global_position = Vector2(t[1], s["top"] - 8.0)
		p.velocity = Vector2.ZERO
		p._drop_timer = 0.0
		p.set_collision_mask_value(ledge_layer, true)
		brain._nav_step = {}
		brain.goal_override = Vector2((g["x0"] + g["x1"]) / 2.0, g["top"] - 14.0)
		misses_before = brain._stats["misses"]
		frames = 0
		held = 0

	func _physics_process(_delta: float) -> void:
		if drop_test and not done:
			_drop_test_frame()
			return
		if done or trip < 0 or trip >= trips.size():
			return
		frames += 1
		var t: Array = trips[trip]
		if only >= 0:
			_trace()
		if p.is_on_floor() and nav.surface_at(p.global_position) == t[2]:
			held += 1
		else:
			held = 0
		var label := "%s(%.0f) -> %s" % [nav.surface_name(t[0]), t[1], nav.surface_name(t[2])]
		if held >= HOLD_FRAMES:
			var secs := frames / 60.0
			times.append(secs)
			print("  ok   ", label.rpad(26), " %5.1f s  misses %d" % [secs, brain._stats["misses"] - misses_before])
			_next_trip()
		elif frames > int(TRIP_S * 60.0):
			var here: int = nav.surface_at(p.global_position)
			failed.append(label)
			print("  FAIL ", label.rpad(26), " after %.0f s: on %s at (%.0f,%.0f)" % [TRIP_S, nav.surface_name(here), p.global_position.x, p.global_position.y])
			_next_trip()

	# --only: one line whenever the brain's route state or the keys change, and every 0.5 s
	func _trace() -> void:
		var st: Dictionary = brain._nav_step
		var here: int = nav.surface_at(p.global_position)
		var key := "floor=%s surf=%s step=%s[%.0f..%.0f]->%s launched=%s land=%.0f down=%s jump=%s L=%s R=%s drop_t=%s mask6=%s duck=%s misses=%d stucks=%d" % [
			p.is_on_floor(), nav.surface_name(here), st.get("kind", "-"), float(st.get("x0", 0.0)), float(st.get("x1", 0.0)),
			nav.surface_name(int(st.get("to", -1))), st.get("launched", false), float(st.get("land_x", 0.0)),
			Input.is_action_pressed("p1_down"), Input.is_action_pressed("p1_jump"), Input.is_action_pressed("p1_left"),
			Input.is_action_pressed("p1_right"), p._drop_timer > 0.0, p.get_collision_mask_value(ledge_layer), p.is_ducking,
			brain._stats["misses"], brain._stats["stucks"]]
		if key != trace_key or frames % 30 == 0:
			trace_key = key
			print("    f%4d pos=(%.0f,%.0f) v=(%.0f,%.0f) %s" % [frames, p.global_position.x, p.global_position.y, p.velocity.x, p.velocity.y, key])

	# --drop-test: stand on L660b; A) down and jump in the same frame; B) down first, jump 10 frames later
	func _drop_test_frame() -> void:
		dt_frame += 1
		var f := dt_frame % 100
		if f == 1:
			p.global_position = Vector2(530.0, 652.0)
			p.velocity = Vector2.ZERO
			p.set_collision_mask_value(ledge_layer, true)
			print("--- ", "A: down + jump in one frame" if dt_frame < 100 else "B: down, then jump 10 frames later")
		var jump_at := 40 if dt_frame < 100 else 50
		if f == 40:
			Input.action_press("p1_down")
		if f == jump_at:
			Input.action_press("p1_jump")
		if f == jump_at + 2:
			Input.action_release("p1_jump")
		if f == 75:
			Input.action_release("p1_down")
		if f >= 37 and f <= jump_at + 12:
			print("  f%d floor=%s on_ledge=%s duck=%s down=%s jump_just=%s drop_t=%.2f mask6=%s y=%.1f vy=%.0f" % [f, p.is_on_floor(), p._on_ledge(), p.is_ducking,
				Input.is_action_pressed("p1_down"), Input.is_action_just_pressed("p1_jump"), p._drop_timer, p.get_collision_mask_value(ledge_layer), p.global_position.y, p.velocity.y])
		if f == 99:
			var fell: bool = p.global_position.y > 700.0
			dt_results.append(fell)
			print("  result: ", "fell through, y=%.0f" % p.global_position.y if fell else "still on the ledge, y=%.0f" % p.global_position.y)
			if dt_frame > 100:
				# B is how the brain drops (bot_brain.gd 4c). A is kept to show why: pressed
				# in the same frame, the duck costs the floor frame and a plain jump fires.
				exit_code = 0 if dt_results[1] else 1
				print("  same frame (A): ", "drops" if dt_results[0] else "jumps instead")
				print("✅ drop test: down first, then jump, drops through" if exit_code == 0 else "❌ drop test: down first, then jump, did not drop")
				done = true

	func _finish() -> void:
		var total := 0.0
		var worst := 0.0
		for secs in times:
			total += secs
			worst = maxf(worst, secs)
		var mean := total / maxf(float(times.size()), 1.0)
		brain.goal_override = Vector2.INF
		if failed.is_empty() and exit_code == 0:
			print("✅ nav_probe: %d/%d trips, mean %.1f s, max %.1f s, misses %d" % [times.size(), trips.size(), mean, worst, brain._stats["misses"]])
		else:
			exit_code = 1
			printerr("❌ nav_probe: %d/%d trips, failed: %s" % [times.size(), trips.size(), ", ".join(failed)])
		done = true

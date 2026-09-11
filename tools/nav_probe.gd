extends SceneTree
## The nav probe (v0.1.5). The real tower (the same bodies arena.gd builds from
## arena_layouts.gd), one real fighter, one bot brain told to walk to a spot
## (goal_override), and a list of trips from one surface to another: first the
## stacked spots where the soaks deadlocked, then random pairs. A trip passes
## when the fighter stands on the goal surface; it fails after TRIP_S seconds.
## Run it after touching bot_brain.gd, bot_nav.gd, the layout or the movement:
##   godot --headless --path . --fixed-fps 60 --script tools/nav_probe.gd -- --no-net [--trips=40] [--seed=5] [--difficulty=0.7]
## Debug: --only=N runs trip N alone and traces it.
## --drop-test (v0.1.7): the controls sweep, no brain, no trips. Keys are pressed between physics
## frames (from the SceneTree _process), like a real key: down, then jump 0 to 40 frames later, on
## three ledges, must drop; jump first must jump; down + jump on the solid FloorLeft must jump; jump +
## dash and a knight's jump + shield in one frame must print no jump trap. Expect "✅ drop test: N/N cases".
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
	if probe.drop_test and not probe.done:
		probe.drop_tick()
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
	# --drop-test: the sweep's cases and where it is
	const DROP_LEDGES := [["L660b", 530.0], ["L300a", 130.0], ["L800b", 440.0]]
	const SWEEP_MAX_D := 40
	const SETTLE := 30             # frames on the spot with no key before a case starts
	const P1_ACTIONS := ["p1_left", "p1_right", "p1_up", "p1_down", "p1_jump", "p1_dash", "p1_attack", "p1_special"]
	var cases: Array = []          # {group, label, x, top, class, events: [[frame, action, press]], end, expect}
	var case_i := -1
	var cf := 0                    # frame inside the case (negative while it settles)
	var settled := false
	var start_y := 0.0
	var min_y := 0.0
	var max_y := 0.0
	var traps_at_start := 0
	var misses: Array = []
	var groups: Array = []         # [group, passed, total] in order
	var last_phys := -1
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
			brain.set_process(false)
			_build_sweep()
			print("🧭 nav_probe: drop test, ", cases.size(), " cases, no brain")
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
		if drop_test:
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

	# --drop-test: build the cases. A case settles SETTLE frames on its spot, then its key events play.
	func _build_sweep() -> void:
		var ct: Dictionary = get_node("/root/Global").ClassType   # not Global.ClassType: naming Global here compiles global.gd and bot_brain.gd before the autoload exists
		var tops := {}
		for piece in layout["pieces"]:
			tops[str(piece["name"])] = float(piece["y"])
		for l in DROP_LEDGES:
			for d in range(0, SWEEP_MAX_D + 1):
				cases.append(_keys_case("%s: down, then jump 0-%d frames later" % [l[0], SWEEP_MAX_D],
					"%s jump %d frames after down" % [l[0], d], l[1], tops[l[0]], 0, d, "drop"))
		for d in [1, 3]:
			cases.append(_keys_case("L660b: jump first, then down", "L660b down %d frames after jump" % d,
				530.0, tops["L660b"], d, 0, "jump"))
		for d in [0, 1, 2, 8, 20]:
			cases.append(_keys_case("FloorLeft (solid): down + jump", "FloorLeft jump %d frames after down" % d,
				130.0, tops["FloorLeft"], 0, d, "jump"))
		cases.append({"group": "FloorLeft: jump + dash, one frame", "label": "FloorLeft jump + dash (right held)",
			"x": 130.0, "top": tops["FloorLeft"], "class": ct["RANGER"], "end": 70, "expect": "any",
			"events": [[0, "p1_right", true], [5, "p1_jump", true], [5, "p1_dash", true],
				[8, "p1_jump", false], [8, "p1_dash", false], [20, "p1_right", false]]})
		cases.append({"group": "FloorLeft: knight jump + shield, one frame", "label": "FloorLeft knight jump + shield",
			"x": 130.0, "top": tops["FloorLeft"], "class": ct["KNIGHT"], "end": 70, "expect": "any",
			"events": [[0, "p1_jump", true], [0, "p1_special", true], [3, "p1_jump", false], [3, "p1_special", false]]})
		# the jump trap's own lines (backlog 20): an action in the same frame that takes the jump's speed away
		cases.append({"group": "FloorLeft: jump + dash down-right, one frame", "label": "FloorLeft jump + dash (right + down held)",
			"x": 100.0, "top": tops["FloorLeft"], "class": ct["RANGER"], "end": 70, "expect": "any",
			"events": [[0, "p1_right", true], [0, "p1_down", true], [1, "p1_down", false], [1, "p1_jump", true], [1, "p1_dash", true],
				[4, "p1_jump", false], [4, "p1_dash", false], [20, "p1_right", false]]})
		cases.append({"group": "FloorLeft: ranger jump + special aimed up", "label": "FloorLeft ranger jump + special (up held)",
			"x": 130.0, "top": tops["FloorLeft"], "class": ct["RANGER"], "end": 70, "expect": "any",
			"events": [[0, "p1_up", true], [5, "p1_jump", true], [5, "p1_special", true], [8, "p1_jump", false], [8, "p1_special", false], [20, "p1_up", false]]})
		cases.append({"group": "FloorLeft: mage jump + blink, one frame", "label": "FloorLeft mage jump + blink (right held)",
			"x": 60.0, "top": tops["FloorLeft"], "class": ct["MAGE"], "end": 70, "expect": "any",
			"events": [[0, "p1_right", true], [5, "p1_jump", true], [5, "p1_special", true], [8, "p1_jump", false], [8, "p1_special", false], [20, "p1_right", false]]})

	func _keys_case(group: String, label: String, x: float, top: float, down_at: int, jump_at: int, expect: String) -> Dictionary:
		return {"group": group, "label": label, "x": x, "top": top, "class": 0,
			"end": maxi(down_at, jump_at) + 45, "expect": expect,
			"events": [[down_at, "p1_down", true], [jump_at, "p1_jump", true], [jump_at + 3, "p1_jump", false],
				[maxi(down_at, jump_at) + 20, "p1_down", false]]}

	func _traps() -> int:
		var n = p.get("jump_trap_count")
		return int(n) if n != null else -1

	# Called from the SceneTree's _process: after this frame's physics step, before the next one.
	func drop_tick() -> void:
		var pf := Engine.get_physics_frames()
		if last_phys >= 0 and pf - last_phys != 1:
			printerr("❌ drop test: %d physics steps in one frame; run it with --fixed-fps 60" % (pf - last_phys))
			exit_code = 1
			done = true
			return
		last_phys = pf
		if case_i < 0:
			_next_case()
			return
		var c: Dictionary = cases[case_i]
		cf += 1
		if cf < 0:
			return
		var y: float = p.global_position.y
		if cf == 0:
			settled = p.is_on_floor() and (c["expect"] != "drop" or p._on_ledge())
			start_y = y
			min_y = y
			max_y = y
			traps_at_start = _traps()
			if c["expect"] == "any":
				print("  case: ", c["label"])   # the trap lines that follow belong to this case
		else:
			min_y = minf(min_y, y)
			max_y = maxf(max_y, y)
		for e in c["events"]:
			if int(e[0]) == cf:
				if e[2]:
					Input.action_press(e[1])
				else:
					Input.action_release(e[1])
		if cf >= int(c["end"]):
			_judge(c)
			_next_case()

	func _next_case() -> void:
		for a in P1_ACTIONS:
			Input.action_release(a)
		case_i += 1
		if case_i >= cases.size():
			_sweep_finish()
			return
		var c: Dictionary = cases[case_i]
		p.class_type = c["class"]
		p.global_position = Vector2(c["x"], c["top"] - 8.0)
		p.velocity = Vector2.ZERO
		p._drop_timer = 0.0
		p.set_collision_mask_value(ledge_layer, true)
		p.is_dashing = false
		p.dash_timer = 0.0
		p.dash_cooldown_timer = 0.0
		p.is_shielding = false
		p.shield_timer = 0.0
		p.special_cooldown = 0.0
		p.current_arrows = 3
		p.mage_charges = 3
		p._sp_prev_x = INF   # the teleport is not speed
		cf = -SETTLE

	func _judge(c: Dictionary) -> void:
		var fell := max_y > start_y + 30.0
		var rose := min_y < start_y - 20.0
		var what := "drops" if fell and not rose else ("jumps" if rose else "stays")
		var ok := true
		if c["expect"] == "drop":
			ok = fell and not rose
		elif c["expect"] == "jump":
			ok = rose
		var now := _traps()
		if now >= 0 and now > traps_at_start:
			ok = false
			what += ", %d jump trap line(s)" % (now - traps_at_start)
		if not settled:
			ok = false
			what = "did not settle on its spot"
		var row: Array = []
		for g in groups:
			if g[0] == c["group"]:
				row = g
		if row.is_empty():
			row = [c["group"], 0, 0]
			groups.append(row)
		row[2] += 1
		if ok:
			row[1] += 1
		else:
			misses.append("%s: %s (want: %s)" % [c["label"], what, c["expect"]])

	func _sweep_finish() -> void:
		for g in groups:
			print("  ", str(g[0]).rpad(46), " %d/%d" % [g[1], g[2]])
		for m in misses:
			print("  MISS ", m)
		if _traps() < 0:
			print("  (this player.gd has no jump_trap_count: count the 🪤 lines in the output by hand)")
		var passed := cases.size() - misses.size()
		exit_code = 0 if misses.is_empty() and cases.size() > 0 else 1
		if exit_code == 0:
			print("✅ drop test: %d/%d cases" % [passed, cases.size()])
		else:
			printerr("❌ drop test: %d/%d cases, %d missed" % [passed, cases.size(), misses.size()])
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

# ==============================================================================
# BOT BRAIN (headless AI opponents)
# ==============================================================================
# Attached by arena.gd to the LOCAL fighter when the client runs with
#   godot --headless --path . -- --autojoin --ai=<persona> [--ai-seed=N] [--ai-difficulty=0..1]
# It never touches player.gd:
#   * it perceives by reading the scene tree (players / projectiles groups, the
#     arena platforms and powerup),
#   * it acts by pressing the same input actions a human presses
#     (Input.action_press / action_release on p<N>_left ... p<N>_special),
#   * it aims by feeding a synthetic InputEventMouseMotion into Input, so the
#     unchanged mouse-aim branch in player.gd reads it like a real mouse.
# Frame ordering: player.gd checks is_action_just_pressed(), which is only true
# in the physics frame the press happened. The brain runs BEFORE the fighter in
# the same physics frame (process_physics_priority below zero) and releases a
# tap on the next frame, so every press is seen exactly once.
# Human-likeness: decisions wait out a reaction delay (100-250 ms scaled by
# difficulty) before they reach the inputs, aim carries gaussian error, and a
# seeded RNG makes a run reproducible (--ai-seed).
# Routes (v0.1.5): scripts/bot_nav.gd turns the tower layout into places to
# stand and the moves between them, and _steer_to follows the route. Two stall
# guards stop a round running for hours: no kill for HUNT_AFTER_S makes every
# persona hunt, and a bot that gets nowhere for STUCK_S takes a detour.
# ==============================================================================
extends Node
# No class_name: the global class cache is only rebuilt by the editor, so
# headless builds reference this script via preload() instead.

const PERSONAS := ["wanderer", "chaser", "sniper", "turtle", "rusher", "griefer"]
const IMPLEMENTED := ["wanderer", "chaser", "sniper", "turtle", "rusher", "griefer"]
# Class a persona picks when the client was started without --class.
# Sniper plays mage: firebolt charges regenerate, the ranger's three arrows do not.
const DEFAULT_CLASS := {"wanderer": -1, "chaser": 1, "sniper": 2, "turtle": 1, "rusher": 3, "griefer": 4}
const PROJECTILE_SPEED := {0: 560.0, 2: 460.0, 3: 600.0, 4: 480.0}   # by ClassType: ranger, mage, rogue, druid (v0.1.3 pacing)
const PROJECTILE_GRAVITY := {0: 180.0, 2: 0.0, 3: 0.0, 4: 200.0}
const THINK_HZ := 10.0                   # decisions per second
const STATUS_EVERY := 5.0                # seconds between "🧠 [Bot]" status lines
const PlayerScript := preload("res://scripts/player.gd")
const ARENA_W := 640.0
const ARENA_H := 1080.0                  # v0.1.3: the tower, three screens
const ACTIONS := ["left", "right", "up", "down", "jump", "dash", "attack", "special"]
# Movement numbers from player.gd, for route planning.
const SPEED := PlayerScript.SPEED         # v0.1.3: read from the fighter, not a copy
const FALL_G := 1600.0
const SEAM_Y := ARENA_H + 16.0           # bottom wrap: out of the floor hole, in at the ceiling hole (y = -10)
const BotNav := preload("res://scripts/bot_nav.gd")
# v0.1.5 stall guards (the overnight soaks stalled for hours):
const HUNT_AFTER_S := 20.0               # no kill anywhere this long: every persona hunts
const STUCK_S := 4.0                     # wanting to move this long without getting anywhere: a detour
const DETOUR_S := 3.0                    # how long a detour lasts
const NAV_RETRY_S := 0.5                 # a route jump or drop is not pressed again sooner
const NAV_MISS_COST := 150.0             # route cost added per recent miss of a move
const NAV_MISS_FORGET_S := 60.0          # a missed move is forgiven after this long
const DROP_DOWN_S := 0.25                # "down" stays held this long after the drop's jump
const DROP_STEADY_FRAMES := 3            # frames standing on the ledge, down held, before the drop's jump
const NAV_LAUNCH_S := 1.2                # a pressed route move that has not left the floor by then missed
const LEAP_NEED_PX := 28.0               # a wide route jump dashes only if its ledge is further than this

var persona := "wanderer"
var seed_value := 0
var difficulty := 0.7
var reaction_delay := 0.15               # s, derived from difficulty in setup()
var aim_sigma_deg := 8.0                 # gaussian aim error, derived from difficulty

var rng := RandomNumberGenerator.new()
var fighter: CharacterBody2D = null
var prefix := ""
var _clock := 0.0                        # brain time, seconds since _ready
var _think_timer := 0.0
var _queue: Array = []                   # [{t, ctrl}] decisions waiting out the reaction delay
var _held := {}                          # action -> true while pressed by us
var _tap_release: Array = []             # actions pressed this frame, released next frame
var _jump_hold_left := 0.0
var _aim_world := Vector2.ZERO           # where the synthetic mouse points (world space)
var _has_aim := false
var _aim_frames := 0
var _aim_expect := Vector2.ZERO          # direction player.gd should have read last frame
var _last_enemy_pos := {}                # id -> Vector2, for the velocity estimate
var _enemy_vel := {}
var _status_timer := 0.0
var _aim_warned := false
var _stats := {"moves": 0, "jumps": 0, "dashes": 0, "attacks": 0, "specials": 0, "evades": 0,
	"aim_err_sum": 0.0, "aim_err_n": 0, "aim_err_max": 0.0, "decisions": 0,
	"drops": 0, "wraps": 0, "seams": 0, "land_sum": 0.0, "land_n": 0, "max_loop": 0, "shift_wraps": 0,
	"steps": 0, "misses": 0, "stucks": 0}

# steering state shared by the personas
var _stuck_time := 0.0                   # seconds spent pushing into a wall on the floor
var _w_target := Vector2(320, 200)       # wanderer / fallback roam target
var _w_retarget_at := 0.0
var _w_pause_until := 0.0
var _t_shield_until := 0.0               # turtle: when the current shield decision expires
var _t_counter_until := 0.0              # turtle: counter-attack window after a block
var _r_engage_until := 0.0               # rusher: committed to a burst on this target
var _goal := Vector2.ZERO                # where the persona is steering this tick
var _has_goal := false
var _leap_dash := false                  # tap dash at the apex of a wide route jump (v0.1.5)
var _climb_since := 0.0                  # brain time that jump was pressed
var _last_pos := Vector2.ZERO            # wrap statistics
var _wrap_at := -1.0                     # brain time of the last bottom wrap, -1 once landed
var _loop_len := 0                       # bottom wraps since the last landing
var _was_rotating := false               # arena.is_arena_rotating last frame (backlog 23)
var _g_mood := "harass"                  # griefer
var _g_mood_until := 0.0
var _g_goal := Vector2.ZERO
# route following and the stall guards (v0.1.5)
var goal_override := Vector2.INF         # tools/nav_probe.gd: steer only to this point (INF = off)
var _nav = null                          # bot_nav.gd built from the arena layout; null = no map
var _nav_step := {}                      # the route move being followed (bot_nav.gd), plus from / launched
var _nav_air := false                    # the last think tick was in the air
var _nav_pressed_at := -10.0             # brain time a route jump or drop was last pressed
var _nav_misses := {}                    # "i>j" -> [misses, brain time of the last one]
var _drop_state := 0                     # a drop-through: 0 none, 1 down held (waiting for a steady ledge), 2 jump sent
var _drop_frames := 0                    # frames in a row on the ledge while down is held
var _drop_since := 0.0
var _last_kill_at := 0.0                 # brain time of the last kill or round start anywhere
var _hunting := false
var _steer_moving := false               # this think tick's steering wanted to go somewhere
var _progress_surface := -1
var _progress_x := 0.0
var _progress_at := 0.0
var _detour_until := 0.0
var _detour_goal := Vector2.ZERO


func setup(p_persona: String, p_seed: int, p_difficulty: float) -> void:
	persona = p_persona if p_persona in PERSONAS else "wanderer"
	difficulty = clampf(p_difficulty, 0.0, 1.0)
	if p_seed == 0:
		rng.randomize()
		seed_value = int(rng.seed & 0x7fffffff)
		rng.seed = seed_value
	else:
		seed_value = p_seed
		rng.seed = seed_value
	reaction_delay = lerpf(0.25, 0.10, difficulty)
	aim_sigma_deg = lerpf(15.0, 2.5, difficulty)


func _ready() -> void:
	# Run before the fighter's _physics_process in the same physics frame.
	process_physics_priority = -10
	fighter = get_parent() as CharacterBody2D
	if fighter == null or not ("player_id" in fighter):
		push_error("[BotBrain] parent is not a fighter; brain disabled")
		set_physics_process(false)
		return
	prefix = "p" + str(fighter.player_id) + "_"
	if not InputMap.has_action(prefix + "left"):
		push_error("[BotBrain] no input map for " + prefix + "*; brain disabled")
		set_physics_process(false)
		return
	# Synthetic mouse events must apply immediately: the headless display server
	# never flushes Godot's accumulated-input buffer.
	Input.use_accumulated_input = false
	var arena = fighter.get_parent()
	if arena != null and "layout" in arena and not arena.layout.is_empty():
		_nav = BotNav.new()
		_nav.build(arena.layout)
	Global.net_player_died.connect(_on_player_died)
	Global.net_new_round.connect(_on_new_round)
	var note := "" if persona in IMPLEMENTED else " (not built yet: playing as wanderer)"
	print("🧠 [Bot] P%d persona=%s seed=%d difficulty=%.2f reaction=%.0fms aim_sigma=%.1f°%s nav=%s" % [
		fighter.player_id, persona, seed_value, difficulty, reaction_delay * 1000.0, aim_sigma_deg, note,
		("%d surfaces" % _nav.surfaces.size()) if _nav != null else "off"])


func _exit_tree() -> void:
	_release_all()
	if Global.net_player_died.is_connected(_on_player_died):
		Global.net_player_died.disconnect(_on_player_died)
	if Global.net_new_round.is_connected(_on_new_round):
		Global.net_new_round.disconnect(_on_new_round)


func _physics_process(delta: float) -> void:
	_clock += delta
	# 1. finish last frame's taps so player.gd saw exactly one just-pressed frame
	for a in _tap_release:
		_release(a)
	_tap_release.clear()

	if not _active():
		if not _held.is_empty():
			_release_all()
		_queue.clear()
		_has_aim = false
		return

	# 2. variable-height jumps: release after the decided hold time
	if _jump_hold_left > 0.0:
		_jump_hold_left -= delta
		if _jump_hold_left <= 0.0:
			_release("jump")

	# 3. think at THINK_HZ; the decision waits out the reaction delay in the queue
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer += 1.0 / THINK_HZ
		var snap := _perceive()
		var ctrl := _decide(snap)
		if not ctrl.is_empty():
			_stats["decisions"] += 1
			var jitter := rng.randf_range(0.7, 1.3)
			_queue.append({"t": _clock + reaction_delay * jitter, "ctrl": ctrl})

	# 4. apply every decision whose reaction delay has elapsed
	while _queue.size() > 0 and _queue[0]["t"] <= _clock:
		_apply(_queue.pop_front()["ctrl"])

	# 4b. frame-accurate follow-up: a wide route jump dashes toward its ledge at
	#     the apex (a dash ignores gravity, so an earlier one cuts the rise short),
	#     and only when the ledge is still out of reach (a dash overshoots a near one)
	if _leap_dash:
		var airborne := not fighter.is_on_floor()
		var apex := fighter.velocity.y > -90.0
		if airborne and apex and _clock - _climb_since > 0.12 and fighter.dash_cooldown_timer <= 0.0 and not fighter.is_dashing:
			_leap_dash = false
			if not _nav_step.is_empty():
				var fx := fighter.global_position.x
				if absf(clampf(fx, float(_nav_step["lx0"]), float(_nav_step["lx1"])) - fx) > LEAP_NEED_PX:
					_tap("dash")
					_stats["dashes"] += 1
		elif _clock - _climb_since > 0.8:
			_leap_dash = false

	# 4c. a drop-through (v0.1.5): down first, the jump once the fighter has stood
	#     on the ledge for DROP_STEADY_FRAMES with down held. Down and jump in the
	#     same frame jump instead: the duck costs the floor frame the drop needs
	#     (tools/nav_probe.gd --drop-test).
	if _drop_state == 1:
		if fighter.is_on_floor() and fighter._on_ledge():
			_drop_frames += 1
		else:
			_drop_frames = 0
		if _drop_frames >= DROP_STEADY_FRAMES:
			if _held.has("jump"):
				_release("jump")
				_jump_hold_left = 0.0
			_tap("jump")
			_drop_state = 2
			_drop_since = _clock
		elif _clock - _drop_since > 0.6:
			_release("down")
			_drop_state = 0
	elif _drop_state == 2 and (_clock - _drop_since > DROP_DOWN_S or fighter.velocity.y < -100.0):
		_release("down")
		_drop_state = 0
	_track_wraps()

	# 5. keep the synthetic mouse on the current aim point every frame. The
	#    fighter reads it later this frame (before it moves), so the self-check
	#    compares its aim now against what we asked for LAST frame.
	if _has_aim:
		_measure_aim()
		_push_mouse(_aim_world)
		_aim_expect = _aim_world - fighter.global_position

	# 6. status line for the harness logs
	_status_timer += delta
	if _status_timer >= STATUS_EVERY:
		_status_timer -= STATUS_EVERY
		_print_status()


# Count bottom wraps (y jumps from the floor band to the ceiling), seam crossings
# (x jumps across the arena) and the time from a wrap to the next landing.
func _track_wraps() -> void:
	var pos := fighter.global_position
	# v0.0.33 (backlog 23): the stage turn is a free fall by design (the platforms
	# are soft for 2.5 s). A wrap while arena.is_arena_rotating is counted apart
	# as shift_wraps and never joins a fall loop; the loop restarts clean when
	# the turn begins, so the fleet gate (max_loop >= 4) only sees real loops.
	var arena := fighter.get_parent()
	var rotating: bool = arena != null and ("is_arena_rotating" in arena) and arena.is_arena_rotating
	if rotating and not _was_rotating:
		_loop_len = 0
		_wrap_at = -1.0
	_was_rotating = rotating
	if fighter.spawn_invuln_timer < 0.99 and _last_pos != Vector2.ZERO:
		if _last_pos.y > ARENA_H - 60.0 and pos.y < 40.0:
			if rotating:
				_stats["shift_wraps"] += 1
			else:
				_stats["wraps"] += 1
				_loop_len += 1
				if _wrap_at < 0.0:
					_wrap_at = _clock
		if absf(pos.x - _last_pos.x) > 400.0:
			_stats["seams"] += 1
	if fighter.is_on_floor() and _wrap_at >= 0.0:
		_stats["land_sum"] += _clock - _wrap_at
		_stats["land_n"] += 1
		_stats["max_loop"] = maxi(_stats["max_loop"], _loop_len)
		_wrap_at = -1.0
		_loop_len = 0
	_last_pos = pos


func _active() -> bool:
	if not is_instance_valid(fighter):
		return false
	if not fighter.is_local_player or fighter.player_id < 1 or fighter.player_id > 4:
		return false
	if fighter.is_dead or fighter.is_egg or Global.is_spectator:
		return false
	return true


# ------------------------------------------------------------------------------
# PERCEPTION: one snapshot of the world, read from the scene tree
# ------------------------------------------------------------------------------
func _perceive() -> Dictionary:
	var me := fighter
	var snap := {
		"pos": me.global_position, "vel": me.velocity, "on_floor": me.is_on_floor(),
		"facing_right": me.is_facing_right, "dashing": me.is_dashing,
		"shielding": me.is_shielding, "bear": me.is_bear_form, "class": me.class_type,
		"dash_ready": me.dash_cooldown_timer <= 0.0, "attack_ready": me.attack_cooldown <= 0.0,
		"special_ready": me.special_cooldown <= 0.0,
		"enemies": [], "projectiles": [], "platforms": [], "powerup": null,
	}
	var seen := {}
	for p in get_tree().get_nodes_in_group("players"):
		if p == me or not is_instance_valid(p) or p.is_dead:
			continue
		var pid: int = p.player_id
		var pos: Vector2 = p.global_position
		var vel := Vector2.ZERO
		if _last_enemy_pos.has(pid):
			var raw: Vector2 = (pos - _last_enemy_pos[pid]) * THINK_HZ
			if raw.length() < 1500.0:   # a respawn / wrap jump is not a velocity
				vel = _enemy_vel.get(pid, Vector2.ZERO).lerp(raw, 0.5)
		_last_enemy_pos[pid] = pos
		_enemy_vel[pid] = vel
		seen[pid] = true
		snap["enemies"].append({"id": pid, "pos": pos, "vel": vel, "dashing": p.is_dashing,
			"shielding": p.is_shielding, "bear": p.is_bear_form, "egg": p.is_egg,
			"invuln": p.spawn_invuln_timer > 0.0,
			"dist": _wrapped_delta(me.global_position, pos).length()})
	for pid in _last_enemy_pos.keys():
		if not seen.has(pid):
			_last_enemy_pos.erase(pid)
			_enemy_vel.erase(pid)
	snap["pickups"] = []      # our own stuck arrows (walking over one refills the quiver)
	for pr in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(pr) or not ("shooter_id" in pr):
			continue
		if "is_stuck" in pr and pr.is_stuck:
			if pr.shooter_id == me.player_id:
				snap["pickups"].append(pr.global_position)
			continue
		if pr.shooter_id == me.player_id:
			continue
		snap["projectiles"].append({"pos": pr.global_position, "vel": pr.velocity, "shooter": pr.shooter_id})
	snap["ammo"] = _ammo()
	snap["threat"] = _inbound_threat(snap)
	var arena := me.get_parent()
	if _nav != null:
		# v0.1.5: only places to stand (ledge, bump and floor tops), so a roam or
		# retreat target is never inside a wall or the ceiling
		for sf: Dictionary in _nav.surfaces:
			snap["platforms"].append(Rect2(sf["x0"], sf["top"], sf["x1"] - sf["x0"], 12.0))
	else:
		# no layout table: read the collision shapes. v0.0.39: the ground slabs
		# live under arena.ground_node (anchored); the brain reads both nodes.
		var plat_nodes: Array = []
		if arena != null and "platforms_node" in arena and arena.platforms_node != null:
			plat_nodes.append(arena.platforms_node)
		if arena != null and "ground_node" in arena and arena.ground_node != null:
			plat_nodes.append(arena.ground_node)
		for pn in plat_nodes:
			for body in pn.get_children():
				for cs in body.get_children():
					if cs is CollisionShape2D and cs.shape is RectangleShape2D:
						var size: Vector2 = cs.shape.size
						snap["platforms"].append(cs.global_transform * Rect2(-size * 0.5, size))
	if arena != null and "powerup_node" in arena and is_instance_valid(arena.powerup_node):
		snap["powerup"] = arena.powerup_node.global_position
	return snap


# Displacement from a to b. v0.1.3: the tower has walls, so there is no
# horizontal seam to cross any more (the side passages are a route, not a
# wrap the brain plans through); the plain difference is the shortest way.
func _wrapped_delta(a: Vector2, b: Vector2) -> Vector2:
	var d := b - a
	return d


func _nearest_enemy(snap: Dictionary) -> Dictionary:
	var best := {}
	for e in snap["enemies"]:
		if e["invuln"]:
			continue
		if best.is_empty() or e["dist"] < best["dist"]:
			best = e
	if best.is_empty() and snap["enemies"].size() > 0:
		best = snap["enemies"][0]
	return best


func _ammo() -> int:
	match int(fighter.class_type):
		Global.ClassType.RANGER: return fighter.current_arrows
		Global.ClassType.MAGE: return fighter.mage_charges
		Global.ClassType.ROGUE: return fighter.rogue_kunai
		_: return 99


func _is_melee_class() -> bool:
	return fighter.class_type == Global.ClassType.KNIGHT or (fighter.class_type == Global.ClassType.DRUID and fighter.is_bear_form)


# Reach of the basic attack: sword 20 px offset + 14 px half-box, projectiles ~1 s of flight.
func _attack_range() -> float:
	return 40.0 if _is_melee_class() else 300.0


# The nearest projectile that will pass within 28 px of us: {t (s to closest approach), dist}.
func _inbound_threat(snap: Dictionary) -> Dictionary:
	var best := {}
	for pr in snap["projectiles"]:
		var rel: Vector2 = _wrapped_delta(pr["pos"], snap["pos"])   # projectile -> us
		var v: Vector2 = pr["vel"]
		var v2 := v.length_squared()
		if v2 < 1.0 or rel.dot(v) <= 0.0:
			continue   # standing still or flying away
		var t := rel.dot(v) / v2
		var miss := (rel - v * t).length()
		if t < 0.8 and miss < 28.0 and (best.is_empty() or t < best["t"]):
			best = {"t": t, "miss": miss, "from": pr["shooter"]}
	return best


# Point to aim at so a projectile of our class meets the target: solves
# |p + v t| = S t for the flight time, then lifts the aim for gravity drop.
func _lead_point(snap: Dictionary, enemy: Dictionary) -> Vector2:
	var cls := int(fighter.class_type)
	var speed: float = PROJECTILE_SPEED.get(cls, 650.0)
	var p: Vector2 = _wrapped_delta(snap["pos"], enemy["pos"])
	var v: Vector2 = enemy["vel"] * lerpf(0.4, 1.0, difficulty)   # weak players under-lead
	var a := v.length_squared() - speed * speed
	var b := 2.0 * p.dot(v)
	var c := p.length_squared()
	var t := 0.0
	if absf(a) < 1.0:
		t = -c / b if absf(b) > 0.001 else 0.0
	else:
		var disc := b * b - 4.0 * a * c
		if disc >= 0.0:
			var r := sqrt(disc)
			var t1 := (-b - r) / (2.0 * a)
			var t2 := (-b + r) / (2.0 * a)
			t = minf(t1, t2) if minf(t1, t2) > 0.0 else maxf(t1, t2)
	t = clampf(t, 0.0, 1.2)
	var aim: Vector2 = p + v * t
	aim.y -= 0.5 * PROJECTILE_GRAVITY.get(cls, 0.0) * t * t
	return snap["pos"] + aim


# The platform a straight fall from (x, y) lands on; {} when the column below is
# empty and the fall ends in the bottom wrap (out of the ceiling at y = -10).
func _platform_below(snap: Dictionary, x: float, y: float) -> Dictionary:
	var best := {}
	var rx := wrapf(x, 0.0, ARENA_W)
	for r: Rect2 in snap["platforms"]:
		if rx < r.position.x - 6.0 or rx > r.end.x + 6.0:
			continue
		if r.position.y < y + 8.0:
			continue   # above our feet
		if best.is_empty() or r.position.y < best["top"]:
			best = {"rect": r, "top": r.position.y}
	return best


func _fall_time(dy: float) -> float:
	return sqrt(2.0 * maxf(dy, 0.0) / FALL_G)


# Airborne over an empty column: the fall ends in the seam and we come back out of
# the ceiling, which is how this arena reaches its high ground. Pick the platform
# to come down on (closest to the goal among the ones air control can reach,
# else the highest reachable, else the nearest column so the next pass converges)
# and return the direction to hold.
func _landing_move(snap: Dictionary, goal: Vector2, has_goal: bool) -> int:
	var pos: Vector2 = snap["pos"]
	var t_seam := _fall_time(SEAM_Y - pos.y)
	var best_dx := 0.0
	var best_score := 1e9
	var near_dx := 0.0
	var near_abs := 1e9
	for r: Rect2 in snap["platforms"]:
		var cx := clampf(pos.x, r.position.x + 8.0, r.end.x - 8.0)
		var dx := wrapf(cx - pos.x, -ARENA_W * 0.5, ARENA_W * 0.5)
		var land_y := r.position.y - 12.0
		var t_land: float
		if land_y > pos.y + 8.0 and absf(dx) < 60.0:
			t_land = _fall_time(land_y - pos.y)             # still above it: direct
		else:
			t_land = t_seam + _fall_time(land_y + 10.0)     # through the seam
		var budget := SPEED * maxf(t_land - 0.1, 0.0)
		if absf(dx) < near_abs:
			near_abs = absf(dx)
			near_dx = dx
		if absf(dx) > budget:
			continue
		var score: float
		if has_goal:
			score = _wrapped_delta(Vector2(cx, land_y), goal).length()
		else:
			score = r.position.y + absf(dx) * 0.3          # highest first, nearer breaks ties
		if score < best_score:
			best_score = score
			best_dx = dx
	var dx := best_dx if best_score < 1e9 else near_dx
	return 0 if absf(dx) < 6.0 else int(signf(dx))


# One route move from the floor (v0.1.5): walk to its take-off stretch, then
# press. The press lands a reaction delay after the decision, so the position
# is predicted that far ahead.
func _follow_move(snap: Dictionary, m: Dictionary, here: int, ctrl: Dictionary) -> void:
	var pos: Vector2 = snap["pos"]
	var ahead: float = pos.x + snap["vel"].x * (reaction_delay + 0.05)
	_nav_step = m.duplicate()
	_nav_step["from"] = here
	_nav_step["launched"] = false
	var spot := clampf(pos.x, m["x0"], m["x1"])
	var can_press := _clock - _nav_pressed_at > NAV_RETRY_S
	match str(m["kind"]):
		"walkoff":
			ctrl["move"] = int(m["dir"])   # keep walking: the fall starts past the end
		"drop":
			if absf(ahead - spot) > 6.0:
				ctrl["move"] = int(signf(spot - pos.x)) if absf(spot - pos.x) > 6.0 else 0
			else:
				ctrl["move"] = 0
				if absf(snap["vel"].x) < 40.0 and can_press and _drop_state == 0:
					ctrl["drop_through"] = true
					_nav_press()
		_:
			# a gap wider than a running jump needs the dash at the apex: wait for it
			var dash_ok: bool = snap["dash_ready"] or not m.get("need_dash", false)
			if ahead >= m["x0"] and ahead <= m["x1"] and can_press and dash_ok:
				_nav_press()
				ctrl["jump"] = true
				ctrl["jump_hold"] = 0.3
				ctrl["leap"] = m["leap"]
				ctrl["move"] = int(m["dir"])
			elif pos.x >= m["x0"] and pos.x <= m["x1"]:
				ctrl["move"] = 0   # inside the stretch but carried past it: brake, press next tick
			else:
				ctrl["move"] = int(signf(spot - pos.x))


func _nav_press() -> void:
	_nav_step["launched"] = true
	_nav_pressed_at = _clock
	_stats["steps"] += 1


# Route bookkeeping, once per think tick before deciding. In the air, a walk-off
# that fell from its own end counts as launched; any other fall the route did
# not press (the far end with a turn still in the reaction queue, a shove) just
# ends the move. Back on the floor, a launched move that came down anywhere but
# its surface, or a press that never left the floor, is a miss: routes avoid
# that move for a while (NAV_MISS_COST, NAV_MISS_FORGET_S).
func _nav_track_floor(snap: Dictionary) -> void:
	if _nav_step.is_empty():
		_nav_air = not snap["on_floor"]
		return
	if not snap["on_floor"]:
		_nav_air = true
		if not _nav_step["launched"]:
			if _nav_step["kind"] == "walkoff" and absf(snap["pos"].x - float(_nav_step["x0"])) <= 24.0:
				_nav_step["launched"] = true
				_stats["steps"] += 1
			else:
				_nav_step = {}
		return
	if _nav_air:
		if _nav_step["launched"] and _nav.surface_at(snap["pos"]) != _nav_step["to"]:
			_nav_miss()
		_nav_step = {}
	elif not _nav_step["launched"]:
		_nav_step = {}   # not pressed yet: this tick's steering picks the move again
	elif _clock - _nav_pressed_at > NAV_LAUNCH_S:
		_nav_miss()      # pressed, but the floor never went away
		_nav_step = {}
	_nav_air = false


func _nav_miss() -> void:
	var key := "%d>%d" % [_nav_step["from"], _nav_step["to"]]
	var n: int = int(_nav_misses[key][0]) + 1 if _nav_misses.has(key) else 1
	_nav_misses[key] = [n, _clock]
	_stats["misses"] += 1


func _nav_penalty() -> Dictionary:
	var pen := {}
	for key in _nav_misses.keys():
		if _clock - float(_nav_misses[key][1]) > NAV_MISS_FORGET_S:
			_nav_misses.erase(key)
		else:
			pen[key] = NAV_MISS_COST * float(_nav_misses[key][0])
	return pen


# In the air on a route move: head for the landing stretch, judged where we will
# be when this decision reaches the keys.
func _air_steer(snap: Dictionary) -> int:
	var ahead: float = snap["pos"].x + snap["vel"].x * (reaction_delay + 0.1)
	var target := clampf(ahead, float(_nav_step["lx0"]) + 4.0, float(_nav_step["lx1"]) - 4.0)
	return 0 if absf(target - ahead) < 6.0 else int(signf(target - ahead))


# Walk toward a point. v0.1.5 (the tower): on another surface, follow the route
# from bot_nav.gd (jump up, drop through a ledge, walk off an end); on the same
# surface, walk, and hop a small rise or a blocked step. In the air, _decide
# steers a route move to its landing spot.
func _steer_to(snap: Dictionary, target: Vector2, ctrl: Dictionary, stop_dist := 8.0) -> void:
	var pos: Vector2 = snap["pos"]
	_goal = target
	_has_goal = true
	var d := _wrapped_delta(pos, target)
	ctrl["move"] = 0 if absf(d.x) < stop_dist else int(signf(d.x))
	if not snap["on_floor"]:
		return   # air control toward the target; _decide overrides it on a route move
	if _nav != null:
		if not _nav_step.is_empty() and _nav_step["launched"]:
			# the press is on its way (the reaction delay, the drop's duck): hold the take-off
			ctrl["move"] = 0 if _nav_step["kind"] == "drop" else int(_nav_step["dir"])
			_steer_moving = true
			return
		var here: int = _nav.surface_at(pos)
		var there: int = _nav.surface_under(target)
		if here >= 0 and there >= 0 and here != there:
			var m: Dictionary = _nav.next_move(here, pos.x, there, _nav_penalty())
			if not m.is_empty():
				_follow_move(snap, m, here, ctrl)
				_steer_moving = true
				return
	_steer_moving = ctrl["move"] != 0
	if ctrl["move"] != 0 and absf(snap["vel"].x) < 20.0:
		_stuck_time += 1.0 / THINK_HZ
	else:
		_stuck_time = 0.0
	var rise := -d.y
	if (rise > 24.0 and rise < BotNav.JUMP_RISE and absf(d.x) < 110.0) or _stuck_time > 0.3:
		ctrl["jump"] = true
		ctrl["jump_hold"] = 0.3 if rise > 50.0 else rng.randf_range(0.08, 0.2)
		_stuck_time = 0.0


# A standing spot on a platform that is far from the enemy but not too far from us.
func _retreat_point(snap: Dictionary, enemy: Dictionary) -> Vector2:
	var best: Vector2 = snap["pos"]
	var best_score := -1e9
	for r: Rect2 in snap["platforms"]:
		for fx in [0.25, 0.75]:
			var pt := Vector2(r.position.x + r.size.x * fx, r.position.y - 14.0)
			var score: float = _wrapped_delta(enemy["pos"], pt).length() - 0.6 * _wrapped_delta(snap["pos"], pt).length()
			if score > best_score:
				best_score = score
				best = pt
	return best


func _roam(snap: Dictionary, ctrl: Dictionary, prefer_high := false) -> void:
	# wanderer-style target picking, also the fallback when nobody is in sight
	if _clock >= _w_retarget_at:
		var plats: Array = snap["platforms"]
		if plats.size() > 0 and rng.randf() < (0.8 if prefer_high else 0.55):
			var r: Rect2 = plats[rng.randi() % plats.size()]
			if prefer_high:
				for _i in range(3):
					var alt: Rect2 = plats[rng.randi() % plats.size()]
					if alt.position.y < r.position.y:
						r = alt
			_w_target = Vector2(rng.randf_range(r.position.x + 12.0, r.end.x - 12.0), r.position.y - 14.0)
		else:
			_w_target = Vector2(rng.randf_range(30.0, ARENA_W - 30.0), snap["pos"].y)
		_w_retarget_at = _clock + rng.randf_range(0.8, 2.5)
	_steer_to(snap, _w_target, ctrl)


# React to an inbound projectile: dash through it (dash frames are invulnerable
# and catch arrows), else hop. Turtle overrides this with the shield.
func _evade(snap: Dictionary, ctrl: Dictionary) -> bool:
	var th: Dictionary = snap["threat"]
	if th.is_empty() or rng.randf() > lerpf(0.35, 0.95, difficulty):
		return false
	if th["t"] > reaction_delay + 0.35:
		return false
	_stats["evades"] += 1
	if snap["dash_ready"] and not snap["dashing"]:
		ctrl["dash"] = true
	elif snap["on_floor"]:
		ctrl["jump"] = true
		ctrl["jump_hold"] = 0.25
	return true


# ------------------------------------------------------------------------------
# DECISION: one control intent per think tick. Keys (all optional):
#   move: -1/0/1 held direction   aim: world point   jump: bool + jump_hold: s
#   dash / attack / special: one-frame taps
# ------------------------------------------------------------------------------
func _decide(snap: Dictionary) -> Dictionary:
	_nav_track_floor(snap)
	_has_goal = false
	_steer_moving = false
	var ctrl: Dictionary
	var hunting := _is_hunting()
	if goal_override.is_finite():
		ctrl = {}
		_steer_to(snap, goal_override, ctrl, 6.0)
	elif _clock < _detour_until:
		ctrl = _decide_detour(snap)
	elif hunting and persona != "rusher":
		ctrl = _decide_chaser(snap)
	else:
		match persona:
			"chaser":
				ctrl = _decide_chaser(snap)
			"sniper":
				ctrl = _decide_sniper(snap)
			"turtle":
				ctrl = _decide_turtle(snap)
			"rusher":
				ctrl = _decide_rusher(snap)
			"griefer":
				ctrl = _decide_griefer(snap)
			_:
				ctrl = _decide_wanderer(snap)
	_watch_progress(snap)
	if not snap["on_floor"] and not _nav_step.is_empty():
		# Airborne on a route move (v0.1.5): steer for its landing stretch, whatever was held.
		ctrl["move"] = _air_steer(snap)
		ctrl.erase("jump")
	elif not snap["on_floor"] and _platform_below(snap, snap["pos"].x, snap["pos"].y).is_empty():
		# Airborne over an empty column: this fall ends in the bottom seam and comes
		# out of the ceiling. Air-steer to the landing platform, whatever was held.
		var goal: Vector2 = _goal if _has_goal else snap["pos"]
		if not _has_goal:
			var enemy := _nearest_enemy(snap)
			if not enemy.is_empty():
				goal = enemy["pos"]
		ctrl["move"] = _landing_move(snap, goal, _has_goal or goal != snap["pos"])
		ctrl.erase("jump")
	return ctrl


func _decide_wanderer(snap: Dictionary) -> Dictionary:
	var ctrl := {}
	var pos: Vector2 = snap["pos"]
	if _clock < _w_pause_until:
		ctrl["move"] = 0
		return ctrl
	if _clock >= _w_retarget_at and rng.randf() < 0.25:
		# stand still for a moment (exercises idle suppression on the send path)
		_w_pause_until = _clock + rng.randf_range(0.3, 1.2)
		_w_retarget_at = _w_pause_until
		ctrl["move"] = 0
		return ctrl
	_roam(snap, ctrl)
	if snap["on_floor"] and not ctrl.has("jump") and rng.randf() < 0.04:
		ctrl["jump"] = true
		ctrl["jump_hold"] = rng.randf_range(0.05, 0.3)
	if snap["dash_ready"] and rng.randf() < 0.02 + 0.03 * difficulty:
		ctrl["dash"] = true
	var enemy := _nearest_enemy(snap)
	if not enemy.is_empty():
		ctrl["aim"] = enemy["pos"]
		if snap["attack_ready"] and enemy["dist"] < 280.0 and rng.randf() < 0.15 + 0.35 * difficulty:
			ctrl["attack"] = true
	else:
		var face: int = ctrl["move"] if ctrl["move"] != 0 else (1 if snap["facing_right"] else -1)
		ctrl["aim"] = pos + Vector2(face * 120.0, rng.randf_range(-40.0, 40.0))
		if snap["attack_ready"] and rng.randf() < 0.08:
			ctrl["attack"] = true
	if snap["special_ready"] and rng.randf() < 0.03:
		ctrl["special"] = true
	return ctrl


# CHASER: close the distance, jump what is in the way, dash into range, swing.
func _decide_chaser(snap: Dictionary) -> Dictionary:
	var ctrl := {}
	var enemy := _nearest_enemy(snap)
	if enemy.is_empty():
		_roam(snap, ctrl)
		return ctrl
	var d := _wrapped_delta(snap["pos"], enemy["pos"])
	var reach := _attack_range()
	ctrl["aim"] = enemy["pos"] if _is_melee_class() else _lead_point(snap, enemy)
	if _evade(snap, ctrl):
		ctrl["move"] = int(signf(d.x)) if absf(d.x) > 8.0 else 0
		return ctrl
	if enemy["dist"] > reach * 0.8:
		_steer_to(snap, enemy["pos"], ctrl, reach * 0.6)
	else:
		ctrl["move"] = 0
	# target above and close: hop up to it (stomps happen if we land on it)
	if snap["on_floor"] and d.y < -30.0 and d.y > -BotNav.JUMP_RISE and absf(d.x) < 60.0 and not ctrl.has("jump"):
		ctrl["jump"] = true
		ctrl["jump_hold"] = 0.3
	# dash to engage: same height, medium range, dash ready
	if snap["dash_ready"] and enemy["dist"] > 70.0 and enemy["dist"] < 190.0 and absf(d.y) < 30.0 \
			and rng.randf() < lerpf(0.15, 0.6, difficulty):
		ctrl["dash"] = true
	if snap["attack_ready"] and enemy["dist"] < reach * lerpf(1.3, 1.0, difficulty) \
			and not enemy["shielding"] and not enemy["dashing"]:
		ctrl["attack"] = true
	return ctrl


# SNIPER: keep a standoff band, take high ground, lead every shot, refill.
func _decide_sniper(snap: Dictionary) -> Dictionary:
	var ctrl := {}
	var enemy := _nearest_enemy(snap)
	if snap["ammo"] <= 0 and snap["pickups"].size() > 0:
		var best: Vector2 = snap["pickups"][0]
		for q in snap["pickups"]:
			if _wrapped_delta(snap["pos"], q).length() < _wrapped_delta(snap["pos"], best).length():
				best = q
		_steer_to(snap, best, ctrl, 4.0)
		if not enemy.is_empty():
			ctrl["aim"] = _lead_point(snap, enemy)
		return ctrl
	if enemy.is_empty():
		_roam(snap, ctrl, true)
		return ctrl
	var d := _wrapped_delta(snap["pos"], enemy["pos"])
	ctrl["aim"] = _lead_point(snap, enemy)
	if _evade(snap, ctrl):
		ctrl["move"] = -int(signf(d.x)) if absf(d.x) > 1.0 else 1
		return ctrl
	var near := lerpf(120.0, 170.0, difficulty)
	var far := 280.0
	if enemy["dist"] < near:
		# back off to the platform that gains the most distance; a jump breaks a melee approach
		_steer_to(snap, _retreat_point(snap, enemy), ctrl, 6.0)
		if snap["on_floor"] and enemy["dist"] < 70.0 and rng.randf() < 0.5:
			ctrl["jump"] = true
			ctrl["jump_hold"] = 0.3
		if snap["dash_ready"] and enemy["dist"] < 60.0 and ctrl["move"] != 0:
			ctrl["dash"] = true
	elif enemy["dist"] > far:
		_steer_to(snap, enemy["pos"], ctrl, far * 0.8)
	else:
		# in the band: settle on high ground now and then, otherwise hold
		if _clock >= _w_retarget_at:
			_roam(snap, ctrl, true)
			_w_retarget_at = _clock + rng.randf_range(1.5, 3.5)
		else:
			ctrl["move"] = 0
	if snap["attack_ready"] and snap["ammo"] > 0 and enemy["dist"] < 340.0 \
			and not enemy["shielding"] and not enemy["dashing"] \
			and rng.randf() < lerpf(0.4, 0.9, difficulty):
		ctrl["attack"] = true
	return ctrl


# TURTLE: hold ground, shield inbound projectiles and dashes, punish up close.
func _decide_turtle(snap: Dictionary) -> Dictionary:
	var ctrl := {}
	var enemy := _nearest_enemy(snap)
	if enemy.is_empty():
		ctrl["move"] = 0
		return ctrl
	var d := _wrapped_delta(snap["pos"], enemy["pos"])
	ctrl["aim"] = enemy["pos"]
	var th: Dictionary = snap["threat"]
	var melee_rush: bool = enemy["dashing"] and enemy["dist"] < 110.0 and absf(d.y) < 30.0
	# No shield while falling toward the seam: the shield branch in player.gd has no
	# air control, so a shielded fall chains through the wrap (same rule as the griefer).
	var can_shield: bool = snap["on_floor"] or not _platform_below(snap, snap["pos"].x, snap["pos"].y).is_empty()
	if can_shield and _clock >= _t_shield_until and snap["special_ready"] and not snap["shielding"] and (melee_rush or (not th.is_empty() and th["t"] < reaction_delay + 0.3)):
		if rng.randf() < lerpf(0.5, 0.97, difficulty):
			ctrl["special"] = true          # knight: shield 0.38 s; druid in the air: 1.5 s
			_t_shield_until = _clock + 0.6
			_t_counter_until = _clock + 1.5
			_stats["evades"] += 1
			ctrl["move"] = 0
			return ctrl
	if snap["shielding"]:
		ctrl["move"] = 0
		return ctrl
	var reach := _attack_range()
	var countering := _clock < _t_counter_until
	# punish anyone inside the engage circle; chase a little further after a block
	var engage := 100.0 if _is_melee_class() else reach
	if enemy["dist"] < engage or (countering and enemy["dist"] < 170.0):
		if enemy["dist"] > reach * 0.8:
			_steer_to(snap, enemy["pos"], ctrl, reach * 0.6)
		else:
			ctrl["move"] = 0
		if snap["attack_ready"] and enemy["dist"] < reach * 1.15 and not enemy["shielding"] and not enemy["dashing"]:
			ctrl["attack"] = true
	elif enemy["dist"] > 220.0 and not _is_melee_class():
		ctrl["move"] = 0
		if snap["attack_ready"] and snap["ammo"] > 0 and rng.randf() < 0.3:
			ctrl["aim"] = _lead_point(snap, enemy)
			ctrl["attack"] = true
	elif enemy["dist"] > 240.0:
		# nobody coming: drift closer, slowly and stop again
		_steer_to(snap, enemy["pos"], ctrl, 200.0)
	else:
		ctrl["move"] = 0
	return ctrl


# RUSHER: burst mobility. Dash-slash (rogue special) into the target, kunai at
# point blank, hop and stomp, dash out when a projectile is inbound.
func _decide_rusher(snap: Dictionary) -> Dictionary:
	var ctrl := {}
	var enemy := _nearest_enemy(snap)
	if enemy.is_empty():
		_roam(snap, ctrl)
		if snap["dash_ready"] and rng.randf() < 0.1:
			ctrl["dash"] = true
		return ctrl
	var d := _wrapped_delta(snap["pos"], enemy["pos"])
	ctrl["aim"] = enemy["pos"]
	if _evade(snap, ctrl):
		return ctrl
	if enemy["dist"] > 150.0:
		_steer_to(snap, enemy["pos"], ctrl, 20.0)
		if snap["dash_ready"] and absf(d.y) < 40.0 and enemy["dist"] < 260.0 and rng.randf() < 0.5:
			ctrl["dash"] = true
	else:
		# engaged: keep pressure, stay airborne, land on heads
		_steer_to(snap, enemy["pos"], ctrl, 14.0)
		if _clock >= _r_engage_until and snap["special_ready"] and enemy["dist"] < 140.0 and not enemy["shielding"] \
				and rng.randf() < lerpf(0.3, 0.8, difficulty):
			ctrl["special"] = true          # rogue: dash + shadow slash along the aim
			_r_engage_until = _clock + 0.5
		if snap["attack_ready"] and snap["ammo"] > 0 and enemy["dist"] < 120.0 and not enemy["shielding"] and not enemy["dashing"]:
			ctrl["attack"] = true
		if snap["on_floor"] and not ctrl.has("jump") and (d.y < -20.0 or rng.randf() < 0.25):
			ctrl["jump"] = true
			ctrl["jump_hold"] = rng.randf_range(0.1, 0.3)
	return ctrl


# GRIEFER (druid): deliberate edge cases. Moods rotate every 2-5 s: "wrap" heads
# for the highest ground (the route often runs out of the floor hole and in at
# the ceiling), "camp" sits on / falls through the powerup, "harass" plays a
# chaser that dashes INTO projectiles, spams the air shield and toggles bear
# form whenever it is on the floor. v0.1.5: the "seam" mood is gone; the tower
# has walls, and that mood pinned the griefer against the left one for hours.
func _decide_griefer(snap: Dictionary) -> Dictionary:
	var ctrl := {}
	var pos: Vector2 = snap["pos"]
	var enemy := _nearest_enemy(snap)
	var plats: Array = snap["platforms"]
	if _clock >= _g_mood_until:
		var moods := ["wrap", "harass", "harass"]
		if snap["powerup"] != null:
			moods.append("camp")
			moods.append("camp")
		_g_mood = moods[rng.randi() % moods.size()]
		_g_mood_until = _clock + rng.randf_range(2.0, 5.0)
		if _g_mood == "wrap" and plats.size() > 0:
			var top: Rect2 = plats[0]
			for r: Rect2 in plats:
				if r.position.y < top.position.y:
					top = r
			_g_goal = Vector2(rng.randf_range(top.position.x + 10.0, top.end.x - 10.0), top.position.y - 14.0)
	if not enemy.is_empty():
		ctrl["aim"] = enemy["pos"] if _is_melee_class() else _lead_point(snap, enemy)
	# dash INTO an inbound projectile (dash frames are invulnerable)
	var th: Dictionary = snap["threat"]
	if not th.is_empty() and th["t"] < reaction_delay + 0.35 and snap["dash_ready"]:
		for e in snap["enemies"]:
			if e["id"] == th["from"]:
				ctrl["move"] = int(signf(_wrapped_delta(pos, e["pos"]).x))
		ctrl["dash"] = true
		_stats["evades"] += 1
		return ctrl
	match _g_mood:
		"wrap":
			_steer_to(snap, _g_goal, ctrl, 10.0)
			if snap["on_floor"] and absf(_wrapped_delta(pos, _g_goal).y) < 20.0:
				_g_mood_until = _clock   # arrived: pick the next mood
		"camp":
			if snap["powerup"] == null:
				_g_mood_until = _clock
			else:
				_steer_to(snap, snap["powerup"], ctrl, 6.0)
		_:
			if enemy.is_empty():
				_roam(snap, ctrl, true)
			else:
				var reach := _attack_range()
				if enemy["dist"] > reach * 0.8:
					_steer_to(snap, enemy["pos"], ctrl, reach * 0.6)
				else:
					ctrl["move"] = 0
				if snap["attack_ready"] and enemy["dist"] < reach and not enemy["shielding"] and not enemy["dashing"]:
					ctrl["attack"] = true
	# unpredictable toggles: bear form on the floor, the 1.5 s shield in the air.
	# Not while falling toward the seam: the shield branch in player.gd ignores
	# input, so a shielded fall has no air control and chains through the wrap.
	if snap["special_ready"] and not ctrl.has("special"):
		if snap["on_floor"] and rng.randf() < 0.12:
			ctrl["special"] = true
		elif not snap["on_floor"] and rng.randf() < 0.3 and not _platform_below(snap, pos.x, pos.y).is_empty():
			ctrl["special"] = true
	return ctrl


# ------------------------------------------------------------------------------
# STALL GUARDS (v0.1.5): overnight soaks stalled for hours with two fighters
# that never met (docs/reference/bot-soak-2026-09-08.md)
# ------------------------------------------------------------------------------
func _on_player_died(_killer_id, _victim_id, _stock, _weapon) -> void:
	_last_kill_at = _clock


func _on_new_round(_round_num) -> void:
	_last_kill_at = _clock


# No kill anywhere for HUNT_AFTER_S: a sniper keeping its distance, a turtle
# holding its ground and a griefer in a mood all go and find someone.
func _is_hunting() -> bool:
	var hunting := _clock - _last_kill_at > HUNT_AFTER_S
	if hunting != _hunting:
		_hunting = hunting
		if hunting:
			print("🧭 [BotNav] P%d hunt on: no kill for %.0f s" % [fighter.player_id, _clock - _last_kill_at])
	return hunting


# Steering that wanted to move for STUCK_S without leaving its surface or
# getting 24 px along it: head for a random surface for DETOUR_S, then try again.
func _watch_progress(snap: Dictionary) -> void:
	if not snap["on_floor"] or goal_override.is_finite():
		return
	var here: int = _nav.surface_at(snap["pos"]) if _nav != null else -1
	if not _steer_moving or here != _progress_surface or absf(snap["pos"].x - _progress_x) > 24.0:
		_progress_surface = here
		_progress_x = snap["pos"].x
		_progress_at = _clock
		return
	var plats: Array = snap["platforms"]
	if _clock - _progress_at < STUCK_S or plats.is_empty():
		return
	_stats["stucks"] += 1
	var r: Rect2 = plats[rng.randi() % plats.size()]
	_detour_goal = Vector2(rng.randf_range(r.position.x + 12.0, maxf(r.end.x - 12.0, r.position.x + 12.0)), r.position.y - 14.0)
	_detour_until = _clock + DETOUR_S
	_progress_at = _clock
	_nav_step = {}
	var there: int = _nav.surface_under(_goal) if _nav != null else -1
	print("🧭 [BotNav] P%d stuck %.0f s on %s at (%.0f,%.0f), goal (%.0f,%.0f) on %s: detour to (%.0f,%.0f)" % [
		fighter.player_id, STUCK_S, _nav.surface_name(here) if _nav != null else "-", snap["pos"].x, snap["pos"].y,
		_goal.x, _goal.y, _nav.surface_name(there) if _nav != null else "-", _detour_goal.x, _detour_goal.y])


func _decide_detour(snap: Dictionary) -> Dictionary:
	var ctrl := {}
	_steer_to(snap, _detour_goal, ctrl, 10.0)
	var enemy := _nearest_enemy(snap)
	if not enemy.is_empty():
		ctrl["aim"] = enemy["pos"] if _is_melee_class() else _lead_point(snap, enemy)
		if snap["attack_ready"] and enemy["dist"] < _attack_range() and not enemy["shielding"]:
			ctrl["attack"] = true
	return ctrl


# ------------------------------------------------------------------------------
# ACTUATION: intents become input actions and synthetic mouse motion
# ------------------------------------------------------------------------------
func _apply(ctrl: Dictionary) -> void:
	if ctrl.has("move"):
		var mv: int = ctrl["move"]
		var want_left := mv < 0
		var want_right := mv > 0
		if want_left != _held.has("left") or want_right != _held.has("right"):
			_stats["moves"] += 1
		_set_held("left", want_left)
		_set_held("right", want_right)
	if ctrl.has("aim"):
		var d: Vector2 = _wrapped_delta(fighter.global_position, ctrl["aim"])
		if d.length_squared() < 1.0:
			d = Vector2.RIGHT
		d = d.rotated(deg_to_rad(rng.randfn(0.0, aim_sigma_deg)))
		_aim_world = fighter.global_position + d
		if not _has_aim:
			_aim_frames = 0
		_has_aim = true
	if ctrl.get("drop_through", false) and _drop_state == 0:
		# down now; the jump follows in _physics_process once the fighter stands steady (4c)
		_press("down")
		_drop_state = 1
		_drop_frames = 0
		_drop_since = _clock
		_stats["drops"] += 1
	elif ctrl.get("jump", false) and not _held.has("jump") and _drop_state == 0:
		_press("jump")
		_jump_hold_left = maxf(float(ctrl.get("jump_hold", 0.1)), 2.0 / 60.0)
		_stats["jumps"] += 1
		if ctrl.get("leap", false):
			_leap_dash = true
			_climb_since = _clock
	if ctrl.get("dash", false):
		_tap("dash")
		_stats["dashes"] += 1
	if ctrl.get("attack", false):
		_tap("attack")
		_stats["attacks"] += 1
	if ctrl.get("special", false):
		_tap("special")
		_stats["specials"] += 1


func _set_held(action: String, on: bool) -> void:
	if on and not _held.has(action):
		_press(action)
	elif not on and _held.has(action):
		_release(action)


func _press(action: String) -> void:
	Input.action_press(prefix + action)
	_held[action] = true


func _release(action: String) -> void:
	Input.action_release(prefix + action)
	_held.erase(action)


func _tap(action: String) -> void:
	if _held.has(action):
		return
	_press(action)
	_tap_release.append(action)


func _release_all() -> void:
	if prefix == "":
		return
	for a in ACTIONS:
		if InputMap.has_action(prefix + a):
			Input.action_release(prefix + a)
	_held.clear()
	_tap_release.clear()
	_jump_hold_left = 0.0
	_leap_dash = false
	_drop_state = 0


# player.gd aims the local fighter at get_global_mouse_position(), which is
# Input's mouse position mapped through the viewport's final and canvas
# transforms. Feeding a mouse-motion event at the inverse mapping of the world
# aim point makes the unchanged aim code look exactly where the brain wants.
func _push_mouse(world: Vector2) -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var screen: Vector2 = vp.get_final_transform() * (vp.get_canvas_transform() * world)
	var ev := InputEventMouseMotion.new()
	ev.position = screen
	ev.global_position = screen
	ev.relative = screen - vp.get_mouse_position()
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	_aim_frames += 1


func _measure_aim() -> void:
	# Self-check that the synthetic mouse reaches player.gd: last frame's push
	# must be the direction the fighter is aiming now. Dash and shield frames
	# skip the aim code in player.gd, and a near-zero vector is ignored there.
	if _aim_frames < 2 or fighter.is_dashing or fighter.is_shielding:
		return
	var want := _aim_expect
	if want.length_squared() < 1.0:
		return
	var err := absf(rad_to_deg(want.angle_to(fighter.aim_direction)))
	_stats["aim_err_sum"] += err
	_stats["aim_err_n"] += 1
	_stats["aim_err_max"] = maxf(_stats["aim_err_max"], err)


func _print_status() -> void:
	var mean_err := 0.0
	if _stats["aim_err_n"] > 0:
		mean_err = _stats["aim_err_sum"] / _stats["aim_err_n"]
	var land_avg := 0.0
	if _stats["land_n"] > 0:
		land_avg = _stats["land_sum"] / _stats["land_n"]
	print("🧠 [Bot %s P%d %.0fs] pos=(%.0f,%.0f) decisions=%d moves=%d jumps=%d dashes=%d attacks=%d specials=%d evades=%d | wraps=%d drops=%d seams=%d land_avg=%.2fs max_loop=%d shift=%d | aim err mean %.1f° max %.1f° over %d frames | held=%s queue=%d | nav surf=%s steps=%d misses=%d stucks=%d hunt=%d" % [
		persona, fighter.player_id, _clock, fighter.global_position.x, fighter.global_position.y,
		_stats["decisions"], _stats["moves"], _stats["jumps"], _stats["dashes"], _stats["attacks"], _stats["specials"], _stats["evades"],
		_stats["wraps"], _stats["drops"], _stats["seams"], land_avg, _stats["max_loop"], _stats["shift_wraps"],
		mean_err, _stats["aim_err_max"], _stats["aim_err_n"], ",".join(_held.keys()), _queue.size(),
		_nav.surface_name(_nav.surface_at(fighter.global_position)) if _nav != null else "-",
		_stats["steps"], _stats["misses"], _stats["stucks"], int(_hunting)])
	if _stats["aim_err_n"] > 60 and mean_err > 1.0 and not _aim_warned:
		_aim_warned = true
		push_warning("[BotBrain] synthetic mouse aim is not reaching player.gd (mean error %.1f°)" % mean_err)
	_send_status(mean_err, land_avg)


# The bot card for the server dashboard (v0.0.22). The same numbers as the
# printed line, as a small packet the server keeps in status.json. The server
# never sends it on to the other players. The "state", "target", "goal",
# "combat" and "learning" slots are empty for now: they are the shape a future
# smarter brain (or a learning brain) will fill in, and the dashboard already
# knows how to draw them.
func _send_status(mean_err: float, land_avg: float) -> void:
	var state = null
	if _clock < _detour_until:
		state = "detour"
	elif _hunting:
		state = "hunt"
	elif persona == "griefer":
		state = _g_mood        # the griefer already has a mood, so it can show it
	var goal = null
	if _has_goal:
		goal = [roundi(_goal.x), roundi(_goal.y)]
	Global.send_net_data({
		"type": "bot_status",
		"schema": 1,
		"kind": "brain",
		"persona": persona,
		"seed": seed_value,
		"difficulty": snappedf(difficulty, 0.01),
		"uptime_s": roundi(_clock),
		"state": state,
		"target": null,
		"goal": goal,
		"actions": {
			"decisions": _stats["decisions"], "moves": _stats["moves"], "jumps": _stats["jumps"],
			"dashes": _stats["dashes"], "attacks": _stats["attacks"], "specials": _stats["specials"],
			"evades": _stats["evades"],
		},
		"nav": {
			"wraps": _stats["wraps"], "drops": _stats["drops"], "seams": _stats["seams"],
			"land_avg_s": snappedf(land_avg, 0.01), "max_loop": _stats["max_loop"],
			"shift_wraps": _stats["shift_wraps"],
			"steps": _stats["steps"], "misses": _stats["misses"], "stucks": _stats["stucks"],
		},
		"aim": {
			"err_mean_deg": snappedf(mean_err, 0.1), "err_max_deg": snappedf(_stats["aim_err_max"], 0.1),
			"frames": _stats["aim_err_n"],
		},
		"combat": {"kills": null, "deaths": null, "shots": null, "hits": null,
			"accuracy": null, "air_time_pct": null, "damage_dealt": null},
		"learning": {"episode": null, "reward": null, "weights": {}, "deltas": {}},
	})

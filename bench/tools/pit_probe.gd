# THE HAUNTED HOUSE's pit (bottom left, under the ledge by the left wall), measured.
# The user, 2026-10-25: "You have to wall jump and dash to get out. Its really hard to
# do that repeatedly with intention."
# Part 1, the moves: a "kid" presses jump a moment after it sees its fighter touch a
# wall (3 to 12 ticks), steers this way or that at the press (a thumb is not exact),
# lets go of jump after 6 to 20 ticks, and some kids dash up near the top of a jump.
# Many tries from five spots on the pit's floor: how many get out within 4 s, and how
# fast. With the old rules (sim.tf_moves off) and the new ones.
# Part 2, the phone stick (client/touch_sticks.gd itself): the fighter slides down a
# wall of the pit with the thumb up toward it; five moves a kid makes to jump off it
# (dip the thumb level and back up, pump it down and up, swing it over the top, from
# level flick it straight up, lift it and touch again): which ones jump off, on both
# walls. Old stick (sticks.pump off) and new.
#   godot --headless --path bench --script res://tools/pit_probe.gd [-- --tries=400 --seed=1]
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const Sticks = preload("res://client/touch_sticks.gd")

const ARENA := 3                 # THE HAUNTED HOUSE
const EXIT_Y := 690              # the ledge over the pit and the pillar's top: standing at or above it = out
const STARTS := [80, 120, 165, 210, 250]   # feet x on the pit's floor (y 1020); the pit's room is x 60 to 270
const FLOOR_Y := 1020
const MAX_T := 240

var tries := 400
var seed_value := 1

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tries="):
			tries = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
	var sim = _sim()
	print("THE HAUNTED HOUSE's pit: x 60 to 270, floor y %d, out = standing at y %d or above" % [FLOOR_Y, EXIT_Y])
	var modes: Array = [false, true] if "tf_moves" in sim else [false]
	print("\nPart 1, the moves (%d tries a row, 4 s each)" % tries)
	for new_rules in modes:
		for dash in [false, true]:
			_kid_row(new_rules, dash)
	print("\nPart 2, the phone stick")
	var sticks_new: Array = [false, true] if "pump" in Sticks.new() else [false]
	for new_rules in modes:
		for pump in sticks_new:
			_stick_row(new_rules, pump)
	quit(0)

func _sim():
	var sim = SimScript.new(0, 24, 7)
	sim.set_arena(ARENA)
	sim.respawn = false
	sim.power_arrows = false
	sim.start_round([{"id": 0, "bot": false}])
	sim.pet_at = -1
	sim.bats_at = -1
	sim.candy_t = -1
	return sim

func _fresh(new_rules: bool, feet_x: int):
	var sim = _sim()
	if "tf_moves" in sim:
		sim.tf_moves = new_rules
	var f = sim.fighters[0]
	sim._place(f, Vector2i(feet_x, FLOOR_Y))
	sim.step()
	sim.take_events()
	return sim

static func _out(f) -> bool:
	return f.on_ground and f.y + 63 <= EXIT_Y and f.state != P.F_DEAD

# ------------------------------------------------------------------ part 1
class Kid:
	var rng := RandomNumberGenerator.new()
	var dash_habit := false
	var hold := 0
	var steer := 0
	var steer_next := 0
	var steer_in := -1
	var press_in := -1
	var press_steer := 0
	var saw_wall := 0
	var dash_in := -1
	var dash_way := 0
	var dashed := false
	var prev := 0
	var was_up := true
	var t := 0

	func _pick(weights: Array) -> int:
		var r := rng.randf()
		for i in weights.size():
			r -= weights[i]
			if r <= 0.0:
				return i
		return weights.size() - 1

	func buttons(sim, f) -> int:
		var b := 0
		var wall: int = _touching_wall(sim, f)
		if f.on_ground:
			dashed = false
			saw_wall = 0
			if press_in < 0 and hold == 0:
				press_in = rng.randi_range(2, 10) if t > 0 else 0
				press_steer = [-1, 1, 0][_pick([0.4, 0.4, 0.2])]
				steer_next = press_steer
				steer_in = -1
		elif wall != 0:
			if saw_wall != wall:
				saw_wall = wall
				if press_in < 0:
					press_in = rng.randi_range(3, 12)
					press_steer = [wall, -wall, 0][_pick([0.4, 0.3, 0.3])]
					steer_next = -wall
					steer_in = -1
		else:
			saw_wall = 0
			if dash_habit and not dashed and dash_in < 0 and f.vy >= 0.0 and was_up and f.y + 63 > 690:
				dash_in = rng.randi_range(0, 6)
				dash_way = [P.B_UP, P.B_UP | P.B_LEFT, P.B_UP | P.B_RIGHT][_pick([0.4, 0.3, 0.3])]
		was_up = f.vy < 0.0
		if press_in == 0:
			if prev & P.B_JUMP:
				press_in = 1          # the jump is still held: let go for a tick first
			else:
				hold = rng.randi_range(6, 20)
				steer = press_steer
				steer_in = rng.randi_range(2, 10)
		if press_in >= 0:
			press_in -= 1
		if steer_in == 0:
			steer = steer_next
		if steer_in >= 0:
			steer_in -= 1
		if hold > 0:
			b |= P.B_JUMP
			hold -= 1
		b |= P.B_RIGHT if steer > 0 else (P.B_LEFT if steer < 0 else 0)
		if dash_in == 0:
			b = (b & ~(P.B_LEFT | P.B_RIGHT | P.B_UP)) | P.B_DODGE | dash_way
			dashed = true
		if dash_in >= 0:
			dash_in -= 1
		prev = b
		t += 1
		return b

	static func _touching_wall(sim, f) -> int:
		if f.on_ground:
			return 0
		if sim.box_hits_solid(f.x - 1, f.y, 36, 63):
			return -1
		if sim.box_hits_solid(f.x + 1, f.y, 36, 63):
			return 1
		return 0

func _kid_row(new_rules: bool, dash: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var got := 0
	var times: Array = []
	var wjs := 0
	var n := 0
	for i in tries:
		var sim = _fresh(new_rules, STARTS[i % STARTS.size()])
		var f = sim.fighters[0]
		var kid := Kid.new()
		kid.rng.seed = rng.randi()
		kid.dash_habit = dash
		n += 1
		for t in MAX_T:
			sim.apply_input(f, kid.buttons(sim, f), 0)
			sim.step()
			for e in sim.take_events():
				if e[0] == P.E_WALLJUMP:
					wjs += 1
			if _out(f):
				got += 1
				times.append(t + 1)
				break
	times.sort()
	var med := "-" if times.is_empty() else "%.2f s" % (times[times.size() / 2] / 60.0)
	print("  %s rules, %s: out in 4 s %d of %d (%d%%), median %s, wall jumps a try %.1f" % [
		"new" if new_rules else "old", "jump and dash" if dash else "jumps only ", got, n,
		roundi(100.0 * got / n), med, float(wjs) / n])

# ------------------------------------------------------------------ part 2
# The fighter slides down a wall of the pit, the thumb up toward that wall (jump held
# since the last jump). Then one of the moves a kid makes to jump off it:
const GESTURES := ["dip", "pump", "swing", "flick up", "lift, touch"]

func _stick_row(new_rules: bool, pump: bool) -> void:
	var line := "  %s rules, %s stick:" % ["new" if new_rules else "old", "new" if pump else "old"]
	for g in GESTURES:
		var walls := 0
		for wall in [-1, 1]:
			if _gesture_wall_jumps(new_rules, pump, wall, g):
				walls += 1
		line += "  %s %s" % [g, ["no", "one wall", "yes"][walls]]
	print(line)

func _sticks(pump: bool):
	var s = Sticks.new()
	s.fit(Vector2(1920, 1080))
	if "pump" in s:
		s.pump = pump
	return s

# The thumb's offset at an angle (0 right, 90 up, 180 left) and a share of the reach.
static func _at(deg: float, share: float) -> Vector2:
	return Vector2(cos(deg_to_rad(deg)), -sin(deg_to_rad(deg))) * 240.0 * share

func _touch(s, p: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = p
	e.pressed = down
	s._touch(e)

func _drag(s, p: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = p
	s._drag(e)

# The thumb's path a tick at a time: [offset or null (lifted), ...].
func _gesture_path(g: String, wall: int) -> Array:
	var toward := 120.0 if wall < 0 else 60.0      # up toward the wall: 60 degrees over level that side
	var away := 180.0 - toward
	var level := 170.0 if wall < 0 else 10.0
	var path: Array = []
	match g:
		"dip":           # down to level toward the wall and back up
			for i in 3:
				path.append(_at(lerpf(toward, level, (i + 1) / 3.0), 0.8))
			for i in 3:
				path.append(_at(lerpf(level, toward, (i + 1) / 3.0), 0.8))
		"pump":          # down the same line and back up
			for i in 3:
				path.append(_at(toward, lerpf(0.8, 0.45, (i + 1) / 3.0)))
			for i in 3:
				path.append(_at(toward, lerpf(0.45, 0.8, (i + 1) / 3.0)))
		"swing":         # over the top to up and away
			for i in 4:
				path.append(_at(lerpf(toward, away, (i + 1) / 4.0), 0.8))
		"flick up":      # level toward the wall (jump let go), then one quick flick straight up
			for i in 3:
				path.append(_at(lerpf(toward, level, (i + 1) / 3.0), 0.8))
			path.append(_at(90.0, 0.8))
		"lift, touch":   # the thumb off and down again, then up and away
			path.append(null)
			path.append(null)
			path.append(Vector2.ZERO)
			for i in 3:
				path.append(_at(away, 0.8 * (i + 1) / 3.0))
	for i in 8:
		path.append(path[-1])
	return path

func _gesture_wall_jumps(new_rules: bool, pump: bool, wall: int, g: String) -> bool:
	var sim = _fresh(new_rules, 165)
	var f = sim.fighters[0]
	var s = _sticks(pump)
	var c := Vector2(400, 700)
	var toward := 120.0 if wall < 0 else 60.0
	_touch(s, c, true)
	for i in 4:      # the thumb went up toward the wall a while ago: jump held
		_drag(s, c + _at(toward, 0.8 * minf(1.0, (i + 1) / 2.0)))
		s.buttons()
	f.buttons = s.buttons()
	# now in the air against the wall, sliding down, holding toward it
	f.x = 60 if wall < 0 else 234
	f.y = 820
	f.vy = 2.0
	f.on_ground = false
	f.coyote = 0
	for i in 4:
		sim.apply_input(f, s.buttons(), 0)
		sim.step()
	sim.take_events()
	var down := true
	for p in _gesture_path(g, wall):
		if p == null:
			if down:
				_touch(s, c, false)
				down = false
		else:
			if not down:
				_touch(s, c, true)   # the stick's middle is where the thumb lands
				down = true
			_drag(s, c + p)
		sim.apply_input(f, s.buttons(), 0)
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_WALLJUMP:
				return true
	return false

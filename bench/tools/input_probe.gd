# Runs the simulation with no network and presses a person's buttons on it
# (sim.apply_input), the way the server does for a seat with a person. Prints a
# PASS/fail line per rule and exits 1 on a fail. The first-playable plan, 3.1.
#   godot --headless --path bench --script res://tools/input_probe.gd
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")

var fails := 0

func _init() -> void:
	_run_right_and_jump()
	_shoot_and_catch()
	_kill_stays_dead()
	_drop_through_a_ledge()
	_frozen_round_start()
	_aim_help()
	_bench_path_alive()
	if fails == 0:
		print("✅ input_probe: every check passed")
		quit(0)
	else:
		printerr("❌ input_probe: %d check(s) failed" % fails)
		quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	fails += 0 if ok else 1
	print("%s %s: %s" % ["PASS" if ok else "FAIL", name, detail])

# A sim with people on the given seats (no bots), nobody respawns.
func _game(n: int) -> RefCounted:
	var sim = SimScript.new(0, 24, 7)
	sim.respawn = false
	sim.power_arrows = false
	var seats: Array = []
	for i in n:
		seats.append({"id": i, "bot": false})
	sim.start_round(seats)
	return sim

func _press(sim, f, buttons: int, aim: int, ticks: int) -> Array:
	var evs: Array = []
	for i in ticks:
		sim.apply_input(f, buttons, aim)
		sim.step()
		evs.append_array(sim.take_events())
	return evs

func _has(evs: Array, type: int, who: int = -1) -> bool:
	for e in evs:
		if e[0] == type and (who < 0 or e[3] == who):
			return true
	return false

func _run_right_and_jump() -> void:
	var sim = _game(1)
	var f = sim.fighters[0]
	sim._place(f, Vector2i(240, 1020))   # the floor, far from the gap
	sim.step()
	sim.take_events()
	var x0: int = f.x
	_press(sim, f, P.B_RIGHT, 0, 60)
	var dx: int = f.x - x0
	_check("right for 60 ticks moves the fighter right", dx > 300 and dx < 420 and f.on_ground,
		"dx=%d px (top speed %.2f px/tick), on the ground=%s" % [dx, sim.RUN_MAX, f.on_ground])
	var y0: int = f.y
	var top: int = y0
	for i in 60:
		sim.apply_input(f, P.B_JUMP if i < 30 else 0, 0)
		sim.step()
		top = mini(top, f.y)
	var rise := y0 - top
	var analytic: float = sim.JUMP * sim.JUMP / (2.0 * sim.GRAVITY_HELD)
	_check("a held jump rises about 153 px", rise >= 150 and rise <= 165,
		"rose %d px (the plan's estimate %.1f from v²/2g; a 60 Hz step adds half a tick: %.1f)" % [rise, analytic, analytic + sim.JUMP * 0.5])
	var evs := _press(sim, f, 0, 0, 1)
	_check("the jump landed again", f.on_ground and f.y == y0, "y=%d (start %d)" % [f.y, y0])
	# a short tap jumps lower than a held jump
	var tap_top: int = f.y
	for i in 60:
		sim.apply_input(f, P.B_JUMP if i < 2 else 0, 0)
		sim.step()
		tap_top = mini(tap_top, f.y)
	var tap_rise := y0 - tap_top
	_check("a tapped jump is lower", tap_rise < rise - 40, "tap rose %d px, held rose %d px" % [tap_rise, rise])
	# a jump pressed a few ticks before landing still jumps (the buffer)
	for i in 10:
		sim.apply_input(f, P.B_JUMP if i == 0 else 0, 0)
		sim.step()
	var air_y: int = f.y
	sim.apply_input(f, P.B_JUMP, 0)   # pressed in the air, high up
	sim.step()
	var buffered := false
	for i in 60:
		sim.apply_input(f, 0, 0)
		sim.step()
		if f.on_ground:
			break
	# now press jump 3 ticks before a landing: fall from the first jump's height
	var t := 0
	for i in 200:
		var pressed := false
		if f.on_ground and t == 0:
			sim.apply_input(f, P.B_JUMP, 0)
			t = 1
			pressed = true
		elif t == 1 and f.vy > 0.0 and f.y > y0 - 30:
			sim.apply_input(f, P.B_JUMP, 0)   # about 3 ticks before the floor
			t = 2
			pressed = true
		else:
			sim.apply_input(f, 0, 0)
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_JUMP and t == 2 and not pressed:
				buffered = true
		if buffered:
			break
	_check("a jump pressed just before landing still jumps (buffer)", buffered, "air y=%d, buffered=%s" % [air_y, buffered])

func _shoot_and_catch() -> void:
	var sim = _game(2)
	var a = sim.fighters[0]
	var b = sim.fighters[1]
	sim._place(a, Vector2i(240, 1020))
	sim._place(b, Vector2i(540, 1020))
	sim.step()
	sim.take_events()
	# hold shoot 3 ticks aiming right, let go: one arrow flies right
	var evs := _press(sim, a, P.B_SHOOT, 0, 3)
	_check("holding shoot does not fire yet", a.arrows == 3 and a.aiming and sim.arrows.is_empty(), "arrows=%d aiming=%s" % [a.arrows, a.aiming])
	var caught := false
	var dead := false
	for i in 40:
		sim.apply_input(a, 0, 0)
		sim.apply_input(b, P.B_DODGE if i == 9 else 0, 0)   # b dodges 9 ticks after the shot
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_CATCH and e[3] == 1:
				caught = true
			if e[0] == P.E_DEATH:
				dead = true
	_check("let go of shoot fires one arrow", a.arrows == 2, "a.arrows=%d" % a.arrows)
	_check("a dodge in time catches the arrow", caught and not dead and b.arrows == 4,
		"caught=%s dead=%s b.arrows=%d (the catch gives the arrow to the catcher)" % [caught, dead, b.arrows])
	# an empty quiver: let go fires nothing and says so
	a.arrows = 0
	evs = _press(sim, a, P.B_SHOOT, 0, 2)
	evs.append_array(_press(sim, a, 0, 0, 1))
	_check("an empty quiver gives a dry-fire event", _has(evs, P.E_DRYFIRE, 0) and sim.arrows.is_empty() == (sim.live_arrow_count() == 0), "events=%s" % str(evs))

func _kill_stays_dead() -> void:
	var sim = _game(2)
	var a = sim.fighters[0]
	var b = sim.fighters[1]
	sim._place(a, Vector2i(240, 1020))
	sim._place(b, Vector2i(540, 1020))
	sim.step()
	sim.take_events()
	_press(sim, a, P.B_SHOOT, 0, 2)
	var evs := _press(sim, a, 0, 0, 40)
	_check("an arrow kills in one hit", _has(evs, P.E_DEATH, 1) and b.state == P.F_DEAD and sim.alive_count() == 1,
		"b.state=%d alive=%d" % [b.state, sim.alive_count()])
	_press(sim, a, 0, 0, 200)
	_check("the dead stay dead (one life a round)", b.state == P.F_DEAD and sim.alive_count() == 1 and sim.last_alive() == a,
		"after 200 more ticks: b.state=%d" % b.state)
	# the benchmark's way still respawns
	sim.respawn = true
	_press(sim, a, 0, 0, 1)
	_check("with respawn on (the benchmark) the dead come back", b.state == P.F_NORMAL, "b.state=%d" % b.state)

func _drop_through_a_ledge() -> void:
	var sim = _game(1)
	var f = sim.fighters[0]
	sim._place(f, Vector2i(570, 780))   # on the ledge at row 26 (cells 14..23)
	sim.step()
	sim.take_events()
	_check("the fighter stands on the ledge", f.on_ground and f.y + sim.BODY_H == 780, "feet y=%d on_ground=%s" % [f.y + sim.BODY_H, f.on_ground])
	# jump alone from the ledge: up, not through
	var y0: int = f.y
	var top: int = y0
	for i in 30:
		sim.apply_input(f, P.B_JUMP if i < 10 else 0, 0)
		sim.step()
		top = mini(top, f.y)
	_check("jump on a ledge jumps up", top < y0 - 60, "rose %d" % (y0 - top))
	for i in 90:
		sim.apply_input(f, 0, 0)
		sim.step()
	_check("and lands back on it", f.on_ground and f.y == y0, "y=%d" % f.y)
	# down alone: still on the ledge (TowerFall's rule: it takes down + jump)
	_press(sim, f, P.B_DOWN, 0, 30)
	_check("down alone stays on the ledge", f.on_ground and f.y == y0, "feet y=%d" % (f.y + sim.BODY_H))
	# down, then jump while down is held: through the ledge
	sim.apply_input(f, P.B_DOWN, 0)
	sim.step()
	sim.apply_input(f, P.B_DOWN | P.B_JUMP, 0)
	sim.step()
	for i in 20:
		sim.apply_input(f, P.B_DOWN, 0)
		sim.step()
	_check("down + jump drops through the ledge", f.y + sim.BODY_H > 810, "feet y=%d after 22 ticks" % (f.y + sim.BODY_H))

func _frozen_round_start() -> void:
	var sim = _game(1)
	var f = sim.fighters[0]
	sim._place(f, Vector2i(240, 1020))
	sim.frozen = true
	sim.step()
	var x0: int = f.x
	_press(sim, f, P.B_RIGHT | P.B_JUMP, 0, 30)
	_check("frozen (the round's first moment): buttons do nothing", f.x == x0 and f.on_ground, "x=%d (start %d)" % [f.x, x0])
	sim.frozen = false
	_press(sim, f, P.B_RIGHT, 0, 30)
	_check("unfrozen: they work again", f.x > x0 + 100, "x=%d" % f.x)

func _aim_help() -> void:
	var sim = _game(2)
	var a = sim.fighters[0]
	var b = sim.fighters[1]
	sim._place(a, Vector2i(240, 1020))
	sim._place(b, Vector2i(380, 1020))   # 140 px away, inside the 162 px help
	sim.step()
	sim.take_events()
	var aim_up := 3600 - 200   # 20 degrees above the floor line (y grows downward)
	_press(sim, a, P.B_SHOOT, aim_up, 2)
	_press(sim, a, 0, aim_up, 1)
	var ang: float = sim.arrows[0].ang if sim.arrows.size() > 0 else 9.0
	_check("a shot near an enemy snaps to it (aim help)", absf(ang) < 0.1, "aimed -20 degrees, the arrow flies at %.1f degrees" % rad_to_deg(ang))
	# far away: no snap
	var sim2 = _game(2)
	var c = sim2.fighters[0]
	var d = sim2.fighters[1]
	sim2._place(c, Vector2i(240, 1020))
	sim2._place(d, Vector2i(640, 1020))   # 400 px: too far for the help
	sim2.step()
	sim2.take_events()
	_press(sim2, c, P.B_SHOOT, aim_up, 2)
	_press(sim2, c, 0, aim_up, 1)
	var ang2: float = sim2.arrows[0].ang if sim2.arrows.size() > 0 else 9.0
	_check("a far enemy gets no help", absf(rad_to_deg(ang2) + 20.0) < 1.0, "the arrow flies at %.1f degrees" % rad_to_deg(ang2))

func _bench_path_alive() -> void:
	var sim = SimScript.new(8, 24, 7)
	var counts := {}
	for t in 1200:
		sim.step()
		for e in sim.take_events():
			counts[e[0]] = counts.get(e[0], 0) + 1
	var buf := StreamPeerBuffer.new()
	sim.write_snapshot(buf, [])
	var ok: bool = counts.get(P.E_SHOOT, 0) > 20 and counts.get(P.E_DEATH, 0) > 0 and counts.get(P.E_SPAWN, 0) > 8 and sim.fighters.size() == 8
	_check("the benchmark's 8 bots still play (shoot, die, respawn)", ok,
		"shots=%d deaths=%d spawns=%d, snapshot %d bytes" % [counts.get(P.E_SHOOT, 0), counts.get(P.E_DEATH, 0), counts.get(P.E_SPAWN, 0), buf.data_array.size()])

# Runs the simulation with no network and presses a person's buttons on it
# (sim.apply_input), the way the server does for a seat with a person. Prints a
# PASS/fail line per rule and exits 1 on a fail. The first-playable plan, 3.1.
#   godot --headless --path bench --script res://tools/input_probe.gd
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const Predict = preload("res://client/predict.gd")
const Present = preload("res://client/present.gd")
const Net = preload("res://client/net.gd")
const Brain = preload("res://sim/brain.gd")
const LevelScript = preload("res://sim/level.gd")
const Routes = preload("res://sim/routes.gd")

var fails := 0

func _init() -> void:
	_run_right_and_jump()
	_shoot_and_catch()
	_shots_lock_in()
	_kill_stays_dead()
	_drop_through_a_ledge()
	_frozen_round_start()
	_bots_wait_at_fight()
	_aim_help()
	_bench_path_alive()
	_walls_at_the_edge()
	_walls_close()
	_spawns_apart()
	_state_round_trip()
	_prediction_alone()
	_arrows_in_the_present()
	_brain_arrow_copy()
	_route_file_fresh()
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
	var dodged := false
	for i in 40:
		sim.apply_input(a, 0, 0)
		# b dodges into the arrow when it is 6 ticks of flight away (p4.4: the arrow lobs, so a
		# dodge away from it can leave it short, in the floor)
		var near: bool = not dodged and not sim.arrows.is_empty() and b.x - sim.arrows[0].x < 6.0 * SimScript.ARROW_SPEED
		sim.apply_input(b, (P.B_DODGE | P.B_LEFT) if near else 0, 0)
		dodged = dodged or near
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

# p4.4 (the user: about half the shots never left the bow): a let-go shoot always
# fires: a jump keeps the bow drawn, a release in a dodge fires when the dodge
# ends, a press in a dodge draws when it ends; B_CANCEL lowers the bow with no
# arrow; and the arrow lobs, falling by ARROW_LOB_G a tick from the bow.
func _shots_lock_in() -> void:
	# a jump with the bow drawn, let go in the air: an arrow
	var sim = _game(1)
	var f = sim.fighters[0]
	sim._place(f, Vector2i(240, 1020))
	sim.step()
	sim.take_events()
	var evs := _press(sim, f, P.B_SHOOT, 0, 3)
	evs.append_array(_press(sim, f, P.B_SHOOT | P.B_JUMP, 0, 4))
	var air: bool = not f.on_ground
	var still_up: bool = f.aiming and f.drawn
	evs.append_array(_press(sim, f, 0, 0, 1))
	_check("a jump keeps the bow drawn, and let go in the air it fires", air and still_up and _has(evs, P.E_SHOOT, 0) and f.arrows == 2,
		"in the air=%s, drawn after the jump=%s, arrows=%d" % [air, still_up, f.arrows])
	# let go in a dodge: the arrow leaves the first tick after the dodge, at the aim it was let go with
	sim = _game(1)
	f = sim.fighters[0]
	sim._place(f, Vector2i(240, 1020))
	sim.step()
	sim.take_events()
	_press(sim, f, P.B_SHOOT, 900, 3)                       # drawn, aimed down (90.0 degrees)
	_press(sim, f, P.B_SHOOT | P.B_DODGE | P.B_RIGHT, 0, 1)  # the dodge takes the bow down; shoot still held
	var in_dodge: bool = f.state == P.F_DODGE
	evs = _press(sim, f, P.B_RIGHT, 3150, 1)                # let go in the dodge, aimed up-right (315 degrees)
	var waited: bool = f.shot_wait and not _has(evs, P.E_SHOOT)
	var after := 0
	for i in 40:
		evs = _press(sim, f, 0, 0, 1)
		after += 1
		if _has(evs, P.E_SHOOT, 0):
			break
	var ang_ok: bool = not sim.arrows.is_empty() and absf(angle_difference(sim.arrows[0].ang, deg_to_rad(315.0))) < 0.2
	_check("let go in a dodge, the arrow leaves when the dodge ends, at the aim it was let go with", in_dodge and waited and after <= sim.DODGE_TICKS + 1 and f.arrows == 2 and ang_ok,
		"in the dodge=%s, waited=%s, fired %d ticks later (the dodge: %d), arrows=%d, angle ok=%s" % [in_dodge, waited, after, sim.DODGE_TICKS, f.arrows, ang_ok])
	# shoot pressed in a dodge: the bow comes up when it ends; let go: an arrow
	sim = _game(1)
	f = sim.fighters[0]
	sim._place(f, Vector2i(240, 1020))
	sim.step()
	sim.take_events()
	_press(sim, f, P.B_DODGE | P.B_RIGHT, 0, 1)
	_press(sim, f, P.B_SHOOT, 0, 2)
	var down_in_dodge: bool = f.state == P.F_DODGE and f.drawn and not f.aiming
	for i in 30:
		_press(sim, f, P.B_SHOOT, 0, 1)
		if f.state == P.F_NORMAL and f.aiming:
			break
	var up_after: bool = f.aiming
	evs = _press(sim, f, 0, 0, 1)
	_check("shoot pressed in a dodge draws when the dodge ends; let go fires", down_in_dodge and up_after and _has(evs, P.E_SHOOT, 0),
		"drawn in the dodge, bow down=%s, bow up after=%s, arrows=%d" % [down_in_dodge, up_after, f.arrows])
	# B_CANCEL: the bow comes down, no arrow, no dry fire
	sim = _game(1)
	f = sim.fighters[0]
	sim._place(f, Vector2i(240, 1020))
	sim.step()
	sim.take_events()
	evs = _press(sim, f, P.B_SHOOT, 0, 3)
	evs.append_array(_press(sim, f, P.B_CANCEL, 0, 1))
	evs.append_array(_press(sim, f, 0, 0, 30))
	_check("let go with B_CANCEL: no arrow, no dry fire, the bow down", not _has(evs, P.E_SHOOT) and not _has(evs, P.E_DRYFIRE) and f.arrows == 3 and not f.aiming and not f.drawn,
		"arrows=%d aiming=%s drawn=%s" % [f.arrows, f.aiming, f.drawn])
	# the lob: a flat shot falls by ARROW_LOB_G a tick from the bow, ARROW_SPEED across
	sim = _game(1)
	f = sim.fighters[0]
	sim._place(f, Vector2i(240, 1020))
	sim.step()
	_press(sim, f, P.B_SHOOT, 0, 2)
	_press(sim, f, 0, 0, 1)
	var worst := 0.0
	var n := 0
	var x0: float = sim.arrows[0].x if not sim.arrows.is_empty() else 0.0
	for k in 10:
		if sim.arrows.is_empty() or sim.arrows[0].state != P.S_FLY:
			break
		var a = sim.arrows[0]
		worst = maxf(worst, absf(a.vy - (k + 1) * SimScript.ARROW_LOB_G))
		worst = maxf(worst, absf(a.x - (x0 + k * SimScript.ARROW_SPEED)))
		n += 1
		_press(sim, f, 0, 0, 1)
	_check("the arrow lobs: it falls by ARROW_LOB_G a tick from the bow and keeps its speed across", n == 10 and worst < 0.001,
		"%d ticks checked, the worst %.4f off (%.1f px a tick across, %.2f px a tick faster down each tick)" % [n, worst, SimScript.ARROW_SPEED, SimScript.ARROW_LOB_G])

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

# After FIGHT the bots stand still BOT_WAIT_MIN..MAX ticks (no move, no shot), so
# people move first; then they play. 20 rounds: 1 person standing still + 7 bots.
func _bots_wait_at_fight() -> void:
	var firsts: Array = []
	var never := 0
	var moved_early := 0
	var deaths_early := 0
	var moved_later := 0
	for sd in range(1, 21):
		var sim = SimScript.new(0, 24, sd)
		sim.respawn = false
		sim.power_arrows = false
		var seats: Array = [{"id": 0, "bot": false}]
		for i in range(1, 8):
			seats.append({"id": i, "bot": true})
		sim.start_round(seats)
		sim.frozen = true
		for t in 90:
			sim.step()
		sim.take_events()
		sim.frozen = false
		var at_fight := {}
		for f in sim.fighters:
			at_fight[f.id] = Vector2i(f.x, f.y)
		var first := -1
		for t in 300:
			sim.step()
			var evs: Array = sim.take_events()
			if first < 0 and _has(evs, P.E_SHOOT):
				first = t + 1
			if t + 1 < SimScript.BOT_WAIT_MIN and _has(evs, P.E_DEATH):
				deaths_early += 1
			if t + 1 == SimScript.BOT_WAIT_MIN - 1 or t + 1 == 300:
				var n := 0
				for f in sim.fighters:
					if f.bot and f.state != P.F_DEAD and Vector2i(f.x, f.y) != at_fight[f.id]:
						n += 1
				if t + 1 == 300:
					moved_later += 1 if n > 0 else 0
				else:
					moved_early += n
		if first < 0:
			never += 1
		else:
			firsts.append(first)
	firsts.sort()
	var ok: bool = never == 0 and firsts[0] >= SimScript.BOT_WAIT_MIN and moved_early == 0 and deaths_early == 0 and moved_later == 20
	_check("bots stand still and hold fire 1 to 1.5 s after FIGHT", ok,
		"20 rounds: bots that moved in the first %d ticks: %d, deaths: %d; the first shot came %d to %d ticks after FIGHT (median %d); rounds with no shot in 5 s: %d, with the bots moving by 5 s: %d" % [
			SimScript.BOT_WAIT_MIN - 1, moved_early, deaths_early,
			firsts[0] if firsts.size() > 0 else -1, firsts[-1] if firsts.size() > 0 else -1,
			firsts[firsts.size() / 2] if firsts.size() > 0 else -1, never, moved_later])

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

# The purple walls (D2, TowerFall's miasma): none before 25 s, deadly from 27 s.
# A still person at the left edge dies the tick they turn deadly, the other one
# (in the middle) lives, and the walls melt at once (one fighter left).
func _walls_at_the_edge() -> void:
	var sim = _game(2)
	sim.walls_start = 1500
	sim._place(sim.fighters[0], Vector2i(80, 1020))    # the floor by the left edge
	sim._place(sim.fighters[1], Vector2i(960, 660))    # the middle ledge
	var first_w := -1
	var first_deadly := -1
	var dead_t := -1
	var cause := -1
	var gone_t := -1
	for t in range(1, 1800):
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_DEATH and e[3] == 0:
				dead_t = t
				cause = e[4]
		if first_w < 0 and sim.walls_width() > 0:
			first_w = t
		if first_deadly < 0 and sim.walls_deadly():
			first_deadly = t
		if dead_t > 0 and gone_t < 0 and sim.walls_width() == 0:
			gone_t = t
	var ok: bool = first_w > 1500 and first_w < 1560 and first_deadly == 1620 and dead_t == 1620 and cause == 6 \
		and sim.fighters[1].state != P.F_DEAD and gone_t > dead_t and gone_t <= dead_t + 20
	_check("the purple walls come at 25 s, kill at the edge from 27 s, melt when one is left", ok,
		"the walls show at %.2f s, deadly at %.2f s, the person at the edge dies at %.2f s (cause %d), gone %d ticks later, the one in the middle %s" % [
		first_w / 60.0, first_deadly / 60.0, dead_t / 60.0, cause, gone_t - dead_t, "lives" if sim.fighters[1].state != P.F_DEAD else "died"])

# Two still people in the middle of the middle ledge: nobody dies before the walls
# close, then both on the same tick (a draw), about 44.6 s after FIGHT.
func _walls_close() -> void:
	var sim = _game(2)
	sim.walls_start = 1500
	sim._place(sim.fighters[0], Vector2i(900, 660))
	sim._place(sim.fighters[1], Vector2i(1020, 660))
	var deaths: Array = []
	for t in range(1, 3000):
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_DEATH:
				deaths.append([t, e[3], e[4]])
	var ok: bool = deaths.size() == 2 and deaths[0][0] == deaths[1][0] and deaths[0][2] == 6 and deaths[1][2] == 6 \
		and deaths[0][0] > 2600 and deaths[0][0] < 2880 and sim.walls_width() == 0
	_check("the walls close on the last ones in the middle by 48 s (both die, a draw)", ok,
		"deaths %s (tick, seat, cause); the walls afterwards %d px" % [str(deaths), sim.walls_width()])

# No spawn spot sits one drop above another: dropping through your own ledge and
# steering up to 150 px sideways, you would land on the one below (p1.2 had 7 such
# pairs, the source of the first second's stomps). Every spot stands on a floor or
# a ledge with room for the body. Every arena (G5; tools/arena_probe.gd has the rest).
func _spawns_apart() -> void:
	var bad: Array = []
	var spots: Array = []
	for n in SimScript.LevelScript.count():
		var lv = SimScript.LevelScript.new(n)
		spots.append("%s %d" % [lv.name, lv.spawns.size()])
		for a in lv.spawns:
			if not lv.stands(a):
				bad.append("%s: %s does not stand" % [lv.name, a])
			for b in lv.spawns:
				if a != b and lv.one_drop(a, b, 150):
					bad.append("%s: %s over %s" % [lv.name, a, b])
	_check("no spawn spot sits one drop above another (every arena)", bad.is_empty(),
		"spots: %s; %s" % [", ".join(spots), "none over another" if bad.is_empty() else ", ".join(bad)])

# Random buttons held 4 to 30 ticks: runs, jumps (held and tapped), drops,
# dodges, and (with shots) aims and shots, from a seeded rng.
func _random_buttons(rng: RandomNumberGenerator, shots: bool) -> Array:
	var b := 0
	if rng.randf() < 0.7:
		b |= P.B_LEFT if rng.randf() < 0.5 else P.B_RIGHT
	if rng.randf() < 0.35:
		b |= P.B_JUMP
	if rng.randf() < 0.15:
		b |= P.B_DOWN
	if rng.randf() < 0.1:
		b |= P.B_UP
	if rng.randf() < 0.12:
		b |= P.B_DODGE
	if shots and rng.randf() < 0.2:
		b |= P.B_SHOOT
	return [b, rng.randi_range(0, 3599), rng.randi_range(4, 30)]

# P2: T_OWN carries a fighter's whole state (sim.write_fighter_state). From each
# spawn spot, a person plays 300 random ticks (knocked back or killed just then
# on some spots, so the hurt and dead states run too); then the state is written,
# read into a fresh fighter in a second sim, and both run the same 600 random
# ticks side by side. A field missing from the state would split them.
func _state_round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var lv = SimScript.LevelScript.new()
	var split := ""
	var compared := 0
	var states := {}
	for si in lv.spawns.size() * 2:
		var spot: Vector2i = lv.spawns[si % lv.spawns.size()]
		var a = _game(1)
		var fa = a.fighters[0]
		a._place(fa, spot)
		var hold := [0, 0, 0]
		for t in 300:
			if hold[2] <= 0:
				hold = _random_buttons(rng, true)
			hold[2] -= 1
			a.apply_input(fa, hold[0], hold[1])
			a.step()
		if si % 4 == 1:
			a._kill(fa, 255, 1)
		elif si % 4 == 2:
			a._hurt(fa, 10.0, -7.0)
		var buf := StreamPeerBuffer.new()
		a.write_fighter_state(buf, fa)
		var b = _game(1)
		var fb = b.fighters[0]
		var rb := StreamPeerBuffer.new()
		rb.data_array = buf.data_array
		b.read_fighter_state(rb, fb)
		a.arrows.clear()   # the copy gets the fighter, not the arrows in the air
		for t in 900:
			if hold[2] <= 0:
				hold = _random_buttons(rng, true)
			hold[2] -= 1
			a.apply_input(fa, hold[0], hold[1])
			b.apply_input(fb, hold[0], hold[1])
			a.step()
			b.step()
			states[fa.state] = true
			var wa := StreamPeerBuffer.new()
			var wb := StreamPeerBuffer.new()
			a.write_fighter_state(wa, fa)
			b.write_fighter_state(wb, fb)
			compared += 1
			if wa.data_array != wb.data_array:
				split = "from %s, %d ticks after the copy: the original at (%d, %d) state %d, the copy at (%d, %d) state %d" % [
					spot, t + 1, fa.x, fa.y, fa.state, fb.x, fb.y, fb.state]
				break
		if split != "":
			break
	_check("a fighter's whole state goes over and comes back the same (T_OWN)", split == "" and states.size() >= 5,
		split if split != "" else "%d runs (each spot twice) x 900 ticks side by side, the same state on all %d; states seen %s; %d bytes" % [
			lv.spawns.size() * 2, compared, str(states.keys()), _state_size()])

func _state_size() -> int:
	var sim = _game(1)
	var buf := StreamPeerBuffer.new()
	sim.write_fighter_state(buf, sim.fighters[0])
	return buf.data_array.size()

# P2: the prediction alone (client/predict.gd) is never wrong. A server sim with
# one person runs input N on tick N; the client runs 4 ticks ahead with random
# buttons (no shots: a shot can come down on the shooter, and deaths are the
# server's); each second tick's T_OWN reaches the client 6 ticks later. Every
# correction must be 0 px.
func _prediction_alone() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var server = _game(1)
	var f = server.fighters[0]
	server._place(f, Vector2i(960, 660))
	var pred = Predict.new()
	pred.seat = 0
	var lead := 4
	var delay := 6
	var sent := {}
	var pending: Array = []
	var hold := [0, 0, 0]
	for st in range(1, 1801):
		if hold[2] <= 0:
			hold = _random_buttons(rng, false)
		hold[2] -= 1
		sent[st + lead] = [hold[0], hold[1]]
		pred.on_tick(st + lead, hold[0], hold[1])
		var inp: Array = sent.get(st, [0, 0])
		server.apply_input(f, inp[0], inp[1])
		server.step()
		server.take_events()
		if server.tick % 2 == 0:
			var buf := StreamPeerBuffer.new()
			server.write_fighter_state(buf, f)
			pending.append([st + delay, {"tick": server.tick, "used": st, "margin": lead, "late": 0,
				"flags": P.OWN_FIGHTER, "moves_from": 0, "pkt": buf.data_array, "at": 0}])
		while pending.size() > 0 and pending[0][0] <= st:
			pred.reconcile(pending.pop_front()[1])
	var worst := 0.0
	for e in pred.errors:
		worst = maxf(worst, e)
	_check("the prediction alone is never wrong (inputs 4 ticks ahead, T_OWN 6 ticks late)",
		pred.errors.size() > 800 and worst == 0.0 and pred.jumps == 0,
		"%d corrections checked, the worst %.1f px, %d jumps, %d ticks run again" % [pred.errors.size(), worst, pred.jumps, pred.replayed])

# P2: the arrows in the present (client/present.gd). The benchmark's 8 bots shoot
# plain arrows for 50 s; each snapshot is read as the page reads it (net.gd) and
# flown on 6 ticks, then set beside where the server really has each arrow 6
# ticks later. Only an arrow that met a fighter in those ticks may differ.
func _arrows_in_the_present() -> void:
	var server = SimScript.new(8, 24, 11)
	server.power_arrows = false
	var reader = Net.new()
	var present = Present.new()
	var k := 6
	var hist := {}
	var snaps := {}
	var errs := PackedFloat32Array()
	var buf := StreamPeerBuffer.new()
	for t in 3000:
		server.step()
		server.take_events()
		var pos := {}
		for a in server.arrows:
			if not a.dead:
				pos[a.id] = Vector2(a.x, a.y)
		hist[server.tick] = pos
		if server.tick % 2 != 0:
			continue
		server.write_snapshot(buf, [])
		reader._on_snapshot(buf.data_array)
		snaps[server.tick] = reader.newest()
		var old: int = server.tick - k
		if not snaps.has(old):
			continue
		var flown: Dictionary = present.arrows_at(snaps[old], server.tick, null, -1, [], [], 0.0)
		for id in flown:
			var st0 := int(snaps[old]["arrows"].get(id, {}).get("state", P.S_STUCK))
			if pos.has(id) and (st0 == P.S_FLY or st0 == P.S_FALL):   # in the air (p4.10: not one in a body)
				var e := Vector2(SimScript.wrap_d(pos[id].x, flown[id]["x"], 1920.0), SimScript.wrap_d(pos[id].y, flown[id]["y"], 1080.0)).length()
				errs.append(e)
		snaps.erase(old)
		hist.erase(old - 2)
	errs.sort()
	var n := errs.size()
	var exact := 0
	for e in errs:
		if e <= 0.5:
			exact += 1
	var pct := 100.0 * exact / maxf(1.0, n)
	_check("an arrow flown on 6 ticks from a snapshot is where the server has it (the arrows in the present)",
		n > 1000 and pct >= 95.0,
		"%d arrows in the air compared: %.1f%% within 0.5 px, p99 %.1f px, the worst %.1f px (the rest met a fighter on the way); %d bytes a snapshot" % [
			n, pct, errs[mini(n - 1, int(n * 0.99))] if n > 0 else 0.0, errs[n - 1] if n > 0 else 0.0, buf.data_array.size()])

# G6: the bot brain flies a copy of an arrow before it shoots (sim/brain.gd fly).
# 70 shots on each arena from random places to stand, at random angles: the copy
# must stick on the same tick and at the same spot as the real arrow (the shooter
# leaves the sim after the shot, so nothing else can stop the arrow).
func _brain_arrow_copy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 30
	var shots := 0
	var stuck := 0
	var same_tick := 0
	var worst := 0.0
	var flying := 0
	for n in LevelScript.count():
		var sim = SimScript.new(0, 24, 30 + n)
		sim.set_arena(n)
		sim.respawn = false
		sim.power_arrows = false
		var k := 0
		while k < 70:
			var spot := Vector2i(rng.randi_range(1, 63) * 30, rng.randi_range(2, 35) * 30)
			if not sim.level.stands(spot):
				continue
			k += 1
			sim.start_round([{"id": 0, "bot": false}])
			var f = sim.fighters[0]
			sim._place(f, spot)
			var aim := rng.randi_range(0, 3599)
			sim.apply_input(f, P.B_SHOOT, aim)
			sim.step()
			sim.apply_input(f, 0, aim)   # let go: the shot, made before the step moves anything
			var ang: float = f.aim
			var dir := Vector2.from_angle(ang)
			var copy: Array = Brain.fly(sim, f.x + SimScript.HALF_W + dir.x * 30.0, f.y + SimScript.ARROW_Y + dir.y * 30.0,
				dir.x * SimScript.ARROW_SPEED, dir.y * SimScript.ARROW_SPEED, 400)
			sim.fighters.clear()
			var a = sim.arrows[0] if sim.arrows.size() > 0 else null
			var t := 0
			while a != null and a.state == P.S_FLY and t < 400:
				sim.step()
				t += 1
			shots += 1
			if a == null:
				continue
			if a.state == P.S_STUCK:
				stuck += 1
				if copy[0] == Brain.FLY_WALL and copy[1] == t:
					same_tick += 1
					worst = maxf(worst, Vector2(copy[2], copy[3]).distance_to(Vector2(a.x, a.y)))
				else:
					worst = INF
			elif copy[0] == Brain.FLY_NONE:
				flying += 1
	_check("the bot brain's copy of an arrow sticks where the real arrow sticks (sim/brain.gd fly)",
		shots == 70 * LevelScript.count() and same_tick == stuck and stuck + flying == shots and worst <= 2.0,   # 70 a layout (p4.9: 4 layouts)
		"%d shots on %d arenas: %d stuck, the copy on the same tick for %d, the worst %.2f px apart; %d still flying after 400 ticks, both" % [
			shots, LevelScript.count(), stuck, same_tick, worst, flying])

# G6: the bots walk by the route file (sim/routes.json, made by arena_probe.gd
# --write-routes). It must have been made for every arena as it is now (each
# arena's grid hash) and for the moves as they are now (their hash); a changed
# arena or move list with an old file fails here, not in a round.
func _route_file_fresh() -> void:
	var bad: Array = []
	var edges := 0
	for n in LevelScript.count():
		var lv = LevelScript.new(n)
		var rm = Routes.map_for(lv)
		if rm == null:
			bad.append(lv.name)
			continue
		for key in rm.cand:
			edges += rm.cand[key].size()
	_check("the route file matches every arena and the moves (sim/routes.json; else: arena_probe.gd -- --write-routes)",
		bad.is_empty(), "%d arenas, %d moves kept between their floors and ledges%s" % [LevelScript.count(), edges,
			"" if bad.is_empty() else "; no match for " + ", ".join(bad)])


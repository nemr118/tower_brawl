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
	_bots_wait_at_fight()
	_aim_help()
	_bench_path_alive()
	_walls_at_the_edge()
	_walls_close()
	_spawns_apart()
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
# a ledge with room for the body.
func _spawns_apart() -> void:
	var lv = SimScript.LevelScript.new()
	var bad: Array = []
	for a in lv.spawns:
		if not _stands(lv, a):
			bad.append("%s does not stand" % a)
		for b in lv.spawns:
			if a != b and _one_drop(lv, a, b, 150):
				bad.append("%s over %s" % [a, b])
	_check("no spawn spot sits one drop above another", bad.is_empty(),
		"%d spots; %s" % [lv.spawns.size(), "none over another" if bad.is_empty() else ", ".join(bad)])

func _stands(lv, s: Vector2i) -> bool:
	if s.y % 30 != 0:
		return false
	var under := false
	for cx in range(floori((s.x - 18) / 30.0), floori((s.x + 17) / 30.0) + 1):
		if lv.cell(cx, s.y / 30) != 0:
			under = true
		for cy in range(floori((s.y - 63) / 30.0), floori((s.y - 1) / 30.0) + 1):
			if lv.cell(cx, cy) == 1:
				return false
	return under

# b is below a, less than reach px to the side, and some column between them is
# open (no solid block, no other ledge) from under a's ledge down to b's head.
func _one_drop(lv, a: Vector2i, b: Vector2i, reach: int) -> bool:
	if b.y <= a.y or absi(a.x - b.x) >= reach:
		return false
	var top: int = a.y / 30 + 1
	var head: int = floori((b.y - 63) / 30.0)
	for cx in range(floori((mini(a.x, b.x) - 18) / 30.0), floori((maxi(a.x, b.x) + 17) / 30.0) + 1):
		var open := true
		for cy in range(top, head):
			if lv.cell(cx, cy) != 0:
				open = false
				break
		if open:
			return true
	return false

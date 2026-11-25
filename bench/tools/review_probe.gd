# The rules the November review changed (docs/reference/game-review-2026-11.md,
# "Bugs the code hunt found"), each with a test. No network: the simulation alone,
# and the page's copy of your fighter (client/predict.gd).
#   godot --headless --path bench --script res://tools/review_probe.gd
# Bug 4, THE WINNER IS SAFE: once the server has called a round (sim.safe = the
# winner's seat), nothing kills the winner: an arrow, a blast, poison, fire, a stomp,
# the purple walls, lightning, a ghost cat, a knife, spikes, a furnace. Each one says
# E_PHEW instead (at most one per fighter every PHEW_EVERY ticks), the arrow drops
# off, and the winner is not moved. The same hit with nobody safe still kills.
# Bug 3, THE FREED SEAT: when a seat is given up in a round (the person left, the host
# took the seat), its fighter goes out at once with a normal death (sim.leave, cause
# C_LEFT), so an empty seat can never win a round. (The server's side of it, the point
# and the names, is checked on a running server by tools/v2_seat_check.py.)
# Bug 9, THE WINNER'S SCREEN: the server adds the replay's length to its 8 s. The
# length is worked out in proto.gd (replay_secs) from numbers that live in the page's
# client/deathcam.gd: the test plays the real deathcam and compares.
# Prints a PASS/FAIL line per rule and exits 1 on a fail.
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const Boiler = preload("res://sim/boiler.gd")
const Predict = preload("res://client/predict.gd")
const Deathcam = preload("res://client/deathcam.gd")

var fails := 0
var checks := 0

func _init() -> void:
	_safe_arrow()
	_safe_blast()
	_safe_zones()
	_safe_stomp_and_spikes()
	_safe_walls()
	_safe_lightning_cat_knife()
	_safe_furnace()
	_safe_costume()
	_safe_ends_with_the_round()
	_safe_prediction()
	_freed_seat()
	_replay_length()
	if fails == 0:
		print("✅ review_probe: %d of %d checks passed" % [checks, checks])
		quit(0)
	else:
		printerr("❌ review_probe: %d of %d checks failed" % [fails, checks])
		quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	checks += 1
	fails += 0 if ok else 1
	print("%s %s: %s" % ["PASS" if ok else "FAIL", name, detail])

# A sim with people on n seats (no bots), nobody respawns, on the bench arena (or `arena`).
func _game(n: int, arena: int = 0) -> RefCounted:
	var sim = SimScript.new(0, 24, 7)
	sim.set_arena(arena)
	sim.respawn = false
	sim.power_arrows = false
	var seats: Array = []
	for i in n:
		seats.append({"id": i, "bot": false})
	sim.start_round(seats)
	return sim

func _steps(sim, ticks: int) -> Array:
	var evs: Array = []
	for i in ticks:
		sim.step()
		for e in sim.take_events():
			evs.append([sim.tick] + e)     # [tick, type, x, y, a, b]
	return evs

func _of(evs: Array, type: int, who: int = -1) -> Array:
	var out: Array = []
	for e in evs:
		if e[1] == type and (who < 0 or e[4] == who):
			out.append(e)
	return out

# Two people on the floor, 300 px apart; a shoots b. With b safe: no death, one
# E_PHEW (b = 0: an arrow) at the arrow's spot, the arrow drops off and b has not moved.
func _safe_arrow() -> void:
	var lines: Array = []
	var ok := true
	for safe_on in [false, true]:
		var sim = _game(2)
		var a = sim.fighters[0]
		var b = sim.fighters[1]
		sim._place(a, Vector2i(240, 1020))
		sim._place(b, Vector2i(540, 1020))
		_steps(sim, 1)
		if safe_on:
			sim.safe = b.id
		var at := Vector2i(b.x, b.y)
		sim.apply_input(a, P.B_SHOOT, 0)
		_steps(sim, 2)
		sim.apply_input(a, 0, 0)
		var evs := _steps(sim, 60)
		var deaths := _of(evs, P.E_DEATH, b.id).size()
		var phews := _of(evs, P.E_PHEW, b.id)
		var arrow_state := -1
		for ar in sim.arrows:
			arrow_state = ar.state
		if safe_on:
			var near: bool = phews.size() == 1 and absf(phews[0][2] - (at.x + 18)) <= 30.0 and absf(phews[0][3] - (at.y + 31)) <= 40.0
			var good: bool = b.state == P.F_NORMAL and deaths == 0 and near and phews[0][5] == 0 \
				and arrow_state == P.S_STUCK and Vector2i(b.x, b.y) == at and b.vx == 0.0
			ok = ok and good
			lines.append("safe: b lives (state %d), %d death, %d PHEW (what %d, at %s; b's middle %s), the arrow lies on the floor (state %d), b moved %d px" % [
				b.state, deaths, phews.size(), phews[0][5] if phews.size() > 0 else -1, str(Vector2i(phews[0][2], phews[0][3])) if phews.size() > 0 else "-",
				str(at + Vector2i(18, 31)), arrow_state, absi(b.x - at.x) + absi(b.y - at.y)])
		else:
			ok = ok and b.state == P.F_DEAD and deaths == 1 and phews.is_empty()
			lines.append("nobody safe: b dies (%d death, %d PHEW)" % [deaths, phews.size()])
	_check("the winner is safe from an arrow: it drops off, E_PHEW says an arrow", ok, "; ".join(lines))

# A bomb goes off at b's feet. With b safe: no death, E_PHEW (b = 1: a blast), and b
# is not thrown (not safe: it dies and its body flies off at 16 px a tick).
func _safe_blast() -> void:
	var lines: Array = []
	var ok := true
	for safe_on in [false, true]:
		var sim = _game(2)
		var a = sim.fighters[0]
		var b = sim.fighters[1]
		sim._place(a, Vector2i(240, 1020))
		sim._place(b, Vector2i(540, 1020))
		_steps(sim, 1)
		if safe_on:
			sim.safe = b.id
		var bomb = SimScript.Arrow.new()   # a bomb arrow stuck in the floor 40 px from b, 3 ticks of fuse left
		bomb.id = 900
		bomb.kind = P.A_BOMB
		bomb.state = P.S_STUCK
		bomb.x = b.x + 18 + 40.0
		bomb.y = b.y + 63.0
		bomb.owner = a.id
		bomb.fuse = 3
		sim.arrows.append(bomb)
		var at := Vector2i(b.x, b.y)
		var evs := _steps(sim, 20)
		var phews := _of(evs, P.E_PHEW, b.id)
		var moved := absi(b.x - at.x) + absi(b.y - at.y)
		if safe_on:
			var good: bool = b.state == P.F_NORMAL and _of(evs, P.E_DEATH).is_empty() and phews.size() == 1 and phews[0][5] == 1 and moved == 0 \
				and _of(evs, P.E_EXPLODE).size() == 1
			ok = ok and good
			lines.append("safe: b lives (state %d), %d PHEW (what %d), moved %d px" % [b.state, phews.size(), phews[0][5] if phews.size() > 0 else -1, moved])
		else:
			ok = ok and b.state == P.F_DEAD and phews.is_empty() and moved > 50
			lines.append("nobody safe: b dies and its body is thrown %d px" % moved)
	_check("the winner is safe from a blast, and is not thrown", ok, "; ".join(lines))

# b stands in poison, then in fire, for 200 ticks. Safe: it lives, and E_PHEW (b = 2)
# comes at most once every PHEW_EVERY ticks (poison and fire try to kill every tick).
func _safe_zones() -> void:
	var lines: Array = []
	var ok := true
	for kind in [P.Z_MIASMA, P.Z_FIRE]:
		var sim = _game(2)
		var b = sim.fighters[1]
		sim._place(sim.fighters[0], Vector2i(240, 1020))
		sim._place(b, Vector2i(540, 1020))
		_steps(sim, 1)
		sim.safe = b.id
		if kind == P.Z_MIASMA:
			sim._add_zone(P.Z_MIASMA, b.x + 18.0, b.y + 31.0, SimScript.MIASMA_R, 400)
		else:
			sim._add_zone(P.Z_FIRE, b.x + 18.0, b.y + 63.0, SimScript.FIRE_WIDTH, 400)
		var evs := _steps(sim, 200)
		var phews := _of(evs, P.E_PHEW, b.id)
		var gap_min := 99999
		var whats := {}
		for i in phews.size():
			whats[phews[i][5]] = true
			if i > 0:
				gap_min = mini(gap_min, phews[i][0] - phews[i - 1][0])
		var first: int = SimScript.MIASMA_KILL_TICKS if kind == P.Z_MIASMA else SimScript.FIRE_KILL_TICKS
		var want := (200 - first) / SimScript.PHEW_EVERY + 1
		var good: bool = b.state != P.F_DEAD and _of(evs, P.E_DEATH).is_empty() and phews.size() == want and gap_min >= SimScript.PHEW_EVERY and whats.keys() == [2]
		ok = ok and good
		lines.append("%s for 200 ticks: b lives, %d PHEW (%d would fit), never closer than %d ticks, what %s" % [
			"poison" if kind == P.Z_MIASMA else "fire", phews.size(), want, gap_min, str(whats.keys())])
	_check("the winner is safe from poison and fire, one E_PHEW every %d ticks at most" % SimScript.PHEW_EVERY, ok, "; ".join(lines))

# a falls on b's head. b safe: b lives and a bounces off. Then b wears spikes and a
# is the safe one: the spikes do not kill a.
func _safe_stomp_and_spikes() -> void:
	var lines: Array = []
	var ok := true
	for spikes in [false, true]:
		var sim = _game(2)
		var a = sim.fighters[0]
		var b = sim.fighters[1]
		sim._place(b, Vector2i(540, 1020))
		sim._place(a, Vector2i(540, 1020 - 110))
		a.vy = 6.0
		sim.safe = a.id if spikes else b.id
		if spikes:
			b.spikes_t = 600
			b.spike_up = true
		var evs := _steps(sim, 30)
		var who: int = a.id if spikes else b.id
		var phews := _of(evs, P.E_PHEW, who)
		var good: bool = a.state != P.F_DEAD and b.state != P.F_DEAD and _of(evs, P.E_DEATH).is_empty() and phews.size() >= 1 and phews[0][5] == 2
		ok = ok and good
		lines.append("%s: both live, %d PHEW for seat %d" % ["a lands on b's spikes, a is safe" if spikes else "a stomps b, b is safe", phews.size(), who])
	# the same stomp with nobody safe kills
	var sim2 = _game(2)
	sim2._place(sim2.fighters[1], Vector2i(540, 1020))
	sim2._place(sim2.fighters[0], Vector2i(540, 1020 - 110))
	sim2.fighters[0].vy = 6.0
	var evs2 := _steps(sim2, 30)
	ok = ok and sim2.fighters[1].state == P.F_DEAD and _of(evs2, P.E_PHEW).is_empty()
	lines.append("nobody safe: the stomp kills (%d death)" % _of(evs2, P.E_DEATH).size())
	_check("the winner is safe from a stomp and from spikes", ok, "; ".join(lines))

# b stands by the left edge while the purple walls come (another fighter is alive, so
# they do not melt): safe, b lives inside the deadly wall.
func _safe_walls() -> void:
	var sim = _game(2)
	var b = sim.fighters[1]
	sim.walls_start = 1
	sim._place(sim.fighters[0], Vector2i(960, 660))
	sim._place(b, Vector2i(80, 1020))
	sim.safe = b.id
	var evs := _steps(sim, 400)
	var phews := _of(evs, P.E_PHEW, b.id)
	var inside: bool = sim.walls_deadly() and b.x < sim.walls_width() - SimScript.WALLS_EDGE
	_check("the winner is safe from the purple walls", b.state != P.F_DEAD and inside and phews.size() >= 2 and phews[0][5] == 2 and _of(evs, P.E_DEATH).is_empty(),
		"b at x=%d inside a deadly wall %d px wide for %d ticks: it lives, %d PHEW" % [b.x, sim.walls_width(), 400 - SimScript.WALLS_DEADLY, phews.size()])

# The three that the server never lets run once a round is decided (lightning, the
# ghost cats, a costume's knife need a second living fighter): forced here, each
# still spares the safe one.
func _safe_lightning_cat_knife() -> void:
	var lines: Array = []
	var ok := true
	# lightning: an orb's bolt strikes where b stands
	var sim = _game(2)
	var a = sim.fighters[0]
	var b = sim.fighters[1]
	sim.powerups = true
	sim._place(a, Vector2i(240, 1020))
	sim._place(b, Vector2i(540, 1020))
	_steps(sim, 3)
	sim.safe = b.id
	var o = SimScript.Orb.new()
	o.kind = P.PU_INF
	o.state = P.ORB_WARN
	o.t = SimScript.PU_WARN - 2
	o.x = b.x + 18.0
	o.y = b.y + 31.0
	sim.orbs.append(o)
	var at := Vector2i(b.x, b.y)
	var evs := _steps(sim, 6)
	var good: bool = _of(evs, P.E_STRIKE).size() == 1 and b.state != P.F_DEAD and _of(evs, P.E_PHEW, b.id).size() == 1 and Vector2i(b.x, b.y) == at
	ok = ok and good
	lines.append("lightning on b: %d strike, b lives, %d PHEW, moved %d px" % [_of(evs, P.E_STRIKE).size(), _of(evs, P.E_PHEW, b.id).size(), absi(b.x - at.x) + absi(b.y - at.y)])
	# the ghost cats
	sim = _game(2)
	a = sim.fighters[0]
	b = sim.fighters[1]
	sim._place(a, Vector2i(240, 1020))
	sim._place(b, Vector2i(540, 1020))
	_steps(sim, 3)
	sim.safe = b.id
	sim._send_cats(a)
	evs = _steps(sim, 240)
	good = b.state != P.F_DEAD and _of(evs, P.E_PHEW, b.id).size() >= 1 and _of(evs, P.E_DEATH).is_empty()
	ok = ok and good
	lines.append("3 ghost cats at b: b lives, %d PHEW, %d cats left" % [_of(evs, P.E_PHEW, b.id).size(), sim.cats.size()])
	# a costume's knife
	sim = _game(2)
	a = sim.fighters[0]
	b = sim.fighters[1]
	sim._place(a, Vector2i(500, 1020))
	sim._place(b, Vector2i(540, 1020))
	_steps(sim, 3)
	sim.safe = b.id
	a.mask = true
	sim._knife(a, 0.0, false)
	evs = _steps(sim, 20)
	good = b.state != P.F_DEAD and _of(evs, P.E_KNIFE).size() == 1 and _of(evs, P.E_PHEW, b.id).size() == 1 and _of(evs, P.E_DEATH).is_empty()
	ok = ok and good
	lines.append("a knife swing at b: b lives, %d PHEW" % _of(evs, P.E_PHEW, b.id).size())
	_check("the winner is safe from lightning, a ghost cat and a knife", ok, "; ".join(lines))

# THE BOILER ROOM: the victim stands in each furnace's fire (as boiler_probe.gd does).
# Safe: it lives and is not thrown.
func _safe_furnace() -> void:
	var lines: Array = []
	var ok := true
	for i in Boiler.FURNACES.size():
		var sim = _game(2, 4)
		for f in sim.fighters:
			f.wait_t = 99999
		var spec: Array = Boiler.FURNACES[i]
		var r: Rect2 = spec[2]
		var c := r.get_center()
		var victim = sim.fighters[0]
		sim._place(sim.fighters[1], Vector2i(1700, 240))
		sim._place(victim, Vector2i(int(c.x), int(r.end.y)))
		sim.safe = victim.id
		var hz = sim.hazards
		for h in hz.furnaces + hz.pipes:
			h.wait = 99999
		hz.hook.wait = 99999
		hz.lights_wait = 99999
		hz.surge_wait = 99999
		hz.tick = 2
		hz._to_phase(hz.furnaces[i], Boiler.WARN)
		var phews := 0
		var deaths := 0
		var blast := false
		var thrown := 0.0
		for t in Boiler.FURNACE_WARN + Boiler.FURNACE_BLAST + 5:
			sim._place(victim, Vector2i(int(c.x), int(r.end.y)))   # held in the fire (it would fall from a hanging spot)
			sim.step()
			thrown = maxf(thrown, absf(victim.vx))
			for e in sim.take_events():
				if e[0] == P.E_FURNACE:
					blast = true
				elif e[0] == P.E_PHEW and e[3] == victim.id and e[4] == 2:
					phews += 1
				elif e[0] == P.E_DEATH:
					deaths += 1
		var good: bool = blast and victim.state != P.F_DEAD and deaths == 0 and phews >= 1 and thrown == 0.0
		ok = ok and good
		lines.append("F%d: fire %s, the one in it %s, %d PHEW, thrown %.0f px a tick" % [i, "came" if blast else "NEVER CAME",
			"lives" if victim.state != P.F_DEAD else "DIED", phews, thrown])
	_check("the winner is safe in a furnace's fire (THE BOILER ROOM)", ok, "; ".join(lines))

# The winner in a costume (GHOSTFACE, THE BIG TURKEY): an arrow does not knock it down
# either, and one while it is down does not end it.
func _safe_costume() -> void:
	var sim = _game(2)
	var a = sim.fighters[0]
	var b = sim.fighters[1]
	sim._place(a, Vector2i(240, 1020))
	sim._place(b, Vector2i(540, 1020))
	_steps(sim, 1)
	b.mask = true
	sim.safe = b.id
	a.inf = true
	var evs: Array = []
	for shot in 2:
		sim.apply_input(a, P.B_SHOOT, 0)
		evs.append_array(_steps(sim, 2))
		sim.apply_input(a, 0, 0)
		evs.append_array(_steps(sim, 50))
	_check("the winner in a costume is safe too: no knock-down, no end", b.state == P.F_NORMAL and _of(evs, P.E_MASK_DOWN).is_empty() and _of(evs, P.E_DEATH).is_empty() and _of(evs, P.E_PHEW, b.id).size() == 2,
		"2 arrows at GHOSTFACE: state %d, %d knock-downs, %d deaths, %d PHEW" % [b.state, _of(evs, P.E_MASK_DOWN).size(), _of(evs, P.E_DEATH).size(), _of(evs, P.E_PHEW, b.id).size()])

# A new round (and the lobby) makes nobody safe again.
func _safe_ends_with_the_round() -> void:
	var sim = _game(2)
	sim.safe = 1
	sim.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": false}])
	var after_round: int = sim.safe
	sim.safe = 1
	sim.clear()
	_check("a new round makes nobody safe", after_round == -1 and sim.safe == -1, "after start_round %d, after clear %d (-1: nobody)" % [after_round, sim.safe])

# The page's copy of your fighter stays in step. You won, the round is called, and you
# shoot bombs at your own feet (kids do). The server does not throw you; the copy must
# not either. The page hears "you are safe" in each T_OWN (proto OWN_SAFE). Run twice:
# with the flag (the page never moves you wrongly), and without it (the copy throws
# you, then the server's word yanks you back), on a slow link (inputs 12 ticks ahead,
# T_OWN 20 ticks late) so the copy's bomb goes off before the server's word comes.
# Measured: where the page drew you on each tick, beside where the server really had
# you on that tick (0 px: the copy was right all along).
func _safe_prediction() -> void:
	var res: Array = []
	for flag_on in [true, false]:
		var server = _game(2)
		var f = server.fighters[0]
		server._place(f, Vector2i(300, 1020))
		server._place(server.fighters[1], Vector2i(1500, 1020))
		server.fighters[1].state = P.F_DEAD       # the loser: the round is called
		server.fighters[1].dead_t = 99999
		server.safe = f.id
		f.pw_kind = P.A_BOMB
		f.inf = true
		var pred = Predict.new()
		pred.seat = 0
		var lead := 12
		var delay := 20
		var sent := {}
		var pending: Array = []
		var phews := 0
		var shown := {}      # tick -> where the page drew you on it
		var truth := {}      # tick -> where the server had you
		for st in range(1, 901):
			# every 90 ticks: stand, aim straight down 3 ticks, let go; then a few steps right or left
			var c := st % 90
			var b := P.B_SHOOT if c < 3 else ((P.B_RIGHT if (st / 90) % 2 == 0 else P.B_LEFT) if c > 40 and c < 60 else 0)
			sent[st + lead] = [b, 900]
			pred.on_tick(st + lead, b, 900)
			if pred.me != null:
				shown[st + lead] = Vector2(pred.me.x, pred.me.y)
			var inp: Array = sent.get(st, [0, 900])
			server.apply_input(f, inp[0], inp[1])
			server.step()
			truth[st] = Vector2(f.x, f.y)
			for e in server.take_events():
				if e[0] == P.E_PHEW:
					phews += 1
			if server.tick % 2 == 0:
				var buf := StreamPeerBuffer.new()
				server.write_fighter_state(buf, f)
				pending.append([st + delay, {"tick": server.tick, "used": st, "margin": lead, "late": 0,
					"flags": P.OWN_FIGHTER | (P.OWN_SAFE if flag_on else 0), "moves_from": 0, "pkt": buf.data_array, "at": 0}])
			while pending.size() > 0 and pending[0][0] <= st:
				pred.reconcile(pending.pop_front()[1])
		var worst := 0.0
		for e in pred.errors:
			worst = maxf(worst, e)
		var off := 0.0
		var off_n := 0
		for t in shown:
			if truth.has(t):
				var d: float = (shown[t] - truth[t]).length()
				off = maxf(off, d)
				if d > 0.5:
					off_n += 1
		res.append([pred.errors.size(), worst, off, phews, f.state, off_n])
	var with_flag: Array = res[0]
	var without: Array = res[1]
	_check("the page's copy stays in step while the winner is safe (your own bombs at your feet)",
		with_flag[0] > 400 and with_flag[1] == 0.0 and with_flag[2] == 0.0 and with_flag[3] >= 8 and with_flag[4] != P.F_DEAD and without[2] > 20.0,
		"with OWN_SAFE: %d corrections, the worst %.1f px; drawn wrong on %d ticks, at most %.1f px; %d PHEW on the server, the winner lives. Without it (the copy not told): drawn wrong on %d ticks, at most %.1f px" % [
		with_flag[0], with_flag[1], with_flag[5], with_flag[2], with_flag[3], without[5], without[2]])

# Bug 3: three people in a round, seat 1 gives its seat up: its fighter dies at once
# (E_DEATH cause 12, E_KILL with no killer), no ghost rises, the others play on. A
# costume does not save it (a hit only knocks GHOSTFACE down: this is no hit), nor
# does being the round's safe winner (it left: nobody is left to keep safe).
func _freed_seat() -> void:
	var lines: Array = []
	var ok := true
	for how in ["plain", "in a costume", "the safe winner"]:
		var sim = _game(3)
		var b = sim.fighters[1]
		sim._place(sim.fighters[0], Vector2i(240, 1020))
		sim._place(b, Vector2i(540, 1020))
		sim._place(sim.fighters[2], Vector2i(700, 1020))
		_steps(sim, 2)
		if how == "in a costume":
			b.mask = true
		elif how == "the safe winner":
			sim.safe = b.id
		sim.leave(b.id)
		sim.leave(b.id)       # twice is once
		var evs := _steps(sim, 120)
		var deaths := _of(evs, P.E_DEATH, b.id)
		var kills := _of(evs, P.E_KILL)
		var good: bool = b.state == P.F_DEAD and deaths.size() == 1 and deaths[0][5] == P.C_LEFT and kills.size() == 1 and kills[0][4] == 255 \
			and kills[0][5] == b.id and not b.ghost and _of(evs, P.E_GHOST).is_empty() and sim.alive_count() == 2 and sim.safe == -1 \
			and _of(evs, P.E_PHEW).is_empty()
		ok = ok and good
		lines.append("%s: %d death (cause %d: %s), killer %d, ghost %s, %d left alive, safe %d" % [how, deaths.size(), deaths[0][5] if deaths.size() > 0 else -1,
			P.CAUSES.get(deaths[0][5] if deaths.size() > 0 else -1, "-"), kills[0][4] if kills.size() > 0 else -1, "rises" if b.ghost else "none", sim.alive_count(), sim.safe])
	# a seat with no fighter (it joined mid-round), or a dead one: nothing happens
	var sim2 = _game(2)
	sim2.leave(5)
	var none := _steps(sim2, 5)
	ok = ok and _of(none, P.E_DEATH).is_empty()
	_check("a seat given up in a round: its fighter goes out at once (cause %d, %s), so an empty seat cannot win" % [P.C_LEFT, P.CAUSES[P.C_LEFT]], ok, "; ".join(lines))

# Bug 9: the replay's length. The real deathcam gets n kills by seat 0 (each with the
# 3.5 s of frames before it and 0.8 s after, as it records them), and plays its montage
# at 60 frames a second to the end. proto.gd's replay_secs(n), which the server adds
# to the winner's screen, must say the same time (the frames are 1/20 s apart and a
# part changes on the frame after its end: 0.2 s of room).
func _replay_length() -> void:
	var lines: Array = []
	var ok := true
	for n in [0, 1, 2, 3, 6, 9]:
		var cam = Deathcam.new()
		for k in n:
			var frames: Array = []
			for i in 87:      # 20 a second: 70 before the kill (3.5 s), the kill's frame, 16 after (0.8 s)
				frames.append({"t": k * 10.0 + i / 20.0, "view": {}, "evs": []})
			var clip := {"killer": 0, "victim": 1, "frames": frames, "kill_i": 70, "open_s": 0.0, "at": Vector2(960, 540)}
			var list: Array = cam.clips.get(0, [])
			list.append(clip)
			if list.size() > Deathcam.MAX_PER_KILLER:
				list.pop_front()
			cam.clips[0] = list
		var started: bool = cam.start(0, ["A", "B"])
		var secs := 0.0
		while cam.playing and secs < 60.0:
			cam.step(1.0 / 60.0)
			secs += 1.0 / 60.0
		var want: float = P.replay_secs(n)
		var good: bool = absf(secs - want) <= 0.2 and started == (n > 0)
		ok = ok and good
		lines.append("%d kills: the deathcam plays %.2f s, replay_secs says %.2f s" % [n, secs, want])
		cam.free()
	_check("the server's replay length (proto.gd replay_secs) is the deathcam's own", ok, "; ".join(lines))

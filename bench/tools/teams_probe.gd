# TEAMS, proved (2026-11-24). The lobby's MODE can be TEAMS: two teams, no friendly fire,
# a round goes to the last team standing. This probe checks every rule, with no network:
#   1. THE RULES IN THE SIM (sim/sim.gd friends, decided, safe_team). Each "a teammate
#      cannot hurt you" rule is run three ways from the same start: as teammates (nothing
#      happens), as foes in TEAMS, and in FREE FOR ALL (both: it hurts, as it always did).
#      The two last ones show the test would have caught a hit.
#   2. THE BOTS (sim/brain.gd): 200 whole rounds of 4 against 4. How many arrows a bot
#      aimed at a teammate, and how many times anyone was hurt by a teammate: both 0.
#   3. THE SERVER (server/game_server.gd), run in here tick by tick with no sockets: who
#      goes to which team, the tap that changes sides, the bots spread evenly, START
#      refused when a team is empty, a round won by a team, a draw, one point for the
#      team on every member, every living winner safe (PHEW), the match to the goal, the
#      catch-up SHIELD for the team behind, the log line.
#   4. THE PAGE'S COPIES (client/present.gd, client/predict.gd): a teammate's arrow is
#      not stopped at a teammate, and the page hears "you are safe" for a whole team.
#   godot --headless --path bench --script res://tools/teams_probe.gd
#       [-- --only=rules|bots|server|page] [--bot-rounds=200]
#       [--balance[=300]]   bots only: how long a round lasts and who wins, 4 against 4,
#                           2 against 2 and 1 against 3 on the Harvest season's arenas
# Prints a PASS/FAIL line per rule and exits 1 on a fail.
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const Brain = preload("res://sim/brain.gd")
const ServerScript = preload("res://server/game_server.gd")
const Present = preload("res://client/present.gd")
const Predict = preload("res://client/predict.gd")

# seats 0 and 1 together against seat 2; seat 0 against seats 1 and 2; nobody with anybody
const MATES := {0: 0, 1: 0, 2: 1}
const FOES := {0: 0, 1: 1, 2: 1}
const FFA := {}
const WAYS := [["teammates", MATES], ["foes", FOES], ["free for all", FFA]]

var fails := 0
var checks := 0
var only := ""
var bot_rounds := 200
var balance := 0
var quiet_server := true

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
		elif a.begins_with("--bot-rounds="):
			bot_rounds = int(a.substr(13))
		elif a == "--balance":
			balance = 300
		elif a.begins_with("--balance="):
			balance = int(a.substr(10))
	if balance > 0:
		_balance()
		quit(0)
		return
	if only == "" or only == "rules":
		_arrow()
		_stomp()
		_bump()
		_blast()
		_fire_and_poison()
		_pie()
		_peck()
		_cats()
		_freeze_and_rain()
		_boo()
		_bats()
		_aim_help()
		_shared_arrows()
		_nobodys_dangers()
		_decided()
		_team_safe()
		_snapshot_bits()
	if only == "" or only == "bots":
		_bots_pick()
		_bots_rounds()
	if only == "" or only == "server":
		_server_picker()
		_server_start_needs_both()
		_server_round_and_point()
		_server_draws()
		_server_match()
		_server_leavers()
		_server_mode_in_a_match()
		_server_ffa_is_ffa()
	if only == "" or only == "page":
		_page_arrows()
		_page_safe()
	if fails == 0:
		print("✅ teams_probe: %d of %d checks passed" % [checks, checks])
		quit(0)
	else:
		printerr("❌ teams_probe: %d of %d checks failed" % [fails, checks])
		quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	checks += 1
	fails += 0 if ok else 1
	print("%s %s: %s" % ["PASS" if ok else "FAIL", name, detail])

# ------------------------------------------------------------------ helpers (the sim)
# A sim with people on n seats (no bots), nobody respawns, on the bench arena, with
# these teams (seat -> team; {}: FREE FOR ALL).
func _game(n: int, teams: Dictionary, arena: int = 0) -> RefCounted:
	var sim = SimScript.new(0, 24, 7)
	sim.set_arena(arena)
	sim.respawn = false
	sim.power_arrows = false
	var seats: Array = []
	for i in n:
		seats.append({"id": i, "bot": false})
	sim.start_round(seats)
	sim.teams = teams.duplicate()
	return sim

# Three people on the bench arena's floor: a (seat 0) at x 240, b (seat 1) at bx, and c
# (seat 2) far away on the right floor. c keeps the round going: with a and b teammates
# there is still a foe alive.
func _three(teams: Dictionary, bx: int = 540) -> Array:
	var sim = _game(3, teams)
	sim._place(sim.fighters[0], Vector2i(240, 1020))
	sim._place(sim.fighters[1], Vector2i(bx, 1020))
	sim._place(sim.fighters[2], Vector2i(1680, 1020))
	_steps(sim, 1)
	return [sim, sim.fighters[0], sim.fighters[1], sim.fighters[2]]

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

# Seat 0 draws the bow, aims (0.1 degree steps) and lets go.
func _shoot(sim, f, aim: int = 0) -> void:
	sim.apply_input(f, P.B_SHOOT, aim)
	_steps(sim, 2)
	sim.apply_input(f, 0, aim)

# An arrow of `owner` lying stuck at (x, y).
func _stuck(sim, owner: int, x: float, y: float, kind: int = P.A_NORMAL, fuse: int = -1):
	var ar = SimScript.Arrow.new()
	ar.id = 900 + sim.arrows.size()
	ar.kind = kind
	ar.state = P.S_STUCK
	ar.x = x
	ar.y = y
	ar.owner = owner
	ar.fuse = fuse
	ar.stuck_t = SimScript.PICKUP_DELAY
	sim.arrows.append(ar)
	return ar

# ------------------------------------------------------------------ 1. the rules in the sim
# a shoots at b, 180 px away on the same floor. A teammate: the arrow flies through b
# and lands in the floor behind it. Then b with a SHIELD (it is not used up) and b in a
# dodge (no catch: the arrow is not b's to take out of the air).
func _arrow() -> void:
	var lines: Array = []
	var ok := true
	for way in WAYS:
		var g := _three(way[1], 420)
		var sim = g[0]
		var b = g[2]
		b.arrows = SimScript.MAX_QUIVER     # (a full quiver: b cannot pick the arrow up once it lies behind it)
		_shoot(sim, g[1])
		var evs := _steps(sim, 60)
		var ar = sim.arrows[0] if sim.arrows.size() > 0 else null
		var behind: bool = ar != null and ar.state == P.S_STUCK and ar.x > b.x + SimScript.BODY_W
		if way[0] == "teammates":
			ok = ok and b.state == P.F_NORMAL and _of(evs, P.E_DEATH).is_empty() and behind
			lines.append("teammates: b lives, the arrow lies in the floor at x %d, behind b (b's body ends at x %d)" % [int(ar.x) if ar != null else -1, b.x + SimScript.BODY_W])
		else:
			ok = ok and b.state == P.F_DEAD and _of(evs, P.E_DEATH, b.id).size() == 1
			lines.append("%s: b is knocked out" % way[0])
	# a teammate's arrow and b's SHIELD, then b's dodge
	for what in ["shield", "dodge"]:
		for way in [WAYS[0], WAYS[1]]:
			var g := _three(way[1], 420)
			var sim = g[0]
			var b = g[2]
			if what == "shield":
				b.shield = 1
			else:
				b.state = P.F_DODGE     # a dodge held on the spot for 40 ticks
				b.dodge_t = 40
			_shoot(sim, g[1])
			var evs := _steps(sim, 30)
			var pops := _of(evs, P.E_SHIELD_POP, b.id).size()
			var catches := _of(evs, P.E_CATCH, b.id).size()
			if way[0] == "teammates":
				ok = ok and pops == 0 and catches == 0 and b.shield == (1 if what == "shield" else 0) and b.arrows == SimScript.START_QUIVER
				lines.append("teammates, b %s: %d shield used, %d catch, b holds %d arrows" % ["has a SHIELD" if what == "shield" else "dodges", pops, catches, b.arrows])
			else:
				ok = ok and (pops == 1 if what == "shield" else catches == 1)
				lines.append("foes, b %s: %s" % ["has a SHIELD" if what == "shield" else "dodges", "the shield takes it" if what == "shield" else "b catches it"])
	_check("a teammate's arrow passes through you (no hit, no shield used, no catch)", ok, "; ".join(lines))

# a comes down on b's head. Teammates: a bounces off (the jump event a stomp gives) and
# nobody is hurt, also when b wears the SPIKED SHIELD. Foes: b is out; with spikes, a is.
func _stomp() -> void:
	var lines: Array = []
	var ok := true
	for spikes in [false, true]:
		for way in WAYS:
			var sim = _game(3, way[1])
			var a = sim.fighters[0]
			var b = sim.fighters[1]
			sim._place(b, Vector2i(540, 1020))
			sim._place(a, Vector2i(540, 1020 - 110))
			sim._place(sim.fighters[2], Vector2i(1680, 1020))
			a.vy = 6.0
			if spikes:
				b.spikes_t = 600
				b.spike_up = true
			var evs := _steps(sim, 30)
			var bounce := 0
			for e in _of(evs, P.E_JUMP, a.id):
				if e[5] == 1:
					bounce += 1
			if way[0] == "teammates":
				ok = ok and a.state != P.F_DEAD and b.state != P.F_DEAD and _of(evs, P.E_DEATH).is_empty() and bounce >= 1 and _of(evs, P.E_HURT).is_empty()
				lines.append("teammates%s: both live, a bounced %d time(s)" % [", b has spikes" if spikes else "", bounce])
			else:
				var dead = a if spikes else b
				ok = ok and dead.state == P.F_DEAD
				lines.append("%s%s: %s is knocked out" % [way[0], ", b has spikes" if spikes else "", "a" if spikes else "b"])
	_check("a teammate's stomp bounces off and hurts nobody (spikes too)", ok, "; ".join(lines))

# a runs into b at 12 px a tick (a hard bump: the slower one is knocked). Teammates: no
# knock, only the soft nudge apart.
func _bump() -> void:
	var lines: Array = []
	var ok := true
	for way in WAYS:
		var g := _three(way[1])
		var sim = g[0]
		var a = g[1]
		var b = g[2]
		a.x = b.x - 24
		a.vx = 12.0
		var evs := _steps(sim, 3)
		var knocks := _of(evs, P.E_HURT, b.id).size()
		if way[0] == "teammates":
			ok = ok and knocks == 0 and b.state == P.F_NORMAL
		else:
			ok = ok and knocks == 1
		lines.append("%s: b knocked %d time(s)" % [way[0], knocks])
	_check("a teammate running into you does not knock you", ok, "; ".join(lines))

# a's bomb goes off 40 px from b (inside the blast), then 200 px from b (the ring
# around it, where a foe is knocked back). Teammates: nothing at all. And b's own bomb
# still throws b, in every mode (your own blast is no friendly fire: the rule of p4.19).
func _blast() -> void:
	var lines: Array = []
	var ok := true
	for dist in [40.0, 200.0]:
		for way in WAYS:
			var g := _three(way[1])
			var sim = g[0]
			var b = g[2]
			_stuck(sim, 0, b.x + 18 + dist, b.y + 63.0, P.A_BOMB, 3)
			var at := Vector2i(b.x, b.y)
			var evs := _steps(sim, 20)
			var moved := absi(b.x - at.x) + absi(b.y - at.y)
			var knocks := _of(evs, P.E_HURT, b.id).size()
			if way[0] == "teammates":
				ok = ok and b.state == P.F_NORMAL and moved == 0 and knocks == 0 and _of(evs, P.E_EXPLODE).size() == 1
				lines.append("teammates, %d px: b lives, moved %d px, knocked %d" % [int(dist), moved, knocks])
			elif dist < 100.0:
				ok = ok and b.state == P.F_DEAD
				lines.append("%s, %d px: b is knocked out" % [way[0], int(dist)])
			else:
				ok = ok and b.state != P.F_DEAD and knocks == 1
				lines.append("%s, %d px: b is knocked back" % [way[0], int(dist)])
	for way in WAYS:
		var g := _three(way[1])
		var sim = g[0]
		var b = g[2]
		_stuck(sim, 1, b.x + 18 + 40.0, b.y + 63.0, P.A_BOMB, 3)
		var evs := _steps(sim, 6)
		ok = ok and b.state != P.F_DEAD and _of(evs, P.E_HURT, b.id).size() == 1
		lines.append("%s, b's own bomb: b is thrown, not out" % way[0])
	_check("a teammate's blast does nothing to you", ok, "; ".join(lines))

# b stands 200 ticks in fire, then in poison, from a's arrow. Teammates: b does not
# burn or choke at all. Fire that is b's own, or nobody's, still burns b.
func _fire_and_poison() -> void:
	var lines: Array = []
	var ok := true
	for kind in [P.Z_FIRE, P.Z_MIASMA]:
		var word := "fire" if kind == P.Z_FIRE else "poison"
		for way in WAYS:
			for owner in [0, 1, -1]:
				if owner != 0 and way[0] != "teammates":
					continue
				var g := _three(way[1])
				var sim = g[0]
				var b = g[2]
				if kind == P.Z_FIRE:
					sim._add_zone(P.Z_FIRE, b.x + 18.0, b.y + 63.0, SimScript.FIRE_WIDTH, 400, owner)
				else:
					sim._add_zone(P.Z_MIASMA, b.x + 18.0, b.y + 31.0, SimScript.MIASMA_R, 400, owner)
				var worst := 0
				for i in 200:
					sim.step()
					worst = maxi(worst, maxi(b.burn_t, b.miasma_t))
				sim.take_events()
				var whose: String = "a's" if owner == 0 else ("b's own" if owner == 1 else "nobody's")
				if way[0] == "teammates" and owner == 0:
					ok = ok and b.state == P.F_NORMAL and worst == 0
					lines.append("teammates, %s %s: b lives, never %s" % [whose, word, "burning" if kind == P.Z_FIRE else "choking"])
				else:
					ok = ok and b.state == P.F_DEAD
					lines.append("%s, %s %s: b is knocked out" % [way[0], whose, word])
	_check("a teammate's fire and poison do nothing to you", ok, "; ".join(lines))

# a's pie splats 200 px from b (the cream reaches 300 px), then 40 px from b (its small
# blast). Teammates: no cream, no blast.
func _pie() -> void:
	var lines: Array = []
	var ok := true
	for dist in [200.0, 40.0]:
		for way in WAYS:
			var g := _three(way[1])
			var sim = g[0]
			var b = g[2]
			var pie = SimScript.Arrow.new()
			pie.kind = P.A_PIE
			pie.owner = 0
			pie.x = b.x + 18 + dist
			pie.y = b.y + 31.0
			sim._pie(pie)
			var evs := _steps(sim, 2)
			var creamed := _of(evs, P.E_PIED, b.id).size()
			if way[0] == "teammates":
				ok = ok and b.pied_t == 0 and creamed == 0 and b.state == P.F_NORMAL and not b.in_smoke
				lines.append("teammates, %d px: b has no cream and stands" % int(dist))
			elif dist < 100.0:
				ok = ok and b.state == P.F_DEAD
				lines.append("%s, %d px: b is knocked out by the pie's blast" % [way[0], int(dist)])
			else:
				ok = ok and creamed == 1 and b.pied_t > 0 and b.state != P.F_DEAD
				lines.append("%s, %d px: b is creamed" % [way[0], int(dist)])
	_check("a teammate's pie does not cream you", ok, "; ".join(lines))

# a wears the costume (GHOSTFACE, THE BIG TURKEY) and swings at b, 40 px in front.
# Teammates: a miss, and b's SHIELD is not used up either.
func _peck() -> void:
	var lines: Array = []
	var ok := true
	for shield in [0, 1]:
		for way in WAYS:
			var g := _three(way[1], 280)
			var sim = g[0]
			var a = g[1]
			var b = g[2]
			b.shield = shield
			a.mask = true
			sim._knife(a, 0.0, false)
			var evs := _steps(sim, 20)
			if way[0] == "teammates":
				ok = ok and b.state == P.F_NORMAL and b.shield == shield and _of(evs, P.E_SHIELD_POP).is_empty() and _of(evs, P.E_KNIFE).size() == 1
				lines.append("teammates%s: b stands%s" % [", b has a SHIELD" if shield else "", ", the shield is whole" if shield else ""])
			else:
				ok = ok and (b.shield == 0 and _of(evs, P.E_SHIELD_POP, b.id).size() == 1 if shield else b.state == P.F_DEAD)
				lines.append("%s%s: %s" % [way[0], ", b has a SHIELD" if shield else "", "the shield takes it" if shield else "b is knocked out"])
	_check("a teammate's peck (or knife) misses you", ok, "; ".join(lines))

# a lets the GHOST CATS go. Teammates: every cat hunts the foe (c), and b, who stands
# nearest, is never caught. With no foe alive, no cat leaves.
func _cats() -> void:
	var lines: Array = []
	var ok := true
	for way in WAYS:
		var g := _three(way[1])
		var sim = g[0]
		var b = g[2]
		sim._send_cats(g[1])
		var targets: Array = []
		for c in sim.cats:
			targets.append(c.target)
		var evs := _steps(sim, 300)
		if way[0] == "teammates":
			ok = ok and targets == [2, 2, 2] and b.state == P.F_NORMAL and _of(evs, P.E_DEATH, b.id).is_empty()
			lines.append("teammates: the 3 cats hunt seats %s (c is seat 2); b lives; c is %s" % [str(targets), "caught" if g[3].state == P.F_DEAD else "not caught"])
		else:
			ok = ok and targets.has(1) and b.state == P.F_DEAD
			lines.append("%s: the cats hunt seats %s; b is caught" % [way[0], str(targets)])
	var two = _game(2, {0: 0, 1: 0})
	two._send_cats(two.fighters[0])
	ok = ok and two.cats.is_empty()
	lines.append("only a teammate alive: %d cats leave" % two.cats.size())
	_check("a teammate's ghost cats never hunt you", ok, "; ".join(lines))

# a takes FREEZE, then RAIN. Teammates: b is not frozen and not slowed; the foe c is.
func _freeze_and_rain() -> void:
	var lines: Array = []
	var ok := true
	for way in WAYS:
		var g := _three(way[1])
		var sim = g[0]
		var b = g[2]
		var c = g[3]
		sim._give(g[1], P.PU_FREEZE)
		var frozen := [b.freeze_t > 0, c.freeze_t > 0]
		g = _three(way[1])
		sim = g[0]
		b = g[2]
		c = g[3]
		sim._give(g[1], P.PU_RAIN)
		_steps(sim, 5)
		var slowed := [SimScript.speed_mult(b) < 1.0, SimScript.speed_mult(c) < 1.0]
		if way[0] == "teammates":
			ok = ok and frozen == [false, true] and slowed == [false, true]
		else:
			ok = ok and frozen == [true, true] and slowed == [true, true]
		lines.append("%s: frozen b %s, c %s; slowed by the rain b %s, c %s" % [way[0], frozen[0], frozen[1], slowed[0], slowed[1]])
	_check("a teammate's FREEZE and RAIN leave you alone", ok, "; ".join(lines))

# a is out and floats as a ghost; it dashes (BOO) through b. Teammates: b is not shoved.
# Then b shoots through a's ghost: a teammate's arrow does not pop it.
func _boo() -> void:
	var lines: Array = []
	var ok := true
	for way in WAYS:
		var g := _three(way[1])
		var sim = g[0]
		var a = g[1]
		var b = g[2]
		a.state = P.F_DEAD
		a.dead_t = 9999
		a.ghost = true
		a.gx = b.x + 18.0 - 100.0
		a.gy = b.y + 31.0
		sim.apply_input(a, P.B_SHOOT, 0)
		_steps(sim, 1)
		sim.apply_input(a, 0, 0)        # let go: the dash, to the right
		var evs := _steps(sim, 15)
		var shoved := 0
		for e in _of(evs, P.E_BOO, a.id):
			if e[5] == b.id:
				shoved += 1
		if way[0] == "teammates":
			ok = ok and shoved == 0 and b.state == P.F_NORMAL
		else:
			ok = ok and shoved == 1
		lines.append("%s: b shoved %d time(s)" % [way[0], shoved])
	for way in WAYS:
		var g := _three(way[1])
		var sim = g[0]
		var a = g[1]
		var b = g[2]
		a.x = 700          # (the body lies out of the arrow's way)
		a.state = P.F_DEAD
		a.dead_t = 9999
		a.ghost = true
		a.gx = b.x + 18.0 + 140.0
		a.gy = b.y + 28.0 + 4.0
		_shoot(sim, b)
		var evs := _steps(sim, 20)
		var pops := _of(evs, P.E_GHOST_POP, a.id).size()
		ok = ok and pops == (0 if way[0] == "teammates" else 1)
		lines.append("%s: b's arrow pops a's ghost %d time(s)" % [way[0], pops])
	_check("a teammate's ghost cannot BOO you, and your arrow does not pop it", ok, "; ".join(lines))

# b has the BAT SWARM (the bats knock arrows away within 85 px). a shoots at b.
# Teammates: the bats let it by (and it flies through b). Foes: it is knocked down.
func _bats() -> void:
	var lines: Array = []
	var ok := true
	for way in WAYS:
		var g := _three(way[1], 420)
		var sim = g[0]
		var b = g[2]
		b.bats_t = 480
		b.arrows = SimScript.MAX_QUIVER     # (so b does not pick the arrow up when it lies behind it)
		_shoot(sim, g[1])
		var fell := false
		for i in 60:
			sim.step()
			for ar in sim.arrows:
				if ar.state == P.S_FALL:
					fell = true
		sim.take_events()
		var ar0 = sim.arrows[0] if sim.arrows.size() > 0 else null
		if way[0] == "teammates":
			ok = ok and not fell and ar0 != null and ar0.x > b.x + SimScript.BODY_W and b.state == P.F_NORMAL
			lines.append("teammates: the arrow is not knocked away, it lands behind b at x %d" % (int(ar0.x) if ar0 != null else -1))
		else:
			ok = ok and fell and b.state == P.F_NORMAL
			lines.append("%s: the bats knock the arrow down" % way[0])
	_check("a teammate's bats let your arrows by", ok, "; ".join(lines))

# A person's shot snaps to an enemy near its line (the aim help). a aims 30 degrees up,
# b stands 120 px in front. Teammates: the shot goes where a aimed. Foes: it snaps to b.
func _aim_help() -> void:
	var lines: Array = []
	var ok := true
	for way in WAYS:
		var g := _three(way[1], 360)
		var sim = g[0]
		var a = g[1]
		_shoot(sim, a, 3300)
		var deg := rad_to_deg(angle_difference(0.0, a.aim))
		if way[0] == "teammates":
			ok = ok and absf(deg - -30.0) < 0.5
		else:
			ok = ok and absf(deg) < 5.0
		lines.append("%s: the arrow leaves at %.1f degrees" % [way[0], deg])
	_check("the aim help never pulls a shot to a teammate", ok, "; ".join(lines))

# The point of a team: b picks up a's arrow from the floor.
func _shared_arrows() -> void:
	var g := _three(MATES)
	var sim = g[0]
	var b = g[2]
	_stuck(sim, 0, b.x + 18.0, b.y + 50.0)
	var evs := _steps(sim, 3)
	_check("a teammate can pick up your arrows", b.arrows == SimScript.START_QUIVER + 1 and _of(evs, P.E_PICKUP, b.id).size() == 1,
		"b stood on a's arrow: b holds %d arrows (it had %d)" % [b.arrows, SimScript.START_QUIVER])

# What belongs to nobody hits everyone, teams or not: an orb's lightning on b, and the
# purple walls on b (a and b are teammates, c is the foe).
func _nobodys_dangers() -> void:
	var lines: Array = []
	var g := _three(MATES)
	var sim = g[0]
	var b = g[2]
	sim.powerups = true
	var o = SimScript.Orb.new()
	o.kind = P.PU_INF
	o.state = P.ORB_WARN
	o.t = SimScript.PU_WARN - 2
	o.x = b.x + 18.0
	o.y = b.y + 31.0
	sim.orbs.append(o)
	_steps(sim, 6)
	var zapped: bool = b.state == P.F_DEAD
	lines.append("lightning on b: b is %s" % ("knocked out" if zapped else "standing"))
	g = _three(MATES, 80)
	sim = g[0]
	b = g[2]
	sim.walls_start = 1
	_steps(sim, 400)
	var walled: bool = b.state == P.F_DEAD
	lines.append("the purple walls on b: b is %s" % ("knocked out" if walled else "standing"))
	_check("what belongs to nobody (lightning, the purple walls) still hits a team", zapped and walled, "; ".join(lines))

# Four fighters, two a team. When both of one team are out the round is decided, with
# two still alive: the purple walls melt and the ghost cats go. In FREE FOR ALL the
# same two alive mean the round goes on.
func _decided() -> void:
	var lines: Array = []
	var ok := true
	for teams in [{0: 0, 1: 1, 2: 0, 3: 1}, {}]:
		var sim = _game(4, teams)
		sim.walls_start = 1
		for i in 4:
			sim._place(sim.fighters[i], Vector2i([400, 700, 1300, 1500][i], 1020))
		_steps(sim, 200)
		var before: bool = sim.decided()
		sim._send_cats(sim.fighters[0])
		var cats_before: int = sim.cats.size()
		sim._kill(sim.fighters[1], 0, 1)
		var mid: bool = sim.decided()
		sim._kill(sim.fighters[3], 2, 1)
		var after: bool = sim.decided()
		_steps(sim, 3)
		var melting: bool = sim.walls_melt_t >= 0
		if teams.is_empty():
			ok = ok and not before and not mid and not after and not melting and sim.alive_count() == 2
			lines.append("free for all, 2 of 4 alive: decided %s, the walls melt %s" % [after, melting])
		else:
			ok = ok and not before and not mid and after and melting and sim.cats.is_empty() and cats_before == 3 and sim.alive_count() == 2
			lines.append("teams, one out: decided %s; both of a team out (2 alive): decided %s, the walls melt %s, %d of %d cats left" % [mid, after, melting, sim.cats.size(), cats_before])
		sim._kill(sim.fighters[0], 255, 6)
		sim._kill(sim.fighters[2], 255, 6)
		ok = ok and sim.decided() and sim.alive_count() == 0
	lines.append("nobody alive: decided (a draw)")
	_check("a round is decided when one team is left", ok, "; ".join(lines))

# The round is called for team 0 with two of it alive (the server sets safe_team). An
# arrow at one and a bomb under the other: both live, each says PHEW. A winner who gives
# up the seat still goes. A new round makes nobody safe.
func _team_safe() -> void:
	var lines: Array = []
	var sim = _game(4, {0: 0, 1: 1, 2: 0, 3: 1})
	for i in 4:
		sim._place(sim.fighters[i], Vector2i([300, 700, 1300, 1700][i], 1020))
	_steps(sim, 2)
	sim._kill(sim.fighters[1], 0, 1)
	sim._kill(sim.fighters[3], 2, 1)
	sim.safe_team = 0
	var f0 = sim.fighters[0]
	var f2 = sim.fighters[2]
	var ar = SimScript.Arrow.new()      # a foe's arrow, in the air, about to reach seat 0
	ar.id = 800
	ar.owner = 1
	ar.state = P.S_FLY
	ar.t = 20
	ar.x = f0.x + 80.0
	ar.y = f0.y + 28.0
	ar.vx = -16.0
	sim.arrows.append(ar)
	_stuck(sim, 3, f2.x + 18 + 40.0, f2.y + 63.0, P.A_BOMB, 3)
	var evs := _steps(sim, 20)
	var phew0 := _of(evs, P.E_PHEW, 0).size()
	var phew2 := _of(evs, P.E_PHEW, 2).size()
	var ok: bool = f0.state != P.F_DEAD and f2.state != P.F_DEAD and phew0 == 1 and phew2 == 1 and sim.is_safe(f0) and sim.is_safe(f2) \
		and not sim.is_safe(sim.fighters[1])
	lines.append("an arrow at seat 0 and a bomb under seat 2, both winners: both live, PHEW %d and %d" % [phew0, phew2])
	sim.leave(2)
	ok = ok and f2.state == P.F_DEAD and f0.state != P.F_DEAD and sim.safe_team == 0
	lines.append("seat 2 gives up its seat: its fighter goes (state %d), seat 0 stays safe" % f2.state)
	sim.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": false}])
	ok = ok and sim.safe_team == -1 and sim.safe == -1
	lines.append("a new round: safe_team %d" % sim.safe_team)
	_check("every living fighter of the winning team is safe, with a PHEW", ok, "; ".join(lines))

# The snapshot says each fighter's team in two spare bits of flags2, so the page can
# draw the flags on the very tick. In FREE FOR ALL the bits are 0 and the snapshot is
# byte for byte what it was.
func _snapshot_bits() -> void:
	var bits: Array = []
	var sizes: Array = []
	var packets: Array = []
	for teams in [{0: 0, 1: 1, 2: 1}, {}]:
		var sim = _game(3, teams)
		_steps(sim, 2)
		var buf := StreamPeerBuffer.new()
		sim.write_snapshot(buf, [], {})
		var pkt := buf.data_array
		packets.append(pkt)
		sizes.append(pkt.size())
		var row: Array = []
		for i in 3:
			row.append(pkt[20 + i * 14 + 13] & (P.F2_TEAMS | P.F2_TEAM_B))
		bits.append(row)
	var others_same := true      # every byte but the three flags2 bytes is the same in both
	for i in mini(sizes[0], sizes[1]):
		if packets[0][i] != packets[1][i] and not [33, 47, 61].has(i):
			others_same = false
	_check("the snapshot carries each fighter's team; in FREE FOR ALL not one byte changes",
		bits[0] == [P.F2_TEAMS, P.F2_TEAMS | P.F2_TEAM_B, P.F2_TEAMS | P.F2_TEAM_B] and bits[1] == [0, 0, 0] and sizes[0] == sizes[1] and others_same,
		"teams: the team bits of seats 0, 1, 2 are %s (8: on a team, 16: the second team); free for all: %s; both snapshots %d bytes, the other bytes the same: %s" % [
			str(bits[0]), str(bits[1]), sizes[0], others_same])

# ------------------------------------------------------------------ 2. the bots
# A bot with a teammate right beside it and a foe far away picks the foe, as its enemy
# and for its shot. With no foe alive it has no enemy.
func _bots_pick() -> void:
	var lines: Array = []
	var ok := true
	for way in WAYS:
		var g := _three(way[1])
		var sim = g[0]
		var a = g[1]
		a.level = Brain.NORMAL
		sim._place(g[3], Vector2i(700, 1020))     # c, the foe: on a's floor, farther than b
		var near = Brain.nearest_enemy(sim, a)
		var shot: Array = Brain._pick_shot(sim, a)
		var ids := [near.id if near != null else -1, shot[0].id if not shot.is_empty() else -1]
		if way[0] == "teammates":
			ok = ok and ids == [2, 2]
		else:
			ok = ok and ids == [1, 1]
		lines.append("%s: the nearest enemy is seat %d, the shot is for seat %d" % [way[0], ids[0], ids[1]])
	var two = _game(2, {0: 0, 1: 0})
	ok = ok and Brain.nearest_enemy(two, two.fighters[0]) == null and Brain._pick_shot(two, two.fighters[0]).is_empty()
	lines.append("only a teammate alive: no enemy, no shot")
	_check("a bot never picks a teammate as its enemy or its target", ok, "; ".join(lines))

# Whole rounds of bots, 4 against 4, on the Harvest season's arenas with the power-ups
# on. Seats 0 and 1 are people pressed at random in a third of the rounds (their ghosts,
# their aim help, their wild shots). Counted:
#   - arrows a BOT let go while the seat it aimed at (its Mind's target) was a teammate
#     (an arrow may cross a teammate on its way to a foe: those are counted too, they
#     fly through and must do nothing);
#   - every way a fighter was hurt by a teammate, seen from outside the rules: a
#     knockout whose killer is a teammate; frozen or slowed by a teammate's power-up;
#     creamed by a teammate's pie; shoved by a teammate's ghost; a SHIELD used up or an
#     arrow caught from a teammate; knocked back with only a teammate's blast or body
#     to explain it.
# The same count is run in FREE FOR ALL with the same "teams" only in the counting: it
# must find plenty there, or the count would prove nothing.
func _bots_rounds() -> void:
	var tm := _bot_count(bot_rounds, true)
	var ffa := _bot_count(maxi(20, bot_rounds / 5), false)
	_check("%d bot rounds of 4 against 4: no arrow aimed at a teammate, nobody hurt by a teammate" % bot_rounds,
		tm["aimed"] == 0 and tm["hurt"] == 0 and tm["shots"] > 500 and tm["deaths"] > 500 and tm["through"] > 0 and ffa["hurt"] > 20 and ffa["aimed"] > 20,
		"TEAMS: %d rounds, %d arrows by bots (%d aimed at a teammate), %d by the people; %d arrows flew through a teammate's body on their way and did nothing to it; %d knockouts (%d by a teammate); hurt by a teammate %d %s. The same count in FREE FOR ALL, %d rounds: %d arrows aimed at a 'teammate', hurt by one %d %s" % [
			tm["rounds"], tm["shots"], tm["aimed"], tm["people_shots"], tm["through"], tm["deaths"], tm["kinds"].get("knockout", 0), tm["hurt"], str(tm["kinds"]),
			ffa["rounds"], ffa["aimed"], ffa["hurt"], str(ffa["kinds"])])

func _bot_count(rounds: int, teams_on: bool) -> Dictionary:
	var out := {"rounds": 0, "shots": 0, "aimed": 0, "people_shots": 0, "deaths": 0, "hurt": 0, "kinds": {}, "through": 0}
	var side := {}                # the teams, for the counting (in FREE FOR ALL the sim does not get them)
	for i in 8:
		side[i] = i % 2
	var arenas: Array = LevelScript.mix_for("harvest")
	var pad := RandomNumberGenerator.new()
	pad.seed = 4242
	for r in rounds:
		var sim = SimScript.new(0, 24, 6000 + r)
		sim.respawn = false
		sim.powerups = true
		sim.season = "harvest"
		sim.walls_start = 25 * 60
		sim.bot_level = 1 + r % 3
		sim.set_arena(arenas[r % arenas.size()])
		var list: Array = []
		for i in 8:
			list.append({"id": i, "bot": not (i < 2 and r % 3 == 0)})
		sim.start_round(list)
		if teams_on:
			sim.teams = side.duplicate()
		for f in sim.fighters:
			f.points = (f.id % 2) * 2            # one team leads by 2: BIG power-ups come, the SHIELD
		sim.catch_up()
		var held := {}
		var slow_was := {}
		var crossed := {}             # the arrows that were inside a teammate's body while they flew (their ids)
		var t := 0
		var over_at := -1
		while t < 3600 and (over_at < 0 or t - over_at < 90):
			t += 1
			for f in sim.fighters:
				if f.bot:
					continue
				var k: Array = held.get(f.id, [0, 0, 0])
				if k[2] <= 0:
					k = [_pad(pad), pad.randi_range(0, 3599), pad.randi_range(4, 30)]
				k[2] -= 1
				held[f.id] = k
				sim.apply_input(f, k[0], k[1])
			var before := {}                         # each arrow as it was before this tick: id -> [owner, x, y]
			for ar in sim.arrows:
				before[ar.id] = [ar.owner, ar.x, ar.y]
			sim.step()
			var evs: Array = sim.take_events()
			_count_tick(sim, evs, side, before, slow_was, out)
			for ar in sim.arrows:
				if ar.state != P.S_FLY or crossed.has(ar.id):
					continue
				for f in sim.fighters:
					if f.state == P.F_DEAD or not _mate(side, ar.owner, f.id):
						continue
					var ax := SimScript.wrap_d(f.x, ar.x, 1920.0)
					var ay := SimScript.wrap_d(f.y, ar.y, 1080.0)
					if ax >= 0.0 and ax <= SimScript.BODY_W and ay >= 0.0 and ay <= SimScript.BODY_H:
						crossed[ar.id] = true
						out["through"] += 1
						break
			for f in sim.fighters:
				slow_was[f.id] = f.slow_t
			if over_at < 0:
				var teams_left := {}
				for f in sim.fighters:
					if f.state != P.F_DEAD:
						teams_left[side[f.id] if teams_on else f.id] = true
				if teams_left.size() <= 1:
					over_at = t
		out["rounds"] += 1
	return out

func _mate(side: Dictionary, a: int, b: int) -> bool:
	return a != b and side.has(a) and side.has(b) and side[a] == side[b]

func _hurt_by_mate(out: Dictionary, kind: String) -> void:
	out["hurt"] += 1
	out["kinds"][kind] = int(out["kinds"].get(kind, 0)) + 1

# One tick's events, looked at for harm between teammates.
func _count_tick(sim, evs: Array, side: Dictionary, before: Dictionary, slow_was: Dictionary, out: Dictionary) -> void:
	var blasts: Array = []        # [x, y, owner] of this tick
	var pies: Array = []
	for e in evs:
		if e[0] == P.E_EXPLODE:
			blasts.append([e[1], e[2], e[3]])
		elif e[0] == P.E_PIE:
			pies.append([e[1], e[2], e[3]])
	for e in evs:
		var k: int = e[0]
		if k == P.E_SHOOT:
			var f = sim.fighter(e[3])
			if f != null and f.bot and f.mind != null:
				out["shots"] += 1
				if _mate(side, f.id, f.mind.target):
					out["aimed"] += 1
			else:
				out["people_shots"] += 1
		elif k == P.E_KILL:
			out["deaths"] += 1
			if _mate(side, e[3], e[4]):
				_hurt_by_mate(out, "knockout")
		elif k == P.E_FREEZE:
			for f in sim.fighters:
				if f.freeze_t > 0 and f.state != P.F_DEAD and _mate(side, e[3], f.id):
					_hurt_by_mate(out, "frozen")
		elif k == P.E_BOO and e[4] != 255:
			if _mate(side, e[3], e[4]):
				_hurt_by_mate(out, "shoved by a ghost")
		elif k == P.E_PIED:
			var by_foe := false
			var by_mate := false
			for p in pies:
				if _mate(side, p[2], e[3]):
					by_mate = true
				else:
					by_foe = true
			if by_mate and not by_foe:
				_hurt_by_mate(out, "creamed")
		elif k == P.E_SHIELD_POP or k == P.E_CATCH:
			# the arrow that did it: the one that was nearest this spot before the tick
			var best := -1
			var bd := 3600.0
			for id in before:
				var d := Vector2(SimScript.wrap_d(before[id][1], e[1], 1920.0), SimScript.wrap_d(before[id][2], e[2], 1080.0)).length_squared()
				if d < bd:
					bd = d
					best = before[id][0]
			if best >= 0 and _mate(side, best, e[3]):
				_hurt_by_mate(out, "a shield used up" if k == P.E_SHIELD_POP else "an arrow caught")
		elif k == P.E_HURT:
			# a knock: is there a teammate's blast or a teammate's body to explain it, and no foe's (or its own)?
			var f = sim.fighter(e[3])
			var mate_did := false
			var other_did := false
			for b in blasts:
				if Vector2(SimScript.wrap_d(b[0], e[1], 1920.0), SimScript.wrap_d(b[1], e[2], 1080.0)).length() < 520.0:
					if _mate(side, b[2], e[3]):
						mate_did = true
					else:
						other_did = true
			for o in sim.fighters:
				if f == null or o == f:
					continue
				var near: bool = absf(SimScript.wrap_d(o.x, f.x, 1920.0)) < 90.0 and absf(SimScript.wrap_d(o.y, f.y, 1080.0)) < 110.0
				var ghost_near: bool = o.ghost and absf(SimScript.wrap_d(o.gx, e[1], 1920.0)) < 90.0 and absf(SimScript.wrap_d(o.gy, e[2], 1080.0)) < 90.0
				if (near and o.state != P.F_DEAD) or ghost_near:
					if _mate(side, o.id, f.id):
						mate_did = true
					else:
						other_did = true
			if mate_did and not other_did:
				_hurt_by_mate(out, "knocked")
	if sim.rain_t > 0 and sim.rain_owner >= 0:
		for f in sim.fighters:
			if f.state != P.F_DEAD and f.slow_t > int(slow_was.get(f.id, 0)) and _mate(side, sim.rain_owner, f.id):
				_hurt_by_mate(out, "slowed by rain")

func _pad(pad: RandomNumberGenerator) -> int:
	var b := 0
	if pad.randi_range(0, 9) < 4:
		b |= P.B_LEFT if pad.randf() < 0.5 else P.B_RIGHT
	if pad.randf() < 0.3:
		b |= P.B_JUMP
	if pad.randf() < 0.12:
		b |= P.B_DODGE
	if pad.randf() < 0.45:
		b |= P.B_SHOOT
	return b

# ------------------------------------------------------------------ the balance (bots only)
# How TEAMS plays with bots at NORMAL: 4 against 4, 2 against 2, 1 against 3, on the four
# arenas of the Harvest season, power-ups on. A round's length, each team's share, draws.
func _balance() -> void:
	print("⚖️ [Teams] %d rounds a line, the season 'harvest', bots NORMAL, the purple walls at 25 s, power-ups on" % balance)
	var arenas: Array = LevelScript.mix_for("harvest")
	for split in [[4, 4], [2, 2], [1, 3]]:
		var all := {"rounds": 0, "wins": [0, 0], "draws": 0, "secs": [], "left": [], "walls": 0}
		for arena in arenas:
			var r := _balance_run(arena, split)
			_balance_line(LevelScript.name_of(arena), split, r)
			all["rounds"] += r["rounds"]
			all["draws"] += r["draws"]
			all["walls"] += r["walls"]
			all["wins"][0] += r["wins"][0]
			all["wins"][1] += r["wins"][1]
			all["secs"].append_array(r["secs"])
			all["left"].append_array(r["left"])
		_balance_line("ALL FOUR ARENAS", split, all)
		# a match: the first team to the goal (rounds are won by each team at its share; a draw gives no point)
		var p0: float = float(all["wins"][0]) / maxf(1.0, all["rounds"])
		var p1: float = float(all["wins"][1]) / maxf(1.0, all["rounds"])
		var secs: Array = all["secs"]
		var mean := 0.0
		for v in secs:
			mean += v
		mean /= maxf(1.0, secs.size())
		for goal in [3, 5]:
			var m := _match_odds(p0, p1, goal)
			print("⚖️ [Teams]     a match to %d points: %.1f rounds on average, about %.0f s of play (each round also waits 1.5 s before FIGHT and 1.5 s after); the first team wins %.0f%% of matches" % [
				goal, m[1], m[1] * mean, 100.0 * m[0]])

func _balance_run(arena: int, split: Array) -> Dictionary:
	var n: int = split[0] + split[1]
	var sim = SimScript.new(0, 24, 5000 + arena * 10 + n + split[0])
	sim.respawn = false
	sim.powerups = true
	sim.season = "harvest"
	sim.bot_level = 2
	sim.walls_start = 25 * 60
	sim.set_arena(arena)
	var out := {"rounds": 0, "wins": [0, 0], "draws": 0, "secs": [], "left": [], "walls": 0}
	var teams := {}
	for i in n:
		# the server spreads bots one by one to the smaller team: 0, 1, 0, 1... (1 against 3: seat 0 alone)
		teams[i] = (i % 2) if split[0] == split[1] else (0 if i < split[0] else 1)
	for r in balance:
		var list: Array = []
		for i in n:
			list.append({"id": i, "bot": true})
		sim.reset_powers()
		sim.start_round(list)
		sim.teams = teams.duplicate()
		sim.frozen = false
		var t := 0
		var walls := false
		while not sim.decided() and t < 3600:
			t += 1
			sim.step()
			for e in sim.take_events():
				if e[0] == P.E_DEATH and e[4] == 6:
					walls = true
		out["rounds"] += 1
		out["secs"].append(t / 60.0)
		if walls:
			out["walls"] += 1
		if sim.alive_count() == 0 or not sim.decided():
			out["draws"] += 1
		else:
			out["wins"][teams[sim.last_alive().id]] += 1
			out["left"].append(sim.alive_count())
	return out

func _balance_line(name: String, split: Array, r: Dictionary) -> void:
	var secs: Array = r["secs"].duplicate()
	secs.sort()
	var left := 0.0
	for v in r["left"]:
		left += v
	var n: float = maxf(1.0, r["rounds"])
	print("⚖️ [Teams] %-18s %d against %d: a round %.1f s (9 in 10 under %.1f s, the longest %.1f s); the team of %d wins %.1f%%, the team of %d %.1f%%, draws %.1f%%; the winners have %.1f fighters left; the walls knocked someone out in %.0f%% of rounds" % [
		name, split[0], split[1], secs[secs.size() / 2], secs[int(secs.size() * 0.9)], secs[secs.size() - 1],
		split[0], 100.0 * r["wins"][0] / n, split[1], 100.0 * r["wins"][1] / n, 100.0 * r["draws"] / n,
		left / maxf(1.0, r["left"].size()), 100.0 * r["walls"] / n])

# A match to `goal` points when the first team wins a round with chance p0, the second
# with p1 (the rest are draws): [the chance the first team wins, the rounds it takes on
# average]. Worked out exactly, state by state.
func _match_odds(p0: float, p1: float, goal: int) -> Array:
	var pd := 1.0 - p0 - p1
	var win := {}
	var len := {}
	for a in range(goal, -1, -1):
		for b in range(goal, -1, -1):
			var key := Vector2i(a, b)
			if a == goal:
				win[key] = 1.0
				len[key] = 0.0
			elif b == goal:
				win[key] = 0.0
				len[key] = 0.0
			else:
				# a draw stays in this state: divide it out
				win[key] = (p0 * win[Vector2i(a + 1, b)] + p1 * win[Vector2i(a, b + 1)]) / maxf(0.0001, 1.0 - pd)
				len[key] = (1.0 + p0 * len[Vector2i(a + 1, b)] + p1 * len[Vector2i(a, b + 1)]) / maxf(0.0001, 1.0 - pd)
	return [win[Vector2i(0, 0)], len[Vector2i(0, 0)]]

# ------------------------------------------------------------------ helpers (the server)
# The real server (server/game_server.gd) with no sockets and no network thread. This
# probe calls its tick itself (60 ticks are one second of the game, run as fast as they
# go), puts the players' messages into its inbox as the network thread would, and reads
# what it sends out of its outbox.
var srv_n := 0
var next_client := 1
var sent: Array = []              # every JSON message the server sent since the last _take: [client id (0: all), message]
var own_flags := {}               # client id -> the OWN_* flags of its newest T_OWN
var own_pkt := {}                 # client id -> that whole T_OWN packet
var log_dir := ""

func _server(bots: int, teams: bool):
	var srv = ServerScript.new()
	srv_n += 1
	if log_dir == "":
		log_dir = ProjectSettings.globalize_path("res://").path_join("../bench_results/teams_probe").simplify_path()
		DirAccess.make_dir_recursive_absolute(log_dir)
	srv.quiet = true
	srv.sim = SimScript.new(0, 24, 100 + srv_n)
	srv.sim.respawn = false
	srv.sim.powerups = false          # nothing falls from the sky: the probe decides who is knocked out
	srv.sim.walls_start = 0
	srv.season_pick = "harvest"
	srv.sim.season = "harvest"
	srv.arena_pick = 0                # the bench arena
	srv.sim.set_arena(0)
	srv.bots_wanted = bots
	srv.mode_teams = teams
	srv.server_log = FileAccess.open(log_dir.path_join("server_%d.jsonl" % srv_n), FileAccess.WRITE)
	for i in 8:
		var s = ServerScript.Seat.new()
		s.i = i
		srv.seats.append(s)
	srv.started_ms = Time.get_ticks_msec()
	srv.sec_start_ms = srv.started_ms
	sent.clear()
	own_flags.clear()
	own_pkt.clear()
	return srv

func _tick(srv, n: int = 1) -> void:
	for i in n:
		srv._physics_process(0.0)
		for o in srv.net_out:
			if o[1] is String:
				sent.append([o[0], JSON.parse_string(o[1])])
			elif o[1].size() > 11 and o[1][0] == P.T_OWN:
				own_flags[o[0]] = o[1][11]
				own_pkt[o[0]] = o[1]
		srv.net_out.clear()

# A person opens the page, says hello and takes a seat. Returns the client's id.
func _join(srv, name: String) -> int:
	var id := next_client
	next_client += 1
	srv.net_in.append(["open", id, "10.0.0.%d" % id])
	srv.net_in.append(["text", id, JSON.stringify({"kind": "hello", "name": name, "version": P.VERSION, "token": "probe%d" % id})])
	srv.net_in.append(["text", id, JSON.stringify({"kind": "join", "name": name})])
	_tick(srv)
	return id

func _send(srv, id: int, d: Dictionary) -> void:
	srv.net_in.append(["text", id, JSON.stringify(d)])
	_tick(srv)

# The messages of one kind the server sent since the last call (and forget them all).
func _take(kind: String) -> Array:
	var out: Array = []
	for m in sent:
		if typeof(m[1]) == TYPE_DICTIONARY and str(m[1].get("kind", "")) == kind:
			out.append(m[1])
	sent.clear()
	return out

# The newest seats message's teams, seat by seat.
func _seat_teams(msgs: Array) -> Array:
	var out: Array = []
	if msgs.is_empty():
		return out
	for st in msgs[msgs.size() - 1]["seats"]:
		out.append(int(st["team"]))
	return out

func _own_teams(srv) -> Array:
	var out: Array = []
	for s in srv.seats:
		out.append(s.team if s.kind != 0 else -1)
	return out

func _points(srv) -> Array:
	var out: Array = []
	for s in srv.seats:
		out.append(s.points)
	return out

# START from a seated player, then on to FIGHT: 3 s of countdown, 1.5 s of ROUND START.
func _start(srv, id: int) -> void:
	_send(srv, id, {"kind": "start"})
	_tick(srv, ServerScript.COUNTDOWN_TICKS + ServerScript.ROUND_START_TICKS + 2)

# The probe knocks these seats out (by `killer`, with an arrow), all on the same tick,
# and the server takes one tick to see it.
func _knock(srv, victims: Array, killer: int) -> void:
	for v in victims:
		srv.sim._kill(srv.sim.fighter(v), killer, 1)
	_tick(srv)

# From a called round to the next round's FIGHT (or to whatever comes instead).
func _next_fight(srv) -> void:
	_tick(srv, ServerScript.ROUND_END_TICKS + ServerScript.ROUND_START_TICKS + 2)

func _events_with(srv, word: String) -> int:
	var n := 0
	for e in srv.events_ring:
		if word in str(e["text"]):
			n += 1
	return n

func _log_lines(srv, kind: String) -> Array:
	srv.server_log.flush()
	var out: Array = []
	for raw in FileAccess.get_file_as_string(srv.server_log.get_path()).split("\n", false):
		var d = JSON.parse_string(raw)
		if typeof(d) == TYPE_DICTIONARY and str(d.get("kind", "")) == kind:
			out.append(d)
	return out

# ------------------------------------------------------------------ 3. the server
# Who goes to which team: new people to the smaller team, a tap changes sides (only in
# the lobby, only in TEAMS), the bots are spread as evenly as can be.
func _server_picker() -> void:
	var lines: Array = []
	var ok := true
	var srv = _server(0, true)
	var ids: Array = []
	for nm in ["Ava", "Ben", "Cleo", "Dan"]:
		ids.append(_join(srv, nm))
	var got := _own_teams(srv).slice(0, 4)
	var msg_teams := _seat_teams(_take("seats")).slice(0, 4)
	ok = ok and got == [0, 1, 0, 1] and msg_teams == [0, 1, 0, 1]
	lines.append("four people join: teams %s (the seats message says %s)" % [str(got), str(msg_teams)])
	_send(srv, ids[0], {"kind": "team"})
	var after_tap := _own_teams(srv).slice(0, 4)
	var id5 := _join(srv, "Eve")
	var eve: int = srv.seats[4].team
	ok = ok and after_tap == [1, 1, 0, 1] and eve == 0
	lines.append("Ava taps her card: %s; then Eve joins the smaller team: team %d" % [str(after_tap), eve])
	_send(srv, ids[0], {"kind": "start"})
	var counting: bool = srv.phase == P.PH_COUNTDOWN
	_send(srv, ids[1], {"kind": "team"})
	var in_count := _own_teams(srv).slice(0, 5)
	_tick(srv, ServerScript.COUNTDOWN_TICKS + ServerScript.ROUND_START_TICKS + 2)
	_send(srv, ids[2], {"kind": "team"})
	var in_match := _own_teams(srv).slice(0, 5)
	ok = ok and counting and in_count == [1, 1, 0, 1, 0] and in_match == [1, 1, 0, 1, 0] and srv.phase == P.PH_PLAY \
		and srv.sim.teams == {0: 1, 1: 1, 2: 0, 3: 1, 4: 0}
	lines.append("a tap in the countdown and a tap in the match change nothing: %s; the round's teams are the lobby's" % str(in_match))
	srv.free()
	# FREE FOR ALL: a tap does nothing
	srv = _server(0, false)
	var a := _join(srv, "Ava")
	_send(srv, a, {"kind": "team"})
	ok = ok and srv.seats[0].team == 0
	lines.append("FREE FOR ALL: a tap is ignored")
	srv.free()
	# the bots: one person on the first team and 3 bots
	srv = _server(3, true)
	a = _join(srv, "Ava")
	var plan: Array = srv._team_plan()
	var lobby_teams := _seat_teams(_take("seats"))
	_start(srv, a)
	var round_teams: Dictionary = srv.sim.teams
	ok = ok and plan.slice(0, 4) == [0, 1, 1, 0] and lobby_teams == plan and round_teams == {0: 0, 1: 1, 2: 1, 3: 0}
	lines.append("1 person + 3 bots: the lobby shows %s, the round has %s (2 against 2)" % [str(lobby_teams.slice(0, 4)), str(round_teams)])
	srv.free()
	# every mix of people and bots: the teams are as even as they can be
	var worst := 0
	var tried := 0
	for p0 in 5:
		for p1 in 5:
			for bots in 8:
				if p0 + p1 > 8 or p0 + p1 + bots < 2:
					continue
				srv = _server(bots, true)
				for i in p0 + p1:
					srv.seats[i].kind = 1
					srv.seats[i].team = 0 if i < p0 else 1
				var pl: Array = srv._team_plan()
				var n0: int = pl.count(0)
				var n1: int = pl.count(1)
				var b_now: int = mini(bots, 8 - p0 - p1)
				var best: int = maxi(absi(p0 - p1) - b_now, (p0 + p1 + b_now) % 2)
				tried += 1
				if absi(n0 - n1) != best or n0 + n1 != p0 + p1 + b_now:
					worst += 1
					lines.append("NOT EVEN: %d and %d people, %d bots -> %d against %d" % [p0, p1, bots, n0, n1])
				srv.free()
	ok = ok and worst == 0
	lines.append("%d mixes of people (0 to 4 a team) and bots (0 to 7): the bots always make the teams as even as they can be" % tried)
	_check("the team picker: new people to the smaller team, a tap changes sides in the lobby, bots are spread evenly", ok, "; ".join(lines))

# A match in TEAMS needs a fighter on each team. START says why not.
func _server_start_needs_both() -> void:
	var lines: Array = []
	var srv = _server(0, true)
	var a := _join(srv, "Ava")
	var b := _join(srv, "Ben")
	_send(srv, b, {"kind": "team"})            # both on the first team now
	_take("seats")
	_send(srv, a, {"kind": "start"})
	var notes := _take("note")
	var said: bool = notes.size() == 1 and str(notes[0]["text"]) == ServerScript.TEAMS_NEED
	var host: Array = srv._host_cmd("start", {})
	var ok: bool = srv.phase == P.PH_LOBBY and said and host[0] == false and str(host[1]) == ServerScript.TEAMS_NEED and not srv._teams_ok()
	lines.append("2 people on one team, no bots: START is refused (%s); the host's START too" % ("the note says why" if said else "NO NOTE"))
	_send(srv, a, {"kind": "bots", "n": 1})    # a bot will fill the empty team
	var seats_ok := _take("seats")
	_send(srv, a, {"kind": "start"})
	var counting: bool = srv.phase == P.PH_COUNTDOWN
	ok = ok and counting and bool(seats_ok[seats_ok.size() - 1]["teams_ok"])
	lines.append("with a bot: START counts down (%s)" % counting)
	_send(srv, a, {"kind": "bots", "n": 0})    # the bot goes in the countdown: the team is empty again
	_tick(srv, 2)
	var stopped := _take("note")
	ok = ok and srv.phase == P.PH_LOBBY and stopped.size() == 1 and str(stopped[0]["text"]) == ServerScript.TEAMS_NEED
	lines.append("the bot is taken away in the countdown: back to the lobby, with the note")
	srv.free()
	_check("a TEAMS match starts only with a fighter on each team, and says why not", ok, "; ".join(lines))

# Ava and Cleo against Ben and Dan. Ben and Dan are knocked out: the round is called for
# TEAM TURKEY with both of it alive; both are safe (an arrow, a bomb: PHEW); 1.5 s later
# the team has ONE point, shown on both; the log line says the mode, the teams and who won.
func _server_round_and_point() -> void:
	var lines: Array = []
	var srv = _server(0, true)
	var ids: Array = []
	for nm in ["Ava", "Ben", "Cleo", "Dan"]:
		ids.append(_join(srv, nm))
	_start(srv, ids[0])
	_take("round_end")
	_knock(srv, [1], 0)
	var one_out: bool = srv.phase == P.PH_PLAY
	_knock(srv, [3], 2)
	var ends := _take("round_end")
	var e: Dictionary = ends[0] if ends.size() == 1 else {}
	var ok: bool = one_out and srv.phase == P.PH_ROUND_END and not e.is_empty() and not bool(e["draw"]) and str(e["name"]) == "TEAM TURKEY" \
		and int(e["team"]) == 0 and e["members"] == [0.0, 2.0] and [0, 2].has(int(e["winner"])) and srv.sim.safe_team == 0 and srv.sim.safe == -1
	lines.append("one of TEAM PIE out: the round goes on (%s). Both out: round_end says '%s WINS', team %s, members %s, 2 alive" % [
		one_out, e.get("name", "?"), e.get("team", "?"), str(e.get("members", "?"))])
	# both winners are hit after the call
	var f0 = srv.sim.fighter(0)
	var f2 = srv.sim.fighter(2)
	var ar = SimScript.Arrow.new()
	ar.id = 800
	ar.owner = 1
	ar.state = P.S_FLY
	ar.t = 20
	ar.x = f0.x + 80.0
	ar.y = f0.y + 28.0
	ar.vx = -16.0
	srv.sim.arrows.append(ar)
	_stuck(srv.sim, 3, f2.x + 18 + 40.0, f2.y + 63.0, P.A_BOMB, 3)
	_tick(srv, 20)
	var phews := _log_lines(srv, "phew")
	var phew_seats: Array = []
	for p in phews:
		phew_seats.append(int(p["seat"]))
	phew_seats.sort()
	var safe_flags := [(int(own_flags.get(ids[0], 0)) & P.OWN_SAFE) != 0, (int(own_flags.get(ids[1], 0)) & P.OWN_SAFE) != 0,
		(int(own_flags.get(ids[2], 0)) & P.OWN_SAFE) != 0, (int(own_flags.get(ids[3], 0)) & P.OWN_SAFE) != 0]
	ok = ok and f0.state != P.F_DEAD and f2.state != P.F_DEAD and phew_seats == [0, 2] and safe_flags == [true, false, true, false]
	lines.append("an arrow at Ava and a bomb under Cleo after the call: both live, PHEW for seats %s; the pages are told 'you are safe': %s" % [str(phew_seats), str(safe_flags)])
	var before := _points(srv).slice(0, 4)
	_next_fight(srv)
	var after := _points(srv).slice(0, 4)
	var in_sim := [srv.sim.fighter(0).points, srv.sim.fighter(1).points, srv.sim.fighter(2).points, srv.sim.fighter(3).points]
	ok = ok and before == [0, 0, 0, 0] and after == [1, 0, 1, 0] and in_sim == after and srv.team_points == [1, 0] and srv.round_no == 2 \
		and srv.phase == P.PH_PLAY and srv.sim.safe_team == -1
	lines.append("1.5 s later: the teams' points %s, the seats show %s (the snapshot too: %s), round %d is on, nobody is safe" % [
		str(srv.team_points), str(after), str(in_sim), srv.round_no])
	var rl: Array = _log_lines(srv, "round")
	var r0: Dictionary = rl[0] if rl.size() > 0 else {}
	ok = ok and str(r0.get("mode", "")) == "teams" and r0.get("teams", []) == [0.0, 1.0, 0.0, 1.0, -1.0, -1.0, -1.0, -1.0] and int(r0.get("team_won", -9)) == 0 \
		and r0.get("team_names", []) == ["TEAM TURKEY", "TEAM PIE"]
	lines.append("the round's log line: mode %s, teams %s, team_won %s" % [r0.get("mode", "?"), str(r0.get("teams", "?")), str(r0.get("team_won", "?"))])
	var wins := [int(srv.stats["Ava"]["round_wins"]), int(srv.stats["Ben"]["round_wins"]), int(srv.stats["Cleo"]["round_wins"]), int(srv.stats["Dan"]["round_wins"])]
	ok = ok and wins == [1, 0, 1, 0]
	lines.append("tonight's numbers: rounds won %s" % str(wins))
	srv.free()
	_check("a round goes to the last team standing: one point for the team, every living winner safe", ok, "; ".join(lines))

# Both teams out on the same tick: a draw, no point. And 60 s with both teams still
# standing: a draw too.
func _server_draws() -> void:
	var lines: Array = []
	var srv = _server(0, true)
	var ids: Array = []
	for nm in ["Ava", "Ben", "Cleo", "Dan"]:
		ids.append(_join(srv, nm))
	_start(srv, ids[0])
	_take("round_end")
	_knock(srv, [0, 1, 2, 3], 255)
	var ends := _take("round_end")
	var ok: bool = ends.size() == 1 and bool(ends[0]["draw"]) and not ends[0].has("team") and srv.sim.safe_team == -1
	_next_fight(srv)
	ok = ok and srv.team_points == [0, 0] and _points(srv).slice(0, 4) == [0, 0, 0, 0] and srv.round_no == 2
	lines.append("everyone out on one tick: a draw, the points stay %s" % str(srv.team_points))
	_take("round_end")
	_knock(srv, [0, 3], 255)             # one of each team out: two foes are left, and they only stand there
	_tick(srv, ServerScript.ROUND_MAX_TICKS)
	ends = _take("round_end")
	ok = ok and ends.size() == 1 and bool(ends[0]["draw"]) and srv.team_points == [0, 0]
	var rl: Array = _log_lines(srv, "round")
	ok = ok and rl.size() == 2 and int(rl[1]["team_won"]) == -1 and bool(rl[1]["draw"])
	lines.append("60 s with a fighter of each team still up: a draw (the log: team_won %s)" % str(rl[1]["team_won"] if rl.size() > 1 else "?"))
	srv.free()
	_check("both teams gone on the same tick is a draw; so is a round nobody ends", ok, "; ".join(lines))

# A whole match: Ava and Cleo (TEAM TURKEY) against Ben and a bot (TEAM PIE), first team
# to 5. Cleo makes every knockout. At 2 to 0 the people of the team behind start with a
# SHIELD (not its bot, not the leaders). The match ends for the team: its name, its
# members, Cleo as its best player; a crown for both.
func _server_match() -> void:
	var lines: Array = []
	var srv = _server(1, true)
	var ids: Array = []
	for nm in ["Ava", "Ben", "Cleo"]:
		ids.append(_join(srv, nm))
	_start(srv, ids[0])
	var teams: Dictionary = srv.sim.teams.duplicate()
	var ok: bool = teams == {0: 0, 1: 1, 2: 0, 3: 1} and srv.goal == 5 and srv.match_teams
	lines.append("Ava, Ben, Cleo and one bot: teams %s, first to %d" % [str(teams), srv.goal])
	var shields: Array = []
	var rounds := 0
	_take("match_end")
	while srv.phase == P.PH_PLAY and rounds < 9:
		rounds += 1
		if srv.team_points == [2, 0]:
			shields = [srv.sim.fighter(0).shield, srv.sim.fighter(1).shield, srv.sim.fighter(2).shield, srv.sim.fighter(3).shield]
		_knock(srv, [1, 3], 2)
		_next_fight(srv)
	var said := _events_with(srv, "starts with a SHIELD")
	ok = ok and shields == [0, 1, 0, 0] and said >= 1
	lines.append("at 2 to 0 the round starts with SHIELDs %s (Ben is behind; the bot gets none)" % str(shields))
	var ends := _take("match_end")
	var m: Dictionary = ends[0] if ends.size() == 1 else {}
	var crowns := [srv.seats[0].crowns, srv.seats[1].crowns, srv.seats[2].crowns, srv.seats[3].crowns]
	ok = ok and rounds == 5 and srv.phase == P.PH_MATCH_END and not m.is_empty() and str(m["name"]) == "TEAM TURKEY" and int(m["team"]) == 0 \
		and int(m["winner"]) == 2 and str(m["best"]) == "Cleo" and m["members"] == [0.0, 2.0] and crowns == [1, 0, 1, 0] and srv.team_points == [5, 0] \
		and _points(srv).slice(0, 4) == [5, 0, 5, 0]
	lines.append("after %d rounds: match_end says '%s', members %s, the best player seat %s '%s'; crowns %s; points %s" % [
		rounds, m.get("name", "?"), str(m.get("members", "?")), str(m.get("winner", "?")), m.get("best", "?"), str(crowns), str(_points(srv).slice(0, 4))])
	var ml: Array = _log_lines(srv, "match")
	ok = ok and ml.size() == 1 and str(ml[0]["mode"]) == "teams" and int(ml[0]["team_won"]) == 0
	_tick(srv, int(srv.phase_t) + 2)
	ok = ok and srv.phase == P.PH_LOBBY and not srv.match_teams and srv.team_points == [0, 0] and srv.sim.teams.is_empty() and srv.mode_teams
	lines.append("then the lobby: no team points left, the MODE is still TEAMS")
	srv.free()
	_check("the match: first team to the goal, the catch-up SHIELD for the people of the team behind", ok, "; ".join(lines))

# People who leave. The winning team's last one standing leaves before the point: the
# team still gets it (a teammate is still seated). Everyone of the winning team leaves:
# no point, and with a team empty the match stops. Someone who sits down in the middle
# of a match joins the smaller team and shows that team's points at once.
func _server_leavers() -> void:
	var lines: Array = []
	var srv = _server(0, true)
	var ids: Array = []
	for nm in ["Ava", "Ben", "Cleo", "Dan"]:
		ids.append(_join(srv, nm))
	_start(srv, ids[0])
	_knock(srv, [1, 2, 3], 0)                 # Ava alone wins it for TEAM TURKEY; Cleo is out but seated
	_send(srv, ids[0], {"kind": "leave"})    # and leaves before the point
	var gone: bool = srv.sim.fighter(0).state == P.F_DEAD and srv.seats[0].kind == 0
	_next_fight(srv)
	var ok: bool = gone and srv.team_points == [1, 0] and srv.seats[2].points == 1 and srv.seats[0].points == 0 and srv.round_no == 2
	lines.append("the last winner standing leaves before the point: her fighter goes, the team still gets it (points %s, Cleo shows %d)" % [str(srv.team_points), srv.seats[2].points])
	# Eve sits down in the middle of round 2: the teams are 1 (Cleo) and 2 (Ben, Dan)
	var eve := _join(srv, "Eve")
	var es = srv.seats[srv.conns[eve].seat]
	ok = ok and es.team == 0 and es.points == 1 and not es.in_round
	lines.append("Eve sits down in round 2: team %d (the smaller one), she shows its %d point" % [es.team, es.points])
	_knock(srv, [1, 3], 2)
	_next_fight(srv)
	ok = ok and srv.team_points == [2, 0] and es.points == 2 and es.in_round and int(srv.sim.teams.get(es.i, -1)) == 0
	lines.append("round 3: she fights for it, the team has %d" % srv.team_points[0])
	# round 3: TEAM TURKEY (Cleo, Eve) wins, then both leave before the point
	_take("note")
	_knock(srv, [1, 3], 2)
	_send(srv, ids[2], {"kind": "leave"})
	_send(srv, eve, {"kind": "leave"})
	_tick(srv, ServerScript.ROUND_END_TICKS + 2)
	var notes := _take("note")
	var why := str(notes[notes.size() - 1]["text"]) if notes.size() > 0 else ""
	ok = ok and srv.phase == P.PH_LOBBY and _events_with(srv, "no point: nobody of TEAM TURKEY is left") == 1 and why == "The match stopped: a team has no fighter left."
	lines.append("the whole winning team leaves before the point: no point, and the match stops ('%s')" % why)
	srv.free()
	_check("people who leave: the point stays with the team, an empty team stops the match, a late joiner gets the smaller team", ok, "; ".join(lines))

# The MODE is fixed for a match. The host turns TEAMS on in the middle of a FREE FOR ALL
# match: that match stays FREE FOR ALL to its end, the next one is TEAMS. A player's own
# MODE change is only taken in the lobby. The lobby's settings file keeps the mode.
func _server_mode_in_a_match() -> void:
	var lines: Array = []
	var srv = _server(0, false)
	srv.lobby_path = log_dir.path_join("lobby_settings.json")
	var ids: Array = []
	for nm in ["Ava", "Ben", "Cleo"]:
		ids.append(_join(srv, nm))
	_start(srv, ids[0])
	_take("seats")
	var r: Array = srv._host_cmd("mode", {"pick": "teams"})
	_tick(srv)
	var seats := _take("seats")
	var sm: Dictionary = seats[seats.size() - 1] if seats.size() > 0 else {}
	var ok: bool = r[0] == true and srv.mode_teams and not srv.match_teams and srv.sim.teams.is_empty() and str(sm.get("mode", "")) == "ffa" \
		and str(sm.get("mode_pick", "")) == "teams" and _seat_teams(seats) == [-1, -1, -1, -1, -1, -1, -1, -1]
	lines.append("the host picks TEAMS in a FREE FOR ALL match: '%s'; the page is told mode %s, pick %s" % [r[1], sm.get("mode", "?"), sm.get("mode_pick", "?")])
	_take("round_end")
	_knock(srv, [1], 0)
	var still: bool = srv.phase == P.PH_PLAY        # 2 of 3 alive: no team has won anything
	_knock(srv, [2], 0)
	var ends := _take("round_end")
	ok = ok and still and ends.size() == 1 and not ends[0].has("team") and str(ends[0]["name"]) == "Ava" and srv.sim.safe == 0 and srv.sim.safe_team == -1
	_next_fight(srv)
	ok = ok and _points(srv).slice(0, 3) == [1, 0, 0]
	lines.append("that match plays on as FREE FOR ALL: 'Ava' wins the round alone, points %s" % str(_points(srv).slice(0, 3)))
	_send(srv, ids[1], {"kind": "mode", "pick": "ffa"})
	ok = ok and srv.mode_teams
	lines.append("a player's MODE change in a match is not taken")
	srv._host_cmd("stop", {})
	_tick(srv)
	_take("seats")
	_send(srv, ids[1], {"kind": "mode", "pick": "ffa"})
	var back_ffa: bool = not srv.mode_teams
	_send(srv, ids[1], {"kind": "mode", "pick": "teams"})
	_send(srv, ids[1], {"kind": "mode", "pick": "pancakes"})
	seats = _take("seats")
	sm = seats[seats.size() - 1] if seats.size() > 0 else {}
	ok = ok and back_ffa and srv.mode_teams and str(sm.get("mode", "")) == "teams" and _seat_teams(seats).slice(0, 3) == [0, 1, 0]
	lines.append("in the lobby a player turns it off and on again (a made-up mode is ignored): mode %s, teams %s" % [sm.get("mode", "?"), str(_seat_teams(seats).slice(0, 3))])
	_start(srv, ids[0])
	ok = ok and srv.match_teams and srv.sim.teams == {0: 0, 1: 1, 2: 0}
	lines.append("the next match is TEAMS: %s" % str(srv.sim.teams))
	srv.free()
	# the settings file: a new server reads the mode; an option on the command line wins
	var s2 = _server(0, false)
	s2._load_lobby(log_dir, {})
	var read_back: bool = s2.mode_teams
	s2.free()
	var s3 = _server(0, false)
	s3._load_lobby(log_dir, {"mode": "ffa"})
	ok = ok and read_back and not s3.mode_teams
	s3.free()
	lines.append("lobby_settings.json keeps it: a new server comes up in TEAMS (%s); with --mode ffa it does not" % read_back)
	DirAccess.remove_absolute(log_dir.path_join("lobby_settings.json"))
	_check("the MODE: fixed for a match, changed in the lobby or by the host, kept over a restart", ok, "; ".join(lines))

# FREE FOR ALL on the same server: no teams anywhere, the old messages, the old points.
func _server_ffa_is_ffa() -> void:
	var lines: Array = []
	var srv = _server(0, false)
	var ids: Array = []
	for nm in ["Ava", "Ben", "Cleo"]:
		ids.append(_join(srv, nm))
	var seats := _take("seats")
	var sm: Dictionary = seats[seats.size() - 1]
	var ok: bool = str(sm["mode"]) == "ffa" and _seat_teams(seats) == [-1, -1, -1, -1, -1, -1, -1, -1] and bool(sm["teams_ok"])
	_start(srv, ids[0])
	var buf := StreamPeerBuffer.new()
	srv.sim.write_snapshot(buf, [], srv._head())
	var bits := 0
	for i in 3:
		bits |= buf.data_array[20 + i * 14 + 13] & (P.F2_TEAMS | P.F2_TEAM_B)
	ok = ok and srv.goal == 4 and srv.sim.teams.is_empty() and bits == 0 and not srv.match_teams
	lines.append("3 people, FREE FOR ALL: the page is told mode %s and no teams; first to %d (the old rule); no team bits in the snapshot" % [sm["mode"], srv.goal])
	_take("round_end")
	_knock(srv, [0, 1], 2)
	var ends := _take("round_end")
	var e: Dictionary = ends[0] if ends.size() == 1 else {}
	ok = ok and not e.is_empty() and not e.has("team") and not e.has("members") and str(e["name"]) == "Cleo" and int(e["winner"]) == 2 and srv.sim.safe == 2 and srv.sim.safe_team == -1
	_next_fight(srv)
	var rl: Array = _log_lines(srv, "round")
	ok = ok and _points(srv).slice(0, 3) == [0, 0, 1] and str(rl[0]["mode"]) == "ffa" and not rl[0].has("teams")
	lines.append("round_end names 'Cleo' (no team fields); points %s; the log line says mode %s" % [str(_points(srv).slice(0, 3)), rl[0]["mode"]])
	srv.free()
	_check("FREE FOR ALL on the new server is the old game: no teams, the old messages and points", ok, "; ".join(lines))

# ------------------------------------------------------------------ 4. the page's copies
# The page flies every arrow on to your own tick in a copy of the sim (client/present.gd),
# where the fighters stand as stoppers. A teammate's arrow must not stop at a teammate
# there either. One arrow, shot by seat 0, about to cross seat 1, flown 12 ticks on: with
# the snapshot's team bits it is far behind seat 1; without them it waits at seat 1.
func _page_arrows() -> void:
	var lines: Array = []
	var ok := true
	for with_teams in [true, false]:
		var present = Present.new()
		var f2 := P.F2_TEAMS if with_teams else 0
		var snap := {"tick": 1000, "arena": 0,
			"fighters": [
				{"id": 0, "state": P.F_NORMAL, "x": 222.0, "y": 957.0, "vx": 0, "vy": 0, "flags2": f2},
				{"id": 1, "state": P.F_NORMAL, "x": 522.0, "y": 957.0, "vx": 0, "vy": 0, "flags2": f2},
				{"id": 2, "state": P.F_NORMAL, "x": 1662.0, "y": 957.0, "vx": 0, "vy": 0, "flags2": f2 | (P.F2_TEAM_B if with_teams else 0)}],
			"arrows": {7: {"kind": P.A_NORMAL, "state": P.S_FLY, "x": 430.0, "y": 975.0, "vx": 16.0, "vy": 0.0, "ang": 0.0, "age": 12, "owner": 0, "big": false}}}
		var out: Dictionary = present.arrows_at(snap, 1012, null, -1, [], [], 0.0)
		var x: float = out[7]["x"] if out.has(7) else -1.0
		if with_teams:
			ok = ok and x > 522.0 + 36.0 + 40.0 and present.sim.teams == {0: 0, 1: 0, 2: 1}
			lines.append("with the team bits: after 12 ticks the arrow is at x %d, behind the teammate (who ends at x 558)" % int(x))
		else:
			ok = ok and x < 522.0 + 36.0 and present.sim.teams.is_empty()
			lines.append("without them (FREE FOR ALL): it waits at the fighter, x %d" % int(x))
	_check("the page's own arrows fly through teammates too (client/present.gd)", ok, "; ".join(lines))

# The page's copy of your fighter (client/predict.gd) hears "you are safe" in each T_OWN.
# In TEAMS the server says it to every living fighter of the winning team: here to both
# winners' pages, and each page's copy then takes the same rule (sim.safe = its seat).
func _page_safe() -> void:
	var srv = _server(0, true)
	var ids: Array = []
	for nm in ["Ava", "Ben", "Cleo", "Dan"]:
		ids.append(_join(srv, nm))
	_start(srv, ids[0])
	_knock(srv, [1, 3], 2)
	_tick(srv, 4)
	var got: Array = []
	for k in [0, 2, 1]:
		var pkt: PackedByteArray = own_pkt.get(ids[k], PackedByteArray())
		var pred = Predict.new()
		pred.seat = k
		if pkt.size() > 16:
			pred.reconcile({"tick": pkt.decode_u32(1), "flags": pkt[11], "moves_from": pkt.decode_u32(12), "pkt": pkt, "at": 16, "arena": 0})
		got.append(pred.sim.safe)
	srv.free()
	_check("each living winner's page is told it is safe, and its copy follows", got == [0, 2, -1],
		"the copies' safe seat after the round is called: Ava's page %d, Cleo's page %d (both winners), Ben's page %d (out: -1)" % [got[0], got[1], got[2]])

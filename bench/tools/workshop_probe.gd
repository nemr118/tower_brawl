# SANTA'S WORKSHOP's probe (sim/workshop.gd, layout 8): the toy train's rules, offline.
#   godot --headless --path bench --script res://tools/workshop_probe.gd -- [--rounds=N] [--seed=N] [--level=easy|normal|hard]
# Checks: the track is clear from one tunnel mouth to the other, with a low ledge near
# every part of it (a slow player gets up on one in time from anywhere) and no spawn
# spot on it; the whistle comes WARN_T ticks before every
# train, from either side; a fighter on the track is knocked out (cause 13) the tick the
# train reaches it; a held jump clears it (how early and how late the press may be); a
# fighter on a low ledge is safe, and the train's roof holds nobody; a dodge and a SHIELD
# do not save (the furnace's rule); the round's winner is safe (E_PHEW, not thrown), a
# winning team too; a costume is knocked down by one train and ended by the next; the
# page's own copy (sim.predicting) never runs the train, and a lone fighter never sees
# one; the train bumps a fallen body and knocks arrows about; flee() tells a bot what to
# do, and bots caught on the track at the whistle get out alive; the snapshot part reads
# back the same through the page's reader (client/net.gd), and on_tick() rolls it on.
# Then --rounds rounds (200 by default) of 8 bots as arena_probe.gd plays them (one life,
# the purple walls at 25 s): how they die (the train's share must stay under 8%), stuck
# bots (1 in 800 at most), and the timing rules (the first whistle 5 s or more after
# FIGHT, every train WARN_T after its whistle). Exits 1 when a check fails.
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const Shop = preload("res://sim/workshop.gd")
const Brain = preload("res://sim/brain.gd")
const Net = preload("res://client/net.gd")

const ARENA := 8
const FLOOR := Shop.FLOOR_Y
var fails := 0

func _init() -> void:
	var rounds := 200
	var seed_value := 8008
	var level := Brain.NORMAL
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("--level="):
			level = maxi(1, Brain.NAMES.find(a.get_slice("=", 1).to_upper()))
	var lv = LevelScript.new(ARENA)
	print("== %s (layout %d, theme %s)" % [lv.name, ARENA, lv.theme])
	_check("the arena is SANTA'S WORKSHOP with the workshop theme, in the lobby's list", lv.name == "SANTA'S WORKSHOP" \
		and lv.theme == "workshop" and LevelScript.PLAY.has(ARENA), "theme %s, PLAY %s" % [lv.theme, str(LevelScript.PLAY)])
	_places(lv)
	_warns_first()
	_knocks_out()
	_jump_clears()
	_ledge_safe()
	_roof()
	_dodge_shield()
	_winner_safe()
	_costume()
	_predicting()
	_lone_fighter()
	_bodies_arrows()
	_flee()
	_snapshot()
	if rounds > 0:
		_rounds(rounds, seed_value, level)
	if fails == 0:
		print("✅ workshop_probe: every check passed")
		quit(0)
	else:
		printerr("❌ workshop_probe: %d check(s) failed" % fails)
		quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %s: %s" % ["PASS" if ok else "FAIL", name, detail])

# A sim on the workshop with n fighters (seat 0 a person, the rest bots), playing. The
# bots stand still unless a test lets them play. Everyone starts up on the star, out of
# the way: a test puts its own fighters where it wants them.
func _game(n: int, seed_value: int = 7):
	var sim = SimScript.new(0, 24, seed_value)
	sim.set_arena(ARENA)
	sim.respawn = false
	sim.power_arrows = false
	var seats: Array = []
	for i in n:
		seats.append({"id": i, "bot": i > 0})
	sim.start_round(seats)
	sim.frozen = false
	for i in sim.fighters.size():
		sim.fighters[i].wait_t = 99999
		_put(sim, sim.fighters[i], 960, 420)
	return sim

# Puts f with its feet at (x, feet), standing still.
func _put(sim, f, x: float, feet: float) -> void:
	sim._place(f, Vector2i(int(x), int(feet)))

# The whistle starts now, for a train heading d (1 right, -1 left).
func _force(sim, d: int) -> void:
	var hz = sim.hazards
	hz.tick = 2                    # past the round's first tick (its own pick of the first whistle)
	hz.wait = 99999
	hz.dir = d
	hz._to(Shop.WARN)

# The train is n ticks into its run now, heading d.
func _running(sim, d: int, n: int) -> void:
	var hz = sim.hazards
	hz.tick = 2
	hz.wait = 99999
	hz.dir = d
	hz._to(Shop.RUN)
	hz.t = n
	hz.hit.clear()
	hz.bumped.clear()
	hz.knocked.clear()

# ------------------------------------------------------------------ where things are
func _places(lv) -> void:
	var odd: Array = []
	var top_row: int = (FLOOR - Shop.TRAIN_H) / 30
	for cx in lv.COLS:
		if lv.cell(cx, FLOOR / 30) == LevelScript.EMPTY:
			odd.append("no floor under the track at col %d" % cx)
		for cy in range(FLOOR / 30 - 3, FLOOR / 30):      # the three rows a body walks in (the train's box is the lower two)
			if lv.cell(cx, cy) == LevelScript.SOLID:
				odd.append("a block on the track at col %d row %d" % [cx, cy])
	_check("the track is clear from edge to edge (a body can walk it all, both tunnels open) with floor under all of it",
		odd.is_empty(), "64 cols, the train's box rows %d-%d, the tunnels rows %d-%d" % [top_row, FLOOR / 30 - 1, FLOOR / 30 - 3, FLOOR / 30 - 1] \
		if odd.is_empty() else ", ".join(odd.slice(0, 6)))
	# a low ledge near every part of the floor: how far the body must walk to stand under one
	var hz = Shop.new(lv)
	var worst := 0.0
	var worst_x := 0
	var under := 0
	for x in range(0, Shop.W, 6):
		var d := 9999.0
		for step in range(0, 80):
			if hz._under_perch(fposmod(x + step * 6.0, float(Shop.W))) or hz._under_perch(fposmod(x - step * 6.0, float(Shop.W))):
				d = step * 6.0
				break
		if d == 0.0:
			under += 1
		if d > worst:
			worst = d
			worst_x = x
	_check("a low ledge (90 or 120 px up, a jump straight up lands on it) within 150 px of every place on the floor", worst <= 150.0,
		"the farthest: %d px (a body at x %d); %d%% of the floor is right under one" % [worst, worst_x, roundi(100.0 * under / (Shop.W / 6.0))])
	# a slow player anywhere on the floor: 0.75 s to notice the whistle, a walk to the nearest
	# low ledge, a jump up (22 ticks to stand on it). The ticks to spare before the train's
	# front is there, the worst place and way
	var spare := 99999.0
	var spare_at := ""
	for x in range(0, Shop.W - 36, 6):
		var d := 9999.0
		for step in range(0, 80):
			if hz._under_perch(fposmod(x + step * 6.0, float(Shop.W))) or hz._under_perch(fposmod(x - step * 6.0, float(Shop.W))):
				d = step * 6.0
				break
		var need: float = 45.0 + d / Shop.WALK + 22.0
		for way in [1, -1]:
			var have: float = Shop.WARN_T + (x if way > 0 else Shop.W - x - 36.0) / Shop.SPEED
			if have - need < spare:
				spare = have - need
				spare_at = "x %d, the train from the %s" % [x, "left" if way > 0 else "right"]
	_check("a slow player (0.75 s to notice the whistle, then a walk and one jump) is on a low ledge before the train, from anywhere on the floor",
		spare >= 15.0, "the fewest ticks to spare: %d (%.2f s), at %s" % [spare, spare / 60.0, spare_at])
	var nearest := INF
	var bad: Array = []
	var track := Rect2(0, FLOOR - Shop.TRAIN_H, Shop.W, Shop.TRAIN_H)
	for s in lv.spawns:
		var body := Rect2(s.x - 18, s.y - 63, 36, 63)
		var gap := maxf(0.0, maxf(track.position.y - body.end.y, body.position.y - track.end.y))
		nearest = minf(nearest, gap)
		if gap < 60.0:
			bad.append("spawn (%d, %d) is %d px over the train" % [s.x, s.y, gap])
	_check("no spawn spot within 60 px of the train's box", bad.is_empty(),
		"the nearest is %d px over it" % nearest if bad.is_empty() else ", ".join(bad))

# ------------------------------------------------------------------ the whistle
func _warns_first() -> void:
	var lines: Array = []
	var ok := true
	for d in [1, -1]:
		var sim = _game(2)
		_force(sim, d)
		var warn_at := 0               # the whistle's event comes with the forced start (tick 0)
		var go_at := -1
		var first_box := -1
		var gone_at := -1
		var mouth := -1
		for t in Shop.WARN_T + Shop.RUN_T + 20:
			sim.step()
			for e in sim.take_events():
				if e[0] == P.E_TRAIN:
					go_at = t + 1
					mouth = e[1]
					ok = ok and e[3] == (1 if d > 0 else 0)
			if sim.hazards.box().size.x > 0.0 and first_box < 0:
				first_box = t + 1
			if first_box > 0 and gone_at < 0 and sim.hazards.phase == Shop.IDLE:
				gone_at = t + 1
		var good: bool = go_at == Shop.WARN_T and first_box >= go_at and mouth == Shop.mouth_x(d) and gone_at == Shop.WARN_T + Shop.RUN_T
		ok = ok and good
		lines.append("to the %s: whistle on tick %d, out of the mouth at x %d on tick %d (%.2f s later), gone on tick %d (%.2f s on the floor)" % [
			"right" if d > 0 else "left", warn_at, mouth, go_at, go_at / 60.0, gone_at, (gone_at - go_at) / 60.0])
	_check("the whistle comes %d ticks (%.2f s) before the train, from either side; the train is gone %.2f s later" % [Shop.WARN_T,
		Shop.WARN_T / 60.0, Shop.RUN_T / 60.0], ok and Shop.WARN_T >= 90, "; ".join(lines))
	# a round's own timing: the whistle's event comes first
	var sim2 = _game(2, 31)
	var seen: Array = []
	for t in 1300:
		sim2.step()
		for e in sim2.take_events():
			if e[0] == P.E_TRAIN_WARN or e[0] == P.E_TRAIN:
				seen.append([e[0], t + 1])
	var order_ok: bool = seen.size() >= 2 and seen[0][0] == P.E_TRAIN_WARN and seen[1][0] == P.E_TRAIN \
		and seen[1][1] - seen[0][1] == Shop.WARN_T and seen[0][1] >= Shop.FIRST[0] and seen[0][1] <= Shop.FIRST[1]
	_check("in a round the first whistle comes %.1f to %.2f s after FIGHT, the train %d ticks after it" % [Shop.FIRST[0] / 60.0, Shop.FIRST[1] / 60.0, Shop.WARN_T],
		order_ok, "the events: %s" % str(seen.slice(0, 4)))

# ------------------------------------------------------------------ on the track
func _knocks_out() -> void:
	var lines: Array = []
	var ok := true
	for d in [1, -1]:
		for x in [30, 420, 960, 1500, 1890]:   # in a tunnel, on a trapdoor, the middle, on the other trapdoor, in the other tunnel
			var sim = _game(3)
			var victim = sim.fighters[0]
			var up = sim.fighters[1]
			_put(sim, victim, x, FLOOR)
			_put(sim, up, x, 930 if x > 90 and x < 330 else 810)     # another one a ledge up (the workbench by the tunnel is at 930, a shelf at 810)
			_force(sim, d)
			var died := -1
			var cause := -1
			var hit_ev := false
			for t in Shop.WARN_T + Shop.RUN_T + 5:
				sim.apply_input(victim, 0, 0)
				sim.step()
				for e in sim.take_events():
					if e[0] == P.E_DEATH and e[3] == victim.id and died < 0:
						died = t + 1
						cause = e[4]
					if e[0] == P.E_TRAIN_HIT and e[3] == victim.id:
						hit_ev = true
			# the front reaches the body's near edge (less the margin) on this tick of the run
			var reach: float = (x - 18 + Shop.HIT_MARGIN) if d > 0 else (Shop.W - (x + 18 - Shop.HIT_MARGIN))
			var want := Shop.WARN_T + maxi(1, ceili((reach + 0.001) / Shop.SPEED))
			var good: bool = cause == 13 and hit_ev and absi(died - want) <= 1 and up.state != P.F_DEAD
			ok = ok and good
			lines.append("x %d %s: tick %d (the front is there on %d)%s" % [x, "R" if d > 0 else "L", died, want, "" if good else " BAD (cause %d, the one above %s)" % [cause, "lived" if up.state != P.F_DEAD else "DIED"]])
	_check("a fighter standing on the track is knocked out (cause 13: %s) the tick the train reaches it; one on a ledge above lives" % P.CAUSES.get(13, "-"),
		ok, "; ".join(lines))

# A held jump from the open floor: how many ticks before the train reaches the body may the
# press come? `hold` ticks of jump (a full hold: 60).
func _jump_window(hold: int, d: int) -> Array:
	var lived: Array = []
	for lead in range(0, 40):
		var sim = _game(2)
		var f = sim.fighters[0]
		var x := 405                    # open floor: on a trapdoor, no low ledge over it (the shelf above is 210 px up)
		_put(sim, f, x, FLOOR)
		var reach: float = (x - 18) if d > 0 else (Shop.W - (x + 18))
		var arrive := ceili(reach / Shop.SPEED)
		_running(sim, d, 0)
		for t in arrive + 60:
			var b := 0
			if t >= arrive - lead and t < arrive - lead + hold:
				b = P.B_JUMP
			sim.apply_input(f, b, 0)
			sim.step()
			sim.take_events()
		if f.state != P.F_DEAD:
			lived.append(lead)
	return lived

func _jump_clears() -> void:
	var full := _jump_window(60, 1)
	var full_l := _jump_window(60, -1)
	var mid := _jump_window(12, 1)
	var tap := _jump_window(2, 1)
	var ok: bool = full.size() >= 10 and full_l.size() >= 10 and mid.size() >= 4
	_check("a held jump clears the train (the press may come over a spread of ticks before it arrives)", ok,
		"jump held all the way: pressed %s ticks before it arrives (%d ticks, %.2f s of leeway; the other way %d); held 12 ticks: %s (%d ticks); a tap: %s" % [
		_span(full), full.size(), full.size() / 60.0, full_l.size(), _span(mid), mid.size(), _span(tap) if not tap.is_empty() else "never (too low)"])

func _span(l: Array) -> String:
	return "none" if l.is_empty() else "%d to %d" % [l[0], l[-1]]

# ------------------------------------------------------------------ off the track
func _ledge_safe() -> void:
	var lines: Array = []
	var ok := true
	# [feet x, feet y, what]: the lowest ledges (row 31, 90 px up; row 30, 120 px up), both ends
	for spot in [[150, 930, "the workbench by the left tunnel"], [1740, 930, "the workbench by the right tunnel"],
			[540, 930, "the bench in the court"], [960, 900, "the tree's lowest boughs"], [690, 900, "their left end"]]:
		for d in [1, -1]:
			var sim = _game(2)
			var f = sim.fighters[0]
			_put(sim, f, spot[0], spot[1])
			_force(sim, d)
			var moved := false
			for t in Shop.WARN_T + Shop.RUN_T + 5:
				sim.apply_input(f, 0, 0)
				sim.step()
				sim.take_events()
				if f.y + 63 != spot[1] or absf(f.vx) > 0.0:
					moved = true
			var good: bool = f.state != P.F_DEAD and not moved
			ok = ok and good
			if d > 0 or not good:
				lines.append("%s (feet %d px over the floor): %s" % [spot[2], FLOOR - int(spot[1]), "safe, not moved" if good else "HIT or MOVED"])
	_check("a fighter standing on a low ledge is safe from the train, and is not moved by it", ok, "; ".join(lines))

# The roof is no platform: a fighter that comes down on the train goes through its roof
# into the box (and is knocked out); nobody ever stands on it.
func _roof() -> void:
	var sim = _game(2)
	var f = sim.fighters[0]
	_running(sim, 1, 40)               # the train's box is at x 308 to 520 now
	var r: Rect2 = sim.hazards.box()
	_put(sim, f, r.get_center().x + 60.0, FLOOR - Shop.TRAIN_H - 40)   # in the air over where its middle will be
	var stood := false
	var died := false
	var cause := -1
	for t in 40:
		sim.apply_input(f, 0, 0)
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_DEATH and e[3] == f.id:
				died = true
				cause = e[4]
		if f.state != P.F_DEAD and f.on_ground and f.y + 63 < FLOOR:
			stood = true
	_check("the train's roof holds nobody: a fighter that drops onto it falls into it and is knocked out", died and cause == 13 and not stood,
		"dropped from 40 px over the roof: %s, cause %d, stood on something above the floor: %s" % ["knocked out" if died else "alive", cause, stood])

# The furnace's rule: its fire does not care about a dodge or a SHIELD (a SHIELD takes arrows).
func _dodge_shield() -> void:
	var sim = _game(3)
	var a = sim.fighters[0]
	var b = sim.fighters[1]
	_put(sim, a, 700, FLOOR)
	_put(sim, b, 1200, FLOOR)
	a.shield = 1
	_running(sim, 1, 40)
	var out := {}
	for t in 80:
		sim.apply_input(a, 0, 0)
		# b rolls on the floor (a dodge) as the train comes
		var bb := (P.B_DODGE | P.B_LEFT) if (t % 30) == 20 else P.B_LEFT
		sim.apply_input(b, bb, 0)
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_DEATH:
				out[e[3]] = [e[4], b.state if e[3] == b.id else a.state]
	_check("a SHIELD and a dodge do not save from the train (as with a furnace's fire)", out.has(a.id) and out.has(b.id) and out[a.id][0] == 13 and out[b.id][0] == 13,
		"the one with a SHIELD: %s; the one dodging: %s" % ["knocked out" if out.has(a.id) else "LIVED", "knocked out" if out.has(b.id) else "LIVED"])

func _winner_safe() -> void:
	# FREE FOR ALL: the round is called, its winner stands on the track
	var sim = _game(2)
	var w = sim.fighters[0]
	_put(sim, w, 700, FLOOR)
	sim.safe = w.id
	_running(sim, 1, 20)
	var phews := 0
	var deaths := 0
	var thrown := 0.0
	for t in 80:
		sim.apply_input(w, 0, 0)
		sim.step()
		thrown = maxf(thrown, maxf(absf(w.vx), absf(w.vy)))
		for e in sim.take_events():
			if e[0] == P.E_PHEW and e[3] == w.id:
				phews += 1
			if e[0] == P.E_DEATH:
				deaths += 1
	var ffa: bool = w.state != P.F_DEAD and deaths == 0 and phews == 1 and thrown == 0.0 and w.x == 700 - 18
	# TEAMS: the winning team is safe, the round decided
	var s2 = _game(3)
	s2.teams = {0: 0, 1: 0, 2: 1}
	for f in s2.fighters:
		_put(s2, f, 600 + f.id * 200, FLOOR)
	s2._kill(s2.fighters[2], 255, 1)
	s2.take_events()
	s2.safe_team = 0
	_running(s2, -1, 20)
	var phews2 := 0
	for t in 120:
		for f in s2.fighters:
			s2.apply_input(f, 0, 0)
		s2.step()
		for e in s2.take_events():
			if e[0] == P.E_PHEW:
				phews2 += 1
	var team: bool = s2.fighters[0].state != P.F_DEAD and s2.fighters[1].state != P.F_DEAD and phews2 == 2
	# and a round that is decided but not called yet: the train hurts nobody
	var s3 = _game(2)
	_put(s3, s3.fighters[0], 700, FLOOR)
	s3._kill(s3.fighters[1], 255, 1)
	_running(s3, 1, 20)
	for t in 80:
		s3.apply_input(s3.fighters[0], 0, 0)
		s3.step()
	var decided: bool = s3.fighters[0].state != P.F_DEAD
	_check("the round's winner is safe on the track (E_PHEW once, not thrown); a winning team too; a decided round's last fighter too", ffa and team and decided,
		"the winner: %s, %d PHEW, thrown %.1f; the team's two: %s, %d PHEW; the last one standing: %s" % ["alive" if w.state != P.F_DEAD else "DEAD", phews, thrown,
		"alive" if team else "NOT both alive", phews2, "alive" if decided else "DEAD"])

func _costume() -> void:
	var sim = _game(2)
	var f = sim.fighters[0]
	_put(sim, f, 900, FLOOR)
	f.mask = true
	_running(sim, 1, 30)
	var downs := 0
	var deaths := 0
	var hits := 0
	for t in 60:                       # the first train passes all the way over it (it lies in the box about 18 ticks)
		sim.apply_input(f, 0, 0)
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_MASK_DOWN and e[3] == f.id:
				downs += 1
			if e[0] == P.E_DEATH:
				deaths += 1
			if e[0] == P.E_TRAIN_HIT:
				hits += 1
	var first: bool = f.state != P.F_DEAD and downs == 1 and deaths == 0 and hits == 1 and f.down_t > 0
	var down_left: int = f.down_t
	# a second train while it is still down (MASK_GRACE is long past): the end
	sim._place(f, Vector2i(900, FLOOR))
	f.mask = true
	f.down_t = down_left
	f.state = P.F_HURT
	f.dodge_t = down_left
	_running(sim, -1, 60)
	var cause := -1
	for t in 50:
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_DEATH and e[3] == f.id:
				cause = e[4]
	_check("a costume is knocked down by a train (one hit for the whole train), and a second train ends it", first and cause == 13,
		"the first train: %d knock-down, %d deaths, %d train hits, then %s; the second: %s" % [downs, deaths, hits, "down, alive" if first else "WRONG",
		"knocked out (cause 13)" if cause == 13 else "cause %d" % cause])

# ------------------------------------------------------------------ no round, no train
func _predicting() -> void:
	var sim = _game(3)
	sim.predicting = true
	var moved := false
	for t in 1300:
		sim.step()
		sim.take_events()
		if sim.hazards.tick != 0 or sim.hazards.phase != Shop.IDLE:
			moved = true
	_check("the page's own copy of the game (sim.predicting) never runs the train", not moved, "1300 ticks: %s" % ("it never moved" if not moved else "IT MOVED"))

func _lone_fighter() -> void:
	var sim = SimScript.new(0, 24, 9)
	sim.set_arena(ARENA)
	sim.respawn = false
	sim.start_round([{"id": 0, "bot": false}])
	sim.frozen = false
	var f = sim.fighters[0]
	_put(sim, f, 960, FLOOR)
	var moved := false
	for t in 2400:
		sim.apply_input(f, 0, 0)
		sim.step()
		sim.take_events()
		if sim.hazards.phase != Shop.IDLE:
			moved = true
	_check("a lone fighter (the route runs, the reach test) never sees a train", not moved and f.state != P.F_DEAD,
		"40 s on the track: %s" % ("no whistle, no train" if not moved else "a train came"))

# ------------------------------------------------------------------ bodies and arrows
func _bodies_arrows() -> void:
	var sim = _game(3)
	var body = sim.fighters[0]
	_put(sim, body, 900, FLOOR)
	sim._kill(body, 255, 1)
	_put(sim, sim.fighters[2], 300, 420)
	for t in 40:                       # it lies still
		sim.step()
	sim.take_events()
	var x0: int = body.x
	var stuck = SimScript.Arrow.new()
	stuck.id = 900
	stuck.state = P.S_STUCK
	stuck.x = 1100.0
	stuck.y = float(FLOOR) - 4.0
	stuck.owner = 5
	sim.arrows.append(stuck)
	var fly = SimScript.Arrow.new()     # shot at the train's front when it is 150 px away
	fly.id = 901
	fly.state = P.S_FLY
	fly.y = float(FLOOR) - 22.0
	fly.vx = -14.0
	fly.vy = 0.0
	fly.owner = 5
	fly.t = 30
	_running(sim, 1, 30)
	var tink := false
	var tossed := false
	var top := 9999.0
	for t in 110:
		if t == 60:
			fly.x = Shop.front_at(sim.hazards.t, 1) + 150.0
			sim.arrows.append(fly)
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_TINK:
				tink = true
		if stuck.state == P.S_FALL:
			tossed = true
		if tossed:
			top = minf(top, stuck.y)
	var moved: int = body.x - x0
	_check("the train bumps a fallen body along, tosses an arrow stuck in the track, and a flying arrow bounces off it", moved > 40 and tossed and tink,
		"the body moved %d px the train's way; the stuck arrow was tossed %s (up to y %d); the flying one %s" % [moved, "ahead" if tossed else "NOT", top,
		"bounced (tink)" if tink else "DID NOT bounce"])

# ------------------------------------------------------------------ the bots
# The train (heading right) is `eta` ticks from reaching a body whose feet middle is at x:
# on its run, or still in its whistle when x is that near the mouth.
func _coming(sim, x: float, eta: float) -> void:
	var run_ticks: float = (x - 18.0) / Shop.SPEED
	if run_ticks >= eta:
		_running(sim, 1, int(run_ticks - eta))
	else:
		_force(sim, 1)
		sim.hazards.t = Shop.WARN_T - int(eta - run_ticks)

func _flee() -> void:
	var sim = _game(2)
	var bot = sim.fighters[1]
	bot.level = Brain.NORMAL
	var hz = sim.hazards
	var lines: Array = []
	var ok := true
	var near: float = Shop.REACT[Brain.NORMAL] - 2.0
	# [feet x, feet y, the answer wanted, what], the train `near` ticks away (it heads right)
	var cases := [
		[150, FLOOR, Shop.JUMP_UP, "under the workbench"],
		[960, FLOOR, Shop.JUMP_UP, "under the tree"],
		[30, FLOOR, Shop.GO_RIGHT, "in the left tunnel"],
		[1890, FLOOR, Shop.GO_LEFT, "in the right tunnel"],
		[960, 420, 0, "up on the star"],
	]
	for c in cases:
		_put(sim, bot, c[0], c[1])
		bot.on_ground = true
		_coming(sim, c[0], near)
		var got: int = hz.flee(sim, bot)
		_coming(sim, c[0], Shop.REACT[Brain.NORMAL] + 20.0)
		var far: int = hz.flee(sim, bot)
		hz._to(Shop.IDLE)
		var none: int = hz.flee(sim, bot)
		ok = ok and got == c[2] and none == 0 and far == 0
		lines.append("%s: %d (the train far: %d, none: %d)" % [c[3], got, far, none])
	# an EASY bot leaves it later than a HARD one
	_put(sim, bot, 960, FLOOR)
	bot.on_ground = true
	_coming(sim, 960, 45.0)
	bot.level = Brain.EASY
	var easy: int = hz.flee(sim, bot)
	bot.level = Brain.HARD
	var hard: int = hz.flee(sim, bot)
	ok = ok and easy == 0 and hard == Shop.JUMP_UP
	lines.append("the train 45 ticks away: an EASY bot %d, a HARD one %d" % [easy, hard])
	# on a low ledge with the train about to pass under: stay
	bot.level = Brain.NORMAL
	_put(sim, bot, 960, 900)
	bot.on_ground = true
	_coming(sim, 960, 25.0)
	var stay: int = hz.flee(sim, bot)
	ok = ok and stay == Shop.STAY
	lines.append("on the tree's lowest boughs with the train 25 ticks away: %d (stay)" % stay)
	_check("flee() tells a bot what to do about the train once it is near (1, -1 walk; 2, -2 walk and jump; 3 jump; 4 stay; 0 nothing)", ok, ", ".join(lines))
	# bots playing on the track when the whistle starts get out alive
	for lvl in [Brain.EASY, Brain.NORMAL, Brain.HARD]:
		var lived := 0
		var tries := 0
		var lost: Array = []
		for k in 16:
			for d in [1, -1]:
				var s2 = _game(2, 50 + k)
				var b2 = s2.fighters[1]
				b2.level = lvl
				b2.wait_t = 0
				var x := 20 + k * 125              # from one tunnel to the other
				_put(s2, b2, x, FLOOR)
				_force(s2, d)
				tries += 1
				for t in Shop.WARN_T + Shop.RUN_T + 5:
					s2.step()
					s2.take_events()
				if b2.state != P.F_DEAD:
					lived += 1
				else:
					lost.append("%d%s" % [x, "R" if d > 0 else "L"])
		_check("%s bots on the track when the whistle starts get out alive (9 in 10 at least)" % Brain.NAMES[lvl], lived * 10 >= tries * 9,
			"%d of %d lived (from x 20 to 1895, both ways)%s" % [lived, tries, "" if lost.is_empty() else "; lost at " + ", ".join(lost)])

# ------------------------------------------------------------------ the snapshot
func _snapshot() -> void:
	var sim = _game(4)
	var hz = sim.hazards
	_running(sim, -1, 77)
	hz.tick = 333
	hz.now = 70123
	sim.tick = 70123
	var buf := StreamPeerBuffer.new()
	sim.write_snapshot(buf, [])
	var reader = Net.new()
	reader._on_snapshot(buf.data_array)
	var h: Dictionary = reader.newest().get("hazards", {})
	var good: bool = not h.is_empty() and h["k"] == Shop.KIND and h["n"] == (333 & 255) and h["phase"] == Shop.RUN and h["t"] == 77.0 \
		and h["dir"] == -1 and h["held"] == false and h["at"] == (70123 & 0xFFFF)
	hz.dir = 1
	hz._to(Shop.WARN)
	hz.t = 50
	sim.write_snapshot(buf, [])
	reader._on_snapshot(buf.data_array)
	var h2: Dictionary = reader.newest().get("hazards", {})
	good = good and h2["phase"] == Shop.WARN and h2["t"] == 50.0 and h2["dir"] == 1
	var raw := StreamPeerBuffer.new()
	hz.write(raw)
	_check("the snapshot's train part reads back the same through the page's reader (client/net.gd)", good,
		"%d bytes after the hazards byte %d; read: %s then %s" % [raw.data_array.size(), Shop.KIND, str(h), str(h2)])
	# the boiler room's own byte and state are as they were
	var sb = SimScript.new(0, 24, 7)
	sb.set_arena(4)
	sb.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": true}])
	sb.write_snapshot(buf, [])
	reader._on_snapshot(buf.data_array)
	var hb: Dictionary = reader.newest().get("hazards", {})
	var sk = SimScript.new(0, 24, 7)
	sk.set_arena(1)
	sk.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": true}])
	sk.write_snapshot(buf, [])
	reader._on_snapshot(buf.data_array)
	_check("the other arenas' snapshots are as they were (THE BOILER ROOM's state after byte 1, none on THE KEEP)",
		hb.has("hook") and not hb.has("k") and not reader.newest().has("hazards"), "the boiler room: %d keys; the keep: %s" % [hb.size(),
		"no hazards" if not reader.newest().has("hazards") else "HAS hazards"])
	# on_tick: the page rolls the state on to your own tick
	var a: Dictionary = Shop.on_tick(h2, (70123 + 10) & 0xFFFF)                  # the whistle, 10 ticks on
	var b: Dictionary = Shop.on_tick(h2, (70123 + 60) & 0xFFFF)                  # past its end (at most AHEAD_MAX on): the train runs
	var c: Dictionary = Shop.on_tick(h2, (70123 - 5) & 0xFFFF)                   # never back
	var late := {"k": Shop.KIND, "n": 0, "phase": Shop.RUN, "t": float(Shop.RUN_T - 3), "dir": 1, "held": false, "at": 65530}
	var e: Dictionary = Shop.on_tick(late, 4)                                    # over the 16 bit wrap: 10 ticks on, the train is gone
	var rolled: bool = a["phase"] == Shop.WARN and a["t"] == 60.0 and b["phase"] == Shop.WARN and b["t"] == 50.0 + Shop.AHEAD_MAX \
		and c["t"] == 50.0 and e["phase"] == Shop.IDLE and h2["t"] == 50.0
	var near := {"k": Shop.KIND, "n": 0, "phase": Shop.WARN, "t": float(Shop.WARN_T - 4), "dir": -1, "held": false, "at": 100}
	var g: Dictionary = Shop.on_tick(near, 110)
	rolled = rolled and g["phase"] == Shop.RUN and g["t"] == 6.0 and g["at"] == 110
	_check("on_tick() rolls a state on to a later tick (the whistle runs out, the train starts, rolls, is gone), never back", rolled,
		"+10: %s t %.0f; +60: t %.0f (at most %d on); -5: t %.0f; 4 ticks before a whistle's end +10: phase %d t %.0f; 3 before a run's end +10: phase %d" % [
		["rest", "whistle", "run"][a["phase"]], a["t"], b["t"], Shop.AHEAD_MAX, c["t"], g["phase"], g["t"], e["phase"]])

# ------------------------------------------------------------------ the bots' rounds
func _rounds(count: int, seed_value: int, level: int) -> void:
	var t0 := Time.get_ticks_msec()
	var sim = SimScript.new(0, 24, seed_value)
	sim.bot_level = level
	sim.set_arena(ARENA)
	sim.respawn = false
	sim.power_arrows = false
	sim.walls_start = 25 * 60
	var seats: Array = []
	for i in 8:
		seats.append({"id": i, "bot": true})
	var causes := {}
	var deaths := 0
	var lengths: Array = []
	var draws := 0
	var stuck := 0
	var whistles := 0
	var trains := 0
	var with_train := 0
	var first_warn := 99999
	var bad_gap := 0                 # trains that did not come WARN_T ticks after their whistle
	var on_track := 0                # fighter-ticks on the track (feet under the train's roof) while a train ran
	var stuck_where: Array = []      # the feet of each bot that stood 5 s in one place
	var hz = sim.hazards
	for r in count:
		sim.start_round(seats)
		sim.frozen = false
		var trail := {}
		var stuck_now := {}
		var t := 0
		var warn_t := -1
		var had_train := false
		while t < 3600:
			sim.step()
			t += 1
			for e in sim.take_events():
				if e[0] == P.E_DEATH:
					deaths += 1
					causes[e[4]] = causes.get(e[4], 0) + 1
				elif e[0] == P.E_TRAIN_WARN:
					whistles += 1
					warn_t = t
					first_warn = mini(first_warn, t)
				elif e[0] == P.E_TRAIN:
					trains += 1
					had_train = true
					if warn_t < 0 or t - warn_t != Shop.WARN_T:
						bad_gap += 1
			if hz.phase == Shop.RUN:
				for f in sim.fighters:
					if f.state != P.F_DEAD and f.y + 63 > Shop.SAFE_Y and f.on_ground:
						on_track += 1
			if t % 30 == 0:
				for f in sim.fighters:
					if f.state == P.F_DEAD:
						continue
					var tr: Array = trail.get(f.id, [])
					tr.append(Vector2(f.x, f.y))
					if tr.size() > 10:
						tr.remove_at(0)
					trail[f.id] = tr
					if tr.size() == 10 and not stuck_now.has(f.id):
						var lo: Vector2 = tr[0]
						var hi: Vector2 = tr[0]
						for p in tr:
							lo = lo.min(p)
							hi = hi.max(p)
						if hi.x - lo.x < 90.0 and hi.y - lo.y < 90.0:
							stuck_now[f.id] = true
							stuck_where.append("(%d, %d)" % [(lo.x + hi.x) / 2 + 18, (lo.y + hi.y) / 2 + 63])
			if sim.alive_count() <= 1:
				break
		stuck += stuck_now.size()
		lengths.append(t / 60.0)
		if had_train:
			with_train += 1
		if sim.alive_count() == 0 or t >= 3600:
			draws += 1
	lengths.sort()
	var parts: Array = []
	var ks: Array = causes.keys()
	ks.sort()
	for k in ks:
		parts.append("%s %d (%.1f%%)" % [P.CAUSES.get(k, str(k)), causes[k], 100.0 * causes[k] / maxi(1, deaths)])
	var share: float = 100.0 * causes.get(13, 0) / maxi(1, deaths)
	print("   %d rounds of 8 %s bots: length median %.1f s, p90 %.1f s, longest %.1f s; draws %d%%; %d deaths: %s" % [count, Brain.NAMES[level],
		lengths[count / 2], lengths[int(count * 0.9)], lengths[-1], roundi(100.0 * draws / count), deaths, ", ".join(parts)])
	print("   in those rounds: %d whistles, %d trains, a train in %d%% of rounds; %d bot ticks on the track while a train ran; (%.1f s)" % [
		whistles, trains, roundi(100.0 * with_train / count), on_track, (Time.get_ticks_msec() - t0) / 1000.0])
	_check("the train's knockouts under 8%% of all knockouts (%d rounds of 8 bots): it is spice, not the main killer" % count, share < 8.0,
		"%.1f%% (%d of %d)" % [share, causes.get(13, 0), deaths])
	_check("bots stuck 5 s (inside a 90 px square while alive) no more than 1 bot round in 800", stuck * 800 <= count * 8,
		"%d of %d bot rounds%s" % [stuck, count * 8, "" if stuck_where.is_empty() else " (feet at " + ", ".join(stuck_where) + ")"])
	_check("the first whistle comes 5 s or more after FIGHT, and every train %d ticks after its whistle" % Shop.WARN_T, first_warn >= 300 and bad_gap == 0,
		"the first whistle on tick %d; %d of %d trains came some other time" % [first_warn, bad_gap, trains])

# p4.9 power-ups, headless: whole matches of 8 brains on an arena with the orbs on.
# Seats 0 and 1 count as people (the brain plays them too), so FLYING and the BIG
# power-ups (people only, behind the leader) get taken as well. Prints what dropped,
# what was taken by whom, the deaths by cause (lightning, ghost cats, spikes...), and
# checks the rules: orbs warn then strike, the bolt kills only near the orb, a BIG one
# only goes to someone behind the leader (p4.10: bots too), only the arrow kind comes
# back next round, a shield takes an arrow, no living body is ever inside a block (the
# flying bots), the whole fighter (write_fighter_state) reads back the same; p4.10: a
# killing arrow stays in the body and carries it, a wall pins it, taking the arrow lets
# it fall. Exit 1 on a failed check.
#   godot --headless --path bench --script res://tools/power_probe.gd -- --matches=6 --arena=1
extends SceneTree

const SimScript = preload("res://sim/sim.gd")
const P = preload("res://sim/proto.gd")
const BrainScript = preload("res://sim/brain.gd")

var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("🧪 [PowerProbe] FAIL: " + what)

func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var matches := int(args.get("matches", "6"))
	var arena := int(args.get("arena", "1"))
	var sim = SimScript.new(0, 24, int(args.get("seed", "11")))
	sim.respawn = false
	sim.powerups = true
	sim.walls_start = 25 * 60
	sim.set_arena(arena)
	var counts := {}
	var causes := {}
	var takes := {}
	var big_takes := 0
	var rounds := 0
	var inside := 0
	var fly_ticks := 0
	var bot_fly := 0
	var bot_big := 0
	var t0 := Time.get_ticks_msec()
	for mi in matches:
		var points := [0, 0, 0, 0, 0, 0, 0, 0]
		sim.reset_powers()
		var done := false
		while not done:
			var seat_list: Array = []
			for i in 8:
				seat_list.append({"id": i, "bot": i >= 2})
			sim.start_round(seat_list)
			rounds += 1
			for f in sim.fighters:
				f.points = points[f.id]
				# only the arrow kind came back (p4.10: the rest last one round)
				_check(f.pw_kind == int(sim.keep.get(f.id, 0)) and not f.inf and not f.fly and not f.big and f.shield == 0,
					"seat %d starts the round with only its arrow kind" % f.id)
			var top := 0
			for v in points:
				top = maxi(top, v)
			sim.frozen = false
			var t := 0
			while sim.alive_count() > 1 and t < 3600:
				t += 1
				for f in sim.fighters:
					if not f.bot and f.state != P.F_DEAD:
						BrainScript.think(sim, f)   # the "people" are played by the brain too
				sim.step()
				for f in sim.fighters:
					if f.state != P.F_DEAD:
						if sim.box_hits_solid(f.x, f.y, SimScript.BODY_W, SimScript.BODY_H):
							inside += 1
						if f.fly and f.bot:
							fly_ticks += 1
				for e in sim.take_events():
					counts[e[0]] = counts.get(e[0], 0) + 1
					if e[0] == P.E_DEATH:
						causes[e[4]] = causes.get(e[4], 0) + 1
					elif e[0] == P.E_PU_GET:
						var who = sim.fighter(e[3])
						takes[e[4]] = takes.get(e[4], 0) + 1
						if e[4] == P.PU_FLY and who.bot:
							bot_fly += 1
						if P.is_big(e[4]):
							big_takes += 1
							if who.bot:
								bot_big += 1
							_check(who.points < top, "a BIG one went to seat %d (%d points, top %d)" % [e[3], who.points, top])
					elif e[0] == P.E_STRIKE:
						for f in sim.fighters:
							if f.state != P.F_DEAD and not f.mask:   # p4.12: GHOSTFACE is knocked down, not out
								var dx := SimScript.wrap_d(e[1], f.x + SimScript.HALF_W, 1920)
								var dy := SimScript.wrap_d(e[2], f.y + SimScript.MID_Y, 1080)
								_check(dx * dx + dy * dy > SimScript.STRIKE_R * SimScript.STRIKE_R, "someone near the bolt lived")
			var last = sim.last_alive()
			if last != null and sim.alive_count() == 1:
				points[last.id] += 1
				if points[last.id] >= 3:
					done = true
			# the whole fighter reads back the same (prediction): every power-up field
			for f in sim.fighters:
				var buf := StreamPeerBuffer.new()
				sim.write_fighter_state(buf, f)
				buf.seek(0)
				var g := SimScript.Fighter.new()
				sim.read_fighter_state(buf, g)
				for k in ["pw_kind", "shield", "inf", "fly", "big", "freeze_t", "slow_t", "speed_t", "invis_t", "umbrella_t", "spikes_t", "spike_up", "spike_regen", "vdir", "pinned", "carry_t",
						"trick", "trick_t", "mask", "down_t", "knife_t", "knife_cd", "knife_hit"]:
					_check(g.get(k) == f.get(k), "the whole fighter's %s read back %s, not %s" % [k, g.get(k), f.get(k)])
	# a shield takes one arrow, then the next one kills
	var s2 = SimScript.new(0, 24, 3)
	s2.respawn = false
	s2.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": false}])
	s2.frozen = false
	var a = s2.fighters[0]
	var b = s2.fighters[1]
	b.shield = 1
	b.x = a.x + 300
	b.y = a.y
	for shot in 2:
		var arrow := SimScript.Arrow.new()
		arrow.x = b.x + 18.0
		arrow.y = b.y + 20.0
		arrow.vx = 4.0
		arrow.owner = 0
		arrow.t = 20
		s2.arrows.append(arrow)
		s2._arrow_hit_fighters(arrow)
		if shot == 0:
			_check(b.state != P.F_DEAD and b.shield == 0, "the shield took the first arrow")
		else:
			_check(b.state == P.F_DEAD, "the second arrow killed")
	# p4.10 deaths: a killing arrow stays in the body and carries it (open air); a body
	# carried into a wall hangs there on the arrow, which sticks in the wall; taking that
	# arrow lets the body fall
	var s4 = SimScript.new(0, 24, 9)
	s4.respawn = false
	s4.set_arena(0)
	s4.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": false}, {"id": 2, "bot": false}])
	s4.frozen = false
	var v1 = s4.fighters[1]
	v1.x = 900
	v1.y = 220
	var a1 := SimScript.Arrow.new()
	a1.x = v1.x - 2.0
	a1.y = v1.y + 25.0
	a1.vx = 16.0
	a1.owner = 0
	a1.t = 20
	s4.arrows.append(a1)
	s4._arrow_hit_fighters(a1)
	var x0: int = v1.x
	for tick in 12:
		s4.step()
	var carried: int = v1.x - x0
	_check(v1.state == P.F_DEAD and a1.state == P.S_BODY and a1.body == 1, "the killing arrow stays in the body")
	_check(carried > 60 and carried < 200, "the arrow carries the body on a bit (it moved %d px in 12 ticks)" % carried)
	_check(absf(SimScript.wrap_d(v1.x + a1.bx, a1.x, 1920)) < 1.0, "the arrow rides with the body")
	var v2 = s4.fighters[2]
	v2.x = 75
	v2.y = 200
	var a2 := SimScript.Arrow.new()
	a2.x = v2.x + 34.0
	a2.y = v2.y + 25.0
	a2.vx = -16.0
	a2.owner = 0
	a2.t = 20
	s4.arrows.append(a2)
	s4._arrow_hit_fighters(a2)
	var pinned_ev := 0
	for tick in 60:
		s4.step()
		for e in s4.take_events():
			if e[0] == P.E_PIN:
				pinned_ev += 1
	var hang_y: int = v2.y
	for tick in 60:
		s4.step()
	_check(v2.pinned and pinned_ev == 1 and a2.state == P.S_STUCK and a2.pins == 2 and v2.y == hang_y, "a wall pins the body: it hangs there, the arrow in the wall")
	var taker = s4.fighters[0]
	taker.x = int(a2.x) - 18
	taker.y = int(a2.y) - 31
	taker.state = P.F_NORMAL
	for tick in 3:
		s4._pickups()
	for tick in 30:
		s4.step()
	_check(a2.dead and not v2.pinned and v2.y > hang_y, "taking the pinning arrow lets the body fall")
	print("🧪 [PowerProbe] deaths: carried %d px in 12 ticks; pinned on the wall at y %d; it fell to y %d once the arrow was taken" % [carried, hang_y, v2.y])
	# p4.11 ghosts: a person's ghost rises GHOST_WAIT after its death, floats by the stick
	# (through walls), its BOO dash shoves a living fighter (not a dead one), an arrow pops it
	var s5 = SimScript.new(0, 24, 4)
	s5.respawn = false
	s5.set_arena(1)
	# (the one to shove is a person standing still: a bot's walk depends on the sim's dice,
	# which p4.12's black cat and bats now also use)
	s5.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": false}, {"id": 2, "bot": true}])
	s5.frozen = false
	var pg = s5.fighters[0]
	var tg = s5.fighters[1]
	s5._kill(pg, 1, 1)
	_check(not pg.ghost and pg.ghost_wait == SimScript.GHOST_WAIT, "a person's ghost waits to rise")
	var bot_dead = s5.fighters[2]
	s5._kill(bot_dead, 1, 1)
	for tick in SimScript.GHOST_WAIT + 2:
		s5.step()
	_check(pg.ghost and not bot_dead.ghost, "the person's ghost rose, a bot's did not")
	var gx0: float = pg.gx
	for tick in 30:
		s5.apply_input(pg, P.B_RIGHT, 0)
		s5.step()
	_check(SimScript.wrap_d(gx0, pg.gx, 1920) > 60.0, "the stick floats the ghost (it moved %.0f px)" % SimScript.wrap_d(gx0, pg.gx, 1920))
	pg.gx = float(tg.x + 18 - 100)
	pg.gy = float(tg.y + 31)
	pg.boo_cd = 0
	tg.state = P.F_NORMAL
	s5.apply_input(pg, P.B_SHOOT, 0)
	s5.apply_input(pg, 0, 0)       # let go of shoot, aimed right (0): BOO
	var shoved := false
	for tick in 12:
		s5.step()
		for e in s5.take_events():
			if e[0] == P.E_BOO and e[4] == tg.id:
				shoved = true
	_check(shoved and tg.state != P.F_DEAD, "the BOO shoves a living fighter (and never kills it)")
	pg.gx = 900.0      # in open air on THE KEEP (a ghost inside a wall is safe: arrows stick in the wall)
	pg.gy = 300.0
	pg.gvx = 0.0
	pg.gvy = 0.0
	var ar := SimScript.Arrow.new()
	ar.x = pg.gx - 20.0
	ar.y = pg.gy
	ar.vx = 16.0
	ar.owner = 1
	ar.t = 20
	s5.arrows.append(ar)
	s5.step()
	_check(pg.popped_t > 0, "an arrow pops the ghost")
	print("🧪 [PowerProbe] ghosts: rose after %d ticks, floated, BOO'd, popped by an arrow" % SimScript.GHOST_WAIT)
	# ghost cats: one hunts a fighter standing still (it dies, cause 8), one meets a
	# fighter dodging (the cat is caught: E_CAT_POOF with b = 1, nobody dies)
	var s3 = SimScript.new(0, 24, 5)
	s3.respawn = false
	s3.set_arena(1)
	s3.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": false}, {"id": 2, "bot": false}])
	s3.frozen = false
	s3._give(s3.fighters[0], P.PU_CATS)
	_check(s3.cats.size() == SimScript.CATS_N, "GHOST CATS sent %d cats" % s3.cats.size())
	var cat_kills := 0
	var caught := 0
	var dodger = s3.fighters[2]
	for tick in 600:
		for c in s3.cats:      # the dodger dodges when a cat is close
			if c.target == dodger.id and dodger.state == P.F_NORMAL and dodger.dodge_cd == 0 \
					and absf(SimScript.wrap_d(c.x, dodger.x + 18.0, 1920)) < 60.0 and absf(SimScript.wrap_d(c.y, dodger.y + 31.0, 1080)) < 60.0:
				s3._start_dodge(dodger, Vector2(SimScript.wrap_d(dodger.x + 18.0, c.x, 1920), SimScript.wrap_d(dodger.y + 31.0, c.y, 1080)))   # into the cat
		s3.step()
		for e in s3.take_events():
			if e[0] == P.E_DEATH and e[4] == 8:
				cat_kills += 1
			elif e[0] == P.E_CAT_POOF and e[4] == 1:
				caught += 1
	print("🧪 [PowerProbe] ghost cats: %d kills, %d caught by a dodge, %d cats left" % [cat_kills, caught, s3.cats.size()])
	_check(cat_kills >= 1, "a ghost cat killed the fighter standing still")
	_check(caught >= 1, "a dodge caught a ghost cat")
	_check(s3.fighters[0].state != P.F_DEAD, "the cats never hurt their owner")
	var names := []
	for k in counts:
		names.append("%d:%d" % [k, counts[k]])
	print("🧪 [PowerProbe] %d matches, %d rounds on arena %d in %d ms" % [matches, rounds, arena, Time.get_ticks_msec() - t0])
	print("🧪 [PowerProbe] warnings %d, strikes %d, taken %d (BIG %d), faded %d, shields popped %d, cats gone %d, freezes %d, pins %d" % [
		counts.get(P.E_PU_WARN, 0), counts.get(P.E_STRIKE, 0), counts.get(P.E_PU_GET, 0), big_takes, counts.get(P.E_PU_GONE, 0),
		counts.get(P.E_SHIELD_POP, 0), counts.get(P.E_CAT_POOF, 0), counts.get(P.E_FREEZE, 0), counts.get(P.E_PIN, 0)])
	print("🧪 [PowerProbe] bots took FLYING %d times (flew %d ticks) and BIG ones %d times; living bodies inside a block: %d ticks" % [bot_fly, fly_ticks, bot_big, inside])
	_check(inside == 0, "no living body is ever inside a block (%d ticks)" % inside)
	var tl := []
	for k in takes:
		tl.append("%s %d" % [P.PU_SHORT.get(k, str(k)), takes[k]])
	print("🧪 [PowerProbe] taken: " + ", ".join(tl))
	var cl := []
	for k in causes:
		cl.append("%s %d" % [P.CAUSES.get(k, str(k)), causes[k]])
	print("🧪 [PowerProbe] deaths: " + ", ".join(cl))
	_check(counts.get(P.E_STRIKE, 0) > 0, "no bolt ever struck")
	_check(counts.get(P.E_PU_GET, 0) > 0, "nobody ever took a power-up")
	print("🧪 [PowerProbe] %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(0 if fails == 0 else 1)

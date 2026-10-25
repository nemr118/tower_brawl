# p4.9 power-ups, headless: whole matches of 8 brains on an arena with the orbs on.
# Seats 0 and 1 count as people (the brain plays them too), so FLYING and the BIG
# power-ups (people only, behind the leader) get taken as well. Prints what dropped,
# what was taken by whom, the deaths by cause (lightning, ghost cats, spikes...), and
# checks the rules: orbs warn then strike, the bolt kills only near the orb, a bot
# never takes FLYING or a BIG one, a BIG one only goes to a person behind the leader,
# kept power-ups come back next round, a shield takes an arrow, the whole fighter
# (write_fighter_state) reads back the same. Exit 1 on a failed check.
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
				# kept power-ups came back (the round before set them)
				if sim.keep.has(f.id):
					var k: Array = sim.keep[f.id]
					_check(f.pw_kind == k[0] and f.inf == k[2] and f.big == k[4], "seat %d's kept power-ups came back" % f.id)
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
				for e in sim.take_events():
					counts[e[0]] = counts.get(e[0], 0) + 1
					if e[0] == P.E_DEATH:
						causes[e[4]] = causes.get(e[4], 0) + 1
					elif e[0] == P.E_PU_GET:
						var who = sim.fighter(e[3])
						takes[e[4]] = takes.get(e[4], 0) + 1
						if e[4] == P.PU_FLY:
							_check(not who.bot, "a bot took FLYING")
						if e[4] >= P.PU_CATS:
							big_takes += 1
							_check(not who.bot and who.points < top, "a BIG one went to seat %d (bot %s, %d points, top %d)" % [e[3], who.bot, who.points, top])
					elif e[0] == P.E_STRIKE:
						for f in sim.fighters:
							if f.state != P.F_DEAD:
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
				for k in ["pw_kind", "shield", "inf", "fly", "big", "freeze_t", "slow_t", "speed_t", "invis_t", "umbrella_t", "spikes_t", "spike_up", "spike_regen", "vdir"]:
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
	var names := []
	for k in counts:
		names.append("%d:%d" % [k, counts[k]])
	print("🧪 [PowerProbe] %d matches, %d rounds on arena %d in %d ms" % [matches, rounds, arena, Time.get_ticks_msec() - t0])
	print("🧪 [PowerProbe] warnings %d, strikes %d, taken %d (BIG %d), faded %d, shields popped %d, cats gone %d, freezes %d" % [
		counts.get(P.E_PU_WARN, 0), counts.get(P.E_STRIKE, 0), counts.get(P.E_PU_GET, 0), big_takes, counts.get(P.E_PU_GONE, 0),
		counts.get(P.E_SHIELD_POP, 0), counts.get(P.E_CAT_POOF, 0), counts.get(P.E_FREEZE, 0)])
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

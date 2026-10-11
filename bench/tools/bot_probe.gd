# The bot probe (G6, server bots): measures the bot brain offline, on each arena
# of sim/level.gd. No server, no drawing.
#   godot --headless --path bench --script res://tools/bot_probe.gd -- [--layout=N] [--rounds=N] [--png=DIR] [--seed=N]
#       [--level=old,easy,normal,hard] [--catch] [--reach] [--kid] [--deaths=v2_server.jsonl --png=DIR]
# Rounds of 8 bots, as the server plays them (one life, the purple walls at 25 s,
# the 60 s backstop, plain arrows): how long they last, draws, how the bots die
# and where (the death spots: how many of the 144 squares of 120 px see a death,
# and the share of the deaths in the busiest 15, a tenth of them),
# bots stuck 5 s (inside a 90 px square while alive, once a round per bot).
# Shots: how many had a wall between the bot and its target at the moment the
# arrow left the bow (the target is the one the brain aimed at, f.mind.target; a
# wall between: every copy of an arrow shot at it, straight or a little above or
# below, meets a block or a ledge first, at where it is and at where it runs to:
# brain.gd find_shot with no lead, the level's lead and a full lead), and what
# each arrow did: stuck
# in a block or a ledge before it reached anyone, reached a fighter (a kill, or a
# bounce off one), was caught, or met another arrow (a tink).
# --level: the brain's levels to measure, one after another (sim/brain.gd; the
# default is the sim's bot_level, what the server plays). Arrows: the share of time a bot has none,
# and pickups a round. Cost: the brains' share of a tick.
# --catch: the catch test instead of rounds (G6 step 4): a person shoots at a bot
# that stands and only dodges (the Mind's test knob only_dodge), 200 arrows a level,
# from 200 to 600 px, along a path that reaches it (on all three arenas, random
# places); of the arrows that reach the bot, the share it catches.
# --reach: the reach test instead of rounds (G6 step 5): a lone bot (NORMAL; the
# Mind's test knob force_goal) starts in the middle of each floor or ledge and is
# sent to every other one; it must stand there within 8 s. The share that made
# it, per arena, the slowest, and the ones that did not.
# --kid: the stand-in for a kid instead of rounds (G6 step 7): one seat is a
# person's (the bots see a person, brain.gd PEOPLE) whose buttons come from
# p3.1's brain (OLD: it walks at the nearest, shoots at it, often into walls,
# dodges at random), against 7 bots of the level, --rounds on each arena: how
# often it is the last one standing (1 in 8 against 7 like it), how long it lives.
# --deaths=FILE: no rounds here: the death spots of a real server's rounds (the
# round lines of its v2_server.jsonl, a soak's or a play night's), drawn as maps
# with --png (deaths_N_server.png).
# --png DIR: a death-spot map per arena (deaths_N.png): blocks grey, ledges amber,
# each square of 120 px red by its share of the deaths.
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const Brain = preload("res://sim/brain.gd")
const Routes = preload("res://sim/routes.gd")

const W := 1920
const H := 1080
const SQ := 120                   # a death-spot square: 16 x 9 of them
const ROUND_MAX := 3600           # the server's 60 s backstop
const WALLS_AT := 25 * 60         # the server's purple walls

# The sim with a stopwatch on the brain (the same hook as tools/sim_prof.gd), and
# a look at each shot the moment the brain makes it (before anything moves; not
# timed).
class Timed extends "res://sim/sim.gd":
	var brain_us := 0
	var shots_seen := 0
	var walled := 0
	func _brain(f: Fighter) -> void:
		var n := arrows.size()
		var t := Time.get_ticks_usec()
		super._brain(f)
		brain_us += Time.get_ticks_usec() - t
		if arrows.size() > n:
			shots_seen += 1
			if _wall_between(f):
				walled += 1

	# A wall between the shooter and its target: no copy of an arrow reaches it,
	# straight or a little above or below, where it is or where it runs to (the
	# same test for any brain, the new levels' own; past 900 px it counts as a wall).
	func _wall_between(f) -> bool:
		var o = fighter(f.mind.target) if f.mind != null else null
		if o == null or o.state == P.F_DEAD:
			return false
		for lead in [0.0, BrainScript.LEAD[f.level], 1.0]:
			if not is_nan(BrainScript.find_shot(self, f, o, lead)):
				return false
		return true

func _init() -> void:
	var only := -1
	var rounds := 100
	var png_dir := ""
	var seed_value := 2000
	var levels: Array = [SimScript.new(0).bot_level]
	var catch_test := false
	var reach_test := false
	var kid_test := false
	var deaths_file := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--layout="):
			only = int(a.get_slice("=", 1))
		elif a.begins_with("--rounds="):
			rounds = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--png="):
			png_dir = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a == "--catch":
			catch_test = true
		elif a == "--reach":
			reach_test = true
		elif a == "--kid":
			kid_test = true
		elif a.begins_with("--deaths="):
			deaths_file = a.get_slice("=", 1)
		elif a.begins_with("--level="):
			levels.clear()
			for name in a.get_slice("=", 1).split(","):
				var k := Brain.NAMES.find(name.strip_edges().to_upper())
				if k < 0:
					printerr("unknown level %s (%s)" % [name, ", ".join(Brain.NAMES)])
					quit(1)
					return
				levels.append(k)
	if png_dir != "":
		DirAccess.make_dir_recursive_absolute(png_dir)
	if catch_test:
		for lv in levels:
			_catch(lv, seed_value)
		quit(0)
		return
	if deaths_file != "":
		_server_deaths(deaths_file, png_dir)
		quit(0)
		return
	if kid_test:
		for lv in levels:
			_kid(lv, rounds, seed_value)
		quit(0)
		return
	if reach_test:
		var all_ok := true
		for n in LevelScript.count():
			if only < 0 or n == only:
				all_ok = _reach(n) and all_ok
		quit(0 if all_ok else 1)
		return
	for n in LevelScript.count():
		if only < 0 or n == only:
			for lv in levels:
				_rounds(n, lv, rounds, seed_value + n, png_dir)
	quit(0)

# The death spots of a server's rounds (its round lines), a map per arena.
func _server_deaths(path: String, png_dir: String) -> void:
	var spots := {}      # arena -> {square: deaths}
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		printerr("cannot read %s" % path)
		return
	while not fa.eof_reached():
		var d = JSON.parse_string(fa.get_line())
		if not (d is Dictionary) or d.get("kind", "") != "round":
			continue
		var n := int(d.get("arena", 0))
		if not spots.has(n):
			spots[n] = {}
		for e in d.get("deaths", []):
			var sq := Vector2i(clampi(int(e[3]) / SQ, 0, W / SQ - 1), clampi(int(e[4]) / SQ, 0, H / SQ - 1))
			spots[n][sq] = spots[n].get(sq, 0) + 1
	for n in spots:
		var busiest := 0
		var total := 0
		for sq in spots[n]:
			busiest = maxi(busiest, spots[n][sq])
			total += spots[n][sq]
		print("== %s: %d deaths in %d of %d squares" % [LevelScript.name_of(n), total, spots[n].size(), (W / SQ) * (H / SQ)])
		if png_dir != "":
			var out := png_dir.path_join("deaths_%d_server.png" % n)
			_png(LevelScript.new(n), spots[n], busiest, out)
			print("   map: %s" % out)

# The stand-in for a kid: seat 0 plays OLD against 7 bots of this level, on each
# arena, as the server plays a round.
func _kid(level: int, count: int, seed_value: int) -> void:
	var t0 := Time.get_ticks_msec()
	var won := 0
	var draws := 0
	var lives: Array = []
	var lengths: Array = []
	var causes := {}
	var n_rounds := 0
	for n in LevelScript.count():
		var sim = SimScript.new(0, 24, seed_value + 100 * n + level)
		sim.set_arena(n)
		sim.respawn = false
		sim.power_arrows = false
		sim.walls_start = WALLS_AT
		var seats: Array = [{"id": 0, "bot": false, "level": Brain.OLD}]
		for i in range(1, 8):
			seats.append({"id": i, "bot": true, "level": level})
		for r in count:
			sim.start_round(seats)
			sim.frozen = false
			var t := 0
			var died_at := -1
			var kid = sim.fighters[0]
			while t < ROUND_MAX:
				if kid.state != P.F_DEAD:
					Brain.think(sim, kid)   # the person's buttons, from OLD
				sim.step()
				t += 1
				for e in sim.take_events():
					if e[0] == P.E_DEATH and e[3] == 0 and died_at < 0:
						died_at = t
						causes[e[4]] = causes.get(e[4], 0) + 1
				if sim.alive_count() <= 1:
					break
			n_rounds += 1
			lengths.append(t / 60.0)
			lives.append((died_at if died_at >= 0 else t) / 60.0)
			if sim.alive_count() == 1 and sim.last_alive().id == 0:
				won += 1
			elif sim.alive_count() == 0 or t >= ROUND_MAX:
				draws += 1
	lives.sort()
	lengths.sort()
	var deaths := 0
	for k in causes:
		deaths += causes[k]
	var parts: Array = []
	for k in [1, 3, 6]:
		parts.append("%s %d%%" % [P.CAUSES[k], roundi(100.0 * causes.get(k, 0) / maxi(1, deaths))])
	print("== the stand-in for a kid (a person's seat played by OLD) against 7 %s bots, %d rounds on 3 arenas: it won %d (%.1f%%; 1 in 8 is 12.5%%), lived a median %.1f s (p90 %.1f) of rounds a median %.1f s; draws %d%%; it died by %s (%.1f s)" % [
		Brain.NAMES[level], n_rounds, won, 100.0 * won / maxi(1, n_rounds), lives[lives.size() / 2], lives[int(lives.size() * 0.9)],
		lengths[lengths.size() / 2], roundi(100.0 * draws / maxi(1, n_rounds)), ", ".join(parts), (Time.get_ticks_msec() - t0) / 1000.0])

# The reach test: from the middle of every surface to every other, a lone bot.
func _reach(n: int) -> bool:
	var t0 := Time.get_ticks_msec()
	var lv = LevelScript.new(n)
	var rm = Routes.map_for(lv)
	if rm == null:
		print("== the reach test, %s: no route map (run arena_probe.gd -- --write-routes)" % lv.name)
		return false
	var sim = SimScript.new(0, 24, 3000 + n)
	sim.set_arena(n)
	sim.respawn = false
	sim.power_arrows = false
	var tries := 0
	var made := 0
	var times: Array = []
	var failed: Array = []
	for a in rm.surfs.size():
		var cols: Array = rm.surfs[a][1]
		var start := Vector2i(cols[cols.size() / 2] * 30, rm.surfs[a][0] * 30)
		for b in rm.surfs.size():
			if a == b:
				continue
			tries += 1
			sim.start_round([{"id": 0, "bot": true, "level": Brain.NORMAL}])
			var f = sim.fighters[0]
			sim._place(f, start)
			f.wait_t = 0
			f.mind = Brain.Mind.new()
			f.mind.force_goal = b
			var ok := false
			for t in 480:
				sim.step()
				sim.take_events()
				if f.on_ground and f.state == P.F_NORMAL and rm.surface_of(Routes.place_at(f, rm.at)) == b:
					ok = true
					times.append(t / 60.0)
					break
			if ok:
				made += 1
			else:
				failed.append("%s -> %s" % [Routes.surf_name(rm.surfs[a]), Routes.surf_name(rm.surfs[b])])
	times.sort()
	var share := 100.0 * made / maxi(1, tries)
	print("== the reach test, %s: %d of %d trips made it within 8 s (%.1f%%); median %.1f s, the slowest %.1f s (%.1f s)" % [
		lv.name, made, tries, share, times[times.size() / 2] if not times.is_empty() else 0.0, times[-1] if not times.is_empty() else 0.0,
		(Time.get_ticks_msec() - t0) / 1000.0])
	if not failed.is_empty():
		print("   did not make it: %s%s" % ["; ".join(failed.slice(0, 8)), "; ..." if failed.size() > 8 else ""])
	return share >= 95.0

# The catch test: 200 arrows at a bot of this level that stands and only dodges.
func _catch(level: int, seed_value: int) -> void:
	if level == Brain.OLD:
		print("== the catch test: OLD has no catch to test (its dodges are random; the rounds show its catches)")
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var caught := 0
	var killed := 0
	var missed := 0
	var shots := 0
	var tries := 0
	var places: Array = []        # per arena: every place to stand (feet at a cell's left edge)
	for n in LevelScript.count():
		var lv = LevelScript.new(n)
		var list: Array = []
		for r in range(1, LevelScript.ROWS):
			for cx in LevelScript.COLS:
				if lv.stands(Vector2i(cx * 30, r * 30)):
					list.append(Vector2i(cx * 30, r * 30))
		places.append(list)
	while shots < 200 and tries < 20000:
		tries += 1
		var n := shots % LevelScript.count()
		var sim = SimScript.new(0, 24, seed_value + shots)
		sim.set_arena(n)
		sim.respawn = false
		sim.power_arrows = false
		var a: Vector2i = places[n][rng.randi() % places[n].size()]
		var b: Vector2i = places[n][rng.randi() % places[n].size()]
		var d := Vector2(SimScript.wrap_d(a.x, b.x, W), SimScript.wrap_d(a.y, b.y, H)).length()
		if d < 200.0 or d > 600.0:
			continue
		sim.start_round([{"id": 0, "bot": false}, {"id": 1, "bot": true, "level": level}])
		var shooter = sim.fighters[0]
		var bot = sim.fighters[1]
		sim._place(shooter, a)
		sim._place(bot, b)
		bot.wait_t = 0
		bot.mind = Brain.Mind.new()
		bot.mind.only_dodge = true
		for k in 3:
			sim.step()
		var ang := Brain.find_shot(sim, shooter, bot, 0.0)
		if is_nan(ang):
			continue
		shots += 1
		var aim := Brain.aim_steps(ang)
		sim.apply_input(shooter, P.B_SHOOT, aim)
		sim.step()
		sim.take_events()
		sim.apply_input(shooter, 0, aim)
		var fate := ""
		for t in 120:
			sim.step()
			for e in sim.take_events():
				if e[0] == P.E_CATCH and e[3] == 1:
					fate = "caught"
				elif e[0] == P.E_DEATH and e[3] == 1:
					fate = "killed"
			var flying := false
			for ar in sim.arrows:
				if not ar.dead and ar.state == P.S_FLY:
					flying = true
			if fate != "" or not flying:
				break
		if fate == "caught":
			caught += 1
		elif fate == "killed":
			killed += 1
		else:
			missed += 1
	var reached := caught + killed
	print("== the catch test, level %s: %d arrows (200 to 600 px, along a path to it): %d reached the bot, %d caught (%.0f%%; the level's chance %.0f%%), %d killed it; %d missed it" % [
		Brain.NAMES[level], shots, reached, caught, 100.0 * caught / maxi(1, reached), 100.0 * Brain.CATCH[level], killed, missed])

func _rounds(n: int, level: int, count: int, seed_value: int, png_dir: String) -> void:
	var t0 := Time.get_ticks_msec()
	var sim = Timed.new(0, 24, seed_value)
	sim.bot_level = level
	sim.set_arena(n)
	sim.respawn = false
	sim.power_arrows = false
	sim.walls_start = WALLS_AT
	var seats: Array = []
	for i in 8:
		seats.append({"id": i, "bot": true})
	var lengths: Array = []
	var draws := 0
	var causes := {}
	var deaths := 0
	var spots := {}
	var stuck := 0
	var stuck_at := {}
	var shots := 0
	var fates := {"wall": 0, "fighter": 0, "caught": 0, "tink": 0}
	var tracked := {}             # a flying arrow's id -> true, until its fate is known
	var arrow_kills := 0
	var catches := 0
	var pickups := 0
	var none_n := 0
	var low_n := 0
	var alive_n := 0
	var ticks := 0
	var tick_us := 0
	for r in count:
		sim.start_round(seats)
		sim.frozen = false
		var trail := {}
		var stuck_now := {}
		tracked.clear()
		var t := 0
		while t < ROUND_MAX:
			var s0 := Time.get_ticks_usec()
			sim.step()
			tick_us += Time.get_ticks_usec() - s0
			t += 1
			for e in sim.take_events():
				match e[0]:
					P.E_DEATH:
						deaths += 1
						causes[e[4]] = causes.get(e[4], 0) + 1
						var sq := Vector2i(clampi(e[1] / SQ, 0, W / SQ - 1), clampi(e[2] / SQ, 0, H / SQ - 1))
						spots[sq] = spots.get(sq, 0) + 1
						if e[4] == 1:
							arrow_kills += 1
					P.E_SHOOT:
						shots += 1
						for a in sim.arrows:
							if a.owner == e[3] and a.t <= 1 and not tracked.has(a.id):
								tracked[a.id] = true
								break
					P.E_CATCH:
						catches += 1
					P.E_TINK:
						fates["tink"] += 2
						fates["fighter"] -= 2
					P.E_PICKUP:
						pickups += 1
			if not tracked.is_empty():
				var by_id := {}
				for a in sim.arrows:
					if not a.dead:
						by_id[a.id] = a
				for id in tracked.keys():
					var a = by_id.get(id)
					var fate := ""
					if a == null:
						fate = "caught"
					elif a.state == P.S_STUCK:
						fate = "wall"
					elif a.state == P.S_FALL:
						fate = "fighter"
					if fate != "":
						fates[fate] += 1
						tracked.erase(id)
			if t % 10 == 0:
				for f in sim.fighters:
					if f.state != P.F_DEAD:
						alive_n += 1
						if f.arrows == 0:
							none_n += 1
						if f.arrows < 2:
							low_n += 1
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
							var at := Vector2i(int(lo.x + hi.x + 36) / 240, int(lo.y + hi.y + 63) / 240)
							stuck_at[at] = stuck_at.get(at, 0) + 1
			if sim.alive_count() <= 1:
				break
		ticks += t
		stuck += stuck_now.size()
		lengths.append(t / 60.0)
		if sim.alive_count() == 0 or t >= ROUND_MAX:
			draws += 1
	lengths.sort()
	print("== layout %d %s, level %s: %d rounds of 8 bots" % [n, LevelScript.name_of(n), Brain.NAMES[level], count])
	print("   rounds: length median %.1f s, p90 %.1f s, longest %.1f s; draws %d%%" % [
		lengths[count / 2], lengths[int(count * 0.9)], lengths[-1], roundi(100.0 * draws / count)])
	var parts: Array = []
	for k in [1, 3, 6]:
		parts.append("%s %d%%" % [P.CAUSES[k], roundi(100.0 * causes.get(k, 0) / maxi(1, deaths))])
	var per_sq: Array = spots.values()
	per_sq.sort()
	per_sq.reverse()
	var busiest: int = per_sq[0] if not per_sq.is_empty() else 0
	var top := 0
	for k in mini(15, per_sq.size()):
		top += per_sq[k]
	print("   deaths: %s; death spots %d of %d squares, the busiest 15 squares hold %.0f%% of the deaths" % [
		", ".join(parts), spots.size(), (W / SQ) * (H / SQ), 100.0 * top / maxi(1, deaths)])
	var where: Array = []
	var sqs := stuck_at.keys()
	sqs.sort_custom(func(a, b): return stuck_at[a] > stuck_at[b])
	for sq in sqs.slice(0, 3):
		where.append("%d at (%d, %d)" % [stuck_at[sq], sq.x * 120 + 60, sq.y * 120 + 60])
	print("   stuck 5 s: %d of %d bot rounds%s" % [stuck, count * 8, "" if where.is_empty() else " (" + ", ".join(where) + ")"])
	print("   shots: %d (%.1f a round): %d%% with a wall between the bot and its target; an arrow kill every %.1f shots; caught %d (%.1f%%)" % [
		shots, float(shots) / count, roundi(100.0 * sim.walled / maxi(1, sim.shots_seen)), float(shots) / maxi(1, arrow_kills), catches,
		100.0 * catches / maxi(1, shots)])
	var known: int = fates["wall"] + fates["fighter"] + fates["caught"] + fates["tink"]
	print("   the arrows: %d%% stuck in a block or a ledge before reaching anyone, %d%% reached a fighter, %d%% caught, %d%% met another arrow" % [
		roundi(100.0 * fates["wall"] / maxi(1, known)), roundi(100.0 * fates["fighter"] / maxi(1, known)),
		roundi(100.0 * fates["caught"] / maxi(1, known)), roundi(100.0 * fates["tink"] / maxi(1, known))])
	print("   arrows: a bot has none %d%% of its time alive, fewer than 2 %d%%; %.1f pickups a round" % [roundi(100.0 * none_n / maxi(1, alive_n)),
		roundi(100.0 * low_n / maxi(1, alive_n)), float(pickups) / count])
	print("   cost: a tick %.3f ms, the brains %.3f ms of it (%.0f%%), over %d ticks" % [
		tick_us / 1000.0 / maxi(1, ticks), sim.brain_us / 1000.0 / maxi(1, ticks), 100.0 * sim.brain_us / maxi(1, tick_us), ticks])
	if png_dir != "":
		var path := png_dir.path_join("deaths_%d_%s.png" % [n, Brain.NAMES[level].to_lower()])
		_png(sim.level, spots, busiest, path)
		print("   map: %s" % path)
	print("   (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))

func _png(lv, spots: Dictionary, busiest: int, path: String) -> void:
	var img := Image.create(W / 2, H / 2, false, Image.FORMAT_RGBA8)
	img.fill(Color("1b2233"))
	for sq in spots:
		var k: float = float(spots[sq]) / maxi(1, busiest)
		img.fill_rect(Rect2i(sq.x * SQ / 2, sq.y * SQ / 2, SQ / 2, SQ / 2), Color(0.25 + 0.75 * k, 0.12, 0.12))
	for cy in LevelScript.ROWS:
		for cx in LevelScript.COLS:
			var c: int = lv.cell(cx, cy)
			if c == LevelScript.SOLID:
				img.fill_rect(Rect2i(cx * 15, cy * 15, 15, 15), Color("8a93a8"))
			elif c == LevelScript.LEDGE:
				img.fill_rect(Rect2i(cx * 15, cy * 15, 15, 5), Color("e0a040"))
	img.save_png(path)

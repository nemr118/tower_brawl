# p4.19 the balance check (the user: "a fun, balanced, silly game"). Bots play hundreds of
# whole rounds on every arena, with 8, 4 and 2 fighters (the family mostly plays 2 to 4),
# and this counts who wins and why:
#   - by START SPOT: does one spot win far more than its share? (the spots are shuffled each round)
#   - by POWER-UP: how often does the fighter who took it win the round, next to all who took any?
#   - THE BIG TURKEY (the costume), the turkey's catcher, a fighter who starts with a SHIELD
#     (the catch-up help): their share of wins next to a fair share
#   - how the knockouts happen, how long a round lasts, how many end in a draw.
# Bots are not people: read the numbers as "is anything far off", not to the percent.
#   godot --headless --path bench --script res://tools/balance_probe.gd -- --rounds=300 [--season=harvest] [--sizes=8,4,2] [--arenas=1,2,5,6] [--level=2]
extends SceneTree

const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const P = preload("res://sim/proto.gd")
const CAUSES := {1: "an arrow", 2: "a blast", 3: "a stomp", 4: "fire", 5: "poison", 6: "the walls", 7: "lightning", 8: "a ghost cat",
	9: "spikes", 10: "a swarm", 11: "a knife or peck", 12: "a furnace", 13: "steam"}

var rounds := 300
var season := "harvest"
var sizes: Array = [8, 4, 2]
var arenas: Array = []
var level := 2
var total := {}          # the sum over every arena, by size

func _say(s: String) -> void:
	print("⚖️ [Balance] " + s)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
		elif a.begins_with("--season="):
			season = a.substr(9)
		elif a.begins_with("--sizes="):
			sizes = Array(a.substr(8).split(",")).map(func(v): return int(v))
		elif a.begins_with("--arenas="):
			arenas = Array(a.substr(9).split(",")).map(func(v): return int(v))
		elif a.begins_with("--level="):
			level = int(a.substr(8))
	if arenas.is_empty():
		arenas = LevelScript.PLAY.duplicate()
	_say("%d rounds a line, the season '%s', bots at level %d" % [rounds, season, level])
	for n in sizes:
		total[n] = _blank()
		for arena in arenas:
			var r := _run(arena, n, 0)
			_line(r, n)
			_add(total[n], r)
		_powers(total[n], n)
	for n in sizes:
		if n < 3:
			continue
		var sh := _blank()
		for arena in arenas:
			_add(sh, _run(arena, n, 1))
		_say("%d fighters, one starts with a SHIELD (the catch-up help): it wins %.0f%% of rounds (a fair share: %.0f%%)" % [
			n, 100.0 * sh["f0_wins"] / maxf(1.0, sh["rounds"]), 100.0 / n])
	quit()

func _blank() -> Dictionary:
	return {"rounds": 0, "draws": 0, "secs": [], "spot_wins": {}, "spot_starts": {}, "got": {}, "won": {}, "any_got": 0, "any_won": 0,
		"mask": 0, "mask_won": 0, "bird": 0, "bird_won": 0, "causes": {}, "f0_wins": 0, "name": "", "pied": 0}

func _add(t: Dictionary, r: Dictionary) -> void:
	for k in ["rounds", "draws", "any_got", "any_won", "mask", "mask_won", "bird", "bird_won", "f0_wins", "pied"]:
		t[k] += r[k]
	for k in ["got", "won", "causes"]:
		for key in r[k]:
			t[k][key] = int(t[k].get(key, 0)) + int(r[k][key])

# rounds whole rounds of n bots on one arena. shield 1: fighter 0 starts every round with a SHIELD.
func _run(arena: int, n: int, shield: int) -> Dictionary:
	var s = SimScript.new(0, 24, 4000 + arena * 10 + n + shield * 7)
	s.respawn = false
	s.powerups = true
	s.season = season
	s.bot_level = level
	s.walls_start = 25 * 60       # the purple walls, as the server sets them
	s.set_arena(arena)
	var out := _blank()
	out["name"] = s.level.name
	for r in rounds:
		var list := []
		for i in n:
			list.append({"id": i, "bot": true})
		s.reset_powers()
		s.start_round(list)
		s.frozen = false
		if shield == 1:
			s._give(s.fighters[0], P.PU_SHIELD)
		var spot := {}
		for f in s.fighters:
			var feet := Vector2(f.x + SimScript.HALF_W, f.y + SimScript.BODY_H)
			var best := 0
			for k in s.level.spawns.size():
				if feet.distance_to(Vector2(s.level.spawns[k])) < feet.distance_to(Vector2(s.level.spawns[best])):
					best = k
			spot[f.id] = best
			out["spot_starts"][best] = int(out["spot_starts"].get(best, 0)) + 1
		var first := {}           # each fighter's first power-up this round
		var masked := {}
		var birder := {}
		var t := 0
		s.take_events()
		while s.alive_count() > 1 and t < 3600:
			t += 1
			s.step()
			for e in s.take_events():
				if e[0] == P.E_PU_GET and not first.has(e[3]):
					first[e[3]] = e[4]
				elif e[0] == P.E_TRICK and e[4] == 4:
					masked[e[3]] = true
				elif e[0] == P.E_PET and e[4] == 1:
					birder[e[3]] = true
				elif e[0] == P.E_PIED:
					out["pied"] += 1
				elif e[0] == P.E_DEATH:
					out["causes"][e[4]] = int(out["causes"].get(e[4], 0)) + 1
		out["rounds"] += 1
		out["secs"].append(t / 60.0)
		var winner := -1
		if s.alive_count() == 1:
			for f in s.fighters:
				if f.state != P.F_DEAD:
					winner = f.id
		if winner < 0:
			out["draws"] += 1
		else:
			out["spot_wins"][spot[winner]] = int(out["spot_wins"].get(spot[winner], 0)) + 1
			if winner == 0:
				out["f0_wins"] += 1
		for id in first:
			var k: int = first[id]
			out["got"][k] = int(out["got"].get(k, 0)) + 1
			out["any_got"] += 1
			if id == winner:
				out["won"][k] = int(out["won"].get(k, 0)) + 1
				out["any_won"] += 1
		for id in masked:
			out["mask"] += 1
			if id == winner:
				out["mask_won"] += 1
		for id in birder:
			out["bird"] += 1
			if id == winner:
				out["bird_won"] += 1
	return out

# One arena's line: the round's length, the draws, and the start spots that win most and least
# (as a share of the rounds a fighter started there).
func _line(r: Dictionary, n: int) -> void:
	var secs: Array = r["secs"]
	secs.sort()
	var rates: Array = []
	for k in r["spot_starts"]:
		var st := int(r["spot_starts"][k])
		rates.append([100.0 * int(r["spot_wins"].get(k, 0)) / maxf(1.0, st), k, st])
	rates.sort_custom(func(a, b): return a[0] > b[0])
	var fair: float = 100.0 * (r["rounds"] - r["draws"]) / maxf(1.0, r["rounds"]) / n
	# how far the best spot is from a fair share, in standard errors (over 3: a real edge, not luck)
	var top: Array = rates[0]
	var se := sqrt(fair * (100.0 - fair) / maxf(1.0, top[2]))
	var low: Array = rates[rates.size() - 1]
	_say("%-18s %d fighters: a round %.1f s (9 in 10 under %.1f s), draws %.0f%%; a fair share %.1f%%; the best spot %d wins %.1f%% (%.1f errors over), the worst spot %d %.1f%%" % [
		r["name"], n, secs[secs.size() / 2], secs[int(secs.size() * 0.9)], 100.0 * r["draws"] / maxf(1.0, r["rounds"]), fair,
		top[1], top[0], (top[0] - fair) / maxf(0.01, se), low[1], low[0]])

# Every arena together: each power-up's taker (the first one a fighter takes in a round), the
# costume, the turkey's catcher; and how the knockouts happened.
func _powers(t: Dictionary, n: int) -> void:
	var base: float = 100.0 * t["any_won"] / maxf(1.0, t["any_got"])
	_say("%d fighters, every arena: a fighter who takes any power-up wins %.1f%% of its rounds (a fair share %.1f%%). By the first one taken:" % [n, base, 100.0 / n])
	var keys: Array = t["got"].keys()
	keys.sort()
	for k in keys:
		var got := int(t["got"][k])
		if got < 20:
			continue
		var rate := 100.0 * int(t["won"].get(k, 0)) / got
		var se := sqrt(base * (100.0 - base) / got)
		var mark := ""
		if absf(rate - base) > 3.0 * se:
			mark = "   <-- far from the rest"
		_say("    %-14s taken %4d times, its taker wins %5.1f%%%s" % [P.pu_short(k, season), got, rate, mark])
	if t["mask"] > 0:
		_say("    the costume (%s): %d times, its wearer wins %.1f%%" % [P.pu_short(P.PU_MASK, season), t["mask"], 100.0 * t["mask_won"] / t["mask"]])
	if t["bird"] > 0:
		_say("    the turkey's catcher: %d times, wins %.1f%%" % [t["bird"], 100.0 * t["bird_won"] / t["bird"]])
	var all := 0
	for k in t["causes"]:
		all += int(t["causes"][k])
	var parts: Array = []
	var ck: Array = t["causes"].keys()
	ck.sort_custom(func(a, b): return int(t["causes"][a]) > int(t["causes"][b]))
	for k in ck:
		parts.append("%s %.0f%%" % [CAUSES.get(k, "cause %d" % k), 100.0 * int(t["causes"][k]) / maxf(1.0, all)])
	_say("    knockouts: %s; creamed by a pie %d times" % [", ".join(parts), t["pied"]])

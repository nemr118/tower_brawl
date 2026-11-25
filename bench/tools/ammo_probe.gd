# p4.20 the classes study (docs/reference/classes-scope.md; the user: "Archer ammo is a concern.
# I love the pick up ammo mechanic, if we add a melee character, how does that impact ammo
# recovery?"). Bots play whole rounds and this counts the arrows: how many an archer shoots
# and picks up, how much of its time its quiver is empty, how many arrows lie around to be
# fetched, and who wins, in a plain match and in matches where some fighters are melee
# fighters. The melee fighter here is the costume (THE BIG TURKEY / GHOSTFACE: no bow, a
# short swing, a hit knocks it down, a second ends it): the one melee fighter the game has.
#   godot --headless --path bench --script res://tools/ammo_probe.gd -- --rounds=300
extends SceneTree

const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const P = preload("res://sim/proto.gd")

var rounds := 300

func _say(s: String) -> void:
	print("🏹 [Ammo] " + s)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
	_say("%d rounds a line on the four Harvest arenas, bots at NORMAL, no power-up orbs and no dishes (the arrows alone)" % rounds)
	_say("-- the plain game: how the quiver's size changes it")
	for q in [2, 3, 4, 5]:
		_run(4, 0, q, false, "4 archers, each starts with %d" % q)
	for q in [3, 4]:
		_run(8, 0, q, false, "8 archers, each starts with %d" % q)
	_run(2, 0, 3, false, "2 archers, each starts with 3")
	_say("-- melee fighters among them (a melee fighter holds no bow)")
	for cfg in [[4, 1], [4, 2], [8, 2], [8, 4]]:
		_run(cfg[0], cfg[1], 3, false, "%d fighters, %d melee; melee picks arrows up (and can do nothing with them)" % cfg)
		_run(cfg[0], cfg[1], 3, true, "%d fighters, %d melee; melee leaves arrows where they lie" % cfg)
	quit()

# n fighters, the first `melee` of them in the costume; every archer starts with `quiver` arrows.
func _run(n: int, melee: int, quiver: int, no_pick: bool, what: String) -> void:
	var t := {"rounds": 0, "ticks": 0, "arch_ticks": 0, "dry_ticks": 0, "shots": 0, "dry": 0, "picks": 0, "catches": 0, "lying": 0,
		"sunk": 0, "arch_wins": 0, "melee_wins": 0, "draws": 0, "secs": [], "arch_n": 0}
	for arena in LevelScript.mix_for("harvest"):
		var s = SimScript.new(0, 24, 5100 + arena * 13 + n * 3 + melee * 7 + quiver)
		s.respawn = false
		s.powerups = false
		s.season = "harvest"
		s.candy_drop = 0.0
		s.candy_t = 999999
		s.walls_start = 25 * 60
		s.start_quiver = quiver
		s.melee_no_pickup = no_pick
		s.set_arena(arena)
		for r in rounds / 4:
			var list := []
			for i in n:
				list.append({"id": i, "bot": true})
			s.reset_powers()
			s.start_round(list)
			for i in melee:
				s.fighters[i].mask = true
				s.fighters[i].arrows = 0          # a melee fighter brings no arrows to the round
			s.frozen = false
			s.take_events()
			var ticks := 0
			while s.alive_count() > 1 and ticks < 3600:
				ticks += 1
				s.step()
				for f in s.fighters:
					if f.state != P.F_DEAD and not f.mask:
						t["arch_ticks"] += 1
						if f.arrows == 0:
							t["dry_ticks"] += 1
				var lying := 0
				for a in s.arrows:
					if not a.dead and (a.state == P.S_STUCK or a.state == P.S_BODY):
						lying += 1
				t["lying"] += lying
				for e in s.take_events():
					if e[0] == P.E_SHOOT:
						t["shots"] += 1
					elif e[0] == P.E_DRYFIRE:
						t["dry"] += 1
					elif e[0] == P.E_PICKUP and e[3] >= melee:
						t["picks"] += 1
					elif e[0] == P.E_CATCH and e[3] >= melee:
						t["catches"] += 1
			t["rounds"] += 1
			t["ticks"] += ticks
			t["arch_n"] += n - melee
			t["secs"].append(ticks / 60.0)
			for i in melee:
				t["sunk"] += s.fighters[i].arrows
			var winner := -1
			if s.alive_count() == 1:
				for f in s.fighters:
					if f.state != P.F_DEAD:
						winner = f.id
			if winner < 0:
				t["draws"] += 1
			elif winner < melee:
				t["melee_wins"] += 1
			else:
				t["arch_wins"] += 1
	var secs: Array = t["secs"]
	secs.sort()
	var an: float = maxf(1.0, t["arch_n"])
	var line := "%s: a round %.1f s (9 in 10 under %.1f); an archer shoots %.1f and fetches %.1f a round, catches %.2f; its quiver is empty %.0f%% of its time (%.2f empty pulls a round); %.1f arrows lie around on average" % [
		what, secs[secs.size() / 2], secs[int(secs.size() * 0.9)], t["shots"] / an, t["picks"] / an, t["catches"] / an,
		100.0 * t["dry_ticks"] / maxf(1.0, t["arch_ticks"]), t["dry"] / an, float(t["lying"]) / maxf(1.0, t["ticks"])]
	if melee > 0:
		line += "; a melee fighter ends a round holding %.1f arrows; wins: each melee fighter %.0f%%, each archer %.0f%% (a fair share %.0f%%)" % [
			float(t["sunk"]) / (t["rounds"] * melee), 100.0 * t["melee_wins"] / t["rounds"] / melee,
			100.0 * t["arch_wins"] / t["rounds"] / (n - melee), 100.0 / n]
	_say(line)

# p4.20 the classes study (docs/reference/classes-scope.md): what is a perk worth? One fighter
# of four (or of eight) gets a kit every round, the others are plain archers, all bots at
# NORMAL; its share of round wins beside a fair share is the kit's price. The kits here are
# made of things the game already has (a SHIELD at the start, a bigger or smaller quiver, big
# arrows, wings, speed, the costume as a melee fighter), so nothing new had to be built to
# measure them. Bots are not people: read "far over" and "far under", not the last percent.
#   godot --headless --path bench --script res://tools/kit_probe.gd -- --rounds=400 [--n=4]
extends SceneTree

const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const P = preload("res://sim/proto.gd")
const KITS := ["plain (the control)", "starts with a SHIELD", "starts with 1 arrow", "starts with 2 arrows", "starts with 5 arrows",
	"a quiver that never empties", "big arrows", "wings (flies all round)", "runs 1.6 times as fast all round",
	"2 arrows and a SHIELD", "5 arrows, no dodge-catch help: slower (not built)", "melee: the costume as it is (a hit knocks it down, a second ends it)",
	"melee, out at the first hit", "melee, out at the first hit, with a SHIELD", "melee, out at the first hit, runs 1.6 times as fast"]

var rounds := 400
var n := 4

func _say(s: String) -> void:
	print("🎒 [Kit] " + s)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
		elif a.begins_with("--n="):
			n = int(a.substr(4))
	_say("%d rounds a kit, %d fighters (one has the kit), the four Harvest arenas, power-up orbs and dishes on as in a real match; a fair share is %.1f%%" % [rounds, n, 100.0 / n])
	for k in KITS.size():
		if "(not built)" in KITS[k]:
			continue
		_run(k)
	quit()

func _kit(s, f, k: int) -> void:
	match k:
		1:
			f.shield = 1
		2:
			f.arrows = 1
		3:
			f.arrows = 2
		4:
			f.arrows = 5
		5:
			f.inf = true
		6:
			f.big = true
		7:
			f.fly = true
		8:
			f.speed_t = 100000
		9:
			f.arrows = 2
			f.shield = 1
		11, 12, 13, 14:
			f.mask = true
			f.arrows = 0
			if k == 13:
				f.shield = 1
			if k == 14:
				f.speed_t = 100000

func _run(k: int) -> void:
	var wins := 0
	var played := 0
	var secs: Array = []
	var kos := 0
	for arena in LevelScript.mix_for("harvest"):
		var s = SimScript.new(0, 24, 6200 + arena * 11 + k * 5 + n)
		s.respawn = false
		s.powerups = true
		s.season = "harvest"
		s.walls_start = 25 * 60
		s.melee_one_hit = k >= 12
		s.set_arena(arena)
		for r in rounds / 4:
			var list := []
			for i in n:
				list.append({"id": i, "bot": true})
			s.reset_powers()
			s.start_round(list)
			_kit(s, s.fighters[0], k)
			s.frozen = false
			s.take_events()
			var t := 0
			while s.alive_count() > 1 and t < 3600:
				t += 1
				s.step()
				for e in s.take_events():
					if e[0] == P.E_KILL and e[3] == 0 and e[4] != 0:
						kos += 1
			played += 1
			secs.append(t / 60.0)
			if s.alive_count() == 1 and s.fighters[0].state != P.F_DEAD:
				wins += 1
	secs.sort()
	var share := 100.0 * wins / played
	var fair := 100.0 / n
	var se := sqrt(fair * (100.0 - fair) / played)
	_say("%-72s wins %5.1f%% (%+5.1f, %+.1f errors); %.2f knockouts a round; a round %.1f s" % [KITS[k], share, share - fair, (share - fair) / se,
		float(kos) / played, secs[secs.size() / 2]])

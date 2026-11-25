# TEAMS must not change FREE FOR ALL. This tool proves it: it plays whole rounds with
# fixed seeds (bots, and "people" pressed by a script), and prints one number per line
# that sums up everything that happened: every event of every tick, where every fighter
# ended, and where the sim's random numbers stand at the end. One extra random number
# drawn, or one fighter one pixel off, and a line's number changes.
# Run it on the old code and on the new code: the two outputs must be the same, byte
# for byte.
#   godot --headless --path bench --script res://tools/ffa_hash.gd -- [--rounds=12]
# It reads nothing but the sim, so the same file runs on the code from before TEAMS.
extends SceneTree

const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const P = preload("res://sim/proto.gd")

var rounds := 12

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.substr(9))
	var all := 0
	var lines := 0
	for arena in LevelScript.count():
		for season in ["harvest", "halloween", ""]:
			for n in [8, 4, 3, 2]:
				var h := _run(arena, season, n)
				all = hash([all, h])
				lines += 1
				print("ffa_hash arena %d season '%s' fighters %d: %d" % [arena, season, n, h])
	print("ffa_hash ALL %d lines, %d rounds each: %d" % [lines, rounds, all])
	quit()

# rounds whole rounds on one arena: the number that sums them up.
func _run(arena: int, season: String, n: int) -> int:
	var s = SimScript.new(0, 24, 9000 + arena * 100 + n * 7 + season.length())
	s.respawn = false
	s.powerups = true
	s.season = season
	s.walls_start = 25 * 60
	s.set_arena(arena)
	var pad := RandomNumberGenerator.new()      # the "people's" thumbs: its own numbers, never the sim's
	pad.seed = 77 + arena * 13 + n
	var h := 0
	for r in rounds:
		s.bot_level = 1 + r % 3
		# seats 0 and 1 are people in two rounds of three (their ghosts, the aim help, the catch-up)
		var list := []
		for i in n:
			list.append({"id": i, "bot": not (i < 2 and r % 3 != 0)})
		if r == 0:
			s.reset_powers()
		s.start_round(list)
		for f in s.fighters:
			f.points = (f.id * 5 + r) % 4       # someone leads, someone is 2 behind: BIG orbs, the SHIELD
		s.catch_up()
		s.frozen = false
		var held := {}                           # seat -> [buttons, aim, ticks left]
		var t := 0
		var called := -1                         # the tick the round was called (the winner is safe from then)
		while t < 3600 and (called < 0 or t - called < 90):
			t += 1
			for f in s.fighters:
				if f.bot:
					continue
				var k: Array = held.get(f.id, [0, 0, 0])
				if k[2] <= 0:
					k = [_buttons(pad), pad.randi_range(0, 3599), pad.randi_range(4, 30)]
				k[2] -= 1
				held[f.id] = k
				s.apply_input(f, k[0], k[1])
			s.step()
			for e in s.take_events():
				h = hash([h, e[0], e[1], e[2], e[3], e[4]])
			if called < 0 and s.alive_count() <= 1:
				called = t
				s.safe = s.last_alive().id if s.alive_count() == 1 else -1    # as the server does
		for f in s.fighters:
			h = hash([h, f.id, f.x, f.y, f.state, f.arrows, f.shield, f.pw_kind])
		h = hash([h, t, s.arrows.size(), s.zones.size(), s.rng.state])
	return h

# A person's buttons for the next moment: runs, jumps, dodges, draws the bow and lets go.
func _buttons(pad: RandomNumberGenerator) -> int:
	var b := 0
	var r := pad.randi_range(0, 9)
	if r < 4:
		b |= P.B_LEFT if pad.randf() < 0.5 else P.B_RIGHT
	if pad.randf() < 0.3:
		b |= P.B_JUMP
	if pad.randf() < 0.12:
		b |= P.B_DODGE
	if pad.randf() < 0.1:
		b |= P.B_DOWN
	if pad.randf() < 0.45:
		b |= P.B_SHOOT
	return b

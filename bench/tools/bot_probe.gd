# The bot probe (G6, server bots): measures the bot brain offline, on each arena
# of sim/level.gd. No server, no drawing.
#   godot --headless --path bench --script res://tools/bot_probe.gd -- [--layout=N] [--rounds=N] [--png=DIR] [--seed=N]
# Rounds of 8 bots, as the server plays them (one life, the purple walls at 25 s,
# the 60 s backstop, plain arrows): how long they last, draws, how the bots die
# and where (the death spots: how many of the 144 squares of 120 px see a death,
# and the share of the deaths in the busiest 15, a tenth of them),
# bots stuck 5 s (inside a 90 px square while alive, once a round per bot).
# Shots: how many had a wall between the bot and the nearest enemy when it shot
# (a straight line from the bow to the enemy's middle crosses a block), and how
# many arrows killed or were caught. Arrows: the share of time a bot has none,
# and pickups a round. Cost: the brains' share of a tick.
# --png DIR: a death-spot map per arena (deaths_N.png): blocks grey, ledges amber,
# each square of 120 px red by its share of the deaths.
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")

const W := 1920
const H := 1080
const SQ := 120                   # a death-spot square: 16 x 9 of them
const ROUND_MAX := 3600           # the server's 60 s backstop
const WALLS_AT := 25 * 60         # the server's purple walls

# The sim with a stopwatch on the brain (the same hook as tools/sim_prof.gd).
class Timed extends "res://sim/sim.gd":
	var brain_us := 0
	func _brain(f: Fighter) -> void:
		var t := Time.get_ticks_usec()
		super._brain(f)
		brain_us += Time.get_ticks_usec() - t

func _init() -> void:
	var only := -1
	var rounds := 100
	var png_dir := ""
	var seed_value := 2000
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--layout="):
			only = int(a.get_slice("=", 1))
		elif a.begins_with("--rounds="):
			rounds = maxi(1, int(a.get_slice("=", 1)))
		elif a.begins_with("--png="):
			png_dir = a.get_slice("=", 1)
		elif a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
	if png_dir != "":
		DirAccess.make_dir_recursive_absolute(png_dir)
	for n in LevelScript.count():
		if only < 0 or n == only:
			_rounds(n, rounds, seed_value + n, png_dir)
	quit(0)

func _rounds(n: int, count: int, seed_value: int, png_dir: String) -> void:
	var t0 := Time.get_ticks_msec()
	var sim = Timed.new(0, 24, seed_value)
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
	var walled := 0
	var arrow_kills := 0
	var catches := 0
	var pickups := 0
	var none_n := 0
	var alive_n := 0
	var ticks := 0
	var tick_us := 0
	for r in count:
		sim.start_round(seats)
		sim.frozen = false
		var trail := {}
		var stuck_now := {}
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
						if _wall_between(sim, sim.fighter(e[3])):
							walled += 1
					P.E_CATCH:
						catches += 1
					P.E_PICKUP:
						pickups += 1
			if t % 10 == 0:
				for f in sim.fighters:
					if f.state != P.F_DEAD:
						alive_n += 1
						if f.arrows == 0:
							none_n += 1
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
	print("== layout %d %s: %d rounds of 8 bots (the brain as it is)" % [n, LevelScript.name_of(n), count])
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
	print("   shots: %d (%.1f a round): %d%% with a wall between the bot and the nearest enemy; an arrow kill every %.1f shots; caught %d (%.1f%%)" % [
		shots, float(shots) / count, roundi(100.0 * walled / maxi(1, shots)), float(shots) / maxi(1, arrow_kills), catches,
		100.0 * catches / maxi(1, shots)])
	print("   arrows: a bot has none %d%% of its time alive; %.1f pickups a round" % [roundi(100.0 * none_n / maxi(1, alive_n)), float(pickups) / count])
	print("   cost: a tick %.3f ms, the brains %.3f ms of it (%.0f%%), over %d ticks" % [
		tick_us / 1000.0 / maxi(1, ticks), sim.brain_us / 1000.0 / maxi(1, ticks), 100.0 * sim.brain_us / maxi(1, tick_us), ticks])
	if png_dir != "":
		var path := png_dir.path_join("deaths_%d.png" % n)
		_png(sim.level, spots, busiest, path)
		print("   map: %s" % path)
	print("   (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))

# A wall between the shooter and the nearest enemy (the one the old brain aims
# at): the straight line from the bow to the enemy's middle crosses a block.
func _wall_between(sim, f) -> bool:
	if f == null:
		return false
	var o = SimScript.BrainScript.nearest_enemy(sim, f)
	if o == null:
		return false
	var ox := float(f.x + SimScript.HALF_W)
	var oy := float(f.y + SimScript.ARROW_Y)
	var dx := SimScript.wrap_d(ox, o.x + SimScript.HALF_W, W)
	var dy := SimScript.wrap_d(oy, o.y + SimScript.MID_Y, H)
	return sim._line_blocked(ox, oy, dx, dy)

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

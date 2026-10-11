# The arena probe (G5, the super arena): the clever-ledges rules of
# docs/reference/v0.2-transformation-plan.md (section 3) as checks, for each
# layout in sim/level.gd. Offline: no server, no drawing.
#   godot --headless --path bench --script res://tools/arena_probe.gd -- [--layout=N] [--png=DIR] [--rounds=N] [--quick] [--list]
#       [--write-routes]
# Spawn fairness: no spawn spot has a clear straight shot at another within
# 600 px (through the wrap too; a block stops the line, a ledge only from above,
# the way an arrow sticks); each spot stands with room for the body, and none
# sits one drop above another (input_probe rule 27's test).
# The routes: a surface is a floor or a ledge (a run of places to stand on one
# row). From its places (every second one, and both ends) the sim's own movement
# runs a set of moves (walks off the edge, tapped and held jumps with steering,
# run-up jumps, drops through a ledge, wall jumps, ledge grabs, dodges) and
# records where each one lands. Every surface must be reachable from every other
# (no dead ends), each must be left at least two ways, and the wrap must carry
# routes both ways sideways and down. Balance: as many spawn spots left as right,
# the blocks and ledges per half within 10%, and not a perfect mirror.
# --rounds N: N rounds of 8 bots on the layout (one life, the purple walls at
# 25 s, the bots' brain as it is): length, draws, how they die, stuck bots.
# --png DIR: a flat map per layout (arena_N.png): blocks grey, ledges amber,
# surfaces green (plain moves reach them), cyan (only a wall jump or a dodge),
# red (a dead end), spawn spots white with their number, clear shots red lines.
# --write-routes: instead of the checks, run every move from every place of every
# arena (from the five starts of Routes.STURDY: a move counts when all of them land
# on the same surface, and stop there once it lets go) and keep the fastest move from each place to each other
# surface in sim/routes.json, with each arena's grid hash and the moves' hash (the bot brain
# replays them, G6; input_probe fails when an arena or the moves changed and the
# file did not).
# Exits 1 when a layout other than the bench arena fails a rule (the bench
# arena, layout 0, is the test arena: reported, never a fail).
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const Routes = preload("res://sim/routes.gd")

const COLS := 64
const ROWS := 36
const W := 1920
const H := 1080
const SHOT_RANGE := 600.0
const BOW_UP := 35                # the arrow leaves the body 28 px below its top (sim ARROW_Y): 35 px above the feet
const AIM_POINTS := [Vector2(0, -55), Vector2(0, -32), Vector2(0, -8), Vector2(-14, -32), Vector2(14, -32)]
const WRAP_NAMES := ["right", "left", "down", "up"]
const DIGITS := ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"]

var fails := 0
var quick := false
var list := false

func _init() -> void:
	var only := -1
	var png_dir := ""
	var rounds := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--layout="):
			only = int(a.get_slice("=", 1))
		elif a.begins_with("--png="):
			png_dir = a.get_slice("=", 1)
		elif a.begins_with("--rounds="):
			rounds = int(a.get_slice("=", 1))
		elif a == "--quick":
			quick = true
		elif a == "--list":
			list = true
		elif a == "--write-routes":
			_write_routes()
			return
	if png_dir != "":
		DirAccess.make_dir_recursive_absolute(png_dir)
	for n in LevelScript.count():
		if only < 0 or n == only:
			_probe(n, png_dir, rounds)
	if fails == 0:
		print("✅ arena_probe: every rule passed")
		quit(0)
	else:
		printerr("❌ arena_probe: %d rule(s) failed" % fails)
		quit(1)

func _write_routes() -> void:
	var t0 := Time.get_ticks_msec()
	var arenas: Array = []
	var edges_n := 0
	for n in LevelScript.count():
		var lv = LevelScript.new(n)
		var sim = SimScript.new(0, 24, 7)
		sim.set_arena(n)
		sim.respawn = false
		sim.power_arrows = false
		var all: Dictionary = Routes.run_all(lv, sim, 1, false, Routes.STURDY, true)
		var flat := Routes.keep_fastest(lv, all["results"], all["sf"]["surfs"])
		edges_n += flat.size() / 7
		arenas.append({"id": n, "name": lv.name, "grid": Routes.grid_hash(lv), "edges": Array(flat)})
		print("   %s: %d places, %d moves run, %d edges kept" % [lv.name, all["places"], all["runs"], flat.size() / 7])
	var data := {"version": Routes.FILE_VERSION, "moves": Routes.moves_hash(), "made_by": "tools/arena_probe.gd --write-routes", "arenas": arenas}
	var path := ProjectSettings.globalize_path(Routes.FILE)
	var fa := FileAccess.open(path, FileAccess.WRITE)
	fa.store_string(JSON.stringify(data))
	fa.close()
	print("✅ arena_probe: %s written: %d arenas, %d edges, %d bytes (%.1f s)" % [Routes.FILE, arenas.size(), edges_n,
		FileAccess.get_file_as_bytes(path).size(), (Time.get_ticks_msec() - t0) / 1000.0])
	quit(0)

func _rule(bench: bool, name: String, ok: bool, detail: String) -> void:
	if not ok and not bench:
		fails += 1
	print("%s %s: %s" % ["PASS" if ok else ("FAIL (the test arena, reported)" if bench else "FAIL"), name, detail])

func _probe(n: int, png_dir: String, rounds: int) -> void:
	var t0 := Time.get_ticks_msec()
	var lv = LevelScript.new(n)
	var bench: bool = n == LevelScript.BENCH
	print("== layout %d %s: %d spawn spots, %d torches" % [n, lv.name, lv.spawns.size(), lv.torches.size()])
	# spawn fairness
	var shots := _clear_shots(lv)
	var pairs: Array = []
	for s in shots:
		pairs.append("%d and %d (%d px)" % [s[0], s[1], roundi(s[2])])
	_rule(bench, "no spawn spot has a clear shot at another within 600 px", shots.is_empty(),
		"%d spots, %s" % [lv.spawns.size(), "no clear shot" if shots.is_empty() else "clear: " + ", ".join(pairs)])
	var bad: Array = []
	for i in lv.spawns.size():
		var a: Vector2i = lv.spawns[i]
		if not lv.stands(a):
			bad.append("%d does not stand" % i)
		for j in lv.spawns.size():
			if i != j and lv.one_drop(a, lv.spawns[j], 150):
				bad.append("%d over %d" % [i, j])
	_rule(bench, "every spawn spot stands, none one drop above another", bad.is_empty(),
		"all stand, none over another" if bad.is_empty() else ", ".join(bad))
	# the routes
	var g := _routes(lv)
	var surfs: Array = g["surfs"]
	var comp: Array = g["comp"]
	var dead: Array = []
	for i in surfs.size():
		if not comp[i]:
			dead.append(_surf_name(surfs[i]) + " (" + g["why"][i] + ")")
	_rule(bench, "every floor and ledge reachable from every other (no dead ends)", dead.is_empty(),
		"%d surfaces, %d places, %d moves from %d starts (%d moves each), %d edges; %s" % [surfs.size(), g["places"],
		g["runs"], g["starts"], g["moves"], g["edge_n"], "all joined" if dead.is_empty() else "apart: " + "; ".join(dead)])
	var one_way: Array = []
	for i in surfs.size():
		if g["outs"][i] < 2:
			one_way.append("%s (%d)" % [_surf_name(surfs[i]), g["outs"][i]])
	_rule(bench, "every floor and ledge can be left at least two ways", one_way.is_empty(),
		"the fewest ways out: %d" % g["min_out"] if one_way.is_empty() else "only one way out of " + "; ".join(one_way))
	var wraps: Array = g["wraps"]
	_rule(bench, "the wrap carries routes: sideways both ways and down", wraps[0] > 0 and wraps[1] > 0 and wraps[2] > 0,
		"edges through the wrap: right %d, left %d, down %d, up %d" % [wraps[0], wraps[1], wraps[2], wraps[3]])
	var hard: Array = []
	for i in surfs.size():
		if comp[i] and not g["plain_in"][i]:
			hard.append(_surf_name(surfs[i]))
	var hard_routes: Array = []
	for key in g["edges"]:
		if not g["edges"][key]:
			hard_routes.append("%s -> %s" % [_surf_name(surfs[key.x]), _surf_name(surfs[key.y])])
	print("   only a wall jump or a dodge reaches: %s; routes only a wall jump or a dodge makes: %d%s" % [
		"none" if hard.is_empty() else ", ".join(hard), hard_routes.size(),
		"" if hard_routes.is_empty() else " (" + "; ".join(hard_routes.slice(0, 4)) + ("; ..." if hard_routes.size() > 4 else "") + ")"])
	# balance
	var b := _balance(lv)
	_rule(bench, "balanced left against right, not a perfect mirror", b["ok"], b["detail"])
	if list:
		for i in surfs.size():
			print("   surface %d: %s, %d ways out, %s" % [i, _surf_name(surfs[i]), g["outs"][i], "joined" if comp[i] else g["why"][i]])
	if rounds > 0:
		_rounds(n, rounds)
	if png_dir != "":
		var path := png_dir.path_join("arena_%d.png" % n)
		_png(lv, g, shots, path)
		print("   map: %s" % path)
	print("   (%.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))

# ------------------------------------------------------------------ spawn fairness
# Each pair of spawn spots, both ways: from the bow to five points on the other
# body, through each wrap copy; the shortest clear line under SHOT_RANGE counts.
func _clear_shots(lv) -> Array:
	var best := {}
	for i in lv.spawns.size():
		var a: Vector2i = lv.spawns[i]
		var bow := Vector2(a.x, a.y - BOW_UP)
		for j in lv.spawns.size():
			if i == j:
				continue
			var b: Vector2i = lv.spawns[j]
			for ox in [-1, 0, 1]:
				for oy in [-1, 0, 1]:
					for p in AIM_POINTS:
						var to: Vector2 = Vector2(b.x + ox * W, b.y + oy * H) + p
						var d := bow.distance_to(to)
						var key := Vector2i(mini(i, j), maxi(i, j))
						if d < SHOT_RANGE and d < best.get(key, [0, 0, INF])[2] and _line_clear(lv, bow, to):
							best[key] = [key.x, key.y, d, bow, to]
	var out: Array = best.values()
	out.sort_custom(func(x, y): return x[2] < y[2])
	return out

# A block stops the line; a ledge stops it only on the way down into it from above.
func _line_clear(lv, from: Vector2, to: Vector2) -> bool:
	var d := to - from
	var n := maxi(1, ceili(d.length() / 5.0))
	var prev_row := floori(from.y / 30.0)
	for k in range(1, n + 1):
		var p := from + d * (float(k) / n)
		var cy := floori(p.y / 30.0)
		var c: int = lv.cell(floori(p.x / 30.0), cy)
		if c == LevelScript.SOLID or (c == LevelScript.LEDGE and d.y > 0.0 and cy > prev_row):
			return false
		prev_row = cy
	return true

# ------------------------------------------------------------------ the routes
# The places, the moves and the runs are sim/routes.gd's (the bot brain replays
# the same moves): every second place of each surface (and both ends), each move.
func _surf_name(s: Array) -> String:
	return Routes.surf_name(s)

func _routes(lv) -> Dictionary:
	var sim = SimScript.new(0, 24, 7)
	sim.set_arena(lv.id)
	sim.respawn = false
	sim.power_arrows = false
	var all: Dictionary = Routes.run_all(lv, sim, 4 if quick else 2, quick)
	var sf: Dictionary = all["sf"]
	var at: Dictionary = sf["at"]
	var surfs: Array = sf["surfs"]
	var edges := {}       # Vector2i(from, to) -> true when a plain move does it (false: only a wall jump or a dodge)
	var wraps := [0, 0, 0, 0]
	for r in all["results"]:
		var key := Vector2i(r[0], r[3])
		var plain: bool = (r[6] & (Routes.F_WJ | Routes.F_DODGE)) == 0
		edges[key] = edges.get(key, false) or plain
		for k in 4:
			if r[7] & (1 << k):
				wraps[k] += 1
	# the joined part: the biggest set of surfaces that all reach each other
	var n := surfs.size()
	var fwd: Array = []
	var back: Array = []
	for i in n:
		fwd.append([])
		back.append([])
	var outs: Array = []
	outs.resize(n)
	outs.fill(0)
	var plain_in: Array = []
	plain_in.resize(n)
	plain_in.fill(false)
	for key in edges:
		fwd[key.x].append(key.y)
		back[key.y].append(key.x)
		outs[key.x] += 1
		if edges[key]:
			plain_in[key.y] = true
	var best: Array = []
	var seen := {}
	for i in n:
		if seen.has(i):
			continue
		var a := _reach(i, fwd)
		var b := _reach(i, back)
		var scc: Array = []
		for k in a:
			if b.has(k):
				scc.append(k)
				seen[k] = true
		if scc.size() > best.size():
			best = scc
	var comp: Array = []
	comp.resize(n)
	comp.fill(false)
	for k in best:
		comp[k] = true
	var why: Array = []
	why.resize(n)
	why.fill("")
	if not best.is_empty():
		var into := _reach(best[0], fwd)
		var outof := _reach(best[0], back)
		for i in n:
			if not comp[i]:
				why[i] = "can't get there" if not into.has(i) else ("can't get out" if not outof.has(i) else "?")
	var min_out := 999
	for i in n:
		min_out = mini(min_out, outs[i])
	return {"surfs": surfs, "at": at, "comp": comp, "why": why, "outs": outs, "min_out": min_out, "plain_in": plain_in,
		"wraps": wraps, "edges": edges, "edge_n": edges.size(), "runs": all["runs"], "starts": all["starts"],
		"places": all["places"], "moves": all["moves"]}

func _reach(from: int, adj: Array) -> Dictionary:
	var seen := {from: true}
	var todo: Array = [from]
	while not todo.is_empty():
		var i: int = todo.pop_back()
		for k in adj[i]:
			if not seen.has(k):
				seen[k] = true
				todo.append(k)
	return seen

# ------------------------------------------------------------------ balance
func _balance(lv) -> Dictionary:
	var sl := 0
	var sr := 0
	for s in lv.spawns:
		if s.x < W / 2:
			sl += 1
		elif s.x > W / 2:
			sr += 1
	var cl := [0, 0, 0]
	var cr := [0, 0, 0]
	var differ := 0
	var filled := 0
	for cy in ROWS:
		for cx in COLS:
			var c: int = lv.cell(cx, cy)
			if cx < COLS / 2:
				cl[c] += 1
			else:
				cr[c] += 1
			if c != LevelScript.EMPTY:
				filled += 1
			if c != lv.cell(COLS - 1 - cx, cy):
				differ += 1
	var near := func(a: int, b: int) -> bool: return absi(a - b) <= maxi(a, b) * 0.1
	var ok: bool = sl == sr and near.call(cl[1], cr[1]) and near.call(cl[2], cr[2]) and differ > 0
	return {"ok": ok, "detail": "spawn spots %d left, %d right (%d in the middle); blocks %d / %d cells, ledges %d / %d; %d cells differ from the mirror image (%.0f%% of the %d filled)" % [
		sl, sr, lv.spawns.size() - sl - sr, cl[1], cr[1], cl[2], cr[2], differ, 100.0 * differ / maxi(1, filled), filled]}

# ------------------------------------------------------------------ the bots' rounds
# 8 bots, one life, the purple walls at 25 s, the 60 s backstop, as the server
# plays a round (minus the people). Stuck: a bot that stays inside a 90 px
# square for 5 s while alive (counted once a round per bot).
func _rounds(n: int, count: int) -> void:
	var sim = SimScript.new(0, 24, 1000 + n)
	sim.set_arena(n)
	sim.respawn = false
	sim.power_arrows = false
	sim.walls_start = 25 * 60
	var seats: Array = []
	for i in 8:
		seats.append({"id": i, "bot": true})
	var lengths: Array = []
	var draws := 0
	var causes := {}
	var deaths := 0
	var cells := {}
	var stuck := 0
	var stuck_at := {}
	for r in count:
		sim.start_round(seats)
		sim.frozen = false
		var trail := {}
		var stuck_now := {}
		var t := 0
		while t < 3600:
			sim.step()
			t += 1
			for e in sim.take_events():
				if e[0] == P.E_DEATH:
					deaths += 1
					causes[e[4]] = causes.get(e[4], 0) + 1
					cells[Vector2i(e[1] / 120, e[2] / 120)] = true
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
							var sq := Vector2i(int(lo.x + hi.x + 36) / 240, int(lo.y + hi.y + 63) / 240)
							stuck_at[sq] = stuck_at.get(sq, 0) + 1
			if sim.alive_count() <= 1:
				break
		stuck += stuck_now.size()
		lengths.append(t / 60.0)
		if sim.alive_count() == 0 or t >= 3600:
			draws += 1
	lengths.sort()
	var parts: Array = []
	for k in [1, 3, 6]:
		parts.append("%s %d%%" % [P.CAUSES[k], roundi(100.0 * causes.get(k, 0) / maxi(1, deaths))])
	var where: Array = []
	var sqs := stuck_at.keys()
	sqs.sort_custom(func(a, b): return stuck_at[a] > stuck_at[b])
	for sq in sqs.slice(0, 3):
		where.append("%d at (%d, %d)" % [stuck_at[sq], sq.x * 120 + 60, sq.y * 120 + 60])
	print("   bots' rounds (%d, 8 bots): length median %.1f s, p90 %.1f s, longest %.1f s; draws %d%%; deaths: %s; death spots %d of 144 squares; stuck 5 s: %d of %d bot rounds%s" % [
		count, lengths[count / 2], lengths[int(count * 0.9)], lengths[-1], roundi(100.0 * draws / count), ", ".join(parts),
		cells.size(), stuck, count * 8, "" if where.is_empty() else " (" + ", ".join(where) + ")"])

# ------------------------------------------------------------------ the map picture
func _png(lv, g: Dictionary, shots: Array, path: String) -> void:
	var img := Image.create(W / 2, H / 2, false, Image.FORMAT_RGBA8)
	img.fill(Color("1b2233"))
	for cy in ROWS:
		for cx in COLS:
			var c: int = lv.cell(cx, cy)
			if c == LevelScript.SOLID:
				img.fill_rect(Rect2i(cx * 15, cy * 15, 15, 15), Color("8a93a8"))
			elif c == LevelScript.LEDGE:
				img.fill_rect(Rect2i(cx * 15, cy * 15, 15, 5), Color("e0a040"))
	var surfs: Array = g["surfs"]
	for i in surfs.size():
		var col := Color("4caf50") if g["plain_in"][i] else Color("40c0e0")
		if not g["comp"][i]:
			col = Color("e04040")
		for cx in surfs[i][1]:
			var y: int = surfs[i][0] * 15 - 3
			for x in range(cx * 15 - 9, cx * 15 + 9):
				for dy in 2:
					img.set_pixel(posmod(x, W / 2), posmod(y + dy, H / 2), col)
	for t in lv.torches:
		img.fill_rect(Rect2i(int(t.x / 2) - 2, int(t.y / 2) - 2, 5, 5), Color("ff8a30"))
	for s in shots:
		_line(img, s[3] / 2.0, s[4] / 2.0, Color("ff3030"))
	for i in lv.spawns.size():
		var sp: Vector2i = lv.spawns[i]
		img.fill_rect(Rect2i(sp.x / 2 - 9, sp.y / 2 - 31, 18, 31), Color.WHITE)
		_digit(img, i % 10, sp.x / 2 - 3, sp.y / 2 - 26, Color.BLACK)
	img.save_png(path)

func _line(img: Image, a: Vector2, b: Vector2, col: Color) -> void:
	var n := maxi(1, ceili(a.distance_to(b)))
	for k in n + 1:
		var p := a.lerp(b, float(k) / n)
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
			img.set_pixel(posmod(int(p.x) + d.x, W / 2), posmod(int(p.y) + d.y, H / 2), col)

func _digit(img: Image, d: int, x: int, y: int, col: Color) -> void:
	var bits: String = DIGITS[d]
	for k in 15:
		if bits[k] == "1":
			img.fill_rect(Rect2i(x + (k % 3) * 2, y + (k / 3) * 3, 2, 3), col)

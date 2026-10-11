# The arena probe (G5, the super arena): the clever-ledges rules of
# docs/reference/v0.2-transformation-plan.md (section 3) as checks, for each
# layout in sim/level.gd. Offline: no server, no drawing.
#   godot --headless --path bench --script res://tools/arena_probe.gd -- [--layout=N] [--png=DIR] [--rounds=N] [--quick] [--list]
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
# Exits 1 when a layout other than the bench arena fails a rule (the bench
# arena, layout 0, is the test arena: reported, never a fail).
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")

const COLS := 64
const ROWS := 36
const W := 1920
const H := 1080
const SHOT_RANGE := 600.0
const BOW_UP := 35                # the arrow leaves the body 28 px below its top (sim ARROW_Y): 35 px above the feet
const AIM_POINTS := [Vector2(0, -55), Vector2(0, -32), Vector2(0, -8), Vector2(-14, -32), Vector2(14, -32)]
const MAX_T := 240                # a move gives up after 4 s
const J := P.B_JUMP
const F_WJ := 1                   # a move's flags: it used a wall jump,
const F_DODGE := 2                # a dodge,
const F_GRAB := 4                 # a ledge grab
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
	print("   only a wall jump or a dodge reaches: %s" % ("none" if hard.is_empty() else ", ".join(hard)))
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
# The places to stand: the feet at a cell's left edge (cx * 30) on top of row r.
# A surface: a run of places side by side on one row (joined across the wrap).
func _surfaces(lv) -> Dictionary:
	var at := {}          # Vector2i(cx, r) -> surface index
	var surfs: Array = [] # [row, [cx, ...]]
	for r in ROWS:
		var runs: Array = []
		var cur: Array = []
		for cx in COLS:
			if lv.stands(Vector2i(cx * 30, r * 30)):
				cur.append(cx)
			elif not cur.is_empty():
				runs.append(cur)
				cur = []
		if not cur.is_empty():
			runs.append(cur)
		if runs.size() > 1 and runs[0][0] == 0 and runs[-1][-1] == COLS - 1:
			runs[-1].append_array(runs[0])
			runs.remove_at(0)
		for run in runs:
			for cx in run:
				at[Vector2i(cx, r)] = surfs.size()
			surfs.append([r, run])
	return {"at": at, "surfs": surfs}

func _surf_name(s: Array) -> String:
	var cols: Array = s[1]
	return "row %d cols %d-%d" % [s[0], cols[0], cols[-1]]

func _dir(d: int) -> int:
	return P.B_RIGHT if d > 0 else (P.B_LEFT if d < 0 else 0)

# The moves, each a list of [from tick, to tick, buttons] held together; "let_go"
# lets go of left and right once in the air; "steer" + "wall": hold that way, and
# at a wall in the air jump off it (up to 4 times), steer away for "wall" ticks,
# then back toward it.
func _moves() -> Array:
	var m: Array = []
	for d in [-1, 1]:
		m.append({"segs": [[0, 999, _dir(d)]]})
		m.append({"segs": [[0, 999, _dir(d)]], "let_go": true})
	for hold in ([1, 30] if quick else [1, 6, 30]):
		m.append({"segs": [[0, hold, J]]})
		for d in [-1, 1]:
			for at in ([0, 12] if quick else [0, 12, 24]):
				m.append({"segs": [[0, hold, J], [at, 999, _dir(d)]]})
	for d in [-1, 1]:
		for run in ([10] if quick else [8, 20]):
			for hold in [6, 30]:
				m.append({"segs": [[0, run, _dir(d)], [run, run + hold, J], [run, 999, _dir(d)]]})
				m.append({"segs": [[0, run, _dir(d)], [run, run + hold, J]]})
				m.append({"segs": [[0, run, _dir(d)], [run, run + hold, J], [run + 12, 999, _dir(-d)]]})
	for d in [-1, 0, 1]:
		m.append({"segs": [[0, 3, P.B_DOWN], [0, 1, J], [0, 999, _dir(d)]], "drop": true})
		if d != 0:
			m.append({"segs": [[0, 3, P.B_DOWN], [0, 1, J], [10, 999, _dir(d)]], "drop": true})
	for d in [-1, 1]:
		for back in [4, 10, 999]:
			m.append({"segs": [[0, 30, J]], "steer": d, "wall": back})
		m.append({"segs": [[20, 50, J]], "steer": d, "wall": 8})
	var ways := [P.B_RIGHT, P.B_LEFT, P.B_UP, P.B_UP | P.B_RIGHT, P.B_UP | P.B_LEFT, P.B_DOWN | P.B_RIGHT, P.B_DOWN | P.B_LEFT]
	for at in ([10] if quick else [6, 14]):
		for w in ways:
			var steer := P.B_RIGHT if w & P.B_RIGHT else (P.B_LEFT if w & P.B_LEFT else 0)
			m.append({"segs": [[0, 30, J], [at, at + 1, P.B_DODGE | w], [at, 999, steer]]})
	for w in [P.B_RIGHT, P.B_LEFT, P.B_UP, P.B_UP | P.B_RIGHT, P.B_UP | P.B_LEFT]:
		var steer := P.B_RIGHT if w & P.B_RIGHT else (P.B_LEFT if w & P.B_LEFT else 0)
		m.append({"segs": [[0, 1, P.B_DODGE | w], [0, 999, steer]]})
	for d in [-1, 1]:
		m.append({"segs": [[0, 1, P.B_DODGE | _dir(d)], [4, 34, J], [0, 999, _dir(d)]]})
	return m

func _routes(lv) -> Dictionary:
	var sf := _surfaces(lv)
	var at: Dictionary = sf["at"]
	var surfs: Array = sf["surfs"]
	var sim = SimScript.new(0, 24, 7)
	sim.set_arena(lv.id)
	sim.respawn = false
	sim.power_arrows = false
	var moves := _moves()
	var edges := {}       # Vector2i(from, to) -> true when a plain move does it (false: only a wall jump or a dodge)
	var wraps := [0, 0, 0, 0]
	var runs := 0
	var starts := 0
	var places := 0
	for si in surfs.size():
		var cols: Array = surfs[si][1]
		places += cols.size()
		var on_ledge := false
		for cx in cols:
			if lv.cell(cx, surfs[si][0]) == LevelScript.LEDGE or lv.cell(cx - 1, surfs[si][0]) == LevelScript.LEDGE:
				on_ledge = true
		var picks: Array = []
		var stride := 4 if quick else 2
		for k in cols.size():
			if k % stride == 0 or k == cols.size() - 1:
				picks.append(cols[k])
		for cx in picks:
			starts += 1
			var spot := Vector2i(cx * 30, surfs[si][0] * 30)
			for mv in moves:
				if mv.has("drop") and not on_ledge:
					continue
				runs += 1
				var res := _run_move(sim, spot, mv, at)
				var to: int = res[0]
				if to < 0 or to == si:
					continue
				var key := Vector2i(si, to)
				var plain: bool = (res[1] & (F_WJ | F_DODGE)) == 0
				edges[key] = edges.get(key, false) or plain
				for k in 4:
					if res[2] & (1 << k):
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
		"wraps": wraps, "edges": edges, "edge_n": edges.size(), "runs": runs, "starts": starts, "places": places, "moves": moves.size()}

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

# One move from a place: [the surface it lands on (-1: none, or it never left),
# flags, the wrap edges it crossed (bits: right, left, down, up)].
func _run_move(sim, spot: Vector2i, mv: Dictionary, at: Dictionary) -> Array:
	var f = SimScript.Fighter.new()
	f.id = 0
	f.bot = false
	sim.fighters = [f]
	sim.arrows.clear()
	sim._place(f, spot)
	sim.events.clear()
	var segs: Array = mv["segs"]
	var flags := 0
	var wrapped := 0
	var airborne := false
	var prev := 0
	var steer: int = mv.get("steer", 0)
	var walls := 0
	var wall_side := 0
	var wall_t := 0
	var hold_t := 0
	var still := 0
	for t in MAX_T:
		var b := 0
		for s in segs:
			if t >= s[0] and t < s[1]:
				b |= s[2]
		if mv.get("let_go", false) and airborne:
			b &= ~(P.B_LEFT | P.B_RIGHT)
		if mv.has("wall"):
			if wall_t > 0:
				wall_t -= 1
				if wall_t == 0:
					steer = wall_side
			if hold_t > 0:
				hold_t -= 1
				b |= J               # hold it: a higher jump off the wall
			elif f.wall != 0 and not f.on_ground and f.state == P.F_NORMAL and walls < 4:
				if prev & J:
					b &= ~J          # let go for a tick: the jump off the wall needs a fresh press
				else:
					b |= J           # still steering into the wall on this tick, or there is no wall jump
			b |= _dir(steer)
		var x0: int = f.x
		var y0: int = f.y
		sim.apply_input(f, b, 0)
		sim.step()
		prev = b
		for e in sim.take_events():
			if e[0] == P.E_WALLJUMP:
				flags |= F_WJ
				if mv.has("wall"):
					walls += 1
					wall_side = 1 if e[4] == 1 else -1
					steer = -wall_side
					wall_t = mv["wall"]
					hold_t = 12
			elif e[0] == P.E_DODGE:
				flags |= F_DODGE
			elif e[0] == P.E_LEDGE:
				flags |= F_GRAB
		if f.x - x0 < -900:
			wrapped |= 1
		elif f.x - x0 > 900:
			wrapped |= 2
		if f.y - y0 < -500:
			wrapped |= 4
		elif f.y - y0 > 500:
			wrapped |= 8
		if not f.on_ground:
			airborne = true
			still = 0
		elif airborne and f.state == P.F_NORMAL:
			return [_surface_at(f, at), flags, wrapped]
		elif f.x == x0 and t > 40:
			still += 1
			if still > 10:
				break      # on the ground and not going anywhere
	return [-1, flags, wrapped]

func _surface_at(f, at: Dictionary) -> int:
	var feet: int = f.y + 63
	if posmod(feet, 30) != 0:
		return -1
	var r := posmod(feet / 30, ROWS)
	var cx := roundi((f.x + 18) / 30.0)
	for k in [0, -1, 1, -2, 2]:
		var key := Vector2i(posmod(cx + k, COLS), r)
		if at.has(key):
			return at[key]
	return -1

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
	print("   bots' rounds (%d, 8 bots): length median %.1f s, p90 %.1f s, longest %.1f s; draws %d%%; deaths: %s; death spots %d of 144 squares; stuck 5 s: %d of %d bot rounds" % [
		count, lengths[count / 2], lengths[int(count * 0.9)], lengths[-1], roundi(100.0 * draws / count), ", ".join(parts),
		cells.size(), stuck, count * 8])

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

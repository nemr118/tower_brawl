# ==============================================================================
# The routes (G5's arena probe, G6's bots). The places to stand in an arena (a
# surface: a run of them side by side on one row, a floor or a ledge), the moves a
# fighter can make from a place (walks off an edge, tapped and held jumps with
# steering, run-up jumps, drops through a ledge, wall jumps, ledge grabs, dodges),
# and MovePlayer, which presses a move's buttons tick by tick. tools/arena_probe.gd
# runs the moves from the places to check an arena's rules; with --write-routes it
# keeps the fastest move from every place to each other surface in FILE, and the
# bot brain (sim/brain.gd) loads that and replays the moves.
# ==============================================================================
extends RefCounted

const P = preload("res://sim/proto.gd")
const LevelScript = preload("res://sim/level.gd")
const SimScript = preload("res://sim/sim.gd")

const COLS := 64
const ROWS := 36
const MAX_T := 240                # a move gives up after 4 s
const J := P.B_JUMP
const F_WJ := 1                   # a move's flags: it used a wall jump,
const F_DODGE := 2                # a dodge,
const F_GRAB := 4                 # a ledge grab
const FILE := "res://sim/routes.json"
const FILE_VERSION := 3
# The starts a move is run from for the route file: the place, the remainder of a
# pixel either way, a pixel either way. A bot never starts exactly as the probe's
# fighter did (it stops by friction), so the file keeps a move only when all five
# land on the same surface.
const STURDY := [[0, 0.0], [0, -0.45], [0, 0.45], [-1, 0.0], [1, 0.0]]

# The places to stand: the feet at a cell's left edge (cx * 30) on top of row r.
# A surface: a run of places side by side on one row (joined across the wrap).
# {"at": Vector2i(cx, r) -> surface index, "surfs": [[row, [cx, ...]], ...]}
static func surfaces(lv) -> Dictionary:
	var at := {}
	var surfs: Array = []
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

static func surf_name(s: Array) -> String:
	var cols: Array = s[1]
	return "row %d cols %d-%d" % [s[0], cols[0], cols[-1]]

static func dir_buttons(d: int) -> int:
	return P.B_RIGHT if d > 0 else (P.B_LEFT if d < 0 else 0)

# The moves, each a list of [from tick, to tick, buttons] held together; "let_go"
# lets go of left and right once in the air; "steer" + "wall": hold that way, and
# at a wall in the air jump off it (up to 4 times), steer away for "wall" ticks,
# then back toward it; "drop": only from a ledge.
static func moves(quick := false) -> Array:
	var m: Array = []
	for d in [-1, 1]:
		m.append({"segs": [[0, 999, dir_buttons(d)]]})
		m.append({"segs": [[0, 999, dir_buttons(d)]], "let_go": true})
	for hold in ([1, 30] if quick else [1, 6, 30]):
		m.append({"segs": [[0, hold, J]]})
		for d in [-1, 1]:
			for at in ([0, 12] if quick else [0, 12, 24]):
				m.append({"segs": [[0, hold, J], [at, 999, dir_buttons(d)]]})
	for d in [-1, 1]:
		for run in ([10] if quick else [8, 20]):
			for hold in [6, 30]:
				m.append({"segs": [[0, run, dir_buttons(d)], [run, run + hold, J], [run, 999, dir_buttons(d)]]})
				m.append({"segs": [[0, run, dir_buttons(d)], [run, run + hold, J]]})
				m.append({"segs": [[0, run, dir_buttons(d)], [run, run + hold, J], [run + 12, 999, dir_buttons(-d)]]})
	for d in [-1, 0, 1]:
		m.append({"segs": [[0, 3, P.B_DOWN], [0, 1, J], [0, 999, dir_buttons(d)]], "drop": true})
		if d != 0:
			m.append({"segs": [[0, 3, P.B_DOWN], [0, 1, J], [10, 999, dir_buttons(d)]], "drop": true})
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
		m.append({"segs": [[0, 1, P.B_DODGE | dir_buttons(d)], [4, 34, J], [0, 999, dir_buttons(d)]]})
	return m

# Presses one move's buttons, a tick at a time: buttons(f) once a tick, before the
# sim steps. A wall jump on the last tick shows in the fighter's state (the sim
# sets wj_t to 12 on it, and faces away from the wall), so the arena probe's lone
# sim and the bot brain in a real round press the same buttons.
class MovePlayer:
	var mv: Dictionary
	var t := 0
	var prev := 0
	var steer := 0
	var walls := 0
	var wall_side := 0
	var wall_t := 0
	var hold_t := 0
	var airborne := false

	func _init(move: Dictionary) -> void:
		mv = move
		steer = int(mv.get("steer", 0))

	func buttons(f) -> int:
		var walling: bool = mv.has("wall")
		if walling and t > 0 and f.wj_t == 12:   # it jumped off a wall on the last tick
			walls += 1
			wall_side = -f.facing
			steer = -wall_side
			wall_t = int(mv["wall"])
			hold_t = 12
		if t > 0 and not f.on_ground:   # (a fighter just placed has no on_ground yet; a move starts standing)
			airborne = true
		var b := 0
		for s in mv["segs"]:
			if t >= s[0] and t < s[1]:
				b |= s[2]
		if mv.get("let_go", false) and airborne:
			b &= ~(P.B_LEFT | P.B_RIGHT)
		if walling:
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
			b |= P.B_RIGHT if steer > 0 else (P.B_LEFT if steer < 0 else 0)
		prev = b
		t += 1
		return b

# One move from a place, on a lone sim (sim.fighters is replaced): [the surface it
# lands on (-1: none, or it never left), flags, the wrap edges it crossed (bits:
# right, left, down, up), ticks to the landing, the landing place's cx]. dx and rx
# start it a pixel or part of one aside (STURDY). settle: after the landing let go
# of everything until it stops (up to 30 ticks): it counts only if it stops on
# that surface (a fast landing on a short ledge slides off), and the place where it
# stops is the landing place.
static func run_move(sim, spot: Vector2i, mv: Dictionary, at: Dictionary, dx := 0, rx := 0.0, settle := false) -> Array:
	var f = SimScript.Fighter.new()
	f.id = 0
	f.bot = false
	sim.fighters = [f]
	sim.arrows.clear()
	sim._place(f, spot)
	f.x += dx
	f.rx = rx
	sim.events.clear()
	var player := MovePlayer.new(mv)
	var flags := 0
	var wrapped := 0
	var still := 0
	for t in MAX_T:
		var b := player.buttons(f)
		var x0: int = f.x
		var y0: int = f.y
		sim.apply_input(f, b, 0)
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_WALLJUMP:
				flags |= F_WJ
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
			still = 0
		elif player.airborne and f.state == P.F_NORMAL:
			var landed: int = at.get(place_at(f, at), -1)
			var ticks := t + 1
			if settle:
				for k in 30:
					if f.vx == 0.0:
						break
					sim.apply_input(f, 0, 0)
					sim.step()
					sim.take_events()
					ticks += 1
					if not f.on_ground:
						return [-1, flags, wrapped, ticks, -1]
			var place := place_at(f, at)
			if settle and at.get(place, -1) != landed:
				return [-1, flags, wrapped, ticks, -1]
			return [at.get(place, -1), flags, wrapped, ticks, place.x]
		elif f.x == x0 and t > 40:
			still += 1
			if still > 10:
				break      # on the ground and not going anywhere
	return [-1, flags, wrapped, MAX_T, -1]

# The place a fighter on the ground stands on (Vector2i(cx, row), a key of at), or
# Vector2i(-1, -1): its feet on a cell's top, the nearest place within 2 cells.
static func place_at(f, at: Dictionary) -> Vector2i:
	var feet: int = f.y + 63
	if posmod(feet, 30) != 0:
		return Vector2i(-1, -1)
	var r := posmod(feet / 30, ROWS)
	var cx := roundi((f.x + 18) / 30.0)
	for k in [0, -1, 1, -2, 2]:
		var key := Vector2i(posmod(cx + k, COLS), r)
		if at.has(key):
			return key
	return Vector2i(-1, -1)

# Every move from the places of each surface (every stride-th place, and both
# ends): [[from surface, from cx, move index, to surface, to cx, ticks, flags,
# wraps], ...] for the moves that land on another surface; and how many runs.
# starts: [[dx, rx], ...]: a move counts only when every start lands on the same
# surface (the most ticks of them; the first start's landing place). settle: see
# run_move (the route file's moves land and stop; the arena probe's checks do not).
static func run_all(lv, sim, stride: int, quick: bool, starts_at: Array = [[0, 0.0]], settle := false) -> Dictionary:
	var sf := surfaces(lv)
	var at: Dictionary = sf["at"]
	var surfs: Array = sf["surfs"]
	var mvs := moves(quick)
	var out: Array = []
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
		for k in cols.size():
			if k % stride == 0 or k == cols.size() - 1:
				picks.append(cols[k])
		for cx in picks:
			starts += 1
			var spot := Vector2i(cx * 30, surfs[si][0] * 30)
			for mi in mvs.size():
				var mv: Dictionary = mvs[mi]
				if mv.has("drop") and not on_ledge:
					continue
				runs += 1
				var res := run_move(sim, spot, mv, at, starts_at[0][0], starts_at[0][1], settle)
				if res[0] < 0 or res[0] == si:
					continue
				var same := true
				for k in range(1, starts_at.size()):
					var other := run_move(sim, spot, mv, at, starts_at[k][0], starts_at[k][1], settle)
					if other[0] != res[0]:
						same = false
						break
					res[3] = maxi(res[3], other[3])
					res[1] |= other[1]
				if same:
					out.append([si, cx, mi, res[0], res[4], res[3], res[1], res[2]])
	return {"sf": sf, "results": out, "runs": runs, "starts": starts, "places": places, "moves": mvs.size()}

# ------------------------------------------------------------------ the route file
static func grid_hash(lv) -> String:
	return lv.grid.hex_encode().sha256_text()

static func moves_hash() -> String:
	return str(moves(false)).sha256_text()

# The fastest move from every place to each other surface, from run_all's results
# (every place, every move): a flat list per arena, 7 numbers an edge: from row,
# from cx, move index, to row, to cx, ticks, flags.
static func keep_fastest(lv, results: Array, surfs: Array) -> PackedInt32Array:
	var best := {}     # Vector3i(from cx, from surface, to surface) -> the result
	for r in results:
		var key := Vector3i(r[1], r[0], r[3])
		var old = best.get(key)
		var plain: bool = (r[6] & (F_WJ | F_DODGE)) == 0
		if old == null or r[5] < old[5] or (r[5] == old[5] and plain and (old[6] & (F_WJ | F_DODGE)) != 0):
			best[key] = r
	var keys := best.keys()
	keys.sort()
	var out := PackedInt32Array()
	for key in keys:
		var r: Array = best[key]
		out.append_array([surfs[r[0]][0], r[1], r[2], surfs[r[3]][0], r[4], r[5], r[6]])
	return out

# A route map: what the bot brain plans with, for one arena. The surfaces and
# places (surfaces()), the moves, cand[Vector2i(A, B)] = the edges from surface A
# that land on B ([from cx, move index, to cx, ticks, flags]), and over the
# surfaces the cost (ticks) and the next surface of the fastest way (hop[A][G]).
class RouteMap:
	var id := 0
	var surfs: Array = []
	var at := {}
	var idx := {}               # Vector2i(cx, row) -> its index in its surface's run (for walking)
	var mvs: Array = []
	var cand := {}
	var cost: Array = []        # cost[A][G]: ticks (INF: no way)
	var hop: Array = []         # hop[A][G]: the next surface (-1: none)

	func surface_of(place: Vector2i) -> int:
		return at.get(place, -1)

	# Ticks to walk from place a to place b on one surface (TowerFall's top speed, a
	# few ticks to start and stop).
	func walk_ticks(a: Vector2i, b: Vector2i) -> float:
		var d: int = absi(int(idx.get(a, 0)) - int(idx.get(b, 0)))
		return 0.0 if d == 0 else d * 30.0 / 6.75 + 6.0

static var _maps := {}          # arena id -> RouteMap (or null: no file, or it does not match the arena)
static var _file_data = null
static var warned := false

# The route map of lv's arena, built once from FILE; null when the file is missing
# or was made for another grid or other moves (then the brain walks the old way).
static func map_for(lv) -> RouteMap:
	if _maps.has(lv.id):
		return _maps[lv.id]
	var rm: RouteMap = null
	if _file_data == null:
		var text := FileAccess.get_file_as_string(FILE)
		var d = JSON.parse_string(text) if text != "" else null
		_file_data = d if d is Dictionary else {}
	var arenas: Array = _file_data.get("arenas", [])
	for a in arenas:
		if int(a.get("id", -1)) == lv.id and str(a.get("grid", "")) == grid_hash(lv) \
				and str(_file_data.get("moves", "")) == moves_hash() and int(_file_data.get("version", 0)) == FILE_VERSION:
			rm = _build(lv, a.get("edges", []))
	if rm == null and not warned:
		warned = true
		push_warning("routes: %s has no route map for arena %d (%s): run tools/arena_probe.gd -- --write-routes" % [FILE, lv.id, lv.name])
	_maps[lv.id] = rm
	return rm

static func _build(lv, flat: Array) -> RouteMap:
	var rm := RouteMap.new()
	rm.id = lv.id
	var sf := surfaces(lv)
	rm.surfs = sf["surfs"]
	rm.at = sf["at"]
	for si in rm.surfs.size():
		var cols: Array = rm.surfs[si][1]
		for k in cols.size():
			rm.idx[Vector2i(cols[k], rm.surfs[si][0])] = k
	rm.mvs = moves(false)
	var n: int = rm.surfs.size()
	for i in n:
		var c := []
		c.resize(n)
		c.fill(INF)
		c[i] = 0.0
		rm.cost.append(c)
		var h := []
		h.resize(n)
		h.fill(-1)
		h[i] = i
		rm.hop.append(h)
	for k in range(0, flat.size() - 6, 7):
		var a: int = rm.at.get(Vector2i(int(flat[k + 1]), int(flat[k])), -1)
		var b: int = rm.at.get(Vector2i(int(flat[k + 4]), int(flat[k + 3])), -1)
		if a < 0 or b < 0 or a == b:
			continue
		var e := [int(flat[k + 1]), int(flat[k + 2]), int(flat[k + 4]), int(flat[k + 5]), int(flat[k + 6])]
		var key := Vector2i(a, b)
		if not rm.cand.has(key):
			rm.cand[key] = []
		rm.cand[key].append(e)
		# a surface-to-surface cost: the move, plus walking half the surface to its start
		var c: float = e[3] + rm.surfs[a][1].size() * 30.0 / 6.75 / 2.0
		if c < rm.cost[a][b]:
			rm.cost[a][b] = c
			rm.hop[a][b] = b
	for m in n:          # the fastest ways over all the surfaces (Floyd and Warshall)
		for i in n:
			if rm.cost[i][m] == INF:
				continue
			for j in n:
				var c: float = rm.cost[i][m] + rm.cost[m][j]
				if c < rm.cost[i][j]:
					rm.cost[i][j] = c
					rm.hop[i][j] = rm.hop[i][m]
	return rm

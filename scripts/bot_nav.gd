extends RefCounted
# ==============================================================================
# BOT NAV (v0.1.5): the tower as a route map for the bot brain
# ==============================================================================
# The brain was written for the old arena: to reach something above or below,
# walk to an empty column and fall through the bottom seam. The tower has a
# ledge under almost every column, so a bot whose target stood straight above
# or below it stood still or jumped on the spot, and a round could run for ten
# hours (docs/reference/bot-soak-2026-09-08.md). This file turns the layout
# table (arena_layouts.gd) into places to stand and the moves between them,
# and answers one question: what is the next move from here to there?
#
# A surface is the top of a ledge, a bump or the floor. A move leaves surface i
# from a stretch of it (x0..x1) and lands on surface "to":
#   jump     a surface up to JUMP_RISE higher: under a one-way ledge, or from
#            the end of this one to a ledge beside and above ("leap": the
#            brain may add a dash at the apex; "need_dash": the gap is wider
#            than a running jump, so it waits for the dash to be ready)
#   drop     down, then jump, through a one-way ledge, steering in the air
#   walkoff  walk off a free end ("dir" -1 or 1) and fall, steering in the air;
#            the floor hole comes out of the ceiling hole
# The brain steers a move's fall for the landing surface's inner stretch
# (lx0..lx1); land_x is only the planner's guess of where it comes down.
# A fall is planned with player.gd's numbers: FALL_GRAVITY up to MAX_FALL_SPEED,
# and air steering that starts a reaction delay late (REACT). tools/nav_probe.gd
# drives a real fighter through these routes.
# No class_name (headless builds load it with preload, like bot_brain.gd).
# ==============================================================================

const PlayerScript := preload("res://scripts/player.gd")
const HALF := 9.0          # half the fighter's 14 px width, plus 2 px
const FEET := 8.0          # the feet sit 8 px below the middle point (arena.gd FEET_OFFSET)
const LAND_IN := 13.0      # land at least this far inside a surface's end
const JUMP_RISE := 75.0    # the jump apex is 80 px (430^2 / (2 * 1150)); rows are 70 apart
const JUMP_GAP := 56.0     # a running jump covers about 74 px sideways while it rises 70
const JUMP_GAP_DASH := 96.0  # with a dash at the apex (77 px flat) a gap this wide is still one jump
const JUMP_SIDE := 24.0    # the take-off stretch at an end, for a jump to a ledge beside
const DRIFT := 0.85        # share of full-speed air travel a planned fall may count on
const REACT := 0.25        # the slowest brain's reaction delay: air steering starts this late
const BRAKE_S := 0.13      # air friction (player.gd FRICTION 1300) stops a fighter from full speed in this long
const DROP_STEP := 8.0     # drop take-off points are tried this far apart
const MIN_STRETCH := 12.0  # a drop stretch narrower than this is too hard to stop on
const WALK_COST := 0.1     # route cost per px walked (a drop costs 20, a jump 40 to 50)

var width := 640.0
var height := 1080.0
var surfaces: Array = []   # [{name, kind, x0, x1, top}]
var moves: Array = []      # moves[i] = [{to, kind, x0, x1, lx0, lx1, dir, leap, need_dash, land_x, cost}]


func build(layout: Dictionary) -> void:
	width = float(layout.get("width", 640.0))
	height = float(layout.get("height", 1080.0))
	surfaces.clear()
	for piece in layout.get("pieces", []):
		var kind := str(piece["kind"])
		var top := float(piece["y"])
		if kind == "wall" and top < height - 0.5:
			continue   # the side walls and the ceiling are not somewhere to stand; the floor is
		var x0 := maxf(float(piece["x"]), 0.0)
		var x1 := minf(float(piece["x"]) + float(piece["w"]), width)
		if x1 - x0 < 2.0 * LAND_IN:
			continue
		surfaces.append({"name": str(piece["name"]), "kind": kind, "x0": x0, "x1": x1, "top": top})
	moves.clear()
	for i in surfaces.size():
		moves.append(_jumps_from(i) + _falls_from(i))


# The surface a fighter standing at pos is on; -1 in the air or off the map.
func surface_at(pos: Vector2) -> int:
	var feet := pos.y + FEET
	for i in surfaces.size():
		var s: Dictionary = surfaces[i]
		if pos.x >= s["x0"] - 7.0 and pos.x <= s["x1"] + 7.0 and absf(feet - s["top"]) <= 6.0:
			return i
	return -1


# The surface under a point: where a fighter at that point stands or would land.
func surface_under(pos: Vector2) -> int:
	var x := clampf(pos.x, 0.0, width)
	var best := _first_below(x, pos.y + FEET - 10.0)
	if best < 0:
		best = _first_below(x, -10.0)   # over the floor hole: the fall comes out of the ceiling
	return best


func surface_name(i: int) -> String:
	return str(surfaces[i]["name"]) if i >= 0 and i < surfaces.size() else "-"


# Seconds to fall dy px from rest: FALL_GRAVITY until MAX_FALL_SPEED, then that speed.
func fall_time(dy: float) -> float:
	var g: float = PlayerScript.FALL_GRAVITY
	var vmax: float = PlayerScript.MAX_FALL_SPEED
	var d_cap := vmax * vmax / (2.0 * g)
	if dy <= d_cap:
		return sqrt(2.0 * maxf(dy, 0.0) / g)
	return vmax / g + (dy - d_cap) / vmax


# The first move of the cheapest route from surface "from" (standing at x) to
# surface "to"; {} when already there or there is no route. penalty maps
# "i>j" to extra cost, so a move that just failed is tried less.
func next_move(from: int, x: float, to: int, penalty: Dictionary = {}) -> Dictionary:
	var n := surfaces.size()
	if from < 0 or to < 0 or from >= n or to >= n or from == to:
		return {}
	var dist: Array = []
	var at_x: Array = []
	var first: Array = []
	var done: Array = []
	dist.resize(n)
	at_x.resize(n)
	first.resize(n)
	done.resize(n)
	dist.fill(INF)
	at_x.fill(0.0)
	first.fill({})
	done.fill(false)
	dist[from] = 0.0
	at_x[from] = x
	for _k in n:
		var u := -1
		for v in n:
			if not done[v] and dist[v] < INF and (u < 0 or dist[v] < dist[u]):
				u = v
		if u < 0 or u == to:
			break
		done[u] = true
		for m: Dictionary in moves[u]:
			var j: int = m["to"]
			var take_x := clampf(at_x[u], m["x0"], m["x1"])
			var c: float = dist[u] + m["cost"] + absf(take_x - at_x[u]) * WALK_COST + float(penalty.get("%d>%d" % [u, j], 0.0))
			if c < dist[j]:
				dist[j] = c
				at_x[j] = float(m["land_x"])
				first[j] = m if u == from else first[u]
	return first[to]


# Pairs (from, to) with no route; the probe expects none.
func unreachable() -> Array:
	var out: Array = []
	for i in surfaces.size():
		for j in surfaces.size():
			if i != j and next_move(i, (surfaces[i]["x0"] + surfaces[i]["x1"]) / 2.0, j).is_empty():
				out.append([surface_name(i), surface_name(j)])
	return out


func _jumps_from(i: int) -> Array:
	var a: Dictionary = surfaces[i]
	var out: Array = []
	for j in surfaces.size():
		var b: Dictionary = surfaces[j]
		var rise: float = a["top"] - b["top"]
		if j == i or rise <= 0.0 or rise > JUMP_RISE:
			continue
		var lx0: float = b["x0"] + LAND_IN
		var lx1: float = b["x1"] - LAND_IN
		var ledge: bool = b["kind"] == "ledge"
		var under0 := maxf(a["x0"] + HALF, b["x0"] + HALF)
		var under1 := minf(a["x1"] - HALF, b["x1"] - HALF)
		if ledge and under1 - under0 >= 8.0:
			# straight up through the one-way ledge
			out.append(_move(j, "jump", under0, under1, 0, false, clampf((under0 + under1) / 2.0, lx0, lx1), 40.0))
			continue
		var gap_right: float = b["x0"] - a["x1"]
		var gap_left: float = a["x0"] - b["x1"]
		var overlap_ok := JUMP_SIDE if ledge else 0.0   # a solid bump must be fully beside us
		if gap_right >= -overlap_ok and gap_right <= JUMP_GAP_DASH:
			var wide_r := gap_right > JUMP_GAP
			out.append(_move(j, "jump", a["x1"] - JUMP_SIDE, a["x1"] - 2.0, 1, gap_right > 16.0, lx0, 70.0 if wide_r else 50.0, wide_r))
		elif gap_left >= -overlap_ok and gap_left <= JUMP_GAP_DASH:
			var wide_l := gap_left > JUMP_GAP
			out.append(_move(j, "jump", a["x0"] + 2.0, a["x0"] + JUMP_SIDE, -1, gap_left > 16.0, lx1, 70.0 if wide_l else 50.0, wide_l))
	return out


func _falls_from(i: int) -> Array:
	var a: Dictionary = surfaces[i]
	var out: Array = []
	# drops: every take-off point on a ledge, grouped into stretches per landing
	if a["kind"] == "ledge":
		var runs := {}   # to -> [x0, x1, land_x]
		var x: float = a["x0"] + 14.0
		while x <= a["x1"] - 14.0:
			for hit in _landings(x, a["top"], i, 0):
				var j: int = hit[0]
				if runs.has(j) and x - runs[j][1] <= DROP_STEP + 0.5:
					runs[j][1] = x
				else:
					if runs.has(j):
						_add_drop(out, j, runs[j])
					runs[j] = [x, x, hit[1]]
			x += DROP_STEP
		for j in runs:
			_add_drop(out, j, runs[j])
	# walk off a free end (not against a wall)
	for side in [-1, 1]:
		var ex: float = a["x0"] - HALF - 3.0 if side < 0 else a["x1"] + HALF + 3.0
		if ex <= HALF or ex >= width - HALF:
			continue
		var edge: float = a["x0"] if side < 0 else a["x1"]
		for hit in _landings(ex, a["top"], i, side):
			out.append(_move(hit[0], "walkoff", edge, edge, side, false, hit[1], 20.0 + 0.1 * absf(float(hit[1]) - ex)))
	return out


func _add_drop(out: Array, j: int, run: Array) -> void:
	if run[1] - run[0] < MIN_STRETCH:
		return
	out.append(_move(j, "drop", run[0], run[1], 0, false, run[2], 20.0))


func _move(j: int, kind: String, x0: float, x1: float, dir: int, leap: bool, land_x: float, cost: float, need_dash := false) -> Dictionary:
	var b: Dictionary = surfaces[j]
	return {"to": j, "kind": kind, "x0": x0, "x1": x1, "lx0": b["x0"] + LAND_IN, "lx1": b["x1"] - LAND_IN,
		"dir": dir, "leap": leap, "need_dash": need_dash, "land_x": land_x, "cost": cost}


# Surfaces a fall starting at (x, y) can land on, as [surface, land_x]. dir 0 is
# a drop from standing: steering starts REACT seconds in. dir -1 / 1 is a
# walk-off at full speed: it carries on for REACT seconds (or the whole fall,
# if that is shorter) before the brain can brake, and can hold on to the end.
func _landings(x: float, y: float, skip: int, dir: int) -> Array:
	var out: Array = []
	var wrapped := _first_below(x, y) < 0
	var speed: float = PlayerScript.SPEED
	for j in surfaces.size():
		if j == skip:
			continue
		var b: Dictionary = surfaces[j]
		var dy: float = (height + 16.0 - y) + b["top"] + 10.0 if wrapped else b["top"] - y
		if dy <= 20.0:
			continue
		var t := fall_time(dy)
		var lo: float
		var hi: float
		if dir == 0:
			var reach := speed * maxf(t - REACT, 0.0) * DRIFT
			lo = x - reach
			hi = x + reach
		else:
			# at full speed until the brain reacts, then braking (FRICTION 1300) for what is left of the fall
			var tb := clampf(t - REACT, 0.0, BRAKE_S)
			var near := speed * minf(t, REACT) * 0.9 + speed * tb - 650.0 * tb * tb
			var far := speed * t * 0.95
			if far < near:
				continue
			lo = x + near if dir > 0 else x - far
			hi = x + far if dir > 0 else x - near
		var in0: float = b["x0"] + LAND_IN
		var in1: float = b["x1"] - LAND_IN
		if hi < in0 or lo > in1:
			continue
		var lx := clampf(clampf(x + dir * speed * minf(t, REACT), lo, hi), in0, in1)
		if _path_lands_on(x, lx, y, j, wrapped, dy):
			out.append([j, lx])
	return out


# Does a fall from (x, y) that ends over lx come down on surface j first? The
# columns under the path (the start, the middle, the end) may hold nothing
# higher than j. A fall through the floor hole is two paths: down to the wrap
# line, where x has moved in step with the time, over hole columns only; then
# out of the ceiling from that x to lx.
func _path_lands_on(x: float, lx: float, y: float, j: int, wrapped: bool, dy: float) -> bool:
	var top: float = surfaces[j]["top"]
	var cols: Array = [x, (x + lx) / 2.0, lx]
	var from_y := y
	if wrapped:
		var share := clampf(fall_time(height + 16.0 - y) / maxf(fall_time(dy), 0.001), 0.0, 1.0)
		var xw := x + (lx - x) * share
		for c in [x, (x + xw) / 2.0, xw]:
			if _first_below(c, y) >= 0:
				return false   # a floor under this column: the fall stops before the hole
		cols = [xw, (xw + lx) / 2.0, lx]
		from_y = -10.0
	for k in cols.size():
		var h := _first_below(cols[k], from_y)
		if h >= 0 and h != j and surfaces[h]["top"] <= top:
			return false       # something higher (or level) catches the fall first
		if k == cols.size() - 1 and h != j:
			return false       # the end column must come down on j
	return true


func _first_below(x: float, y: float) -> int:
	var best := -1
	for i in surfaces.size():
		var s: Dictionary = surfaces[i]
		if x >= s["x0"] - HALF and x <= s["x1"] + HALF and s["top"] > y + 4.0:
			if best < 0 or s["top"] < surfaces[best]["top"]:
				best = i
	return best

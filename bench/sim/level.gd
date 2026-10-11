# The arenas: 1920 x 1080, a 30 px collision grid (64 x 36 cells), wrap on all
# four edges (gaps in the floor and ceiling, passages in the side walls).
# One-way ledges are LEDGE cells: you jump up through them and land on their top.
# LAYOUTS holds them; LevelScript.new(n) builds layout n. Layout 0 is the
# benchmark arena, built from PIECES (pieces marked mirror=1 are copied to the
# other side), and stays the default: the tests and the benchmark page use it.
# The others are text maps (G5, the super arena): 36 lines of 64 characters,
# '#' a block, '=' a ledge, '.' air, a digit a spawn spot (the feet stand on the
# cell below, at this cell's left edge: the body covers this cell and the one to
# its left), a letter a..h a torch (the first four are T1's lights).
extends RefCounted

const CELL := 30
const COLS := 64
const ROWS := 36
const W := 1920
const H := 1080
const EMPTY := 0
const SOLID := 1
const LEDGE := 2
const BENCH := 0
const PLAY := [1, 2]          # the arenas the lobby offers (MIX takes them in turn); the bench is the test arena

# [x, y, w, h, kind, mirror] in cells
const PIECES := [
	[0, 0, 28, 2, SOLID, 1],      # ceiling, gap 28..35
	[0, 34, 28, 2, SOLID, 1],     # floor, gap 28..35
	[0, 2, 2, 12, SOLID, 1],      # side wall above the passage (rows 14..19)
	[0, 20, 2, 14, SOLID, 1],     # side wall below it
	[6, 30, 8, 1, LEDGE, 1],
	[26, 28, 12, 2, SOLID, 0],    # the roof over the floor gap
	[14, 26, 10, 1, LEDGE, 1],
	[2, 24, 5, 2, SOLID, 1],      # wall bump
	[27, 22, 10, 1, LEDGE, 0],
	[21, 16, 2, 7, SOLID, 1],     # pillar: wall jumps
	[4, 18, 9, 1, LEDGE, 1],
	[24, 14, 16, 1, LEDGE, 0],
	[9, 11, 6, 2, SOLID, 1],
	[16, 10, 7, 1, LEDGE, 1],
	[4, 6, 10, 1, LEDGE, 1],
	[29, 6, 6, 1, LEDGE, 0],
]

# No spot sits one drop above another (dropping through your own ledge only):
# p1.2 had 7 such pairs, and a fighter could stomp the one below in the first
# second. TowerFall keeps its spawn spots apart too. input_probe rule 27. The
# bench's low ledge spots sit at the ledge ends, under the pillars, out of the
# way of a fighter running off the side ledge (v0.2.0-p1.3's page has the numbers).
const LAYOUTS := [
	{"name": "THE BENCH", "pieces": PIECES,
		"spawns": [Vector2i(240, 1020), Vector2i(1680, 1020), Vector2i(690, 780), Vector2i(1230, 780),
			Vector2i(360, 540), Vector2i(1560, 540), Vector2i(210, 180), Vector2i(1710, 180),
			Vector2i(960, 180), Vector2i(960, 660)],
		"torches": [Vector2(78, 300), Vector2(1842, 300), Vector2(78, 800), Vector2(1842, 800),
			Vector2(660, 560), Vector2(1260, 560), Vector2(960, 120), Vector2(960, 930)]},
	# The Keep: a castle courtyard: the keep (a roof on two short legs, merlons on
	# top) over the floor, the watchtower block above it, side blocks with steps,
	# pillars hanging from the ceiling, two gaps in the floor and one passage in each
	# side wall (G5, 2026-10-10)
	{"name": "THE KEEP", "map": [
		"############....################################....############",
		"############....################################....############",
		"##...................##..................##...................##",
		"##...................##..................##...................##",
		"##...................##h.................##...................##",
		"##c..................##.........7........##..................d##",
		"##..........................========.....##...................##",
		"##............................................................##",
		"##..5....................#....................................##",
		"##======.................#............#.....................6.##",
		"##...............=========............#.................======##",
		"##....................................=========...............##",
		"##............................................................##",
		"##............................................................##",
		"................................................................",
		".............................######.............................",
		".............................######.............................",
		".............................######.............................",
		"########........................g.......................########",
		"########................................................########",
		"##............................................................##",
		"##...............=======................=======...............##",
		"##............................................................##",
		"##........................##........##.......................b##",
		"##a.......=======.........##....4...##........................##",
		"##........................############.........=======........##",
		"##........................############.................#......##",
		"##......#.................############.................#...3..##",
		"##...2..#.................##........##.................#########",
		"#########................e##........##f................#########",
		"#########.........======..##........##..======.........#########",
		"#########...........................................############",
		"############........................................############",
		"############.........0.....................1........############",
		"############....################################....############",
		"############....################################....############"
	]},
	# The Bridges: open air: floating islands and long bridges, one wide pit in the
	# middle of the floor, two passages in each side wall with a ledge under each (G5,
	# 2026-10-10)
	{"name": "THE BRIDGES", "map": [
		"###########################..........###########################",
		"###########################..........###########################",
		"##............................................................##",
		"##............................................................##",
		"##c..........................................................d##",
		"##............................................................##",
		"##................6...........................................##",
		"##.............#######.......................7................##",
		"...............#######....................#######...............",
		"..........................................#######...............",
		"................................................................",
		"............========............................................",
		"#######.....................................========.....#######",
		"#######.................================.................#######",
		"##.....................................................5......##",
		"##.......4..........................................######....##",
		"##....######.................#....#.................######....##",
		"##....######.................#..8.#...........................##",
		"##...........................######...........................##",
		"##..........................g######h..........................##",
		"##............................................3...............##",
		"##................2........................######.............##",
		"...............######......................######...............",
		"...............######...........................................",
		"................................................................",
		"................................................................",
		"##=====..............................======..............=====##",
		"##...................======...................................##",
		"##................................................#######.....##",
		"##.....#######...................................f#######.....##",
		"##a....#######e..............................................b##",
		"##............................................................##",
		"##............................................................##",
		"##....0...................................................1...##",
		"###########################..........###########################",
		"###########################..........###########################"
	]},
]

var id := BENCH
var name := ""
var grid := PackedByteArray()
var rects: Array = []          # [Rect2i in px, kind] (the bench's pieces only)
var spawns: Array[Vector2i] = []   # feet positions
var torches: Array[Vector2] = []

func _init(layout: int = BENCH) -> void:
	id = clampi(layout, 0, LAYOUTS.size() - 1)
	var lay: Dictionary = LAYOUTS[id]
	name = lay["name"]
	grid.resize(COLS * ROWS)
	grid.fill(EMPTY)
	if lay.has("pieces"):
		for p in lay["pieces"]:
			_add(p[0], p[1], p[2], p[3], p[4])
			if p[5] == 1:
				_add(COLS - p[0] - p[2], p[1], p[2], p[3], p[4])
		spawns.assign(lay["spawns"])
		torches.assign(lay["torches"])
	else:
		_read_map(lay["map"])

static func count() -> int:
	return LAYOUTS.size()

static func name_of(layout: int) -> String:
	return LAYOUTS[clampi(layout, 0, LAYOUTS.size() - 1)]["name"]

func _read_map(lines: Array) -> void:
	var spots := {}
	var lights := {}
	for cy in ROWS:
		var line: String = lines[cy] if cy < lines.size() else ""
		if line.length() != COLS:
			push_error("level %s: line %d has %d characters, not %d" % [name, cy, line.length(), COLS])
		for cx in mini(COLS, line.length()):
			var ch := line.unicode_at(cx)
			if ch == 35:          # '#'
				grid[cy * COLS + cx] = SOLID
			elif ch == 61:        # '='
				grid[cy * COLS + cx] = LEDGE
			elif ch >= 48 and ch <= 57:   # a digit: a spawn spot
				spots[ch - 48] = Vector2i(cx * CELL, (cy + 1) * CELL)
			elif ch >= 97 and ch <= 104:  # a..h: a torch
				lights[ch - 97] = Vector2(cx * CELL + CELL / 2, cy * CELL + CELL / 2)
	var keys := spots.keys()
	keys.sort()
	for k in keys:
		spawns.append(spots[k])
	keys = lights.keys()
	keys.sort()
	for k in keys:
		torches.append(lights[k])

func _add(x: int, y: int, w: int, h: int, kind: int) -> void:
	rects.append([Rect2i(x * CELL, y * CELL, w * CELL, h * CELL), kind])
	for cy in range(y, y + h):
		for cx in range(x, x + w):
			grid[cy * COLS + cx] = kind

# The body (36 x 63) stands with the middle of its feet at s: a block or a
# ledge under it, no block in it (input_probe rule 27, tools/arena_probe.gd).
func stands(s: Vector2i) -> bool:
	if posmod(s.y, CELL) != 0:
		return false
	var under := false
	for cx in range(floori((s.x - 18) / 30.0), floori((s.x + 17) / 30.0) + 1):
		if cell(cx, s.y / CELL) != EMPTY:
			under = true
		for cy in range(floori((s.y - 63) / 30.0), floori((s.y - 1) / 30.0) + 1):
			if cell(cx, cy) == SOLID:
				return false
	return under

# b is below a, less than reach px to the side, and some column between them is
# open (no block, no other ledge) from under a's ledge down to b's head.
func one_drop(a: Vector2i, b: Vector2i, reach: int) -> bool:
	if b.y <= a.y or absi(a.x - b.x) >= reach:
		return false
	var top: int = a.y / CELL + 1
	var head: int = floori((b.y - 63) / 30.0)
	for cx in range(floori((mini(a.x, b.x) - 18) / 30.0), floori((maxi(a.x, b.x) + 17) / 30.0) + 1):
		var open := true
		for cy in range(top, head):
			if cell(cx, cy) != EMPTY:
				open = false
				break
		if open:
			return true
	return false

func cell(cx: int, cy: int) -> int:
	return grid[posmod(cy, ROWS) * COLS + posmod(cx, COLS)]

func cell_at(px: float, py: float) -> int:
	return cell(floori(px / CELL), floori(py / CELL))

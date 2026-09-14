# The benchmark arena: 1920 x 1080, a 30 px collision grid (64 x 36 cells), wrap
# on all four edges (a gap in the floor and ceiling, a passage in each side wall).
# One-way ledges are LEDGE cells: you jump up through them and land on their top.
# Pieces marked mirror=1 are copied to the other side, so the map is balanced.
extends RefCounted

const CELL := 30
const COLS := 64
const ROWS := 36
const W := 1920
const H := 1080
const EMPTY := 0
const SOLID := 1
const LEDGE := 2

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

var grid := PackedByteArray()
var rects: Array = []          # [Rect2i in px, kind] for drawing
var spawns: Array[Vector2i] = []   # feet positions
var torches: Array[Vector2] = []

func _init() -> void:
	grid.resize(COLS * ROWS)
	grid.fill(EMPTY)
	for p in PIECES:
		_add(p[0], p[1], p[2], p[3], p[4])
		if p[5] == 1:
			_add(COLS - p[0] - p[2], p[1], p[2], p[3], p[4])
	spawns = [Vector2i(240, 1020), Vector2i(1680, 1020), Vector2i(300, 900), Vector2i(1620, 900),
		Vector2i(255, 540), Vector2i(1665, 540), Vector2i(270, 180), Vector2i(1650, 180),
		Vector2i(960, 420), Vector2i(960, 660)]
	torches = [Vector2(78, 300), Vector2(1842, 300), Vector2(78, 800), Vector2(1842, 800),
		Vector2(660, 560), Vector2(1260, 560), Vector2(960, 120), Vector2(960, 930)]

func _add(x: int, y: int, w: int, h: int, kind: int) -> void:
	rects.append([Rect2i(x * CELL, y * CELL, w * CELL, h * CELL), kind])
	for cy in range(y, y + h):
		for cx in range(x, x + w):
			grid[cy * COLS + cx] = kind

func cell(cx: int, cy: int) -> int:
	return grid[posmod(cy, ROWS) * COLS + posmod(cx, COLS)]

func cell_at(px: float, py: float) -> int:
	return cell(floori(px / CELL), floori(py / CELL))

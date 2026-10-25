# The look polish of 2026-10-25 for the castle arenas (THE KEEP, THE BRIDGES, the bench:
# theme ""): detail on the arena's shapes that keeps the tiles' own detail, and keeps
# the play space easy to read. client/polish.gd has a switch for each piece:
#   castle_depth    a soft shade deep inside big blocks: their edges read lit, their middles recede
#   castle_moss     moss tufts on some tops you stand on, ivy hanging under ceilings and overhangs
#   castle_ledges   iron brackets where a plank meets a wall, chains from a floating plank up to the block above
#   castle_sconces  iron wall sconces with glowing coals for the torches (the old sprite was a plain
#                   stick); on LOW, where there are no flame particles, a small flickering flame in each
# p4.14 the user picked code-drawn detail for two more arenas' platforms (ComfyUI changed
# their shapes): THE HAUNTED HOUSE (hh_dress: cobwebs in the top inner corners, a few faint
# cracks, candles with flickering flames, little skulls, purple moss, dark roots under
# ceilings) and THE BOILER ROOM (boiler_dress: rivet rows on steel tops, rust drips, oil
# stains under overhangs, short hazard stripes; world.gd lifts this node over the boiler's
# picture there).
# world.gd puts this node over the tiles (the lit layer: the night darkens it and the
# torches light it, like the stone) and calls build() for each arena and look. Drawn once;
# only the flames move (the LOW sconces, the candles).
extends Node2D

const Polish = preload("res://client/polish.gd")
const HALO := preload("res://assets/fx_halo.png")
const C := 30                     # the grid (sim/level.gd CELL)
const IRON := Color(0.16, 0.15, 0.2)
const IRON_HI := Color(0.42, 0.4, 0.48)
const MOSS := [Color(0.2, 0.42, 0.3), Color(0.3, 0.6, 0.4), Color(0.42, 0.74, 0.5)]

var level
var castle := false
var hh := false                   # p4.14 hh_dress: THE HAUNTED HOUSE's dressing
var nightmare := false            # p4.14 boiler_dress: THE BOILER ROOM's dressing
var candles: Array = []           # hh_dress: where each candle's flame sits
var depth := PackedByteArray()    # castle_depth: each block cell's distance (in cells) to the nearest open cell
var flames := _Flames.new()       # castle_sconces on LOW: the torch flames, added light on the glow layer
var t := 0.0

class _Flames extends Node2D:
	var dv
	func _draw() -> void:
		if dv != null:
			dv._paint_flames(self)

func setup(glow_parent: Node2D, add_mat: Material) -> void:
	flames.dv = self
	flames.material = add_mat
	flames.visible = false
	glow_parent.add_child(flames)

# A new arena or a new look (particles: the look draws flame particles at the torches).
func build(lv, particles: bool) -> void:
	level = lv
	castle = lv.theme == ""
	hh = lv.theme == "halloween" and Polish.on("hh_dress")
	nightmare = lv.theme == "nightmare" and Polish.on("boiler_dress")
	visible = castle or hh or nightmare
	candles = _find_candles() if hh else []
	flames.visible = (castle and not particles and Polish.on("castle_sconces")) or (hh and not candles.is_empty())
	if castle and Polish.on("castle_depth"):
		_measure_depth()
	queue_redraw()
	flames.queue_redraw()

func _process(delta: float) -> void:
	if flames.visible:
		t += delta
		flames.queue_redraw()

static func _hash(x: int, y: int, salt: int) -> int:
	return ((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0x7fffffff

func _solid(cx: int, cy: int) -> bool:
	if cx < 0 or cy < 0 or cx >= level.COLS or cy >= level.ROWS:
		return true   # past the edge counts as rock: the outer walls' far side stays dark
	return level.cell(cx, cy) == level.SOLID

# Each block cell's distance to the nearest open cell (8 neighbours), at most 6.
func _measure_depth() -> void:
	var cols: int = level.COLS
	var rows: int = level.ROWS
	depth.resize(cols * rows)
	var queue: Array[Vector2i] = []
	for cy in rows:
		for cx in cols:
			var open := not _solid(cx, cy)
			depth[cy * cols + cx] = 0 if open else 6
			if open:
				queue.append(Vector2i(cx, cy))
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d: int = depth[c.y * cols + c.x]
		if d >= 5:
			continue
		for oy in [-1, 0, 1]:
			for ox in [-1, 0, 1]:
				var n := Vector2i(c.x + ox, c.y + oy)
				if n.x < 0 or n.y < 0 or n.x >= cols or n.y >= rows:
					continue
				if depth[n.y * cols + n.x] > d + 1:
					depth[n.y * cols + n.x] = d + 1
					queue.append(n)

func _depth_at(cx: int, cy: int) -> float:
	var cols: int = level.COLS
	cx = clampi(cx, 0, cols - 1)
	cy = clampi(cy, 0, level.ROWS - 1)
	return float(depth[cy * cols + cx])

func _draw() -> void:
	if level == null:
		return
	if hh:
		_paint_hh()
		return
	if nightmare:
		_paint_boiler()
		return
	if not castle:
		return
	if Polish.on("castle_depth"):
		_paint_depth()
	if Polish.on("castle_moss"):
		_paint_moss()
	if Polish.on("castle_ledges"):
		_paint_ledges()
	if Polish.on("castle_sconces"):
		for p in level.torches:
			_sconce(p)

# castle_depth: each corner of a block cell gets the mean depth of the 4 cells around
# it; the shade grows from the second cell in, so a block's edge keeps its full light.
func _paint_depth() -> void:
	var cols: int = level.COLS
	var rows: int = level.ROWS
	var corner := PackedFloat32Array()
	corner.resize((cols + 1) * (rows + 1))
	for vy in rows + 1:
		for vx in cols + 1:
			var s := _depth_at(vx - 1, vy - 1) + _depth_at(vx, vy - 1) + _depth_at(vx - 1, vy) + _depth_at(vx, vy)
			corner[vy * (cols + 1) + vx] = clampf((s * 0.25 - 1.6) * 0.1, 0.0, 0.3)
	for cy in rows:
		for cx in cols:
			if not _solid(cx, cy):
				continue
			var a0 := corner[cy * (cols + 1) + cx]
			var a1 := corner[cy * (cols + 1) + cx + 1]
			var a2 := corner[(cy + 1) * (cols + 1) + cx + 1]
			var a3 := corner[(cy + 1) * (cols + 1) + cx]
			if a0 + a1 + a2 + a3 <= 0.0:
				continue
			var x := cx * C
			var y := cy * C
			draw_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + C, y), Vector2(x + C, y + C), Vector2(x, y + C)]),
				PackedColorArray([Color(0.01, 0.0, 0.03, a0), Color(0.01, 0.0, 0.03, a1), Color(0.01, 0.0, 0.03, a2), Color(0.01, 0.0, 0.03, a3)]))

# castle_moss: a tuft on about one top in four, ivy under about one ceiling cell in five.
func _paint_moss() -> void:
	var rows: int = level.ROWS
	var cols: int = level.COLS
	for cy in rows:
		for cx in cols:
			if not _solid(cx, cy) or cy == 0:
				continue
			var x := cx * C
			var y := cy * C
			if not _solid(cx, cy - 1) and level.cell(cx, cy - 1) == 0 and _hash(cx, cy, 1) % 4 == 0:
				var h := _hash(cx, cy, 2)
				var bx: int = x + 4 + h % 18
				for k in 5:   # blades up from the top edge, and a clump on the face
					var bh := 2 + (h >> (k + 3)) % 5
					draw_rect(Rect2(bx + k * 2, y - bh, 2, bh), MOSS[(h >> k) % 3])
				draw_rect(Rect2(bx - 2, y, 14, 3), MOSS[1])
				draw_rect(Rect2(bx + 1, y + 3, 8, 2), MOSS[0])
			if cy + 1 < rows and level.cell(cx, cy + 1) == 0 and _hash(cx, cy, 3) % 5 == 0:
				_vine(Vector2(x + 6 + _hash(cx, cy, 4) % 18, y + C), 16 + _hash(cx, cy, 5) % 42, _hash(cx, cy, 6))

func _vine(top: Vector2, length: int, h: int) -> void:
	var stem := Color(0.14, 0.3, 0.18)
	var pts := PackedVector2Array()
	for s in range(0, length + 1, 3):
		pts.append(top + Vector2(sin(s * 0.22 + h % 7) * 2.5, s))
	draw_polyline(pts, stem, 2.0)
	for k in range(1, pts.size()):
		if k % 2 == 0:
			var side := 1.0 if (k / 2 + h) % 2 == 0 else -1.0
			var p: Vector2 = pts[k]
			draw_rect(Rect2(p.x + (1.0 if side > 0 else -4.0), p.y - 1, 3, 2), MOSS[(h + k) % 3])
			draw_rect(Rect2(p.x + (2.0 if side > 0 else -4.0), p.y - 2, 2, 1), MOSS[2])

# castle_ledges: brackets where a plank's end meets a block; a floating plank hangs on two
# chains from the block above it, when there is one within 7 cells.
func _paint_ledges() -> void:
	for cy in level.ROWS:
		var run := -1
		for cx in level.COLS + 1:
			var is_ledge: bool = cx < level.COLS and level.cell(cx, cy) == level.LEDGE
			if is_ledge and run < 0:
				run = cx
			elif not is_ledge and run >= 0:
				_ledge(run, cx, cy)
				run = -1

func _ledge(c0: int, c1: int, cy: int) -> void:
	var y := cy * C
	var cols: int = level.COLS
	var wall_l: bool = _solid(c0 - 1, cy) and c0 > 0
	var wall_r: bool = _solid(c1, cy) and c1 < cols
	if wall_l:
		_bracket(Vector2(c0 * C, y), 1.0)
	if wall_r:
		_bracket(Vector2(c1 * C, y), -1.0)
	if wall_l or wall_r:
		return
	for cx in [c0, c1 - 1]:
		for up in range(1, 8):
			var ry: int = cy - up
			if ry < 0:
				break
			if _solid(cx, ry):
				_chain(cx * C + (9 if cx == c0 else 21), (ry + 1) * C, y + 2)
				break
			if level.cell(cx, ry) == level.LEDGE:
				break

func _bracket(at: Vector2, dir: float) -> void:
	# a plate on the wall, a strut under the plank, a rivet
	draw_rect(Rect2(at.x - (3.0 if dir > 0 else 0.0), at.y + 10, 3, 18), IRON)
	draw_line(at + Vector2(dir * 1.0, 26), at + Vector2(dir * 16.0, 12), IRON, 4.0)
	draw_line(at + Vector2(dir * 1.0, 24), at + Vector2(dir * 14.0, 12), IRON_HI, 1.0)
	draw_rect(Rect2(at.x + dir * 2.0 - 1.0, at.y + 12, 2, 2), IRON_HI)

func _chain(x: float, y0: float, y1: float) -> void:
	var y := y0
	var k := 0
	while y < y1 - 4:
		if k % 2 == 0:   # a link seen face on: a ring
			draw_rect(Rect2(x - 3, y, 6, 2), IRON)
			draw_rect(Rect2(x - 3, y + 5, 6, 2), IRON)
			draw_rect(Rect2(x - 3, y, 2, 7), IRON)
			draw_rect(Rect2(x + 1, y, 2, 7), IRON)
			draw_rect(Rect2(x - 3, y, 1, 7), IRON_HI)
		else:            # a link seen edge on: a bar
			draw_rect(Rect2(x - 1, y, 2, 7), IRON)
			draw_rect(Rect2(x - 1, y, 1, 7), IRON_HI)
		y += 6.0
		k += 1
	draw_rect(Rect2(x - 4, y1 - 4, 8, 3), IRON)   # the ring on the plank

# castle_sconces: a wall plate, an arm, a bowl with glowing coals (the flame sits on top).
func _sconce(p: Vector2) -> void:
	draw_rect(Rect2(p.x - 7, p.y - 2, 14, 22), IRON)                     # the plate
	draw_rect(Rect2(p.x - 7, p.y - 2, 1, 22), IRON_HI)
	draw_rect(Rect2(p.x - 1, p.y + 1, 2, 2), IRON_HI)                    # rivets
	draw_rect(Rect2(p.x - 1, p.y + 15, 2, 2), IRON_HI)
	draw_rect(Rect2(p.x - 2, p.y - 19, 4, 19), IRON)                     # the arm
	draw_line(Vector2(p.x - 2, p.y - 8), Vector2(p.x - 7, p.y - 12), IRON, 2.0)   # its curls
	draw_line(Vector2(p.x + 2, p.y - 8), Vector2(p.x + 7, p.y - 12), IRON, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(p.x - 13, p.y - 27), Vector2(p.x + 13, p.y - 27), Vector2(p.x + 7, p.y - 19),
		Vector2(p.x - 7, p.y - 19)]), IRON)                                   # the bowl
	draw_rect(Rect2(p.x - 13, p.y - 28, 26, 2), IRON_HI)                 # its rim
	draw_rect(Rect2(p.x - 10, p.y - 30, 20, 2), Color(2.4, 0.9, 0.3))    # the coals (over 1: the night darkens them)
	draw_rect(Rect2(p.x - 6, p.y - 31, 12, 1), Color(2.6, 1.5, 0.5))

# castle_sconces on LOW: a flame over each bowl, flickering (no particles on LOW); hh_dress:
# a small flame on each candle.
func _paint_flames(n: Node2D) -> void:
	if hh:
		for i in candles.size():
			var cp: Vector2 = candles[i]
			var ck := 0.8 + 0.2 * sin(t * 11.0 + i * 2.1) * sin(t * 6.7 + i)
			n.draw_texture_rect(HALO, Rect2(cp - Vector2(30, 32), Vector2(60, 52)), false, Color(1.0, 0.6, 0.25, 0.45 * ck))
			var sw := sin(t * 8.0 + i * 1.7) * 0.8
			n.draw_colored_polygon(PackedVector2Array([cp + Vector2(-2.5 * ck, 0), cp + Vector2(sw, -8.0 * ck), cp + Vector2(2.5 * ck, 0),
				cp + Vector2(0, 1.5)]), Color(1.0, 0.62, 0.2, 0.95))
			n.draw_colored_polygon(PackedVector2Array([cp + Vector2(-1.2, -0.5), cp + Vector2(sw * 0.6, -5.0 * ck), cp + Vector2(1.2, -0.5)]),
				Color(1.0, 0.95, 0.7))
		return
	for i in level.torches.size():
		var p: Vector2 = level.torches[i] + Vector2(0, -31)
		var k := 0.85 + 0.15 * sin(t * 13.0 + i * 1.9) * sin(t * 7.3 + i)
		var sway := sin(t * 9.0 + i * 2.3) * 1.5
		n.draw_texture_rect(HALO, Rect2(p - Vector2(34, 40), Vector2(68, 64)), false, Color(1.0, 0.55, 0.2, 0.35 * k))
		for layer in 3:
			var w: float = [9.0, 6.0, 3.0][layer] * k
			var h: float = [20.0, 14.0, 8.0][layer] * k
			var col: Color = [Color(1.0, 0.42, 0.1, 0.9), Color(1.0, 0.72, 0.25), Color(1.0, 0.95, 0.7)][layer]
			n.draw_colored_polygon(PackedVector2Array([p + Vector2(-w, 0), p + Vector2(-w * 0.7, -h * 0.45), p + Vector2(sway, -h),
				p + Vector2(w * 0.7, -h * 0.45), p + Vector2(w, 0), p + Vector2(0, w * 0.35)]), col)

# ---------------------------------------------------------------- p4.14 THE HAUNTED HOUSE
const WEB := Color(0.92, 0.92, 1.0, 0.55)
const ROOT := Color(0.2, 0.11, 0.16)
const ROOT_HI := Color(0.34, 0.2, 0.26)
const HH_MOSS := [Color(0.24, 0.3, 0.3), Color(0.32, 0.4, 0.36), Color(0.42, 0.5, 0.44)]
const BONE := Color(1.0, 0.98, 0.9)
const BONE_D := Color(0.62, 0.6, 0.56)
const HOLE := Color(0.1, 0.05, 0.12)
const WAX := Color(0.94, 0.9, 0.78)

# Tops you stand on (a block cell with open air above): a candle on about one in seven,
# never two side by side, never on the outer floor's edge.
func _find_candles() -> Array:
	var out: Array = []
	var last := -9
	for cy in range(1, level.ROWS):
		for cx in range(1, level.COLS - 1):
			if _solid(cx, cy) and level.cell(cx, cy - 1) == 0 and _hash(cx, cy, 11) % 5 == 0 and absi(cx - last) > 2:
				out.append(Vector2(cx * C + 8 + _hash(cx, cy, 12) % 14, cy * C - 9))
				last = cx
	return out

func _paint_hh() -> void:
	var rows: int = level.ROWS
	var cols: int = level.COLS
	for cy in rows:
		for cx in cols:
			var x := cx * C
			var y := cy * C
			if not _solid(cx, cy):
				# a cobweb in a top inner corner: a wall on one side, a ceiling above
				if cy > 0 and level.cell(cx, cy) == 0 and _solid(cx, cy - 1):
					if _solid(cx - 1, cy):
						_web(Vector2(x, y), 1.0, 24 + _hash(cx, cy, 14) % 12)
					if _solid(cx + 1, cy):
						_web(Vector2(x + C, y), -1.0, 24 + _hash(cx, cy, 16) % 12)
				continue
			var open_up: bool = cy > 0 and level.cell(cx, cy - 1) == 0
			if open_up and _hash(cx, cy, 17) % 3 == 0:   # a purple-grey moss tuft on a top
				var h := _hash(cx, cy, 18)
				var bx: int = x + 4 + h % 18
				for k in 4:
					var bh := 2 + (h >> (k + 3)) % 4
					draw_rect(Rect2(bx + k * 2, y - bh, 2, bh), HH_MOSS[(h >> k) % 3])
				draw_rect(Rect2(bx - 2, y, 12, 2), HH_MOSS[1])
			elif open_up and _hash(cx, cy, 19) % 6 == 0 and not _has_candle(cx, cy):   # a little skull on a top
				_skull(Vector2(x + 8 + _hash(cx, cy, 20) % 12, y - 7))
			if cy + 1 < rows and level.cell(cx, cy + 1) == 0 and _hash(cx, cy, 21) % 3 == 0:   # a root under a ceiling
				_root(Vector2(x + 5 + _hash(cx, cy, 22) % 20, y + C), 18 + _hash(cx, cy, 23) % 40, _hash(cx, cy, 24))
			if _hash(cx, cy, 25) % 7 == 0 and (open_up or not _solid(cx - 1, cy) or not _solid(cx + 1, cy)):   # a faint crack on a face
				var hc := _hash(cx, cy, 26)
				var p0 := Vector2(x + 6 + hc % 16, y + 4 + (hc >> 4) % 8)
				draw_polyline(PackedVector2Array([p0, p0 + Vector2(3, 5), p0 + Vector2(1, 9), p0 + Vector2(5, 14)]), Color(0.04, 0.02, 0.07, 0.3), 1.0)
	for cp in candles:   # the candles (their flames are on the glow layer)
		var c: Vector2 = cp
		draw_rect(Rect2(c.x - 3, c.y - 1, 6, 10), WAX)
		draw_rect(Rect2(c.x - 3, c.y - 1, 1, 10), Color(1.2, 1.2, 1.1))
		draw_rect(Rect2(c.x + 2, c.y + 3, 2, 4), WAX)          # a drip
		draw_rect(Rect2(c.x - 4, c.y + 8, 8, 1), Color(0.7, 0.66, 0.56))
		draw_line(c + Vector2(0, 1), c + Vector2(0, -1), Color(0.15, 0.1, 0.1), 1.0)   # the wick

func _has_candle(cx: int, cy: int) -> bool:
	for cp in candles:
		var c: Vector2 = cp
		if int(c.x) / C == cx and int(c.y + 9) / C == cy:
			return true
	return false

# A cobweb from a corner: threads out from it and three curved rings between them.
func _web(corner: Vector2, dir: float, r: int) -> void:
	var spokes := [0.0, 0.42, 0.85, 1.28]
	for a in spokes:
		draw_line(corner, corner + Vector2(dir * cos(a), sin(a)) * r, WEB, 1.0)
	for ring in [0.35, 0.65, 0.95]:
		var pts := PackedVector2Array()
		for a in spokes:
			pts.append(corner + Vector2(dir * cos(a), sin(a)) * (r * ring + (1.5 if a == 0.42 or a == 0.85 else 0.0)))
		draw_polyline(pts, WEB, 1.0)

func _skull(at: Vector2) -> void:
	at += Vector2(0, -3)
	draw_rect(Rect2(at.x - 5, at.y, 11, 7), BONE)         # the head
	draw_rect(Rect2(at.x - 4, at.y - 2, 9, 2), BONE)
	draw_rect(Rect2(at.x - 3, at.y + 7, 7, 3), BONE_D)    # the jaw
	draw_rect(Rect2(at.x - 3, at.y + 2, 3, 3), HOLE)      # the eyes
	draw_rect(Rect2(at.x + 1, at.y + 2, 3, 3), HOLE)
	draw_rect(Rect2(at.x, at.y + 5, 1, 2), HOLE)          # the nose
	draw_rect(Rect2(at.x - 2, at.y + 8, 1, 1), HOLE)      # teeth
	draw_rect(Rect2(at.x + 1, at.y + 8, 1, 1), HOLE)

func _root(top: Vector2, length: int, h: int) -> void:
	var pts := PackedVector2Array()
	for s in range(0, length + 1, 3):
		pts.append(top + Vector2(sin(s * 0.3 + h % 5) * 2.0 + s * 0.06 * (1 if h % 2 == 0 else -1), s))
	draw_polyline(pts, ROOT, 3.0)
	draw_polyline(pts, ROOT_HI, 1.0)
	if pts.size() > 4:   # a little side root
		var mid: Vector2 = pts[pts.size() / 2]
		var side := 1.0 if (h >> 3) % 2 == 0 else -1.0
		draw_line(mid, mid + Vector2(side * 5.0, 6.0), ROOT, 1.0)

# ---------------------------------------------------------------- p4.14 THE BOILER ROOM
const RIVET := Color(0.62, 0.58, 0.54)
const RIVET_D := Color(0.1, 0.08, 0.08)
const RUST := Color(0.55, 0.26, 0.1)
const HAZ_Y := Color(0.86, 0.68, 0.14)
const HAZ_K := Color(0.08, 0.07, 0.06)

func _paint_boiler() -> void:
	var rows: int = level.ROWS
	var cols: int = level.COLS
	for cy in rows:
		for cx in cols:
			if not _solid(cx, cy):
				continue
			var x := cx * C
			var y := cy * C
			var open_up: bool = cy > 0 and level.cell(cx, cy - 1) == 0
			var open_dn: bool = cy + 1 < rows and level.cell(cx, cy + 1) == 0
			if open_up:                                    # a row of rivets just under the top
				for k in range(4, C - 2, 6):
					draw_rect(Rect2(x + k, y + 4, 3, 3), RIVET)
					draw_rect(Rect2(x + k + 2, y + 6, 1, 1), RIVET_D)
			if open_up and _hash(cx, cy, 32) % 6 == 0:    # a short band of hazard stripes along a top
				draw_rect(Rect2(x, y, C, 5), HAZ_K)
				for k in range(0, C, 6):
					draw_colored_polygon(PackedVector2Array([Vector2(x + k, y), Vector2(x + k + 3, y), Vector2(x + k, y + 5),
						Vector2(x + k - 3, y + 5)]), HAZ_Y)
			if _hash(cx, cy, 33) % 4 == 0:                 # a rust drip running down from a seam
				var hx := x + 3 + _hash(cx, cy, 34) % 24
				var ln := 6 + _hash(cx, cy, 35) % 16
				for k in ln:
					draw_rect(Rect2(hx, y + 6 + k, 3 if k < ln - 3 else 2, 1), Color(RUST, 0.85 * (1.0 - float(k) / ln)))
			if open_dn and _hash(cx, cy, 36) % 4 == 0:     # an oil stain dripping under an overhang
				var ox := x + 6 + _hash(cx, cy, 37) % 18
				draw_rect(Rect2(ox - 3, y + C - 3, 8, 3), Color(0.03, 0.02, 0.02, 0.5))
				draw_rect(Rect2(ox, y + C, 2, 3 + _hash(cx, cy, 38) % 5), Color(0.03, 0.02, 0.02, 0.45))


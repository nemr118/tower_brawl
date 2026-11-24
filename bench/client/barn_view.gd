# THE HARVEST BARN's look (theme "barn", sim/level.gd), for Thanksgiving: late on a
# harvest afternoon. world.gd makes one (behind the tiles), calls setup once and
# set_theme on each arena and look. Drawn by hand, all of it, on every look. What goes
# where:
#   still (behind this node, the lit world, drawn once): the sky and the low sun, far
#     hills, the tree line, the fields (corn shocks, a pumpkin patch, a fence), the
#     barn's dark inside with its boards and the open hay door at the back, the silo's
#     round body and dome, the old trees' limbs and leaves;
#   this node (the lit world, behind the blocks, 30 times a second): the weather vane
#     on the ridge, geese far away;
#   blocks (the lit world, where the stone tiles were, drawn once): every block and
#     ledge. The barn is red boards with white trim, the hay is bales with twine, the
#     silo's chute is riveted steel, the wagon is planks on two wheels, the floor is
#     earth with a grass top, the side walls are tree trunks and the ceiling is their
#     leaves. Every top you can stand on gets a bright lip, and every ledge is a pale
#     plank with a dark line under it, so the shapes read at a glance. Nothing is
#     drawn past a block's own cells: the shapes stay true;
#   front (the threats layer, under the fighters, 30 times a second): the lanterns
#     where the torches were, the falling leaves, straw dust in the barn.
# The night turns into a warm afternoon (world.dark_base), the castle's backdrops,
# tiles and torch sprites hide, and the fog, the light shafts, the spirit lights and
# the embers rest; set_theme puts all of it back on another arena. LOW (no particles)
# gets fewer leaves, no dust and no geese.
# Cheap on phones: almost everything is plain boxes (the renderer draws those in a few
# batches); round things are three boxes each, which suits the pixel look too.
# Nothing here reads the layout's number: the theme picks the look, and the shapes
# come from the level's own grid.
extends Node2D

const HALO := preload("res://assets/fx_halo.png")
const C := 30                     # the grid (sim/level.gd CELL)
const REDRAW_HZ := 30.0           # the moving parts are drawn again 30 times a second (cheaper on phones)
const DAY := Color(0.84, 0.76, 0.7)        # the afternoon (world.dark_base): it tints the lit world
const LAMP := Color(0.62, 0.42, 0.2)       # a lantern's light (dim: it is still day)
const SUN := Vector2(300, 726)
const HORIZON := 812.0
# what a block is made of
const K_BARN := 1
const K_HAY := 2
const K_SILO := 3
const K_WAGON := 4
const K_GROUND := 5
const K_TRUNK := 6
const K_CANOPY := 7
# the cols the barn's walls stand in (the yards are outside them)
const BARN_C0 := 18
const BARN_C1 := 45
# the colours
const RED := Color(0.72, 0.15, 0.11)
const RED_D := Color(0.5, 0.09, 0.07)
const RED_L := Color(0.82, 0.22, 0.15)
const RED_M := Color(0.63, 0.12, 0.09)
const TRIM := Color(0.97, 0.94, 0.86)
const TRIM_D := Color(0.3, 0.07, 0.05)
const STRAW := Color(0.9, 0.72, 0.3)
const STRAW_L := Color(1.0, 0.9, 0.56)
const STRAW_D := Color(0.6, 0.42, 0.13)
const TWINE := Color(0.68, 0.4, 0.14)
const STEEL := Color(0.68, 0.75, 0.8)
const STEEL_L := Color(0.9, 0.94, 0.97)
const STEEL_D := Color(0.4, 0.48, 0.57)
const STEEL_K := Color(0.14, 0.18, 0.25)
const WOOD := Color(0.56, 0.37, 0.19)
const WOOD_L := Color(0.84, 0.64, 0.38)
const WOOD_D := Color(0.24, 0.13, 0.06)
const EARTH := Color(0.42, 0.28, 0.17)
const EARTH_D := Color(0.27, 0.17, 0.1)
const GRASS := Color(0.86, 0.8, 0.36)
const GRASS_D := Color(0.5, 0.48, 0.18)
const BARK := Color(0.38, 0.25, 0.16)
const BARK_L := Color(0.66, 0.5, 0.34)
const BARK_D := Color(0.2, 0.12, 0.07)
const PLANK := Color(0.8, 0.58, 0.32)
const PLANK_L := Color(1.0, 0.9, 0.62)
const PLANK_D := Color(0.22, 0.12, 0.05)
const WALL_IN := Color(0.2, 0.085, 0.07)     # the barn's inside, far behind the play space
const WALL_LINE := Color(0.3, 0.13, 0.1)
const DOOR_TRIM := Color(0.42, 0.33, 0.29)
const IRON := Color(0.1, 0.08, 0.08)
# a block's dark line (under it, beside it, under its lip) and its lip, by kind
const LINES := [Color.BLACK, TRIM_D, Color(0.38, 0.25, 0.07), STEEL_K, WOOD_D, Color(0.18, 0.11, 0.06), BARK_D, Color(0.14, 0.05, 0.03)]
const LIPS := [Color.WHITE, TRIM, STRAW_L, Color(0.97, 0.99, 1.0), WOOD_L, GRASS, Color(0.76, 0.6, 0.42), Color.WHITE]
const LEAF_COLS := [Color(0.95, 0.5, 0.1), Color(0.86, 0.22, 0.1), Color(0.98, 0.76, 0.2), Color(0.72, 0.3, 0.08), Color(0.92, 0.62, 0.14)]
const BUNCH_COLS := [Color(0.5, 0.17, 0.08), Color(0.72, 0.32, 0.08), Color(0.86, 0.52, 0.12), Color(0.62, 0.2, 0.08)]
const LEAVES_LOW := 14
const LEAVES := 40
const DUST := 22
# the old trees' limbs under the yard's planks, far side [from, through, to] (px)
const LIMBS := [
	[Vector2(60, 236), Vector2(200, 208), Vector2(330, 201)],
	[Vector2(176, 344), Vector2(250, 328), Vector2(330, 321)],
	[Vector2(176, 356), Vector2(300, 444), Vector2(480, 441)],
	[Vector2(60, 596), Vector2(170, 566), Vector2(270, 561)],
	[Vector2(60, 742), Vector2(240, 690), Vector2(420, 681)],
	[Vector2(1860, 268), Vector2(1720, 238), Vector2(1590, 231)],
	[Vector2(1860, 704), Vector2(1810, 684), Vector2(1770, 681)],
	[Vector2(1860, 948), Vector2(1800, 926), Vector2(1740, 921)]]

var world
var level
var on := false
var rich := false                 # NORMAL and HIGH (the look has particles): more leaves, dust, geese
var t := 0.0
var redraw_wait := 0.0
var still: _Layer
var blocks: _Layer
var front: _Layer
var kinds := PackedByteArray()    # each cell: 0, or what its block is made of
var lamps: Array = []             # [flame's place, hangs from: 0 a chain up, -1 a wall on the left, 1 on the right, top of the chain]
var loft_y := 580.0               # the loft's floor (the top of the walls under the hay doors)

class _Layer extends Node2D:
	var bv
	var which := 0
	func _draw() -> void:
		if bv != null and bv.on:
			bv._paint(self, which)

func setup(w) -> void:
	world = w
	visible = false
	light_mask = 0                 # the sky and the scenery take no light: a flash of lightning must not turn the day white
	still = _new_layer(0)
	still.show_behind_parent = true
	still.light_mask = 0
	add_child(still)
	blocks = _new_layer(1)
	world.add_child(blocks)
	world.move_child(blocks, world.tiles_lit.get_index() + 1)   # where the tiles are
	front = _new_layer(2)
	world.threats.add_child(front)
	world.threats.move_child(front, 0)                          # under the fighters

func _new_layer(which: int) -> _Layer:
	var n := _Layer.new()
	n.bv = self
	n.which = which
	n.visible = false
	return n

# Another arena, or another look. On the barn the backdrop and the blocks are ours.
# Elsewhere everything goes back (the boiler room hides the same things itself, just
# before this runs, so there we leave them hidden).
func set_theme(lv) -> void:
	var was := on
	level = lv
	on = lv.theme == "barn"
	rich = world.parts.get("particles", false)
	visible = on
	for n in [still, blocks, front]:
		n.visible = on
	if on:
		world.dark_base = DAY
		world.dark.color = DAY
		world.bg_far.visible = false
		world.bg_mid.visible = false
		world.tiles_plain.visible = false
		world.tiles_lit.visible = false
		for tr in world.torches:
			tr[0].visible = false     # the stone torch: a lantern takes its place (its light stays)
			tr[2].visible = false
			tr[2].emitting = false
			tr[3].visible = false
			tr[1].color = LAMP
		for f in world.fogs:          # no fog, no light shafts from windows, no spirit lights: a clear day
			f.visible = false
		for sh in world.shafts:
			sh.visible = false
		world._set_wisps(0, 0)
		world.ambient[0].visible = false   # no embers: this barn is full of hay
		world.ambient[0].emitting = false
		# HIGH's bloom makes bright parts brighter still: start a step lower there
		var glare: bool = world.parts.get("bloom", false)
		modulate = Color(0.8, 0.8, 0.82) if glare else Color.WHITE
		blocks.modulate = Color(0.9, 0.9, 0.9) if glare else Color.WHITE
		_scan()
		still.queue_redraw()
		blocks.queue_redraw()
	elif was:
		world._set_fog_layers(world.fog_on)
		for sh in world.shafts:
			sh.visible = world.parts.get("shafts", false)
		world._set_wisps(int(world.parts.get("wisps", 0)), int(world.parts.get("wisp_lights", 0)))
		var fx_on: bool = world.parts.get("particles", false)
		world.ambient[0].visible = fx_on
		world.ambient[0].emitting = fx_on
		if lv.theme != "nightmare":
			world.bg_far.visible = true
			world.bg_mid.visible = true
			var lit: bool = world.parts.get("lit", false)
			world.tiles_plain.visible = not lit
			world.tiles_lit.visible = lit
			for tr in world.torches:
				tr[3].visible = fx_on

func _process(delta: float) -> void:
	if not on:
		return
	t += delta
	redraw_wait -= delta
	if redraw_wait > 0.0:
		return
	redraw_wait = 1.0 / REDRAW_HZ
	queue_redraw()
	front.queue_redraw()

func _paint(n: Node2D, which: int) -> void:
	if which == 0:
		_paint_still(n)
	elif which == 1:
		_paint_blocks(n)
	else:
		_paint_front(n)

static func _h(x: int, y: int, salt: int) -> int:
	return ((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0x7fffffff

# A round shape from three boxes, r.x wide and r.y high each way from c.
static func _blob(n: CanvasItem, c: Vector2, r: Vector2, col: Color) -> void:
	n.draw_rect(Rect2(c.x - r.x, c.y - r.y * 0.45, r.x * 2.0, r.y * 0.9), col)
	n.draw_rect(Rect2(c.x - r.x * 0.8, c.y - r.y * 0.8, r.x * 1.6, r.y * 1.6), col)
	n.draw_rect(Rect2(c.x - r.x * 0.45, c.y - r.y, r.x * 0.9, r.y * 2.0), col)

# A box with a colour at the top and another at the bottom.
static func _fade(n: CanvasItem, r: Rect2, top: Color, low: Color) -> void:
	n.draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
		PackedColorArray([top, top, low, low]))

static func _frame(n: CanvasItem, r: Rect2, col: Color, w: float) -> void:
	n.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, w), col)
	n.draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), col)
	n.draw_rect(Rect2(r.position.x, r.position.y, w, r.size.y), col)
	n.draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), col)

func _solid(cx: int, cy: int) -> bool:
	return level.cell(cx, cy) == level.SOLID

func _kind(cx: int, cy: int) -> int:
	return kinds[posmod(cy, level.ROWS) * level.COLS + posmod(cx, level.COLS)]

# What each block is made of, from where it stands: the ceiling is leaves, the floor
# earth, the side walls (and what grows out of them) tree, the left yard's blocks the
# wagon and its load, the right yard's the silo; in the barn, what stands on the floor
# or on the loft is hay, the rest is the barn. Then the loft's level, and where each
# lantern hangs.
func _scan() -> void:
	var cols: int = level.COLS
	var rows: int = level.ROWS
	kinds.resize(cols * rows)
	kinds.fill(0)
	for cy in rows:
		for cx in cols:
			if not _solid(cx, cy):
				continue
			var k := K_BARN
			if cy < 2:
				k = K_CANOPY
			elif cy >= rows - 2:
				k = K_GROUND
			elif cx < 2 or cx >= cols - 2:
				k = K_TRUNK
			elif cx < BARN_C0:
				k = K_WAGON if cy >= rows - 4 else (K_HAY if cy >= rows - 8 else K_TRUNK)
			elif cx > BARN_C1:
				k = K_SILO
			elif cy >= rows - 6 or (cx > BARN_C0 + 1 and cx < BARN_C1 - 1 and cy > 10):
				k = K_HAY
			kinds[cy * cols + cx] = k
	# down the barn's left wall: the eaves, the hay door's gap, then the wall the loft rests on
	var step := 0
	for cy in range(2, rows - 2):
		var wall := _kind(BARN_C0, cy) == K_BARN
		if (step == 0 and wall) or (step == 1 and not wall):
			step += 1
		elif step == 2 and wall:
			loft_y = cy * C + 10.0
			break
	lamps.clear()
	for p in level.torches:
		var flame: Vector2 = p + Vector2(0, -30)
		var cx := int(p.x / C)
		var cy := int(p.y / C)
		var hang := 0
		var top := flame.y - 60.0
		if _solid(cx - 1, cy) or _solid(cx - 1, cy - 1):
			hang = -1
		elif _solid(cx + 1, cy) or _solid(cx + 1, cy - 1):
			hang = 1
		else:
			for up in range(1, 7):     # the block or the ledge it hangs under
				var c: int = level.cell(cx, cy - up)
				if c != 0:
					top = (cy - up) * C + (C if c == level.SOLID else 11)
					break
		lamps.append([flame, hang, top])

# ------------------------------------------------------------------ behind the blocks, drawn once
func _paint_still(n: Node2D) -> void:
	_sky(n)
	_fields(n)
	_trees(n)
	_silo(n)
	_barn(n)
	# the pits in the floor: dark earth, not sky
	var run := -1
	for cx in level.COLS + 1:
		var pit: bool = cx < level.COLS and not _solid(cx, level.ROWS - 1)
		if pit and run < 0:
			run = cx
		elif not pit and run >= 0:
			_fade(n, Rect2(run * C, 1020, (cx - run) * C, 60), Color(0.2, 0.12, 0.08), Color(0.04, 0.02, 0.02))
			run = -1

func _sky(n: Node2D) -> void:
	var stops := [[0.0, Color(0.27, 0.4, 0.66)], [280.0, Color(0.5, 0.6, 0.78)], [500.0, Color(0.98, 0.82, 0.68)],
		[680.0, Color(1.12, 0.76, 0.46)], [HORIZON + 10.0, Color(1.15, 0.62, 0.3)]]
	for i in stops.size() - 1:
		_fade(n, Rect2(0, stops[i][0], 1920, stops[i + 1][0] - stops[i][0]), stops[i][1], stops[i + 1][1])
	# the low sun and its glow
	n.draw_texture_rect(HALO, Rect2(SUN - Vector2(560, 400), Vector2(1120, 800)), false, Color(1.2, 0.62, 0.2, 0.55))
	n.draw_texture_rect(HALO, Rect2(SUN - Vector2(200, 200), Vector2(400, 400)), false, Color(1.2, 0.85, 0.4, 0.75))
	n.draw_circle(SUN, 58.0, Color(1.2, 0.84, 0.44))
	n.draw_circle(SUN, 52.0, Color(1.25, 1.0, 0.66))
	# long clouds, lit from below [middle, half size]
	for c in [[Vector2(250, 250), Vector2(190, 15)], [Vector2(420, 380), Vector2(130, 11)], [Vector2(1560, 190), Vector2(210, 17)],
			[Vector2(1700, 330), Vector2(120, 10)], [Vector2(980, 96), Vector2(260, 12)], [Vector2(1480, 520), Vector2(90, 8)],
			[Vector2(130, 500), Vector2(110, 9)]]:
		var p: Vector2 = c[0]
		var r: Vector2 = c[1]
		_blob(n, p + Vector2(0, r.y * 0.55), r, Color(1.12, 0.68, 0.48))
		_blob(n, p + Vector2(r.x * 0.3, r.y * 1.0), r * Vector2(0.6, 0.8), Color(1.12, 0.68, 0.48))
		_blob(n, p, r * Vector2(0.94, 0.9), Color(0.66, 0.56, 0.7))
		_blob(n, p + Vector2(-r.x * 0.25, -r.y * 0.7), r * Vector2(0.5, 0.9), Color(0.66, 0.56, 0.7))
	# far hills, hazy in the low light
	for hill in [[786.0, 30.0, 0.0031, 0.6, Color(0.74, 0.5, 0.5)], [800.0, 18.0, 0.0057, 2.4, Color(0.6, 0.4, 0.34)]]:
		var pts := PackedVector2Array([Vector2(0, HORIZON + 12.0)])
		for x in range(0, 1921, 48):
			pts.append(Vector2(x, hill[0] - hill[1] * (0.5 + 0.5 * sin(x * hill[2] + hill[3])) - 6.0 * sin(x * 0.013 + hill[3])))
		pts.append(Vector2(1920, HORIZON + 12.0))
		n.draw_colored_polygon(pts, hill[4])
	# the tree line: round crowns in autumn colours (the barn hides the middle ones)
	var crowns := [Color(0.52, 0.22, 0.1), Color(0.66, 0.34, 0.1), Color(0.44, 0.19, 0.12), Color(0.42, 0.36, 0.14), Color(0.74, 0.46, 0.13)]
	for i in 66:
		var x := i * 30.0 + float(_h(i, 3, 1) % 18)
		if x > 560.0 and x < 1360.0:
			continue
		var r := 13.0 + float(_h(i, 5, 2) % 13)
		_blob(n, Vector2(x, HORIZON + 2.0 - r * 0.45), Vector2(r, r), crowns[_h(i, 7, 3) % crowns.size()])

# The fields from the tree line down to the yard: a far green one, stubble, a ploughed
# one with furrows, then the yard's own grass. Corn shocks on the left, a pumpkin patch
# on the right, a fence along the far field. The strip by the floor stays plain: later
# a turkey runs there, and nothing may hide it.
func _fields(n: Node2D) -> void:
	_fade(n, Rect2(0, HORIZON, 1920, 26), Color(0.5, 0.46, 0.2), Color(0.56, 0.5, 0.22))
	_fade(n, Rect2(0, HORIZON + 26, 1920, 40), Color(0.86, 0.64, 0.28), Color(0.8, 0.58, 0.25))
	_fade(n, Rect2(0, HORIZON + 66, 1920, 62), Color(0.52, 0.34, 0.2), Color(0.46, 0.3, 0.17))
	_fade(n, Rect2(0, HORIZON + 128, 1920, 80), Color(0.68, 0.54, 0.25), Color(0.55, 0.43, 0.2))
	var vp := Vector2(960, HORIZON - 120.0)       # the furrows run to one far point
	for i in 60:
		var xb := -600.0 + i * 52.0
		var a := Vector2(xb, HORIZON + 128.0)
		var b := vp + (a - vp) * ((HORIZON + 66.0 - vp.y) / (a.y - vp.y))
		if maxf(a.x, b.x) < 60.0 or minf(a.x, b.x) > 1860.0 or (minf(a.x, b.x) > 560.0 and maxf(a.x, b.x) < 1360.0):
			continue
		n.draw_line(b, a, Color(0.36, 0.22, 0.13), 3.0)
	# the fence along the stubble
	for side in [[62.0, 540.0], [1380.0, 1858.0]]:
		n.draw_rect(Rect2(side[0], HORIZON + 34, side[1] - side[0], 3), Color(0.4, 0.27, 0.17))
		n.draw_rect(Rect2(side[0], HORIZON + 43, side[1] - side[0], 3), Color(0.4, 0.27, 0.17))
		var x: float = side[0] + 22.0
		while x < side[1]:
			n.draw_rect(Rect2(x, HORIZON + 28, 5, 24), Color(0.33, 0.21, 0.13))
			x += 58.0
	# a row of standing corn behind the left yard's fence
	var cx := 70.0
	var ci := 0
	while cx < 532.0:
		var ch := 20.0 + float(_h(ci, 9, 31) % 9)
		n.draw_rect(Rect2(cx, HORIZON + 30.0 - ch, 3, ch), Color(0.5, 0.47, 0.17))
		n.draw_rect(Rect2(cx - 3.0, HORIZON + 34.0 - ch * 0.7, 9, 3), Color(0.66, 0.58, 0.22))
		n.draw_rect(Rect2(cx - 1.0, HORIZON + 28.0 - ch, 5, 5), Color(0.86, 0.68, 0.3))
		cx += 9.0 + float(_h(ci, 9, 32) % 4)
		ci += 1
	_scarecrow(n, Vector2(1452, HORIZON + 62.0))
	# corn shocks: bundles of stalks tied near the top
	for s in [[Vector2(118, 912), 1.0], [Vector2(214, 896), 0.8], [Vector2(452, 918), 1.05], [Vector2(514, 892), 0.75],
			[Vector2(1806, 900), 0.85]]:
		_shock(n, s[0], s[1])
	# the pumpkin patch: small and far, with vines
	for q in [[Vector2(1404, 910), 1.0], [Vector2(1436, 928), 1.2], [Vector2(1470, 904), 0.9], [Vector2(1500, 932), 1.1],
			[Vector2(1422, 890), 0.8], [Vector2(1790, 930), 1.1], [Vector2(1832, 916), 0.9], [Vector2(1486, 886), 0.75]]:
		var p: Vector2 = q[0]
		var s: float = q[1]
		n.draw_rect(Rect2(p.x - 15.0 * s, p.y + 4.0 * s, 30.0 * s, 2), Color(0.3, 0.38, 0.14))       # the vine and a leaf
		n.draw_rect(Rect2(p.x - 16.0 * s, p.y + 1.0 * s, 8.0 * s, 5.0 * s), Color(0.36, 0.46, 0.17))
		_blob(n, p, Vector2(8, 6) * s, Color(0.78, 0.36, 0.08))
		_blob(n, p + Vector2(-1, -1) * s, Vector2(4.5, 4.5) * s, Color(0.94, 0.52, 0.12))
		n.draw_rect(Rect2(p.x - 1.0, p.y - 8.0 * s, 2, 3), Color(0.3, 0.36, 0.12))

# A scarecrow far off in the stubble: a pole, a cross bar, a shirt, a hat, straw hands.
func _scarecrow(n: Node2D, foot: Vector2) -> void:
	var pole := Color(0.33, 0.21, 0.13)
	n.draw_rect(Rect2(foot.x - 2, foot.y - 46, 4, 46), pole)
	n.draw_rect(Rect2(foot.x - 20, foot.y - 36, 40, 3), pole)
	n.draw_rect(Rect2(foot.x - 9, foot.y - 38, 18, 20), Color(0.4, 0.36, 0.24))      # the shirt
	n.draw_rect(Rect2(foot.x - 16, foot.y - 38, 32, 6), Color(0.4, 0.36, 0.24))
	n.draw_rect(Rect2(foot.x - 24, foot.y - 38, 6, 5), Color(0.9, 0.74, 0.34))        # straw hands
	n.draw_rect(Rect2(foot.x + 18, foot.y - 38, 6, 5), Color(0.9, 0.74, 0.34))
	n.draw_rect(Rect2(foot.x - 6, foot.y - 50, 12, 12), Color(0.86, 0.7, 0.44))       # the sack head
	n.draw_rect(Rect2(foot.x - 11, foot.y - 53, 22, 4), Color(0.3, 0.2, 0.14))        # the hat
	n.draw_rect(Rect2(foot.x - 6, foot.y - 61, 12, 9), Color(0.3, 0.2, 0.14))

func _shock(n: Node2D, foot: Vector2, s: float) -> void:
	var stalk := Color(0.84, 0.66, 0.32)
	var stalk_d := Color(0.58, 0.42, 0.18)
	n.draw_colored_polygon(PackedVector2Array([foot + Vector2(-17, 0) * s, foot + Vector2(-4, -30) * s, foot + Vector2(-9, -46) * s,
		foot + Vector2(0, -38) * s, foot + Vector2(8, -47) * s, foot + Vector2(4, -30) * s, foot + Vector2(17, 0) * s]), stalk)
	for k in [-10.0, -3.0, 4.0, 11.0]:
		n.draw_line(foot + Vector2(k, 0) * s, foot + Vector2(k * 0.25, -30) * s, stalk_d, 1.5)
	n.draw_rect(Rect2(foot.x - 5.0 * s, foot.y - 32.0 * s, 10.0 * s, 3.0), Color(0.5, 0.26, 0.1))

# The two old trees: the hollow behind each side passage, the limbs the yard's planks
# rest on, and bunches of leaves under the canopy and at the limbs' ends.
func _trees(n: Node2D) -> void:
	for x in [0.0, 1860.0]:
		for cy in range(2, level.ROWS - 2):
			if not _solid(int(x / C), cy):
				n.draw_rect(Rect2(x, cy * C, 60, C), Color(0.1, 0.06, 0.04))
	var limb := Color(0.3, 0.19, 0.12)
	var limb_l := Color(0.5, 0.36, 0.24)
	for l in LIMBS:
		if not _limb_holds(l):
			continue
		for k in 2:
			n.draw_line(l[k], l[k + 1], limb, 11.0)
			n.draw_line(l[k] + Vector2(0, -4), l[k + 1] + Vector2(0, -4), limb_l, 2.0)
		n.draw_rect(Rect2(l[1].x - 5.0, l[1].y - 5.5, 10, 11), limb)
	# leaves hanging under the canopy, all along the top (thin over the barn's ridge)
	for i in 34:
		var x := 20.0 + i * 57.0 + float(_h(i, 11, 4) % 24)
		var deep := 1.0 if (x < 700.0 or x > 1220.0) else 0.45
		_bunch(n, Vector2(x, 62.0 + float(_h(i, 13, 5) % 14) * deep), (16.0 + float(_h(i, 17, 6) % 12)) * (0.7 + 0.3 * deep), i)
	# and at the ends of the limbs
	for i in LIMBS.size():
		var tip: Vector2 = LIMBS[i][2]
		if _limb_holds(LIMBS[i]):
			_bunch(n, tip + Vector2(22.0 if tip.x < 960.0 else -22.0, 12.0), 15.0, i + 60)

# A limb is drawn only while a plank still lies on its end (the map may change one day).
func _limb_holds(l: Array) -> bool:
	var tip: Vector2 = l[2]
	return level.cell_at(tip.x + (-15.0 if tip.x < 960.0 else 15.0), tip.y - 12.0) == level.LEDGE

func _bunch(n: Node2D, p: Vector2, r: float, pick: int) -> void:
	_blob(n, p, Vector2(r, r), BUNCH_COLS[pick % 4])
	_blob(n, p + Vector2(r * 0.7, r * 0.2), Vector2(r, r) * 0.72, BUNCH_COLS[(pick + 1) % 4])
	_blob(n, p + Vector2(-r * 0.6, r * 0.35), Vector2(r, r) * 0.62, BUNCH_COLS[(pick + 2) % 4])
	n.draw_rect(Rect2(p.x - r * 0.3, p.y - r * 0.7, r * 0.8, r * 0.7), BUNCH_COLS[(pick + 3) % 4])

# The silo's round body and its dome, behind the bright chute you climb (the blocks).
# Dark, like the barn's inside: scenery, not a wall.
func _silo(n: Node2D) -> void:
	var c0 := -1
	var c1 := -1
	var top: int = level.ROWS
	for cy in level.ROWS:
		for cx in range(BARN_C1 + 1, level.COLS - 2):
			if _kind(cx, cy) == K_SILO:
				c0 = cx if c0 < 0 else mini(c0, cx)
				c1 = maxi(c1, cx + 1)
				top = mini(top, cy)
	if c0 < 0:
		return
	var x0 := c0 * C - 62.0
	var x1 := c1 * C + 62.0
	var mid := (x0 + x1) * 0.5
	var y0 := top * C + 14.0
	var body := Color(0.25, 0.29, 0.37)
	var dark := Color(0.15, 0.18, 0.26)
	var lite := Color(0.34, 0.39, 0.46)
	# the body: lit from the left, round
	n.draw_polygon(PackedVector2Array([Vector2(x0, y0), Vector2(x0 + 70, y0), Vector2(x0 + 70, 1020), Vector2(x0, 1020)]),
		PackedColorArray([body, lite, lite, body]))
	n.draw_polygon(PackedVector2Array([Vector2(x0 + 70, y0), Vector2(x1, y0), Vector2(x1, 1020), Vector2(x0 + 70, 1020)]),
		PackedColorArray([lite, dark, dark, lite]))
	var y := y0 + 44.0
	while y < 1000.0:             # the hoops
		n.draw_rect(Rect2(x0, y, x1 - x0, 3), Color(0.1, 0.12, 0.18, 0.8))
		n.draw_rect(Rect2(x0, y + 3, x1 - x0, 1), Color(0.5, 0.56, 0.64, 0.4))
		y += 58.0
	n.draw_rect(Rect2(x0 - 6, 1000, x1 - x0 + 12, 20), Color(0.2, 0.2, 0.23))     # the footing
	# the dome
	var dome := PackedVector2Array()
	var shine := PackedVector2Array()
	for k in 17:
		var a := PI + PI * k / 16.0
		dome.append(Vector2(mid + cos(a) * (x1 - x0) * 0.5, y0 + sin(a) * 74.0))
		if k >= 3 and k <= 8:
			shine.append(Vector2(mid + cos(a) * (x1 - x0) * 0.42, y0 + sin(a) * 62.0))
	n.draw_colored_polygon(dome, Color(0.2, 0.23, 0.31))
	n.draw_polyline(shine, Color(0.46, 0.52, 0.6), 4.0)
	n.draw_rect(Rect2(x0 - 5, y0 - 3, x1 - x0 + 10, 7), Color(0.12, 0.14, 0.2))   # the rim
	n.draw_rect(Rect2(mid - 7, y0 - 88, 14, 16), Color(0.16, 0.19, 0.26))       # the vent on top
	n.draw_rect(Rect2(mid - 11, y0 - 92, 22, 5), Color(0.12, 0.14, 0.2))

# The barn's dark inside, far behind the play space: the roof's slopes over the stepped
# roof blocks, the back wall's boards with the sun in a few cracks, the open hay door
# up in the loft, the big back door below.
func _barn(n: Node2D) -> void:
	var x0 := BARN_C0 * C * 1.0
	var x1 := (BARN_C1 + 1) * C * 1.0
	# the roof line: through the top outer corner of each roof step, from the ridge out
	var line := PackedVector2Array()
	for cy in range(2, level.ROWS / 2):
		for cx in range(BARN_C0, level.COLS / 2):
			if _kind(cx, cy) == K_BARN and not _solid(cx, cy - 1):
				if line.is_empty() or cx * C < line[line.size() - 1].x:
					line.append(Vector2(cx * C, cy * C + 2))
				break
		if not line.is_empty() and line[line.size() - 1].x <= x0:
			break
	if line.size() < 2:
		return
	line.reverse()                                    # from the eaves up to the ridge
	var shape := PackedVector2Array([Vector2(x0 - 34, line[0].y + 62), line[0]])
	for i in range(1, line.size()):
		shape.append(line[i])
	for i in range(line.size() - 1, -1, -1):          # and down the other side
		shape.append(Vector2(x0 + x1 - line[i].x, line[i].y))
	shape.append(Vector2(x1 + 34, line[0].y + 62))
	n.draw_colored_polygon(shape, Color(0.27, 0.2, 0.2))          # the roof: dark shingles
	for k in range(1, 4):                                          # rows of them along each slope
		for i in line.size() - 1:
			var a: Vector2 = line[i] + Vector2(0, k * 15.0)
			var b: Vector2 = line[i + 1] + Vector2(0, k * 15.0)
			n.draw_line(a, b, Color(0.38, 0.3, 0.29), 2.0)
			n.draw_line(Vector2(x0 + x1 - a.x, a.y), Vector2(x0 + x1 - b.x, b.y), Color(0.38, 0.3, 0.29), 2.0)
	var eaves := line[0].y + 62.0
	n.draw_rect(Rect2(x0, eaves - 2, x1 - x0, 1022.0 - eaves), WALL_IN)
	var gable := PackedVector2Array([Vector2(x0, eaves)])
	for i in line.size():
		gable.append(line[i] + Vector2(18.0 if i == 0 else 0.0, 58))
	for i in range(line.size() - 1, -1, -1):
		gable.append(Vector2(x0 + x1 - line[i].x - (18.0 if i == 0 else 0.0), line[i].y + 58))
	gable.append(Vector2(x1, eaves))
	n.draw_colored_polygon(gable, WALL_IN)
	# the back wall's boards
	var top := line[line.size() - 1].y + 60.0
	var bx := x0 + 24.0
	var i2 := 0
	while bx < x1 - 6.0:
		var from := maxf(top, eaves - (minf(bx - x0, x1 - bx)) * 0.42)
		n.draw_rect(Rect2(bx, from, 2, 1020.0 - from), WALL_LINE)
		if _h(i2, 3, 21) % 5 == 0:         # the sun through a crack
			var cy0 := from + 30.0 + float(_h(i2, 5, 22) % 300)
			n.draw_rect(Rect2(bx, cy0, 2, 40 + _h(i2, 7, 23) % 90), Color(1.2, 0.74, 0.34, 0.5))
		bx += 24.0
		i2 += 1
	# the open hay door at the back of the loft: the evening sky through it
	var mid := (x0 + x1) * 0.5
	var door := Rect2(mid - 78, top + 26, 156, 168)
	n.draw_texture_rect(HALO, door.grow_individual(190, 150, 190, 170), false, Color(1.2, 0.66, 0.26, 0.42))
	n.draw_colored_polygon(PackedVector2Array([Vector2(door.position.x, door.end.y), Vector2(door.end.x, door.end.y),
		Vector2(door.end.x + 150, door.end.y + 170), Vector2(door.position.x - 150, door.end.y + 170)]), Color(1.2, 0.7, 0.3, 0.07))
	n.draw_rect(door.grow(7), Color(0.62, 0.56, 0.5))
	_fade(n, door, Color(1.05, 0.86, 0.62), Color(1.25, 0.66, 0.3))
	n.draw_colored_polygon(PackedVector2Array([Vector2(door.position.x, door.end.y), Vector2(door.position.x, door.end.y - 20),
		Vector2(door.position.x + 50, door.end.y - 34), Vector2(door.position.x + 104, door.end.y - 22), Vector2(door.end.x, door.end.y - 30),
		Vector2(door.end.x, door.end.y)]), Color(0.5, 0.3, 0.24))
	for side in [-1.0, 1.0]:              # its two leaves, swung open
		var leaf := Rect2(door.position.x - 7 - 64 if side < 0 else door.end.x + 7, door.position.y - 4, 64, door.size.y + 8)
		n.draw_rect(leaf, Color(0.36, 0.11, 0.09))
		_frame(n, leaf, Color(0.6, 0.53, 0.47), 5.0)
		n.draw_line(leaf.position + Vector2(4, 4), leaf.end - Vector2(4, 4), Color(0.6, 0.53, 0.47), 5.0)
		n.draw_line(Vector2(leaf.end.x - 4, leaf.position.y + 4), Vector2(leaf.position.x + 4, leaf.end.y - 4), Color(0.6, 0.53, 0.47), 5.0)
	# the big back door on the ground floor, shut: a frame and a cross of boards
	var big := Rect2(mid - 150, loft_y + 136, 300, 1020 - loft_y - 136)
	n.draw_rect(big, Color(0.26, 0.105, 0.085))
	_frame(n, big, DOOR_TRIM, 6.0)
	n.draw_rect(Rect2(mid - 3, big.position.y, 6, big.size.y), DOOR_TRIM)
	for hx in [big.position.x, mid]:
		n.draw_line(Vector2(hx + 6, big.position.y + 6), Vector2(hx + 144, big.end.y), DOOR_TRIM, 6.0)
		n.draw_line(Vector2(hx + 144, big.position.y + 6), Vector2(hx + 6, big.end.y), DOOR_TRIM, 6.0)
	# a beam where the loft's floor is, and two posts
	n.draw_rect(Rect2(x0, loft_y, x1 - x0, 16), Color(0.15, 0.07, 0.05))
	for px in [x0 + 196.0, x1 - 208.0]:
		n.draw_rect(Rect2(px, loft_y + 16, 12, 1004 - loft_y), Color(0.15, 0.07, 0.05))

# ------------------------------------------------------------------ behind the blocks, moving
func _draw() -> void:
	if not on or level == null:
		return
	if rich:
		_geese()
	_vane()

# The weather vane on the ridge: a rooster over an arrow, turning in the wind (drawn
# flat, squeezed sideways as it turns).
func _vane() -> void:
	var ridge: int = level.ROWS
	for cy in range(2, level.ROWS):
		if _solid(level.COLS / 2, cy):
			ridge = cy
			break
	if ridge > 12:
		return
	var foot := Vector2(960, ridge * C)
	var brass := Color(0.95, 0.72, 0.25)
	draw_rect(Rect2(foot.x - 2, foot.y - 36, 4, 36), IRON)       # (short: the page's seat bar is just above)
	draw_rect(Rect2(foot.x - 14, foot.y - 14, 28, 3), IRON)       # the cross: north, south, east, west
	draw_circle(foot + Vector2(0, -8), 4.0, brass)
	var turn := sin(t * 0.33) * 1.3 + sin(t * 0.9 + 1.0) * 0.25
	var sx := cos(turn)
	if absf(sx) < 0.12:
		sx = 0.12 if sx >= 0.0 else -0.12
	draw_set_transform(foot + Vector2(0, -28), 0.0, Vector2(sx * 0.85, 0.85))
	draw_rect(Rect2(-34, -2, 68, 4), IRON)
	draw_colored_polygon(PackedVector2Array([Vector2(46, 0), Vector2(30, -9), Vector2(30, 9)]), IRON)
	draw_colored_polygon(PackedVector2Array([Vector2(-34, 0), Vector2(-46, -10), Vector2(-28, -10), Vector2(-22, 0), Vector2(-28, 10),
		Vector2(-46, 10)]), IRON)
	# the rooster: body, tail, neck and head, comb, beak
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -3), Vector2(-14, -12), Vector2(-4, -17), Vector2(8, -14), Vector2(11, -3)]), IRON)
	draw_colored_polygon(PackedVector2Array([Vector2(-12, -10), Vector2(-25, -26), Vector2(-17, -27), Vector2(-21, -33), Vector2(-9, -25),
		Vector2(-5, -15)]), IRON)
	draw_colored_polygon(PackedVector2Array([Vector2(4, -13), Vector2(7, -27), Vector2(13, -28), Vector2(12, -12)]), IRON)
	draw_circle(Vector2(11, -28), 4.5, IRON)
	draw_colored_polygon(PackedVector2Array([Vector2(14, -29), Vector2(21, -27), Vector2(14, -25)]), brass)
	draw_colored_polygon(PackedVector2Array([Vector2(7, -31), Vector2(9, -37), Vector2(11, -33), Vector2(13, -37), Vector2(15, -31)]),
		Color(0.8, 0.16, 0.1))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# Geese in a V, far off, crossing the sky now and then (40 s across, every 70 s).
func _geese() -> void:
	var u := fmod(t + 20.0, 70.0) / 40.0
	if u >= 1.0:
		return
	var lead := Vector2(lerpf(2000.0, -120.0, u), 150.0 + sin(u * 5.0) * 14.0)
	var col := Color(0.16, 0.14, 0.2, 0.85)
	for i in 7:
		var k := (i + 1) / 2
		var side := 1.0 if i % 2 == 0 else -1.0
		var p := lead + Vector2(k * 22.0, k * 9.0 * side if i > 0 else 0.0)
		var flap := sin(t * 5.0 + i * 0.9) * 4.0
		draw_line(p + Vector2(-8, -flap), p, col, 2.0)
		draw_line(p, p + Vector2(8, -flap), col, 2.0)

# ------------------------------------------------------------------ the blocks and ledges, drawn once
func _paint_blocks(n: Node2D) -> void:
	var cols: int = level.COLS
	var rows: int = level.ROWS
	# each row's runs of one kind: the fill and its texture
	for cy in rows:
		var cx := 0
		while cx < cols:
			var k := _kind(cx, cy)
			var c1 := cx + 1
			while k != 0 and c1 < cols and _kind(c1, cy) == k:
				c1 += 1
			if k != 0:
				_fill(n, k, cx, c1, cy)
			cx = c1
	# what runs down a column, in one piece: the barn's boards, the trunks' bark
	for cx in cols:
		var cy := 0
		while cy < rows:
			var k := _kind(cx, cy)
			var r1 := cy + 1
			while k != 0 and r1 < rows and _kind(cx, r1) == k:
				r1 += 1
			if k == K_BARN or (k == K_TRUNK and (cx < 2 or cx >= cols - 2)):
				_grain(n, k, cx, cy, r1)
			cy = r1
	# the edges: a bright lip on every top you can stand on, a dark line under and
	# beside (the barn: white trim all round)
	for cy in rows:
		var cx := 0
		while cx < cols:
			var k := _kind(cx, cy)
			var c1 := cx + 1
			while k != 0 and c1 < cols and _kind(c1, cy) == k:
				c1 += 1
			if k != 0:
				_edges(n, k, cx, c1, cy)
			cx = c1
	_wheels(n)
	# the ledges: each run a pale plank
	for cy in rows:
		var run := -1
		for cx in cols + 1:
			var is_ledge: bool = cx < cols and level.cell(cx, cy) == level.LEDGE
			if is_ledge and run < 0:
				run = cx
			elif not is_ledge and run >= 0:
				_plank(n, run, cx, cy)
				run = -1

# One row's run of one kind, cells c0..c1: what it is made of.
func _fill(n: Node2D, k: int, c0: int, c1: int, cy: int) -> void:
	var r := Rect2(c0 * C, cy * C, (c1 - c0) * C, C)
	var x0 := c0 * C
	var y := cy * C
	if k == K_BARN:
		n.draw_rect(r, RED)               # (its boards: _grain)
	elif k == K_HAY:
		n.draw_rect(r, STRAW)
		n.draw_rect(Rect2(r.position.x, y + C - 2, r.size.x, 2), STRAW_D)        # the next bale down
		for cx in range(c0, c1):
			if (cx + cy) % 2 == 0:        # a bale is two cells long; each row starts a cell on
				n.draw_rect(Rect2(cx * C, y, 2, C - 2), STRAW_D)
			n.draw_rect(Rect2(cx * C + 14, y, 2, C - 2), TWINE)                    # the twine
			for s in 3:                   # straws
				var h := _h(cx, cy, 40 + s)
				n.draw_rect(Rect2(cx * C + 3 + h % 16, y + 5 + s * 8 + (h >> 5) % 3, 6 + (h >> 8) % 6, 1), STRAW_L if s != 1 else STRAW_D)
	elif k == K_SILO:
		var w := r.size.x                 # round: a bright band left of the middle, dark to the right
		n.draw_rect(r, STEEL)
		n.draw_rect(Rect2(x0 + w * 0.12, y, w * 0.34, C), Color(0.8, 0.86, 0.9))
		n.draw_rect(Rect2(x0 + w * 0.2, y, w * 0.14, C), STEEL_L)
		n.draw_rect(Rect2(x0 + w * 0.66, y, w * 0.18, C), Color(0.54, 0.62, 0.69))
		n.draw_rect(Rect2(x0 + w * 0.84, y, w * 0.16, C), STEEL_D)
		n.draw_rect(Rect2(x0, y + 14, w, 1), Color(STEEL_K, 0.16))
		if cy % 2 == 0:                   # a seam and its rivets every second row
			n.draw_rect(Rect2(x0, y, w, 2), Color(STEEL_K, 0.75))
			var x := x0 + 8.0
			while x < x0 + w - 4.0:
				n.draw_rect(Rect2(x, y + 5, 4, 4), STEEL_L)
				n.draw_rect(Rect2(x + 1, y + 8, 3, 1), STEEL_K)
				x += 13.0
	elif k == K_WAGON:
		n.draw_rect(r, WOOD)
		for b in 3:                       # planks along the wagon
			n.draw_rect(Rect2(r.position.x, y + b * 10 + 9, r.size.x, 1), WOOD_D)
		for cx in range(c0, c1):
			if _h(cx, cy, 51) % 3 == 0:
				n.draw_rect(Rect2(cx * C + 3 + _h(cx, cy, 52) % 12, y + 3 + (_h(cx, cy, 53) % 3) * 10, 10, 2), WOOD_L)
	elif k == K_GROUND:
		n.draw_rect(r, EARTH)
		for cx in range(c0, c1):          # stones and clods
			var h := _h(cx, cy, 61)
			n.draw_rect(Rect2(cx * C + h % 22, y + 9 + (h >> 5) % 14, 5 + (h >> 9) % 4, 3), EARTH_D)
			if h % 3 == 0:
				n.draw_rect(Rect2(cx * C + (h >> 3) % 24, y + 8 + (h >> 7) % 16, 4, 3), Color(0.56, 0.42, 0.28))
	elif k == K_TRUNK:
		n.draw_rect(r, BARK)              # (a trunk's bark: _grain)
		var b0 := maxi(c0, 2)             # a bough out of the trunk: the bark runs along it
		var b1 := mini(c1, level.COLS - 2)
		if b1 > b0:
			for s in 3:
				var gy := y + 6 + s * 9 + _h(cy, s, 73) % 3
				n.draw_rect(Rect2(b0 * C, gy, (b1 - b0) * C, 2), BARK_D)
				n.draw_rect(Rect2(b0 * C, gy + 2, (b1 - b0) * C, 1), Color(BARK_L, 0.5))
	elif k == K_CANOPY:
		n.draw_rect(r, Color(0.36, 0.13, 0.07))
		for cx in range(c0, c1):          # leaves
			for s in 2:
				var h := _h(cx, cy, 80 + s)
				var sz := 9.0 + (h >> 9) % 7
				n.draw_rect(Rect2(cx * C + h % 20, y + (h >> 5) % 18, sz, sz), LEAF_COLS[(h >> 12) % 4] * Color(0.72, 0.72, 0.72))

# One column's run of barn or trunk, rows r0..r1: boards and bark ridges in one piece.
func _grain(n: Node2D, k: int, cx: int, r0: int, r1: int) -> void:
	var x := cx * C
	var y := r0 * C
	var h := (r1 - r0) * C
	if k == K_BARN:
		for b in 3:                       # three boards to a cell; some a little lighter or darker
			var pick := _h(cx * 3 + b, r0, 31) % 7
			if pick == 0:
				n.draw_rect(Rect2(x + b * 10, y, 10, h), RED_L)
			elif pick == 1:
				n.draw_rect(Rect2(x + b * 10, y, 10, h), RED_M)
			n.draw_rect(Rect2(x + b * 10, y, 1, h), RED_D)
		return
	for s in 3:                           # the bark's ridges
		var gx := x + 4 + s * 9 + _h(cx, s, 73) % 4
		n.draw_rect(Rect2(gx, y, 3, h), BARK_D)
		n.draw_rect(Rect2(gx + 3, y, 1, h), Color(BARK_L, 0.5))
	for cy in range(r0, r1):              # a knot here and there
		var hk := _h(cx, cy, 74)
		if hk % 5 == 0:
			var kx := x + 4 + (hk >> 4) % 14
			var ky := cy * C + 5 + (hk >> 8) % 12
			n.draw_rect(Rect2(kx, ky, 10, 8), BARK_D)
			n.draw_rect(Rect2(kx + 2, ky + 2, 6, 4), BARK)
			n.draw_rect(Rect2(kx + 1, ky - 2, 8, 1), BARK_L)
	if cx == 0 or cx == level.COLS - 1:  # round: the far side in shade
		n.draw_rect(Rect2(x, y, C, h), Color(0.05, 0.02, 0.01, 0.3))

# The edges of one row's run, cells c0..c1, drawn inside its cells: nothing grows past
# where you stand.
func _edges(n: Node2D, k: int, c0: int, c1: int, cy: int) -> void:
	var y := cy * C
	var line: Color = LINES[k]
	var lf := _kind(c0 - 1, cy)
	var rt := _kind(c1, cy)
	var open_l: bool = lf == 0
	var open_r: bool = rt == 0
	if k == K_BARN:                    # white trim on every open side, a dark line inside it
		if open_l:
			n.draw_rect(Rect2(c0 * C, y, 6, C), TRIM)
			n.draw_rect(Rect2(c0 * C + 6, y, 1, C), TRIM_D)
		if open_r:
			n.draw_rect(Rect2(c1 * C - 6, y, 6, C), TRIM)
			n.draw_rect(Rect2(c1 * C - 7, y, 1, C), TRIM_D)
	elif k == K_TRUNK:
		if open_l:
			n.draw_rect(Rect2(c0 * C, y, 3, C), BARK_D)
			n.draw_rect(Rect2(c0 * C + 3, y, 2, C), BARK_L)
		if open_r:
			n.draw_rect(Rect2(c1 * C - 3, y, 3, C), BARK_D)
			n.draw_rect(Rect2(c1 * C - 5, y, 2, C), BARK_L)
	else:
		if open_l:
			n.draw_rect(Rect2(c0 * C, y, 3, C), line)
		if open_r:
			n.draw_rect(Rect2(c1 * C - 3, y, 3, C), line)
	# along the bottom and the top: one piece for each stretch with the same neighbour
	for pass_i in 2:
		var cx := c0
		while cx < c1:
			var other := _kind(cx, cy + 1 if pass_i == 0 else cy - 1)
			var e := cx + 1
			while e < c1 and _kind(e, cy + 1 if pass_i == 0 else cy - 1) == other:
				e += 1
			if pass_i == 0:
				_under(n, k, other, cx * C, (e - cx) * C, y, line)
			else:
				_lip(n, k, other, cx * C, (e - cx) * C, y, line)
			cx = e

func _under(n: Node2D, k: int, below: int, x: int, w: int, y: int, line: Color) -> void:
	if below == k or k == K_GROUND:
		return
	if below != 0:
		n.draw_rect(Rect2(x, y + C - 2, w, 2), line)
	elif k == K_BARN:
		n.draw_rect(Rect2(x, y + C - 6, w, 6), TRIM)
		n.draw_rect(Rect2(x, y + C - 7, w, 1), TRIM_D)
		n.draw_rect(Rect2(x, y + C - 2, w, 2), Color(0.62, 0.58, 0.54))
	else:
		n.draw_rect(Rect2(x, y + C - 3, w, 3), line)

func _lip(n: Node2D, k: int, above: int, x: int, w: int, y: int, line: Color) -> void:
	if above == k or k == K_CANOPY:
		return
	if above != 0:
		if k == K_BARN:
			n.draw_rect(Rect2(x, y, w, 2), line)
		return
	if k == K_BARN:
		n.draw_rect(Rect2(x, y, w, 7), TRIM)
		n.draw_rect(Rect2(x, y + 7, w, 2), TRIM_D)
	elif k == K_GROUND:
		n.draw_rect(Rect2(x, y, w, 6), GRASS)
		n.draw_rect(Rect2(x, y + 6, w, 2), GRASS_D)
		for cx in range(x / C, (x + w) / C):      # tufts and bits of straw
			var h := _h(cx, y, 90)
			n.draw_rect(Rect2(cx * C + 3 + h % 20, y + 6, 2, 3), GRASS_D)
			n.draw_rect(Rect2(cx * C + 3 + (h >> 5) % 22, y + 2, 3, 2), Color(1.0, 0.95, 0.55))
	else:
		n.draw_rect(Rect2(x, y, w, 4), LIPS[k])
		n.draw_rect(Rect2(x, y + 4, w, 2), line)

# The wagon's two wheels, over its bed: inside the block, so its shape stays true.
func _wheels(n: Node2D) -> void:
	var c0 := -1
	var c1 := -1
	var row: int = level.ROWS - 3
	for cx in level.COLS:
		if _kind(cx, row) == K_WAGON:
			c0 = cx if c0 < 0 else c0
			c1 = cx + 1
	if c0 < 0:
		return
	var floor_y := (row + 1) * C * 1.0
	n.draw_rect(Rect2(c0 * C + 3, floor_y - 8, (c1 - c0) * C - 6, 8), Color(0.12, 0.07, 0.04, 0.8))   # the shade under the bed
	for wx in [c0 * C + 40.0, c1 * C - 40.0]:
		var hub := Vector2(wx, floor_y - 25.0)
		n.draw_circle(hub, 25.0, Color(0.13, 0.07, 0.04))
		n.draw_circle(hub, 20.0, Color(0.34, 0.2, 0.1))
		for s in 8:
			n.draw_line(hub, hub + Vector2.from_angle(s * TAU / 8.0 + 0.2) * 22.0, Color(0.78, 0.58, 0.32), 3.0)
		n.draw_arc(hub, 22.0, 0.0, TAU, 28, Color(0.82, 0.62, 0.36), 4.0)
		n.draw_circle(hub, 6.0, Color(0.9, 0.72, 0.42))
		n.draw_circle(hub, 2.5, WOOD_D)

# One run of ledge, cells c0..c1 on row cy: a pale plank with a bright top and a dark
# line under it. On the silo it is a steel rung; where it meets a wall it gets a strut;
# the loft's floor shows its joists.
func _plank(n: Node2D, c0: int, c1: int, cy: int) -> void:
	var x0 := c0 * C * 1.0
	var x1 := c1 * C * 1.0
	var y := cy * C * 1.0
	var wall_l := _kind(c0 - 1, cy)
	var wall_r := _kind(c1, cy)
	var steel: bool = wall_l == K_SILO or wall_r == K_SILO
	var body := PLANK if not steel else Color(0.6, 0.68, 0.76)
	var top := PLANK_L if not steel else Color(1.0, 1.0, 1.0)
	var under := PLANK_D if not steel else STEEL_K
	# what holds it up, first (under the plank)
	if wall_l != 0 and wall_l != K_GROUND:
		_strut(n, Vector2(x0, y), 1.0, under, body)
	if wall_r != 0 and wall_r != K_GROUND:
		_strut(n, Vector2(x1, y), -1.0, under, body)
	if (wall_l == K_BARN or wall_r == K_BARN) and c0 > BARN_C0 and c1 <= BARN_C1 and c1 - c0 > 8:    # the loft's floor: joist ends
		var jx := x0 + 20.0
		while jx < x1 - 12.0:
			n.draw_rect(Rect2(jx, y + 11, 9, 7), under)
			n.draw_rect(Rect2(jx + 1, y + 11, 7, 5), Color(0.5, 0.33, 0.17))
			jx += 60.0
	n.draw_rect(Rect2(x0, y, x1 - x0, 11), body)
	n.draw_rect(Rect2(x0, y, x1 - x0, 4), top)
	n.draw_rect(Rect2(x0, y + 9, x1 - x0, 3), under)
	n.draw_rect(Rect2(x0, y, 2, 11), under)
	n.draw_rect(Rect2(x1 - 2, y, 2, 11), under)
	var jx2 := x0 + 60.0
	while jx2 < x1 - 20.0:             # where two boards meet
		n.draw_rect(Rect2(jx2, y + 4, 1, 5), under)
		jx2 += 60.0

func _strut(n: Node2D, at: Vector2, dir: float, dark: Color, lite: Color) -> void:
	n.draw_line(at + Vector2(dir * 1.0, 27), at + Vector2(dir * 17.0, 11), dark, 5.0)
	n.draw_line(at + Vector2(dir * 2.0, 25), at + Vector2(dir * 15.0, 12), lite, 1.5)

# ------------------------------------------------------------------ in front, under the fighters
func _paint_front(n: Node2D) -> void:
	for i in lamps.size():             # the lanterns' glows first (one picture), then their boxes
		var k := _flicker(i)
		var p: Vector2 = lamps[i][0]
		n.draw_texture_rect(HALO, Rect2(p - Vector2(84, 80), Vector2(168, 160)), false, Color(1.0, 0.66, 0.24, 0.34 * k))
	for i in lamps.size():
		_lantern(n, lamps[i], i)
	# leaves falling slowly, all round: each one rocks and turns over as it drifts
	var count := LEAVES if rich else LEAVES_LOW
	for i in count:
		var fall := 34.0 + float(_h(i, 1, 101) % 30)
		var drift := 6.0 + float(_h(i, 2, 102) % 22)
		var ph := float(_h(i, 3, 103) % 628) * 0.01
		var rock := 0.9 + float(_h(i, 4, 104) % 100) * 0.009
		var y := fposmod(float(_h(i, 5, 105) % 1140) + t * fall, 1140.0) - 30.0
		var x := fposmod(float(_h(i, 6, 106) % 2000) + t * drift + sin(t * rock + ph) * (26.0 + float(i % 5) * 7.0), 2000.0) - 40.0
		if level.cell_at(x, y) == level.SOLID:
			continue                   # it passes behind the blocks
		var s := 1.0 + float(i % 4) * 0.16
		var col: Color = LEAF_COLS[i % LEAF_COLS.size()]
		n.draw_set_transform(Vector2(x, y), sin(t * rock + ph) * 0.9 + ph, Vector2(s, s * (0.35 + 0.65 * absf(cos(t * rock * 0.7 + ph)))))
		n.draw_rect(Rect2(-7, -4, 12, 8), col)
		n.draw_rect(Rect2(-4, -5.5, 6, 11), col)
		n.draw_rect(Rect2(5, -2, 4, 4), col)                                   # its point
		n.draw_rect(Rect2(-11, -0.5, 16, 1), Color(0.36, 0.16, 0.06, 0.8))     # the stem and the rib
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if rich:                           # straw dust in the barn, slow in the light
		for i in DUST:
			var bx := BARN_C0 * C + 70.0 + float(_h(i, 7, 107) % 700)
			var by := 330.0 + float(_h(i, 8, 108) % 660)
			var p := Vector2(bx + sin(t * 0.3 + i * 1.3) * 26.0, by + cos(t * 0.23 + i * 2.1) * 18.0 - fmod(t * 4.0 + i * 31.0, 60.0))
			var a := 0.3 + 0.25 * sin(t * 0.9 + i * 1.7)
			n.draw_rect(Rect2(p, Vector2(3, 2)), Color(1.0, 0.86, 0.5, a))

func _flicker(i: int) -> float:
	return 0.85 + 0.15 * sin(t * 12.0 + i * 1.9) * sin(t * 7.1 + i)

# A lantern where a torch was: an iron frame, warm glass, a flame that flickers. It
# hangs on a chain from what is above it, or from an arm on the wall beside it.
func _lantern(n: Node2D, lamp: Array, i: int) -> void:
	var p: Vector2 = lamp[0]
	var hang: int = lamp[1]
	var k := _flicker(i)
	if hang != 0:                      # the arm: out from the wall, a brace under it, a short chain down
		var wx := p.x + hang * 15.0
		n.draw_rect(Rect2(minf(wx, p.x), p.y - 30, absf(wx - p.x) + 2.0, 4), IRON)
		n.draw_line(Vector2(wx, p.y - 14), Vector2(p.x + hang * 3.0, p.y - 28), IRON, 3.0)
		n.draw_rect(Rect2(p.x - 1, p.y - 28, 2, 6), IRON)
	else:
		var y := float(lamp[2])
		while y < p.y - 24.0:          # the chain
			n.draw_rect(Rect2(p.x - 1, y, 2, 4), IRON)
			y += 6.0
	n.draw_rect(Rect2(p.x - 6, p.y - 23, 12, 2), IRON)                          # the handle
	n.draw_rect(Rect2(p.x - 6, p.y - 23, 2, 5), IRON)
	n.draw_rect(Rect2(p.x + 4, p.y - 23, 2, 5), IRON)
	n.draw_rect(Rect2(p.x - 7, p.y - 19, 14, 4), IRON)                          # the cap
	n.draw_rect(Rect2(p.x - 11, p.y - 15, 22, 3), IRON)
	n.draw_rect(Rect2(p.x - 9, p.y - 12, 18, 23), Color(1.0, 0.8 * k, 0.36 * k))  # the glass
	var sway := sin(t * 9.0 + i * 2.3) * 1.2
	n.draw_rect(Rect2(p.x - 4, p.y + 1, 8, 8), Color(1.0, 0.95, 0.7))           # the flame
	n.draw_rect(Rect2(p.x - 3 + sway * 0.5, p.y - 4, 6, 6), Color(1.0, 0.98, 0.8))
	n.draw_rect(Rect2(p.x - 1.5 + sway, p.y - 4.0 - 5.0 * k, 3, 6), Color(1.0, 1.0, 0.9))
	n.draw_rect(Rect2(p.x - 10, p.y - 12, 2, 23), IRON)                         # the frame's bars
	n.draw_rect(Rect2(p.x + 8, p.y - 12, 2, 23), IRON)
	n.draw_rect(Rect2(p.x - 12, p.y + 10, 24, 4), IRON)                         # the base

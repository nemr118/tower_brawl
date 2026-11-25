# THE ROOFTOPS' look (theme "rooftops", sim/level.gd), for Christmas: Christmas Eve at
# night, high over a snowy town. world.gd makes one (behind the tiles), calls setup once,
# and on each arena and each look leave() before the other arenas' looks and set_theme()
# after them (as for THE BIG TABLE). Drawn by hand, all of it, on every look. What goes
# where:
#   still (behind this node, the lit world, drawn once): the night sky and its stars, the
#     big moon, far hills and a far town, the houses' dark fronts with warm windows under
#     every roof (only scenery: you walk in front of them), the belfry's inside and its
#     bell, the poles that hold the planks up, the wires of the string lights, the dark
#     alleys under the floor's gaps;
#   this node (the lit world, behind the blocks, 30 times a second): the sleigh that
#     crosses the moon now and then, the string lights' bulbs, the chimneys' smoke, the
#     star on the spire;
#   blocks (the lit world, where the stone tiles were, drawn once): every block and
#     ledge. A roof is coloured tiles, a chimney and the big stack at the screen's edge
#     are brick, the clock tower is stone with a lit clock, the floor is the lowest roofs,
#     the ceiling is snow clouds. Every top you can stand on wears a white cap of snow,
#     and every ledge is a plank, a stone balcony or a striped awning with snow on it:
#     white on top means "stand here". Nothing is drawn past a block's own cells: the
#     shapes stay true;
#   front (the threats layer, under the fighters, 30 times a second): the lanterns where
#     the torches were, the falling snow.
# What stands out: the things you can stand on are bright (snow, coloured tiles, warm
# brick, pale stone) and the lanterns light them; the scenery is dark blue and takes no
# light. The night is a moonlit blue (world.dark_base).
# Cheap on phones: almost everything is plain boxes (the renderer draws those in a few
# batches), the still parts are drawn once, and LOW (no particles) gets fewer snowflakes,
# less smoke and bulbs with no glow. No new picture, no new font size.
# Nothing here reads the layout's number: the theme picks the look, and the shapes come
# from the level's own grid. Only the string lights' ends and the moon's place are fixed
# (SPANS, MOON); a wire is drawn only while both its ends still sit in a block.
extends Node2D

const HALO := preload("res://assets/fx_halo.png")
const C := 30                     # the grid (sim/level.gd CELL)
const REDRAW_HZ := 30.0           # the moving parts are drawn again 30 times a second (cheaper on phones)
const NIGHT := Color(0.72, 0.78, 1.0)      # the moonlit night (world.dark_base): it tints the lit world
const LAMP := Color(0.8, 0.5, 0.22)        # a lantern's light on the snow
const BLOOM_HIGH := 0.5                    # HIGH's bloom here (1: as on the castle arenas)
const MOON := Vector2(1440, 262)
const MOON_R := 102.0
# what a block is made of
const K_CLOUD := 1
const K_FLOOR := 2
const K_ROOF := 3
const K_CHIM := 4
const K_STACK := 5
const K_TOWER := 6
const K_DORMER := 7
# the cols the clock tower stands in
const TOWER_C0 := 29
const TOWER_C1 := 34
# the colours of the blocks (the night's tint cools them a little)
const SNOW := Color(1.0, 1.0, 1.0)
const SNOW_SH := Color(0.66, 0.76, 0.98)
const SNOW_D := Color(0.5, 0.6, 0.9)
const TRIM := Color(0.97, 0.93, 0.84)
const FASCIA := Color(0.17, 0.1, 0.13)
const BRICK := Color(0.76, 0.4, 0.28)
const BRICK_L := Color(0.92, 0.56, 0.4)
const BRICK_D := Color(0.45, 0.2, 0.16)
const CAP := Color(0.82, 0.83, 0.9)
const STONE := Color(0.6, 0.64, 0.76)
const STONE_L := Color(0.8, 0.84, 0.94)
const STONE_D := Color(0.38, 0.42, 0.56)
const STONE_K := Color(0.16, 0.18, 0.28)
const SLATE := Color(0.33, 0.39, 0.58)
const SLATE_D := Color(0.2, 0.25, 0.42)
const CLOUD := Color(0.47, 0.51, 0.66)
const CLOUD_L := Color(0.58, 0.62, 0.76)
const CLOUD_D := Color(0.33, 0.37, 0.54)
const PLASTER := Color(0.9, 0.84, 0.7)
const TIMBER := Color(0.36, 0.2, 0.12)
const WOOD := Color(0.76, 0.55, 0.34)
const WOOD_D := Color(0.24, 0.13, 0.07)
const GLASS := Color(1.6, 1.16, 0.5)      # a lit window on a block (over 1: the night's tint brings it back)
const GLASS_L := Color(1.7, 1.42, 0.86)
const IRON := Color(0.09, 0.08, 0.1)
const AWN_RED := Color(0.9, 0.2, 0.2)
const AWN_WHITE := Color(0.98, 0.94, 0.86)
# a roof's tiles: [the tile, its dark line, a light tile]
# (the roofs take them in turn from the left of the screen to the right: green, blue,
# teal, red, plum; so two roofs side by side never match)
const ROOFS := [
	[Color(0.2, 0.52, 0.3), Color(0.1, 0.31, 0.17), Color(0.34, 0.68, 0.4)],
	[Color(0.24, 0.4, 0.78), Color(0.13, 0.22, 0.5), Color(0.4, 0.57, 0.94)],
	[Color(0.12, 0.52, 0.54), Color(0.06, 0.31, 0.35), Color(0.24, 0.68, 0.68)],
	[Color(0.76, 0.2, 0.17), Color(0.47, 0.1, 0.1), Color(0.92, 0.33, 0.26)],
	[Color(0.52, 0.3, 0.64), Color(0.31, 0.16, 0.42), Color(0.68, 0.45, 0.8)]]
const DORMER_ROOF := [Color(0.76, 0.2, 0.17), Color(0.47, 0.1, 0.1)]   # a dormer's own little roof
# the houses' fronts (scenery, as they look on the screen): dark, each its own hue
const FRONTS := [Color(0.2, 0.125, 0.15), Color(0.125, 0.155, 0.255), Color(0.115, 0.195, 0.2), Color(0.2, 0.155, 0.12),
	Color(0.17, 0.135, 0.24)]
const BULBS := [Color(1.0, 0.24, 0.2), Color(0.3, 1.0, 0.42), Color(1.0, 0.82, 0.24), Color(0.36, 0.62, 1.0), Color(1.0, 0.45, 0.82)]
# the string lights: [from, to, how far the wire sags] (px). Each end sits just inside a
# block (the big stack's top, a chimney, the tower's spire); the wire hangs behind them.
const SPANS := [
	[Vector2(14, 318), Vector2(440, 548), 46.0],
	[Vector2(462, 548), Vector2(934, 286), 40.0],
	[Vector2(986, 286), Vector2(1512, 460), 60.0],
	[Vector2(1548, 460), Vector2(1906, 318), 14.0]]
const FLAKES_LOW := 40
const FLAKES := 110
const SLEIGH_EVERY := 34.0        # the sleigh sets off this often (s),
const SLEIGH_TIME := 11.0         # takes this long to cross the sky,
const SLEIGH_FIRST := 3.0         # and the first time this soon after the arena shows

var world
var level
var on := false
var rich := false                 # NORMAL and HIGH (the look has particles): more snow, more smoke, bulbs that glow
var t := 0.0
var redraw_wait := 0.0
var still: _Layer
var blocks: _Layer
var front: _Layer
var kinds := PackedByteArray()    # each cell: 0, or what its block is made of
var roof_of := PackedByteArray()  # each roof cell: which of ROOFS its tiles are (the roofs in turn, left to right)
var lamps: Array = []             # [flame's place, hangs from: 0 a chain up, -1 a wall on the left, 1 on the right, top of the chain]
var pots: Array = []              # Vector2: the middle of each chimney's top (the smoke rises from it)
var fronts: Array = []            # [Rect2, which of FRONTS]: the houses' fronts under the roofs
var belfry := Rect2()             # the open part of the tower (no size: none)
var spire := Vector2(-1, -1)      # the middle of the tower's very top
var wires: Array = []             # the SPANS whose ends still sit in a block

class _Layer extends Node2D:
	var rv
	var which := 0
	func _draw() -> void:
		if rv != null and rv.on:
			rv._paint(self, which)

func setup(w) -> void:
	world = w
	visible = false
	light_mask = 0                 # the sky and the scenery take no light: only the blocks are lit by the lanterns
	still = _new_layer(0)
	still.show_behind_parent = true
	still.light_mask = 0
	still.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # the moon's glow: smooth, not squares
	add_child(still)
	blocks = _new_layer(1)
	world.add_child(blocks)
	world.move_child(blocks, world.tiles_lit.get_index() + 1)   # where the tiles are
	front = _new_layer(2)
	front.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	world.threats.add_child(front)
	world.threats.move_child(front, 0)                          # under the fighters

func _new_layer(which: int) -> _Layer:
	var n := _Layer.new()
	n.rv = self
	n.which = which
	n.visible = false
	return n

# world.gd calls leave() first, before the other arenas' looks take their turn: if the
# rooftops were on, everything they hid goes back to what the look has on every arena
# (the castle's backdrops and tiles, the embers, the fog, the light shafts, the spirit
# lights, the torches' halos, HIGH's bloom). So the next arena's own look starts from the
# usual state.
func leave() -> void:
	if not on:
		return
	on = false
	visible = false
	for n in [still, blocks, front]:
		n.visible = false
	world.bg_far.visible = true
	world.bg_mid.visible = true
	var lit: bool = world.parts.get("lit", false)
	world.tiles_plain.visible = not lit
	world.tiles_lit.visible = lit
	var fx_on: bool = world.parts.get("particles", false)
	world.ambient[0].visible = fx_on
	world.ambient[0].emitting = fx_on
	for sh in world.shafts:
		sh.visible = world.parts.get("shafts", false)
	world._set_fog_layers(world.fog_on)
	world._set_wisps(int(world.parts.get("wisps", 0)), int(world.parts.get("wisp_lights", 0)))
	for tr in world.torches:
		tr[3].visible = fx_on
	world.post.material.set_shader_parameter("bloom", 1.0 if world.parts.get("bloom", false) else 0.0)

# Another arena or another look; world.gd calls this last, after the other looks. On the
# rooftops the backdrop and the blocks are ours (the castle's backdrops, tiles and stone
# torches hide) and the night turns moonlit blue.
func set_theme(lv) -> void:
	leave()                        # (it already ran; this keeps a lone call safe)
	level = lv
	if lv.theme != "rooftops":
		return
	on = true
	visible = true
	for n in [still, blocks, front]:
		n.visible = true
	rich = world.parts.get("particles", false)
	world.dark_base = NIGHT
	world.dark.color = NIGHT
	world.bg_far.visible = false
	world.bg_mid.visible = false
	world.tiles_plain.visible = false
	world.tiles_lit.visible = false
	for tr in world.torches:
		tr[0].visible = false      # the stone torch: a lantern takes its place (its light stays)
		tr[2].visible = false
		tr[2].emitting = false
		tr[3].visible = false
		tr[1].color = LAMP
	for f in world.fogs:           # a clear cold night: no fog, no light shafts, no spirit lights, no embers
		f.visible = false
	for sh in world.shafts:
		sh.visible = false
	world._set_wisps(0, 0)
	world.ambient[0].visible = false
	world.ambient[0].emitting = false
	# HIGH's bloom makes the white snow and the bright tiles glow: half the bloom there,
	# and the blocks a step lower (the moon, the clock and the windows still glow)
	var glare: bool = world.parts.get("bloom", false)
	modulate = Color(0.92, 0.92, 0.92) if glare else Color.WHITE
	blocks.modulate = Color(0.8, 0.8, 0.82) if glare else Color.WHITE
	if glare:
		world.post.material.set_shader_parameter("bloom", BLOOM_HIGH)
	_scan()
	redraw_wait = 0.0
	still.queue_redraw()
	blocks.queue_redraw()

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

# A colour as it should look on the screen, for the lit world: the night's tint is
# taken out here, so it comes out as written.
static func _s(r: float, g: float, b: float, a: float = 1.0) -> Color:
	return Color(r / NIGHT.r, g / NIGHT.g, b / NIGHT.b, a)

static func _sc(c: Color, a: float = 1.0) -> Color:
	return Color(c.r / NIGHT.r, c.g / NIGHT.g, c.b / NIGHT.b, a)

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

func _ledge(cx: int, cy: int) -> bool:
	return level.cell(cx, cy) == level.LEDGE

func _kind(cx: int, cy: int) -> int:
	return kinds[posmod(cy, level.ROWS) * level.COLS + posmod(cx, level.COLS)]

# The run of blocks along row cy that holds column cx, through the wrap:
# Vector2i(its first column, how many). The first column may be below 0.
func _run(cx: int, cy: int) -> Vector2i:
	var a := cx
	var n := 1
	while n < level.COLS and _solid(a - 1, cy):
		a -= 1
		n += 1
	var b := cx
	while n < level.COLS and _solid(b + 1, cy):
		b += 1
		n += 1
	return Vector2i(a, n)

# What each block is made of, from where it stands and how wide it is. The top two rows
# are clouds, the bottom two the lowest roofs, the tower's cols the clock tower. At the
# screen's edge stands the big chimney stack (a roof may cross it: then both its sides
# go on past the edge cols). Anything else 4 or more cells wide is a roof; a narrow
# block is a dormer when it stands on the floor, else a chimney. Then the places the
# moving parts need: the lanterns, the chimneys' tops, the houses' fronts, the belfry,
# the spire, the wires.
func _scan() -> void:
	var cols: int = level.COLS
	var rows: int = level.ROWS
	kinds.resize(cols * rows)
	kinds.fill(0)
	roof_of.resize(cols * rows)
	roof_of.fill(0)
	for cy in rows:
		for cx in cols:
			if not _solid(cx, cy):
				continue
			var k := K_ROOF
			var run := _run(cx, cy)
			if cy < 2:
				k = K_CLOUD
			elif cy >= rows - 2:
				k = K_FLOOR
			elif cx >= TOWER_C0 and cx <= TOWER_C1:
				k = K_TOWER
			elif cx < 2 or cx >= cols - 2:
				if _solid(2, cy) and _solid(cols - 3, cy):
					k = K_ROOF
				else:
					k = K_STACK if run.y > 3 else K_CHIM
			elif run.y < 4:
				k = K_CHIM
				for down in range(cy + 1, rows - 1):
					if not _solid(cx, down):
						break
					if down == rows - 2:
						k = K_DORMER
			kinds[cy * cols + cx] = k
	# a roof's tiles: one colour for the whole roof. Each roof is known by where its top
	# row starts (through the wrap); the roofs take the colours in turn, left to right.
	var starts := {}                  # the roof's key (its first col, its top row) -> true
	var key_of := {}                  # a roof cell -> its roof's key
	for cy in rows:
		for cx in cols:
			if kinds[cy * cols + cx] != K_ROOF:
				continue
			var top := cy
			while top > 2 and _kind(cx, top - 1) == K_ROOF:
				top -= 1
			var key := Vector2i(posmod(_run(cx, top).x, cols), top)
			starts[key] = true
			key_of[cy * cols + cx] = key
	var order: Array = starts.keys()
	order.sort()
	for cell in key_of:
		roof_of[cell] = order.find(key_of[cell]) % ROOFS.size()
	# the chimneys' tops
	pots.clear()
	for cy in range(2, rows - 2):
		for cx in cols:
			if _kind(cx, cy) == K_CHIM and not _solid(cx, cy - 1) and _kind(cx - 1, cy) != K_CHIM:
				var w := 1
				while w < 4 and _kind(cx + w, cy) == K_CHIM:
					w += 1
				pots.append(Vector2((cx + w * 0.5) * C, cy * C))
	# the houses' fronts: under each stretch of roof with air below it, down to the floor
	fronts.clear()
	for cy in range(2, rows - 3):
		var run0 := -1
		for cx in range(2, cols - 1):
			var under: bool = cx < cols - 2 and _kind(cx, cy) == K_ROOF and not _solid(cx, cy + 1)
			if under and run0 < 0:
				run0 = cx
			elif not under and run0 >= 0:
				var x0 := run0 * C + (0.0 if _solid(run0 - 1, cy + 1) else 9.0)
				var x1 := cx * C - (0.0 if _solid(cx, cy + 1) else 9.0)
				fronts.append([Rect2(x0, (cy + 1) * C, x1 - x0, (rows - 2 - cy - 1) * C), (run0 * 7 + cy) % FRONTS.size()])
				run0 = -1
	# the belfry: the open rows of the tower, with tower above and below
	belfry = Rect2()
	spire = Vector2(-1, -1)
	var seen_top := false
	var open0 := -1
	for cy in range(2, rows - 2):
		var solid_here := _solid(TOWER_C0, cy)
		if not seen_top:
			var any := false
			for cx in range(TOWER_C0, TOWER_C1 + 1):
				if _solid(cx, cy):
					if not any:
						var w := 1
						while _solid(cx + w, cy) and cx + w <= TOWER_C1:
							w += 1
						spire = Vector2((cx + w * 0.5) * C, cy * C)
					any = true
			seen_top = any
		elif solid_here and open0 >= 0:
			belfry = Rect2(TOWER_C0 * C, open0 * C, (TOWER_C1 - TOWER_C0 + 1) * C, (cy - open0) * C)
			break
		elif not solid_here and open0 < 0 and _solid(TOWER_C0, cy - 1):
			open0 = cy
	# the lanterns: on a wall beside them, or on a chain from what is above
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
					top = (cy - up) * C + (C if c == level.SOLID else 18)
					break
		lamps.append([flame, hang, top])
	wires.clear()
	for sp in SPANS:
		if level.cell_at(sp[0].x, sp[0].y) == level.SOLID and level.cell_at(sp[1].x, sp[1].y) == level.SOLID:
			wires.append(sp)

# ------------------------------------------------------------------ behind the blocks, drawn once
func _paint_still(n: Node2D) -> void:
	_sky(n)
	_far(n)
	_fronts(n)
	_belfry(n)
	_poles(n)
	for sp in wires:               # the string lights' wires (the bulbs: _bulbs)
		var pts := PackedVector2Array()
		for k in 17:
			pts.append(_wire_at(sp, k / 16.0))
		n.draw_polyline(pts, _s(0.18, 0.21, 0.32), 2.0)
	# the alleys under the floor's gaps: dark, with a street lamp's glow far below
	var run := -1
	for cx in level.COLS + 1:
		var gap: bool = cx < level.COLS and not _solid(cx, level.ROWS - 1)
		if gap and run < 0:
			run = cx
		elif not gap and run >= 0:
			var r := Rect2(run * C, 1020, (cx - run) * C, 60)
			_fade(n, r, _s(0.07, 0.08, 0.17), _s(0.01, 0.01, 0.04))
			n.draw_texture_rect(HALO, Rect2(r.position.x + r.size.x * 0.5 - 50, 1040, 100, 80), false, _s(1.0, 0.7, 0.3, 0.3))
			run = -1

static func _wire_at(sp: Array, u: float) -> Vector2:
	var a: Vector2 = sp[0]
	var b: Vector2 = sp[1]
	return a.lerp(b, u) + Vector2(0, float(sp[2]) * 4.0 * u * (1.0 - u))

func _sky(n: Node2D) -> void:
	var stops := [[0.0, _s(0.015, 0.025, 0.09)], [330.0, _s(0.03, 0.055, 0.165)], [700.0, _s(0.065, 0.11, 0.26)],
		[1080.0, _s(0.12, 0.16, 0.32)]]
	for i in stops.size() - 1:
		_fade(n, Rect2(0, stops[i][0], 1920, stops[i + 1][0] - stops[i][0]), stops[i][1], stops[i + 1][1])
	# the stars: most are small, a few are little crosses; none on the moon
	for i in 140:
		var x := float(_h(i, 1, 201) % 1920)
		var u := float(_h(i, 2, 202) % 1000) / 1000.0
		var y := 62.0 + u * u * 660.0
		if Vector2(x, y).distance_to(MOON) < MOON_R + 30.0:
			continue
		var k := 0.4 + float(_h(i, 3, 203) % 60) / 100.0
		var col := _s(0.82 * k, 0.88 * k, 1.0 * k)
		n.draw_rect(Rect2(x, y, 3 if i % 5 == 0 else 2, 3 if i % 5 == 0 else 2), col)
		if i % 17 == 0:
			n.draw_rect(Rect2(x - 3, y, 9, 2), col)
			n.draw_rect(Rect2(x, y - 3, 2, 9), col)
	# the moon: a wide glow, a close glow, the disc and a few craters
	n.draw_texture_rect(HALO, Rect2(MOON - Vector2(470, 470), Vector2(940, 940)), false, _s(0.42, 0.56, 1.0, 0.3))
	n.draw_texture_rect(HALO, Rect2(MOON - Vector2(210, 210), Vector2(420, 420)), false, _s(0.8, 0.88, 1.0, 0.5))
	n.draw_circle(MOON, MOON_R + 5.0, _s(0.8, 0.86, 1.0, 0.45))
	n.draw_circle(MOON, MOON_R, _s(1.0, 0.97, 0.84))
	for cr in [[Vector2(-34, -30), 20.0], [Vector2(30, 14), 26.0], [Vector2(-18, 44), 13.0], [Vector2(46, -46), 10.0],
			[Vector2(-58, 14), 11.0], [Vector2(4, -66), 8.0], [Vector2(60, 52), 7.0]]:
		n.draw_circle(MOON + cr[0], cr[1], _s(0.9, 0.87, 0.76))
		n.draw_circle(MOON + cr[0] + Vector2(2, 2), cr[1] - 3.0, _s(0.94, 0.91, 0.79))

# The far ridge's height at x, and the near hill's.
static func _ridge(x: float) -> float:
	return 700.0 - 74.0 * sin(x * 0.0043 + 0.6) - 34.0 * sin(x * 0.011 + 2.1) - 12.0 * sin(x * 0.031)

static func _hill(x: float) -> float:
	return 874.0 - 26.0 * sin(x * 0.006 + 1.3) - 10.0 * sin(x * 0.019 + 0.4)

# Far behind: snowy mountains under the moon, a nearer hill with pines, and the town on
# it: small dark houses, each with a warm window or two, and a church.
func _far(n: Node2D) -> void:
	var far := PackedVector2Array([Vector2(0, 1080)])
	var far_top := PackedVector2Array()
	var near := PackedVector2Array([Vector2(0, 1080)])
	var near_top := PackedVector2Array()
	for x in range(0, 1921, 40):
		far.append(Vector2(x, _ridge(x)))
		far_top.append(Vector2(x, _ridge(x)))
		near.append(Vector2(x, _hill(x)))
		near_top.append(Vector2(x, _hill(x)))
	far.append(Vector2(1920, 1080))
	near.append(Vector2(1920, 1080))
	n.draw_colored_polygon(far, _s(0.085, 0.12, 0.25))
	n.draw_polyline(far_top, _s(0.3, 0.38, 0.6), 4.0)            # the moon on the snow of the ridge
	for i in 9:                                                   # a few snow fields down its sides
		var x := 60.0 + i * 220.0 + float(_h(i, 4, 204) % 90)
		n.draw_rect(Rect2(x, _ridge(x) + 16.0 + float(i % 3) * 9.0, 70 + _h(i, 5, 205) % 60, 5), _s(0.15, 0.2, 0.36))
	n.draw_colored_polygon(near, _s(0.055, 0.08, 0.185))
	n.draw_polyline(near_top, _s(0.2, 0.27, 0.46), 3.0)
	for i in 34:                                                  # pines: three boxes each, a touch of snow
		var x := float(_h(i, 6, 206) % 1900) + 10.0
		var y := _hill(x) + 6.0
		var h := 28.0 + float(_h(i, 7, 207) % 26)
		var pine := _s(0.03, 0.065, 0.115)
		n.draw_rect(Rect2(x - h * 0.3, y - h * 0.42, h * 0.6, h * 0.42), pine)
		n.draw_rect(Rect2(x - h * 0.21, y - h * 0.74, h * 0.42, h * 0.34), pine)
		n.draw_rect(Rect2(x - h * 0.1, y - h, h * 0.2, h * 0.28), pine)
		n.draw_rect(Rect2(x - h * 0.1, y - h, h * 0.2, 3), _s(0.26, 0.33, 0.52))
	for i in 20:                                                  # the town
		var x := 30.0 + i * 96.0 + float(_h(i, 8, 208) % 44)
		var w := 34.0 + float(_h(i, 9, 209) % 26)
		var h := 26.0 + float(_h(i, 10, 210) % 22)
		var y := _hill(x + w * 0.5) + 8.0
		n.draw_rect(Rect2(x, y - h, w, h + 30.0), _s(0.085, 0.095, 0.19))
		n.draw_rect(Rect2(x - 3, y - h - 5, w + 6, 6), _s(0.24, 0.3, 0.5))           # the roof's snow
		n.draw_rect(Rect2(x + 5, y - h - 11, w - 10, 6), _s(0.2, 0.26, 0.45))
		for k in 1 + _h(i, 11, 211) % 2:
			n.draw_rect(Rect2(x + 7 + k * 15, y - h + 8, 5, 7), _s(1.0, 0.72, 0.3))
	var cx := 1236.0                                              # the church: a nave, a tower, a spire
	var cy := _hill(cx) + 6.0
	var church := _s(0.075, 0.085, 0.18)
	n.draw_rect(Rect2(cx - 40, cy - 44, 70, 60), church)
	n.draw_rect(Rect2(cx + 30, cy - 84, 26, 100), church)
	n.draw_rect(Rect2(cx + 35, cy - 104, 16, 20), church)
	n.draw_rect(Rect2(cx + 40, cy - 124, 6, 20), church)
	n.draw_rect(Rect2(cx - 43, cy - 49, 76, 6), _s(0.24, 0.3, 0.5))
	n.draw_rect(Rect2(cx + 39, cy - 66, 8, 12), _s(1.0, 0.74, 0.32))
	n.draw_rect(Rect2(cx - 22, cy - 28, 6, 12), _s(1.0, 0.74, 0.32))
	n.draw_rect(Rect2(cx - 4, cy - 28, 6, 12), _s(1.0, 0.74, 0.32))

# The houses' fronts under the roofs (scenery: dark, flat, no light on them), the highest
# roof's first, so a lower house stands in front of a taller one. Each has rows of windows:
# most are lit, one may show a Christmas tree.
func _fronts(n: Node2D) -> void:
	for i in fronts.size():
		var r: Rect2 = fronts[i][0]
		var base: Color = FRONTS[fronts[i][1]]
		n.draw_rect(r, _sc(base))
		n.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 14), _sc(base.darkened(0.45)))   # the shade under the roof
		n.draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), _sc(base.lightened(0.12)))   # the corners
		n.draw_rect(Rect2(r.end.x - 3, r.position.y, 3, r.size.y), _sc(base.darkened(0.3)))
		var bi := 0
		var by := r.position.y + 24.0
		while by < r.end.y - 8.0:   # a few bricks that show
			for k in 3:
				var hb := _h(i * 31 + bi, k, 220)
				var bx := r.position.x + 8.0 + float(hb % int(maxf(8.0, r.size.x - 40.0)))
				n.draw_rect(Rect2(bx, by + float(k) * 9.0, 22, 2), _sc(base.lightened(0.07) if hb % 3 != 0 else base.darkened(0.25)))
			by += 30.0
			bi += 1
		var count := maxi(1, int((r.size.x - 24.0) / 84.0))
		var gap := r.size.x / count
		var wy := r.position.y + 40.0
		var row := 0
		while wy + 56.0 < r.end.y - 6.0:
			for k in count:
				var wx := r.position.x + gap * (k + 0.5) - 19.0
				var hw := _h(i * 13 + k, row, 221)
				_window(n, Rect2(wx, wy, 36, 50), hw % 10 < 6, hw % 23 == 3, base)
			wy += 104.0
			row += 1

# One window of a house front: a dark frame, warm glass with a cross of bars when it is
# lit (with a small glow round it), dark glass when it is not.
func _window(n: Node2D, r: Rect2, lit: bool, tree: bool, wall: Color) -> void:
	if lit:
		n.draw_texture_rect(HALO, r.grow_individual(26, 22, 26, 26), false, _s(1.0, 0.62, 0.22, 0.2))
	n.draw_rect(r.grow(3), _sc(wall.darkened(0.55)))
	if lit:
		_fade(n, r, _s(0.86, 0.64, 0.3), _s(0.78, 0.43, 0.16))
		if tree:                    # a Christmas tree inside
			var c := r.position + Vector2(r.size.x * 0.5, r.size.y)
			var green := _s(0.1, 0.3, 0.16)
			n.draw_rect(Rect2(c.x - 13, c.y - 14, 26, 14), green)
			n.draw_rect(Rect2(c.x - 9, c.y - 27, 18, 14), green)
			n.draw_rect(Rect2(c.x - 5, c.y - 39, 10, 13), green)
			n.draw_rect(Rect2(c.x - 2, c.y - 44, 4, 4), _s(1.0, 0.9, 0.4))
			for d in [[-7, -8, 0], [5, -18, 3], [-3, -24, 1], [7, -6, 4], [0, -33, 2]]:
				n.draw_rect(Rect2(c.x + d[0] - 1.5, c.y + d[1], 3, 3), _sc(BULBS[d[2]]))
	else:
		n.draw_rect(r, _s(0.05, 0.07, 0.15))
		n.draw_rect(Rect2(r.position.x + 5, r.position.y + 6, 4, 14), _s(0.14, 0.19, 0.34))
	var bar := _sc(wall.darkened(0.55))
	n.draw_rect(Rect2(r.position.x + r.size.x * 0.5 - 1.5, r.position.y, 3, r.size.y), bar)
	n.draw_rect(Rect2(r.position.x, r.position.y + r.size.y * 0.42, r.size.x, 3), bar)
	n.draw_rect(Rect2(r.position.x - 5, r.end.y + 3, r.size.x + 10, 4), _sc(wall.lightened(0.14)))   # the sill

# The belfry's inside, far behind the fighters who run through it: a dark back wall, a
# thin pillar at each end, the beam and the bronze bell.
func _belfry(n: Node2D) -> void:
	if belfry.size.x <= 0.0:
		return
	var r := belfry
	n.draw_rect(r, _s(0.085, 0.095, 0.17))
	n.draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 10), _s(0.04, 0.045, 0.09))
	for px in [r.position.x + 2.0, r.end.x - 12.0]:
		n.draw_rect(Rect2(px, r.position.y, 10, r.size.y), _s(0.24, 0.27, 0.38))
		n.draw_rect(Rect2(px, r.position.y, 3, r.size.y), _s(0.34, 0.38, 0.5))
	var c := Vector2(r.position.x + r.size.x * 0.36, r.position.y)
	n.draw_rect(Rect2(c.x - 40, c.y + 8, 80, 7), _s(0.2, 0.12, 0.07))                # the beam
	n.draw_rect(Rect2(c.x - 3, c.y + 15, 6, 8), _s(0.2, 0.12, 0.07))
	var bronze := _s(0.62, 0.45, 0.17)
	n.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, 22), c + Vector2(9, 22), c + Vector2(15, 34), c + Vector2(19, 58),
		c + Vector2(25, 66), c + Vector2(-25, 66), c + Vector2(-19, 58), c + Vector2(-15, 34)]), bronze)
	n.draw_rect(Rect2(c.x - 25, c.y + 62, 50, 5), _s(0.4, 0.28, 0.1))
	n.draw_rect(Rect2(c.x - 10, c.y + 28, 4, 26), _s(0.92, 0.76, 0.4))               # its shine
	n.draw_circle(c + Vector2(0, 72), 5.0, _s(0.34, 0.24, 0.1))                      # the clapper

# What holds a plank up when no block does: a pole under each loose end, down to the
# roof below it, and a cross brace between two poles. A ledge with a house front behind
# that end needs none (it is fixed to the wall), nor does a balcony of the tower.
func _poles(n: Node2D) -> void:
	var pole := _s(0.21, 0.14, 0.11)
	var lite := _s(0.34, 0.24, 0.18)
	for cy in range(2, level.ROWS - 2):
		var run := -1
		for cx in level.COLS + 1:
			var is_ledge: bool = cx < level.COLS and _ledge(cx, cy)
			if is_ledge and run < 0:
				run = cx
			elif not is_ledge and run >= 0:
				var feet: Array = []
				var balcony: bool = _kind(run - 1, cy) == K_TOWER or _kind(cx, cy) == K_TOWER   # the tower's own: it needs no pole
				for end in [[run, run - 1, 5.0], [cx - 1, cx, C - 11.0]]:
					if balcony or _solid(end[1], cy) or _in_front(end[0], cy):
						continue
					var down := cy + 1
					while down < level.ROWS - 1 and not _solid(end[0], down):
						down += 1
					if not _solid(end[0], down):
						continue                # nothing under it but an alley
					var x: float = end[0] * C + end[2]
					n.draw_rect(Rect2(x, cy * C + 14, 6, (down - cy) * C - 14), pole)
					n.draw_rect(Rect2(x, cy * C + 14, 2, (down - cy) * C - 14), lite)
					feet.append(Vector2(x + 3.0, down * C))
				if feet.size() == 2 and absf(feet[0].y - feet[1].y) < 1.0 and feet[0].y - cy * C > 100.0:
					var y0 := cy * C + 26.0
					var y1 := minf(feet[0].y - 14.0, y0 + 150.0)
					n.draw_line(Vector2(feet[0].x, y0), Vector2(feet[1].x, y1), pole, 4.0)
					n.draw_line(Vector2(feet[1].x, y0), Vector2(feet[0].x, y1), pole, 4.0)
				run = -1

# Is there a house front behind this cell?
func _in_front(cx: int, cy: int) -> bool:
	var p := Vector2(cx * C + 15.0, cy * C + 15.0)
	for f in fronts:
		if f[0].has_point(p):
			return true
	return false

# ------------------------------------------------------------------ behind the blocks, moving
func _draw() -> void:
	if not on or level == null:
		return
	_sleigh()
	_bulbs()
	_smoke()
	_star()

# The sleigh: a small dark shape with three reindeer that flies from left to right, a
# little upward, right across the moon. Only its shape: it is far away. A few sparks
# trail behind it.
func _sleigh() -> void:
	var u := fposmod(t - SLEIGH_FIRST, SLEIGH_EVERY) / SLEIGH_TIME
	if t < SLEIGH_FIRST or u >= 1.0:
		return
	var x := lerpf(-240.0, 2160.0, u)
	var at := Vector2(x, MOON.y + 54.0 - (x - 300.0) * 0.04 + sin(u * 9.0) * 7.0)
	var ink := _s(0.02, 0.02, 0.06)
	for k in (9 if rich else 5):   # the sparks it leaves
		var back := 44.0 + k * 24.0 + fmod(t * 60.0, 24.0)
		var a := 0.75 * (1.0 - back / 280.0)
		if a > 0.0:
			draw_rect(Rect2(at.x - back, at.y + 6.0 + sin(k * 2.1 + t * 3.0) * 7.0, 3, 3), _s(1.0, 0.86, 0.45, a))
	draw_set_transform(at, -0.04, Vector2(1.15, 1.15))
	# the sleigh: runner, body, the sack, the driver and his hat
	draw_polyline(PackedVector2Array([Vector2(-28, 13), Vector2(18, 13), Vector2(27, 7), Vector2(26, 0)]), ink, 2.5)
	draw_line(Vector2(-16, 8), Vector2(-16, 13), ink, 2.0)
	draw_line(Vector2(10, 8), Vector2(10, 13), ink, 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(-24, 9), Vector2(-27, -7), Vector2(-14, -7), Vector2(-10, 0), Vector2(10, 0),
		Vector2(15, -9), Vector2(22, -9), Vector2(18, 9)]), ink)
	_blob(self, Vector2(-17, -12), Vector2(9, 9), ink)
	_blob(self, Vector2(1, -9), Vector2(8, 10), ink)
	draw_circle(Vector2(3, -21), 5.0, ink)
	draw_colored_polygon(PackedVector2Array([Vector2(-2, -23), Vector2(8, -23), Vector2(-5, -33)]), ink)
	draw_circle(Vector2(-6, -33), 2.2, ink)
	# the reins, then three reindeer at a gallop
	draw_line(Vector2(22, -6), Vector2(150, -16), ink, 1.5)
	for k in 3:
		var p := Vector2(64.0 + k * 38.0, -7.0 - k * 3.0)
		var g := sin(t * 11.0 + k * 1.3) * 5.0
		draw_rect(Rect2(p.x - 12, p.y - 5, 24, 9), ink)                                # the body
		draw_rect(Rect2(p.x - 15, p.y - 6, 4, 4), ink)                                 # the tail
		draw_colored_polygon(PackedVector2Array([p + Vector2(6, -5), p + Vector2(12, -5), p + Vector2(18, -15), p + Vector2(13, -16)]), ink)
		draw_rect(Rect2(p.x + 12, p.y - 19, 10, 5), ink)                               # the head
		draw_line(p + Vector2(14, -19), p + Vector2(11, -27), ink, 1.5)                # the antlers
		draw_line(p + Vector2(12, -24), p + Vector2(8, -26), ink, 1.5)
		draw_line(p + Vector2(17, -19), p + Vector2(19, -27), ink, 1.5)
		draw_line(p + Vector2(18, -24), p + Vector2(22, -25), ink, 1.5)
		draw_line(p + Vector2(8, 3), p + Vector2(12.0 + g, 13), ink, 2.0)               # the legs
		draw_line(p + Vector2(5, 3), p + Vector2(4.0 - g * 0.6, 13), ink, 2.0)
		draw_line(p + Vector2(-8, 3), p + Vector2(-13.0 - g, 13), ink, 2.0)
		draw_line(p + Vector2(-5, 3), p + Vector2(-4.0 + g * 0.6, 13), ink, 2.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The string lights' bulbs: red, green, gold, blue, pink, one after another along each
# wire. Each one glows and dims in its own time.
func _bulbs() -> void:
	for si in wires.size():
		var sp: Array = wires[si]
		var count := maxi(4, int(absf(sp[1].x - sp[0].x) / 31.0))
		for j in count:
			var p := _wire_at(sp, (j + 0.5) / count)
			var k := 0.5 + 0.5 * sin(t * 2.6 + j * 1.9 + si * 2.3)
			var lit := k > 0.35
			var col: Color = BULBS[(j + si) % BULBS.size()]
			draw_rect(Rect2(p.x - 1, p.y, 2, 4), _s(0.12, 0.14, 0.2))
			if lit and rich:
				draw_rect(Rect2(p.x - 8, p.y - 1, 16, 18), _sc(col, 0.2))
			draw_rect(Rect2(p.x - 3, p.y + 3, 6, 9), _sc(col * (1.25 if lit else 0.42)))
			if lit:
				draw_rect(Rect2(p.x - 1, p.y + 5, 2, 3), _s(1.3, 1.3, 1.3))

# A little smoke from every chimney: grey puffs that rise, lean with the wind and fade.
# (The big stack's top is cut by the screen's edge: its smoke is drawn on both sides.)
func _smoke() -> void:
	var puffs := 4 if rich else 2
	for ci in pots.size():
		var top: Vector2 = pots[ci]
		for k in puffs:
			var u := fposmod(t * 0.17 + float(k) / puffs + ci * 0.37, 1.0)
			var p := top + Vector2(u * 34.0 + sin(u * 6.0 + k * 2.0 + ci) * 7.0, -8.0 - u * 118.0)
			var r := 6.0 + 13.0 * u
			var col := _s(0.62, 0.68, 0.86, minf(1.0, u * 7.0) * (1.0 - u) * 0.42)
			draw_circle(p, r, col)
			if top.x < 40.0:
				draw_circle(p + Vector2(1920, 0), r, col)
			elif top.x > 1880.0:
				draw_circle(p - Vector2(1920, 0), r, col)

# The gold star on the spire, on a short pole: it shines a little brighter and dimmer.
func _star() -> void:
	if spire.x < 0.0:
		return
	var c := spire + Vector2(0, -34)
	var k := 0.85 + 0.15 * sin(t * 3.1)
	draw_rect(Rect2(spire.x - 2, spire.y - 24, 4, 24), _s(0.34, 0.3, 0.2))
	if rich:
		draw_rect(Rect2(c.x - 20, c.y - 20, 40, 40), _s(1.0, 0.8, 0.3, 0.12 * k))
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * (15.0 if i % 2 == 0 else 6.5))
	draw_colored_polygon(pts, _s(1.3 * k, 1.02 * k, 0.36 * k))

# ------------------------------------------------------------------ the blocks and ledges, drawn once
func _paint_blocks(n: Node2D) -> void:
	var cols: int = level.COLS
	var rows: int = level.ROWS
	# each row's runs of one kind (and one roof): the fill and its texture
	for cy in rows:
		var cx := 0
		while cx < cols:
			var k := _kind(cx, cy)
			var c1 := cx + 1
			while k != 0 and c1 < cols and _kind(c1, cy) == k and roof_of[cy * cols + c1] == roof_of[cy * cols + cx]:
				c1 += 1
			if k != 0:
				_fill(n, k, cx, c1, cy)
			cx = c1
	# the edges: snow on every top you can stand on, a line under and beside
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
	_tower_face(n)
	_dormer_windows(n)
	# the ledges: each run a plank, a balcony or an awning
	for cy in rows:
		var run := -1
		for cx in cols + 1:
			var is_ledge: bool = cx < cols and _ledge(cx, cy)
			if is_ledge and run < 0:
				run = cx
			elif not is_ledge and run >= 0:
				_plank(n, run, cx, cy)
				run = -1

# One row's run of one kind, cells c0..c1: what it is made of.
func _fill(n: Node2D, k: int, c0: int, c1: int, cy: int) -> void:
	var r := Rect2(c0 * C, cy * C, (c1 - c0) * C, C)
	var y := cy * C
	if k == K_CLOUD:
		n.draw_rect(r, CLOUD)
		if cy == 1:
			n.draw_rect(Rect2(r.position.x, y + 18, r.size.x, 12), CLOUD_D)      # the heavy underside
		for cx in range(c0, c1):
			var h := _h(cx, cy, 30)
			n.draw_rect(Rect2(cx * C + h % 12, y + 2 + (h >> 4) % 10, 16 + (h >> 8) % 12, 7), CLOUD_L)
			if cy == 1 and h % 3 != 0:
				n.draw_rect(Rect2(cx * C + (h >> 5) % 14, y + 22, 14, 8), CLOUD)
	elif k == K_FLOOR or k == K_ROOF:
		var tile: Array = [SLATE, SLATE_D, Color(0.42, 0.48, 0.68)]
		if k == K_ROOF:
			tile = ROOFS[roof_of[cy * level.COLS + c0] % ROOFS.size()]
		n.draw_rect(r, tile[0])
		for b in 3:                    # three rows of tiles to a cell; each row starts half a tile on
			n.draw_rect(Rect2(r.position.x, y + b * 10 + 8, r.size.x, 2), tile[1])
		for cx in range(c0, c1):
			for b in 3:
				var off := 0 if (b + cy) % 2 == 0 else 8
				n.draw_rect(Rect2(cx * C + off, y + b * 10, 2, 8), tile[1])
				n.draw_rect(Rect2(cx * C + off + 15, y + b * 10, 2, 8), tile[1])
			var h := _h(cx, cy, 31)
			if h % 2 == 0:               # a lighter tile here and there
				var lb := (h >> 6) % 3
				n.draw_rect(Rect2(cx * C + (2 if (lb + cy) % 2 == 0 else 10), y + lb * 10, 13, 8), tile[2])
	elif k == K_CHIM or k == K_STACK:
		n.draw_rect(r, BRICK)
		for b in 3:
			n.draw_rect(Rect2(r.position.x, y + b * 10 + 8, r.size.x, 2), BRICK_D)
		for cx in range(c0, c1):
			for b in 3:
				var off := 6 if (b + cy) % 2 == 0 else 21
				n.draw_rect(Rect2(cx * C + off, y + b * 10, 2, 8), BRICK_D)
			var h := _h(cx, cy, 32)
			if h % 3 == 0:               # a paler brick here and there
				var lb := (h >> 6) % 3
				if (lb + cy) % 2 == 0:
					n.draw_rect(Rect2(cx * C + 8, y + lb * 10, 22, 8), BRICK_L)
				else:
					n.draw_rect(Rect2(cx * C, y + lb * 10, 21, 8), BRICK_L)
	elif k == K_TOWER:
		n.draw_rect(r, STONE)
		n.draw_rect(Rect2(r.position.x, y + 13, r.size.x, 2), STONE_D)
		n.draw_rect(Rect2(r.position.x, y + 28, r.size.x, 2), STONE_D)
		for cx in range(c0, c1):
			n.draw_rect(Rect2(cx * C + (10 if cy % 2 == 0 else 24), y, 2, 13), STONE_D)
			n.draw_rect(Rect2(cx * C + (24 if cy % 2 == 0 else 8), y + 15, 2, 13), STONE_D)
			var h := _h(cx, cy, 33)
			if h % 3 == 0:
				n.draw_rect(Rect2(cx * C + 2 + (h >> 4) % 12, y + (2 if (h >> 7) % 2 == 0 else 17), 12, 9), STONE_L)
	elif k == K_DORMER:
		n.draw_rect(r, PLASTER)
		n.draw_rect(Rect2(r.position.x, y + 26, r.size.x, 2), Color(0.74, 0.66, 0.5))

# The edges of one row's run, cells c0..c1, drawn inside its cells: nothing grows past
# where you stand.
func _edges(n: Node2D, k: int, c0: int, c1: int, cy: int) -> void:
	var y := cy * C
	var open_l: bool = _kind(c0 - 1, cy) == 0
	var open_r: bool = _kind(c1, cy) == 0
	var x0 := c0 * C
	var x1 := c1 * C
	if k == K_ROOF:                    # pale boards on a roof's open ends
		if open_l:
			n.draw_rect(Rect2(x0, y, 5, C), TRIM)
			n.draw_rect(Rect2(x0 + 5, y, 2, C), FASCIA)
		if open_r:
			n.draw_rect(Rect2(x1 - 5, y, 5, C), TRIM)
			n.draw_rect(Rect2(x1 - 7, y, 2, C), FASCIA)
	elif k == K_CHIM or k == K_STACK:   # the moon on the left side, shade on the right
		if open_l:
			n.draw_rect(Rect2(x0, y, 4, C), BRICK_L)
		if open_r:
			n.draw_rect(Rect2(x1 - 4, y, 4, C), BRICK_D)
	elif k == K_TOWER:
		if open_l:
			n.draw_rect(Rect2(x0, y, 4, C), STONE_L)
		if open_r:
			n.draw_rect(Rect2(x1 - 4, y, 4, C), STONE_D)
	elif k == K_DORMER:                # dark timbers at a dormer's corners
		if open_l:
			n.draw_rect(Rect2(x0, y, 5, C), TIMBER)
		if open_r:
			n.draw_rect(Rect2(x1 - 5, y, 5, C), TIMBER)
	elif k == K_FLOOR:
		if open_l:
			n.draw_rect(Rect2(x0, y, 5, C), TRIM)
		if open_r:
			n.draw_rect(Rect2(x1 - 5, y, 5, C), TRIM)
	# along the bottom and the top: one piece for each stretch with the same neighbour
	for pass_i in 2:
		var cx := c0
		while cx < c1:
			var other := _kind(cx, cy + 1 if pass_i == 0 else cy - 1)
			var e := cx + 1
			while e < c1 and _kind(e, cy + 1 if pass_i == 0 else cy - 1) == other:
				e += 1
			if pass_i == 0:
				_under(n, k, other, cx, e, y)
			elif other == 0 and k != K_CLOUD:
				_snow(n, k, cx, e, y, open_l and cx == c0, open_r and e == c1)
			cx = e

# Under a block: a roof's dark board with small icicles, a dark line under the others.
func _under(n: Node2D, k: int, below: int, c0: int, c1: int, y: int) -> void:
	if below == k or k == K_CLOUD or (k == K_FLOOR and below != 0):
		return
	var x := c0 * C
	var w := (c1 - c0) * C
	if below != 0:
		n.draw_rect(Rect2(x, y + C - 2, w, 2), Color(0.1, 0.08, 0.12, 0.7))
	elif k == K_ROOF:
		n.draw_rect(Rect2(x, y + C - 8, w, 8), FASCIA)
		n.draw_rect(Rect2(x, y + C - 10, w, 2), TRIM)
		for cx in range(c0, c1):       # icicles on the board (inside the cell)
			var h := _h(cx, y, 40)
			n.draw_rect(Rect2(cx * C + 3 + h % 9, y + C - 8, 3, 4 + (h >> 4) % 4), SNOW_SH)
			n.draw_rect(Rect2(cx * C + 17 + (h >> 7) % 8, y + C - 8, 2, 3 + (h >> 10) % 4), SNOW_SH)
	elif k == K_TOWER:
		n.draw_rect(Rect2(x, y + C - 5, w, 5), STONE_K)
	elif k == K_FLOOR:
		pass
	else:
		n.draw_rect(Rect2(x, y + C - 3, w, 3), Color(0.1, 0.08, 0.12))

# The snow on a top you can stand on, cells c0..c1 of a row whose top edge is y: a white
# cap, a blue shade under it, and drifts that hang a little lower here and there. A
# chimney gets its stone crown under the snow, a dormer its little roof.
func _snow(n: Node2D, k: int, c0: int, c1: int, y: int, end_l: bool, end_r: bool) -> void:
	var x := c0 * C
	var w := (c1 - c0) * C
	if k == K_CHIM or k == K_STACK:
		n.draw_rect(Rect2(x, y + 8, w, 7), CAP)
		n.draw_rect(Rect2(x, y + 15, w, 2), BRICK_D)
	elif k == K_DORMER:
		n.draw_rect(Rect2(x, y + 8, w, 8), DORMER_ROOF[0])
		n.draw_rect(Rect2(x, y + 16, w, 2), DORMER_ROOF[1])
	n.draw_rect(Rect2(x, y + 8, w, 3), SNOW_D if k == K_FLOOR or k == K_ROOF else SNOW_SH)
	n.draw_rect(Rect2(x, y, w, 9), SNOW)
	for cx in range(c0, c1):
		var h := _h(cx, y, 41)
		var dx := cx * C + h % 14
		var dw := 9 + (h >> 4) % 8
		n.draw_rect(Rect2(dx, y + 9, mini(dw, (cx + 1) * C - dx), 2 + (h >> 8) % 2), SNOW)
		n.draw_rect(Rect2(cx * C + 4 + (h >> 10) % 18, y + 4, 5, 2), SNOW_SH)      # a soft dent
	if end_l:                          # the snow rounds the corner a little
		n.draw_rect(Rect2(x, y + 9, 4, 5), SNOW)
	if end_r:
		n.draw_rect(Rect2(x + w - 4, y + 9, 4, 5), SNOW)

# The clock tower's face: the lit clock on its upper part (five to midnight), a warm
# arched window and a wreath on its base. All inside the tower's own blocks.
func _tower_face(n: Node2D) -> void:
	var x0 := TOWER_C0 * C
	var w := (TOWER_C1 - TOWER_C0 + 1) * C
	var mid := x0 + w * 0.5
	var top := -1
	var low := -1
	for cy in range(2, level.ROWS - 2):   # the upper part: full rows from the shoulders down to the belfry
		var full := _solid(TOWER_C0, cy) and _solid(TOWER_C1, cy)
		if full and top < 0:
			top = cy
		elif not full and top >= 0:
			low = cy
			break
	if top >= 0 and low - top >= 5:
		var c := Vector2(mid, (top + low) * C * 0.5 + 4.0)
		var r := minf(w * 0.5 - 24.0, (low - top) * C * 0.5 - 30.0)
		n.draw_circle(c, r + 9.0, STONE_K)
		n.draw_circle(c, r + 6.0, Color(1.2, 0.9, 0.38))
		n.draw_circle(c, r, Color(1.5, 1.28, 0.86))
		for i in 12:
			var d := Vector2.from_angle(i * TAU / 12.0)
			n.draw_line(c + d * (r - (11.0 if i % 3 == 0 else 7.0)), c + d * (r - 3.0), Color(0.2, 0.14, 0.12), 4.0 if i % 3 == 0 else 2.5)
		n.draw_line(c, c + Vector2.from_angle(-PI / 2.0 - 0.07) * (r * 0.5), Color(0.14, 0.1, 0.1), 6.0)      # the hour hand
		n.draw_line(c, c + Vector2.from_angle(-PI / 2.0 - PI / 6.0) * (r * 0.8), Color(0.14, 0.1, 0.1), 4.0)  # the minute hand
		n.draw_circle(c, 5.0, Color(0.14, 0.1, 0.1))
	if belfry.size.x > 0.0:
		var by := belfry.end.y           # the base's top
		var win := Rect2(mid - 19, by + 78, 38, 54)
		n.draw_circle(Vector2(mid, win.position.y), 24.0, STONE_K)
		n.draw_rect(win.grow_individual(5, 0, 5, 5), STONE_K)
		n.draw_circle(Vector2(mid, win.position.y), 19.0, GLASS_L)
		_fade(n, win, GLASS_L, GLASS)
		n.draw_rect(Rect2(mid - 2, win.position.y - 19, 4, win.size.y + 19), STONE_K)
		n.draw_rect(Rect2(win.position.x, win.position.y + 14, win.size.x, 4), STONE_K)
		n.draw_rect(Rect2(win.position.x - 9, win.end.y + 5, win.size.x + 18, 5), STONE_L)
		var wr := Vector2(mid, by + 212.0)                # the wreath
		if wr.y + 30.0 < (level.ROWS - 2) * C:
			n.draw_arc(wr, 17.0, 0.0, TAU, 20, Color(0.14, 0.46, 0.22), 9.0)
			n.draw_arc(wr, 17.0, 0.0, TAU, 20, Color(0.24, 0.62, 0.3), 3.0)
			for i in 5:
				n.draw_rect(Rect2(wr + Vector2.from_angle(i * TAU / 5.0 + 0.4) * 17.0 - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.25, 0.2))
			n.draw_rect(Rect2(wr.x - 9, wr.y + 12, 18, 7), Color(0.9, 0.16, 0.16))
			n.draw_rect(Rect2(wr.x - 3, wr.y + 10, 6, 11), Color(1.0, 0.3, 0.26))

# A small lit window on the front of each dormer (a dormer is a block: its front is solid).
func _dormer_windows(n: Node2D) -> void:
	for cy in range(2, level.ROWS - 2):
		var cx := 0
		while cx < level.COLS:
			if _kind(cx, cy) == K_DORMER and _kind(cx, cy - 1) != K_DORMER and _kind(cx - 1, cy) != K_DORMER:
				var w := 1
				while _kind(cx + w, cy) == K_DORMER:
					w += 1
				var deep := 0
				while _kind(cx, cy + deep) == K_DORMER:
					deep += 1
				if w >= 2 and deep >= 2:
					var win := Rect2(cx * C + w * C * 0.5 - 14.0, cy * C + 24.0, 28, minf(36.0, deep * C - 34.0))
					n.draw_rect(win.grow(3), TIMBER)
					_fade(n, win, GLASS_L, GLASS)
					n.draw_rect(Rect2(win.position.x + 12.5, win.position.y, 3, win.size.y), TIMBER)
					n.draw_rect(Rect2(win.position.x, win.position.y + win.size.y * 0.45, win.size.x, 3), TIMBER)
				cx += w
			else:
				cx += 1

# One run of ledge, cells c0..c1 on row cy. By the tower it is a stone balcony, low down
# it is a striped awning, anywhere else a wooden plank. Each has a white top of snow and
# a dark line under it, and a strut where it meets a block.
func _plank(n: Node2D, c0: int, c1: int, cy: int) -> void:
	var x0 := c0 * C * 1.0
	var x1 := c1 * C * 1.0
	var y := cy * C * 1.0
	var wall_l := _kind(c0 - 1, cy)
	var wall_r := _kind(c1, cy)
	var stone: bool = wall_l == K_TOWER or wall_r == K_TOWER
	var awning: bool = not stone and cy >= level.ROWS - 8
	var body := STONE_L if stone else WOOD
	var under := STONE_K if stone else WOOD_D
	if wall_l != 0:
		_strut(n, Vector2(x0, y), 1.0, under, body)
	if wall_r != 0:
		_strut(n, Vector2(x1, y), -1.0, under, body)
	if awning:
		var k := 0
		var x := x0
		while x < x1:                  # red and white stripes, each with a tab hanging under it
			var col := AWN_RED if k % 2 == 0 else AWN_WHITE
			n.draw_rect(Rect2(x, y + 6, 15, 9), col)
			n.draw_rect(Rect2(x + 1, y + 15, 13, 4), col.darkened(0.14))
			x += 15.0
			k += 1
		n.draw_rect(Rect2(x0, y + 6, x1 - x0, 2), Color(0.45, 0.1, 0.14, 0.55))
	else:
		n.draw_rect(Rect2(x0, y, x1 - x0, 15), body)
		n.draw_rect(Rect2(x0, y + 14, x1 - x0, 4), under)
		n.draw_rect(Rect2(x0, y, 2, 16), under)
		n.draw_rect(Rect2(x1 - 2, y, 2, 16), under)
		var jx := x0 + 60.0
		while jx < x1 - 20.0:          # where two boards (or two stones) meet
			n.draw_rect(Rect2(jx, y + 7, 1, 7), under)
			jx += 60.0
	n.draw_rect(Rect2(x0, y + 6, x1 - x0, 2), SNOW_SH)  # the snow on it, and its shade
	n.draw_rect(Rect2(x0, y, x1 - x0, 6), SNOW)
	for cx in range(c0, c1):
		var h := _h(cx, cy, 42)
		n.draw_rect(Rect2(cx * C + h % 16, y + 6, 8 + (h >> 4) % 6, 2), SNOW)

func _strut(n: Node2D, at: Vector2, dir: float, dark: Color, lite: Color) -> void:
	n.draw_line(at + Vector2(dir * 1.0, 30), at + Vector2(dir * 17.0, 16), dark, 5.0)
	n.draw_line(at + Vector2(dir * 2.0, 28), at + Vector2(dir * 15.0, 17), lite, 1.5)

# ------------------------------------------------------------------ in front, under the fighters
func _paint_front(n: Node2D) -> void:
	for i in lamps.size():             # the lanterns' glows first (one picture), then their boxes
		var k := _flicker(i)
		var p: Vector2 = lamps[i][0]
		n.draw_texture_rect(HALO, Rect2(p - Vector2(92, 86), Vector2(184, 172)), false, Color(1.0, 0.68, 0.26, 0.36 * k))
	for i in lamps.size():
		_lantern(n, lamps[i], i)
	# the snow: flakes that fall slowly and sway; each passes behind the blocks
	var count := FLAKES if rich else FLAKES_LOW
	for i in count:
		var fall := 38.0 + float(_h(i, 1, 101) % 46)
		var ph := float(_h(i, 3, 103) % 628) * 0.01
		var y := fposmod(float(_h(i, 5, 105) % 1140) + t * fall, 1140.0) - 30.0
		var x := fposmod(float(_h(i, 6, 106) % 2000) + t * 9.0 + sin(t * (0.7 + (i % 5) * 0.13) + ph) * (16.0 + float(i % 4) * 7.0), 2000.0) - 40.0
		if level.cell_at(x, y) == level.SOLID:
			continue
		var s := 3.0 + float(i % 4)
		var a := 0.66 + 0.3 * float(i % 4) / 3.0
		n.draw_rect(Rect2(x, y, s, s), Color(1, 1, 1, a))
		if i % 6 == 0:                 # a bigger flake: a small cross
			n.draw_rect(Rect2(x - 2, y + s * 0.5 - 1.0, s + 4, 2), Color(1, 1, 1, a))
			n.draw_rect(Rect2(x + s * 0.5 - 1.0, y - 2, 2, s + 4), Color(1, 1, 1, a))

func _flicker(i: int) -> float:
	return 0.86 + 0.14 * sin(t * 11.0 + i * 1.9) * sin(t * 6.7 + i)

# A lantern where a torch was: an iron frame, warm glass, a flame that flickers, snow and
# a red bow on its cap. It hangs on a chain from what is above it, or from an arm on the
# wall beside it.
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
	n.draw_rect(Rect2(p.x - 10, p.y - 18, 20, 3), Color(0.95, 0.97, 1.0))       # snow on it
	n.draw_rect(Rect2(p.x - 9, p.y - 12, 18, 23), Color(1.0, 0.82 * k, 0.38 * k))  # the glass
	var sway := sin(t * 9.0 + i * 2.3) * 1.2
	n.draw_rect(Rect2(p.x - 4, p.y + 1, 8, 8), Color(1.0, 0.95, 0.7))           # the flame
	n.draw_rect(Rect2(p.x - 3 + sway * 0.5, p.y - 4, 6, 6), Color(1.0, 0.98, 0.8))
	n.draw_rect(Rect2(p.x - 1.5 + sway, p.y - 4.0 - 5.0 * k, 3, 6), Color(1.0, 1.0, 0.9))
	n.draw_rect(Rect2(p.x - 10, p.y - 12, 2, 23), IRON)                         # the frame's bars
	n.draw_rect(Rect2(p.x + 8, p.y - 12, 2, 23), IRON)
	n.draw_rect(Rect2(p.x - 12, p.y + 10, 24, 4), IRON)                         # the base
	n.draw_rect(Rect2(p.x - 6, p.y + 14, 5, 5), Color(0.86, 0.12, 0.14))        # the red bow under it
	n.draw_rect(Rect2(p.x + 1, p.y + 14, 5, 5), Color(0.86, 0.12, 0.14))
	n.draw_rect(Rect2(p.x - 1.5, p.y + 14, 3, 4), Color(1.0, 0.3, 0.28))

# ------------------------------------------------------------------ the gust of snow
# The sweep on THE ROOFTOPS (the bat swarm's rule, sim.gd: GUST_FIRST, GUST_EVERY), drawn
# by client/powers_view.gd on any CanvasItem: the warning (wind lines at the edge it comes
# in from), then a white whirl of snow w x h sweeping across at cx, y.
static func gust(ci: CanvasItem, phase: int, cx: float, y: float, dir: float, w: float, h: float, tt: float) -> void:
	if phase == 0:
		var ex := 40.0 if dir > 0 else 1880.0
		ci.draw_rect(Rect2(0, y - h * 0.5, 1920, h), Color(0.8, 0.9, 1.0, 0.07 + 0.05 * sin(tt * 20.0)))
		for k in 4:
			var zy := y - h * 0.36 + k * h * 0.24
			var zx := ex + dir * fmod(tt * 300.0 + k * 70.0, 220.0)
			ci.draw_line(Vector2(zx, zy), Vector2(zx + dir * 90.0, zy), Color(1.0, 1.0, 1.0, 0.8), 4.0, true)
		return
	for k in 9:      # a white haze, long the way the wind goes
		var bx := cx + (k - 4) * w * 0.115 + sin(tt * 2.0 + k) * 12.0
		ci.draw_set_transform(Vector2(bx, y + sin(tt * 3.0 + k * 1.7) * 14.0), 0.0, Vector2(1.8, 1.0))
		ci.draw_circle(Vector2.ZERO, h * (0.36 if k % 3 == 0 else 0.3), Color(0.88, 0.94, 1.0, 0.07))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for k in 6:      # streaks of wind through it
		var sy := y - h * 0.4 + k * h * 0.16 + sin(tt * 4.0 + k * 2.2) * 6.0
		var sx := cx + (fposmod(k * 131.0 + tt * 520.0, w) - w * 0.5) * dir
		ci.draw_line(Vector2(sx, sy), Vector2(sx - dir * (70.0 + k * 12.0), sy), Color(1.0, 1.0, 1.0, 0.4), 2.0)
	for k in 3:      # the whirl: three curls that turn as it goes
		var c := Vector2(cx + (k - 1) * w * 0.3, y + sin(tt * 2.2 + k * 2.0) * h * 0.12)
		var turn := -dir * tt * 7.0 + k * 2.1
		for ring in 2:
			var rr := h * (0.3 - ring * 0.12)
			ci.draw_arc(c, rr, turn + ring * 1.6, turn + ring * 1.6 + 3.6, 14, Color(1.0, 1.0, 1.0, 0.55 - ring * 0.1), 4.0 - ring, true)
	for i in 84:     # the flakes, each going round as the wind carries it
		var hx := fposmod(i * 97.0 + tt * 80.0 * (1.0 + (i % 3) * 0.3), w) - w * 0.5
		var hy := fposmod(i * 53.0, h) - h * 0.5
		var ang := tt * (5.0 + i % 4) + i
		var p := Vector2(cx + hx * dir + cos(ang) * 16.0, y + hy * 0.8 + sin(ang) * 14.0)
		var s := 4.0 + float(i % 4) * 1.5
		ci.draw_rect(Rect2(p.x - s * 0.5, p.y - s * 0.5, s, s), Color(1.0, 1.0, 1.0, 0.95))

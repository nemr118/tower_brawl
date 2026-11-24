# THE BIG TABLE's look (theme "table", sim/level.gd): the fighters are tiny and the arena
# is a Thanksgiving dinner table seen from the side, in a warm dining room in the evening.
# world.gd makes one (behind the tiles), calls setup once, and on each arena and each
# look leave() before the other arenas' looks and set_theme() after them. What goes where:
#   this node (the lit world, behind the blocks): the room, out of focus
#     (assets/table_back.png: a window at dusk, chair backs, a sideboard);
#   front (a sprite in the lit world, where the tile layers were): the blocks and ledges
#     (assets/table_front.png: the roast on its platter, the candlesticks, the gravy boat
#     over its plates, the pie on its stand, the lamp, the cutlery, the tablecloth);
#   fire (the threats layer, under the fighters: never darkened): the candle flames and
#     a little steam off the roast, the gravy and the pie;
#   glow (the glow layer, added light): each flame's halo and the lamp's light.
# Both pictures are made by tools/make_table_art.py from the map, so they are drawn once
# and cost one sprite each. Only the flames, the steam and the halos move, and they are
# drawn again 30 times a second. The LOW look has no steam.
# Where things are comes from the map's torches (level.gd, the letters a..h): a and b
# sit over the two candles, c under the lamp, d over the roast, e over the gravy boat,
# f over the pie, g and h are the room's own lights. Nothing here knows a layout number.
# set_theme changes world.dark_base (the evening's colour), the torches' lights and a few
# of the castle's parts (the stone torches, the backdrops, the tiles, the embers, the fog,
# the side light shafts, HIGH's bloom); leave() puts them back.
extends Node2D

const BACK := preload("res://assets/table_back.png")
const FRONT := preload("res://assets/table_front.png")
const HALO := preload("res://assets/fx_halo.png")
const C := 30                                # the grid (sim/level.gd CELL)
const REDRAW_HZ := 30.0                      # the moving parts are drawn again this often, not every frame (cheaper on phones)
const DARK := Color(0.8, 0.72, 0.66)         # the evening (world.dark_base): warm, and light enough for white china
const DARK_HIGH := Color(0.62, 0.56, 0.52)   # on HIGH: dimmer, or the look's bloom makes all the white things glow
const BLOOM_HIGH := 0.5                      # and half the bloom: the flames and the lamp glow, the china does not
const CANDLE := Color(0.82, 0.54, 0.28)      # a candle's light
const LAMP := Color(0.8, 0.66, 0.46)         # the lamp's light
const FILL := Color(0.5, 0.34, 0.2)          # the dimmer lights (the roast, the gravy, the pie, the room)
const STEAM := Color(1.0, 0.97, 0.92)
const PUFFS := 5                             # steam puffs a place

var world
var on := false
var low := false                             # the LOW look: no steam
var t := 0.0
var redraw_wait := 0.0
var back := Sprite2D.new()
var front := Sprite2D.new()
var fire: _Layer
var glow: _Layer
var wicks: Array = []                        # Vector2: the top of each candle (the flame stands on it)
var lamp := Vector2.ZERO                     # the middle of the lamp's underside
var has_lamp := false
var steam: Array = []                        # [Vector2 where it rises from, how wide, how strong]

class _Layer extends Node2D:
	var tv
	var which := 0
	func _draw() -> void:
		if tv != null and tv.on:
			tv._paint(self, which)

func setup(w) -> void:
	world = w
	visible = false
	for spr in [back, front]:
		spr.centered = false
		spr.scale = Vector2(2, 2)            # the pictures are 960 x 540
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # smooth art: no blocky pixels at a phone's odd sizes
	back.texture = BACK
	add_child(back)
	front.texture = FRONT
	front.visible = false
	world.add_child(front)
	world.move_child(front, world.tiles_lit.get_index() + 1)
	fire = _new_layer(1, world.threats)
	world.threats.move_child(fire, 0)        # first in the threats layer: under the fighters
	glow = _new_layer(2, world.glow)
	glow.material = world.add_mat

func _new_layer(which: int, parent: Node) -> _Layer:
	var n := _Layer.new()
	n.tv = self
	n.which = which
	n.visible = false
	parent.add_child(n)
	return n

# world.gd calls leave() first, before the other arenas' looks take their turn: if the
# table was on, everything it hid goes back to what the look has on every arena (the
# castle's backdrops and tiles, the embers, the fog, the light shafts, the torches'
# halos, HIGH's bloom). So the next arena's own look starts from the usual state and
# hides what it wants; this file never needs to know the other arenas.
func leave() -> void:
	if not on:
		return
	on = false
	visible = false
	for n in [front, fire, glow]:
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
	for i in world.fogs.size():
		world.fogs[i].visible = i < world.fog_on
	for tr in world.torches:
		tr[3].visible = fx_on
	world.post.material.set_shader_parameter("bloom", 1.0 if world.parts.get("bloom", false) else 0.0)

# Another arena or another look; world.gd calls this last, after the other looks. On the
# table the room and the blocks are ours (the castle's backdrops, tiles and stone torches
# hide) and the night turns into a warm evening.
func set_theme(level) -> void:
	leave()                                  # (it already ran; this keeps a lone call safe)
	if level.theme != "table":
		return
	on = true
	visible = true
	for n in [front, fire, glow]:
		n.visible = true
	low = not world.parts.get("particles", false)
	var bloom: bool = world.parts.get("bloom", false)
	_find(level)
	world.dark_base = DARK_HIGH if bloom else DARK
	world.dark.color = world.dark_base
	if bloom:
		world.post.material.set_shader_parameter("bloom", BLOOM_HIGH)
	world.bg_far.visible = false
	world.bg_mid.visible = false
	world.tiles_plain.visible = false
	world.tiles_lit.visible = false
	world.ambient[0].visible = false         # no embers rise through a dining room (the dust motes stay)
	world.ambient[0].emitting = false
	for f in world.fogs:                     # and no fog: its coarse squares show on the smooth pictures
		f.visible = false
	for i in world.shafts.size():            # one light shaft stays: the lamp's, in the middle
		world.shafts[i].visible = world.parts.get("shafts", false) and i == 1
	for i in world.torches.size():
		var tr: Array = world.torches[i]
		tr[0].visible = false                # the stone torches: ours are candles and a lamp (their lights stay)
		tr[2].visible = false
		tr[2].emitting = false
		tr[3].visible = false
		tr[1].color = (CANDLE if i < 2 else (LAMP if i == 2 else FILL)) * (0.8 if bloom else 1.0)
	for i in mini(wicks.size(), world.torches.size()):
		world.torches[i][1].position = wicks[i] + Vector2(0, -40)
	if has_lamp and world.torches.size() > 2:
		world.torches[2][1].position = lamp + Vector2(0, 110)
	redraw_wait = 0.0

# Where the flames, the lamp's light and the steam go, from the map's torches.
func _find(level) -> void:
	wicks.clear()
	steam.clear()
	has_lamp = false
	var tl: Array = level.torches
	for i in mini(2, tl.size()):             # a, b: a candle under each
		wicks.append(_block_edge(level, tl[i], 1))
	if tl.size() > 2:                        # c: the lamp over it
		lamp = _block_edge(level, tl[2], -1)
		has_lamp = true
	for i in range(3, mini(6, tl.size())):   # d, e, f: the roast, the gravy, the pie
		var cx := int(tl[i].x / C)
		var cy := int(tl[i].y / C) + 1
		var run := _run(level, cx, cy)
		steam.append([Vector2((run.x + run.y + 1) * C * 0.5, cy * C), (run.y - run.x + 1) * C * 0.5,
			1.0 if i == 3 else 0.7])

# The run of block cells along row cy that holds column cx: Vector2i(first, last).
func _run(level, cx: int, cy: int) -> Vector2i:
	var a := cx
	var b := cx
	while a > 0 and level.cell(a - 1, cy) == level.SOLID:
		a -= 1
	while b < level.COLS - 1 and level.cell(b + 1, cy) == level.SOLID:
		b += 1
	return Vector2i(a, b)

# The middle of the block's edge next to a torch's cell: the block under it (dir 1: its
# top) or over it (dir -1: its underside). With no block there, the torch's own place.
func _block_edge(level, p: Vector2, dir: int) -> Vector2:
	var cx := int(p.x / C)
	var cy := int(p.y / C) + dir
	if level.cell(cx, cy) != level.SOLID:
		return p
	var run := _run(level, cx, cy)
	return Vector2((run.x + run.y + 1) * C * 0.5, (cy if dir > 0 else cy + 1) * C)

func _process(delta: float) -> void:
	if not on:
		return
	t += delta
	redraw_wait -= delta
	if redraw_wait > 0.0:
		return
	redraw_wait = 1.0 / REDRAW_HZ
	fire.queue_redraw()
	glow.queue_redraw()

# How bright candle i burns now, about 0.75 to 1: two slow waves and a quick one.
func _flicker(i: int) -> float:
	return 0.87 + 0.08 * sin(t * 9.0 + i * 2.3) * sin(t * 5.3 + i) + 0.05 * sin(t * 23.0 + i * 1.7)

func _paint(n: Node2D, which: int) -> void:
	if which == 1:
		_paint_fire(n)
	else:
		_paint_glow(n)

# Under the fighters: the steam, then the flames.
func _paint_fire(n: Node2D) -> void:
	if not low:
		for si in steam.size():
			var src: Vector2 = steam[si][0]
			var wide: float = steam[si][1]
			var strong: float = steam[si][2]
			for k in PUFFS:   # each puff rises, drifts, grows and fades, then starts again
				var u := fposmod(t * 0.13 + float(k) / PUFFS + si * 0.31, 1.0)
				var x := src.x + (float(k) / (PUFFS - 1) - 0.5) * wide * 1.1 + sin(u * 5.0 + k * 2.1 + si) * 16.0 * u
				var y := src.y - 8.0 - u * 130.0
				var s := 34.0 + 70.0 * u
				var a := sin(u * PI) * 0.32 * strong
				n.draw_texture_rect(HALO, Rect2(x - s * 0.5, y - s * 0.7, s, s * 1.4), false, Color(STEAM, a))
	for i in wicks.size():
		var p: Vector2 = wicks[i] + Vector2(0, -7)      # the top of the wick
		var k := _flicker(i)
		var sway := sin(t * 6.1 + i * 2.3) * 2.2 + sin(t * 13.7 + i) * 0.9
		for layer in 3:   # an orange flame, a yellow one in it, a white heart
			var w: float = [9.0, 6.0, 3.0][layer] * (0.9 + 0.1 * k)
			var h: float = [38.0, 26.0, 13.0][layer] * k
			var col: Color = [Color(1.0, 0.5, 0.12, 0.95), Color(1.0, 0.8, 0.3), Color(1.0, 0.98, 0.84)][layer]
			var lift: float = [0.0, 1.0, 2.0][layer]
			n.draw_colored_polygon(PackedVector2Array([p + Vector2(0, 4.0 - lift), p + Vector2(-w, -h * 0.16),
				p + Vector2(-w * 0.72, -h * 0.5), p + Vector2(sway * (0.4 + 0.2 * layer), -h),
				p + Vector2(w * 0.72, -h * 0.5), p + Vector2(w, -h * 0.16)]), col)

# Added light: a halo round each flame, the lamp's light falling on the table.
func _paint_glow(n: Node2D) -> void:
	for i in wicks.size():
		var p: Vector2 = wicks[i] + Vector2(0, -20)
		var k := _flicker(i)
		n.draw_texture_rect(HALO, Rect2(p - Vector2(150, 140) * k, Vector2(300, 280) * k), false, Color(1.0, 0.55, 0.2, 0.2))
		n.draw_texture_rect(HALO, Rect2(p - Vector2(46, 50), Vector2(92, 96)), false, Color(1.0, 0.7, 0.3, 0.55 * k))
	if has_lamp:
		var k := 0.96 + 0.04 * sin(t * 1.3)
		n.draw_texture_rect(HALO, Rect2(lamp + Vector2(-230, -70), Vector2(460, 420)), false, Color(1.0, 0.8, 0.5, 0.2 * k))
		n.draw_texture_rect(HALO, Rect2(lamp + Vector2(-60, -34), Vector2(120, 90)), false, Color(1.0, 0.9, 0.65, 0.4 * k))

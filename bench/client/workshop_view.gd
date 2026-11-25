# SANTA'S WORKSHOP's look (theme "workshop", sim/level.gd layout 8), for Christmas: the
# workshop cut open like a doll's house, warm and bright, and its toy train drawn from
# the snapshot's state (sim/workshop.gd write/read). world.gd makes one (behind the
# tiles), calls setup once, and on each arena and each look leave() before the other
# arenas' looks and set_theme() after them; show_view each frame, on_event for each event.
# What goes where:
#   back (a sprite, the lit world, behind the blocks): the room, a little out of focus
#     and dimmer than the platforms (assets/workshop_back.png: wood walls, two frosty
#     windows, the big tree, the fireplace, toy cabinets, the gift chute);
#   anim (the lit world, over the back, behind the blocks; 30 times a second): what
#     moves in the room: snow outside the windows, the tree's lights, the fire, the
#     presents sliding down the chute;
#   front (a sprite in the lit world, where the tile layers were): the blocks and ledges
#     (assets/workshop_front.png). Every top you can stand on has a white icing lip, and
#     nothing is painted outside a block's own cells;
#   under (the threats layer, under the fighters): the lanterns where the torches were,
#     the signal's lamps at the tunnel mouths, the warning on the track (a red glow over
#     the strip the train will fill, arrows marching the way it goes);
#   top (the threats layer, over the fighters, every frame while a train is about): the
#     train (assets/workshop_parts.png: engine, wagons, wheels that turn), its steam,
#     the whistle's puff, a bonk where it hits someone;
#   glow (the glow layer, added light): the fire's and the star's glow, the lanterns',
#     the signal's, the engine's lamp.
# The three pictures are made by tools/make_workshop_art.py from the map: drawn once,
# one sprite each. WINDOWS, FIRE, CHUTE and PARTS are that tool's numbers.
# The train is drawn where it is on YOUR tick when you have a fighter (game_client.gd
# rolls the state on: workshop.gd on_tick), else where the snapshot has it; between two
# states it rolls on by the clock (not in a replay: a replay's frames are its own).
# LOW (no particles) gets fewer lights, snowflakes, presents and puffs; the warning and
# the train are the same on every look (they are part of play).
# set_theme changes world.dark_base (the room's light), the torches' lights and a few
# of the castle's parts (stone torches, backdrops, tiles, embers, fog, light shafts,
# spirit lights, HIGH's bloom); leave() puts them back.
extends Node2D

const P = preload("res://sim/proto.gd")
const Shop = preload("res://sim/workshop.gd")
const BACK := preload("res://assets/workshop_back.png")
const FRONT := preload("res://assets/workshop_front.png")
const PARTS_TEX := preload("res://assets/workshop_parts.png")
const HALO := preload("res://assets/fx_halo.png")
# the moving parts in assets/workshop_parts.png (tools/make_workshop_art.py PARTS)
const PARTS := {"engine": Rect2(0, 0, 120, 80), "wagon_a": Rect2(120, 0, 80, 80), "wagon_b": Rect2(200, 0, 80, 80),
	"wheel_big": Rect2(280, 0, 28, 28), "wheel_small": Rect2(280, 28, 22, 22), "lamp_on": Rect2(280, 50, 20, 20),
	"gift_0": Rect2(308, 0, 16, 16), "gift_1": Rect2(324, 0, 16, 16), "gift_2": Rect2(340, 0, 16, 16),
	"lantern": Rect2(356, 0, 32, 44)}
const GROUND := 76.0                         # the rail's top in the engine's and the wagons' boxes
# the train's cars, front to back: [part, its length on the track, where its front is in its box, wheels
# [x in the box, radius, part]] (the tool's CARS). 92 + 6 + 68 + 6 + 68 = 240 px: sim/workshop.gd TRAIN_LEN
const CARS := [
	["engine", 92.0, 110.4, [[26.4, 14.0, "wheel_big"], [55.2, 14.0, "wheel_big"], [80.4, 11.0, "wheel_small"]]],
	["wagon_a", 68.0, 72.0, [[19.2, 11.0, "wheel_small"], [57.6, 11.0, "wheel_small"]]],
	["wagon_b", 68.0, 72.0, [[19.2, 11.0, "wheel_small"], [57.6, 11.0, "wheel_small"]]]]
const CAR_GAP := 6.0
const C := 30                                # the grid (sim/level.gd CELL)
const REDRAW_HZ := 30.0                      # the room's moving parts are drawn again this often (the train: every frame)
const DARK := Color(0.93, 0.88, 0.82)        # the room's light (world.dark_base): warm and bright
const DARK_HIGH := Color(0.74, 0.7, 0.66)    # on HIGH: dimmer, or the look's bloom makes all the icing glow
const BLOOM_HIGH := 0.5
const LAMP := Color(0.42, 0.3, 0.16)         # a lantern's light (dim: the room is bright already)
const FIRE_LIGHT := Color(0.62, 0.36, 0.14)
const STAR_LIGHT := Color(0.5, 0.44, 0.22)
const FLOOR_Y := 1020.0
const WINDOWS := [Rect2(600, 100, 180, 190), Rect2(1140, 100, 180, 190)]   # the two windows' glass
const FIRE := Rect2(1440, 246, 180, 84)                                    # the firebox's opening
const CHUTE := [Vector2(420, 338), Vector2(118, 506)]                      # the chute's slide, top to bottom
const TREE_TOP := 430.0
const BULB_COLS := [Color(1.0, 0.86, 0.45), Color(1.0, 0.42, 0.38), Color(0.5, 0.78, 1.0), Color(0.56, 1.0, 0.64)]
const SIGNAL_X := [44.0, 1876.0]             # the signal's two lamps on each tunnel's arch (left mouth, right mouth),
const SIGNAL_Y := [899.0, 914.0]             # one over the other

var world
var on := false
var rich := false                # NORMAL and HIGH: more of everything that only looks nice
var t := 0.0
var redraw_wait := 0.0
var back := Sprite2D.new()
var front := Sprite2D.new()
var anim: _Layer
var under: _Layer
var top: _Layer
var glow: _Layer
var hz := {}                     # the newest train state (sim/workshop.gd read, rolled on to your tick when you play)
var age := 0.0                   # ticks since it changed (the page rolls it on between states)
var lamps: Array = []            # [the lantern's place, the top of its chain]
var bulbs: Array = []            # [place, colour index, phase]: the tree's lights
var star := Vector2(960, 420)    # the star's middle
var fire_at := Vector2(1530, 300)
var bonks: Array = []            # [place, seconds so far, 1 the train ran right]
var was_busy := false

class _Layer extends Node2D:
	var wv
	var which := 0
	func _draw() -> void:
		if wv != null and wv.on:
			wv._paint(self, which)

func setup(w) -> void:
	world = w
	visible = false
	for spr in [back, front]:
		spr.centered = false
		spr.scale = Vector2(2, 2)            # the pictures are 960 x 540
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	back.texture = BACK
	add_child(back)
	anim = _new_layer(0, self)
	front.texture = FRONT
	front.visible = false
	world.add_child(front)
	world.move_child(front, world.tiles_lit.get_index() + 1)
	under = _new_layer(1, world.threats)
	world.threats.move_child(under, 0)       # first in the threats layer: under the fighters
	top = _new_layer(2, world.threats)
	top.z_index = 3                          # over the fighters and the arrows: the train is the danger
	glow = _new_layer(3, world.glow)
	glow.material = world.add_mat

func _new_layer(which: int, parent: Node) -> _Layer:
	var n := _Layer.new()
	n.wv = self
	n.which = which
	n.visible = false
	parent.add_child(n)
	return n

# world.gd calls leave() first, before the other arenas' looks take their turn: if the
# workshop was on, everything it hid goes back to what the look has on every arena. So
# the next arena's own look starts from the usual state (client/table_view.gd's way).
func leave() -> void:
	if not on:
		return
	on = false
	visible = false
	for n in [front, anim, under, top, glow]:
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
	world._set_wisps(int(world.parts.get("wisps", 0)), int(world.parts.get("wisp_lights", 0)))
	for tr in world.torches:
		tr[3].visible = fx_on
	world.post.material.set_shader_parameter("bloom", 1.0 if world.parts.get("bloom", false) else 0.0)

# Another arena or another look; world.gd calls this last, after the other looks. On the
# workshop the room and the blocks are ours and the night turns into a warm bright room.
func set_theme(level) -> void:
	leave()                                  # (it already ran; this keeps a lone call safe)
	if level.theme != "workshop":
		return
	on = true
	visible = true
	for n in [front, anim, under, top, glow]:
		n.visible = true
	rich = world.parts.get("particles", false)
	var bloom: bool = world.parts.get("bloom", false)
	world.dark_base = DARK_HIGH if bloom else DARK
	world.dark.color = world.dark_base
	if bloom:
		world.post.material.set_shader_parameter("bloom", BLOOM_HIGH)
	world.bg_far.visible = false
	world.bg_mid.visible = false
	world.tiles_plain.visible = false
	world.tiles_lit.visible = false
	world.ambient[0].visible = false         # no embers, no fog, no light shafts, no spirit lights: a tidy bright room
	world.ambient[0].emitting = false
	for f in world.fogs:
		f.visible = false
	for sh in world.shafts:
		sh.visible = false
	world._set_wisps(0, 0)
	for i in world.torches.size():
		var tr: Array = world.torches[i]
		tr[0].visible = false                # the stone torches: ours are the fire, the star and lanterns (their lights stay)
		tr[2].visible = false
		tr[2].emitting = false
		tr[3].visible = false
		tr[1].color = (FIRE_LIGHT if i == 0 else (STAR_LIGHT if i == 1 else LAMP)) * (0.8 if bloom else 1.0)
	_find(level)
	hz = {}
	age = 0.0
	bonks.clear()
	redraw_wait = 0.0

# Where the lanterns hang, where the fire and the star are, and the tree's lights: from
# the map. The torches: a is the fire, b the star's light, the rest are lanterns.
func _find(level) -> void:
	lamps.clear()
	bulbs.clear()
	var tl: Array = level.torches
	if tl.size() > 0:
		fire_at = tl[0]
	if tl.size() > 1:
		star = tl[1] + Vector2(15, 75)       # the star block is under its light, in the arena's middle
	for i in range(2, tl.size()):
		var p: Vector2 = tl[i]
		var cx := int(p.x / C)
		var cy := int(p.y / C)
		var chain := p.y - 66.0
		for up in range(1, 6):               # the block or the ledge it hangs under
			var c: int = level.cell(cx, cy - up)
			if c != 0:
				chain = (cy - up) * C + (C if c == level.SOLID else 11)
				break
		lamps.append([p, chain])
	# the tree's tiers: the runs of ledge centred on the arena, under the star; lights
	# hang on strings between them
	var tiers: Array = []
	for cy in range(int(star.y / C) + 1, level.ROWS - 2):
		var c0 := -1
		var c1 := -1
		for cx in level.COLS:
			if level.cell(cx, cy) == level.LEDGE and absi(cx - level.COLS / 2) < 12:
				c0 = cx if c0 < 0 else c0
				c1 = cx
		if c0 >= 0 and absi(c0 + c1 + 1 - level.COLS) <= 1:
			tiers.append(Vector3(c0 * C, (c1 + 1) * C, cy * C))
	var prev_y := TREE_TOP
	var prev_w := 14.0
	var n := 0
	for i in tiers.size():
		var half: float = (tiers[i].y - tiers[i].x) * 0.5 - 8.0
		var y1: float = tiers[i].z
		for row in 2:                        # two strings to a tier, each sagging in the middle
			var u := 0.42 if row == 0 else 0.8
			var yy := lerpf(prev_y, y1, u)
			var wd := lerpf(prev_w * 0.6, half * 0.9, u)
			var count := 2 + i + row
			for k in count:
				var a := lerpf(-0.82, 0.82, (k + 0.5) / count)
				bulbs.append([Vector2(960.0 + wd * sin(a) / sin(0.82), yy + 16.0 * cos(a * 1.9) - 8.0), n % BULB_COLS.size(), n * 1.37])
				n += 1
		prev_y = y1
		prev_w = half

# ------------------------------------------------------------------ each frame
func show_view(s: Dictionary, delta: float) -> void:
	if not on:
		return
	t += delta
	var h: Dictionary = s.get("hazards", {})
	if int(h.get("k", 0)) == Shop.KIND:
		var same: bool = not hz.is_empty() and int(h["phase"]) == int(hz["phase"]) and float(h["t"]) == float(hz["t"]) and int(h["dir"]) == int(hz["dir"])
		if same and not world.replaying and not bool(h["held"]):
			age = minf(age + delta * 60.0, 4.0)
		else:
			age = 0.0
		hz = h
	for i in range(bonks.size() - 1, -1, -1):
		bonks[i][1] += delta
		if bonks[i][1] > 0.5:
			bonks.remove_at(i)
	var busy: bool = _phase() != Shop.IDLE or not bonks.is_empty()
	if busy or was_busy:
		top.queue_redraw()                   # the train: every frame (and once more to wipe it)
		under.queue_redraw()
		glow.queue_redraw()
	was_busy = busy
	redraw_wait -= delta
	if redraw_wait <= 0.0:
		redraw_wait = 1.0 / REDRAW_HZ
		anim.queue_redraw()
		under.queue_redraw()
		glow.queue_redraw()

func on_event(e: Array) -> void:
	if not on:
		return
	if e[0] == P.E_TRAIN_HIT:
		bonks.append([Vector2(e[1], e[2]), 0.0, e[4]])
		world.fx.shake = maxf(world.fx.shake, 5.0)

func _phase() -> int:
	return int(hz.get("phase", Shop.IDLE))

# Ticks into the train's phase, rolled on between states.
func _ticks() -> float:
	return float(hz.get("t", 0.0)) + age

func _dir() -> int:
	return int(hz.get("dir", 1))

func _paint(n: Node2D, which: int) -> void:
	if which == 0:
		_paint_anim(n)
	elif which == 1:
		_paint_under(n)
	elif which == 2:
		_paint_top(n)
	else:
		_paint_glow(n)

static func _h(x: int, y: int, salt: int) -> int:
	return ((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)) & 0x7fffffff

func _part(n: CanvasItem, name: String, at: Vector2, col: Color = Color.WHITE) -> void:
	var r: Rect2 = PARTS[name]
	n.draw_texture_rect_region(PARTS_TEX, Rect2(at, r.size), r, col)

# ------------------------------------------------------------------ the room's moving parts (behind the blocks)
func _paint_anim(n: Node2D) -> void:
	# snow falling outside the two windows: in each of a window's four panes
	var flakes := 7 if rich else 4
	for wi in WINDOWS.size():
		var w: Rect2 = WINDOWS[wi]
		for pane in 4:
			var pr := Rect2(w.position + Vector2((pane % 2) * (w.size.x * 0.5 + 3.0) + 2.0, (pane / 2) * (w.size.y * 0.5 + 3.0) + 2.0),
				w.size * 0.5 - Vector2(7, 7))
			for i in flakes:
				var hh := _h(i, pane, 10 + wi)
				var sp := 16.0 + float(hh % 22)
				var y := fposmod(float((hh >> 5) % 200) + t * sp, pr.size.y)
				var x := fposmod(float((hh >> 9) % 200) + sin(t * 0.9 + i * 1.7) * 5.0 + t * 3.0, pr.size.x - 3.0)
				var sz := 2.0 + float((hh >> 3) % 2)
				n.draw_rect(Rect2(pr.position + Vector2(x, y), Vector2(sz, sz)), Color(1, 1, 1, 0.8))
	# the tree's lights: they take turns, two colours lit at a time
	var count := bulbs.size() if rich else (bulbs.size() + 1) / 2
	for i in count:
		var b: Array = bulbs[i if rich else i * 2]
		var c: Color = BULB_COLS[b[1]]
		var turn := 0.5 + 0.5 * sin(t * 2.2 + float(b[1]) * PI * 0.5)
		var k := clampf(turn * 1.6 - 0.3, 0.0, 1.0) * (0.85 + 0.15 * sin(t * 9.0 + b[2]))
		var p: Vector2 = b[0]
		n.draw_texture_rect(HALO, Rect2(p - Vector2(13, 13), Vector2(26, 26)), false, Color(c, 0.5 * k))
		n.draw_rect(Rect2(p - Vector2(3.5, 3.5), Vector2(7, 7)), c.darkened(0.55).lerp(c, k))   # (boxes: cheap, and they batch)
		n.draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(3, 3)), Color(1, 1, 1, 0.8 * k))
	# the fire in the fireplace: tongues of flame over the logs
	var fy := FIRE.end.y - 6.0
	n.draw_texture_rect(HALO, Rect2(FIRE.position.x - 30.0, FIRE.position.y - 30.0, FIRE.size.x + 60.0, FIRE.size.y + 60.0), false,
		Color(1.0, 0.56, 0.16, 0.42 + 0.08 * sin(t * 11.0)))
	for i in 5:
		var px := FIRE.position.x + 42.0 + i * 24.0
		var k2 := 0.72 + 0.28 * sin(t * (7.0 + i * 1.3) + i * 2.1) * sin(t * 4.3 + i)
		var sway := sin(t * 6.1 + i * 2.3) * 4.0
		for layer in 3:
			var w2: float = [15.0, 10.0, 5.0][layer]
			var hgt: float = [46.0, 32.0, 17.0][layer] * k2 * (1.0 if i % 2 == 0 else 0.78)
			var col: Color = [Color(1.0, 0.48, 0.12, 0.95), Color(1.0, 0.8, 0.3), Color(1.0, 0.98, 0.84)][layer]
			n.draw_colored_polygon(PackedVector2Array([Vector2(px - w2, fy), Vector2(px - w2 * 0.7, fy - hgt * 0.45),
				Vector2(px + sway * (0.5 + 0.25 * layer), fy - hgt), Vector2(px + w2 * 0.7, fy - hgt * 0.45), Vector2(px + w2, fy)]), col)
	# the fire guard in front of the flames: brass bars (the fire is the room's, behind the play space)
	var guard := Color(0.55, 0.4, 0.16)
	n.draw_rect(Rect2(FIRE.position.x + 14.0, fy - 22.0, FIRE.size.x - 28.0, 3.0), guard)
	var gx := FIRE.position.x + 16.0
	while gx < FIRE.end.x - 14.0:
		n.draw_rect(Rect2(gx, fy - 22.0, 2.0, 26.0), guard)
		gx += 12.0
	# presents sliding down the gift chute (only a look: they are part of the wall)
	var a: Vector2 = CHUTE[0] + Vector2(18, -22)
	var b2: Vector2 = CHUTE[1] + Vector2(0, -12)
	var gifts := 5 if rich else 3
	for i in gifts:
		var u := fposmod(t * 0.16 + float(i) / gifts, 1.0)
		var p2 := a.lerp(b2, u * u * 0.4 + u * 0.6)
		n.draw_set_transform(p2, (b2 - a).angle() + PI, Vector2.ONE)
		_part(n, "gift_%d" % (i % 3), Vector2(-8, -8), Color(0.82, 0.8, 0.78, minf(1.0, minf(u, 1.0 - u) * 9.0)))
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------------ under the fighters
func _paint_under(n: Node2D) -> void:
	for i in lamps.size():                   # the lanterns: a chain, the lantern, its warm disc
		var p: Vector2 = lamps[i][0]
		var y := float(lamps[i][1])
		while y < p.y - 20.0:
			n.draw_rect(Rect2(p.x - 1.0, y, 2, 4), Color(0.17, 0.14, 0.14))
			y += 6.0
		n.draw_texture_rect(HALO, Rect2(p - Vector2(46, 44), Vector2(92, 92)), false, Color(1.0, 0.8, 0.4, 0.3 * _flicker(i)))
		_part(n, "lantern", p + Vector2(-16, -22))
	_paint_signals(n)

func _flicker(i: int) -> float:
	return 0.86 + 0.14 * sin(t * 11.0 + i * 1.9) * sin(t * 6.3 + i)

# How bright each of a mouth's two lamps is now (0..1): they blink in turn at the mouth
# the train comes out of while it whistles (faster near the end), at both while it runs.
func _lamp(mouth: int, which: int) -> float:
	var ph := _phase()
	if ph == Shop.IDLE:
		return 0.0
	var tt := _ticks()
	var from := 0 if _dir() > 0 else 1
	if ph == Shop.WARN and mouth != from:
		return 0.0
	var rate := 9.0 if ph == Shop.WARN and tt < Shop.WARN_T - 40 else 5.0
	return 1.0 if (int(tt / rate) % 2) == which else 0.0

# The signal: the lit lamps on the tunnels' arches, and the warning on the track itself:
# the strip the train will fill glows red, and arrows march along it the way the train
# goes. In the whistle: along the whole floor, faster and brighter near the end. While
# it runs: only ahead of it (behind it the track is safe again).
func _paint_signals(n: Node2D) -> void:
	var ph := _phase()
	if ph == Shop.IDLE:
		return
	for m in 2:
		for w in 2:
			if _lamp(m, w) > 0.5:
				_part(n, "lamp_on", Vector2(SIGNAL_X[m] - 10.0, SIGNAL_Y[w] - 10.0))
	var tt := _ticks()
	var d := _dir()
	var x0 := 0.0                            # the part of the track still in the train's way
	var x1 := 1920.0
	var k := 1.0
	if ph == Shop.RUN:
		var front_x := clampf(Shop.front_at(tt, d), 0.0, 1920.0)
		if d > 0:
			x0 = front_x
		else:
			x1 = front_x
	else:
		k = 0.55 + 0.45 * tt / Shop.WARN_T
	if x1 - x0 < 4.0:
		return
	var late: bool = ph == Shop.RUN or tt >= Shop.WARN_T - 40
	var pulse := 0.5 + 0.5 * sin(tt * (0.5 if late else 0.25))
	var top_y := FLOOR_Y - Shop.TRAIN_H
	var red := Color(1.0, 0.16, 0.1, (0.2 + 0.2 * pulse) * k)
	n.draw_polygon(PackedVector2Array([Vector2(x0, top_y - 10.0), Vector2(x1, top_y - 10.0), Vector2(x1, FLOOR_Y), Vector2(x0, FLOOR_Y)]),
		PackedColorArray([Color(red, 0.0), Color(red, 0.0), red, red]))
	n.draw_rect(Rect2(x0, FLOOR_Y - 5.0, x1 - x0, 5.0), Color(1.0, 0.3, 0.16, (0.45 + 0.4 * pulse) * k))
	var step := 96.0
	var x := fposmod(tt * 5.0 * d, step) - step
	var amber := Color(1.0, 0.82, 0.3, (0.55 + 0.4 * pulse) * k)
	while x < 1920.0 + step:
		if x > x0 + 12.0 and x < x1 - 12.0:  # an arrow head pointing the train's way
			var tip := Vector2(x + d * 11.0, FLOOR_Y - 21.0)
			n.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-d * 13.0, -13.0), tip + Vector2(-d * 22.0, -13.0),
				tip + Vector2(-d * 9.0, 0.0), tip + Vector2(-d * 22.0, 13.0), tip + Vector2(-d * 13.0, 13.0)]), amber)
		x += step

# ------------------------------------------------------------------ over the fighters: the train
func _paint_top(n: Node2D) -> void:
	var ph := _phase()
	var tt := _ticks()
	var d := _dir()
	if ph == Shop.WARN:
		# the whistle: puffs of steam out of the tunnel mouth, three toots
		var mx := 34.0 if d > 0 else 1886.0
		for k in 3:
			var born := 4.0 + k * 30.0
			var a := tt - born
			if a < 0.0 or a > 34.0:
				continue
			for j in 3:
				var u := (a - j * 3.0) / 30.0
				if u < 0.0 or u > 1.0:
					continue
				var p := Vector2(mx + d * (16.0 + 40.0 * u) + sin(u * 6.0 + j) * 4.0, FLOOR_Y - 96.0 - 44.0 * u - j * 5.0)
				var sz := 18.0 + 34.0 * u
				n.draw_texture_rect(HALO, Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(1, 1, 1, 0.85 * (1.0 - u)))
	elif ph == Shop.RUN:
		_paint_train(n, Shop.front_at(tt, d), d, tt)
	for b in bonks:                          # a bonk: a star that pops, and little stars flying off
		var u2: float = b[1] / 0.5
		var p2: Vector2 = b[0]
		var grow := 1.0 - pow(1.0 - minf(u2 * 2.2, 1.0), 3.0)
		_star(n, p2, 46.0 * grow, Color(1.0, 0.95, 0.5, 1.0 - u2))
		_star(n, p2, 26.0 * grow, Color(1, 1, 1, 1.0 - u2))
		for k in 5:
			var ang := -PI * 0.5 + (k - 2) * 0.55 + (0.3 if int(b[2]) == 1 else -0.3)
			_star(n, p2 + Vector2.from_angle(ang) * (30.0 + 90.0 * u2) + Vector2(0, 60.0 * u2 * u2), 9.0, Color(1.0, 0.9, 0.4, 1.0 - u2))

func _star(n: CanvasItem, at: Vector2, r: float, col: Color) -> void:
	if r < 1.0:
		return
	var pts := PackedVector2Array()
	for i in 10:
		pts.append(at + Vector2.from_angle(-PI * 0.5 + i * PI / 5.0) * (r if i % 2 == 0 else r * 0.45))
	n.draw_colored_polygon(pts, col)

# The train with its front at front_x, heading d: steam first (behind it), then each
# car with its wheels turning, a bar between cars.
func _paint_train(n: Node2D, front_x: float, d: int, tt: float) -> void:
	var puffs := 6 if rich else 4
	for i in puffs:                          # a puff every 6 ticks from the funnel: it stays where it came out, rises and thins
		var born := floorf(tt / 6.0) * 6.0 - i * 6.0
		if born < 0.0:
			continue
		var a := tt - born
		var fx := Shop.front_at(born, d) - d * 30.0
		if fx < -20.0 or fx > 1940.0:
			continue
		var p := Vector2(fx - d * a * 0.8 + sin(born * 1.3) * 3.0, FLOOR_Y - 80.0 - a * 2.0)
		var sz := 24.0 + a * 1.7
		n.draw_texture_rect(HALO, Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(1, 1, 1, 0.8 * (1.0 - a / (puffs * 6.0))))
	var x := front_x
	for car in CARS:
		var ln: float = car[1]
		var box_front: float = car[2]
		var r: Rect2 = PARTS[car[0]]
		n.draw_set_transform(Vector2(x, FLOOR_Y), 0.0, Vector2(d, 1))
		n.draw_rect(Rect2(-ln - CAR_GAP, -15.0, CAR_GAP + 2.0, 5.0), Color(0.14, 0.13, 0.17))   # the coupling behind it
		n.draw_texture_rect_region(PARTS_TEX, Rect2(Vector2(-box_front, -GROUND), r.size), r)
		for wh in car[3]:
			var wr: Rect2 = PARTS[wh[2]]
			var wx: float = x + d * (float(wh[0]) - box_front)
			n.draw_set_transform(Vector2(wx, FLOOR_Y - float(wh[1])), d * front_x / float(wh[1]), Vector2.ONE)
			n.draw_texture_rect_region(PARTS_TEX, Rect2(-wr.size * 0.5, wr.size), wr)
		x -= d * (ln + CAR_GAP)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------------ added light
func _paint_glow(n: Node2D) -> void:
	var fk := 0.9 + 0.1 * sin(t * 9.0) * sin(t * 5.3)
	n.draw_texture_rect(HALO, Rect2(FIRE.get_center() - Vector2(190, 150) * fk, Vector2(380, 300) * fk), false, Color(1.0, 0.5, 0.16, 0.16))
	var sk := 0.8 + 0.2 * sin(t * 2.1)
	n.draw_texture_rect(HALO, Rect2(star - Vector2(70, 70) * sk, Vector2(140, 140) * sk), false, Color(1.0, 0.86, 0.4, 0.22))
	for i in lamps.size():
		var p: Vector2 = lamps[i][0]
		n.draw_texture_rect(HALO, Rect2(p - Vector2(30, 30), Vector2(60, 60)), false, Color(1.0, 0.7, 0.3, 0.2 * _flicker(i)))
	var ph := _phase()
	if ph == Shop.IDLE:
		return
	for m in 2:                              # the signal's lamps
		for w in 2:
			var k := _lamp(m, w)
			if k > 0.5:
				var sp := Vector2(SIGNAL_X[m], SIGNAL_Y[w])
				n.draw_texture_rect(HALO, Rect2(sp - Vector2(48, 48), Vector2(96, 96)), false, Color(1.0, 0.2, 0.12, 0.6))
	if ph == Shop.RUN:                       # the engine's lamp, and a warm light along the train
		var d := _dir()
		var fx := Shop.front_at(_ticks(), d)
		n.draw_texture_rect(HALO, Rect2(Vector2(fx + d * 10.0, FLOOR_Y - 36.0) - Vector2(66, 48), Vector2(132, 96)), false, Color(1.0, 0.9, 0.5, 0.5))
		n.draw_texture_rect(HALO, Rect2(Vector2(fx - d * 120.0, FLOOR_Y - 30.0) - Vector2(180, 60), Vector2(360, 120)), false, Color(1.0, 0.8, 0.5, 0.14))

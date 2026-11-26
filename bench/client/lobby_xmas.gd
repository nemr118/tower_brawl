# p4.22 the Christmas dress's own shapes, shared by the lobby and its panels (the user:
# "snow drifting behind the panels and slowly piling on the seat cards, string lights
# that twinkle"): falling snow in three depths, a string of coloured lights whose bulbs
# take turns to glow (the same bulbs as the arenas' strings: client/snow_view.gd), a cap
# of snow lying on a flat top (the title's letters, a seat card, a plank), the sleigh
# that crosses the lobby's sky, and the snow that piles up on the seat cards (Piles).
# Who draws what: lobby_bg.gd (the backdrop), lobby_logo.gd (the title), lobby_cards.gd
# (the cards), each panel (lobby_settings.gd, lobby_champs.gd, lobby_names.gd,
# lobby_arenas.gd, lobby_howto.gd), winner_view.gd (the winner's screen).
# THE MEMORY RULE (p4.21): no words here, no boxes, no new pictures. Every shape is drawn
# in code or with the small soft dot the lobby already holds (assets/fx_halo.png).
# What is drawn again every frame is made of plain rects and that one dot (they go to
# the phone in one batch); the round shapes (the caps of snow) are drawn once and kept.
extends RefCounted

const XV = preload("res://client/christmas_view.gd")     # the sleigh's picture, the sparkle
const HALO := preload("res://assets/fx_halo.png")        # a soft white dot, 64 x 64
const BULBS := [Color(1.0, 0.25, 0.2), Color(0.25, 0.9, 0.35), Color(1.0, 0.85, 0.25), Color(0.3, 0.6, 1.0), Color(1.0, 0.45, 0.85)]   # snow_view.gd's
const SNOW := Color(0.96, 0.98, 1.0)
const SHADE := Color(0.62, 0.74, 0.93)                   # snow in its own shadow
const WIRE := Color(0.03, 0.12, 0.08)
# The snow's three depths: far (small, slow, faint), middle, near (big, quick, bright).
const FLAKE_SPEED := [26.0, 46.0, 82.0]                  # px a second, downwards
const FLAKE_SIZE := [3.0, 5.0, 15.0]                     # px across (the near ones are soft dots)
const FLAKE_ALPHA := [0.42, 0.62, 0.7]
const FLAKE_SWAY := [12.0, 20.0, 34.0]
const PILE_S := 60.0             # a seat card's snow is full after this long
# Where snow lies on each capital letter and digit of the lobby's heavy font (Noto Sans
# Condensed Black): [from, to] across the letter's own width (0..1), how far its left and
# right ends sink at size 150 (a round shoulder, a slope), how high that top is over the
# baseline (of the font's size: 0.72 is a capital's top). H has two tops, W three; L has
# its top and its foot. Measured from the font's own outlines (PIL, each glyph at 150 px:
# the runs of columns whose top is within 14 px of the glyph's highest point).
const SNOW_ON := {
	"A": [[0.27, 0.73, 12.0, 13.0, 0.72]],
	"B": [[0.11, 0.88, 0.0, 13.0, 0.72]],
	"C": [[0.22, 0.95, 14.0, 7.0, 0.727]],
	"D": [[0.11, 0.82, 0.0, 14.0, 0.72]],
	"E": [[0.14, 0.91, 0.0, 0.0, 0.72]],
	"F": [[0.14, 0.93, 0.0, 0.0, 0.72]],
	"G": [[0.2, 0.89, 14.0, 7.0, 0.727]],
	"H": [[0.1, 0.38, 0.0, 0.0, 0.72], [0.64, 0.9, 0.0, 0.0, 0.72]],
	"I": [[0.07, 0.93, 0.0, 0.0, 0.72]],
	"J": [[0.22, 0.78, 0.0, 0.0, 0.713]],
	"K": [[0.11, 0.42, 0.0, 0.0, 0.72], [0.61, 1.0, 14.0, 0.0, 0.72]],
	"L": [[0.14, 0.51, 0.0, 0.0, 0.72], [0.56, 0.92, 0.0, 0.0, 0.153]],
	"M": [[0.08, 0.39, 0.0, 14.0, 0.72], [0.62, 0.93, 13.0, 0.0, 0.72]],
	"N": [[0.09, 0.46, 0.0, 14.0, 0.72], [0.69, 0.91, 0.0, 0.0, 0.72]],
	"O": [[0.17, 0.82, 14.0, 14.0, 0.727]],
	"P": [[0.12, 0.89, 0.0, 13.0, 0.72]],
	"Q": [[0.17, 0.82, 14.0, 14.0, 0.733]],
	"R": [[0.11, 0.87, 0.0, 14.0, 0.72]],
	"S": [[0.12, 0.94, 14.0, 7.0, 0.727]],
	"T": [[0.04, 0.96, 0.0, 0.0, 0.72]],
	"U": [[0.09, 0.37, 0.0, 0.0, 0.713], [0.63, 0.9, 0.0, 0.0, 0.713]],
	"V": [[0.0, 0.36, 0.0, 12.0, 0.72], [0.66, 1.0, 11.0, 0.0, 0.72]],
	"W": [[0.01, 0.22, 0.0, 11.0, 0.72], [0.39, 0.61, 11.0, 12.0, 0.72], [0.77, 0.99, 13.0, 0.0, 0.72]],
	"X": [[0.02, 0.41, 0.0, 14.0, 0.72], [0.56, 0.96, 14.0, 0.0, 0.72]],
	"Y": [[0.0, 0.39, 0.0, 13.0, 0.72], [0.6, 0.99, 14.0, 0.0, 0.72]],
	"Z": [[0.06, 0.95, 0.0, 0.0, 0.72]],
	"0": [[0.17, 0.83, 13.0, 14.0, 0.727]],
	"1": [[0.31, 0.79, 14.0, 0.0, 0.72]],
	"2": [[0.08, 0.83, 14.0, 14.0, 0.727]],
	"3": [[0.06, 0.86, 10.0, 13.0, 0.727]],
	"4": [[0.41, 0.83, 13.0, 0.0, 0.72]],
	"5": [[0.14, 0.83, 8.0, 0.0, 0.713]],
	"6": [[0.23, 0.87, 14.0, 1.0, 0.727]],
	"7": [[0.08, 0.95, 0.0, 0.0, 0.72]],
	"8": [[0.13, 0.88, 14.0, 14.0, 0.727]],
	"9": [[0.13, 0.83, 13.0, 14.0, 0.727]],
	"!": [[0.14, 0.84, 0.0, 0.0, 0.72]],
	"?": [[0.0, 0.92, 10.0, 13.0, 0.727]],
	"&": [[0.15, 0.69, 13.0, 14.0, 0.727]],
}
const SLEIGH_EVERY := 26.0       # the sleigh crosses the sky this often
const SLEIGH_S := 7.5            # and takes this long to cross

# ------------------------------------------------------------------ falling snow
# n flakes over `area`, in three depths; each drifts down, sways and comes round again.
# t: a clock in seconds; alpha: how strong (a panel's snow is fainter than the lobby's).
# The small ones are plain squares, the near ones soft dots: two batches.
static func snow(c: CanvasItem, t: float, area: Rect2, n: int, alpha: float) -> void:
	var w := area.size.x + 80.0
	var h := area.size.y + 80.0
	for pass_i in 2:
		for i in n:
			var d := i % 3
			if (d == 2) != (pass_i == 1):
				continue
			var sp: float = FLAKE_SPEED[d] * (0.82 + (i % 7) * 0.06)
			var sway: float = FLAKE_SWAY[d]
			var x := area.position.x + fposmod(i * 197.3 + sin(t * (0.5 + d * 0.2) + i * 1.7) * sway + t * (5.0 + d * 8.0), w) - 40.0
			var y := area.position.y + fposmod(i * 131.7 + t * sp, h) - 40.0
			var s: float = FLAKE_SIZE[d] * (0.8 + (i % 4) * 0.13)
			var a: float = FLAKE_ALPHA[d] * alpha
			if d == 2:
				c.draw_texture_rect(HALO, Rect2(x - s * 0.5, y - s * 0.5, s, s), false, Color(1, 1, 1, a))
			else:
				c.draw_rect(Rect2(x - s * 0.5, y - s * 0.5, s, s), Color(SNOW, a))

# ------------------------------------------------------------------ a string of lights
# A string from a to b that hangs `sag` px in its middle, a bulb about every `gap` px.
# Each bulb takes its turn to glow brighter (t: a clock; phase: so two strings differ).
# part: ALL, or the backdrop's two layers: STRING (the wire and the bulbs) and GLOW (the
# soft light round each bulb, which the backdrop adds as light on its own layer).
# wire: the wire's colour (a panel's is lighter: the dark one cannot be seen on a dark panel).
enum { ALL, STRING, GLOW }
static func lights(c: CanvasItem, t: float, a: Vector2, b: Vector2, sag: float, gap: float, phase: int, alpha: float = 1.0, part: int = ALL,
		wire: Color = WIRE) -> void:
	var n := clampi(int(a.distance_to(b) / gap), 3, 60)
	var pts := PackedVector2Array()
	for i in n + 1:
		var k := float(i) / n
		pts.append(a.lerp(b, k) + Vector2(0, sag * sin(k * PI)))
	if part != GLOW:
		for i in n:                   # the wire (plain lines: one batch)
			c.draw_line(pts[i], pts[i + 1], Color(wire, alpha), 3.0)
		for i in range(1, n):         # each bulb's cap on the wire
			c.draw_rect(Rect2(pts[i].x - 3.0, pts[i].y - 1.0, 6.0, 6.0), Color(wire, alpha))
	if part != STRING:
		_bulbs(c, t, pts, phase, alpha, true)
	if part != GLOW:
		_bulbs(c, t, pts, phase, alpha, false)

# The bulbs of one string: their soft light (halo true), or the bulbs themselves.
static func _bulbs(c: CanvasItem, t: float, pts: PackedVector2Array, phase: int, alpha: float, halo: bool) -> void:
	for i in range(1, pts.size() - 1):
		var col: Color = BULBS[(i + phase * 2) % BULBS.size()]
		var on := 0.55 + 0.45 * sin(t * 2.6 + i * 1.9 + phase)
		var p := pts[i] + Vector2(0, 9.0)
		if halo:
			c.draw_texture_rect(HALO, Rect2(p.x - 24.0, p.y - 24.0, 48.0, 48.0), false, Color(col.r, col.g, col.b, 0.42 * on * on * alpha))
		else:
			c.draw_texture_rect(HALO, Rect2(p.x - 10.0, p.y - 10.0, 20.0, 20.0), false, Color(col.r * on, col.g * on, col.b * on, alpha))
			c.draw_texture_rect(HALO, Rect2(p.x - 8.0, p.y - 8.0, 16.0, 16.0), false, Color(col.lerp(Color.WHITE, 0.35 * on), alpha))
			c.draw_texture_rect(HALO, Rect2(p.x - 4.0, p.y - 5.0, 7.0, 7.0), false, Color(1, 1, 1, 0.75 * on * alpha))

# Lights across a whole screen's top, in loops from x0 to x1 (the lobby's backdrop, and
# the panels with no card of their own: PICK AN ARENA, HOW TO PLAY, WHO ARE YOU?).
static func top_lights(c: CanvasItem, t: float, x0: float, x1: float, y: float, alpha: float = 1.0, part: int = ALL) -> void:
	var n := maxi(2, int(round((x1 - x0) / 470.0)))
	var w := (x1 - x0) / n
	for i in n:
		lights(c, t, Vector2(x0 + i * w, y - 6.0), Vector2(x0 + (i + 1) * w, y - 6.0), 30.0 + (i % 2) * 10.0, 46.0, i, alpha, part)

# Lights along the top edge of a panel's card (SETTINGS, the MENU, TONIGHT'S CHAMPIONS):
# small loops from corner to corner, the bulbs hanging just over the edge. Their wire is a
# pine green that shows on the dark card, so the bulbs read as one string, not loose dots.
const PANEL_WIRE := Color(0.16, 0.36, 0.24)
static func card_lights(c: CanvasItem, t: float, card: Rect2, alpha: float = 1.0) -> void:
	var x0 := card.position.x + 26.0
	var x1 := card.end.x - 26.0
	var n := maxi(2, int(round((x1 - x0) / 240.0)))
	var w := (x1 - x0) / n
	for i in n:
		lights(c, t, Vector2(x0 + i * w, card.position.y + 1.0), Vector2(x0 + (i + 1) * w, card.position.y + 1.0), 13.0, 40.0, i, alpha, ALL, PANEL_WIRE)

# What lies behind a panel in the dress: the snow still drifts (fainter than the lobby's,
# so the panel's words stay clear). The panel draws this right after its dark layer.
static func behind_panel(c: CanvasItem, t: float, alpha: float = 1.0) -> void:
	snow(c, t + 40.0, Rect2(-420, 0, 2760, 1080), 66, 0.62 * alpha)

# ------------------------------------------------------------------ a cap of snow
# Snow lying on a flat top from x0 to x1 (y: the top's own line): `thick` px deep at its
# lumps, thin at its two ends, a little over each end. sd: which lumps (so two caps
# differ). edge: a dark line round it (the title's own edge colour); see-through: none.
# droop_l, droop_r: how far an end sinks (a round letter's shoulder).
# These are round shapes: draw them once and keep them (a Control that is not redrawn).
static func cap(c: CanvasItem, x0: float, x1: float, y: float, thick: float, sd: int, edge: Color = Color(0, 0, 0, 0),
		droop_l: float = 0.0, droop_r: float = 0.0) -> void:
	if x1 - x0 < 6.0 or thick < 1.0:
		return
	var n := maxi(5, int((x1 - x0) / 6.0))
	var top := PackedVector2Array()
	var low := PackedVector2Array()
	var low2 := PackedVector2Array()
	for i in n + 1:
		var k := float(i) / n
		var x := lerpf(x0 - 3.0, x1 + 3.0, k)
		var ends := pow(sin(k * PI), 0.4)                       # 0 at the two ends, 1 along the middle
		var lump := 0.64 + 0.22 * sin(k * 8.0 + sd * 1.7) + 0.14 * sin(k * 19.0 + sd * 2.9)
		var droop := droop_l * pow(1.0 - k, 3.0) + droop_r * pow(k, 3.0)
		var drip := maxf(0.0, sin(k * 11.0 + sd * 2.3)) * ends * minf(4.0, thick * 0.3)    # it hangs over the edge here and there
		top.append(Vector2(x, y + droop - thick * ends * lump - 1.0))
		low.append(Vector2(x, y + droop + 1.5 + drip))
		low2.append(Vector2(x, y + droop + 4.5 + drip * 1.6))
	var body := top.duplicate()
	var shade := top.duplicate()
	for i in range(n, -1, -1):
		body.append(low[i])
		shade.append(low2[i])
	if edge.a > 0.0:
		var loop := shade.duplicate()
		loop.append(shade[0])
		c.draw_polyline(loop, edge, 7.0, true)
	c.draw_colored_polygon(shade, SHADE)
	c.draw_colored_polygon(body, SNOW)

# Snow on every letter of a word drawn in the lobby's heavy font f at `size`, its left end
# at x and its baseline at base (the title; a match's big banner). Returns where each cap
# lies, [x0, x1, y] (the title's sparkles sit on them). c null: nothing is drawn, only
# the places come back. A letter the table does not know gets no snow.
static func word_caps(c: CanvasItem, f: Font, word: String, x: float, base: float, size: int, edge: Color, sd: int = 0) -> Array:
	var out: Array = []
	var k := size / 150.0
	for i in word.length():
		var ch := word.substr(i, 1)
		if not SNOW_ON.has(ch):
			continue
		var lx := x + f.get_string_size(word.substr(0, i), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var lw := f.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		for sp in SNOW_ON[ch]:
			var x0 := lx + lw * float(sp[0])
			var x1 := lx + lw * float(sp[1])
			var y := base - size * float(sp[4])
			if c != null:
				cap(c, x0, x1, y, size * (0.1 if float(sp[4]) > 0.5 else 0.06), sd + out.size() * 5 + 2, edge, float(sp[2]) * k, float(sp[3]) * k)
			out.append([x0, x1, y])
	return out

# ------------------------------------------------------------------ the sleigh
# The sleigh crosses a sky w wide every SLEIGH_EVERY seconds (the first time a few seconds
# in), from the left to the right, rising and dipping, sparkles behind it. y: its height;
# s: its size (1: 320 px long, as over an arena).
static func sleigh(c: CanvasItem, t: float, w: float, y: float, s: float, alpha: float) -> void:
	var k := fposmod(t + SLEIGH_EVERY - 5.0, SLEIGH_EVERY) / SLEIGH_S
	if k > 1.0 or alpha <= 0.0:
		return
	var x := lerpf(-200.0 * s, w + 200.0 * s, k)
	var yy := y + sin(k * PI) * -46.0 + sin(t * 2.2) * 8.0
	for i in 6:      # sparkles behind it
		var q := fposmod(t * 1.4 + i * 0.17, 1.0)
		XV.sparkle(c, Vector2(x - (118.0 + q * 130.0) * s, yy + (14.0 + sin(i * 1.7) * 22.0) * s), 10.0 * s * (1.0 - q), Color(1.0, 0.95, 0.6, (1.0 - q) * alpha))
	c.draw_set_transform(Vector2(x, yy), sin(t * 2.2 + 1.0) * 0.04 - 0.05, Vector2.ONE * s)
	c.draw_texture_rect(XV.SLEIGH, Rect2(-160, -80, 320, 160), false, Color(1, 1, 1, alpha))
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ------------------------------------------------------------------ the seat cards' snow
# One card's pile: a small node that lies on the card's top edge. It is drawn again only
# when the pile has grown enough to see, or while a puff flies. lobby_cards.gd moves it
# with its card, which costs nothing (a Node2D: moving one does not draw it again).
class Pile extends Node2D:
	var xm = load("res://client/lobby_xmas.gd")   # this file's own functions (a class in a file cannot call them by name)
	var amount := 0.0            # 0..1: how much snow lies on the card
	var shown := -1.0            # the amount it was last drawn at
	var w := 200.0               # the card's width
	var sd := 0                # which lumps its snow has
	var puff: Array = []         # [place, speed, age, size]: the snow that was knocked off

	# The card reacted: the pile falls off in a puff.
	func knock() -> void:
		if amount < 0.04:
			amount = 0.0
			return
		var n := 6 + int(amount * 10.0)
		for k in n:
			var x := (float(k) + randf()) / n * (w - 30.0) - (w - 30.0) * 0.5
			puff.append([Vector2(x, -4.0 - randf() * 8.0 * amount), Vector2(x * 1.6 + randf_range(-40.0, 40.0), -110.0 - randf() * 120.0), 0.0, 5.0 + randf() * 7.0 * amount])
		amount = 0.0
		queue_redraw()

	func step(delta: float, fill_s: float) -> void:
		amount = minf(1.0, amount + delta / fill_s)
		if not puff.is_empty():
			for p in puff:
				p[2] += delta
				p[0] += p[1] * delta
				p[1].x *= 1.0 - 1.5 * delta
				p[1].y += 620.0 * delta
			while not puff.is_empty() and puff[0][2] > 0.75:
				puff.pop_front()
			queue_redraw()
		elif absf(amount - shown) > 0.035:
			queue_redraw()

	func _draw() -> void:
		shown = amount
		if amount >= 0.04:
			xm.cap(self, -w * 0.5 + 12.0, w * 0.5 - 12.0, 0.0, 3.0 + 13.0 * pow(amount, 0.8), sd)
		for p in puff:
			var a := clampf(1.0 - float(p[2]) / 0.75, 0.0, 1.0)
			var s: float = p[3]
			draw_rect(Rect2(p[0] - Vector2(s, s) * 0.5, Vector2(s, s)), Color(xm.SNOW, a))

# The eight cards' piles. lobby_cards.gd makes one of these in the Christmas dress, calls
# step() every frame and place() for each card. A card "reacts" when its pop or its dip
# starts again (a person joins or leaves, a bot's seat comes or goes, a team changes, a
# tap on your own card): this only watches those two clocks, so the cards' own code
# needs no change.
class Piles extends RefCounted:
	var list: Array = []         # a Pile for each card
	var seen: Array = []         # each card's [pop, dip] clocks as last seen
	var fill_s := PILE_S
	var shown := true

	# host: the cards' node (the piles go in under its fighters and words); w: a card's width.
	func _init(host: Control, n: int, w: float) -> void:
		for i in n:
			var p := Pile.new()
			p.w = w
			p.sd = i * 3 + 1
			host.add_child(p)
			host.move_child(p, i)
			list.append(p)
			seen.append([9.0, 9.0])

	# cards: lobby_cards.gd's cards (each has "pop" and "dip": seconds since each began).
	func step(delta: float, cards: Array) -> void:
		for i in list.size():
			var c: Dictionary = cards[i]
			var pop := float(c["pop"])
			var dip := float(c["dip"])
			if pop < float(seen[i][0]) or dip < float(seen[i][1]):
				list[i].knock()
			seen[i][0] = pop
			seen[i][1] = dip
			list[i].step(delta, fill_s)

	# Card i is drawn with its middle at mid and at size s; its top edge is half_h above its middle.
	func place(i: int, mid: Vector2, s: float, half_h: float) -> void:
		var p: Pile = list[i]
		p.position = mid + Vector2(0, -half_h) * s
		p.scale = Vector2.ONE * s

	# on false: the dress came off: every pile goes (nothing falls) and stays hidden.
	func show(on: bool) -> void:
		if on == shown:
			return
		shown = on
		for p in list:
			p.visible = on
			if not on:
				p.amount = 0.0
				p.puff.clear()
				p.queue_redraw()

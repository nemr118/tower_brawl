# p4.22 winter on a castle arena in the Christmas season (world.gd puts it over the
# blocks, under the fighters): a cap of snow on every floor and ledge you can stand on
# (a bright top edge: it also shows where to stand), icicles under the ledges' ends, a
# wreath round each torch, and strings of coloured lights under the ceiling that
# twinkle. The still parts are drawn once (build); only the lights are drawn again,
# 6 times a second.
extends Node2D

const WREATH := preload("res://assets/christmas_wreath.png")
const BOOST := 1.9               # the night darkens this layer (world.gd's CanvasModulate): colours over 1 come out bright
const BULBS := [Color(1.0, 0.25, 0.2), Color(0.25, 0.9, 0.35), Color(1.0, 0.85, 0.25), Color(0.3, 0.6, 1.0), Color(1.0, 0.45, 0.85)]
const HZ := 6.0

var runs: Array = []             # [x0, x1, y]: the top of a floor or a ledge, in px
var icicles: Array = []          # [x, y, long]
var wreaths: Array = []          # the torches' places
var swags: Array = []            # [from, to]: a string of lights between two points
var lights: Node2D
var t := 0.0
var acc := 0.0
var flash_t := 0.0               # a knockout: every bulb burns bright for this long more
const FLASH_S := 0.45

class _Lights extends Node2D:
	var sv
	func _draw() -> void:
		sv._draw_lights(self)

func _init() -> void:
	lights = _Lights.new()
	lights.sv = self
	add_child(lights)
	visible = false

# The arena's snow (level: sim/level.gd; null: none, the layer hides). torches: where the wreaths go.
func build(level, torches: Array) -> void:
	runs.clear()
	icicles.clear()
	wreaths.clear()
	swags.clear()
	visible = level != null
	if level == null:
		queue_redraw()
		return
	for cy in range(1, level.ROWS):
		var cx := 0
		while cx < level.COLS:
			if level.cell(cx, cy) != 0 and level.cell(cx, cy - 1) == 0:
				var x0 := cx
				while cx < level.COLS and level.cell(cx, cy) != 0 and level.cell(cx, cy - 1) == 0:
					cx += 1
				runs.append([x0 * 30.0, cx * 30.0, cy * 30.0])
				# a string of lights under a long ledge, where the row under it is open from end to end
				if cx - x0 >= 5 and cy + 1 < level.ROWS:
					var open := true
					for ux in range(x0, cx):
						if level.cell(ux, cy + 1) != 0:
							open = false
							break
					if open:
						var under: float = cy * 30.0 + (31.0 if level.cell(x0, cy) == 1 else 11.0)
						swags.append([Vector2(x0 * 30.0 + 8.0, under), Vector2(cx * 30.0 - 8.0, under)])
				# icicles under a ledge's two ends, where there is air below
				for ex in [x0, cx - 1]:
					if cy + 1 < level.ROWS and level.cell(ex, cy + 1) == 0 and (ex * 7 + cy * 3) % 3 != 0:
						icicles.append([ex * 30.0 + 15.0, cy * 30.0 + (30.0 if level.cell(ex, cy) == 1 else 8.0), 10.0 + (ex * 5 + cy) % 3 * 5.0])
			else:
				cx += 1
	for tp in torches:
		wreaths.append(Vector2(tp))
	queue_redraw()
	lights.queue_redraw()

# A knockout somewhere in the arena: the lights all flash.
func flash() -> void:
	if visible:
		flash_t = FLASH_S
		lights.queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	acc += delta
	if flash_t > 0.0:
		flash_t = maxf(0.0, flash_t - delta)
		lights.queue_redraw()        # (smooth while it fades)
	elif acc >= 1.0 / HZ:
		acc = 0.0
		lights.queue_redraw()

func _draw() -> void:
	var white := Color(0.96 * BOOST, 0.98 * BOOST, 1.0 * BOOST)
	var shade := Color(0.6 * BOOST, 0.72 * BOOST, 0.92 * BOOST)
	for ic in icicles:
		var x: float = ic[0]
		var y: float = ic[1]
		var l: float = ic[2]
		draw_colored_polygon(PackedVector2Array([Vector2(x - 4.0, y), Vector2(x + 4.0, y), Vector2(x, y + l)]), Color(shade, 0.9))
		draw_line(Vector2(x - 1.5, y), Vector2(x - 0.5, y + l * 0.7), Color(white, 0.9), 1.5)
	for r in runs:
		var x0: float = r[0]
		var x1: float = r[1]
		var y: float = r[2]
		draw_rect(Rect2(x0 - 2.0, y - 1.0, x1 - x0 + 4.0, 6.0), shade)           # the cap's shaded underside
		draw_rect(Rect2(x0 - 3.0, y - 6.0, x1 - x0 + 6.0, 7.0), white)           # the cap
		var n := int((x1 - x0) / 30.0)
		for i in n:                                                              # soft lumps along it
			var lx := x0 + 15.0 + i * 30.0 + ((i * 7 + int(y)) % 5 - 2) * 3.0
			draw_circle(Vector2(lx, y - 6.0), 6.0 + ((i * 3 + int(y / 30.0)) % 3) * 1.5, white)
		draw_circle(Vector2(x0 - 2.0, y - 2.5), 4.5, white)                      # rounded ends
		draw_circle(Vector2(x1 + 2.0, y - 2.5), 4.5, white)
	for w in wreaths:
		draw_texture_rect(WREATH, Rect2(Vector2(w) + Vector2(-38, -44), Vector2(76, 76)), false, Color(BOOST, BOOST, BOOST))

# A string's bulbs hang in a curve; each takes its turn to glow brighter.
func _draw_lights(ci: CanvasItem) -> void:
	for si in swags.size():
		var a: Vector2 = swags[si][0]
		var b: Vector2 = swags[si][1]
		var n := clampi(int(a.distance_to(b) / 28.0), 4, 24)      # a bulb every 28 px or so
		var pts := PackedVector2Array()
		for i in n + 1:
			var k := float(i) / n
			pts.append(a.lerp(b, k) + Vector2(0, 12.0 * sin(k * PI)))
		ci.draw_polyline(pts, Color(0.08 * BOOST, 0.14 * BOOST, 0.1 * BOOST), 2.0)
		for i in range(1, n):
			var col: Color = BULBS[(i + si * 2) % BULBS.size()]
			var on := 0.55 + 0.45 * sin(t * 2.6 + i * 1.9 + si)
			var fk := flash_t / FLASH_S
			if fk > 0.0:              # the flash: brighter, whiter, a wider glow
				on = lerpf(on, 1.6, fk)
				col = col.lerp(Color(1.0, 0.97, 0.85), fk * 0.6)
				ci.draw_circle(pts[i] + Vector2(0, 5), 16.0, Color(col.r * BOOST, col.g * BOOST, col.b * BOOST, 0.22 * fk))
			ci.draw_circle(pts[i] + Vector2(0, 5), 9.0, Color(col.r * BOOST, col.g * BOOST, col.b * BOOST, 0.16 * on))
			ci.draw_circle(pts[i] + Vector2(0, 5), 4.2, Color(col.r * BOOST * on, col.g * BOOST * on, col.b * BOOST * on))

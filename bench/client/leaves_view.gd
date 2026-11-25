# p4.18 autumn leaves falling over a castle arena in the Harvest season (world.gd puts
# it behind the blocks, in front of the backdrop): orange, red and gold, drifting down,
# swaying and turning. LOW has a few, HIGH the most. Drawn again 30 times a second.
extends Node2D

const HV = preload("res://client/harvest_view.gd")
const BOOST := 2.3               # the night darkens this layer (world.gd's CanvasModulate): colours over 1 come out right
const HZ := 30.0

var n := 0
var snow := false                # p4.22: the Christmas season: snowflakes fall, not leaves
var t := 0.0
var acc := 0.0

func set_count(c: int) -> void:
	n = c
	visible = c > 0
	queue_redraw()

func _process(delta: float) -> void:
	if not visible:
		return
	t += delta
	acc += delta
	if acc >= 1.0 / HZ:
		acc = 0.0
		queue_redraw()

func _draw() -> void:
	if snow:        # p4.22: flakes of three sizes, drifting down slowly, swaying
		for i in n:
			var fall := 26.0 + (i % 5) * 9.0
			var fx := fposmod(i * 263.0 + sin(t * 0.6 + i * 1.7) * 36.0 + t * (4.0 + i % 3 * 3.0), 2000.0) - 40.0
			var fy := fposmod(i * 149.0 + t * fall, 1160.0) - 40.0
			draw_circle(Vector2(fx, fy), 2.0 + (i % 3) * 1.2, Color(BOOST, BOOST, BOOST, 0.55 + 0.1 * (i % 4)))
		return
	for i in n:
		var sp := 34.0 + (i % 5) * 12.0
		var x := fposmod(i * 263.0 + sin(t * 0.7 + i * 1.7) * 50.0 + t * (8.0 + i % 3 * 5.0), 2000.0) - 40.0
		var y := fposmod(i * 149.0 + t * sp, 1160.0) - 40.0
		var col: Color = HV.LEAF_COLS[i % HV.LEAF_COLS.size()]
		HV.leaf(self, Vector2(x, y), 0.9 + (i % 4) * 0.2, t * (0.8 + (i % 3) * 0.5) + i, sin(t * 2.0 + i),
			Color(col.r * BOOST, col.g * BOOST, col.b * BOOST, 0.8))

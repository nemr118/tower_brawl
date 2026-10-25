# p4.11 the arena's shapes, easy to read (the user: "the contrast between platform,
# bridge, solid ground and background is too little... you end up running into things
# you didn't realize was there. Keep a high quality look"). Over the blocks, under the
# fighters, in the threats layer so the night never darkens it, on every look: a lit
# warm edge along every block top you can stand on, a fainter cool edge along the
# blocks' sides and undersides (walls you bump into), and on every ledge (a thin
# platform you jump up through, the bridges) a bright amber plank line with small posts
# under it. Built once for each arena (the runs of edge are merged into long lines).
extends Node2D

const C := 30                   # the grid (sim/level.gd CELL)
var tops := PackedVector2Array()     # pairs: a block's top you can stand on
var sides := PackedVector2Array()    # a block's sides and undersides
var ledges := PackedVector2Array()   # a ledge's top
var posts := PackedVector2Array()    # little posts under the ledges
var halloween := false

func build(level) -> void:
	tops.clear()
	sides.clear()
	ledges.clear()
	posts.clear()
	halloween = level.theme == "halloween"
	var rows: int = level.ROWS
	var cols: int = level.COLS
	# runs along each row: a block's top (no block above), its underside (no block below), a ledge
	for cy in rows:
		var run_top := -1
		var run_bot := -1
		var run_ledge := -1
		for cx in cols + 1:
			var c: int = level.cell(cx, cy) if cx < cols else 0
			var top_here: bool = c == 1 and level.cell(cx, cy - 1) != 1
			var bot_here: bool = c == 1 and level.cell(cx, cy + 1) != 1
			var ledge_here: bool = c == 2
			run_top = _run(tops, run_top, top_here, cx, cy * C)
			run_bot = _run(sides, run_bot, bot_here, cx, (cy + 1) * C)
			if ledge_here and run_ledge < 0:
				run_ledge = cx
			elif not ledge_here and run_ledge >= 0:
				ledges.append_array([Vector2(run_ledge * C, cy * C + 2), Vector2(cx * C, cy * C + 2)])
				for px in range(run_ledge, cx):
					if (px - run_ledge) % 3 == 1:
						posts.append_array([Vector2(px * C + 15, cy * C + 5), Vector2(px * C + 15, cy * C + 14)])
				run_ledge = -1
	# runs down each column: a block's left side (no block left of it), its right side
	for cx in cols:
		var run_l := -1
		var run_r := -1
		for cy in rows + 1:
			var c: int = level.cell(cx, cy) if cy < rows else 0
			var l_here: bool = c == 1 and level.cell(cx - 1, cy) != 1
			var r_here: bool = c == 1 and level.cell(cx + 1, cy) != 1
			if l_here and run_l < 0:
				run_l = cy
			elif not l_here and run_l >= 0:
				sides.append_array([Vector2(cx * C, run_l * C), Vector2(cx * C, cy * C)])
				run_l = -1
			if r_here and run_r < 0:
				run_r = cy
			elif not r_here and run_r >= 0:
				sides.append_array([Vector2((cx + 1) * C, run_r * C), Vector2((cx + 1) * C, cy * C)])
				run_r = -1
	queue_redraw()

# One step along a row: a run of edge starts, goes on, or ends (and is kept as a line).
func _run(out: PackedVector2Array, start: int, here: bool, cx: int, y: int) -> int:
	if here and start < 0:
		return cx
	if not here and start >= 0:
		out.append_array([Vector2(start * C, y), Vector2(cx * C, y)])
		return -1
	return start

func _draw() -> void:
	var top_col := Color(1.0, 0.72, 0.42) if halloween else Color(1.0, 0.88, 0.6)
	var side_col := Color(0.72, 0.6, 1.0, 0.42) if halloween else Color(0.62, 0.72, 1.0, 0.42)
	var ledge_col := Color(1.0, 0.62, 0.22) if halloween else Color(1.0, 0.74, 0.32)
	if sides.size() > 0:
		draw_multiline(sides, side_col, 2.0)
	if tops.size() > 0:
		draw_multiline(tops, Color(top_col, 0.22), 8.0)    # a soft glow under the edge
		draw_multiline(tops, Color(top_col, 0.9), 2.5)
	if posts.size() > 0:
		draw_multiline(posts, Color(ledge_col.darkened(0.25), 0.8), 3.0)
	if ledges.size() > 0:
		draw_multiline(ledges, Color(ledge_col, 0.28), 9.0)
		draw_multiline(ledges, Color(ledge_col, 0.95), 3.5)

# p4.11 the arena's shapes, easy to read and still detailed (the user: "the contrast
# between platform, bridge, solid ground and background is too little"; then, after a
# first try with drawn lines: "the edges remove a lot of the detail... Is there a way we
# could both increase the visibility and add detail?"). So nothing is drawn over the
# tiles; the shapes stand out by depth and light instead, as on a lit stage:
#   behind the tiles (this node, in the world before the tile layers): a soft dark halo
#   around every block and a shadow under every ledge, on the backdrop only, so the play
#   space lifts off the scenery and the tiles keep every pixel;
#   on the glow layer (added light, `light`): a faint warm light falling on each block
#   top you can stand on, a fainter cool light on the walls, and a warm glint on the
#   ledges and bridges. Added light keeps the stone's texture: brighter, not covered.
# Built once for each arena (the runs of edge merged into long pieces).
extends Node2D

const C := 30                   # the grid (sim/level.gd CELL)
var blocks: Array = []          # Rect2: the runs of block along each row
var ledge_runs: Array = []      # Rect2: the runs of ledge
var tops: Array = []            # [x0, x1, y]: block tops you can stand on
var walls: Array = []           # [x, y0, y1, dir]: a block's left (-1) or right (1) side
var halloween := false
var light := _Light.new()

class _Light extends Node2D:
	var ev
	func _draw() -> void:
		if ev != null:
			ev._paint_light(self)

func setup(glow_parent: Node2D, add_mat: Material) -> void:
	light.ev = self
	light.material = add_mat
	glow_parent.add_child(light)

func build(level) -> void:
	blocks.clear()
	ledge_runs.clear()
	tops.clear()
	walls.clear()
	halloween = level.theme == "halloween"
	var rows: int = level.ROWS
	var cols: int = level.COLS
	for cy in rows:
		var rb := -1
		var rl := -1
		var rt := -1
		for cx in cols + 1:
			var c: int = level.cell(cx, cy) if cx < cols else 0
			var top_here: bool = c == 1 and level.cell(cx, cy - 1) != 1
			if c == 1 and rb < 0:
				rb = cx
			elif c != 1 and rb >= 0:
				blocks.append(Rect2(rb * C, cy * C, (cx - rb) * C, C))
				rb = -1
			if c == 2 and rl < 0:
				rl = cx
			elif c != 2 and rl >= 0:
				ledge_runs.append(Rect2(rl * C, cy * C, (cx - rl) * C, C))
				rl = -1
			if top_here and rt < 0:
				rt = cx
			elif not top_here and rt >= 0:
				tops.append([rt * C, cx * C, cy * C])
				rt = -1
	for cx in cols:
		var rlft := -1
		var rrgt := -1
		for cy in rows + 1:
			var c: int = level.cell(cx, cy) if cy < rows else 0
			var l_here: bool = c == 1 and level.cell(cx - 1, cy) != 1
			var r_here: bool = c == 1 and level.cell(cx + 1, cy) != 1
			if l_here and rlft < 0:
				rlft = cy
			elif not l_here and rlft >= 0:
				walls.append([cx * C, rlft * C, cy * C, -1])
				rlft = -1
			if r_here and rrgt < 0:
				rrgt = cy
			elif not r_here and rrgt >= 0:
				walls.append([(cx + 1) * C, rrgt * C, cy * C, 1])
				rrgt = -1
	queue_redraw()
	light.queue_redraw()

# Behind the tiles: what shows is only the fringe around the shapes, on the backdrop.
func _draw() -> void:
	var shade := Color(0.02, 0.01, 0.05) if halloween else Color(0.01, 0.02, 0.05)
	for r in blocks:
		draw_rect(r.grow(11).grow_individual(0, 0, 0, 4), Color(shade, 0.18))   # the soft outer halo
		draw_rect(r.grow(6), Color(shade, 0.32))
		draw_rect(r.grow(2), Color(shade, 0.5))
	for r in ledge_runs:
		var plank := Rect2(r.position.x, r.position.y, r.size.x, 12.0)
		draw_rect(Rect2(plank.position + Vector2(-3, 8), Vector2(plank.size.x + 6, 16)), Color(shade, 0.4))   # its shadow below
		draw_rect(plank.grow(3), Color(shade, 0.42))

# On the glow layer (added): light that brightens the tiles without covering them.
func _paint_light(n: Node2D) -> void:
	var warm := Color(1.0, 0.62, 0.3) if halloween else Color(1.0, 0.82, 0.55)
	var cool := Color(0.62, 0.45, 1.0) if halloween else Color(0.5, 0.62, 1.0)
	for t in tops:   # light falling on a top you can stand on, fading down the block's face
		var x0: float = t[0]
		var x1: float = t[1]
		var y: float = t[2]
		n.draw_polygon(PackedVector2Array([Vector2(x0, y - 2), Vector2(x1, y - 2), Vector2(x1, y + 12), Vector2(x0, y + 12)]),
			PackedColorArray([Color(warm, 0.26), Color(warm, 0.26), Color(warm, 0.0), Color(warm, 0.0)]))
	for w in walls:  # a faint cool light down each side
		var x: float = w[0]
		var d: float = w[3]
		n.draw_polygon(PackedVector2Array([Vector2(x, w[1]), Vector2(x - d * 6.0, w[1]), Vector2(x - d * 6.0, w[2]), Vector2(x, w[2])]),
			PackedColorArray([Color(cool, 0.09), Color(cool, 0.0), Color(cool, 0.0), Color(cool, 0.09)]))
	for r in ledge_runs:   # a warm glint along each ledge's top
		var y: float = r.position.y
		n.draw_polygon(PackedVector2Array([Vector2(r.position.x, y), Vector2(r.end.x, y), Vector2(r.end.x, y + 7), Vector2(r.position.x, y + 7)]),
			PackedColorArray([Color(warm, 0.32), Color(warm, 0.32), Color(warm, 0.0), Color(warm, 0.0)]))

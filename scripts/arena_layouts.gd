extends RefCounted
# ==============================================================================
# The arena layouts (v0.1.3, the tower). Design: docs/reference/arena-tower.md.
# ==============================================================================
# One layout = a name, a size, and a list of pieces. A piece is a rectangle
# given by its top-left corner, its width and its height, in arena pixels
# (x 0..640 is the screen, y 0 is the top of the tower). Kinds:
#   wall   solid on every side (the outer walls, the ceiling and the floor)
#   bump   a piece of wall that sticks into the room; solid, a ledge on top
#   ledge  one-way: a fighter jumps up through it and drops through with
#          down + jump; "spawn": true marks a round-start spot
# arena.gd builds a StaticBody2D per piece at load. No scene file holds them,
# so a second layout is a second entry in LAYOUTS, not a second scene.
#
# The tower: 640 wide, 1080 tall (three screens). A 128 px hole in the middle
# of the ceiling and the floor (x 256..384): out of the bottom, in at the top,
# and the other way round. Two side passages through both walls (y 380..428
# and 800..848): out of one wall, in at the other. Ledges every 70 px in a
# zigzag, so every row is one jump (80 px) from the row under it.
# ==============================================================================

const WALL := 48.0        # wall thickness, outside the screen
const HOLE_X0 := 256.0    # the ceiling and floor hole, left edge
const HOLE_X1 := 384.0    # right edge
const PASS_H := 48.0      # a side passage is this tall

const LAYOUTS := {
	"tower": {
		"width": 640.0,
		"height": 1080.0,
		"passages": [380.0, 800.0],   # top edge of each side passage (both walls)
		"pieces": [
			# --- the shell ---
			{"name": "WallLeftTop",     "kind": "wall", "x": -48.0, "y": -48.0, "w": 48.0, "h": 428.0},
			{"name": "WallLeftMid",     "kind": "wall", "x": -48.0, "y": 428.0, "w": 48.0, "h": 372.0},
			{"name": "WallLeftBottom",  "kind": "wall", "x": -48.0, "y": 848.0, "w": 48.0, "h": 280.0},
			{"name": "WallRightTop",    "kind": "wall", "x": 640.0, "y": -48.0, "w": 48.0, "h": 428.0},
			{"name": "WallRightMid",    "kind": "wall", "x": 640.0, "y": 428.0, "w": 48.0, "h": 372.0},
			{"name": "WallRightBottom", "kind": "wall", "x": 640.0, "y": 848.0, "w": 48.0, "h": 280.0},
			{"name": "CeilingLeft",     "kind": "wall", "x": -48.0, "y": -48.0, "w": 304.0, "h": 48.0},
			{"name": "CeilingRight",    "kind": "wall", "x": 384.0, "y": -48.0, "w": 304.0, "h": 48.0},
			{"name": "FloorLeft",       "kind": "wall", "x": -48.0, "y": 1080.0, "w": 304.0, "h": 48.0},
			{"name": "FloorRight",      "kind": "wall", "x": 384.0, "y": 1080.0, "w": 304.0, "h": 48.0},
			# --- the top third ---
			{"name": "L90a",   "kind": "ledge", "x": 130.0, "y": 90.0,  "w": 140.0, "h": 12.0},
			{"name": "L90b",   "kind": "ledge", "x": 370.0, "y": 90.0,  "w": 140.0, "h": 12.0},
			{"name": "B160L",  "kind": "bump",  "x": 0.0,   "y": 160.0, "w": 90.0,  "h": 16.0},
			{"name": "B160R",  "kind": "bump",  "x": 550.0, "y": 160.0, "w": 90.0,  "h": 16.0},
			{"name": "L230",   "kind": "ledge", "x": 250.0, "y": 230.0, "w": 140.0, "h": 12.0},
			{"name": "L300a",  "kind": "ledge", "x": 60.0,  "y": 300.0, "w": 140.0, "h": 12.0, "spawn": true},
			{"name": "L300b",  "kind": "ledge", "x": 440.0, "y": 300.0, "w": 140.0, "h": 12.0, "spawn": true},
			# --- the middle third ---
			{"name": "L380",   "kind": "ledge", "x": 260.0, "y": 380.0, "w": 120.0, "h": 12.0},
			{"name": "L450a",  "kind": "ledge", "x": 130.0, "y": 450.0, "w": 140.0, "h": 12.0},
			{"name": "L450b",  "kind": "ledge", "x": 370.0, "y": 450.0, "w": 140.0, "h": 12.0},
			{"name": "B520L",  "kind": "bump",  "x": 0.0,   "y": 520.0, "w": 90.0,  "h": 16.0},
			{"name": "B520R",  "kind": "bump",  "x": 550.0, "y": 520.0, "w": 90.0,  "h": 16.0},
			{"name": "L590",   "kind": "ledge", "x": 250.0, "y": 590.0, "w": 140.0, "h": 12.0},
			{"name": "L660a",  "kind": "ledge", "x": 40.0,  "y": 660.0, "w": 140.0, "h": 12.0},
			{"name": "L660b",  "kind": "ledge", "x": 460.0, "y": 660.0, "w": 140.0, "h": 12.0},
			# --- the bottom third ---
			{"name": "L730",   "kind": "ledge", "x": 260.0, "y": 730.0, "w": 120.0, "h": 12.0},
			{"name": "L800a",  "kind": "ledge", "x": 130.0, "y": 800.0, "w": 140.0, "h": 12.0},
			{"name": "L800b",  "kind": "ledge", "x": 370.0, "y": 800.0, "w": 140.0, "h": 12.0},
			{"name": "B870L",  "kind": "bump",  "x": 0.0,   "y": 870.0, "w": 90.0,  "h": 16.0},
			{"name": "B870R",  "kind": "bump",  "x": 550.0, "y": 870.0, "w": 90.0,  "h": 16.0},
			{"name": "L940",   "kind": "ledge", "x": 250.0, "y": 940.0, "w": 140.0, "h": 12.0},
			{"name": "L1010a", "kind": "ledge", "x": 60.0,  "y": 1010.0, "w": 140.0, "h": 12.0, "spawn": true},
			{"name": "L1010b", "kind": "ledge", "x": 440.0, "y": 1010.0, "w": 140.0, "h": 12.0, "spawn": true},
		],
	},
}

static func get_layout(name: String) -> Dictionary:
	return LAYOUTS.get(name, LAYOUTS["tower"])

# The round-start spots of a layout: the middle of the top edge of every
# spawn ledge, left to right, top to bottom. The same on every screen.
static func spawn_spots(layout: Dictionary, feet_offset: float) -> Array:
	var out: Array = []
	for piece in layout["pieces"]:
		if bool(piece.get("spawn", false)):
			out.append(Vector2(float(piece["x"]) + float(piece["w"]) / 2.0, float(piece["y"]) - feet_offset))
	out.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out

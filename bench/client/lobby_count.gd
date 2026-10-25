# The countdown (2026-10-25): START was pressed, 3 seconds. The screen dims, a
# big 3, 2, 1 punches in (huge and bright, then it settles), a ring bursts out
# on each beat, and under it GET READY and the arena the match starts on.
# Drawn in the lobby's 1920 x 1080 frame; lobby.gd calls show_count() each frame.
extends Control

const Art = preload("res://client/lobby_art.gd")
const NUM_SIZE := 330
const MID := Vector2(960, 470)    # the number's middle

var pal: Dictionary = {}
var n := 0                         # the number shown (0: none)
var beat := 9.0                    # seconds since it changed
var arena := ""
var fade := 0.0
var num := _Num.new()              # the number: its own control, so its scale is a plain scale
var num_fill := _NumFill.new()

class _Num extends Control:
	var count
	func _draw() -> void:
		if count != null:
			count._paint_num(self, false)

class _NumFill extends Control:
	var count
	func _draw() -> void:
		if count != null:
			count._paint_num(self, true)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size = Vector2(1920, 1080)
	num.count = self
	num_fill.count = self
	for c in [num, num_fill]:
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = Vector2(800, 420)
	num.position = MID - num.size * 0.5
	num.pivot_offset = num.size * 0.5
	num.add_child(num_fill)
	num_fill.material = Art.grad_material(Color.WHITE, Color.WHITE, 210.0 - NUM_SIZE * 0.36, 210.0 + NUM_SIZE * 0.36, 1.0)
	add_child(num)
	visible = false

func set_dress(p: Dictionary) -> void:
	pal = p
	var m: ShaderMaterial = num_fill.material
	m.set_shader_parameter("top_col", pal["logo_top"])
	m.set_shader_parameter("bot_col", pal["logo_bot"])

# secs: the whole seconds left (3, 2, 1), or 0 when no countdown runs.
func show_count(secs: int, arena_name: String, delta: float) -> void:
	if secs != n:
		n = secs
		beat = 0.0
	beat += delta
	arena = arena_name
	fade = clampf(fade + (delta * 5.0 if secs > 0 else -delta * 6.0), 0.0, 1.0)
	visible = fade > 0.0
	if not visible:
		return
	var punch := 1.0 + 1.1 * (1.0 - Art.ease_out(beat / 0.28)) - 0.08 * clampf((beat - 0.28) / 0.7, 0.0, 1.0)
	num.scale = Vector2.ONE * punch
	queue_redraw()
	num.queue_redraw()
	num_fill.queue_redraw()

func _draw() -> void:
	if pal.is_empty():
		return
	draw_rect(Rect2(-1200, -600, 4320, 2280), Color(0, 0, 0, 0.5 * fade))
	if n <= 0:
		return
	var accent: Color = pal["accent"]
	# the ring bursts out on each beat
	var k := clampf(beat / 0.6, 0.0, 1.0)
	draw_arc(MID, 170.0 + 330.0 * Art.ease_out(k), 0.0, TAU, 72, Color(accent.r, accent.g, accent.b, (1.0 - k) * 0.85 * fade),
		16.0 * (1.0 - k) + 2.0, true)
	draw_arc(MID, 150.0 + 200.0 * Art.ease_out(k), 0.0, TAU, 72, Color(1, 1, 1, (1.0 - k) * 0.5 * fade), 5.0, true)
	var edge := Color(0.03, 0.01, 0.05, fade)
	Art.text(self, Art.DISPLAY, Vector2(0, 760), "GET READY!", 74, Color(pal["text"], fade), 10, edge, HORIZONTAL_ALIGNMENT_CENTER, 1920)
	if arena != "":
		Art.text(self, Art.DISPLAY, Vector2(0, 830), arena, 46, Color(pal["accent_hi"], fade), 8, edge, HORIZONTAL_ALIGNMENT_CENTER, 1920)

func _paint_num(c: Control, fill: bool) -> void:
	if n <= 0 or pal.is_empty():
		return
	var s := str(n)
	var a := clampf(beat / 0.08, 0.0, 1.0) * fade
	var base := Vector2(0, 210.0 + NUM_SIZE * 0.36)
	if fill:
		c.draw_string(Art.DISPLAY, base, s, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, NUM_SIZE, Color(1, 1, 1, a))
		return
	c.draw_string_outline(Art.DISPLAY, base + Vector2(0, 16), s, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, NUM_SIZE, 34, Color(0, 0, 0, 0.55 * a))
	c.draw_string_outline(Art.DISPLAY, base, s, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, NUM_SIZE, 30, Color(pal["logo_edge"], a))
	c.draw_string_outline(Art.DISPLAY, base, s, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, NUM_SIZE, 14, Color(pal["logo_rim"], a))

# ==============================================================================
# FONT_WARMUP.GD (v0.1.2, cut 1)
# ==============================================================================
# The story: on the two phones the first replay of a match hitched (89 ms on
# the S25 Ultra, 52 ms on the Pixel) and the first "knocked out" banner cost
# about 40 ms, while every later one was free. Godot draws a glyph the first
# time it is needed: it rasterizes it (at the screen's oversampling, about 4x on
# a phone), puts it into an atlas and uploads the atlas to the GPU. Every
# (font size, outline size) pair has its own atlas. This node draws the printable
# ASCII range once, far off-screen, for every pair the scene will use, prints one
# 🔤 [FontWarm] line, and frees itself. The cost lands in the scene's load
# spike instead of the fight. arena.gd and character_select.gd add one.
# ==============================================================================
extends Node2D

const ASCII := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~·"

var pairs: Array = []   # [[size, outline], ...]


func _init(p: Array) -> void:
	pairs = p
	position = Vector2(-4000.0, -4000.0)   # never on screen; _draw still runs for a visible item


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	var t0 := Time.get_ticks_usec()
	var font: Font = ThemeDB.fallback_font
	var y := 0.0
	for p in pairs:
		var size: int = int(p[0])
		var outline: int = int(p[1])
		if outline > 0:
			draw_string_outline(font, Vector2(0.0, y), ASCII, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, Color(0, 0, 0, 1))
		draw_string(font, Vector2(0.0, y), ASCII, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 1, 1, 1))
		y += float(size) * 2.0
	print("🔤 [FontWarm] pairs=%d ms=%.1f" % [pairs.size(), (Time.get_ticks_usec() - t0) / 1000.0])
	call_deferred("queue_free")

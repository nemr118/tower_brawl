# p4.17 (the user: "Let's make it look great"): the round's big words (ROUND N, FIGHT!,
# a round's winner, DRAW; the replay's match winner and MATCH POINT) in the lobby
# title's style (client/lobby_logo.gd): the lobby's heavy font, a soft glow behind, a
# drop shadow, a dark edge and a coloured rim, the letters filled with a gradient that
# a light sweeps across (lobby_art.gd grad_material), and a pop when a banner comes up
# (big, then settling). Under the big line a painted ribbon can carry a second line
# (the arena's name, WINS THE ROUND; assets/ui_ribbon.png, ComfyUI, its flat middle
# stretched to fit the words). Small lines (GET READY, DRAW IN N) in the same font with
# a dark edge. hud.gd and deathcam.gd hand it what to show every frame (set_banner);
# polish "banners2" (off: the plain words as before). Drawn on a 1920 x 1080 design.
# The letters are drawn at three sizes only and scaled to the size asked for: a font
# keeps a sheet of letters (about 2 MB on the GPU) for every size and outline it draws
# (p4.15's iPhone lesson, client/deathcam.gd).
extends Control

const Art = preload("res://client/lobby_art.gd")
const HALO := preload("res://assets/fx_halo.png")
const RIBBON := preload("res://assets/ui_ribbon.png")
const RIB_CAP := 192.0           # the ribbon picture's ends (its tails and folds), px of its 1024 x 191
const RIB_FACE := 96.0           # where its flat front starts, from each end
const RIB_H := 84.0              # its height on the design
const POP_S := 0.24              # the pop: from POP_BIG times the size to its own over this long
const POP_BIG := 1.45
const BIG := 160                 # the big line over 100 px is drawn at BIG, up to 100 px at MID
const MID := 86
const SMALL := 52                # the ribbon's words and the small lines

var main: Array = []             # [text, size, top colour, bottom colour, rim colour, baseline y(, alpha)]
var alpha := 1.0                 # main's seventh item: the whole banner fades with it (the replay's title)
var rib := ""                    # the ribbon's words under the big line ("": no ribbon)
var extra: Array = []            # [[text, size, colour, baseline y], ...]
var key := ""                    # the big line shown (a new one: the pop starts again)
var t := 9.0
var base := MID                  # the size the big line is drawn at
var line := _Part.new()          # the big line, scaled from base to its size
var fill := _Part.new()          # its letters' fill (the gradient and the light), in line

class _Part extends Control:
	var b
	func _draw() -> void:
		if b != null:
			b._paint_part(self)

func _init() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	for p in [line, fill]:
		p.b = self
		p.size = size
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.material = Art.grad_material(Color.WHITE, Color.WHITE, 0.0, 100.0, 1.0)
	add_child(line)
	line.add_child(fill)

# What to show this frame: the big line (or []), the ribbon's words, the small lines.
func set_banner(m: Array, ribbon: String, ex: Array, delta: float) -> void:
	var k := str(m[0]) if not m.is_empty() else ""
	if k != key:
		key = k
		t = 0.0
	t += delta
	main = m
	rib = ribbon if not m.is_empty() else ""
	extra = ex
	alpha = float(m[6]) if m.size() > 6 else 1.0
	var s := 1.0
	if not main.is_empty() and t < POP_S:
		var u := t / POP_S
		s = 1.0 + (POP_BIG - 1.0) * (1.0 - u) * (1.0 - u) - 0.06 * sin(u * PI)   # big, a little under, settled
	pivot_offset = Vector2(960.0, float(main[5]) - float(main[1]) * 0.36) if not main.is_empty() else Vector2(960, 540)
	scale = Vector2.ONE * s
	if not main.is_empty():
		var y: float = main[5]
		base = BIG if int(main[1]) > 100 else MID
		line.pivot_offset = Vector2(960.0, y)
		line.scale = Vector2.ONE * (float(main[1]) / base)
		var mat: ShaderMaterial = fill.material
		mat.set_shader_parameter("top_col", main[2])
		mat.set_shader_parameter("bot_col", main[3])
		mat.set_shader_parameter("y0", y - base * 0.74)
		mat.set_shader_parameter("y1", y)
	queue_redraw()
	line.queue_redraw()
	fill.queue_redraw()

# The ribbon and its words, then the small lines (a size other than SMALL: scaled).
func _draw() -> void:
	var f := Art.DISPLAY
	var a := clampf(t / 0.08, 0.0, 1.0) * alpha
	if rib != "":
		var k := RIB_H / float(RIBBON.get_height())
		var fs := 44.0
		var tw := f.get_string_size(rib, HORIZONTAL_ALIGNMENT_LEFT, -1, SMALL).x * fs / SMALL
		var cap := RIB_CAP * k
		var w := maxf(tw + 2.0 * RIB_FACE * k + 64.0, 2.0 * cap + 40.0)
		var x0 := 960.0 - w * 0.5
		var y0 := float(main[5]) + 16.0
		var tint := Color(1, 1, 1, a)
		var src_w := float(RIBBON.get_width())
		draw_texture_rect_region(RIBBON, Rect2(x0, y0, cap, RIB_H), Rect2(0, 0, RIB_CAP, RIBBON.get_height()), tint)
		draw_texture_rect_region(RIBBON, Rect2(x0 + cap, y0, w - 2.0 * cap, RIB_H), Rect2(RIB_CAP, 0, src_w - 2.0 * RIB_CAP, RIBBON.get_height()), tint)
		draw_texture_rect_region(RIBBON, Rect2(x0 + w - cap, y0, cap, RIB_H), Rect2(src_w - RIB_CAP, 0, RIB_CAP, RIBBON.get_height()), tint)
		_small(f, rib, fs, Color(1.0, 0.93, 0.62, a), y0 + RIB_H * 0.44 + fs * 0.36, Color(0.24, 0.02, 0.03, 0.95 * a))
	for e in extra:
		_small(f, e[0], float(e[1]), Color(e[2], e[2].a * alpha), float(e[3]), Color(0.07, 0.02, 0.1, 0.9 * alpha))

func _small(f: Font, s: String, fs: float, col: Color, y: float, edge: Color) -> void:
	var k := fs / SMALL
	draw_set_transform(Vector2(960.0 * (1.0 - k), y * (1.0 - k)), 0.0, Vector2(k, k))
	draw_string_outline(f, Vector2(0, y), s, HORIZONTAL_ALIGNMENT_CENTER, 1920, SMALL, 10, edge)
	draw_string(f, Vector2(0, y), s, HORIZONTAL_ALIGNMENT_CENTER, 1920, SMALL, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The big line: in line, the glow, the shadow, the dark edge and the rim; in fill,
# the letters in white (the material turns them into the gradient and the light).
func _paint_part(c: Control) -> void:
	if main.is_empty():
		return
	var f := Art.DISPLAY
	var text: String = main[0]
	var y: float = main[5]
	var a := clampf(t / 0.08, 0.0, 1.0) * alpha
	if c == fill:
		c.draw_string(f, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, base, Color(1, 1, 1, a))
		return
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, base).x
	var ol := int(base * 0.15)
	c.draw_texture_rect(HALO, Rect2(960.0 - w * 0.68, y - base * 1.15, w * 1.36, base * 1.6), false, Color(main[3], 0.34 * a))
	c.draw_string_outline(f, Vector2(0, y + base * 0.07), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, base, ol, Color(0, 0, 0, 0.55 * a))
	c.draw_string_outline(f, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, base, ol, Color(0.07, 0.02, 0.1, a))
	c.draw_string_outline(f, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, base, int(base * 0.06), Color(main[4], a))

# The lobby's look (2026-10-25): its two dresses (HALLOWEEN in October, the
# castle at night the rest of the year), its two fonts (Noto Sans Condensed, an
# open licence: assets/fonts/OFL.txt) and the shapes the lobby draws with:
# panels and buttons with depth (a dark lip under them, a light line on top, a
# soft shadow or a coloured glow), text with an outline and a drop shadow.
# Used by lobby.gd and its parts (lobby_bg, lobby_logo, lobby_cards, lobby_count).
extends RefCounted

const DISPLAY: FontFile = preload("res://assets/fonts/lobby_display.ttf")   # Noto Sans Condensed Black
const BODY: FontFile = preload("res://assets/fonts/lobby_body.ttf")         # Noto Sans Condensed Bold

# A dress is a set of colours and words. "halloween": purple night, pumpkin
# orange, slime green. "castle": blue night, gold.
const DRESSES := {
	"halloween": {
		"tint_top": Color(0.07, 0.01, 0.11, 0.86), "tint_mid": Color(0.05, 0.01, 0.09, 0.38), "tint_bot": Color(0.03, 0.0, 0.06, 0.92),
		"panel": Color(0.10, 0.05, 0.16, 0.93), "panel_edge": Color(0.46, 0.25, 0.72), "panel_hi": Color(0.85, 0.7, 1.0, 0.16),
		"accent": Color(1.0, 0.52, 0.08), "accent_hi": Color(1.0, 0.80, 0.30), "accent_dark": Color(0.45, 0.14, 0.02),
		"second": Color(0.55, 1.0, 0.35), "button": Color(0.30, 0.15, 0.45), "danger": Color(0.62, 0.16, 0.22),
		"text": Color(0.99, 0.96, 1.0), "dim": Color(0.74, 0.66, 0.85), "faint": Color(0.5, 0.42, 0.6),
		"logo_top": Color(1.0, 0.93, 0.5), "logo_bot": Color(1.0, 0.42, 0.04), "logo_rim": Color(0.5, 0.12, 0.62),
		"logo_edge": Color(0.09, 0.02, 0.12), "logo_glow": Color(1.0, 0.42, 0.08, 0.30),
		"ribbon": Color(0.40, 0.14, 0.60), "ribbon_dark": Color(0.20, 0.05, 0.32), "ribbon_text": Color(0.72, 1.0, 0.45),
		"tagline": "HALLOWEEN NIGHT",
		"mist": Color(0.58, 0.32, 0.9, 0.17), "ember": Color(1.0, 0.5, 0.12), "ember2": Color(0.55, 1.0, 0.35),
		"flash": Color(0.8, 0.7, 1.0),
	},
	"castle": {
		"tint_top": Color(0.02, 0.03, 0.07, 0.84), "tint_mid": Color(0.02, 0.03, 0.06, 0.34), "tint_bot": Color(0.01, 0.02, 0.04, 0.92),
		"panel": Color(0.06, 0.08, 0.13, 0.93), "panel_edge": Color(0.34, 0.46, 0.68), "panel_hi": Color(0.75, 0.85, 1.0, 0.16),
		"accent": Color(1.0, 0.74, 0.18), "accent_hi": Color(1.0, 0.9, 0.5), "accent_dark": Color(0.42, 0.24, 0.02),
		"second": Color(0.45, 0.78, 1.0), "button": Color(0.17, 0.26, 0.42), "danger": Color(0.6, 0.18, 0.18),
		"text": Color(0.97, 0.97, 1.0), "dim": Color(0.66, 0.72, 0.84), "faint": Color(0.42, 0.48, 0.58),
		"logo_top": Color(1.0, 0.96, 0.7), "logo_bot": Color(0.96, 0.6, 0.12), "logo_rim": Color(0.55, 0.22, 0.05),
		"logo_edge": Color(0.1, 0.05, 0.02), "logo_glow": Color(1.0, 0.7, 0.25, 0.22),
		"ribbon": Color(0.62, 0.12, 0.14), "ribbon_dark": Color(0.34, 0.05, 0.07), "ribbon_text": Color(1.0, 0.9, 0.6),
		"tagline": "8 PLAYER ARCHER BRAWL",
		"mist": Color(0.45, 0.55, 0.75, 0.14), "ember": Color(1.0, 0.62, 0.22), "ember2": Color(1.0, 0.85, 0.45),
		"flash": Color(0.8, 0.85, 1.0),
	},
}

# Letters filled with a gradient (top colour to bottom colour, over local y0..y1
# of the control that draws them in white) and a light that sweeps across every
# few seconds (shine 0: none). The logo and the countdown's numbers use it.
const GRAD_SHADER := "shader_type canvas_item;
uniform vec4 top_col : source_color = vec4(1.0);
uniform vec4 bot_col : source_color = vec4(1.0);
uniform float y0 = 0.0;
uniform float y1 = 100.0;
uniform float shine = 1.0;
varying vec2 local;
void vertex() {
	local = VERTEX;
}
void fragment() {
	float k = clamp((local.y - y0) / (y1 - y0), 0.0, 1.0);
	vec3 g = mix(top_col.rgb, bot_col.rgb, k);
	float sx = mod(TIME * 420.0, 2600.0) - 300.0;
	float band = 1.0 - smoothstep(0.0, 34.0, abs(local.x - local.y * 0.45 - sx));
	g = mix(g, vec3(1.0), band * 0.6 * shine);
	COLOR = vec4(g, COLOR.a);
}"

static var _ready_fonts := false
static var _boxes := {}
static var _grad: Shader

static func grad_material(top: Color, bot: Color, y0: float, y1: float, shine: float) -> ShaderMaterial:
	if _grad == null:
		_grad = Shader.new()
		_grad.code = GRAD_SHADER
	var m := ShaderMaterial.new()
	m.shader = _grad
	m.set_shader_parameter("top_col", top)
	m.set_shader_parameter("bot_col", bot)
	m.set_shader_parameter("y0", y0)
	m.set_shader_parameter("y1", y1)
	m.set_shader_parameter("shine", shine)
	return m

# The page's options as one string (?a=1&b=2 on the web, --a=1 on the PC).
static func _query() -> String:
	var q := ""
	if OS.has_feature("web"):
		q = str(JavaScriptBridge.eval("window.location.search", true))
	for a in OS.get_cmdline_user_args():
		q += " " + a
	return q

# The dress for tonight: "halloween" from October 1 to November 2, else "castle".
# A test knob: ?dress=castle or ?dress=halloween on the page (--dress=... on the PC).
static func pick_dress() -> String:
	var q := _query()
	for d in DRESSES:
		if ("dress=" + d) in q:
			return d
	var t := Time.get_date_dict_from_system()
	return "halloween" if int(t.month) == 10 or (int(t.month) == 11 and int(t.day) <= 2) else "castle"

# A test knob for pictures: ?lobby_slow=4 plays the lobby's rise-in 4 times
# slower (1: normal).
static func slow_knob() -> float:
	var q := _query()
	var i := q.find("lobby_slow=")
	if i < 0:
		return 1.0
	return clampf(float(q.substr(i + 11).get_slice("&", 0).get_slice(" ", 0)), 1.0, 20.0)

# The fonts hold only the letters the game uses: anything else (a name with an
# emoji) falls back to Godot's own font.
static func fonts_ready() -> void:
	if _ready_fonts:
		return
	_ready_fonts = true
	var fb: Array[Font] = [ThemeDB.fallback_font]
	for f: FontFile in [DISPLAY, BODY]:
		f.fallbacks = fb

# A rounded box with a border (bottom: the lip's height), cached by its looks.
static func box(fill: Color, edge: Color, radius: int, border: int = 2, bottom: int = -1, shadow: Color = Color(0, 0, 0, 0),
		shadow_size: int = 0, top: int = -1) -> StyleBoxFlat:
	var key := "%s|%s|%d|%d|%d|%s|%d|%d" % [fill.to_html(), edge.to_html(), radius, border, bottom, shadow.to_html(), shadow_size, top]
	if _boxes.has(key):
		return _boxes[key]
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(border)
	if bottom >= 0:
		s.border_width_bottom = bottom
	if top >= 0:
		s.border_width_top = top
	s.set_corner_radius_all(radius)
	s.corner_detail = 6
	s.anti_aliasing = true
	if shadow_size > 0:
		s.shadow_color = shadow
		s.shadow_size = shadow_size
		s.shadow_offset = Vector2(0, maxf(2.0, shadow_size * 0.35))
	_boxes[key] = s
	return s

# A panel with depth: a soft shadow, a dark edge, a fill, a light line on top.
static func panel(c: CanvasItem, r: Rect2, fill: Color, edge: Color, radius: int = 18, glow: Color = Color(0, 0, 0, 0.5), glow_size: int = 14) -> void:
	c.draw_style_box(box(fill, edge, radius, 3, 3, glow, glow_size), r)
	var hi := Color(1, 1, 1, 0.09)
	c.draw_line(r.position + Vector2(radius, 5), r.position + Vector2(r.size.x - radius, 5), hi, 2.0)

# Text with a drop shadow and an outline. pos is the baseline's left end, or the
# left end of a box width wide that align lines the text up in (as draw_string).
static func text(c: CanvasItem, font: Font, pos: Vector2, s: String, size: int, col: Color, outline: int = 0,
		edge: Color = Color(0, 0, 0, 1), align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0, shadow: bool = true) -> void:
	if s == "":
		return
	if shadow:
		var so := Vector2(0, maxf(2.0, size * 0.07))
		c.draw_string_outline(font, pos + so, s, align, width, size, outline + maxi(2, size / 12), Color(0, 0, 0, 0.5 * col.a))
	if outline > 0:
		c.draw_string_outline(font, pos, s, align, width, size, outline, Color(edge.r, edge.g, edge.b, edge.a * col.a))
	c.draw_string(font, pos, s, align, width, size, col)

# The biggest size up to size at which s fits in width, in steps of 4 (few sizes:
# each size is its own texture of letters, and fewer of them batch better).
static func fit_size(font: Font, s: String, size: int, width: float, smallest: int = 14) -> int:
	var fs := size
	while fs > smallest and font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > width:
		fs -= 4
	return maxi(fs, smallest)

static func ease_out_back(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)

static func ease_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 - pow(1.0 - x, 3.0)

# A small crown (the matches won tonight), its base centred on p.
static func crown(c: CanvasItem, p: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([Vector2(-12, 0), Vector2(-12, -13), Vector2(-6, -6), Vector2(0, -16), Vector2(6, -6),
		Vector2(12, -13), Vector2(12, 0)])
	for i in pts.size():
		pts[i] = p + pts[i] * s
	c.draw_colored_polygon(pts, col)
	c.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.25, 0.12, 0.0, 0.9), 2.0 * s)

# A key cap for the controls line (PC): a small rounded box with the key's name.
# (Two plain rects, a lip and a face: plain rects batch, so a row of keys is one
# draw.) keycap_words() writes the key's name on it afterwards.
static func keycap(c: CanvasItem, x: float, base_y: float, key: String, size: int, face: Color) -> float:
	var w := BODY.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + size * 0.9
	var h := size * 1.45
	var r := Rect2(x, base_y - size * 1.08, w, h)
	c.draw_rect(r, face.darkened(0.55))
	c.draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 7)), face)
	return w

static func keycap_words(c: CanvasItem, x: float, base_y: float, key: String, size: int, ink: Color) -> void:
	c.draw_string(BODY, Vector2(x + size * 0.45, base_y), key, HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)

# A button with depth (2026-10-25). Its face sits on a darker lip (the bottom
# edge) that goes when it is pressed; a light line on top; a soft shadow, or a
# coloured glow (glow 0..1, the lobby pulses START and JOIN with it). It draws
# its own words: a small caption over a big value (ARENA / MIX), or the value
# alone, with a glyph: 1 play (START), 2 plus (JOIN), 3 a spinner (waiting),
# 4 back (LEAVE), 5 a chevron at the right (a button that steps through choices).
class Btn extends Button:
	var caption := ""
	var value := ""
	var thumb: Texture2D = null    # 2026-10-26: a small picture at the left (the ARENA button: the pick's painting)
	var thumb_src := Rect2()
	var pic: Texture2D = null      # p4.17: a square picture at the left (polish "ui_icons": assets/ui_icons.png)
	var pic_src := Rect2()
	var size_px := 40
	var cap_px := 0          # the caption's size (0: 62% of size_px)
	var glyph := 0
	var face := Color(0.3, 0.3, 0.4)
	var ink := Color.WHITE
	var glow := 0.0
	var glow_col := Color(1, 0.6, 0.1)
	var t := 0.0
	var _shown_glow := -1.0
	var _n: StyleBoxFlat           # the normal and hover faces (their shadows are the glow)
	var _h: StyleBoxFlat

	func setup(face_col: Color, ink_col: Color, fsize: int) -> void:
		face = face_col
		ink = ink_col
		size_px = fsize
		text = ""
		focus_mode = Control.FOCUS_NONE
		_styles()

	func _styles() -> void:
		var edge := face.darkened(0.6)
		_n = StyleBoxFlat.new()
		_face(_n, face, edge, 3, 11, Color(0, 0, 0, 0.45), 10)
		_h = StyleBoxFlat.new()
		_face(_h, face.lightened(0.12), edge, 3, 11, Color(0, 0, 0, 0.45), 14)
		var p := StyleBoxFlat.new()
		_face(p, face.darkened(0.1), edge, 8, 4, Color(0, 0, 0, 0.35), 4)
		var d := StyleBoxFlat.new()
		var dface := Color(face.r, face.g, face.b).lerp(Color(0.16, 0.15, 0.2), 0.7)
		_face(d, Color(dface, 0.92), dface.darkened(0.5), 3, 7, Color(0, 0, 0, 0.3), 6)
		add_theme_stylebox_override("normal", _n)
		add_theme_stylebox_override("hover", _h)
		add_theme_stylebox_override("pressed", p)
		add_theme_stylebox_override("hover_pressed", p)
		add_theme_stylebox_override("disabled", d)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		_shown_glow = -1.0
		_glow_styles()

	# The glow is the shadow of the face, in the glow's colour: only the shadow changes.
	func _glow_styles() -> void:
		var g := clampf(glow, 0.0, 1.0)
		var sh_col := Color(glow_col.r, glow_col.g, glow_col.b, 0.25 + 0.45 * g) if g > 0.01 else Color(0, 0, 0, 0.45)
		_n.shadow_color = sh_col
		_n.shadow_size = 10 + int(22.0 * g)
		_h.shadow_color = sh_col
		_h.shadow_size = 14 + int(22.0 * g)
		_shown_glow = g

	static func _face(s: StyleBoxFlat, fill: Color, edge: Color, top: int, bottom: int, sh_col: Color, sh: int) -> void:
		s.bg_color = fill
		s.border_color = edge
		s.set_border_width_all(3)
		s.border_width_top = top
		s.border_width_bottom = bottom
		s.set_corner_radius_all(16)
		s.corner_detail = 6
		s.shadow_color = sh_col
		s.shadow_size = sh
		s.shadow_offset = Vector2(0, 3)

	# Its words: a small caption over the value, or the value alone (caption "").
	func say(cap: String, val: String) -> void:
		if cap != caption or val != value:
			caption = cap
			value = val
			queue_redraw()

	# The lobby calls this every frame it animates: the glow changes the styles
	# only when it moved enough to see.
	func step(delta: float, g: float) -> void:
		t += delta
		glow = g
		if absf(glow - _shown_glow) > 0.04:
			_glow_styles()
		if glyph == 3 or not is_zero_approx(glow):
			queue_redraw()

	func _draw() -> void:
		var mode := get_draw_mode()
		var down := mode == DRAW_PRESSED or mode == DRAW_HOVER_PRESSED
		var off := disabled
		var top := 8.0 if down else 3.0
		var bottom := 4.0 if down else 11.0
		var w := size.x
		var h := size.y
		if not down:
			draw_rect(Rect2(16, top + 2, w - 32, 2), Color(1, 1, 1, 0.08 if off else 0.26))
		var mid := (top + h - bottom) * 0.5
		var col := ink if not off else Color(ink, 0.38)
		var edge := face.darkened(0.7)
		var icon_w := 0.0
		if glyph in [1, 2, 3, 4] and value != "":
			icon_w = size_px * 0.9
		var cap_x := 0.0
		if thumb != null:
			var th := h - top - bottom - 18.0
			var tr := Rect2(16.0, top + 9.0, th * 16.0 / 9.0, th)
			draw_rect(tr.grow(3.0), Color(0, 0, 0, 0.55))
			draw_texture_rect_region(thumb, tr, thumb_src, Color(1, 1, 1, 0.45 if off else 1.0))
			draw_rect(tr.grow(1.5), Color(edge, 0.9), false, 3.0)
			icon_w = tr.size.x + 14.0
			cap_x = icon_w
		elif pic != null:
			var ih := h - top - bottom - 14.0
			var ir := Rect2(12.0, top + 7.0, ih, ih)
			draw_texture_rect_region(pic, ir, pic_src, Color(1, 1, 1, 0.45 if off else 1.0))
			icon_w = ih + 8.0
			cap_x = icon_w
		var label := value
		var fs := size_px
		var room := w - 40.0 - icon_w - (34.0 if glyph == 5 else 0.0)
		fs = _fit(label, fs, room)
		var tw := DISPLAY.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x0 := (w - tw - icon_w) * 0.5 + icon_w
		if glyph == 5:
			x0 -= 14.0
		var vy := mid + fs * 0.36
		if caption != "":
			var cs := cap_px if cap_px > 0 else int(size_px * 0.62)
			vy = mid + fs * 0.52
			draw_string(BODY, Vector2(cap_x, mid - fs * 0.42), caption, HORIZONTAL_ALIGNMENT_CENTER, w - cap_x - (28.0 if glyph == 5 else 0.0), cs,
				Color(col, col.a * 0.72))
		draw_string_outline(DISPLAY, Vector2(x0, vy), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(edge, 0.85 if not off else 0.3))
		draw_string(DISPLAY, Vector2(x0, vy), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var ic := Vector2(x0 - icon_w * 0.62, vy - fs * 0.36)
		var r := fs * 0.34
		match glyph:
			1:   # play
				var tri := PackedVector2Array([ic + Vector2(-r * 0.7, -r), ic + Vector2(r, 0), ic + Vector2(-r * 0.7, r)])
				draw_colored_polygon(tri, col)
				draw_polyline(tri + PackedVector2Array([tri[0]]), Color(edge, col.a), 3.0)
			2:   # plus
				draw_rect(Rect2(ic - Vector2(r, r * 0.28), Vector2(r * 2.0, r * 0.56)), col)
				draw_rect(Rect2(ic - Vector2(r * 0.28, r), Vector2(r * 0.56, r * 2.0)), col)
			6, 7:   # a minus or a plus alone in the middle (the bots' - and +)
				var bc := Vector2(w * 0.5, mid)
				var br := minf(w, h) * 0.2
				draw_rect(Rect2(bc - Vector2(br, br * 0.26), Vector2(br * 2.0, br * 0.52)), col)
				if glyph == 7:
					draw_rect(Rect2(bc - Vector2(br * 0.26, br), Vector2(br * 0.52, br * 2.0)), col)
			3:   # a spinner
				draw_arc(ic, r, t * 6.0, t * 6.0 + 4.2, 20, col, r * 0.38, true)
			4:   # back
				var pts := PackedVector2Array([ic + Vector2(r * 0.6, -r), ic + Vector2(-r * 0.4, 0), ic + Vector2(r * 0.6, r)])
				draw_polyline(pts, col, r * 0.42)
			5:   # a chevron: tap for the next choice
				var cx := w - 30.0
				var pts2 := PackedVector2Array([Vector2(cx - 6, mid - 12), Vector2(cx + 6, mid), Vector2(cx - 6, mid + 12)])
				draw_polyline(pts2, Color(col, col.a * 0.8), 5.0)

	func _fit(s: String, fs: int, room: float) -> int:
		while fs > 16 and DISPLAY.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > room:
			fs -= 2
		return fs

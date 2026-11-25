# p4.18 HOW TO PLAY (the October logs: kids let go of the bow inside the ring on 20 to 37%
# of their shots, and a holiday brings first-time players). Three big pictures over the
# lobby: how to move and jump, how to shoot, how to dodge and catch; then the round's
# goal in one line. It opens by itself the first time a device takes a seat
# (game_client.gd keeps that on the device) and from the lobby's HOW TO PLAY button; a
# tap anywhere closes it. The pictures fit the controls in use: a phone's CLASSIC sticks,
# its BUTTONS layout, or a keyboard and mouse. Drawn on the lobby's 1920 x 1080 frame.
extends Control

const Art = preload("res://client/lobby_art.gd")
const World = preload("res://client/world.gd")     # p4.19: the real fighters (FIGHTER_TEX), not stand-ins
const Polish = preload("res://client/polish.gd")
const Season = preload("res://client/season.gd")
const GOLD := Color(1.0, 0.82, 0.25)
const INK := Color(0.96, 0.96, 1.0)
const DIM := Color(0.75, 0.78, 0.9)
const TILE := Vector2(540, 560)

var mode := "pc"                  # "pc", "classic" or "buttons"
var t := 0.0
var pal: Dictionary = Art.DRESSES["castle"]   # p4.19: the lobby's dress (lobby.gd sets it)

func _init() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(m: String) -> void:
	mode = m
	t = 0.0
	visible = true
	queue_redraw()

func close() -> void:
	visible = false

func _process(delta: float) -> void:
	if visible:
		t += delta
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not e.pressed and t > 0.4:     # a moment first: the tap that opened it must not close it
			close()

func _text(at: Vector2, s: String, fs: int, col: Color, font: Font = null) -> void:
	var f: Font = font if font != null else Art.DISPLAY
	var p := at - Vector2(f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 0.0)
	draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 8, Color(0, 0, 0, col.a * 0.9))
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

# An arrow from a to b with a head.
func _arrow(a: Vector2, b: Vector2, col: Color, w: float = 10.0) -> void:
	var u := (b - a).normalized()
	var v := Vector2(-u.y, u.x)
	draw_line(a, b - u * w * 1.6, col, w, true)
	draw_colored_polygon(PackedVector2Array([b, b - u * w * 2.6 + v * w * 1.5, b - u * w * 2.6 - v * w * 1.5]), col)

# A thumb: a soft pad with a ring (where it rests) and the pad moved by off.
func _stick(c: Vector2, off: Vector2, r: float, col: Color) -> void:
	draw_circle(c, r, Color(1, 1, 1, 0.06))
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 4.0, true)
	draw_line(c, c + off, Color(col, 0.6), 6.0, true)
	draw_circle(c + off, r * 0.36, Color(col, 0.95))
	draw_arc(c + off, r * 0.36, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 3.0, true)

# A round button with a word.
func _button(c: Vector2, r: float, word: String, col: Color, down: bool) -> void:
	draw_circle(c + Vector2(0, 0.0 if down else 6.0), r, Color(0, 0, 0, 0.5))
	draw_circle(c, r, Color(col.darkened(0.25 if down else 0.0), 0.95))
	draw_arc(c, r, 0.0, TAU, 40, Color(1, 1, 1, 0.8), 4.0, true)
	_text(c + Vector2(0, 14), word, 40, Color(0.08, 0.05, 0.1))

# A key cap with its letter.
func _key(c: Vector2, word: String, w: float = 86.0) -> void:
	var r := Rect2(c - Vector2(w * 0.5, 43), Vector2(w, 86))
	draw_style_box(Art.box(Color(0.9, 0.9, 0.96), Color(0.4, 0.4, 0.5), 14, 3, 9), r)
	_text(c + Vector2(0, 12), word, 38 if word.length() <= 2 else 28, Color(0.1, 0.08, 0.14))

# p4.19 (polish "howto2"): the real fighter from its sheet (128 px frames, 16 a row: 0 and 1
# stand, 2 to 7 run, 8 jump, 9 fall, 10 aim, 13 dodge, 18 let go, 19 ready), with a shadow.
func _fighter(feet: Vector2, seat: int, frame: int, flip: bool, s: float = 1.4) -> void:
	draw_set_transform(feet + Vector2(0, 2), 0.0, Vector2(1.0, 0.28))
	draw_circle(Vector2.ZERO, 44.0, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var src := Rect2((frame % 16) * 128, (frame / 16) * 128, 128, 128)
	var dst := Rect2(feet.x - 64.0 * s, feet.y - 122.0 * s, 128.0 * s, 128.0 * s)
	if flip:
		dst.size.x = -dst.size.x      # a negative width draws it mirrored, in the same place
	draw_texture_rect_region(World.FIGHTER_TEX[seat], dst, src)

# A little archer: a hood, a body, in col (a stand-in for the fighter, drawn big).
func _archer(feet: Vector2, col: Color, s: float = 1.0) -> void:
	var body := PackedVector2Array([feet + Vector2(-22, 0) * s, feet + Vector2(-26, -64) * s, feet + Vector2(0, -92) * s,
		feet + Vector2(26, -64) * s, feet + Vector2(22, 0) * s])
	draw_colored_polygon(body, col)
	body.append(body[0])
	draw_polyline(body, Color(0.05, 0.03, 0.08), 4.0, true)
	draw_circle(feet + Vector2(0, -66) * s, 13.0 * s, Color(0.06, 0.04, 0.1))
	draw_circle(feet + Vector2(-5, -68) * s, 2.6 * s, Color(1, 1, 0.8))
	draw_circle(feet + Vector2(5, -68) * s, 2.6 * s, Color(1, 1, 0.8))

func _draw() -> void:
	var a := clampf(t / 0.15, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.01, 0.05, 0.93 * a))
	_text(Vector2(960, 122), "HOW TO PLAY", 78, Color(GOLD, a))
	var titles := ["1  MOVE", "2  SHOOT", "3  DODGE"]
	var k := 0.5 + 0.5 * sin(t * 2.6)          # the pictures move: 0..1 and back
	var pull := clampf(fmod(t, 2.4) / 1.4, 0.0, 1.0)   # the bow: a slow pull, then let go
	var let_go := fmod(t, 2.4) > 1.4
	var real := Polish.on("howto2")
	var a8 := roundf(a * 8.0) / 8.0       # the fade in steps: lobby_art.gd keeps every box it makes
	for i in 3:
		var r := Rect2(Vector2(90.0 + i * (TILE.x + 60.0), 180.0), TILE)
		if real:
			draw_style_box(Art.box(Color(pal["panel"], 0.97 * a8), Color(pal["accent"], 0.9 * a8), 26, 3, 8, Color(0, 0, 0, 0.55 * a8), 18), r)
			draw_style_box(Art.box(Color(pal["accent"], 0.16 * a8), Color(0, 0, 0, 0), 20, 0), Rect2(r.position + Vector2(8, 8), Vector2(r.size.x - 16, 96)))
		else:
			draw_style_box(Art.box(Color(0.09, 0.06, 0.15, 0.96 * a), Color(GOLD, 0.7 * a), 22, 3, 6, Color(0, 0, 0, 0.5), 14), r)
		_text(Vector2(r.get_center().x, r.position.y + 74.0), titles[i], 54, Color(GOLD, a))
		var c := r.get_center() + Vector2(0, 10)
		var say := ""
		var say2 := ""
		if i == 0:
			var hop := -70.0 * sin(k * PI) if mode != "pc" else -70.0 * sin(k * PI)
			if real:
				# it runs right and left, and hops in the middle of each run
				var right := cos(t * 2.6) > 0.0
				var up := -48.0 * maxf(0.0, sin(k * PI) * 1.6 - 0.6)
				var rising := (k < 0.5) == right
				var fr := (8 if rising else 9) if up < -4.0 else 2 + int(t * 12.0) % 6
				_floor(c + Vector2(0, 132), 400.0)
				_fighter(c + Vector2(-110.0 + 220.0 * k, 130.0 + up), 0, fr, not right)
			else:
				draw_line(c + Vector2(-190, 120), c + Vector2(190, 120), Color(1, 1, 1, 0.35), 6.0)   # a floor
				_archer(c + Vector2(-90.0 + 180.0 * k, 120.0 + hop), Color(0.91, 0.25, 0.24))
			if mode == "pc":
				_key(c + Vector2(-150, -120), "A")
				_key(c + Vector2(-50, -120), "D")
				_key(c + Vector2(110, -120), "SPACE", 190.0)
				say = "A and D run"
				say2 = "W or SPACE jumps"
			else:
				_stick(c + Vector2(-110, -110), Vector2(52.0 * (k * 2.0 - 1.0), 0), 78.0, Color(0.5, 0.8, 1.0))
				if mode == "buttons":
					_button(c + Vector2(120, -110), 62.0, "JUMP", Color(0.55, 1.0, 0.5), k > 0.6)
					say = "left thumb: slide to run"
					say2 = "tap JUMP to jump"
				else:
					_stick(c + Vector2(120, -110), Vector2(0, -56.0 * k), 78.0, Color(0.55, 1.0, 0.5))
					say = "left thumb: slide to run"
					say2 = "push it UP to jump"
		elif i == 1:
			if real:
				_floor(c + Vector2(0, 132), 400.0)
				_fighter(c + Vector2(-150, 130), 1, (18 if fmod(t, 2.4) < 1.7 else 0) if let_go else 10, false)
			else:
				_archer(c + Vector2(-150, 120), Color(0.24, 0.55, 0.91))
			var from := c + Vector2(-120, 60)
			if let_go:
				var fly := clampf((fmod(t, 2.4) - 1.4) / 0.6, 0.0, 1.0)
				_arrow(from + Vector2(260.0 * fly, -60.0 * fly), from + Vector2(70.0 + 260.0 * fly, -76.0 - 60.0 * fly), Color(1, 1, 1), 7.0)
				_text(c + Vector2(110, 110), "LET GO!", 44, Color(GOLD, a))
			else:
				draw_line(from, from + Vector2(190, -44), Color(1, 1, 1, 0.3 + 0.5 * pull), 4.0, true)   # where the arrow will go
			if mode == "pc":
				_key(c + Vector2(0, -120), "MOUSE", 190.0)
				say = "hold the mouse to aim"
				say2 = "let go to shoot"
			else:
				var sc := c + Vector2(60, -110)
				draw_arc(sc, 46.0, 0.0, TAU, 40, Color(GOLD, 0.9), 5.0, true)      # the ring: pull past it
				_stick(sc, Vector2(-96.0, 22.0) * (pull if not let_go else 0.0), 78.0, Color(1.0, 0.75, 0.3))
				say = "right thumb: PULL BACK"
				say2 = "past the ring, then let go"
		else:
			var dash := clampf(fmod(t, 2.0) / 0.5, 0.0, 1.0)
			if real:
				# a dash into an arrow that flies at it; then the arrow is caught
				_floor(c + Vector2(0, 132), 400.0)
				_fighter(c + Vector2(-130.0 + 150.0 * dash, 130), 2, 13 if dash < 1.0 else 19, false)
				if dash < 1.0:
					var ax := lerpf(240.0, 110.0, dash)
					_arrow(c + Vector2(ax + 90.0, 72), c + Vector2(ax, 72), Color(1, 1, 1, 0.95), 7.0)
				elif fmod(t, 2.0) < 1.5:
					var pop := 1.0 + 0.25 * maxf(0.0, 1.0 - (fmod(t, 2.0) - 0.5) / 0.2)
					draw_set_transform(c + Vector2(130, 60), -0.08, Vector2.ONE * pop)
					_text(Vector2(0, 0), "CAUGHT!", 44, Color(GOLD, a))
					draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				_archer(c + Vector2(-110.0 + 150.0 * dash, 120), Color(0.37, 0.83, 0.35))
				_arrow(c + Vector2(210, 70), c + Vector2(110, 70), Color(1, 1, 1, 0.9), 7.0)     # an arrow coming at you
			for j in 3:
				draw_line(c + Vector2(-150.0 + 150.0 * dash - j * 26.0, 60.0 + j * 16.0), c + Vector2(-190.0 + 150.0 * dash - j * 26.0, 60.0 + j * 16.0), Color(1, 1, 1, 0.5 * dash * (1.0 - dash) * 4.0 if real else 0.5 * dash), 5.0)
			if mode == "pc":
				_key(c + Vector2(0, -120), "SHIFT", 170.0)
			else:
				_button(c + Vector2(0, -110), 70.0, "DODGE", Color(1.0, 0.55, 0.3), fmod(t, 2.0) < 0.3)
			say = "DODGE: a quick dash"
			say2 = "into an arrow: you CATCH it"
		_text(Vector2(r.get_center().x, r.end.y - 92.0), say, 34, Color(INK, a), Art.BODY)
		_text(Vector2(r.get_center().x, r.end.y - 46.0), say2, 34, Color(INK, a), Art.BODY)
	_text(Vector2(960, 838), "One life a round. The last one standing wins it.", 40, Color(INK, a), Art.BODY)
	var more := "Pick your arrows up again. Grab the glowing orbs: they are power-ups."
	if real and Season.harvest():
		more = "Pick your arrows up again. Grab the glowing orbs. Catch the turkey!"
	_text(Vector2(960, 892), more, 34, Color(DIM, a), Art.BODY)
	var br := Rect2(710, 930, 500, 96)
	draw_style_box(Art.box(Color(1.0, 0.6, 0.12, a), Color(0.45, 0.2, 0.02, a), 20, 3, 9, Color(1.0, 0.7, 0.2, 0.35 * a), 16), br)
	_text(Vector2(960, 996), "GOT IT", 56, Color(0.13, 0.05, 0.0, a))

# p4.19: a plank to stand on: a wooden top with a dark lip, mid its centre, w wide.
func _floor(mid: Vector2, w: float) -> void:
	draw_style_box(Art.box(Color(0.42, 0.27, 0.15), Color(0.16, 0.09, 0.05), 6, 2, 6), Rect2(mid.x - w * 0.5, mid.y, w, 18))
	draw_rect(Rect2(mid.x - w * 0.5 + 6, mid.y + 3, w - 12, 2), Color(1, 0.9, 0.7, 0.25))

# p4.20 TONIGHT'S CHAMPIONS (the user picked it): who has won how many matches tonight,
# with rounds won and knockouts beside. The server counts these already (its numbers for
# tonight, by name: game_server.gd _stat) and sends the top of the list with the seats
# (the seats message's "champs": [name, matches won, rounds won, knockouts, a bot?]).
# The lobby's TONIGHT button opens this board over the lobby; a tap anywhere closes it.
# THE BIG SCREEN shows the same list in its lobby (lobby.gd _paint_tv calls rows()).
# Drawn on the lobby's 1920 x 1080 frame.
# p4.21 (polish "motion"): the board grows in; its rows slide in one after another, their
# numbers count up, and the crown drops onto the first name.
extends Control

const Art = preload("res://client/lobby_art.gd")
const Motion = preload("res://client/motion.gd")
const Xmas = preload("res://client/lobby_xmas.gd")   # p4.22: the Christmas dress: lights along the board's top, snow behind it
const UI_ICONS := preload("res://assets/ui_icons.png")   # cell 5: the painted crown
const CARD := Rect2(420, 110, 1080, 860)

var pal: Dictionary = Art.DRESSES["castle"]
var list: Array = []
var t := 0.0
var pane: Motion.Pane

func _init() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	pane = Motion.Pane.new(self, CARD.get_center(), 0.88)

func open(champs: Array) -> void:
	list = champs
	t = 0.0
	pane.open()
	queue_redraw()

func close() -> void:
	pane.close()

func _process(delta: float) -> void:
	if not visible:
		return
	var moving := pane.step(delta)
	if moving or t < 0.3 or (pane.live and t < 2.0) or Art.xmas():     # (the rows and their numbers take a moment longer; p4.22: the lights twinkle)
		t += delta
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not e.pressed and t > 0.25 and not pane.closing():
			close()

func _draw() -> void:
	var a := roundf(clampf(t / 0.15, 0.0, 1.0) * 8.0) / 8.0     # the fade in steps: lobby_art.gd keeps every box it makes
	if pane.live:
		a = 1.0
	draw_rect(Rect2(-2000, -1000, 5920, 3080), Color(0.02, 0.01, 0.04, 0.86 * a))
	var accent: Color = pal["accent"]
	if Art.xmas():
		Xmas.behind_panel(self, t, a)
	Art.panel(self, CARD, Color(pal["panel"], 0.985), accent, 30, Color(accent.r, accent.g, accent.b, 0.3), 28)
	if Art.xmas():
		Xmas.card_lights(self, t, CARD, a)
	Art.text(self, Art.DISPLAY, Vector2(CARD.position.x, CARD.position.y + 92.0), "TONIGHT'S CHAMPIONS", 72, pal["accent_hi"], 8, Color(0.03, 0.01, 0.05),
		HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x)
	rows(self, list, Rect2(CARD.position.x + 60.0, CARD.position.y + 150.0, CARD.size.x - 120.0, CARD.size.y - 250.0), pal, 8, t if pane.live else 99.0)
	draw_string(Art.BODY, Vector2(CARD.position.x, CARD.end.y - 44.0), "Tap anywhere to go back.", HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x, 26, Color(pal["dim"], 0.95))

# The list in a box: a heading line, then one row a name (the first row wears the crown).
# Static: THE BIG SCREEN's lobby draws it too.
# t (p4.21): seconds since the board opened: the rows slide in one after another and their
# numbers count up (99: everything in place, as THE BIG SCREEN shows it).
# bxf (p4.22): the draw transform the caller is under (THE BIG SCREEN shrinks the board): a long name is
# squeezed under it and it is put back after.
static func rows(c: CanvasItem, champs: Array, box: Rect2, p: Dictionary, most: int, t: float = 99.0, bxf: Transform2D = Transform2D.IDENTITY) -> void:
	var txt: Color = p["text"]
	var dim: Color = p["dim"]
	var x := box.position.x
	var cols := [box.size.x - 420.0, box.size.x - 250.0, box.size.x - 90.0]     # MATCHES, ROUNDS, KNOCKOUTS: their middles
	var heads := ["MATCHES", "ROUNDS", "KNOCKOUTS"]
	for i in 3:
		c.draw_string(Art.BODY, Vector2(x + cols[i] - 90.0, box.position.y + 26.0), heads[i], HORIZONTAL_ALIGNMENT_CENTER, 180.0, 22, Color(dim, 0.9))
	c.draw_rect(Rect2(x, box.position.y + 38.0, box.size.x, 2), Color(p["panel_edge"], 0.6))
	if champs.is_empty():
		c.draw_string(Art.BODY, Vector2(x, box.position.y + 120.0), "Nobody has won a match yet tonight. Be the first!", HORIZONTAL_ALIGNMENT_CENTER, box.size.x, 30, txt)
		return
	var n := mini(most, champs.size())
	var rh := minf(74.0, (box.size.y - 50.0) / n)
	var x0 := x
	for i in n:
		var row: Array = champs[i]
		var y := box.position.y + 50.0 + i * rh
		var top := i == 0 and int(row[1]) > 0
		var wait := 0.12 + 0.06 * i
		var rk := Motion.rise(t, wait, 0.32) if t < 9.0 else 1.0       # the row slides in from the left
		var ra := clampf(rk * 1.5, 0.0, 1.0)
		var up := Motion.ramp(t, wait + 0.12, 0.55) if t < 9.0 else 1.0   # its numbers count up
		if ra <= 0.0:
			continue
		x = x0 - (1.0 - rk) * 52.0      # (a short way: it stays inside the card)
		if i % 2 == 0:
			c.draw_rect(Rect2(x, y, box.size.x, rh - 4.0), Color(1, 1, 1, 0.04 * ra))
		var base := y + rh * 0.5 + 14.0
		c.draw_string(Art.DISPLAY, Vector2(x + 12.0, base), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(dim, 0.9 * ra))
		if top:
			# the crown drops onto the first name a moment after it, and settles with a bounce
			var ck := Motion.rise(t, wait + 0.3, 0.4) if t < 9.0 else 1.0
			if ck > 0.0:
				var cs := 48.0 * (0.4 + 0.6 * ck)
				c.draw_texture_rect_region(UI_ICONS, Rect2(x + 76.0 - cs * 0.5, y + rh * 0.5 - 2.0 - cs * 0.5 - (1.0 - ck) * 60.0, cs, cs),
					Rect2(5 * 128, 0, 128, 128), Color(1, 1, 1, clampf(ck * 2.0, 0.0, 1.0)))
		var name := str(row[0]) + ("  (a bot)" if row.size() > 4 and bool(row[4]) else "")
		var name_col: Color = Color(p["accent_hi"]) if top else txt
		# p4.22: a name too long for its room is squeezed sideways (the same letters, never a new size), not cut:
		# FRUITCAKE, CORNBREAD and CRANBERRY with "(a bot)" lost their ends
		var room: float = cols[0] - 220.0
		var tw := Art.DISPLAY.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x + 10.0
		var at := Vector2(x + 112.0, base)
		if tw > room:
			var k := room / tw
			c.draw_set_transform_matrix(bxf * Transform2D(0.0, Vector2(k, 1.0), 0.0, Vector2(at.x * (1.0 - k), 0.0)))
		Art.text(c, Art.DISPLAY, at, name, 40, Color(name_col, ra), 5, Color(0.03, 0.01, 0.05), HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
		if tw > room:
			c.draw_set_transform_matrix(bxf)
		for k in 3:
			var num_col: Color = Color(p["accent_hi"]) if k == 0 else Color(txt, 0.9)
			c.draw_string(Art.DISPLAY, Vector2(x + cols[k] - 90.0, base), str(int(roundf(int(row[1 + k]) * up))), HORIZONTAL_ALIGNMENT_CENTER, 180.0, 40,
				Color(num_col, num_col.a * ra))

# p4.20 TONIGHT'S CHAMPIONS (the user picked it): who has won how many matches tonight,
# with rounds won and knockouts beside. The server counts these already (its numbers for
# tonight, by name: game_server.gd _stat) and sends the top of the list with the seats
# (the seats message's "champs": [name, matches won, rounds won, knockouts, a bot?]).
# The lobby's TONIGHT button opens this board over the lobby; a tap anywhere closes it.
# THE BIG SCREEN shows the same list in its lobby (lobby.gd _paint_tv calls rows()).
# Drawn on the lobby's 1920 x 1080 frame.
extends Control

const Art = preload("res://client/lobby_art.gd")
const UI_ICONS := preload("res://assets/ui_icons.png")   # cell 5: the painted crown
const CARD := Rect2(420, 110, 1080, 860)

var pal: Dictionary = Art.DRESSES["castle"]
var list: Array = []
var t := 0.0

func _init() -> void:
	size = Vector2(1920, 1080)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

func open(champs: Array) -> void:
	list = champs
	t = 0.0
	visible = true
	queue_redraw()

func close() -> void:
	visible = false

func _process(delta: float) -> void:
	if visible and t < 0.3:
		t += delta
		queue_redraw()

func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		if not e.pressed and t > 0.25:
			close()

func _draw() -> void:
	var a := roundf(clampf(t / 0.15, 0.0, 1.0) * 8.0) / 8.0     # the fade in steps: lobby_art.gd keeps every box it makes
	draw_rect(Rect2(-2000, -1000, 5920, 3080), Color(0.02, 0.01, 0.04, 0.86 * a))
	var accent: Color = pal["accent"]
	Art.panel(self, CARD, Color(pal["panel"], 0.985), accent, 30, Color(accent.r, accent.g, accent.b, 0.3), 28)
	Art.text(self, Art.DISPLAY, Vector2(CARD.position.x, CARD.position.y + 92.0), "TONIGHT'S CHAMPIONS", 72, pal["accent_hi"], 8, Color(0.03, 0.01, 0.05),
		HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x)
	rows(self, list, Rect2(CARD.position.x + 60.0, CARD.position.y + 150.0, CARD.size.x - 120.0, CARD.size.y - 250.0), pal, 8)
	draw_string(Art.BODY, Vector2(CARD.position.x, CARD.end.y - 44.0), "Tap anywhere to go back.", HORIZONTAL_ALIGNMENT_CENTER, CARD.size.x, 26, Color(pal["dim"], 0.95))

# The list in a box: a heading line, then one row a name (the first row wears the crown).
# Static: THE BIG SCREEN's lobby draws it too.
static func rows(c: CanvasItem, champs: Array, box: Rect2, p: Dictionary, most: int) -> void:
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
	for i in n:
		var row: Array = champs[i]
		var y := box.position.y + 50.0 + i * rh
		var top := i == 0 and int(row[1]) > 0
		if i % 2 == 0:
			c.draw_rect(Rect2(x, y, box.size.x, rh - 4.0), Color(1, 1, 1, 0.04))
		var base := y + rh * 0.5 + 14.0
		c.draw_string(Art.DISPLAY, Vector2(x + 12.0, base), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 40, Color(dim, 0.9))
		if top:
			c.draw_texture_rect_region(UI_ICONS, Rect2(x + 52.0, y + rh * 0.5 - 26.0, 48, 48), Rect2(5 * 128, 0, 128, 128))
		var name := str(row[0]) + ("  (a bot)" if row.size() > 4 and bool(row[4]) else "")
		Art.text(c, Art.DISPLAY, Vector2(x + 112.0, base), name, 40, Color(p["accent_hi"]) if top else txt, 5, Color(0.03, 0.01, 0.05),
			HORIZONTAL_ALIGNMENT_LEFT, cols[0] - 220.0, false)
		for k in 3:
			c.draw_string(Art.DISPLAY, Vector2(x + cols[k] - 90.0, base), str(int(row[1 + k])), HORIZONTAL_ALIGNMENT_CENTER, 180.0, 40,
				Color(p["accent_hi"]) if k == 0 else Color(txt, 0.9))

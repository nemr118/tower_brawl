# The HUD for 8 and the banners, drawn on a 1920 x 1080 design scaled to the
# window's height and centred. A card per seat along the top: the colour, the
# name, the arrows left, the points towards the goal, a crown on the leader,
# a white frame on yours, grey when dead, "next round" for a late joiner.
# The banners: ROUND N, FIGHT!, who won the round, who won the match, and the
# draw clock in a round's last 10 seconds.
extends CanvasLayer

const P = preload("res://sim/proto.gd")
const World = preload("res://client/world.gd")
const FIGHT_S := 0.9
const CARD_W := 210.0
const CARD_STEP := 228.0
const CARD_X := 48.0
const CARD_Y := 10.0
const CARD_H := 78.0
var CROWN := PackedVector2Array([Vector2(0, 16), Vector2(0, 3), Vector2(6, 9), Vector2(12, 0), Vector2(18, 9), Vector2(24, 3), Vector2(24, 16)])

var seats: Array = []
var snap := {}
var my_seat := -1
var goal := 0
var phase := -1
var round_no := 0
var fight_t := 0.0
var banner := ""
var banner_color := Color.WHITE
var info_text := ""
var show_info := false
var hidden := true
var canvas := _Canvas.new()

class _Canvas extends Control:
	var hud
	func _draw() -> void:
		if hud != null:
			hud._paint(self)

func _init() -> void:
	layer = 10
	canvas.hud = self
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = Vector2(1920, 1080)
	add_child(canvas)

func fit(win: Vector2) -> void:
	var k := win.y / 1080.0
	scale = Vector2.ONE * k
	offset = Vector2((win.x - 1920.0 * k) * 0.5, 0.0)

func on_phase(ph: int, rnd: int) -> void:
	phase = ph
	round_no = rnd
	if ph == P.PH_PLAY:
		fight_t = FIGHT_S
	if ph == P.PH_ROUND_START or ph == P.PH_LOBBY:
		banner = ""

func round_end(m: Dictionary) -> void:
	if bool(m.get("draw", false)):
		banner = "DRAW"
		banner_color = Color(0.8, 0.8, 0.8)
	else:
		var w := int(m.get("winner", 0))
		banner = "%s WINS THE ROUND" % str(m.get("name", "")).to_upper()
		banner_color = World.TEAM[w % 8]

func match_end(m: Dictionary) -> void:
	var w := int(m.get("winner", 0))
	banner = "%s WINS THE MATCH" % str(m.get("name", "")).to_upper()
	banner_color = World.TEAM[w % 8]

func update(seats_msg: Dictionary, s: Dictionary, seat: int, delta: float, fps: float, rtt: int, info: bool, lobby_shown: bool) -> void:
	if not seats_msg.is_empty():
		seats = seats_msg["seats"]
		goal = int(seats_msg.get("goal", 0))
	snap = s
	my_seat = seat
	hidden = lobby_shown
	fight_t = maxf(0.0, fight_t - delta)
	show_info = info
	info_text = "%s · %.0f fps · ping %d ms" % [P.VERSION, fps, rtt]
	canvas.queue_redraw()

# The seats with the most points (1 or more): they wear the crown.
func _leaders() -> Array:
	var best := 0
	var out: Array = []
	for st in seats:
		if int(st.get("kind", 0)) != 0:
			best = maxi(best, int(st.get("points", 0)))
	if best <= 0:
		return out
	for st in seats:
		if int(st.get("kind", 0)) != 0 and int(st.get("points", 0)) == best:
			out.append(int(st["i"]))
	return out

func _paint(c: Control) -> void:
	var font := ThemeDB.fallback_font
	if show_info:
		c.draw_string_outline(font, Vector2(16, 1066), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 4, Color.BLACK)
		c.draw_string(font, Vector2(16, 1066), info_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.8))
	if hidden or phase <= P.PH_COUNTDOWN:
		return
	var by_id: Dictionary = snap.get("by_id", {})
	var leaders := _leaders()
	var winner := int(snap.get("winner", P.NO_ONE))
	for st in seats:
		var i := int(st["i"])
		var kind := int(st.get("kind", 0))
		if kind == 0:
			continue
		var x := CARD_X + i * CARD_STEP
		var col: Color = World.TEAM[i % 8]
		var f: Dictionary = by_id.get(i, {})
		var dead: bool = not f.is_empty() and int(f["state"]) == P.F_DEAD
		var waiting := f.is_empty()
		var away: bool = not waiting and (int(f["flags2"]) & P.F2_AWAY) != 0
		c.draw_rect(Rect2(x, CARD_Y, CARD_W, CARD_H), Color(0.04, 0.04, 0.07, 0.78))
		c.draw_rect(Rect2(x, CARD_Y, CARD_W, 9), col.darkened(0.55) if dead else col)
		if i == my_seat:
			c.draw_rect(Rect2(x, CARD_Y, CARD_W, CARD_H), Color(1, 1, 1, 0.95), false, 3.0)
		var name_col := Color(0.55, 0.55, 0.6) if dead else Color.WHITE
		c.draw_string(font, Vector2(x + 10, CARD_Y + 38), str(st.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 20, 25, name_col)
		if waiting:
			c.draw_string(font, Vector2(x + 10, CARD_Y + 66), "next round", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.7, 0.7, 0.75))
		elif away:
			c.draw_string(font, Vector2(x + 10, CARD_Y + 66), "away (a bot plays)", HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(0.9, 0.7, 0.4))
		else:
			var arrows := int(f["arrows"])
			for k in 6:
				var ax := x + 12 + k * 17.0
				var ay := CARD_Y + 60.0
				var a_col := Color(1, 0.95, 0.75) if k < arrows else Color(1, 1, 1, 0.14)
				c.draw_rect(Rect2(ax, ay - 2, 10, 4), a_col)
				c.draw_colored_polygon(PackedVector2Array([Vector2(ax + 10, ay - 5), Vector2(ax + 15, ay), Vector2(ax + 10, ay + 5)]), a_col)
		if not waiting:
			var points := int(st.get("points", 0))
			for k in goal:
				var px := x + CARD_W - 14 - k * 17.0
				var p_col := col if k < points else Color(1, 1, 1, 0.16)
				c.draw_circle(Vector2(px, CARD_Y + 60), 6.0, p_col)
		if i in leaders or (phase == P.PH_MATCH_END and i == winner):
			var crown := PackedVector2Array()
			for v in CROWN:
				crown.append(v + Vector2(x + CARD_W - 32, CARD_Y + 14))
			c.draw_colored_polygon(crown, Color(1.0, 0.82, 0.2))
		if dead:
			c.draw_rect(Rect2(x, CARD_Y, CARD_W, CARD_H), Color(0, 0, 0, 0.35))
	var left := int(snap.get("left", 0))
	if phase == P.PH_ROUND_START:
		_banner(c, font, "ROUND %d" % round_no, 110, Color.WHITE, 440)
		_banner(c, font, "GET READY", 44, Color(0.85, 0.85, 0.9), 520)
	elif phase == P.PH_PLAY:
		if fight_t > 0.0:
			_banner(c, font, "FIGHT!", 150, Color(1.0, 0.3, 0.1), 460)
		if left > 0 and left <= 600:
			_banner(c, font, "DRAW IN %d" % ceili(left / 60.0), 40, Color(1.0, 0.85, 0.5), 1000)
	elif phase == P.PH_ROUND_END and banner != "":
		_banner(c, font, banner, 78, banner_color, 440)
	elif phase == P.PH_MATCH_END and banner != "":
		_banner(c, font, banner, 90, banner_color, 440)
		_banner(c, font, "THE LOBBY OPENS IN %d" % ceili(left / 60.0), 40, Color(0.85, 0.85, 0.9), 520)

func _banner(c: Control, font: Font, text: String, size: int, col: Color, y: float) -> void:
	c.draw_string_outline(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, size, maxi(4, size / 10), Color.BLACK)
	c.draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, size, col)

# The HUD for 8 and the banners, drawn on a 1920 x 1080 design scaled to the
# window's height and centred. A card per seat along the top: the colour, the
# name, the arrows left, the points towards the goal, a crown on the leader,
# a white frame on yours, grey when dead, "next round" for a late joiner.
# The banners: ROUND N, FIGHT!, who won the round, who won the match, and the
# draw clock in a round's last 10 seconds.
# p4.9: under each card, chips for its power-ups (a BIG one with its seconds left);
# when you take one, a banner in the middle: its picture, its name, what it does.
extends CanvasLayer

const P = preload("res://sim/proto.gd")
const World = preload("res://client/world.gd")
const LevelScript = preload("res://sim/level.gd")
const PV = preload("res://client/powers_view.gd")
const BANNER_S := 3.2
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
var note := ""                 # a short line at the bottom (the look stepped down), for note_t seconds
var note_t := 0.0
var hidden := true
var banner_kind := 0           # p4.9: the power-up you just took (its banner), for banner_t seconds
var banner_t := 0.0
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

# p4.9: you took a power-up: its banner in the middle for BANNER_S.
func power_banner(kind: int) -> void:
	banner_kind = kind
	banner_t = BANNER_S

# A short line at the bottom for secs seconds (P2: the look stepped down).
func say(text: String, secs: float) -> void:
	note = text
	note_t = secs

func update(seats_msg: Dictionary, s: Dictionary, seat: int, delta: float, fps: float, rtt: int, info: bool, lobby_shown: bool) -> void:
	if not seats_msg.is_empty():
		seats = seats_msg["seats"]
		goal = int(seats_msg.get("goal", 0))
	snap = s
	my_seat = seat
	hidden = lobby_shown
	fight_t = maxf(0.0, fight_t - delta)
	note_t = maxf(0.0, note_t - delta)
	banner_t = maxf(0.0, banner_t - delta)
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
	if note_t > 0.0:
		var a := minf(1.0, note_t * 2.0)
		c.draw_string_outline(font, Vector2(0, 1030), note, HORIZONTAL_ALIGNMENT_CENTER, 1920, 30, 5, Color(0, 0, 0, a))
		c.draw_string(font, Vector2(0, 1030), note, HORIZONTAL_ALIGNMENT_CENTER, 1920, 30, Color(1, 0.9, 0.6, a))
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
		var pw: Dictionary = snap.get("powers", {}).get(i, {})
		if not pw.is_empty() and not waiting:
			_chips(c, font, x, pw)
	var left := int(snap.get("left", 0))
	if phase == P.PH_ROUND_START:
		_banner(c, font, "ROUND %d" % round_no, 110, Color.WHITE, 440)
		_banner(c, font, LevelScript.name_of(int(snap.get("arena", 0))), 52, Color(1.0, 0.85, 0.5), 522)
		_banner(c, font, "GET READY", 36, Color(0.85, 0.85, 0.9), 590)
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
	if banner_t > 0.0 and banner_kind > 0:
		_power_banner(c, font)

# The power-up chips under a seat's card: its arrow kind, SHIELD, INFINITE, FLY,
# BIG, then a BIG power-up with its seconds left, and FROZEN or SLOW.
func _chips(c: Control, font: Font, x: float, pw: Dictionary) -> void:
	var bits: int = pw["bits"]
	var kind: int = pw["kind"]
	var left := ceili(float(pw["left"]))
	var list: Array = []
	if kind > 0:
		list.append([P.PU_SHORT[kind], PV.COLORS[kind]])
	for pair in [[P.PW_SHIELD, P.PU_SHIELD], [P.PW_INF, P.PU_INF], [P.PW_FLY, P.PU_FLY], [P.PW_BIG, P.PU_BIG]]:
		if bits & pair[0]:
			list.append([P.PU_SHORT[pair[1]], PV.COLORS[pair[1]]])
	for pair in [[P.PW_INVIS_ON, P.PU_INVIS], [P.PW_SPEED, P.PU_SPEED], [P.PW_UMBRELLA, P.PU_RAIN], [P.PW_SPIKES, P.PU_SPIKES]]:
		if bits & pair[0]:
			list.append(["%s %d" % [P.PU_SHORT[pair[1]], left], PV.COLORS[pair[1]]])
	if bits & P.PW_FROZEN:
		list.append(["FROZEN", PV.COLORS[P.PU_FREEZE]])
	elif bits & P.PW_SLOW:
		list.append(["SLOW", PV.COLORS[P.PU_RAIN]])
	var cx := x
	var cy := CARD_Y + CARD_H + 4.0
	for item in list:
		var w := font.get_string_size(item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x + 12.0
		if cx + w > x + CARD_W + 2.0:
			cx = x
			cy += 25.0
		var col: Color = item[1]
		c.draw_rect(Rect2(cx, cy, w, 22), Color(col.darkened(0.55), 0.88))
		c.draw_rect(Rect2(cx, cy, w, 22), Color(col, 0.95), false, 2.0)
		c.draw_string(font, Vector2(cx + 6, cy + 17), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col.lerp(Color.WHITE, 0.45))
		cx += w + 4.0

# The banner for the power-up you took: a card in the middle with its picture,
# its name and what it does; it pops in, stays, and fades.
func _power_banner(c: Control, font: Font) -> void:
	var k := banner_t / BANNER_S
	var a := clampf(banner_t / 0.5, 0.0, 1.0)
	var pop := 1.0 + 0.25 * clampf((k - 0.85) / 0.15, 0.0, 1.0)
	var col: Color = PV.COLORS.get(banner_kind, Color.WHITE)
	var big := banner_kind >= P.PU_CATS
	var name: String = ("BIG: " if big else "") + str(P.PU_NAMES.get(banner_kind, ""))
	var help: String = P.PU_HELP.get(banner_kind, "")
	var w := maxf(font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 60).x, font.get_string_size(help, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x) + 190.0
	var r := Rect2(960.0 - w / 2.0, 250.0, w, 150.0)
	c.draw_rect(r, Color(0.03, 0.03, 0.07, 0.82 * a))
	c.draw_rect(r, Color(PV.GOLD if big else col, a), false, 4.0)
	var ic := Vector2(r.position.x + 80.0, r.position.y + 75.0)
	c.draw_circle(ic, 50.0 * pop, Color(col.darkened(0.2), a))
	c.draw_arc(ic, 50.0 * pop, 0.0, TAU, 32, Color(1, 1, 1, a), 3.0)
	PV.draw_icon(c, ic, banner_kind, 31.0 * pop, Color(0.08, 0.06, 0.12, a), 3.2 - banner_t)
	c.draw_string_outline(font, Vector2(r.position.x + 150.0, r.position.y + 72.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, 7, Color(0, 0, 0, a))
	c.draw_string(font, Vector2(r.position.x + 150.0, r.position.y + 72.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 60, Color(col.lerp(Color.WHITE, 0.35), a))
	c.draw_string(font, Vector2(r.position.x + 150.0, r.position.y + 120.0), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.95, 0.95, 1.0, a))

func _banner(c: Control, font: Font, text: String, size: int, col: Color, y: float) -> void:
	c.draw_string_outline(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, size, maxi(4, size / 10), Color.BLACK)
	c.draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, size, col)

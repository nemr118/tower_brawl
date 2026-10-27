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
const Winner = preload("res://client/winner_view.gd")   # the winner's screen (2026-10-25)
const Banner = preload("res://client/hud_banner.gd")    # p4.17: the round's big words in the lobby title's style
const Art = preload("res://client/lobby_art.gd")
const Polish = preload("res://client/polish.gd")
const BANNER_S := 2.6
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
var awards: Array = []         # p4.11: the match's awards (match_end), on the winner's screen
var winner_seat := 0           # the match's winner and name (match_end), for the winner's screen
var winner_name := ""
var end_t := 0.0               # seconds since the winner's screen came up
var banner_kind := 0           # p4.9: the power-up you just took (its banner), for banner_t seconds
var banner_icon := 0           # the picture on that banner (banner_kind's, or a candy trick's badge)
var banner_name := ""          # p4.12: a name and a tip in place of the power-up's own (the tricks)
var banner_tip := ""
var banner_t := 0.0
var canvas := _Canvas.new()

class _Canvas extends Control:
	var hud
	func _draw() -> void:
		if hud != null:
			hud._paint(self)

var banner_fx = Banner.new()
var title_pal: Dictionary = {}
var round_name := ""               # p4.17: the round's winner (the big line) and a draw
var round_draw := false
var view := Rect2(0, 0, 1920, 1080)   # p4.17: the part of the 1920 x 1080 design the window shows (the winner's backdrop fills it)

func _init() -> void:
	layer = 10
	canvas.hud = self
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.size = Vector2(1920, 1080)
	add_child(canvas)
	add_child(banner_fx)            # p4.17, over the canvas
	title_pal = Art.DRESSES[Art.pick_dress()]

func fit(win: Vector2) -> void:
	var k := win.y / 1080.0
	scale = Vector2.ONE * k
	offset = Vector2((win.x - 1920.0 * k) * 0.5, 0.0)
	view = Rect2(960.0 - win.x / (2.0 * k), 0.0, win.x / k, 1080.0)

func on_phase(ph: int, rnd: int) -> void:
	phase = ph
	round_no = rnd
	if ph == P.PH_PLAY:
		fight_t = FIGHT_S
	if ph == P.PH_ROUND_START or ph == P.PH_LOBBY:
		banner = ""

func round_end(m: Dictionary) -> void:
	round_draw = bool(m.get("draw", false))
	round_name = str(m.get("name", "")).to_upper()
	if bool(m.get("draw", false)):
		banner = "DRAW"
		banner_color = Color(0.8, 0.8, 0.8)
	else:
		var w := int(m.get("winner", 0))
		banner = "%s WINS THE ROUND" % str(m.get("name", "")).to_upper()
		banner_color = World.TEAM[w % 8]

func match_end(m: Dictionary) -> void:
	awards = m.get("awards", [])
	var w := int(m.get("winner", 0))
	banner = "%s WINS THE MATCH" % str(m.get("name", "")).to_upper()
	banner_color = World.TEAM[w % 8]
	winner_seat = w
	winner_name = str(m.get("name", ""))
	end_t = 0.0

# p4.9: you took a power-up: its banner for BANNER_S (p4.12: a small card under the
# cards at the top; name and tip: words in place of the power-up's own, for a trick).
func power_banner(kind: int, name := "", tip := "", icon := -1) -> void:
	banner_kind = kind
	banner_icon = icon if icon >= 0 else kind   # 2026-10-26: a candy trick's own badge (powers_view.gd TRICK_ICON)
	banner_name = name
	banner_tip = tip
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
	if int(s.get("phase", -1)) == P.PH_ROUND_START and note.begins_with("GHOST"):
		note_t = 0.0      # p4.13: a ghost's tip is over when the next round starts
	banner_t = maxf(0.0, banner_t - delta)
	end_t += delta
	show_info = info
	info_text = "%s · %.0f fps · ping %d ms" % [P.VERSION, fps, rtt]
	canvas.queue_redraw()
	banner_fx.visible = not lobby_shown and Polish.on("banners2")
	if banner_fx.visible:
		var sp := _banner_spec()
		banner_fx.set_banner(sp[0], sp[1], sp[2], delta)

# p4.17 (polish "banners2"): the round's words for hud_banner.gd: the big line
# [text, size, top colour, bottom colour, rim colour, y], the ribbon's words, the small lines.
func _banner_spec() -> Array:
	var main: Array = []
	var rib := ""
	var extra: Array = []
	var left := int(snap.get("left", 0))
	if phase == P.PH_ROUND_START:
		main = ["ROUND %d" % round_no, 124, title_pal["logo_top"], title_pal["logo_bot"], title_pal["logo_rim"], 430]
		rib = LevelScript.name_of(int(snap.get("arena", 0)))
		extra.append(["GET READY", 36, Color(0.88, 0.88, 0.95), 600])
	elif phase == P.PH_PLAY:
		if fight_t > 0.0:
			main = ["FIGHT!", 160, Color(1.0, 0.93, 0.5), Color(1.0, 0.22, 0.06), Color(0.45, 0.04, 0.02), 470]
		if left > 0 and left <= 600:
			extra.append(["DRAW IN %d" % ceili(left / 60.0), 40, Color(1.0, 0.85, 0.5), 1000])
	elif phase == P.PH_ROUND_END and banner != "":
		var col: Color = banner_color
		if round_draw:
			main = ["DRAW", 112, Color(0.95, 0.95, 1.0), Color(0.62, 0.62, 0.7), Color(0.25, 0.25, 0.3), 430]
		else:
			main = [round_name, 112, col.lerp(Color.WHITE, 0.55), col, col.darkened(0.6), 430]
			rib = "WINS THE ROUND"
	return [main, rib, extra]

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
	if Polish.on("banners2") and phase != P.PH_MATCH_END:
		pass                              # p4.17: hud_banner.gd draws them
	elif phase == P.PH_ROUND_START:
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
		Winner.paint(c, end_t, winner_seat, winner_name, awards, left, view)   # client/winner_view.gd (2026-10-25)
	if banner_t > 0.0 and banner_kind > 0:
		_power_banner(c, font)

# The power-up chips under a seat's card: its arrow kind, SHIELD, INFINITE, FLY,
# BIG, then a BIG power-up with its seconds left, and FROZEN or SLOW.
func _chips(c: Control, font: Font, x: float, pw: Dictionary) -> void:
	var bits: int = pw["bits"]
	var kind: int = pw["kind"]
	var left := ceili(float(pw["left"]))
	var list: Array = []
	var pk := kind if kind <= P.PU_SMOKE else (P.PU_PUMPKIN if kind == P.A_PUMPKIN else 0)   # p4.12: arrow kind 5 is PUMPKIN BOMBS
	if pk > 0:
		list.append([P.PU_SHORT[pk], PV.COLORS[pk]])
	for pair in [[P.PW_SHIELD, P.PU_SHIELD], [P.PW_INF, P.PU_INF], [P.PW_FLY, P.PU_FLY], [P.PW_BIG, P.PU_BIG]]:
		if bits & pair[0]:
			list.append([P.PU_SHORT[pair[1]], PV.COLORS[pair[1]]])
	for pair in [[P.PW_INVIS_ON, P.PU_INVIS], [P.PW_SPEED, P.PU_SPEED], [P.PW_UMBRELLA, P.PU_RAIN], [P.PW_SPIKES, P.PU_SPIKES]]:
		if bits & pair[0]:
			list.append(["%s %d" % [P.PU_SHORT[pair[1]], left], PV.COLORS[pair[1]]])
	if pw.get("swarm", false):
		list.append(["BATS %d" % left, PV.COLORS[P.PU_BATS]])
	if (int(pw.get("mask", 0)) & 1) != 0:
		list.append(["GHOSTFACE" if (int(pw["mask"]) & 2) == 0 else "DOWN!", PV.COLORS[P.PU_MASK]])
	for tr in [[P.PW_PUMPKIN, "PUMPKIN!"], [P.PW_BACKWARDS, "BACKWARDS"], [P.PW_TINY, "TINY"]]:
		if bits & tr[0]:
			list.append([tr[1], PV.COLORS[P.PU_TRICK]])
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

# The card for the power-up you took (p4.12: small, under the player cards, so it hides
# little of the fight): its picture, its short name and a tip of two or three words; it
# pops in, stays, and fades.
func _power_banner(c: Control, font: Font) -> void:
	var k := banner_t / BANNER_S
	var a := clampf(banner_t / 0.4, 0.0, 1.0)
	var pop := 1.0 + 0.3 * clampf((k - 0.88) / 0.12, 0.0, 1.0)
	var col: Color = PV.COLORS.get(banner_kind, Color.WHITE)
	var big := P.is_big(banner_kind)
	var name: String = banner_name if banner_name != "" else str(P.PU_SHORT.get(banner_kind, ""))
	var tip: String = banner_tip if banner_tip != "" else str(P.PU_TIP.get(banner_kind, ""))
	var nw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var tw := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x if tip != "" else 0.0
	var w := 64.0 + nw + (14.0 + tw if tip != "" else 0.0) + 20.0
	var r := Rect2(960.0 - w / 2.0, 128.0, w, 50.0)
	c.draw_rect(r, Color(0.03, 0.03, 0.07, 0.72 * a))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 3.0)), Color(PV.GOLD if big else col, a))   # a coloured top edge
	var ic := Vector2(r.position.x + 29.0, r.position.y + 26.0)
	c.draw_circle(ic, 19.0 * pop, Color(PV.disc(col), a))
	c.draw_arc(ic, 19.0 * pop, 0.0, TAU, 24, Color(PV.GOLD if big else Color.WHITE, a), 2.0)
	PV.draw_icon(c, ic, banner_icon, 12.0 * pop, Color(0.08, 0.06, 0.12, a), BANNER_S - banner_t)
	var x := r.position.x + 58.0
	c.draw_string_outline(font, Vector2(x, r.position.y + 36.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, 5, Color(0, 0, 0, a))
	c.draw_string(font, Vector2(x, r.position.y + 36.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(col.lerp(Color.WHITE, 0.35), a))
	if tip != "":
		c.draw_string(font, Vector2(x + nw + 14.0, r.position.y + 34.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.86, 0.88, 0.96, 0.9 * a))

func _banner(c: Control, font: Font, text: String, size: int, col: Color, y: float) -> void:
	c.draw_string_outline(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, size, maxi(4, size / 10), Color.BLACK)
	c.draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, 1920, size, col)

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
const Season = preload("res://client/season.gd")        # p4.18: the season's names
const BANNER_S := 2.6
const FIGHT_S := 0.9
const CARD_W := 210.0
const CARD_STEP := 228.0
const CARD_X := 48.0
const CARD_Y := 10.0
const CARD_H := 78.0
const UI_ICONS := preload("res://assets/ui_icons.png")   # p4.19: the painted crown, cell 5 (lobby.gd IC_CROWN)
const HEAD_SRC := Rect2(47, 27, 38, 38)   # p4.19: the hooded head in a fighter sheet's first frame (128 px cells)
# p4.19: a silly line under a round's winner, by the season (the user: "a fun, balanced, silly game").
# Every screen shows the same one: it is picked from the round's number and the winner's seat.
const CHEERS := {
	"harvest": ["GOBBLE GOBBLE!", "PASS THE GRAVY!", "SECOND HELPINGS!", "SAVE ROOM FOR PIE!", "WHO WANTS LEFTOVERS?", "STUFFED!",
		"THAT'S THE WISHBONE!", "TOP OF THE PECKING ORDER!", "MORE MASHED POTATOES!", "NO NAP FOR YOU!"],
	"halloween": ["SPOOKY!", "TRICK... AND TREAT!", "BOO-YAH!", "WHAT A SCREAM!", "FANG-TASTIC!", "NO BONES ABOUT IT!"],
	"": ["BULLSEYE!", "NOT A SCRATCH!", "WHO'S NEXT?", "TOO EASY!", "WHAT A SHOT!", "STILL STANDING!"],
}
const DRAW_LINES := {"harvest": "EVERYBODY NAPS AFTER DINNER", "halloween": "NOBODY GETS THE CANDY", "": "NOBODY LEFT STANDING"}
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
var round_winner := 0              # p4.19: the round winner's seat (it picks the silly line)
var gains: Array = []              # p4.20 (polish "juice"): [seat, seconds since the round was called, its points then]: a +1 flies to the card, the pip pops
const GAIN_FLY_S := 0.55           # the +1's flight from the banner to the card
const GAIN_S := 1.1                # the flight and the pip's pop
var silly := 0                     # p4.20: this round's surprise for everyone (the seats message; proto.gd SILLY_*)
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
		round_winner = w
		if Polish.on("juice") and not hidden:     # p4.20: the +1 starts for the winner's card as the round is called
			gains.append([w, 0.0, _points_of(w)])
		banner = "%s WINS THE ROUND" % str(m.get("name", "")).to_upper()
		banner_color = World.TEAM[w % 8]

# p4.18: the server's season: ROUND N wears its title colours.
func set_season(season: String) -> void:
	title_pal = Art.DRESSES[Art.dress_for(season)]

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
		silly = int(seats_msg.get("silly", 0))
	snap = s
	my_seat = seat
	hidden = lobby_shown
	fight_t = maxf(0.0, fight_t - delta)
	for g in gains:
		g[1] += delta
	# a +1 is over once its pip has popped and the server's point has come (or after 4 s: no point came)
	gains = gains.filter(func(g): return g[1] < GAIN_S or (g[1] < 4.0 and _points_of(int(g[0])) <= int(g[2])))
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
		if silly > 0 and P.silly_name(silly, Season.now) != "":     # p4.20: a silly round says what it is
			rib = P.silly_name(silly, Season.now)
			extra.append(["SILLY ROUND", 52, Color(1.0, 0.85, 0.3), 616])
		else:
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
			if Polish.on("cheers"):
				extra.append([str(DRAW_LINES.get(Season.now, DRAW_LINES[""])), 36, Color(0.88, 0.88, 0.95), 520])
		else:
			main = [round_name, 112, col.lerp(Color.WHITE, 0.55), col, col.darkened(0.6), 430]
			rib = "WINS THE ROUND"
			if Polish.on("cheers"):
				var list: Array = CHEERS.get(Season.now, CHEERS[""])
				extra.append([str(list[(round_no * 7 + round_winner * 3) % list.size()]), 36, Color(1.0, 0.92, 0.6), 640])
	return [main, rib, extra]

# p4.20: the seat alone in the lead (-1: nobody leads, or two share it): it wears a crown in the arena.
func sole_leader() -> int:
	var l := _leaders()
	return int(l[0]) if l.size() == 1 else -1

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
	var new_look := Polish.on("hud2")
	if note_t > 0.0 and new_look:
		_note_pill(c)
	elif note_t > 0.0:
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
		if new_look:
			_card2(c, st, f, x, i in leaders or (phase == P.PH_MATCH_END and i == winner))
			continue
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
	for g in gains:               # p4.20: the +1 on its way from the banner to the winner's card
		if new_look and float(g[1]) < GAIN_FLY_S:
			_gain_fly(c, int(g[0]), float(g[1]) / GAIN_FLY_S)
	if silly > 0 and phase == P.PH_PLAY and fight_t <= 0.0:     # p4.20: the silly round's name stays up, small
		_silly_pill(c)
	if banner_t > 0.0 and banner_kind > 0:
		if new_look:
			_power_card2(c)
		else:
			_power_banner(c, font)

# The power-up chips under a seat's card: its arrow kind, SHIELD, INFINITE, FLY,
# BIG, then a BIG power-up with its seconds left, and FROZEN or SLOW.
func _chips(c: Control, font: Font, x: float, pw: Dictionary) -> void:
	var bits: int = pw["bits"]
	var kind: int = pw["kind"]
	var left := ceili(float(pw["left"]))
	var list: Array = []
	var sn: String = Season.now      # p4.18: the season's names (POPCORN, CROWS, BIG TURKEY, the tricks)
	var pk := PV.arrow_power(kind)   # the power-up an arrow kind came from (p4.12 PUMPKIN BOMBS, p4.18 PIE)
	if pk > 0:
		list.append([P.pu_short(pk, sn), PV.COLORS[pk]])
	for pair in [[P.PW_SHIELD, P.PU_SHIELD], [P.PW_INF, P.PU_INF], [P.PW_FLY, P.PU_FLY], [P.PW_BIG, P.PU_BIG]]:
		if bits & pair[0]:
			list.append([P.pu_short(pair[1], sn), PV.COLORS[pair[1]]])
	for pair in [[P.PW_INVIS_ON, P.PU_INVIS], [P.PW_SPEED, P.PU_SPEED], [P.PW_UMBRELLA, P.PU_RAIN], [P.PW_SPIKES, P.PU_SPIKES]]:
		if bits & pair[0]:
			list.append(["%s %d" % [P.pu_short(pair[1], sn), left], PV.COLORS[pair[1]]])
	if pw.get("swarm", false):
		list.append(["%s %d" % [P.pu_short(P.PU_BATS, sn), left], PV.COLORS[P.PU_BATS]])
	if (int(pw.get("mask", 0)) & 1) != 0:
		list.append([P.pu_short(P.PU_MASK, sn) if (int(pw["mask"]) & 2) == 0 else "DOWN!", PV.COLORS[P.PU_MASK]])
	var tricks: Array = ["TURKEY!", "DIZZY", "PEA-SIZED"] if sn == "harvest" else ["PUMPKIN!", "BACKWARDS", "TINY"]
	for tr in [[P.PW_PUMPKIN, tricks[0]], [P.PW_BACKWARDS, tricks[1]], [P.PW_TINY, tricks[2]]]:
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
	var name: String = banner_name if banner_name != "" else P.pu_short(banner_kind, Season.now)
	var tip: String = banner_tip if banner_tip != "" else P.pu_tip(banner_kind, Season.now)
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

# ---- p4.19 (polish "hud2"): the cards, the chips, the power-up card and the notes in the lobby's
# style (the user: "It should look app store quality"). The old ones above stay behind the switch.

# A fade that moves in 8 steps: lobby_art.gd keeps every box it makes, one per colour, so a
# smooth fade would make hundreds of them.
func _step_a(a: float) -> float:
	return roundf(clampf(a, 0.0, 1.0) * 8.0) / 8.0

# One seat's card: a rounded panel in the seat's colour, the fighter's head in a tile, the name
# in the title's font, the arrows it holds, its points as gold pips, a painted crown on the leader.
func _card2(c: Control, st: Dictionary, f: Dictionary, x: float, leader: bool) -> void:
	var i := int(st["i"])
	var col: Color = World.TEAM[i % 8]
	var waiting := f.is_empty()
	var dead: bool = not waiting and int(f["state"]) == P.F_DEAD
	var away: bool = not waiting and (int(f["flags2"]) & P.F2_AWAY) != 0
	var me := i == my_seat
	var dim := dead or waiting
	var r := Rect2(x, CARD_Y, CARD_W, CARD_H)
	# the panel; yours has a white rim and glows in your colour
	var fill := Color(col.darkened(0.84 if dim else 0.74), 0.92)
	var edge := Color.WHITE if me else (col.darkened(0.55) if dim else col.darkened(0.08))
	c.draw_style_box(Art.box(fill, edge, 14, 3, 6, Color(col, 0.6) if me else Color(0, 0, 0, 0.45), 12 if me else 6), r)
	c.draw_rect(Rect2(x + 16, CARD_Y + 5, CARD_W - 32, 2), Color(1, 1, 1, 0.10))   # a light line along the top
	# the head in its tile
	var tile := Rect2(x + 9, CARD_Y + 8, 56, 56)
	c.draw_style_box(Art.box(col.darkened(0.75 if dim else 0.5), col.darkened(0.5 if dim else 0.0), 10, 3), tile)
	var g := 0.45 if dim else 1.0
	c.draw_texture_rect_region(World.FIGHTER_TEX[i % 8], tile.grow(-4.0), HEAD_SRC, Color(g, g, g, 0.55 if waiting else 1.0))
	if dead:     # knocked out: a small red cross on the tile's corner (a big one on 7 cards hid the names)
		var tc := tile.end - Vector2(9, 9)
		c.draw_circle(tc, 12.0, Color(0.05, 0.02, 0.03))
		for d in [Vector2(1, 1), Vector2(1, -1)]:
			c.draw_line(tc - d * 5.5, tc + d * 5.5, Color(1.0, 0.3, 0.25), 4.0, true)
	# the name: one size of letters, squeezed to fit (a size of its own for every name would cost memory)
	var nm := str(st.get("name", ""))
	var room := CARD_W - 78.0
	var w := Art.DISPLAY.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
	var k := minf(1.0, room / maxf(w, 1.0))
	c.draw_set_transform(Vector2(x + 72, CARD_Y + 34), 0.0, Vector2(k, lerpf(k, 1.0, 0.5)))
	Art.text(c, Art.DISPLAY, Vector2.ZERO, nm, 28, Color(0.6, 0.6, 0.66) if dim else Color.WHITE, 5, Color(0.03, 0.02, 0.05), HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var y2 := CARD_Y + 54.0
	if waiting:
		c.draw_string(Art.BODY, Vector2(x + 72, y2 + 6), "next round", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.75, 0.75, 0.82))
	elif away:
		c.draw_string(Art.BODY, Vector2(x + 72, y2 + 6), "away: a bot plays", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1.0, 0.78, 0.45))
	else:
		# the arrows in the quiver
		var arrows := int(f["arrows"])
		for n in 6:
			var ax := x + 73 + n * 12.0
			var a_col := Color(1.0, 0.95, 0.75, 0.5 if dead else 1.0) if n < arrows else Color(1, 1, 1, 0.13)
			c.draw_rect(Rect2(ax, y2 - 1.5, 6, 3), a_col)
			c.draw_colored_polygon(PackedVector2Array([Vector2(ax + 6, y2 - 5), Vector2(ax + 11, y2), Vector2(ax + 6, y2 + 5)]), a_col)
	if not waiting:
		# the points: gold pips up to a goal of 6, a number past that
		var points := int(st.get("points", 0))
		var gt := _gain_t(i)
		if gt >= GAIN_FLY_S and points <= _gain_base(i):
			points += 1          # p4.20: the +1 has landed; the server's point comes 1.5 s after the call
		if goal <= 6:
			for n in goal:
				var pc := Vector2(x + CARD_W - 17 - n * 13.0, y2)
				if goal - 1 - n < points:
					var pr := 1.0
					if goal - 1 - n == points - 1 and gt >= GAIN_FLY_S and gt < GAIN_S:   # the newest pip pops as its +1 lands
						pr = 1.0 + 1.6 * (1.0 - clampf((gt - GAIN_FLY_S) / (GAIN_S - GAIN_FLY_S), 0.0, 1.0))
					if pr > 0.0:
						c.draw_circle(pc, 5.5 * pr, Color(0.25, 0.14, 0.0))
						c.draw_circle(pc, 4.4 * pr, Color(1.0, 0.82, 0.25, 0.55 if dead else 1.0))
						if pr > 1.05:
							c.draw_arc(pc, 7.0 * pr, 0.0, TAU, 20, Color(1, 1, 1, 0.8), 2.0, true)
				else:
					c.draw_circle(pc, 5.0, Color(0, 0, 0, 0.45))
					c.draw_arc(pc, 4.4, 0.0, TAU, 16, Color(1, 1, 1, 0.3), 1.5, true)
		else:
			var txt := "%d / %d" % [points, goal]
			c.draw_string(Art.BODY, Vector2(x + CARD_W - 86, y2 + 6), txt, HORIZONTAL_ALIGNMENT_RIGHT, 72, 18, Color(1.0, 0.85, 0.35))
	if leader:   # the painted crown, tipped, on the head tile's corner
		c.draw_set_transform(Vector2(x + 14, CARD_Y + 12), -0.42, Vector2.ONE)
		c.draw_texture_rect_region(UI_ICONS, Rect2(-20, -22, 40, 40), Rect2(5 * 128, 0, 128, 128))
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# p4.20: one point from the goal: the card's rim blinks gold (two looks only: lobby_art.gd keeps every box)
	if Polish.on("juice") and goal > 1 and int(st.get("points", 0)) == goal - 1 and phase >= P.PH_ROUND_START and phase <= P.PH_ROUND_END:
		var blink := 0.95 if fmod(Time.get_ticks_msec() / 1000.0, 0.9) < 0.45 else 0.45
		c.draw_style_box(Art.box(Color(0, 0, 0, 0), Color(1.0, 0.82, 0.25, blink), 14, 3, 6), r)
	var pw: Dictionary = snap.get("powers", {}).get(i, {})
	if not pw.is_empty() and not waiting:
		_chips2(c, x, pw, me)

# The power-ups under a card. Yours: a pill with the picture and the word. The others': the
# picture only (8 fighters with a word on everything hid the fight on a phone).
func _chips2(c: Control, x: float, pw: Dictionary, me: bool) -> void:
	var bits: int = pw["bits"]
	var kind: int = pw["kind"]
	var left := ceili(float(pw["left"]))
	var sn: String = Season.now
	var list: Array = []          # [the picture's kind, the word, the colour]
	var pk := PV.arrow_power(kind)
	if pk > 0:
		list.append([pk, P.pu_short(pk, sn), PV.COLORS[pk]])
	for pair in [[P.PW_SHIELD, P.PU_SHIELD], [P.PW_INF, P.PU_INF], [P.PW_FLY, P.PU_FLY], [P.PW_BIG, P.PU_BIG]]:
		if bits & pair[0]:
			list.append([pair[1], P.pu_short(pair[1], sn), PV.COLORS[pair[1]]])
	for pair in [[P.PW_INVIS_ON, P.PU_INVIS], [P.PW_SPEED, P.PU_SPEED], [P.PW_UMBRELLA, P.PU_RAIN], [P.PW_SPIKES, P.PU_SPIKES]]:
		if bits & pair[0]:
			list.append([pair[1], "%s %d" % [P.pu_short(pair[1], sn), left], PV.COLORS[pair[1]]])
	if pw.get("swarm", false):
		list.append([P.PU_BATS, "%s %d" % [P.pu_short(P.PU_BATS, sn), left], PV.COLORS[P.PU_BATS]])
	if (int(pw.get("mask", 0)) & 1) != 0:
		list.append([P.PU_MASK, P.pu_short(P.PU_MASK, sn) if (int(pw["mask"]) & 2) == 0 else "DOWN!", PV.COLORS[P.PU_MASK]])
	var tricks: Array = ["TURKEY!", "DIZZY", "PEA-SIZED"] if sn == "harvest" else ["PUMPKIN!", "BACKWARDS", "TINY"]
	for n in 3:
		if bits & [P.PW_PUMPKIN, P.PW_BACKWARDS, P.PW_TINY][n]:
			list.append([PV.TRICK_ICON + n, tricks[n], PV.COLORS[P.PU_TRICK]])
	if bits & P.PW_FROZEN:
		list.append([P.PU_FREEZE, "FROZEN", PV.COLORS[P.PU_FREEZE]])
	elif bits & P.PW_SLOW:
		list.append([P.PU_RAIN, "SLOW", PV.COLORS[P.PU_RAIN]])
	var cx := x + 2.0
	var cy := CARD_Y + CARD_H + 6.0
	var tt := Time.get_ticks_msec() / 1000.0
	for item in list:
		var col: Color = item[2]
		var w := 30.0
		if me:
			w = 36.0 + Art.BODY.get_string_size(item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x + 10.0
		if cx + w > x + CARD_W + 4.0:
			cx = x + 2.0
			cy += 34.0
		if me:
			c.draw_style_box(Art.box(Color(col.darkened(0.7), 0.92), col, 15, 2), Rect2(cx, cy, w, 30))
			c.draw_string(Art.BODY, Vector2(cx + 34, cy + 22), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col.lerp(Color.WHITE, 0.6))
		var ic := Vector2(cx + 15, cy + 15)
		c.draw_circle(ic, 15.0, Color(0.03, 0.02, 0.05, 0.9))
		c.draw_circle(ic, 13.0, PV.disc(col))
		PV.draw_icon(c, ic, int(item[0]), 9.0, Color(0.08, 0.06, 0.12), tt)
		cx += w + 5.0

# The card for the power-up you took: its picture, its name, a tip. It pops in and fades.
func _power_card2(c: Control) -> void:
	var a := _step_a(banner_t / 0.4)
	var k := banner_t / BANNER_S
	var pop := 1.0 + 0.3 * clampf((k - 0.88) / 0.12, 0.0, 1.0)
	var col: Color = PV.COLORS.get(banner_kind, Color.WHITE)
	var rim: Color = PV.GOLD if P.is_big(banner_kind) else col
	var name: String = banner_name if banner_name != "" else P.pu_short(banner_kind, Season.now)
	var tip: String = banner_tip if banner_tip != "" else P.pu_tip(banner_kind, Season.now)
	var nw := Art.DISPLAY.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 36).x
	var tw := Art.BODY.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x if tip != "" else 0.0
	var w := 78.0 + nw + (18.0 + tw if tip != "" else 0.0) + 26.0
	var r := Rect2(960.0 - w / 2.0, 132.0, w, 60.0)
	c.draw_style_box(Art.box(Color(0.05, 0.04, 0.09, 0.9 * a), Color(rim, a), 30, 3, 5, Color(rim, 0.35 * a), 12), r)
	var ic := Vector2(r.position.x + 34.0, r.position.y + 29.0)
	c.draw_circle(ic, 24.0 * pop, Color(0.03, 0.02, 0.05, a))
	c.draw_circle(ic, 22.0 * pop, Color(PV.disc(col), a))
	PV.draw_icon(c, ic, banner_icon, 14.0 * pop, Color(0.08, 0.06, 0.12, a), BANNER_S - banner_t)
	var x := r.position.x + 68.0
	Art.text(c, Art.DISPLAY, Vector2(x, r.position.y + 42.0), name, 36, Color(col.lerp(Color.WHITE, 0.4), a), 5, Color(0.03, 0.02, 0.05), HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
	if tip != "":
		c.draw_string(Art.BODY, Vector2(x + nw + 18.0, r.position.y + 39.0), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color(0.9, 0.92, 1.0, 0.95 * a))

# A short line for you (the look stepped down, a ghost's tip): a pill at the bottom.
func _note_pill(c: Control) -> void:
	var a := _step_a(note_t * 2.0)
	var w := minf(Art.BODY.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 64.0, 1800.0)
	var r := Rect2(960.0 - w * 0.5, 992.0, w, 52.0)
	c.draw_style_box(Art.box(Color(0.05, 0.04, 0.09, 0.88 * a), Color(1.0, 0.82, 0.3, 0.8 * a), 26, 2, 4, Color(0, 0, 0, 0.4 * a), 8), r)
	c.draw_string(Art.BODY, Vector2(r.position.x + 32.0, r.position.y + 35.0), note, HORIZONTAL_ALIGNMENT_LEFT, w - 64.0, 28, Color(1.0, 0.95, 0.8, a))

# p4.20: a silly round's name, small, under the cards (someone who looked away still knows).
func _silly_pill(c: Control) -> void:
	var words := P.silly_name(silly, Season.now)
	if words == "":
		return
	var w := Art.DISPLAY.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x + 44.0
	var r := Rect2(960.0 - w * 0.5, 90.0, w, 40.0)
	c.draw_style_box(Art.box(Color(0.16, 0.08, 0.02, 0.85), Color(1.0, 0.82, 0.3, 0.9), 20, 2, 4), r)
	c.draw_string(Art.DISPLAY, Vector2(r.position.x + 22.0, r.position.y + 29.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1.0, 0.88, 0.45))

# p4.20 (polish "juice"): how long ago seat i's round was called (-1: no +1 for it now),
# the points it had then, and a seat's points now.
func _gain_t(i: int) -> float:
	for g in gains:
		if int(g[0]) == i:
			return float(g[1])
	return -1.0

func _gain_base(i: int) -> int:
	for g in gains:
		if int(g[0]) == i:
			return int(g[2])
	return 999

func _points_of(i: int) -> int:
	for st in seats:
		if int(st["i"]) == i:
			return int(st.get("points", 0))
	return 0

# The +1: from under the round's banner to the seat's newest pip, k 0..1, on a curve, shrinking.
func _gain_fly(c: Control, seat: int, k: float) -> void:
	var from := Vector2(960, 560)
	var to := Vector2(CARD_X + seat * CARD_STEP + CARD_W - 30.0, CARD_Y + 54.0)
	var e := k * k * (3.0 - 2.0 * k)
	var at := from.lerp(to, e) + Vector2(0, -90.0 * sin(e * PI))
	var sc := lerpf(1.5, 0.6, e)
	c.draw_set_transform(at, 0.0, Vector2.ONE * sc)
	Art.text(c, Art.DISPLAY, Vector2(-34, 18), "+1", 52, Color(1.0, 0.86, 0.3), 0, Color.BLACK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

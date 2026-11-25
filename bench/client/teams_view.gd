# TEAMS on the page (2026-11-24). The lobby's MODE can be TEAMS: two teams, no friendly
# fire (the rules: sim/sim.gd, server/game_server.gd). This file is ALL of its look, kept
# small on purpose: the fighters keep their own seat colours, and each one gets a TEAM FLAG
# in its team's colour:
#   - over each fighter in the arena (Marks, a node client/world.gd adds),
#   - on each seat's card in the lobby (lobby_flags, called by client/lobby_cards.gd),
#   - on each seat's card at the top of a match (hud_flag, called by client/hud.gd).
# The first team's flag is ORANGE and pointed, the second team's is TEAL and fork-tailed,
# so the shape tells them apart too (two of the 8 seat colours are an orange and a teal,
# and some eyes do not see colour). Each flag has a dark rim, so it reads on any colour,
# and its team's letter (T for TEAM TURKEY, P for TEAM PIE...).
# Also here: what the page knows about the teams (read: from the server's seats message),
# the tap on your own lobby card that changes sides (Tap), and the names under the match's
# winner (winner_names, called by client/winner_view.gd).
# A restyle only needs this file: change COLORS, flag(), or where each caller puts it.
extends RefCounted

const P = preload("res://sim/proto.gd")
const Art = preload("res://client/lobby_art.gd")
const Season = preload("res://client/season.gd")

const COLORS := [Color("ff7a1a"), Color("12a5a0")]     # the first team: a warm orange; the second: a cool teal
const RIM := Color(0.05, 0.03, 0.07)                   # the dark rim around every flag
const LETTERS := {"harvest": ["T", "P"], "halloween": ["G", "P"], "": ["G", "S"]}   # TURKEY PIE, GHOST PUMPKIN, GOLD SILVER
# The flags' letters are always drawn at this one size and scaled: a font keeps a sheet of
# letters in memory for every size it draws (p4.15's iPhone lesson), and the lobby's seat
# numbers already use this one.
const LETTER_SIZE := 22

# What the server's newest seats message said (game_client.gd calls read).
static var on := false            # TEAMS is being played now (in the lobby: TEAMS is the MODE)
static var pick := "ffa"          # the lobby's MODE: "ffa" or "teams" (a match keeps the mode it began with)
static var seat_team: Array = []  # each seat's team: 0, 1, or -1 (nobody there, or FREE FOR ALL)
static var names: Array = ["", ""]
static var ok := true             # both teams have a fighter (START works)
# The match that just ended (game_client.gd calls match_end): its winning team, for the
# replay's title (deathcam.gd) and the winner's screen (winner_view.gd). -1: one fighter won.
static var won_team := -1
static var won_title := ""        # the team's name as the server said it
static var won_names: Array = []  # the winning team's members by name
static var best := ""             # its player with the most knockouts (the hero shown)

static func read(m: Dictionary) -> void:
	on = str(m.get("mode", "ffa")) == "teams"
	pick = str(m.get("mode_pick", "ffa"))
	ok = bool(m.get("teams_ok", true))
	names = m.get("team_names", P.team_names(Season.now))
	seat_team.clear()
	for st in m.get("seats", []):
		seat_team.append(int(st.get("team", -1)) if on else -1)

# A seat's team (0 or 1), or -1.
static func team(seat: int) -> int:
	return int(seat_team[seat]) if seat >= 0 and seat < seat_team.size() else -1

static func team_name(t: int) -> String:
	return str(names[t]) if t >= 0 and t < names.size() else ""

static func color(t: int) -> Color:
	return COLORS[clampi(t, 0, 1)]

# The name of the team that won the match ("" when one fighter did).
static func won_name() -> String:
	return won_title

# A fighter's team from its snapshot record (proto F2_TEAMS, F2_TEAM_B): -1 in FREE FOR ALL.
static func team_of_fighter(f: Dictionary) -> int:
	var f2 := int(f.get("flags2", 0))
	if (f2 & P.F2_TEAMS) == 0:
		return -1
	return 1 if (f2 & P.F2_TEAM_B) != 0 else 0

# round_end and match_end (server/game_server.gd) carry "team" when a team won.
static func msg_team(m: Dictionary) -> int:
	return int(m["team"]) if m.has("team") else -1

# The match ended: remember the winning team for the replay and the winner's screen.
static func match_end(m: Dictionary, seat_names: Array) -> void:
	won_team = msg_team(m)
	won_title = str(m.get("name", "")) if won_team >= 0 else ""
	best = str(m.get("best", ""))
	won_names.clear()
	for i in m.get("members", []):
		if int(i) >= 0 and int(i) < seat_names.size():
			won_names.append(str(seat_names[int(i)]))

# ------------------------------------------------------------------ the flag
# One team flag, hanging from `top` (the middle of its top edge), w px wide and a bit
# taller. The first team's comes to a point; the second team's has a forked tail.
# base: the transform the caller draws with (its letter is drawn scaled, then base is put back).
static func flag(c: CanvasItem, top: Vector2, t: int, w: float, alpha: float = 1.0, base: Transform2D = Transform2D.IDENTITY) -> void:
	if t < 0:
		return
	var col: Color = COLORS[clampi(t, 0, 1)]
	var h := w * 1.15
	var shape: Array = [Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0, 1)] if t == 0 \
		else [Vector2(-0.5, 0), Vector2(0.5, 0), Vector2(0.5, 1), Vector2(0, 0.72), Vector2(-0.5, 1)]
	var rim_w := maxf(2.0, w * 0.12)
	var pts := PackedVector2Array()
	for v in shape:
		pts.append(top + Vector2(v.x * w, v.y * h))
	# the dark rim: the same shape, drawn as a thick closed line under the fill
	var loop := pts.duplicate()
	loop.append(pts[0])
	c.draw_polyline(loop, Color(RIM, alpha), rim_w * 2.0, true)
	if t == 0:
		c.draw_colored_polygon(pts, Color(col, alpha))
	else:   # (the forked one in two halves: a polygon with a notch is drawn as two plain ones)
		c.draw_colored_polygon(PackedVector2Array([pts[0], top, pts[3], pts[4]]), Color(col, alpha))
		c.draw_colored_polygon(PackedVector2Array([top, pts[1], pts[2], pts[3]]), Color(col, alpha))
	# a lighter band along the top, like cloth catching the light
	c.draw_rect(Rect2(top.x - w * 0.5, top.y, w, maxf(2.0, h * 0.14)), Color(col.lightened(0.45), alpha))
	# the team's letter, in white, a little above the middle (the pointed flag narrows below)
	var list: Array = LETTERS.get(Season.now, LETTERS[""])
	var k := w * 0.6 / LETTER_SIZE
	var mid := top + Vector2(0, h * (0.5 if t == 0 else 0.6))
	c.draw_set_transform_matrix(base * Transform2D(0.0, Vector2(k, k), 0.0, mid))
	c.draw_string(Art.DISPLAY, Vector2(-40, 0), str(list[clampi(t, 0, 1)]), HORIZONTAL_ALIGNMENT_CENTER, 80, LETTER_SIZE, Color(1, 1, 1, alpha))
	c.draw_set_transform_matrix(base)

# ------------------------------------------------------------------ the lobby's cards
# A flag on the top edge of each seat's card (lobby_cards.gd calls this at the end of its
# words pass; xfs: where each card is drawn, [its middle, its scale], [] when off screen).
# A person's or a bot's team; faded on a seat a bot will fill.
static func lobby_flags(n: CanvasItem, cards, xfs: Array) -> void:
	if not on:
		return
	for i in mini(xfs.size(), seat_team.size()):
		var t := team(i)
		if xfs[i].is_empty() or t < 0:
			continue
		var c: Dictionary = cards.cards[i]
		var xf := Transform2D(0.0, Vector2.ONE * float(xfs[i][1]), 0.0, xfs[i][0])
		n.draw_set_transform_matrix(xf)
		# yours sways a little: it is the one you can tap
		var sway := sin(cards.t * 3.0) * 3.0 if c["me"] and cards.phase == P.PH_LOBBY else 0.0
		# p4.21 (polish "motion"): a new flag drops onto its card from above and settles with a small bounce
		# (lobby_cards.gd sets flag_t: under 0 it has not started yet)
		var ft := float(c.get("flag_t", 9.0))
		if ft < 0.0:
			continue
		var drop := (Art.ease_out_back(ft / 0.38) - 1.0) * 90.0 if ft < 0.38 else 0.0
		var fa := (0.55 if int(c["kind"]) == 0 else 1.0) * clampf(ft / 0.1, 0.0, 1.0)
		if c.has("awards") and not c["awards"].is_empty():
			# after a match the card's top carries its award: the flag goes small into the top right
			# corner (it hung over the award's words)
			flag(n, Vector2(cards.W * 0.5 - 28.0 + sway, -cards.H * 0.5 - 10.0 + drop), t, 36.0, fa, xf)
		else:
			flag(n, Vector2(sway, -cards.H * 0.5 - 12.0 + drop), t, 54.0, fa, xf)
	n.draw_set_transform_matrix(Transform2D.IDENTITY)

# ------------------------------------------------------------------ the match's cards (the HUD)
# A small flag on a seat's card at the top of the match: on the lower left corner of the
# head's tile (the crown sits on its upper left, the knocked-out cross on its lower right).
static func hud_flag(c: CanvasItem, seat: int, card_x: float, card_y: float) -> void:
	if on and team(seat) >= 0:
		flag(c, Vector2(card_x + 15.0, card_y + 42.0), team(seat), 28.0)

# ------------------------------------------------------------------ the winner's screen
# The colour of the big name: the winning team's own (the hero under it keeps the seat
# colour of the team's best player, which may be the other team's orange or teal).
# In FREE FOR ALL: `seat_col`, the winner's seat colour, as before.
static func winner_color(seat_col: Color) -> Color:
	return COLORS[won_team].lightened(0.3) if won_team >= 0 and won_team < 2 else seat_col

# Under TEAM TURKEY WINS THE MATCH: the team's members by name (winner_view.gd calls this
# with its own pop scale already set; y: where the line goes, in its words' frame).
static func winner_names(c: CanvasItem, y: float, alpha: float) -> void:
	if won_team < 0 or won_names.is_empty():
		return
	var line := "  ·  ".join(won_names).to_upper()
	var col: Color = COLORS[clampi(won_team, 0, 1)].lightened(0.35)
	var fs := Art.fit_size(Art.DISPLAY, line, 44, 800, 20)
	Art.text(c, Art.DISPLAY, Vector2(-420, y), line, fs, Color(col, alpha), 7, Color(0.03, 0.01, 0.05), HORIZONTAL_ALIGNMENT_CENTER, 840)

# ------------------------------------------------------------------ the tap on your own card
# The lobby (lobby.gd) lays this see-through button over your own seat's card while TEAMS
# is the MODE and the lobby is open. A tap says "change my team" (the server does it and
# says so in its next seats message).
class Tap extends Control:
	signal pressed
	var last_ms := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		visible = false

	# Where your card is now (cards: lobby_cards.gd), or hidden when there is nothing to tap.
	func place(cards, my_seat: int, can_tap: bool) -> void:
		visible = can_tap and my_seat >= 0
		if not visible:
			return
		var xf: Array = cards._xf(my_seat)
		var half := Vector2(cards.W, cards.H) * 0.5 * float(xf[1])
		position = xf[0] - half - Vector2(0, 40.0)      # (the flag above the card counts too)
		size = half * 2.0 + Vector2(0, 40.0)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			accept_event()
			var now := Time.get_ticks_msec()
			if now - last_ms > 300:      # (one tap, one change: a shaky thumb does not flip twice)
				last_ms = now
				pressed.emit()

# ------------------------------------------------------------------ the arena
# The flags over the fighters, drawn in the arena (world.gd adds one of these on top of
# its fighters and calls show_view every frame). A fighter's team comes with its own
# snapshot record, so the flag is right on the very tick, and in the match's end replay.
class Marks extends Node2D:
	const WORLD_W := 36.0         # a flag as wide as a fighter's body (36 px of the 1920 px arena: 16 px on a small phone)
	var teams = load("res://client/teams_view.gd")   # this file's own functions (a class in a file cannot call them by name)
	var hats = load("res://client/hats.gd")          # p4.22: how tall the hat under the flag is
	var list: Array = []          # [x, y, team] for each flag to draw this frame

	# fl: the fighters as drawn this frame; sprites: world.gd's slots ([sprite, ...] by seat).
	# A fighter the page hides (INVISIBLE, in bats, you in smoke) has its sprite hidden: no flag.
	func show_view(fl: Array, sprites: Array) -> void:
		var had := not list.is_empty()
		list.clear()
		for f in fl:
			var t: int = teams.team_of_fighter(f)
			var i := int(f["id"])
			if t < 0 or int(f["state"]) == P.F_DEAD or i < 0 or i >= sprites.size():
				continue
			var spr: Sprite2D = sprites[i][0]
			if not spr.visible:
				continue
			# over the head; a little bob so 8 flags do not look glued on
			# (p4.22: over the fighter's winter hat, client/hats.gd; 0 out of the Christmas season)
			list.append([float(f["x"]) + 18.0, float(f["y"]) - 52.0 - float(hats.lift(i)) + sin(Time.get_ticks_msec() / 260.0 + i) * 2.0, t])
		if had or not list.is_empty():
			queue_redraw()

	func _draw() -> void:
		for m in list:
			teams.flag(self, Vector2(m[0], m[1]), int(m[2]), WORLD_W)

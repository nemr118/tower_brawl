# The 8 seats as a line-up of cards (2026-10-25), each in its player's colour
# with the fighter standing on a lit spot: a person's card glows, yours pulses
# and stands a little higher (YOU), a seat a bot will fill shows a faded fighter
# (BOT · NORMAL), an open seat a dark shape (OPEN). The fighters breathe (the idle
# frames), now and then one aims or raises the bow; a person who joins pops in
# with a hop and a burst of sparks; in the countdown everyone aims. The last
# match's awards hang on their winners' cards as a gold ribbon (more than one:
# they flip in turn). The cards rise in when the lobby comes up and drop away at
# the countdown's end. Three layers: the cards (smooth), the fighters (pixel
# art, nearest), the words (smooth).
extends Control

const Art = preload("res://client/lobby_art.gd")
const AwardArt = preload("res://client/award_art.gd")   # p4.17: the award's picture on the card (polish "award_badges")
const Polish = preload("res://client/polish.gd")
const World = preload("res://client/world.gd")
const P = preload("res://sim/proto.gd")
const HALO := preload("res://assets/fx_halo.png")
const N := 8
const TOP := 240.0               # the cards' top in the 1920 x 1080 frame
const H := 364.0
const X0 := 60.0
const GAP := 16.0
const W := (1800.0 - 7.0 * GAP) / 8.0
const FEET := 66.0               # the fighter's feet, from the card's middle
const SCALE := 1.6               # the fighter: 1.6 x its 128 px frame
const AWARD_S := 3.2             # each award on a card shows this long

var pal: Dictionary = {}
var halloween := false
var tier := 2
var t := 0.0
var cards: Array = []
var my_seat := -1
var phase := -1
var intro := 9.0                 # seconds since the lobby came up (lobby.gd sets it)
var exit := 0.0                  # 0..1: the countdown's end, the cards drop away
var counting := false
var level_name := "NORMAL"
var seated := false              # you have a seat (an open card says OPEN, else JOIN)
var connected := true            # no connection yet: an open card says OPEN
var fighters := _Pass.new()
var words := _Pass.new()

class _Pass extends Control:
	var cards_ref
	var which := 0
	func _draw() -> void:
		if cards_ref != null:
			cards_ref._paint(self, which)

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	size = Vector2(1920, 1080)
	for k in 2:
		var p: _Pass = [fighters, words][k]
		p.cards_ref = self
		p.which = k + 1
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.size = size
		add_child(p)
	fighters.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	words.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for i in N:
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(0, 0, 0, 0)
		glow.set_corner_radius_all(18)
		glow.corner_detail = 6
		cards.append({"kind": 0, "name": "", "fill": false, "me": false, "away": false, "next": false, "crowns": 0,
			"points": 0, "pop": 9.0, "hop": 9.0, "pose": 0, "pose_t": 0.0, "next_pose": 3.0 + randf() * 9.0,
			"awards": [], "sparks": [], "glow": glow})

func set_dress(p: Dictionary, hw: bool) -> void:
	pal = p
	halloween = hw

# The seats message (game_server.gd "seats"): who sits where. bots: how many
# bots fill the empty seats at the start; awards: the last match's.
func set_seats(list: Array, me: int, ph: int, bots: int, awards: Array) -> void:
	my_seat = me
	phase = ph
	seated = me >= 0
	var free_seen := 0
	for i in N:
		var st: Dictionary = list[i] if i < list.size() else {}
		var c: Dictionary = cards[i]
		var kind := int(st.get("kind", 0))
		var nm := str(st.get("name", ""))
		var fill := false
		if kind == 0:
			fill = free_seen < bots and ph <= P.PH_COUNTDOWN
			free_seen += 1
		if kind == 1 and (int(c["kind"]) != 1 or str(c["name"]) != nm):
			c["pop"] = 0.0
			c["hop"] = 0.0
			_sparks(c, i)
		c["kind"] = kind
		c["name"] = nm
		c["fill"] = fill
		c["me"] = i == me
		c["away"] = kind == 1 and not bool(st.get("on", true))
		c["next"] = kind == 1 and ph > P.PH_COUNTDOWN and not bool(st.get("in", false))
		c["crowns"] = int(st.get("crowns", 0))
		c["points"] = int(st.get("points", 0))
		var mine: Array = []
		for aw in awards:
			# a person's award shows while they sit there; a bot's on the seat a bot fills again
			var an := str(aw.get("name", ""))
			if int(aw.get("seat", -1)) == i and ((kind != 0 and an == nm) or (fill and an.begins_with("BOT"))):
				mine.append([str(aw.get("title", "")), str(aw.get("why", ""))])
		c["awards"] = mine

func _sparks(c: Dictionary, i: int) -> void:
	var list: Array = []
	var n := 6 if tier <= 1 else 16
	for k in n:
		var a := TAU * k / n + randf() * 0.4
		list.append([Vector2(0, FEET - 60.0), Vector2(cos(a), sin(a) - 0.4) * (260.0 + randf() * 200.0), 0.0, k % 3 == 0])
	c["sparks"] = list

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	t += delta
	for i in N:
		var c: Dictionary = cards[i]
		c["pop"] += delta
		c["hop"] += delta
		c["pose_t"] = maxf(0.0, c["pose_t"] - delta)
		c["next_pose"] -= delta
		if c["next_pose"] <= 0.0:
			c["next_pose"] = 5.0 + randf() * 9.0
			if c["hop"] > 1.0 and (int(c["kind"]) != 0 or c["fill"]):
				if randf() < 0.35:
					c["hop"] = 0.0
				else:
					c["pose"] = [19, 10][randi() % 2]
					c["pose_t"] = 1.0
		var sp: Array = c["sparks"]
		for s in sp:
			s[2] += delta
			s[0] += s[1] * delta
			s[1] *= 1.0 - 2.2 * delta
			s[1].y += 500.0 * delta
		while not sp.is_empty() and sp[0][2] > 0.8:
			sp.pop_front()
		if c["me"]:
			var g := 0.5 + 0.5 * sin(t * 4.2)
			var sb: StyleBoxFlat = c["glow"]
			var col: Color = World.TEAM[i]
			sb.shadow_color = Color(col.r, col.g, col.b, 0.45 + 0.35 * g)
			sb.shadow_size = 14 + int(14.0 * g)
	queue_redraw()
	fighters.queue_redraw()
	words.queue_redraw()

# Where card i is drawn: its middle, its scale. It rises in (intro), drops away
# (exit), pops when someone joins, and yours stands higher.
func _xf(i: int) -> Array:
	var c: Dictionary = cards[i]
	var cx := X0 + i * (W + GAP) + W * 0.5
	var cy := TOP + H * 0.5
	var k := Art.ease_out_back((intro - 0.05 * i) / 0.5)
	cy += (1.0 - k) * 560.0
	var e := clampf(exit * 1.7 - i * 0.09, 0.0, 1.0)
	cy += e * e * 760.0
	var s := 1.0
	var pop: float = c["pop"]
	if pop < 0.45:
		s += 0.12 * sin(PI * pop / 0.45)
	if c["me"]:
		cy -= 10.0
	return [Vector2(cx, cy), s]

func _frame(i: int) -> int:
	var c: Dictionary = cards[i]
	if counting:
		return 19
	var hop: float = c["hop"]
	if hop < 0.5:
		return 8 if hop < 0.17 else (9 if hop < 0.36 else 27)
	if c["pose_t"] > 0.0:
		return c["pose"]
	return int(t * 2.2 + i * 0.37) % 2

# The cards are drawn kind by kind across all 8 (every box, then every glow,
# then every name...), not card by card: draws that share a texture follow each
# other, so the page batches them (fewer draw calls on a phone).
func _paint(n: Control, which: int) -> void:
	if pal.is_empty():
		return
	var xfs: Array = []
	for i in N:
		var xf := _xf(i)
		xfs.append(xf if xf[0].y < 1400.0 else [])
	if which == 0:
		_cards(n, xfs)
	elif which == 1:
		for i in N:
			if not xfs[i].is_empty():
				_at(n, xfs[i])
				_fighter(n, i)
	else:
		_words(n, xfs)
	n.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _at(n: Control, xf: Array) -> void:
	n.draw_set_transform(xf[0], 0.0, Vector2.ONE * xf[1])

func _draw() -> void:
	_paint(self, 0)

# The cards themselves: a glow (yours), the box in the seat's colour, a sheen on
# its top half (NORMAL and HIGH), the lit spot and the soft floor under the fighter.
func _cards(n: Control, xfs: Array) -> void:
	var r := Rect2(-W * 0.5, -H * 0.5, W, H)
	var low := tier <= 1
	for i in N:
		if xfs[i].is_empty() or not cards[i]["me"]:
			continue
		_at(n, xfs[i])
		n.draw_style_box(cards[i]["glow"], r)
	for i in N:
		if xfs[i].is_empty():
			continue
		var c: Dictionary = cards[i]
		var col: Color = World.TEAM[i]
		var fill: Color
		var edge: Color
		if int(c["kind"]) != 0:
			fill = Color(col.darkened(0.78), 0.94)
			edge = col.lightened(0.15) if c["me"] else col.darkened(0.15)
		elif c["fill"]:
			fill = Color(col.darkened(0.86), 0.9)
			edge = Color(col.darkened(0.45), 0.9)
		else:
			fill = Color(0.04, 0.03, 0.06, 0.82)
			edge = Color(col.darkened(0.55), 0.75)
		_at(n, xfs[i])
		n.draw_style_box(Art.box(fill, edge, 16, 4 if c["me"] else 3, 4 if c["me"] else 3, Color(0, 0, 0, 0.5), 0 if low else 12), r)
	if not low:
		for i in N:
			if xfs[i].is_empty():
				continue
			var col: Color = World.TEAM[i]
			var sh := Color(col.r, col.g, col.b, 0.34 if int(cards[i]["kind"]) != 0 else 0.12)
			var clear := Color(col.r, col.g, col.b, 0.0)
			_at(n, xfs[i])
			n.draw_primitive(PackedVector2Array([Vector2(-W * 0.5 + 14, -H * 0.5 + 4), Vector2(W * 0.5 - 14, -H * 0.5 + 4),
				Vector2(W * 0.5 - 4, 0), Vector2(-W * 0.5 + 4, 0)]), PackedColorArray([sh, sh, clear, clear]), PackedVector2Array())
	# the lit spot, a ring of the seat's colour on the floor and the dark floor itself:
	# all one soft texture, so they go together
	for i in N:
		if xfs[i].is_empty():
			continue
		var c: Dictionary = cards[i]
		var col: Color = World.TEAM[i]
		var live: bool = int(c["kind"]) != 0
		_at(n, xfs[i])
		if live or c["fill"]:
			var k := 1.0 if live else 0.45
			if counting:
				k = 1.35
			n.draw_texture_rect(HALO, Rect2(-W * 0.62, FEET - 250.0, W * 1.24, 270.0), false, Color(col.r, col.g, col.b, 0.42 * k))
		if live:
			n.draw_texture_rect(HALO, Rect2(-88, FEET - 22, 176, 44), false, Color(col.r * 1.4, col.g * 1.4, col.b * 1.4, 0.9))
		n.draw_texture_rect(HALO, Rect2(-74, FEET - 15, 148, 30), false, Color(0, 0, 0, 0.85))

# The fighter: its sheet (world.gd FIGHTER_TEX), the frame for what it does,
# facing the middle of the line-up; faded for a bot to come, a dark shape for an open seat.
func _fighter(n: Control, i: int) -> void:
	var c: Dictionary = cards[i]
	var kind := int(c["kind"])
	var frame := _frame(i)
	var src := Rect2((frame % 16) * 128, (frame / 16) * 128, 128, 128)
	var hop: float = c["hop"]
	var lift := -sin(PI * clampf(hop / 0.36, 0.0, 1.0)) * 70.0 if hop < 0.36 else 0.0
	var dst := Rect2(-64.0 * SCALE, FEET - 122.0 * SCALE + lift, 128.0 * SCALE, 128.0 * SCALE)
	if i >= 4:
		dst.size.x = -dst.size.x   # a negative width draws it mirrored, in the same place
	var mod := Color.WHITE
	if kind == 2:
		mod = Color(0.88, 0.88, 0.95)
	elif kind == 0:
		mod = Color(0.62, 0.62, 0.72, 0.7) if c["fill"] else Color(0.0, 0.0, 0.0, 0.55)
	if c["away"]:
		mod = Color(0.6, 0.6, 0.65, 0.8)
	n.draw_texture_rect_region(World.FIGHTER_TEX[i], dst, src, mod)

# What a card says: its name, tag and award, worked out once a frame.
func _view(i: int) -> Dictionary:
	var c: Dictionary = cards[i]
	var col: Color = World.TEAM[i]
	var kind := int(c["kind"])
	var v := {"live": kind != 0}
	var nm: String = c["name"]
	var name_col: Color = pal["text"]
	if kind == 0:
		nm = "BOT" if c["fill"] else ("OPEN" if seated or not connected else "JOIN!")
		name_col = Color(pal["dim"]) if c["fill"] else Color(pal["faint"])
	elif c["me"]:
		name_col = Color(1.0, 0.97, 0.82)
	v["name"] = nm
	v["name_col"] = name_col
	v["name_size"] = Art.fit_size(Art.DISPLAY, nm, 38, W - 18, 18)
	var tag := ""
	var tag_fill := Color(0.2, 0.2, 0.26)
	var tag_ink := Color(0.85, 0.85, 0.9)
	if kind == 1:
		if c["me"]:
			tag = "YOU"
			tag_fill = pal["accent"]
			tag_ink = Color(0.12, 0.04, 0.0)
		elif c["away"]:
			tag = "AWAY"
			tag_fill = Color(0.5, 0.35, 0.1)
		elif c["next"]:
			tag = "NEXT ROUND"
		elif int(c["points"]) > 0 and phase > P.PH_COUNTDOWN:
			tag = "%d PT%s" % [c["points"], "" if int(c["points"]) == 1 else "S"]
			tag_fill = col.darkened(0.3)
			tag_ink = Color.WHITE
		else:
			tag = "READY"
			tag_fill = Color(pal["second"]).darkened(0.45)
			tag_ink = Color(pal["second"]).lightened(0.5)
	elif kind == 2:
		tag = "BOT"
	elif c["fill"]:
		tag = "BOT · %s" % level_name
		tag_fill = Color(0.16, 0.16, 0.22, 0.9)
		tag_ink = Color(pal["dim"])
	v["tag"] = tag
	if tag != "":
		var tgs := Art.fit_size(Art.BODY, tag, 26, W - 40, 16)
		var tw := Art.BODY.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, tgs).x + 28.0
		v["tag_size"] = tgs
		v["tag_rect"] = Rect2(-tw * 0.5, FEET + 72, tw, 38)
		v["tag_fill"] = tag_fill
		v["tag_ink"] = tag_ink
	var aws: Array = c["awards"]
	if not aws.is_empty() and (v["live"] or c["fill"]):
		var k := int(t / AWARD_S) % aws.size()
		var ph := fmod(t, AWARD_S)
		v["award"] = aws[k]
		v["award_sy"] = clampf(minf(ph / 0.18, (AWARD_S - ph) / 0.18), 0.05, 1.0) if aws.size() > 1 else 1.0
		v["title_size"] = Art.fit_size(Art.DISPLAY, aws[k][0], 28, W - 24, 16)
		v["why_size"] = Art.fit_size(Art.BODY, aws[k][1], 22, W - 22, 14)
	return v

# The words, kind by kind: the boxes (the seat's number, the award ribbons, the
# tags), the crowns, then each kind of text for all cards, then the sparks.
func _words(n: Control, xfs: Array) -> void:
	var edge := Color(0.02, 0.01, 0.04)
	var disp := Art.DISPLAY
	var body := Art.BODY
	var low := tier <= 1
	var views: Array = []
	for i in N:
		views.append(_view(i) if not xfs[i].is_empty() else {})
	var ribbon_y := -H * 0.5 + 72.0
	var rr := Rect2(-W * 0.5 + 6, -30, W - 12, 64)
	# the boxes: the seat's number (a plain rect: it batches), the award ribbon, the tag pill
	for i in N:
		if views[i].is_empty():
			continue
		var col: Color = World.TEAM[i]
		_at(n, xfs[i])
		n.draw_rect(Rect2(-W * 0.5 + 10, -H * 0.5 + 10, 50, 32), col if views[i]["live"] else col.darkened(0.55))
	for i in N:
		if views[i].is_empty() or not views[i].has("award"):
			continue
		_ribbon_xf(n, xfs[i], ribbon_y, views[i]["award_sy"])
		n.draw_style_box(Art.box(Color(0.36, 0.22, 0.02, 0.95), Color(1.0, 0.8, 0.25), 8, 2, 4), rr)
	for i in N:
		if views[i].is_empty() or views[i]["tag"] == "":
			continue
		var tf: Color = views[i]["tag_fill"]
		_at(n, xfs[i])
		n.draw_style_box(Art.box(tf, tf.darkened(0.5), 19, 2, 3), views[i]["tag_rect"])
	for i in N:
		if views[i].is_empty() or int(cards[i]["crowns"]) <= 0 or not views[i]["live"]:
			continue
		_at(n, xfs[i])
		Art.crown(n, Vector2(W * 0.5 - 24.0, -H * 0.5 + 38), 1.1, Color(1.0, 0.82, 0.2))
	# the seat numbers
	for i in N:
		if views[i].is_empty():
			continue
		_at(n, xfs[i])
		n.draw_string(disp, Vector2(-W * 0.5 + 10, -H * 0.5 + 35), "P%d" % (i + 1), HORIZONTAL_ALIGNMENT_CENTER, 50, 22,
			Color(0.05, 0.03, 0.08) if views[i]["live"] else Color(0.6, 0.6, 0.65))
	# the names: their shadows, then their edges, then their letters
	var name_pos := Vector2(-W * 0.5, FEET + 58)
	if not low:
		for i in N:
			if views[i].is_empty():
				continue
			_at(n, xfs[i])
			var fs: int = views[i]["name_size"]
			n.draw_string_outline(disp, name_pos + Vector2(0, maxf(2.0, fs * 0.07)), views[i]["name"], HORIZONTAL_ALIGNMENT_CENTER, W, fs,
				6 + maxi(2, fs / 12), Color(0, 0, 0, 0.5))
	for i in N:
		if views[i].is_empty():
			continue
		_at(n, xfs[i])
		n.draw_string_outline(disp, name_pos, views[i]["name"], HORIZONTAL_ALIGNMENT_CENTER, W, views[i]["name_size"], 6, edge)
	for i in N:
		if views[i].is_empty():
			continue
		_at(n, xfs[i])
		n.draw_string(disp, name_pos, views[i]["name"], HORIZONTAL_ALIGNMENT_CENTER, W, views[i]["name_size"], views[i]["name_col"])
	# the awards: the title's edge, its letters, then why
	for pass_i in 3:
		for i in N:
			if views[i].is_empty() or not views[i].has("award"):
				continue
			_ribbon_xf(n, xfs[i], ribbon_y, views[i]["award_sy"])
			var aw: Array = views[i]["award"]
			if pass_i == 0:
				n.draw_string_outline(disp, Vector2(rr.position.x, -2), aw[0], HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, views[i]["title_size"], 4, edge)
			elif pass_i == 1:
				n.draw_string(disp, Vector2(rr.position.x, -2), aw[0], HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, views[i]["title_size"],
					Color(1.0, 0.86, 0.35))
			else:
				n.draw_string(body, Vector2(rr.position.x, 24), aw[1], HORIZONTAL_ALIGNMENT_CENTER, rr.size.x, views[i]["why_size"],
					Color(1.0, 0.95, 0.85, 0.95))
	# p4.17: the award's picture in a round badge beside the fighter (polish "award_badges")
	if Polish.on("award_badges"):
		for i in N:
			if views[i].is_empty() or not views[i].has("award") or not AwardArt.ORDER.has(str(views[i]["award"][0])):
				continue
			_at(n, xfs[i])
			var bc := Vector2(W * 0.5 - 38.0, FEET - 52.0)
			n.draw_circle(bc, 33.0, Color(0.08, 0.05, 0.12, 0.92))
			AwardArt.draw(n, str(views[i]["award"][0]), Rect2(bc - Vector2(28, 28), Vector2(56, 56)))
			n.draw_arc(bc, 33.0, 0.0, TAU, 32, Color(1.0, 0.8, 0.25), 3.0, true)
	# the tags' words, the crowns' counts
	for i in N:
		if views[i].is_empty() or views[i]["tag"] == "":
			continue
		var tr: Rect2 = views[i]["tag_rect"]
		_at(n, xfs[i])
		n.draw_string(body, Vector2(tr.position.x, tr.position.y + 28), views[i]["tag"], HORIZONTAL_ALIGNMENT_CENTER, tr.size.x,
			views[i]["tag_size"], views[i]["tag_ink"])
	for i in N:
		var crowns: int = cards[i]["crowns"]
		if views[i].is_empty() or crowns <= 1 or not views[i]["live"]:
			continue
		_at(n, xfs[i])
		Art.text(n, disp, Vector2(W * 0.5 - 98, -H * 0.5 + 37), "%dx" % crowns, 24, Color(1.0, 0.88, 0.4), 4, edge,
			HORIZONTAL_ALIGNMENT_RIGHT, 56, false)
	# the sparks of a pop
	for i in N:
		if xfs[i].is_empty():
			continue
		var col: Color = World.TEAM[i]
		_at(n, xfs[i])
		for s in cards[i]["sparks"]:
			var a := clampf(1.0 - s[2] / 0.8, 0.0, 1.0)
			var sc: Color = Color(1, 1, 0.85) if s[3] else col.lightened(0.3)
			var sz := 9.0 * a + 3.0
			n.draw_rect(Rect2(s[0] - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(sc.r, sc.g, sc.b, a))

# The award ribbon's own place: its middle on the card, squashed while it flips.
func _ribbon_xf(n: Control, xf: Array, y: float, sy: float) -> void:
	n.draw_set_transform(xf[0] + Vector2(0, y) * xf[1], 0.0, Vector2(xf[1], xf[1] * sy))

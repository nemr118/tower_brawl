# The winner's screen (2026-10-25), shown at a match's end after the deathcam's
# montage (hud.gd calls paint() each frame, on its 1920 x 1080 design). The
# arena dims; light rays turn behind the winner's fighter, who drops onto a
# podium and raises the bow; confetti falls; the name in its colour, WINS THE
# MATCH; on the right the awards slide in one by one as cards (the award in
# gold, who in their colour, why); at the bottom THE LOBBY OPENS IN N with a bar
# that runs out. t: seconds since the screen came up. Its look and fonts: lobby_art.gd.
extends RefCounted

const Art = preload("res://client/lobby_art.gd")
const World = preload("res://client/world.gd")
const Polish = preload("res://client/polish.gd")
const AwardArt = preload("res://client/award_art.gd")   # p4.13 polish "award_art": a picture on each award card
const HALO := preload("res://assets/fx_halo.png")
const MID := Vector2(420, 830)    # the winner's feet
const FIGHTER := 3.0              # the fighter: 3 x its 128 px frame
const END_S := 12.0               # the match's end (game_server.gd MATCH_END_TICKS / 60): the bar's full length

static func paint(c: Control, t: float, seat: int, who: String, awards: Array, left_ticks: int) -> void:
	Art.fonts_ready()
	var col: Color = World.TEAM[posmod(seat, 8)]
	var gold := Color(1.0, 0.84, 0.3)
	var edge := Color(0.03, 0.01, 0.05)
	var a := clampf(t / 0.35, 0.0, 1.0)
	# the arena dims
	c.draw_rect(Rect2(-600, -100, 3120, 1300), Color(0.01, 0.0, 0.03, 0.66 * a))
	# light rays in the winner's colour, turning slowly
	for k in 14:
		var a0 := t * 0.25 + TAU * k / 14.0
		var a1 := a0 + TAU / 28.0
		var r := 1100.0
		c.draw_colored_polygon(PackedVector2Array([MID + Vector2(0, -150), MID + Vector2(0, -150) + Vector2(cos(a0), sin(a0)) * r,
			MID + Vector2(0, -150) + Vector2(cos(a1), sin(a1)) * r]), Color(col.r, col.g, col.b, 0.075 * a))
	c.draw_texture_rect(HALO, Rect2(MID.x - 330, MID.y - 560, 660, 620), false, Color(col.r, col.g, col.b, 0.55 * a))
	# the podium
	var pod := Rect2(MID.x - 170, MID.y, 340, 140)
	c.draw_style_box(Art.box(col.darkened(0.55), col.darkened(0.8), 10, 3, 6, Color(0, 0, 0, 0.5), 14), pod)
	c.draw_rect(Rect2(pod.position.x + 6, pod.position.y + 4, pod.size.x - 12, 16), col.lightened(0.1))
	Art.crown(c, Vector2(MID.x, MID.y + 98), 2.6, gold)
	# the fighter drops in, lands, then raises the bow and breathes
	var drop := 1.0 - Art.ease_out(t / 0.4)
	var frame := 9 if t < 0.4 else (27 if t < 0.55 else (10 if int(t * 0.8) % 3 != 2 else int(t * 2.0) % 2))
	var fs := 128.0 * FIGHTER
	var bob := sin(t * 2.4) * 4.0 if t > 0.55 else 0.0
	var dst := Rect2(MID.x - fs * 0.5, MID.y - 122.0 * FIGHTER - drop * 700.0 + bob, fs, fs)
	var ell := PackedVector2Array()
	for k in 24:
		var an := TAU * k / 24.0
		ell.append(MID + Vector2(cos(an) * 110.0, sin(an) * 20.0))
	c.draw_colored_polygon(ell, Color(0, 0, 0, 0.5 * a))
	c.draw_texture_rect_region(World.FIGHTER_TEX[posmod(seat, 8)], dst, Rect2((frame % 16) * 128, (frame / 16) * 128, 128, 128))
	# confetti
	for k in 70:
		var sp := 90.0 + (k % 7) * 26.0
		var x := fposmod(k * 137.5 + sin(t * 1.3 + k) * 40.0, 1920.0)
		var y := fposmod(k * 53.0 + t * sp, 1180.0) - 80.0
		var cc: Color = World.TEAM[k % 8] if k % 3 != 0 else gold
		var w := 14.0 * absf(sin(t * 3.0 + k)) + 3.0
		c.draw_rect(Rect2(x - w * 0.5, y - 4, w, 9), Color(cc.r, cc.g, cc.b, 0.9 * a))
	# the words over the winner
	var pop := Art.ease_out_back((t - 0.25) / 0.45)
	if pop > 0.0:
		c.draw_set_transform(Vector2(MID.x, 280), 0.0, Vector2.ONE * (0.6 + 0.4 * pop))
		Art.text(c, Art.DISPLAY, Vector2(-420, -100), "WINNER!", 66, gold, 9, edge, HORIZONTAL_ALIGNMENT_CENTER, 840)
		var ns := Art.fit_size(Art.DISPLAY, who.to_upper(), 124, 800, 40)
		Art.text(c, Art.DISPLAY, Vector2(-420, 20), who.to_upper(), ns, col.lightened(0.25), 12, edge, HORIZONTAL_ALIGNMENT_CENTER, 840)
		Art.text(c, Art.DISPLAY, Vector2(-420, 84), "WINS THE MATCH", 48, Color(0.96, 0.94, 1.0), 8, edge, HORIZONTAL_ALIGNMENT_CENTER, 840)
		c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the awards, one card each, sliding in one after another
	if not awards.is_empty():
		Art.text(c, Art.DISPLAY, Vector2(880, 168), "AWARDS", 54, gold, 8, edge, HORIZONTAL_ALIGNMENT_CENTER, 1000)
		var n := mini(awards.size(), 12)
		var rows := ceili(n / 2.0)
		var ch := minf(124.0, 760.0 / maxf(1.0, rows))
		for i in n:
			var aw: Dictionary = awards[i]
			var k := Art.ease_out_back((t - 0.5 - i * 0.09) / 0.4)
			if k <= 0.0:
				continue
			var s := int(aw.get("seat", 0))
			var pc: Color = World.TEAM[posmod(s, 8)]
			var x := 880.0 + (i % 2) * 508.0 + (1.0 - k) * 120.0
			var y := 196.0 + (i / 2) * ch
			var r := Rect2(x, y, 492, ch - 12)
			c.draw_style_box(Art.box(Color(0.07, 0.04, 0.11, 0.94), pc.darkened(0.2), 12, 2, 4, Color(0, 0, 0, 0.45), 10), r)
			c.draw_rect(Rect2(x + 4, y + 4, 12, r.size.y - 12), pc)
			var title := str(aw.get("title", ""))
			var tx := x + 30.0          # the words start here (after the picture, when there is one)
			if Polish.on("award_art"):
				var side := r.size.y - 14.0
				if AwardArt.draw(c, title, Rect2(x + 22.0, y + 7.0, side, side)):
					tx = x + 30.0 + side
			var tw := 450.0 - (tx - x - 30.0)
			Art.text(c, Art.DISPLAY, Vector2(tx, y + r.size.y * 0.46), title, Art.fit_size(Art.DISPLAY, title, 34, tw, 18),
				Color(1.0, 0.86, 0.35), 5, edge, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
			var nm := str(aw.get("name", ""))
			var why := str(aw.get("why", ""))
			var nw := Art.BODY.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
			c.draw_string(Art.BODY, Vector2(tx, y + r.size.y * 0.82), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, pc.lightened(0.35))
			c.draw_string(Art.BODY, Vector2(tx + 8 + nw, y + r.size.y * 0.82), "· " + why, HORIZONTAL_ALIGNMENT_LEFT, tw - 10 - nw,
				Art.fit_size(Art.BODY, "· " + why, 26, tw - 10 - nw, 16), Color(0.9, 0.9, 0.96))
	# the lobby comes back: a pill with a bar that runs out
	var secs := ceili(left_ticks / 60.0)
	var pr := Rect2(660, 986, 600, 62)
	Art.panel(c, pr, Color(0.07, 0.04, 0.11, 0.92), Color(0.5, 0.4, 0.7), 31, Color(0, 0, 0, 0.45), 10)
	var frac := clampf(left_ticks / (END_S * 60.0), 0.0, 1.0)
	c.draw_style_box(Art.box(Color(gold, 0.85), Color(gold, 0.0), 6, 0, 0), Rect2(pr.position.x + 30, pr.end.y - 16, (pr.size.x - 60) * frac, 6))
	c.draw_string(Art.BODY, Vector2(pr.position.x, pr.position.y + 38), "THE LOBBY OPENS IN %d" % secs, HORIZONTAL_ALIGNMENT_CENTER,
		pr.size.x, 30, Color(0.95, 0.93, 1.0))

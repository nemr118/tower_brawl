# p4.9 the power-ups on the page, on every look (LOW too: they are part of play).
# An orb's warning: the electricity builds up over its spot, a ring closes in on the
# spot as the bolt comes (when it closes, the bolt strikes), the power-up's name over
# it. The lightning: the bench test's bolt, a flash, a shock ring. A body the bolt
# killed: the electricity runs through it (arcs, the body flickers: world.gd asks
# zapped()). The orbs, bobbing, their name under them; a BIG one gold. The pop when
# someone takes one (its name rises over them). The ghost cats, the rain, and what
# each fighter has: a shield bubble, wings, an umbrella, ice, spikes, speed lines.
# All drawn by hand (_draw), no particles. A child node on the glow layer adds the
# light: the bolt, the sparks, the glow of the orbs and cats, the flash.
extends Node2D

const LobbyArt = preload("res://client/lobby_art.gd")   # p4.19: its fonts
const UI_ICONS := preload("res://assets/ui_icons.png")  # p4.20: the painted crown (cell 5) over the match's leader
const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const GhostfaceScript = preload("res://client/ghostface.gd")
const Polish = preload("res://client/polish.gd")
const Season = preload("res://client/season.gd")   # p4.18: the season's names and pictures
const HV = preload("res://client/harvest_view.gd") # p4.18: the Harvest season's pictures
const XV = preload("res://client/christmas_view.gd")   # p4.22: the Christmas season's pictures
const RooftopsView = preload("res://client/rooftops_view.gd")   # p4.22: THE ROOFTOPS' gust of snow
const Hats = preload("res://client/hats.gd")       # p4.22: the marks over a head clear its winter hat (Hats.lift)
const ICONS2 := preload("res://assets/pu_icons.png")   # p4.13 polish "icons2": ComfyUI's power-up pictures (64 px a cell, kind - 1)
const TRICKS2 := preload("res://assets/trick_icons.png")   # 2026-10-26 polish "trick_art": the candy tricks' badges (64 px a cell)
const TRICK_ICON := 100           # the tricks' icon kinds (the page's own, never sent): + 0 PUMPKIN HEAD, + 1 BACKWARDS, + 2 TINY; GHOSTFACE is P.PU_MASK
const COLORS := {P.PU_FIRE: Color(1.0, 0.55, 0.15), P.PU_BOMB: Color(1.0, 0.32, 0.25), P.PU_POISON: Color(0.72, 0.4, 1.0),
	P.PU_SMOKE: Color(0.8, 0.82, 0.88), P.PU_SHIELD: Color(0.35, 0.85, 1.0), P.PU_INF: Color(1.0, 0.85, 0.3),
	P.PU_FLY: Color(0.95, 0.97, 1.0), P.PU_BIG: Color(0.5, 1.0, 0.45), P.PU_CATS: Color(0.55, 1.0, 0.6),
	P.PU_RAIN: Color(0.45, 0.65, 1.0), P.PU_INVIS: Color(0.85, 0.85, 1.0), P.PU_FREEZE: Color(0.6, 0.9, 1.0),
	P.PU_SPIKES: Color(1.0, 0.72, 0.3), P.PU_SPEED: Color(1.0, 0.95, 0.35),
	P.PU_TRICK: Color(0.85, 0.5, 1.0), P.PU_PUMPKIN: Color(1.0, 0.55, 0.1), P.PU_BATS: Color(0.62, 0.45, 0.85),
	P.PU_MASK: Color(0.96, 0.96, 1.0), P.PU_PIE: Color(1.0, 0.9, 0.72), P.PU_SNOWBALL: Color(0.78, 0.92, 1.0)}
const GOLD := Color(1.0, 0.82, 0.25)
const BOLT_COL := Color(0.62, 0.78, 1.0)
const ZAP_S := 1.8                 # the electricity runs through a body this long
const PV_WHITE := Color(1, 1, 1)

var world                          # the arena (its fx: flashes, lights, shake)
var glow_node: Node2D
var font: Font
var t := 0.0
var view := {}
var me := -1
var team: Array = []
var fighters := {}                 # seat -> the fighter as drawn this frame
var powers := {}                   # seat -> {bits, kind, left}
var zaps := {}                     # seat -> seconds of electricity left
var bolts: Array = []              # [to, secs left, big, points]
var pops: Array = []               # [pos, text, colour, secs left, secs, big, what it does]
var rings: Array = []              # [pos, max r, colour, secs, secs left]
var flash := 0.0                   # the arena lights up (a strike, a freeze), 1 .. 0
var flash_col := Color.WHITE
var drops: Array = []              # the rain's streaks
var jag_t := 0.0                   # the electricity is redrawn this often (it crackles)
var arcs := {}                     # key -> [PackedVector2Array]: the warnings' and the bodies' arcs
var blind := false                 # your fighter stands in smoke: the others are out of sight
var bolt_s := 0.4                  # a bolt shows this long (a test knob: the page's bolt_s= holds it for pictures)
var names: Array = []              # the seats' names (the game client sets them), for a BIG warning's "for"
var knife_at := {}                 # p4.12 GHOSTFACE: seat -> when (t) it last swung the knife
var down_at := {}                  # seat -> when it was knocked down
var up_at := {}                    # seat -> when it got back up
var hearts: Array = []             # [pos, secs left]: hearts rising from a petted cat
var candy_pops: Array = []         # p4.13 a candy opened: {pos, left, seat, word, icon, trick, at}
var confetti: Array = []           # [pos, vel, colour, secs left, spin]: a candy's wrapper bits
var pied := {}                     # p4.18 PIE: seat -> when (t) it was covered in cream
var phews: Array = []              # p4.19 PHEW: {at, seat, t0, what, dir}: the round's winner was hit after the call, and is safe
const PHEW_S := 1.7
var leader := -1                   # p4.20 (polish "juice"): the seat alone in the lead of the match (-1: nobody): a small crown over it
var taunts := {}                   # p4.19 the GOBBLE button: seat -> when (t) it last taunted
const TAUNT_S := 1.3
const TAUNT_WORDS := {"christmas": ["HO HO HO!", "BAH HUMBUG!", "SNOW WAY!", "NAUGHTY LIST!"], "harvest": ["GOBBLE!", "GOBBLE GOBBLE!", "YUM!"], "halloween": ["BOO!", "MUAHAHA!", "EEK!"], "": ["HA HA!", "NYAH NYAH!", "TOO SLOW!"]}
# p4.22 the Christmas season (client/christmas_view.gd draws them)
var ride_offs: Array = []          # [from, dir, t0]: a reindeer flying off after a ride
var knifed := {}                   # seat -> where its body was when the costume's swing knocked it out (this tick: its E_KILL follows)
var sacked := {}                   # KRAMPUS's seat -> the colours of those in his sack this round
var sack_fly: Array = []           # {from, by, col, t0}: one on its way into the sack
var gifts: Array = []              # {spot, floor, t0}: the giant present that just landed
var sleigh_outs: Array = []        # {x, t0}: the sleigh flying on after its drop
var squashed := {}                 # seat -> when (t) the present landed on it
var prints: Array = []             # [pos, t0, dir]: footprints in the snow (a snowy arena: world.fx.snowy), gone after PRINT_S
var print_x := {}                  # seat -> where it left its last footprint
const PRINT_S := 5.0
const PRINT_MAX := 96
var test_phew := false             # a test knob (the page's ?phew): a PHEW on your own fighter every 3 s (pictures)
var _phew_next := 2.0
var test_cream := false            # a test knob (the page's ?cream): the cream on your own screen, again and again (pictures)
const PIED_S := SimScript.PIED_TICKS / 60.0
const FEATHER_COLS := [Color(0.55, 0.3, 0.12), Color(0.95, 0.5, 0.1), Color(0.85, 0.2, 0.1), Color(0.98, 0.8, 0.25), Color(1, 1, 1)]
const CANDY_POP_S := 1.8
const CANDY_COLS := [Color(1.0, 0.55, 0.12), Color(0.62, 0.3, 0.95), Color(0.5, 0.95, 0.4), Color(1.0, 0.45, 0.75), Color(1, 1, 1)]

class _Glow extends Node2D:
	var pv
	func _draw() -> void:
		if pv != null:
			pv._paint_glow(self)

func setup(w, glow_parent: Node2D, add_mat: Material, colors: Array) -> void:
	world = w
	team = colors
	font = LobbyArt.BODY if Polish.on("hud2") else ThemeDB.fallback_font   # p4.19: the lobby's bold letters on the arena's labels too
	z_index = 5                     # over the arrows and clouds of the threats layer
	glow_node = _Glow.new()
	glow_node.pv = self
	glow_node.material = add_mat
	glow_parent.add_child(glow_node)
	for i in 110:
		drops.append(Vector2(randf() * 2000.0, randf() * 1080.0))

func raining() -> bool:
	return int(view.get("rain", {}).get("owner", P.NO_ONE)) != P.NO_ONE

func zapped(seat: int) -> bool:
	return zaps.has(seat)

# This frame's view (net.gd sample, or a deathcam frame) and your seat.
func show_view(s: Dictionary, delta: float, my_seat: int) -> void:
	t += delta
	view = s
	me = my_seat
	fighters.clear()
	for f in s.get("fighters", []):
		fighters[int(f["id"])] = f
	powers = s.get("powers", {})
	var mine: Dictionary = fighters.get(me, {})
	blind = not mine.is_empty() and mine["state"] != P.F_DEAD and (int(mine["flags"]) & 128) != 0
	for k in zaps.keys():
		zaps[k] -= delta
		if zaps[k] <= 0.0:
			zaps.erase(k)
	for b in bolts:
		b[1] -= delta
	bolts = bolts.filter(func(b): return b[1] > 0.0)
	for p in pops:
		p[3] -= delta
	pops = pops.filter(func(p): return p[3] > 0.0)
	phews = phews.filter(func(ph): return t - float(ph["t0"]) < PHEW_S)
	ride_offs = ride_offs.filter(func(r): return t - float(r[2]) < 0.8)
	sack_fly = sack_fly.filter(func(q): return t - float(q["t0"]) < 0.7)
	gifts = gifts.filter(func(q): return t - float(q["t0"]) < 0.54)
	sleigh_outs = sleigh_outs.filter(func(q): return t - float(q["t0"]) < 4.0)
	knifed.clear()
	# p4.22 footprints: on a snowy arena whoever runs on the ground leaves one every 18 px
	if world != null and world.fx != null and world.fx.snowy:
		for seat in fighters:
			var pf: Dictionary = fighters[seat]
			var pp: Dictionary = powers.get(seat, {})
			if pf["state"] == P.F_DEAD or (int(pf["flags"]) & 2) == 0 or (int(pp.get("bits", 0)) & (P.PW_INVIS | P.PW_BATS)) != 0:
				print_x.erase(seat)
				continue
			var px: float = float(pf["x"]) + 18.0
			if not print_x.has(seat) or absf(px - float(print_x[seat])) > 400.0:
				print_x[seat] = px          # (a first step, or through the wrap: no trail across the arena)
			elif absf(px - float(print_x[seat])) >= 18.0:
				prints.append([Vector2(px, float(pf["y"]) + 63.0), t, signf(px - float(print_x[seat]))])
				print_x[seat] = px
		if prints.size() > PRINT_MAX:
			prints = prints.slice(prints.size() - PRINT_MAX)
		prints = prints.filter(func(q): return t - float(q[1]) < PRINT_S)
	elif not prints.is_empty():
		prints.clear()
	if test_phew and t > _phew_next and fighters.has(me):
		_phew_next = t + 3.0
		on_event([P.E_PHEW, float(fighters[me]["x"]) + 40.0, float(fighters[me]["y"]) + 20.0, me, int(t / 3.0) % 3])
	for h in hearts:
		h[1] -= delta
	hearts = hearts.filter(func(h): return h[1] > 0.0)
	for cp in candy_pops:
		cp["left"] -= delta
	candy_pops = candy_pops.filter(func(cp): return cp["left"] > 0.0)
	for q in confetti:
		q[1] = q[1] * (1.0 - 1.5 * delta) + Vector2(0, 700.0 * delta)
		q[0] = q[0] + q[1] * delta
		q[3] -= delta
	confetti = confetti.filter(func(q): return q[3] > 0.0)
	for r in rings:
		r[4] -= delta
	rings = rings.filter(func(r): return r[4] > 0.0)
	flash = maxf(0.0, flash - delta * 3.0)
	if raining():
		for i in drops.size():
			var d: Vector2 = drops[i] + Vector2(-5.0, 30.0) * delta * 60.0
			if d.y > 1090.0:
				d = Vector2(randf() * 2000.0, -20.0)
			drops[i] = d
	jag_t -= delta
	if jag_t <= 0.0:
		jag_t = 0.06
		_new_arcs()
	queue_redraw()
	if glow_node != null:
		glow_node.queue_redraw()

# The electricity crackles: new arcs for each warning, each zapped body, each bolt.
func _new_arcs() -> void:
	arcs.clear()
	for o in view.get("orbs", []):
		if int(o["state"]) != P.ORB_WARN:
			continue
		var c := Vector2(o["x"], o["y"])
		var list: Array = []
		var n := 2 + int(float(o["prog"]) * 4.0)
		for i in n:
			var a := randf() * TAU
			var r := SimScript.STRIKE_R * randf_range(0.5, 1.1)
			list.append(_jag(c + Vector2.from_angle(a) * 8.0, c + Vector2.from_angle(a) * r, 5, 9.0))
		arcs["w%d:%d" % [int(o["x"]), int(o["y"])]] = list
	for seat in zaps:
		var f: Dictionary = fighters.get(seat, {})
		if f.is_empty():
			continue
		var c := Vector2(f["x"] + 18.0, f["y"] + 31.0)
		var list: Array = []
		for i in 4:
			var a := randf() * TAU
			list.append(_jag(c + Vector2.from_angle(a) * 6.0, c + Vector2.from_angle(a + randf_range(-0.8, 0.8)) * randf_range(26.0, 48.0), 4, 7.0))
		arcs["z%d" % seat] = list
	for b in bolts:
		b[3] = _bolt_points(b[0], b[2])

func _jag(a: Vector2, b: Vector2, n: int, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array([a])
	var nrm := (b - a).orthogonal().normalized()
	for i in range(1, n):
		pts.append(a.lerp(b, float(i) / n) + nrm * randf_range(-amp, amp))
	pts.append(b)
	return pts

func _bolt_points(to: Vector2, big: bool) -> PackedVector2Array:
	var x := to.x + randf_range(-60.0, 60.0)
	var pts := PackedVector2Array([Vector2(x, -20.0)])
	var y := -20.0
	while y < to.y - 70.0:
		y += randf_range(50.0, 110.0)
		x += randf_range(-55.0, 55.0) * (1.4 if big else 1.0)
		x = lerpf(x, to.x, clampf(y / maxf(1.0, to.y), 0.0, 1.0) * 0.35)
		pts.append(Vector2(x, minf(y, to.y - 30.0)))
	pts.append(to)
	return pts

func on_event(e: Array) -> void:
	var pos := Vector2(e[1], e[2])
	var type: int = e[0]
	if type == P.E_STRIKE and Season.christmas():
		# p4.22: no lightning in the season: the sleigh's giant present lands here (the same rule)
		gifts.append({"spot": pos, "floor": pos.y + SimScript.ORB_UP, "t0": t})
		sleigh_outs.append({"x": XV.sleigh_x(1.0, pos.x), "v": (pos.x + 330.0) / (XV.DROP_AT * SimScript.PU_WARN / 60.0), "t0": t})
		rings.append([pos + Vector2(0, SimScript.ORB_UP), SimScript.STRIKE_R * 2.0, Color(1, 1, 1, 0.9), 0.4, 0.4])
		world.fx.flash(pos, 5.0, Color(1.0, 0.95, 0.8), 0.25, true)
		world.fx.shake = maxf(world.fx.shake, 13.0 if e[4] == 1 else 9.0)
		for i in 18:
			var ang := TAU * i / 18.0 + randf() * 0.3
			confetti.append([pos, Vector2.from_angle(ang) * randf_range(200.0, 460.0) + Vector2(0, -220.0), XV.RIBBONS[i % XV.RIBBONS.size()],
				randf_range(0.8, 1.3), randf() * TAU])
	elif type == P.E_STRIKE:
		var big: bool = e[4] == 1
		bolts.append([pos, bolt_s, big, _bolt_points(pos, big)])
		flash = 1.0
		flash_col = Color(0.8, 0.88, 1.0)
		rings.append([pos, SimScript.STRIKE_R * (2.6 if big else 2.0), BOLT_COL, 0.45, 0.45])
		world.fx.flash(pos, 9.0, Color(0.8, 0.9, 1.0), 0.35, true)
		world.fx.light_burst(pos, Color(0.7, 0.8, 1.0), 3.5, 5.0, 0.4)
		world.fx.shake = maxf(world.fx.shake, 14.0 if big else 10.0)
		world.fx.aberration = 1.0
	elif type == P.E_DEATH and e[4] == 7 and Season.christmas():
		squashed[int(e[3])] = t          # p4.22: flat under the present, stars over it
		_pop(pos + Vector2(0, -40), "SQUASH!", Color(1.0, 0.9, 0.5), 1.2, true)
	elif type == P.E_DEATH and e[4] == 7:
		zaps[int(e[3])] = ZAP_S
	elif type == P.E_DEATH and e[4] == 11:
		knifed[int(e[3])] = pos           # (its E_KILL, in the same tick, says who swung)
	elif type == P.E_KILL and Season.christmas() and knifed.has(int(e[4])) and int(e[3]) != 255:
		# p4.22: knocked out by KRAMPUS: into his sack
		var who := int(e[4])
		var by := int(e[3])
		var col: Color = team[who % team.size()] if team.size() > 0 else Color.WHITE
		sack_fly.append({"from": knifed[who], "by": by, "col": col, "t0": t, "seat": who})
		if not sacked.has(by):
			sacked[by] = []
		sacked[by].append(col)
	elif type == P.E_SPAWN:               # a new round's fighter: nothing of the last round sticks to its seat
		sacked.erase(int(e[3]))
		squashed.erase(int(e[3]))
	elif type == P.E_SNOW:                # p4.22 a snowball bursts: its reach as a white ring, powder flying
		var sr: float = SimScript.SNOW_R * (SimScript.BIG_FX if e[4] == 1 else 1.0)
		rings.append([pos, sr, Color(0.92, 0.97, 1.0, 0.9), 0.45, 0.45])
		rings.append([pos, sr * 0.5, Color(1, 1, 1, 0.9), 0.3, 0.3])
		world.fx.flash(pos, 3.5, Color(0.85, 0.93, 1.0), 0.18, true)
		for i in 16:
			var ang := TAU * i / 16.0 + randf() * 0.4
			confetti.append([pos, Vector2.from_angle(ang) * randf_range(160.0, 440.0) + Vector2(0, -140.0), Color(0.95, 0.98, 1.0),
				randf_range(0.5, 0.9), randf() * TAU])
	elif type == P.E_SNOWED:              # packed into a snowman (_draw_kit draws it while it is frozen)
		_pop(pos + Vector2(0, -56), "BRRR!", Color(0.8, 0.93, 1.0), 1.1, true)
		rings.append([pos, 64.0, Color(1, 1, 1, 0.9), 0.3, 0.3])
	elif type == P.E_RIDE_END:            # the reindeer flies off
		var rf: Dictionary = fighters.get(int(e[3]), {})
		ride_offs.append([pos, 1.0 if rf.is_empty() or (int(rf["flags"]) & 1) != 0 else -1.0, t])
	elif type == P.E_PU_GET:
		var k: int = e[4]
		var col: Color = COLORS.get(k, Color.WHITE)
		var cp := _candy_pop_for(int(e[3]))
		if not cp.is_empty() and (cp["word"] == "TREAT" or k == P.PU_MASK):
			cp["word"] = P.pu_short(k, Season.now)   # p4.13: a candy's treat: its big badge shows it, no small one
			cp["icon"] = k
			return
		_pop(pos + Vector2(0, -36), P.pu_short(k, Season.now), col, 1.6, P.is_big(k) or k == P.PU_MASK, k)
		rings.append([pos + Vector2(0, 30), 110.0 if P.is_big(k) or k == P.PU_MASK else 80.0, col, 0.4, 0.4])
		world.fx.flash(pos + Vector2(0, 30), 4.0, col, 0.25, true)
	elif type == P.E_SHIELD_POP:
		rings.append([pos, 70.0, Color(0.45, 0.9, 1.0), 0.3, 0.3])
		_pop(pos + Vector2(0, -26), "BLOCK", Color(0.55, 0.95, 1.0), 0.9, false, P.PU_SHIELD)
		world.fx.flash(pos, 3.5, Color(0.5, 0.9, 1.0), 0.2, true)
	elif type == P.E_FREEZE:
		flash = 0.8
		flash_col = Color(0.55, 0.85, 1.0)
		rings.append([pos, 1100.0, Color(0.65, 0.92, 1.0), 0.7, 0.7])
	elif type == P.E_CAT_POOF:
		rings.append([pos, 60.0, Color(0.6, 1.0, 0.65), 0.3, 0.3])
		if e[4] == 1:
			_pop(pos + Vector2(0, -20), "CATCH!", Color(0.7, 1.0, 0.7), 0.9)
	elif type == P.E_PU_GONE:
		rings.append([pos, 46.0, Color(1, 1, 1, 0.7), 0.3, 0.3])
	elif type == P.E_KNIFE:      # p4.12 GHOSTFACE swings
		knife_at[int(e[3])] = t
	elif type == P.E_MASK_DOWN:
		down_at[int(e[3])] = t     # (its ring and a target mark say: hit it now)
		rings.append([pos, 70.0, Color(1.0, 0.32, 0.28), 0.35, 0.35])
		world.fx.shake = maxf(world.fx.shake, 5.0)
	elif type == P.E_MASK_UP:
		up_at[int(e[3])] = t
		rings.append([pos + Vector2(0, 28), 56.0, Color(0.85, 0.85, 0.95), 0.3, 0.3])   # a puff as it gets up
	elif type == P.E_TRICK:      # p4.12 TRICK OR TREAT (p4.13: from a candy; its big badge says what came out)
		var cp := _candy_pop_for(int(e[3]))
		if cp.is_empty():
			cp = _new_candy_pop(pos, int(e[3]))
		var b: int = e[4]
		cp["trick"] = b > 0 and b < 4
		cp["word"] = P.trick_name(b, Season.now)
		cp["icon"] = [P.PU_TRICK, TRICK_ICON, TRICK_ICON + 1, TRICK_ICON + 2, P.PU_MASK][clampi(b, 0, 4)]
	elif type == P.E_CANDY_DROP:  # p4.13 a candy out of a body, or from the sky
		rings.append([pos, 44.0, COLORS[P.PU_TRICK], 0.3, 0.3])
	elif type == P.E_CANDY_GET:   # someone opens one: a burst of wrapper bits, and a big badge
		_new_candy_pop(pos, int(e[3]))
		rings.append([pos, 120.0, COLORS[P.PU_TRICK], 0.45, 0.45])
		rings.append([pos, 70.0, Color(1.0, 0.6, 0.15), 0.3, 0.3])
		world.fx.flash(pos, 5.0, Color(0.9, 0.6, 1.0), 0.3, true)
		var wrap: Array = XV.RIBBONS if Season.christmas() else CANDY_COLS      # p4.22: a present's ribbons
		for i in 16:
			var ang := TAU * i / 16.0 + randf() * 0.3
			confetti.append([pos, Vector2.from_angle(ang) * randf_range(180.0, 420.0) + Vector2(0, -160.0),
				wrap[i % wrap.size()], randf_range(0.7, 1.1), randf() * TAU])
	elif type == P.E_CAT_COME:   # the black cat shows up (its own PET ME tag says the rest)
		if e[3] == 2:            # p4.22: the reindeer
			rings.append([pos + Vector2(0, -30), 90.0, Color(1.0, 0.88, 0.45), 0.5, 0.5])
			_pop(pos + Vector2(0, -110), "JINGLE JINGLE", Color(1.0, 0.9, 0.5), 1.4, true)
		elif e[3] == 1:            # p4.18: the turkey
			rings.append([pos + Vector2(0, -20), 80.0, Color(1.0, 0.7, 0.25), 0.5, 0.5])
			_pop(pos + Vector2(0, -60), "GOBBLE GOBBLE", Color(1.0, 0.85, 0.4), 1.4, true)
		else:
			rings.append([pos + Vector2(0, -14), 60.0, Color(0.75, 0.6, 1.0), 0.4, 0.4])
	elif type == P.E_PET and e[4] == 2:   # p4.22: someone gets on the reindeer: sparkles
		_pop(pos + Vector2(0, -70), "GIDDY UP!", Color(1.0, 0.9, 0.5), 1.2, true)
		rings.append([pos, 110.0, Color(1.0, 0.88, 0.45), 0.45, 0.45])
		world.fx.flash(pos, 4.0, Color(1.0, 0.9, 0.5), 0.25, true)
		for i in 14:
			var ang := TAU * i / 14.0 + randf() * 0.3
			confetti.append([pos, Vector2.from_angle(ang) * randf_range(140.0, 340.0) + Vector2(0, -200.0), Color(1.0, 0.92, 0.5),
				randf_range(0.6, 1.0), randf() * TAU])
	elif type == P.E_PET and e[4] == 1:   # p4.18: someone caught the turkey: feathers fly (its power-up's own pop follows)
		_pop(pos + Vector2(0, -44), "GOT IT!", Color(1.0, 0.85, 0.4), 1.2, true)
		rings.append([pos, 110.0, Color(1.0, 0.7, 0.25), 0.45, 0.45])
		world.fx.flash(pos, 4.0, Color(1.0, 0.8, 0.4), 0.25, true)
		for i in 18:
			var ang := TAU * i / 18.0 + randf() * 0.3
			confetti.append([pos, Vector2.from_angle(ang) * randf_range(140.0, 380.0) + Vector2(0, -200.0),
				FEATHER_COLS[i % FEATHER_COLS.size()], randf_range(0.8, 1.3), randf() * TAU])
	elif type == P.E_PET:        # someone petted it
		_pop(pos + Vector2(0, -10), "PURR", Color(1.0, 0.6, 0.8), 1.3, false, P.PU_SHIELD)
		hearts.append([pos, 1.2])
		rings.append([pos, 70.0, Color(1.0, 0.6, 0.8), 0.4, 0.4])
	elif type == P.E_PIE:        # p4.18: a pie splats: the cream's reach as a white ring
		var pr: float = SimScript.PIE_R * (SimScript.BIG_FX if e[4] == 1 else 1.0)
		rings.append([pos, pr, Color(1.0, 0.97, 0.9, 0.9), 0.5, 0.5])
		for i in 14:
			var ang := TAU * i / 14.0 + randf() * 0.4
			confetti.append([pos, Vector2.from_angle(ang) * randf_range(200.0, 520.0) + Vector2(0, -120.0), Color(1.0, 0.98, 0.93),
				randf_range(0.5, 0.9), randf() * TAU])
	elif type == P.E_PIED:       # covered in cream (your own screen gets the splat: _draw)
		pied[int(e[3])] = t
		_pop(pos + Vector2(0, -30), "SPLAT!", Color(1.0, 0.97, 0.9), 1.0, true)
	elif type == P.E_PHEW:       # p4.19: the round was called, then something hit its winner. The winner is safe (the user:
		# "winner is safe, but can we do something silly to show the winner would have died?"): what hit
		# turns into a drumstick (a rubber chicken out of the Harvest season) and bounces off; PHEW! over the winner.
		var who := int(e[3])
		var fw: Dictionary = fighters.get(who, {})
		var away := 1.0 if fw.is_empty() or pos.x >= float(fw["x"]) + 18.0 else -1.0
		phews.append({"at": pos, "seat": who, "t0": t, "what": int(e[4]), "dir": away})
		_pop(pos + Vector2(0, -40), ["TOO LATE!", "NICE TRY!", "NOPE!"][clampi(int(e[4]), 0, 2)], GOLD, 1.5, true)
		rings.append([pos, 70.0, Color(1, 1, 1, 0.9), 0.3, 0.3])
		for i in 14:
			var ang := TAU * i / 14.0 + randf() * 0.4
			confetti.append([pos, Vector2.from_angle(ang) * randf_range(160.0, 420.0) + Vector2(0, -160.0), CANDY_COLS[i % CANDY_COLS.size()],
				randf_range(0.7, 1.2), randf() * TAU])
	elif type == P.E_TAUNT:      # p4.19: a taunt: a speech bubble over the fighter (the words by the season)
		taunts[int(e[3])] = t
	elif type == P.E_CATCH_UP:   # far behind: a SHIELD from the start
		rings.append([pos + Vector2(0, 30), 80.0, COLORS[P.PU_SHIELD], 0.5, 0.5])
		_pop(pos + Vector2(0, -36), "HEAD START", COLORS[P.PU_SHIELD], 1.6, false, P.PU_SHIELD)
	elif type == P.E_BATS:       # a swarm screeches at the edge it comes in from
		var at := Vector2(clampf(pos.x, 120.0, 1800.0), pos.y)
		if world != null and world.level != null and world.level.theme == "barn":   # p4.18: the barn's gust of leaves
			_pop(at, "WIND!", Color(1.0, 0.85, 0.5), 1.3, true)
		elif world != null and world.level != null and world.level.theme == "rooftops":   # p4.22: the rooftops' gust of snow
			_pop(at, "BRRR!", Color(0.82, 0.93, 1.0), 1.3, true)
		else:
			_pop(at, "", Color(0.8, 0.65, 1.0), 1.3, true, P.PU_BATS)
	elif type == P.E_GHOST:      # p4.11: a ghost rises from its body
		rings.append([pos, 60.0, Color(0.85, 0.9, 1.0, 0.8), 0.5, 0.5])
	elif type == P.E_BOO:
		if e[4] == 255:          # the dash starts: a whoosh
			rings.append([pos, 40.0, Color(0.9, 0.95, 1.0, 0.7), 0.25, 0.25])
		else:                    # it shoved someone: BOO!
			_pop(pos + Vector2(0, -30), "BOO!", Color(0.92, 0.96, 1.0), 1.0, true)
			rings.append([pos, 80.0, Color(0.9, 0.95, 1.0, 0.9), 0.3, 0.3])
			world.fx.shake = maxf(world.fx.shake, 5.0)
	elif type == P.E_GHOST_POP:  # an arrow popped a ghost
		rings.append([pos, 55.0, Color(0.8, 0.85, 1.0, 0.9), 0.3, 0.3])
		_pop(pos + Vector2(0, -20), "POP!", Color(0.8, 0.85, 1.0), 0.8)

# ------------------------------------------------------------------ the main layer (never darkened)
func _draw() -> void:
	var xmas := Season.christmas()
	if raining() and xmas:
		XV.blizzard(self, drops, t)      # p4.22: RAIN is a BLIZZARD
	elif raining():
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.12, 0.16, 0.3, 0.18))
		for d in drops:
			draw_line(d, d + Vector2(-4.0, 22.0), Color(0.7, 0.8, 1.0, 0.45), 2.0)
	for o in view.get("orbs", []):
		if int(o["state"]) == P.ORB_WARN:
			_draw_warning(o)
		else:
			_draw_orb(o)
	for q in prints:                     # p4.22: footprints in the snow, fading
		var pa: float = clampf(1.0 - (t - float(q[1])) / PRINT_S, 0.0, 1.0)
		var pv: Vector2 = q[0]
		draw_rect(Rect2(pv.x - 4.0 + float(q[2]) * 2.0, pv.y - 5.0, 7.0, 3.0), Color(0.3, 0.42, 0.62, 0.8 * pa))
	for q in gifts:                      # p4.22: the giant present that just landed bursts open over its orb
		XV.landed_gift(self, q["spot"], float(q["floor"]), t - float(q["t0"]))
	for cd in view.get("candies", []):
		_draw_candy(cd)
	for seat in fighters:   # p4.12 GHOSTFACE, in place of its archer (dead ones too: it lies there)
		if not powers.has(seat) or (int(powers[seat].get("mask", 0)) & 1) == 0:
			continue
		var gf: Dictionary = fighters[seat]
		var hid: bool = gf["state"] != P.F_DEAD and (int(powers[seat]["bits"]) & (P.PW_INVIS | P.PW_BATS)) != 0
		if seat != me and gf["state"] != P.F_DEAD and (hid or blind):
			continue
		var gtc: Color = team[seat % team.size()] if team.size() > 0 else Color.WHITE
		if Season.harvest():      # p4.18: THE BIG TURKEY
			HV.big_turkey(self, gf, powers[seat], 0.35 if hid else 1.0, t, gtc, knife_at.get(seat, -9.0))
		elif xmas:                # p4.22: KRAMPUS
			XV.krampus(self, gf, powers[seat], 0.35 if hid else 1.0, t, gtc, knife_at.get(seat, -9.0), sacked.get(seat, []))
		else:
			GhostfaceScript.draw(self, gf, powers[seat], 0.35 if hid else 1.0, t, gtc, knife_at.get(seat, -9.0), down_at.get(seat, -9.0), up_at.get(seat, -9.0))
		if (int(powers[seat]["mask"]) & 2) != 0 and gf["state"] != P.F_DEAD:   # down: a ring counts its 2 seconds
			var rc := Vector2(gf["x"] + 18.0, gf["y"] + 40.0)
			var left := clampf(1.0 - (t - down_at.get(seat, t)) / (SimScript.MASK_DOWN / 60.0), 0.0, 1.0)
			draw_arc(rc, 38.0, -PI * 0.5, -PI * 0.5 + TAU * left, 40, Color(1.0, 0.28, 0.22, 0.9), 4.0, true)
			if seat != me:   # a target mark on it: hit it now
				var tm := Color(1.0, 0.4, 0.35, 0.55 + 0.4 * sin(t * 12.0))
				draw_arc(rc, 16.0, 0.0, TAU, 20, tm, 2.0, true)
				for q in 4:
					var dv := Vector2.from_angle(q * PI * 0.5 + t * 1.5)
					draw_line(rc + dv * 10.0, rc + dv * 24.0, tm, 2.5, true)
	for seat in fighters:
		var f: Dictionary = fighters[seat]
		if f["state"] == P.F_DEAD or not powers.has(seat):
			continue
		var bits: int = powers[seat]["bits"]
		if powers[seat].get("swarm", false):
			_draw_circling_bats(f, seat)   # BAT SWARM: its bats show where it hides
		if seat != me and ((bits & (P.PW_INVIS | P.PW_BATS)) != 0 or blind):
			continue
		if (int(powers[seat].get("mask", 0)) & P.PX_RIDE) != 0:   # p4.22: on the reindeer
			XV.mount(self, f, 0.35 if (bits & (P.PW_INVIS | P.PW_BATS)) != 0 else 1.0, t)
		_draw_kit(f, powers[seat], 0.35 if (bits & (P.PW_INVIS | P.PW_BATS)) != 0 else 1.0)
	for r in ride_offs:                  # p4.22: a reindeer flying off after its ride
		XV.fly_off(self, r[0], float(r[1]), t - float(r[2]))
	for q in sack_fly:                   # one on its way into KRAMPUS's sack
		var kf: Dictionary = fighters.get(int(q["by"]), {})
		if not kf.is_empty():
			var kd := 1.0 if (int(kf["flags"]) & 1) != 0 else -1.0
			XV.into_sack(self, q["from"], Vector2(float(kf["x"]) + 18.0 - kd * 34.0, float(kf["y"]) + 63.0 - XV.KRAMPUS_H * 0.6), q["col"], t - float(q["t0"]))
	for seat in squashed:                # flat under the present: stars over the body
		var sf: Dictionary = fighters.get(seat, {})
		var sage: float = t - float(squashed[seat])
		if not sf.is_empty() and sf["state"] == P.F_DEAD and sage < 2.2:
			XV.stars(self, Vector2(float(sf["x"]) + 18.0, float(sf["y"]) + 50.0), t, clampf((2.2 - sage) * 2.0, 0.0, 1.0))
	if xmas and world != null and world.level != null and (world.level.theme == "" or world.level.theme == "rooftops"):
		for seat in fighters:            # out in the cold: a breath now and then from whoever stands still
			var bf: Dictionary = fighters[seat]
			var bp: Dictionary = powers.get(seat, {})
			if bf["state"] == P.F_DEAD or (int(bf["flags"]) & 2) == 0 or absf(float(bf.get("vx", 0.0))) > 0.5:
				continue
			if (int(bp.get("mask", 0)) & 1) != 0 or (int(bp.get("bits", 0)) & (P.PW_INVIS | P.PW_BATS | P.PW_PUMPKIN | P.PW_FROZEN)) != 0 or (seat != me and blind):
				continue
			var ph := fposmod(t * 0.42 + seat * 0.37, 1.0)
			if ph < 0.4:
				XV.breath(self, Vector2(float(bf["x"]) + 18.0, float(bf["y"]) + 12.0), 1.0 if (int(bf["flags"]) & 1) != 0 else -1.0, ph / 0.4)
	for c in view.get("cats", []):
		_draw_cat(c)
	for g in view.get("ghosts", []):
		_draw_ghost(g)
	if not view.get("pet", {}).is_empty():
		_draw_pet(view["pet"])
	if not view.get("bats", {}).is_empty():
		_draw_swarm(view["bats"])
	for r in rings:
		var k: float = 1.0 - r[4] / r[3]
		var col: Color = r[2]
		col.a *= 1.0 - k
		draw_arc(r[0], r[1] * (0.2 + 0.8 * k), 0.0, TAU, 40, col, 5.0 * (1.0 - k) + 2.0)
	for q in confetti:   # p4.13 a candy's wrapper bits
		var qa: float = clampf(q[3] * 1.6, 0.0, 1.0)
		var sp: float = q[4] + t * 9.0
		var u := Vector2(cos(sp), sin(sp)) * 5.0
		var v := Vector2(-u.y, u.x) * 0.5
		draw_colored_polygon(PackedVector2Array([q[0] - u - v, q[0] + u - v, q[0] + u + v, q[0] - u + v]), Color(q[2], qa))
	for cp in candy_pops:   # p4.13 the big candy badge: what came out of it
		_draw_candy_pop(cp)
	for h in hearts:   # a petted cat: three little hearts float up
		var hk: float = h[1] / 1.2
		for i in 3:
			_heart(h[0] + Vector2((i - 1) * 16.0 + sin(t * 5.0 + i) * 4.0, -20.0 - (1.0 - hk) * (50.0 + i * 12.0)), 5.0, Color(1.0, 0.45, 0.7, hk))
	for p in pops:
		var k: float = p[3] / p[4]
		var at: Vector2 = p[0] + Vector2(0, -46.0 * (1.0 - k))
		var a := clampf(k * 2.5, 0.0, 1.0)
		var col: Color = p[2]
		var kind: int = p[7] if p.size() > 7 else -1
		if kind >= 0:   # a badge with the picture, and one small word under it
			var r := (17.0 if p[5] else 14.0) * (1.0 + 0.35 * clampf((k - 0.85) / 0.15, 0.0, 1.0))
			draw_circle(at, r + 3.0, Color(0.03, 0.03, 0.07, 0.75 * a))
			draw_circle(at, r, Color(disc(col), a))
			draw_arc(at, r, 0.0, TAU, 24, Color(GOLD if p[5] else PV_WHITE, a), 2.0)
			draw_icon(self, at, kind, r * 0.62, Color(0.08, 0.06, 0.12, a), t)
			if p[1] != "":
				_text_c(at + Vector2(0, r + 18.0), p[1], 17 if p[5] else 15, Color(col.lerp(Color.WHITE, 0.4), a))
		else:
			_text_c(at, p[1], 22 if p[5] else 18, Color(col, a))
	if leader >= 0 and fighters.has(leader):      # p4.20: the leader's crown, bobbing over its head
		var lf: Dictionary = fighters[leader]
		var lp: Dictionary = powers.get(leader, {})
		var lhid: bool = leader != me and (blind or (int(lp.get("bits", 0)) & (P.PW_INVIS | P.PW_BATS)) != 0)
		if lf["state"] != P.F_DEAD and not lhid:
			var up := 62.0 if (int(lp.get("mask", 0)) & 1) != 0 else 40.0 + Hats.lift(leader)     # a costume is taller; p4.22: over the hat
			draw_texture_rect_region(UI_ICONS, Rect2(float(lf["x"]) + 18.0 - 16.0, float(lf["y"]) - up + sin(t * 3.0) * 2.5, 32, 32),
				Rect2(5 * 128, 0, 128, 128))
	for ph in phews:
		_draw_phew(ph)
	if xmas:                             # p4.22: the sleigh, over everything in the arena: flying in over a drop, flying on after it
		for o in view.get("orbs", []):
			if int(o["state"]) == P.ORB_WARN:
				XV.sleigh(self, XV.sleigh_x(float(o["prog"]), float(o["x"])), t, 1.0)
		for q in sleigh_outs:
			var sx: float = float(q["x"]) + float(q["v"]) * (t - float(q["t0"]))
			if sx < 2300.0:
				XV.sleigh(self, sx, t, 1.0)
	for seat in taunts:
		var tage: float = t - float(taunts[seat])
		var tf: Dictionary = fighters.get(seat, {})
		if tage < TAUNT_S and not tf.is_empty() and tf["state"] != P.F_DEAD:
			var words: Array = TAUNT_WORDS.get(Season.now, TAUNT_WORDS[""])
			var tcol: Color = team[seat % team.size()] if team.size() > 0 else Color.WHITE
			_bubble(Vector2(float(tf["x"]) + 18.0, float(tf["y"]) - 6.0), str(words[(seat + int(float(taunts[seat]) * 3.0)) % words.size()]), tage,
				clampf((1.0 - tage / TAUNT_S) * 4.0, 0.0, 1.0), tcol.lerp(Color.WHITE, 0.82))
	var cream_k := clampf(1.0 - (t - float(pied.get(me, -99.0))) / PIED_S, 0.0, 1.0)
	if test_cream:
		_draw_cream_screen(1.0 - fposmod(t, PIED_S) / PIED_S)
	elif blind and cream_k > 0.0:
		_draw_cream_screen(cream_k)   # p4.18 PIE: cream over your own screen, sliding off
	elif blind:
		draw_rect(Rect2(0, 0, 1920, 1080), Color(0.5, 0.52, 0.58, 0.32))
		var mine: Dictionary = fighters.get(me, {})
		if not mine.is_empty():   # in the smoke: a closed eye over your head (you can't see anyone)
			var ec := Vector2(mine["x"] + 18.0, mine["y"] - 22.0)
			draw_circle(ec, 15.0, Color(0.03, 0.03, 0.07, 0.7))
			draw_arc(ec + Vector2(0, -4), 9.0, 0.35, PI - 0.35, 10, Color(1, 1, 1, 0.9), 2.5, true)
			for i in 3:
				var lx := -5.0 + i * 5.0
				draw_line(ec + Vector2(lx, 4.0), ec + Vector2(lx * 1.3, 8.0), Color(1, 1, 1, 0.9), 2.0, true)

# p4.13 a candy: a wrapped sweet with orange and purple stripes and twisted ends, a soft
# glow; resting it bobs and wiggles, falling it spins (from the sky: sparkles above it);
# it blinks in its last 2 seconds.
func _draw_candy(cd: Dictionary) -> void:
	if Season.harvest():      # p4.18: a covered dish
		HV.dish(self, cd, t)
		return
	if Season.christmas():    # p4.22: a wrapped present
		XV.present(self, cd, t)
		return
	var rest: bool = (int(cd["flags"]) & 1) != 0
	var a := 1.0
	if int(cd["life"]) < 120 and int(t * 8.0) % 2 == 0:
		a = 0.35
	var c := Vector2(cd["x"], cd["y"])
	var rot := t * 10.0
	if rest:
		c.y += sin(t * 3.0 + c.x * 0.05) * 3.0 - 3.0
		rot = sin(t * 5.0 + c.x) * 0.3
	elif (int(cd["flags"]) & 2) != 0:
		for k in 3:   # a falling star's sparkles
			var sp := c + Vector2(sin(t * 7.0 + k * 2.0) * 8.0, -16.0 - k * 12.0)
			draw_circle(sp, 2.5 - k * 0.6, Color(1.0, 0.92, 0.6, (0.8 - k * 0.2) * a))
	draw_circle(c, 34.0, Color(0.85, 0.5, 1.0, 0.12 * a))
	draw_circle(c, 21.0, Color(1.0, 0.7, 0.3, 0.14 * a))
	var pulse := fmod(t * 0.9 + c.x * 0.003, 1.0)   # a ring that grows and fades: something to grab
	draw_arc(c, 18.0 + 26.0 * pulse, 0.0, TAU, 28, Color(1.0, 0.8, 0.4, (1.0 - pulse) * 0.6 * a), 2.5, true)
	draw_set_transform(c, rot, Vector2.ONE * 1.4)
	var edge := Color(0.14, 0.04, 0.2, a)
	var wrap := Color(0.62, 0.3, 0.95, a)
	for side in [-1.0, 1.0]:   # the twisted ends
		var tri := PackedVector2Array([Vector2(side * 8.0, 0), Vector2(side * 18.0, -8.0), Vector2(side * 18.0, 8.0)])
		draw_colored_polygon(tri, wrap)
		tri.append(tri[0])
		draw_polyline(tri, edge, 1.5, true)
	var body := PackedVector2Array()
	for i in 16:
		var th := TAU * i / 16.0
		body.append(Vector2(cos(th) * 10.0, sin(th) * 8.0))
	draw_colored_polygon(body, Color(1.0, 0.55, 0.12, a))
	for k in 3:   # the stripes
		var sx := -5.0 + k * 5.0
		draw_line(Vector2(sx - 2.5, 6.0), Vector2(sx + 2.5, -6.0), wrap, 2.5, true)
	body.append(body[0])
	draw_polyline(body, edge, 1.6, true)
	draw_circle(Vector2(-4.0, -3.5), 2.0, Color(1, 1, 1, 0.75 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _new_candy_pop(pos: Vector2, seat: int) -> Dictionary:
	var cp := {"pos": pos + Vector2(0, -40), "left": CANDY_POP_S, "seat": seat, "word": "", "icon": P.PU_TRICK, "trick": false, "at": t}
	candy_pops.append(cp)
	return cp

# The candy badge this seat opened a moment ago (its TRICK OR TREAT result follows in the same tick).
func _candy_pop_for(seat: int) -> Dictionary:
	for i in range(candy_pops.size() - 1, -1, -1):
		if candy_pops[i]["seat"] == seat and t - float(candy_pops[i]["at"]) < 0.25:
			return candy_pops[i]
	return {}

# The big candy badge: a ring of candy stripes, what came out of the candy inside, its name
# under it, and TREAT! or TRICK! over it; it pops in, rises and fades.
func _draw_candy_pop(cp: Dictionary) -> void:
	var k: float = cp["left"] / CANDY_POP_S
	var a := clampf(k * 2.5, 0.0, 1.0)
	var at: Vector2 = cp["pos"] + Vector2(0, -60.0 * (1.0 - k))
	var r := 24.0 * (1.0 + 0.4 * clampf((k - 0.85) / 0.15, 0.0, 1.0))
	draw_circle(at, r + 6.0, Color(0.03, 0.03, 0.07, 0.8 * a))
	var xmas := Season.christmas()
	for i in 8:   # the striped ring (p4.22: red and green, a present's ribbon)
		var a0 := t * 2.0 + i * TAU / 8.0
		draw_arc(at, r + 3.0, a0, a0 + TAU / 8.0, 6, Color(XV.RIBBONS[i % 2] if xmas else CANDY_COLS[i % 2], a), 5.0)
	var icon: int = cp["icon"]
	draw_circle(at, r, Color(disc(COLORS.get(P.PU_TRICK if icon >= TRICK_ICON else icon, Color.WHITE)), a))
	draw_icon(self, at, icon, r * 0.62, Color(0.08, 0.06, 0.12, a), t)
	var top := "TRICK!" if cp["trick"] else (("GOBBLE!" if Season.harvest() else "BOO!") if icon == P.PU_MASK else "TREAT!")
	if xmas:
		top = "COAL!" if cp["trick"] else ("GRRR!" if icon == P.PU_MASK else "A GIFT!")
	_text_c(at + Vector2(0, -r - 12.0), top, 16, Color(1.0, 0.75, 0.3, a))
	if str(cp["word"]) != "":
		_text_c(at + Vector2(0, r + 24.0), str(cp["word"]), 20, Color(1.0, 0.95, 0.85, a))

# A pop over someone (p4.12): a badge with a power-up's picture and one small word, rising
# and fading (the user: "graphics or small stylized text that disrupts the game as little
# as possible"); with no picture (kind -1), the small word alone.
func _pop(pos: Vector2, word: String, col: Color, secs: float, big := false, kind := -1) -> void:
	pops.append([pos, word, col, secs, secs, big, "", kind])

func _draw_warning(o: Dictionary) -> void:
	var c := Vector2(o["x"], o["y"])
	var prog: float = o["prog"]
	var feet := c + Vector2(0, SimScript.ORB_UP)
	var col: Color = COLORS.get(int(o["kind"]), Color.WHITE)
	var big: bool = o["big"]
	var R: float = SimScript.STRIKE_R
	if Season.christmas() and prog > XV.DROP_AT:      # p4.22: the sleigh let the giant present go: it falls to the spot
		XV.drop_gift(self, c, feet.y, (prog - XV.DROP_AT) / (1.0 - XV.DROP_AT), t)
	# the danger: a pale disc where the bolt kills, and a ring closing in on it
	draw_circle(c, R, Color(0.6, 0.8, 1.0, 0.06 + 0.12 * prog))
	draw_arc(c, R, 0.0, TAU, 40, Color(0.75, 0.88, 1.0, 0.5 + 0.4 * prog), 3.0)
	draw_arc(c, R * (1.0 + 2.2 * (1.0 - prog)), 0.0, TAU, 48, Color(0.75, 0.88, 1.0, 0.25 + 0.6 * prog), 4.0)
	# the count to the bolt, big in the middle of the danger (3, 2, 1): stand back, then grab it
	var secs := ceili((1.0 - prog) * SimScript.PU_WARN / 60.0)
	_text_c(c + Vector2(0, 14), str(maxi(1, secs)), 38, Color(1.0, 1.0, 1.0, 0.55 + 0.4 * prog))
	var pulse := 0.5 + 0.5 * sin(t * (10.0 + 20.0 * prog))
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.28))
	draw_arc(Vector2.ZERO, R * 0.9, 0.0, TAU, 32, Color(0.85, 0.93, 1.0, 0.4 + 0.5 * pulse), 5.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# what it will drop, over it: its picture (p4.12: no name), and whom a BIG one is for
	var a := 0.55 + 0.45 * prog
	var ic := c + Vector2(0, -R - 34.0)
	draw_circle(ic, 24.0, Color(0.05, 0.05, 0.1, 0.8 * a))
	draw_circle(ic, 20.0, Color(disc(col), a))
	draw_arc(ic, 20.0, 0.0, TAU, 24, Color(PV_WHITE if not big else GOLD, a), 3.0)
	draw_icon(self, ic, int(o["kind"]), 13.0, Color(0.08, 0.06, 0.12, a), t)
	if big:   # a gold ring, and the name of the one it is for, small
		draw_arc(ic, 28.0, 0.0, TAU, 28, Color(GOLD, a * (0.6 + 0.4 * pulse)), 3.0)
		var who := int(o.get("for", 255))
		if who == me and me >= 0:     # p4.18: yours: said big, with arrows from your fighter
			_for_you(ic + Vector2(0, -40.0), c, a)
		elif who >= 0 and who < names.size() and str(names[who]) != "":
			_text_c(ic + Vector2(0, -38.0), "for " + str(names[who]), 16, Color(GOLD, a))

# p4.18 a BIG power-up that came for you (the October logs: 60% of them were never taken;
# nothing said whose they were): FOR YOU over it, pulsing, and three gold arrowheads
# running from your fighter towards it (the short way, through the wrap).
func _for_you(label_at: Vector2, orb: Vector2, a: float) -> void:
	var pulse := 0.75 + 0.25 * sin(t * 9.0)
	_text_c(label_at, "FOR YOU", 24, Color(GOLD.lerp(Color.WHITE, 0.3), a * pulse))
	var mine: Dictionary = fighters.get(me, {})
	if mine.is_empty() or mine["state"] == P.F_DEAD:
		return
	var from := Vector2(mine["x"] + 18.0, mine["y"] + 31.0)
	var d := Vector2(SimScript.wrap_d(from.x, orb.x, 1920.0), SimScript.wrap_d(from.y, orb.y, 1080.0))
	var dist := d.length()
	if dist < 150.0:
		return
	var u := d / dist
	var v := Vector2(-u.y, u.x)
	for i in 3:
		var k := fmod(t * 1.4 + i / 3.0, 1.0)
		var at := from + u * (70.0 + k * minf(180.0, dist - 110.0))
		draw_colored_polygon(PackedVector2Array([at + u * 13.0, at - u * 7.0 + v * 10.0, at - u * 2.0, at - u * 7.0 - v * 10.0]),
			Color(GOLD, a * (1.0 - k) * 0.95))

# p4.18 PIE on your own screen: big blobs of cream that slide down and thin out (k: 1 just
# hit, 0 gone), and the words. The others are out of sight meanwhile (the smoke rule).
func _draw_cream_screen(k: float) -> void:
	var a := clampf(k * 2.4, 0.0, 1.0)       # thick at first; it thins out over the last second
	draw_rect(Rect2(0, 0, 1920, 1080), Color(1.0, 0.98, 0.94, 0.14 * a))
	var mine: Dictionary = fighters.get(me, {})
	var my_at := Vector2(mine["x"] + 18.0, mine["y"] + 31.0) if not mine.is_empty() else Vector2(-9999, -9999)
	for i in 11:
		var bx := 90.0 + i * 178.0 + sin(i * 2.3) * 70.0
		var by := 170.0 + fposmod(i * 371.0, 620.0) + (1.0 - k) * (220.0 + i * 26.0)
		var br := (140.0 + (i % 3) * 46.0) * (0.5 + 0.5 * k)
		var c := Vector2(bx, by)
		if c.distance_to(my_at) < br + 100.0:
			continue               # never over your own fighter: you can still see where you stand
		draw_rect(Rect2(bx - br * 0.2, by, br * 0.4, br * (1.25 + 1.5 * (1.0 - k))), Color(0.99, 0.96, 0.88, 0.9 * a))   # a drip
		draw_circle(c + Vector2(0, br * (1.25 + 1.5 * (1.0 - k))), br * 0.2, Color(0.99, 0.96, 0.88, 0.9 * a))
		draw_circle(c, br * 1.04, Color(0.9, 0.84, 0.7, 0.9 * a))              # the dollop's shaded edge
		draw_circle(c, br, Color(1.0, 0.985, 0.93, 0.94 * a))
		draw_circle(c + Vector2(-br * 0.22, -br * 0.25), br * 0.55, Color(1, 1, 1, 0.9 * a))
	_text_c(Vector2(960, 300), "PIE IN THE FACE!", 60, Color(0.85, 0.4, 0.1, a))

func _draw_orb(o: Dictionary) -> void:
	var big: bool = o["big"]
	var r := 30.0 if big else 22.0
	var c := Vector2(o["x"], o["y"] + sin(t * 3.0 + o["x"] * 0.01) * 5.0)
	var col: Color = COLORS.get(int(o["kind"]), Color.WHITE)
	var a := 1.0
	if float(o["prog"]) > 0.8 and int(t * 8.0) % 2 == 0:
		a = 0.35                     # about to fade: it blinks
	draw_circle(c, r + 4.0, Color(0.05, 0.05, 0.1, 0.8 * a))
	draw_circle(c, r, Color(disc(col), a))
	if Polish.on("icons2"):   # a thin shine, so the colour picture inside stays clear
		draw_arc(c, r * 0.82, PI * 1.08, PI * 1.45, 8, Color(1, 1, 1, 0.5 * a), 2.0)
	else:
		draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.35, Color(1, 1, 1, 0.55 * a))
	draw_arc(c, r, 0.0, TAU, 32, Color(col.lerp(Color.WHITE, 0.5) if Polish.on("icons2") else Color.WHITE, 0.9 * a), 3.0)
	draw_icon(self, c, int(o["kind"]), r * 0.62, Color(0.08, 0.06, 0.12, a), t)
	if big:
		for i in 8:
			var a0 := t * 1.5 + i * TAU / 8.0
			draw_arc(c, r + 12.0, a0, a0 + 0.45, 6, Color(GOLD, a), 5.0)
		if int(o.get("for", 255)) == me and me >= 0:
			_for_you(c + Vector2(0, -r - 22.0), c, a)

# A picture of each power-up (the web font has no symbols), moving so it reads at a
# glance: the flame flickers, the bomb's fuse sparks, poison bubbles, smoke drifts,
# the shield shines, a dot runs round INFINITE's loop, wings flap, the BIG arrow
# grows, the cat's ears twitch, rain falls under the umbrella, the eye blinks, the
# snowflake turns, the spikes bob, the bolt flashes. ci: any canvas; tt: seconds.
# The disc behind a power-up's picture: its colour, darker; with ComfyUI's colour pictures
# (polish "icons2") much darker, so the picture stands out.
# The power-up an arrow kind came from (0: a plain arrow): the first four share their
# numbers; p4.12 PUMPKIN BOMBS, p4.18 PIE.
static func arrow_power(kind: int) -> int:
	if kind >= P.A_FIRE and kind <= P.A_SMOKE:
		return kind
	if kind == P.A_PUMPKIN:
		return P.PU_PUMPKIN
	if kind == P.A_PIE:
		return P.PU_PIE
	if kind == P.A_SNOWBALL:
		return P.PU_SNOWBALL
	return 0

static func disc(col: Color) -> Color:
	return col.darkened(0.62) if Polish.on("icons2") else col.darkened(0.25)

static func draw_icon(ci: CanvasItem, c: Vector2, kind: int, s: float, col: Color, tt: float) -> void:
	var hc := HV.icon_cell(kind, TRICK_ICON, Season.harvest())   # p4.18: PIE's badge, and the Harvest season's own
	if hc >= 0:
		HV.icon(ci, c, hc, s, col.a, tt)
		return
	var xc := XV.icon_cell(kind, TRICK_ICON, Season.christmas())   # p4.22: SNOWBALLS' badge, and the Christmas season's own
	if xc >= 0:
		XV.icon(ci, c, xc, s, col.a, tt)
		return
	if kind >= TRICK_ICON or kind == P.PU_MASK:   # 2026-10-26: a candy trick's badge (and GHOSTFACE's), bobbing like the others
		if Polish.on("trick_art"):
			var cell := 3 if kind == P.PU_MASK else clampi(kind - TRICK_ICON, 0, 2)
			var th := s * 1.25
			var tbob := sin(tt * 3.0 + kind) * s * 0.05
			ci.draw_texture_rect_region(TRICKS2, Rect2(c + Vector2(-th, -th + tbob), Vector2(th, th) * 2.0),
				Rect2(cell * 64, 0, 64, 64), Color(1, 1, 1, col.a))
			return
		if kind >= TRICK_ICON:   # the switch off: the icons p4.13 used for them
			kind = P.PU_PUMPKIN if kind == TRICK_ICON else P.PU_TRICK
	if kind >= 1 and kind <= 17 and Polish.on("icons2"):   # p4.13: ComfyUI's picture, bobbing a little
		var half := s * 1.25
		var bob := sin(tt * 3.0 + kind) * s * 0.05
		ci.draw_texture_rect_region(ICONS2, Rect2(c + Vector2(-half, -half + bob), Vector2(half, half) * 2.0),
			Rect2((kind - 1) * 64, 0, 64, 64), Color(1, 1, 1, col.a))
		return
	if kind == P.PU_FIRE:
		var f := 1.0 + 0.15 * sin(tt * 18.0)
		var sway := sin(tt * 9.0) * s * 0.15
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(sway, -s * f), c + Vector2(s * 0.6, s * 0.2), c + Vector2(s * 0.3, s * 0.8),
			c + Vector2(-s * 0.3, s * 0.8), c + Vector2(-s * 0.6, s * 0.2)]), col)
	elif kind == P.PU_BOMB:
		ci.draw_circle(c + Vector2(0, s * 0.15), s * 0.65, col)
		ci.draw_line(c + Vector2(s * 0.3, -s * 0.35), c + Vector2(s * 0.6, -s * 0.8), col, 3.0)
		if int(tt * 10.0) % 2 == 0:
			for i in 4:
				ci.draw_line(c + Vector2(s * 0.62, -s * 0.85), c + Vector2(s * 0.62, -s * 0.85) + Vector2.from_angle(i * PI / 2.0 + tt) * s * 0.3, Color(1.0, 0.9, 0.3, col.a), 2.0)
	elif kind == P.PU_POISON:
		ci.draw_circle(c + Vector2(0, -s * 0.1), s * 0.55, col)
		ci.draw_rect(Rect2(c + Vector2(-s * 0.3, s * 0.25), Vector2(s * 0.6, s * 0.4)), col)
		for i in 2:
			var k := fmod(tt * 0.9 + i * 0.5, 1.0)
			ci.draw_circle(c + Vector2((i * 2 - 1) * s * 0.45, -s * 0.4 - k * s * 0.6), s * 0.14 * (1.0 - k), col)
	elif kind == P.PU_SMOKE:
		for i in 3:
			var p: Vector2 = [Vector2(-0.4, 0.1), Vector2(0.35, 0.15), Vector2(0, -0.25)][i]
			ci.draw_circle(c + p * s + Vector2(sin(tt * 2.0 + i * 2.0) * s * 0.12, 0), s * (0.38 + 0.06 * sin(tt * 3.0 + i)), col)
	elif kind == P.PU_SHIELD or kind == P.PU_SPIKES:
		var shield := PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.7), c + Vector2(s * 0.7, -s * 0.7),
			c + Vector2(s * 0.6, s * 0.2), c + Vector2(0, s * 0.85), c + Vector2(-s * 0.6, s * 0.2)])
		ci.draw_colored_polygon(shield, col)
		var sh := fmod(tt * 0.8, 1.0)
		ci.draw_line(c + Vector2(-s * 0.7 + sh * s * 1.4, -s * 0.7), c + Vector2(-s * 0.9 + sh * s * 1.4, s * 0.3), Color(1, 1, 1, 0.6 * col.a), 3.0)
		if kind == P.PU_SPIKES:
			var bob := sin(tt * 6.0) * s * 0.1
			for i in 3:
				var x := (i - 1) * s * 0.5
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(x - s * 0.18, -s * 0.7), c + Vector2(x, -s * 1.15 + bob), c + Vector2(x + s * 0.18, -s * 0.7)]), col)
	elif kind == P.PU_INF:
		ci.draw_arc(c + Vector2(-s * 0.38, 0), s * 0.36, 0.0, TAU, 16, col, 4.0)
		ci.draw_arc(c + Vector2(s * 0.38, 0), s * 0.36, 0.0, TAU, 16, col, 4.0)
		var a := tt * 4.0
		var side := 1.0 if fmod(a, TAU * 2.0) < TAU else -1.0
		ci.draw_circle(c + Vector2(side * s * 0.38, 0) + Vector2.from_angle(a * side) * s * 0.36, s * 0.13, Color(1, 1, 1, col.a))
	elif kind == P.PU_FLY:
		var flap := sin(tt * 12.0) * s * 0.35
		for side in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2(side * s, -s * 0.5 + flap), c + Vector2(side * s * 0.8, s * 0.15 + flap * 0.4),
				c + Vector2(side * s * 0.4, s * 0.4)]), col)
	elif kind == P.PU_BIG:
		var g := 0.8 + 0.25 * (0.5 + 0.5 * sin(tt * 5.0))
		ci.draw_line(c + Vector2(-s * 0.8, s * 0.5) * g, c + Vector2(s * 0.6, -s * 0.4) * g, col, 5.0 * g)
		ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.9, -s * 0.6) * g, c + Vector2(s * 0.2, -s * 0.6) * g, c + Vector2(s * 0.7, 0.0) * g]), col)
	elif kind == P.PU_CATS:
		ci.draw_circle(c + Vector2(0, s * 0.1), s * 0.55, col)
		var tw := sin(tt * 7.0) * s * 0.08
		for side in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(side * s * 0.5, -s * 0.15), c + Vector2(side * (s * 0.55 + tw), -s * 0.85), c + Vector2(side * s * 0.1, -s * 0.4)]), col)
		if fmod(tt, 2.0) > 0.15:
			for side in [-1.0, 1.0]:
				ci.draw_circle(c + Vector2(side * s * 0.22, s * 0.02), s * 0.1, Color(0.5, 1.0, 0.4, col.a))
	elif kind == P.PU_RAIN:
		ci.draw_arc(c + Vector2(0, -s * 0.05), s * 0.8, PI, TAU, 16, col, 5.0)
		ci.draw_line(c + Vector2(0, -s * 0.05), c + Vector2(0, s * 0.6), col, 3.0)
		for i in 3:
			var k := fmod(tt * 1.5 + i * 0.33, 1.0)
			ci.draw_line(c + Vector2((i - 1) * s * 0.7, -s * 1.0 + k * s * 0.5), c + Vector2((i - 1) * s * 0.7, -s * 0.85 + k * s * 0.5), col, 2.0)
	elif kind == P.PU_INVIS:
		var open := 0.15 if fmod(tt, 1.6) < 0.25 else 1.0
		ci.draw_set_transform(c, 0.0, Vector2(1.0, open))
		ci.draw_arc(Vector2.ZERO, s * 0.75, 0.0, TAU, 20, col, 3.0)
		ci.draw_circle(Vector2.ZERO, s * 0.28, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif kind == P.PU_FREEZE:
		for i in 3:
			var a := i * PI / 3.0 + tt * 0.8
			ci.draw_line(c - Vector2.from_angle(a) * s * 0.85, c + Vector2.from_angle(a) * s * 0.85, col, 4.0)
	elif kind == P.PU_MASK:       # GHOSTFACE: the hood and the mask
		GhostfaceScript.icon(ci, c, s, col.a, tt)
	elif kind == P.PU_TRICK:      # a wrapped candy that wiggles
		var w := sin(tt * 6.0) * 0.15
		ci.draw_set_transform(c, w, Vector2.ONE)
		ci.draw_circle(Vector2.ZERO, s * 0.45, col)
		for side in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(side * s * 0.4, 0), Vector2(side * s * 0.95, -s * 0.35), Vector2(side * s * 0.95, s * 0.35)]), col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	elif kind == P.PU_PUMPKIN:    # a jack-o'-lantern whose face flickers
		ci.draw_circle(c + Vector2(0, s * 0.1), s * 0.7, col)
		ci.draw_line(c + Vector2(0, -s * 0.55), c + Vector2(s * 0.15, -s * 0.85), col, 3.0)
		if int(tt * 6.0) % 3 != 0:
			ci.draw_circle(c + Vector2(-s * 0.25, 0), s * 0.12, Color(1.0, 0.95, 0.5, col.a))
			ci.draw_circle(c + Vector2(s * 0.25, 0), s * 0.12, Color(1.0, 0.95, 0.5, col.a))
	elif kind == P.PU_BATS:       # a bat flapping
		var fl := sin(tt * 12.0) * s * 0.3
		for side in [-1.0, 1.0]:
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(side * s * 0.15, 0), c + Vector2(side * s, -s * 0.3 - fl), c + Vector2(side * s * 0.7, s * 0.2 - fl * 0.4),
				c + Vector2(side * s * 0.4, s * 0.05)]), col)
		ci.draw_circle(c, s * 0.25, col)
	elif kind == P.PU_SPEED:
		var j := Vector2(sin(tt * 30.0), 0) * s * 0.06
		ci.draw_colored_polygon(PackedVector2Array([c + j + Vector2(s * 0.2, -s * 0.9), c + j + Vector2(-s * 0.5, s * 0.1), c + j + Vector2(0, s * 0.1),
			c + j + Vector2(-s * 0.2, s * 0.9), c + j + Vector2(s * 0.5, -s * 0.1), c + j + Vector2(0, -s * 0.1)]), col)

# What a fighter has, drawn on it (a = 0.35 on your own page while you are invisible).
func _draw_kit(f: Dictionary, pw: Dictionary, a: float) -> void:
	var bits: int = pw["bits"]
	var c := Vector2(f["x"] + 18.0, f["y"] + 31.0)
	var top := Vector2(c.x, f["y"])
	var seat := int(f["id"])
	var tc: Color = team[seat % team.size()] if team.size() > 0 else Color.WHITE
	if (int(pw.get("mask", 0)) & P.PX_ICY) != 0 and (int(f["flags"]) & 2) != 0:   # p4.22 SLIP AND SLIDE: on the ice
		XV.skid(self, Vector2(c.x, f["y"] + 63.0), float(f.get("vx", 0.0)), a, t + seat)
	if (bits & P.PW_FLY) != 0:
		var flap := sin(t * 14.0 + seat) * 0.35
		for side in [-1.0, 1.0]:
			var base := c + Vector2(-side * 6.0, -10.0)
			var tip := base + Vector2(side * 38.0, -26.0 + flap * 30.0)
			draw_colored_polygon(PackedVector2Array([base, tip, base + Vector2(side * 30.0, 4.0 + flap * 14.0), base + Vector2(side * 12.0, 14.0)]),
				Color(1, 1, 1, 0.85 * a))
			draw_polyline(PackedVector2Array([base, tip, base + Vector2(side * 30.0, 4.0 + flap * 14.0)]), Color(0.6, 0.7, 0.9, a), 2.0)
	if (bits & P.PW_FROZEN) != 0 and Season.christmas() and (int(pw.get("mask", 0)) & P.PX_MASK) == 0 and (bits & P.PW_PUMPKIN) == 0:
		XV.snowed(self, f, tc, a, t)   # p4.22: packed into a snowman (world.gd hides the body; not a costume or a trick's form: they keep the ice)
	elif (bits & P.PW_FROZEN) != 0:
		var r := Rect2(f["x"] - 9.0, f["y"] - 9.0, 54.0, 81.0)
		draw_rect(r, Color(0.7, 0.9, 1.0, 0.42 * a))
		draw_rect(r, Color(0.92, 0.98, 1.0, 0.9 * a), false, 3.0)
		draw_line(r.position + Vector2(8, 10), r.position + Vector2(22, 4), Color(1, 1, 1, 0.8 * a), 3.0)
		draw_line(r.position + Vector2(8, 20), r.position + Vector2(14, 16), Color(1, 1, 1, 0.6 * a), 2.0)
	if (bits & P.PW_SHIELD) != 0:
		draw_circle(c, 46.0, Color(0.4, 0.88, 1.0, 0.1 * a))
		draw_arc(c, 46.0, 0.0, TAU, 36, Color(0.5, 0.92, 1.0, (0.7 + 0.2 * sin(t * 5.0)) * a), 3.0)
	if (bits & P.PW_SPIKES) != 0:
		if (bits & P.PW_SPIKE_UP) != 0:
			draw_circle(c, 50.0, Color(GOLD, 0.1 * a))
			draw_arc(c, 50.0, 0.0, TAU, 36, Color(GOLD, 0.85 * a), 3.0)
		for i in 3:
			var x := top.x + (i - 1) * 13.0
			var y: float = top.y - 2.0
			draw_colored_polygon(PackedVector2Array([Vector2(x - 6, y), Vector2(x, y - 17), Vector2(x + 6, y)]), Color(0.85, 0.85, 0.9, a))
			draw_polyline(PackedVector2Array([Vector2(x - 6, y), Vector2(x, y - 17), Vector2(x + 6, y)]), Color(0.2, 0.2, 0.25, a), 1.5)
	if (bits & P.PW_UMBRELLA) != 0:
		var uc := top + Vector2(0, -22)
		var pts := PackedVector2Array()
		for i in 13:
			pts.append(uc + Vector2.from_angle(PI + PI * i / 12.0) * 34.0)
		for i in 4:
			pts.append(uc + Vector2(34.0 - (i + 1) * 17.0, 4.0 if i % 2 == 0 else 0.0))
		draw_colored_polygon(pts, Color(tc.lightened(0.15), 0.95 * a))
		draw_line(uc, uc + Vector2(0, 30), Color(0.25, 0.2, 0.15, a), 3.0)
		draw_arc(uc + Vector2(5, 30), 5.0, 0.0, PI, 8, Color(0.25, 0.2, 0.15, a), 3.0)
	if (bits & P.PW_SPEED) != 0:
		var back := -1.0 if (int(f["flags"]) & 1) != 0 else 1.0
		for i in 3:
			var y: float = f["y"] + 14.0 + i * 16.0
			var x0: float = c.x + back * 22.0
			draw_line(Vector2(x0, y), Vector2(x0 + back * (24.0 + 14.0 * ((i + int(t * 20.0)) % 3)), y), Color(1.0, 0.95, 0.4, 0.75 * a), 3.0)
	if (bits & P.PW_SLOW) != 0:
		for i in 2:
			var k := fmod(t * 1.3 + i * 0.5, 1.0)
			var p := top + Vector2(-12.0 + i * 24.0, 6.0 + 30.0 * k)
			draw_circle(p, 4.0, Color(0.55, 0.75, 1.0, (1.0 - k) * a))
	if (bits & P.PW_PUMPKIN) != 0 and Season.harvest():   # p4.18 TURKEY TIME: a hopping turkey instead of the body
		HV.trick_turkey(self, f, tc, a, t)
	elif (bits & P.PW_PUMPKIN) != 0 and Season.christmas():   # p4.22 SNOWMAN: a hopping snowman instead of the body
		XV.trick_snowman(self, f, tc, a, t)
	elif (bits & P.PW_PUMPKIN) != 0:      # p4.12 the pumpkin trick: a hopping jack-o'-lantern instead of the body
		var pc := c + Vector2(0, 6)
		draw_circle(pc, 30.0, Color(0.6, 0.28, 0.05, a))
		draw_circle(pc, 26.0, Color(1.0, 0.55, 0.1, a))
		draw_line(pc + Vector2(0, -26), pc + Vector2(5, -38), Color(0.25, 0.5, 0.15, a), 5.0)
		var lit := Color(1.0, 0.92, 0.4, a)
		draw_colored_polygon(PackedVector2Array([pc + Vector2(-16, -6), pc + Vector2(-6, -6), pc + Vector2(-11, -15)]), lit)
		draw_colored_polygon(PackedVector2Array([pc + Vector2(6, -6), pc + Vector2(16, -6), pc + Vector2(11, -15)]), lit)
		draw_colored_polygon(PackedVector2Array([pc + Vector2(-18, 4), pc + Vector2(-9, 10), pc + Vector2(0, 5), pc + Vector2(9, 10), pc + Vector2(18, 4),
			pc + Vector2(10, 16), pc + Vector2(-10, 16)]), lit)
	if (bits & P.PW_BACKWARDS) != 0:    # a swirl over the head
		draw_arc(top + Vector2(0, -22), 10.0, t * 8.0, t * 8.0 + 4.5, 12, Color(0.85, 0.5, 1.0, a), 3.0)
		_text_c(top + Vector2(0, -36), "?!", 22, Color(0.9, 0.7, 1.0, a))
	# badges over the head for what has no look of its own: the arrow kind, INFINITE, BIG
	var badges: Array = []
	var pkind := int(pw["kind"])
	if pkind > 0:
		badges.append(arrow_power(pkind) if arrow_power(pkind) > 0 else P.PU_FIRE)
	if (bits & P.PW_INF) != 0:
		badges.append(P.PU_INF)
	if (bits & P.PW_BIG) != 0:
		badges.append(P.PU_BIG)
	var by: float = top.y - (30.0 if (bits & (P.PW_SPIKES | P.PW_UMBRELLA)) != 0 else 16.0) - (34.0 if (bits & P.PW_UMBRELLA) != 0 else 0.0)
	if (bits & P.PW_PUMPKIN) == 0:
		by -= Hats.lift(seat)      # p4.22: over the winter hat (a trick's form wears none)
	for i in badges.size():
		var bc := Vector2(c.x + (i - (badges.size() - 1) / 2.0) * 26.0, by)
		var col: Color = COLORS.get(badges[i], Color.WHITE)
		draw_circle(bc, 12.0, Color(0.05, 0.05, 0.1, 0.8 * a))
		draw_circle(bc, 10.0, Color(disc(col), a))
		draw_icon(self, bc, badges[i], 6.5, Color(0.08, 0.06, 0.12, a), t)

# p4.12 the black cat: walking its floor (legs, a curled tail, green eyes), PET ME over it;
# running off when petted (it fades).
func _draw_pet(pd: Dictionary) -> void:
	if int(pd.get("kind", 0)) == 1:     # p4.18: the turkey (it is off the floor when its feet are not on a cell's line)
		var off := fposmod(float(pd["y"]), 30.0)
		HV.pet(self, pd, t, off > 1.0 and off < 29.0, font)
		return
	if int(pd.get("kind", 0)) == 2:     # p4.22: the reindeer
		XV.pet(self, pd, t, font)
		return
	var feet := Vector2(pd["x"], pd["y"])
	var dir := float(pd["dir"])
	var gone := int(pd.get("gone", 0))
	var a := clampf(gone / 40.0, 0.0, 1.0) if gone > 0 else 1.0
	var body := Color(0.06, 0.05, 0.08, a)
	var rim := Color(0.78, 0.66, 1.0, 0.95 * a)
	var c := feet + Vector2(0, -15)
	draw_circle(c + Vector2(0, 4), 30.0, Color(0.6, 0.45, 0.9, 0.1 * a))   # a soft light round it: a black cat on a dark night
	draw_circle(c + Vector2(0, 4), 20.0, Color(0.7, 0.55, 1.0, 0.1 * a))
	var step := sin(t * 12.0) * 3.0
	for k in 4:   # legs
		var lx := (k - 1.5) * 7.0
		draw_line(c + Vector2(lx, 4), c + Vector2(lx + (step if k % 2 == 0 else -step), 15), rim, 4.5)
		draw_line(c + Vector2(lx, 4), c + Vector2(lx + (step if k % 2 == 0 else -step), 15), body, 3.0)
	var pts := PackedVector2Array()
	for i in 14:
		var ang := TAU * i / 14.0
		pts.append(c + Vector2(cos(ang) * 18.0, sin(ang) * 9.0))
	draw_colored_polygon(pts, body)
	pts.append(pts[0])
	draw_polyline(pts, rim, 2.0, true)
	var head := c + Vector2(dir * 17.0, -8.0)
	for side in [-1.0, 1.0]:   # the ears (behind the head's rim)
		var ear := PackedVector2Array([head + Vector2(side * 8.0 - 1.0, -3.0), head + Vector2(side * 6.5, -15.0), head + Vector2(side * 1.0, -7.0)])
		draw_colored_polygon(ear, body)
		ear.append(ear[0])
		draw_polyline(ear, rim, 1.6, true)
	draw_circle(head, 9.0, body)
	draw_arc(head, 9.0, 0.0, TAU, 16, rim, 2.0, true)
	for side in [-1.0, 1.0]:
		draw_circle(head + Vector2(dir * 2.5 + side * 3.4, -1.0), 2.2, Color(0.55, 1.0, 0.35, a))
	var tail := PackedVector2Array()
	for i in 7:
		tail.append(c + Vector2(-dir * (16.0 + i * 2.6), -2.0 - i * 4.4 + sin(t * 4.0 + i * 0.6) * 2.5))
	draw_polyline(tail, rim, 6.0, true)
	draw_polyline(tail, body, 4.0, true)
	if gone == 0:
		var bob := sin(t * 3.0) * 3.0
		_heart(c + Vector2(0, -34 + bob), 7.0, Color(1.0, 0.45, 0.7, 0.9))
		_text_c(c + Vector2(0, -46 + bob), "PET ME", 14, Color(1.0, 0.85, 0.95, 0.9))

func _heart(c: Vector2, s: float, col: Color) -> void:
	draw_circle(c + Vector2(-s * 0.5, 0), s * 0.55, col)
	draw_circle(c + Vector2(s * 0.5, 0), s * 0.55, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 1.05, s * 0.15), c + Vector2(s * 1.05, s * 0.15), c + Vector2(0, s * 1.2)]), col)

func _bat(p: Vector2, s: float, ph: float, col: Color) -> void:
	var flap := sin(ph) * 8.0 * s
	var rim := Color(0.62, 0.48, 0.85, col.a * 0.9)   # a lit edge, so a black bat shows on the night sky
	for side in [-1.0, 1.0]:
		var wing := PackedVector2Array([p + Vector2(side * 3.0, 0) * s, p + Vector2(side * 18.0 * s, -5.0 * s - flap),
			p + Vector2(side * 15.0 * s, 0.5 * s - flap * 0.7), p + Vector2(side * 13.0 * s, 3.0 * s - flap * 0.4),
			p + Vector2(side * 10.0 * s, 1.5 * s - flap * 0.2), p + Vector2(side * 7.0 * s, 1.0 * s)])
		draw_colored_polygon(wing, col)
		wing.append(wing[0])
		draw_polyline(wing, rim, 1.2, true)
	draw_circle(p, 4.0 * s, col)
	draw_arc(p, 4.0 * s, PI * 1.1, PI * 1.9, 6, rim, 1.2, true)
	for side in [-1.0, 1.0]:   # little ears
		draw_colored_polygon(PackedVector2Array([p + Vector2(side * 1.0, -3.0) * s, p + Vector2(side * 2.6, -6.5) * s, p + Vector2(side * 3.4, -2.0) * s]), col)
	draw_circle(p + Vector2(-1.6, -0.8) * s, 1.0 * s, Color(1.0, 0.25, 0.2, col.a))
	draw_circle(p + Vector2(1.6, -0.8) * s, 1.0 * s, Color(1.0, 0.25, 0.2, col.a))

# A bat swarm: screeching (zigzags and a dim band at the edge it comes in from), then a
# cloud of bats sweeping across in its band.
func _draw_swarm(bd: Dictionary) -> void:
	var y: float = bd["y"]
	var dir := float(bd["dir"])
	var h: float = SimScript.BATS_H
	if world != null and world.level != null and world.level.theme == "barn":   # p4.18: a gust of leaves
		HV.gust(self, int(bd["phase"]), float(bd.get("x", 0.0)), y, dir, SimScript.BATS_W, h, t)
		return
	if world != null and world.level != null and world.level.theme == "rooftops":   # p4.22: a gust of snow
		RooftopsView.gust(self, int(bd["phase"]), float(bd.get("x", 0.0)), y, dir, SimScript.BATS_W, h, t)
		return
	if int(bd["phase"]) == 0:
		var ex := 40.0 if dir > 0 else 1880.0
		draw_rect(Rect2(0, y - h * 0.5, 1920, h), Color(0.35, 0.2, 0.5, 0.08 + 0.06 * sin(t * 20.0)))
		for k in 3:
			var zx := ex + dir * k * 26.0
			draw_polyline(PackedVector2Array([Vector2(zx, y - 30), Vector2(zx + dir * 10, y - 10), Vector2(zx, y + 10), Vector2(zx + dir * 10, y + 30)]),
				Color(0.85, 0.7, 1.0, 0.8), 3.0)
		return
	var cx: float = bd["x"]
	var w: float = SimScript.BATS_W
	for k in 7:   # a dark cloud of wings: soft blobs, darker in the middle
		var bx := cx + (k - 3) * w * 0.14 + sin(t * 2.0 + k) * 10.0
		draw_circle(Vector2(bx, y + sin(t * 3.0 + k * 1.7) * 12.0), h * (0.42 if k % 3 == 0 else 0.34), Color(0.06, 0.02, 0.1, 0.16))
	for i in 64:
		var hx := fposmod(i * 97.0 + t * 30.0 * (1.0 + (i % 3) * 0.3), w) - w * 0.5
		var hy := fposmod(i * 53.0, h) - h * 0.5 + sin(t * 5.0 + i) * 10.0
		_bat(Vector2(cx + hx, y + hy), 1.15 + (i % 4) * 0.18, t * 16.0 + i, Color(0.04, 0.02, 0.07, 0.97))

# BAT SWARM: bats circling the fighter (seen by everyone: they show where it hides).
func _draw_circling_bats(f: Dictionary, seat: int) -> void:
	var c := Vector2(f["x"] + 18.0, f["y"] + 31.0)
	for i in 10:
		var ang := t * 3.0 + i * TAU / 10.0 + seat
		var p := c + Vector2(cos(ang) * (50.0 + 8.0 * sin(t * 4.0 + i)), sin(ang) * 40.0)
		if Season.harvest():      # p4.18: CROWS
			HV.crow(self, p, 1.0, t * 18.0 + i, 0.97)
		elif Season.christmas():  # p4.22: SNOW FLURRY
			XV.flake(self, p, 1.0 + 0.25 * (i % 3), t * 18.0 + i, 0.97)
		else:
			_bat(p, 1.05, t * 18.0 + i, Color(0.04, 0.02, 0.07, 0.95))

# A ghost cat (the user's daughter's idea): a pale glowing cat with big green eyes
# and a wavy ghost's tail instead of legs, outlined so it shows on the dark arena,
# facing the one it hunts.
func _draw_cat(cd: Dictionary) -> void:
	var c := Vector2(cd["x"], cd["y"] + sin(t * 6.0 + cd["x"] * 0.02) * 4.0)
	var tgt: Dictionary = fighters.get(int(cd["target"]), {})
	var dir := 1.0
	if not tgt.is_empty():
		dir = 1.0 if SimScript.wrap_d(c.x, tgt["x"] + 18.0, 1920.0) >= 0.0 else -1.0
	var body := Color(0.86, 0.98, 0.92, 0.92)
	var line := Color(0.1, 0.25, 0.15, 0.95)
	var pts := PackedVector2Array()
	for i in 13:                      # the back, an arc over the top
		var a := PI + PI * i / 12.0
		pts.append(c + Vector2(cos(a) * 30.0, sin(a) * 18.0))
	for i in 7:                       # the ghost's wavy hem underneath
		var x := 30.0 - i * 10.0
		pts.append(c + Vector2(x, 10.0 + (6.0 if i % 2 == 0 else 0.0) + sin(t * 9.0 + i) * 2.0))
	draw_colored_polygon(pts, body)
	pts.append(pts[0])
	draw_polyline(pts, line, 2.5)
	var head := c + Vector2(dir * 24.0, -16.0)
	for side in [-1.0, 1.0]:
		var ear := PackedVector2Array([head + Vector2(side * 14.0 - 3.0, -6.0), head + Vector2(side * 13.0, -27.0 + sin(t * 7.0 + side) * 2.0), head + Vector2(side * 3.0, -14.0)])
		draw_colored_polygon(ear, body)
		ear.append(ear[0])
		draw_polyline(ear, line, 2.0)
	draw_circle(head, 17.0, line)
	draw_circle(head, 15.0, body)
	for side in [-1.0, 1.0]:
		var eye := head + Vector2(dir * 4.0 + side * 6.5, -2.0)
		draw_circle(eye, 4.6, Color(0.35, 1.0, 0.3))
		draw_circle(eye + Vector2(dir * 1.2, 0), 2.0, Color(0.05, 0.05, 0.05))
	draw_circle(head + Vector2(dir * 7.0, 5.0), 2.0, Color(1.0, 0.55, 0.65))
	for side in [-1.0, 1.0]:          # whiskers
		draw_line(head + Vector2(dir * 9.0, 6.0), head + Vector2(dir * 24.0, 3.0 + side * 4.0), line, 1.5)
	var tail := PackedVector2Array()
	for i in 8:
		tail.append(c + Vector2(-dir * (26.0 + i * 5.0), -6.0 - i * 4.0 + sin(t * 8.0 + i * 0.8) * 4.0))
	draw_polyline(tail, line, 8.0)
	draw_polyline(tail, body, 5.0)

# p4.11: a person's ghost: a floating sheet in its colour, eyes, a wavy hem; yours has a
# white outline; dashing (a BOO), a streak behind and an open mouth; popped: out of sight.
func _draw_ghost(g: Dictionary) -> void:
	var flags := int(g["flags"])
	if flags & 1:
		return
	var seat := int(g["seat"])
	var c := Vector2(g["x"], g["y"] + sin(t * 3.0 + seat) * 4.0)
	var tc: Color = team[seat % team.size()] if team.size() > 0 else Color.WHITE
	var body := Color(tc.lerp(Color.WHITE, 0.6), 0.7)
	if flags & 2:   # a BOO dash: whoosh rings around it
		for k in 3:
			draw_arc(c, 28.0 + k * 7.0, 0.0, TAU, 24, Color(body, 0.35 - k * 0.1), 3.0)
	var pts := PackedVector2Array()
	for i in 13:
		pts.append(c + Vector2.from_angle(PI + PI * i / 12.0) * 22.0)
	for k in 7:
		var x := 22.0 - k * (44.0 / 6.0)
		pts.append(c + Vector2(x, 26.0 + (6.0 if k % 2 == 0 else 0.0) + sin(t * 8.0 + k) * 2.0))
	draw_colored_polygon(pts, body)
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, 0.9 if seat == me else 0.35), 2.5 if seat == me else 1.5)
	for side in [-1.0, 1.0]:
		draw_circle(c + Vector2(side * 8.0, -4.0), 4.5, Color(0.08, 0.06, 0.15, 0.9))
	if flags & 2:
		draw_circle(c + Vector2(0, 9), 5.0, Color(0.08, 0.06, 0.15, 0.9))
	if seat == me and (flags & 4):
		draw_arc(c, 30.0, 0.0, TAU, 24, Color(1, 1, 1, 0.25 + 0.15 * sin(t * 4.0)), 2.0)

func _text_c(at: Vector2, s: String, size: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := Vector2(clampf(at.x - w / 2.0, 12.0, maxf(12.0, 1908.0 - w)), clampf(at.y, 30.0, 1070.0))   # on screen
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(4, size / 7), Color(0, 0, 0, 0.85 * col.a))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

# ------------------------------------------------------------------ the glow layer (added light)
func _paint_glow(g: Node2D) -> void:
	if flash > 0.0:
		g.draw_rect(Rect2(0, 0, 1920, 1080), Color(flash_col, flash * 0.45))
	for o in view.get("orbs", []):
		var c := Vector2(o["x"], o["y"])
		var col: Color = COLORS.get(int(o["kind"]), Color.WHITE)
		if int(o["state"]) == P.ORB_WARN:
			var prog: float = o["prog"]
			if Season.christmas():       # p4.22: no lightning: a warm light on the spot where the present will land
				g.draw_circle(c, 30.0 + 22.0 * prog, Color(1.0, 0.85, 0.5, 0.14 + 0.22 * prog))
				continue
			# a column of light from the sky, brighter as the bolt comes
			for i in 3:
				var w := 46.0 - i * 14.0
				g.draw_rect(Rect2(c.x - w / 2.0, 0.0, w, c.y + 20.0), Color(0.45, 0.6, 1.0, (0.05 + 0.13 * prog) * (i + 1) * 0.6))
			g.draw_circle(c, 26.0 + 18.0 * prog, Color(0.55, 0.7, 1.0, 0.18 + 0.3 * prog))
			for pts in arcs.get("w%d:%d" % [int(o["x"]), int(o["y"])], []):
				g.draw_polyline(pts, Color(0.7, 0.85, 1.0, 0.65 + 0.35 * prog), 3.0)
		else:
			var r := 30.0 if o["big"] else 22.0
			if Polish.on("icons2"):   # the glow as a ring round the orb, not over its picture
				g.draw_arc(c, r * 1.65, 0.0, TAU, 40, Color(col, 0.16), r * 1.3)
				g.draw_arc(c, r * 1.25, 0.0, TAU, 32, Color(col, 0.22), r * 0.5)
			else:
				g.draw_circle(c, r * 2.3, Color(col, 0.16))
				g.draw_circle(c, r * 1.5, Color(col, 0.22))
			if o["big"]:
				g.draw_circle(c, r * 3.0, Color(GOLD, 0.12))
	for b in bolts:
		var k: float = clampf(b[1] / 0.4, 0.0, 1.0)
		g.draw_polyline(b[3], Color(BOLT_COL, k), 16.0 if b[2] else 12.0)
		g.draw_polyline(b[3], Color(1, 1, 1, k), 5.0)
		g.draw_circle(b[0], 50.0 * k + 20.0, Color(0.7, 0.85, 1.0, 0.6 * k))
	for seat in zaps:
		var f: Dictionary = fighters.get(seat, {})
		if f.is_empty():
			continue
		var c := Vector2(f["x"] + 18.0, f["y"] + 31.0)
		var k: float = zaps[seat] / ZAP_S
		g.draw_circle(c, 40.0, Color(0.5, 0.7, 1.0, 0.25 * k))
		for pts in arcs.get("z%d" % seat, []):
			g.draw_polyline(pts, Color(0.75, 0.9, 1.0, k), 3.0)
	for cd in view.get("cats", []):
		g.draw_circle(Vector2(cd["x"], cd["y"] - 6.0), 46.0, Color(0.45, 1.0, 0.55, 0.16))
		g.draw_circle(Vector2(cd["x"], cd["y"] - 6.0), 28.0, Color(0.55, 1.0, 0.65, 0.2))

# p4.19 PHEW: the thing that bounced off the winner tumbles away in an arc (a drumstick in the
# Harvest season, else a rubber chicken); over the winner a speech bubble, PHEW!, and three
# drops of sweat.
func _draw_phew(ph: Dictionary) -> void:
	var age: float = t - float(ph["t0"])
	var k := age / PHEW_S
	var dir: float = ph["dir"]
	var at: Vector2 = ph["at"]
	var fade := clampf((1.0 - k) * 4.0, 0.0, 1.0)
	# the prop: up and away, then down, spinning
	var pp := at + Vector2(dir * 260.0 * age, -420.0 * age + 620.0 * age * age)
	draw_set_transform(pp, age * 9.0 * dir, Vector2.ONE * 1.5)
	if Season.christmas():       # p4.22: a snowball bounces off
		XV.snowball(self, Vector2.ZERO, 12.0, fade)
	elif Season.harvest():
		draw_line(Vector2(6, 0), Vector2(26, 0), Color(0.16, 0.08, 0.03, fade), 9.0)          # the bone, with its edge
		draw_line(Vector2(6, 0), Vector2(26, 0), Color(1.0, 0.97, 0.9, fade), 5.0)
		for side in [-1.0, 1.0]:
			draw_circle(Vector2(27, side * 4.0), 5.5, Color(0.16, 0.08, 0.03, fade))
			draw_circle(Vector2(27, side * 4.0), 3.8, Color(1.0, 0.97, 0.9, fade))
		draw_circle(Vector2(-4, 0), 15.0, Color(0.16, 0.08, 0.03, fade))                       # the meat
		draw_circle(Vector2(-4, 0), 12.5, Color(0.72, 0.4, 0.15, fade))
		draw_circle(Vector2(-8, -4), 5.0, Color(0.9, 0.6, 0.3, fade))
	else:
		draw_circle(Vector2(0, 0), 14.0, Color(0.2, 0.12, 0.0, fade))                           # a rubber chicken: body
		draw_circle(Vector2(0, 0), 11.5, Color(1.0, 0.86, 0.25, fade))
		draw_line(Vector2(8, -6), Vector2(22, -16), Color(0.2, 0.12, 0.0, fade), 12.0)          # neck
		draw_line(Vector2(8, -6), Vector2(22, -16), Color(1.0, 0.86, 0.25, fade), 8.0)
		draw_circle(Vector2(24, -18), 8.0, Color(0.2, 0.12, 0.0, fade))
		draw_circle(Vector2(24, -18), 6.0, Color(1.0, 0.86, 0.25, fade))
		draw_circle(Vector2(24, -26), 3.5, Color(0.9, 0.2, 0.15, fade))                         # comb
		draw_colored_polygon(PackedVector2Array([Vector2(29, -20), Vector2(38, -17), Vector2(29, -14)]), Color(1.0, 0.5, 0.1, fade))
		draw_circle(Vector2(25, -19), 1.6, Color(0, 0, 0, fade))
		for side in [-1.0, 1.0]:
			draw_line(Vector2(-6, 8), Vector2(-14 + side * 3.0, 22), Color(1.0, 0.5, 0.1, fade), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the winner: PHEW! in a bubble that pops in, and sweat
	var f: Dictionary = fighters.get(int(ph["seat"]), {})
	if f.is_empty():
		return
	var head := Vector2(float(f["x"]) + 18.0, float(f["y"]) - 6.0)
	_bubble(head, "PHEW!", age, fade, Color.WHITE)
	for i in 3:
		var dk := clampf(age / 0.7, 0.0, 1.0)
		var dv := Vector2((i - 1) * 46.0 - dir * 16.0, -30.0 - i % 2 * 14.0) * dk + Vector2(0, 60.0 * dk * dk)
		var dp := head + Vector2(0, -8) + dv
		var da := (1.0 - dk) * fade
		draw_circle(dp, 5.0, Color(0.55, 0.85, 1.0, da))
		draw_colored_polygon(PackedVector2Array([dp + Vector2(-4, -2), dp + Vector2(0, -12), dp + Vector2(4, -2)]), Color(0.55, 0.85, 1.0, da))

# A speech bubble over a head (PHEW!, a taunt): it pops in, leans a little, and fades in steps
# (lobby_art.gd keeps every box it makes).
func _bubble(head: Vector2, word: String, age: float, fade: float, paper: Color) -> void:
	var pop := 1.0 + 0.4 * clampf(1.0 - age / 0.18, 0.0, 1.0)
	var fs := 30
	var w := LobbyArt.DISPLAY.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 30.0
	var bc := Vector2(clampf(head.x, w * 0.5 + 10.0, 1910.0 - w * 0.5), maxf(60.0, head.y - 62.0))
	draw_set_transform(bc, -0.06, Vector2.ONE * pop)
	var a8 := roundf(fade * 8.0) / 8.0
	draw_colored_polygon(PackedVector2Array([Vector2(-10, 20), Vector2(10, 20), Vector2(0, 40)]), Color(0.06, 0.04, 0.1, a8))
	draw_style_box(LobbyArt.box(Color(paper, a8), Color(0.06, 0.04, 0.1, a8), 14, 4), Rect2(-w * 0.5, -24, w, 48))
	draw_colored_polygon(PackedVector2Array([Vector2(-6, 20), Vector2(6, 20), Vector2(0, 33)]), Color(paper, a8))
	draw_string(LobbyArt.DISPLAY, Vector2(-w * 0.5 + 15.0, 11.0), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.08, 0.05, 0.12, a8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

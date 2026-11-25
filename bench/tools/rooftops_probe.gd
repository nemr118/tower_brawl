# THE ROOFTOPS (p4.22, sim/level.gd's arena with the theme "rooftops"), headless: what is
# its own, each on a little stage.
# Part 1, the gust of snow: the bat swarm's rule with the barn's numbers (sim.gd
#   GUST_FIRST, GUST_EVERY): it warns, sweeps in, an arrow flying into it drops, whoever
#   is inside is hidden, it leaves and the next one comes.
# Part 2, the alleys (the gaps in the floor): a fighter that falls into one, at any place
#   across it, with the stick let go, held left or held right, drops out of the sky and
#   stands on something within 4 s. No fall goes on for ever.
# Part 3, the low places: tools/pit_probe.gd's "kid" (it jumps a moment after it lands or
#   touches a wall, steers this way or that, some kids dash) starts on every part of the
#   floor, the lowest place there is. How many are up one level (or out through an alley
#   and standing higher) within 4 s, and how fast. It must be 95% with jumps only and 85%
#   with dashes too (THE HAUNTED HOUSE's pit gave 97% and 93% after p4.15's fix).
#   --floor-of=N runs only this part on another arena's floor, to compare (2026-11-25, the
#   worst part of each, jumps only / with dashes: the barn 64% / 87%, THE KEEP 83% / 74%,
#   THE HAUNTED HOUSE 55% / 86%, THE BIG TABLE 90% / 91%).
# Part 4, the page's reading of the map (client/rooftops_view.gd, no drawing): every
#   block has a kind, every roof has a house front under it, the chimneys smoke, the
#   belfry and the spire are found, every string of lights still hangs between two
#   blocks, every torch has a lantern, and two roofs side by side differ in colour.
# Exit 1 on a failed check.
#   godot --headless --path bench --script res://tools/rooftops_probe.gd [-- --tries=400 --seed=1]
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const PitProbe = preload("res://tools/pit_probe.gd")       # its Kid
const RooftopsView = preload("res://client/rooftops_view.gd")

const MAX_T := 240
const FLOOR_Y := 1020

var arena := -1
var tries := 400
var seed_value := 1
var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("🧪 [RooftopsProbe] FAIL: " + what)

func _say(s: String) -> void:
	print("🧪 [RooftopsProbe] " + s)

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tries="):
			tries = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
	var other := -1
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--floor-of="):    # only part 3, on another arena's floor (to compare)
			other = int(a.get_slice("=", 1))
	if other >= 0:
		arena = other
		_say("layout %d %s (its floor only, to compare)" % [arena, LevelScript.name_of(arena)])
		_low_places()
		quit(0)
		return
	for n in LevelScript.count():
		if str(LevelScript.LAYOUTS[n].get("theme", "")) == "rooftops":
			arena = n
	if arena < 0:
		print("🧪 [RooftopsProbe] FAIL: no arena has the theme \"rooftops\"")
		quit(1)
		return
	_say("layout %d %s" % [arena, LevelScript.name_of(arena)])
	_gust()
	_alleys()
	_low_places()
	_view()
	if fails == 0:
		print("✅ rooftops_probe: PASS")
	else:
		printerr("❌ rooftops_probe: %d check(s) failed" % fails)
	quit(0 if fails == 0 else 1)

# A stage: the arena, these seats (people), the round running, nothing else going on.
func _stage(seats: int, seed: int):
	var s = SimScript.new(0, 24, seed)
	s.set_arena(arena)
	s.respawn = false
	s.power_arrows = false
	var list: Array = []
	for i in seats:
		list.append({"id": i, "bot": false})
	s.start_round(list)
	s.frozen = false
	s.powerups = false
	s.pet_at = -1
	s.candy_t = -1
	return s

static func _count(events: Array, type: int) -> int:
	var n := 0
	for e in events:
		if e[0] == type:
			n += 1
	return n

# ------------------------------------------------------------------ part 1
func _gust() -> void:
	var s = _stage(2, 71)
	_check(s.bats_at == SimScript.GUST_FIRST, "the first gust of snow comes %d s after FIGHT (bats_at %d)" % [SimScript.GUST_FIRST / 60, s.bats_at])
	s.bats_at = s.play_t
	s.step()
	_check(_count(s.take_events(), P.E_BATS) == 1 and not s.bats.is_empty(), "the gust warns first")
	for k in SimScript.BATS_WARN + 1:
		s.step()
	_check(int(s.bats.get("phase", -1)) == 1, "then it sweeps in")
	for k in 200:
		if s.bats["x"] > 400.0 and s.bats["x"] < 1520.0:
			break
		s.step()
	var dir: float = s.bats["dir"]
	var lead: float = s.bats["x"] + dir * SimScript.BATS_W * 0.5
	var ar = SimScript.Arrow.new()
	ar.id = 9000
	ar.owner = 1
	ar.x = lead + dir * 14.0
	ar.y = s.bats["y"]
	ar.vx = dir * 2.0
	ar.t = 20
	ar.state = P.S_FLY
	s.arrows.append(ar)
	var f = s.fighters[0]
	f.x = int(s.bats["x"]) - 18
	f.y = int(s.bats["y"]) - 31
	s.step()
	s.step()
	_check(ar.state != P.S_FLY, "an arrow flying into the gust drops")
	_check(f.batted > 0 and SimScript.hidden(f), "whoever is inside is hidden")
	var gone := false
	for k in 400:
		s.step()
		if s.bats.is_empty():
			gone = true
			break
	var wait: int = s.bats_at - s.play_t
	_check(gone and wait >= SimScript.GUST_EVERY[0] - 5 and wait <= SimScript.GUST_EVERY[1], "it leaves, and the next one comes %d to %d s later (%d ticks)" % [
		SimScript.GUST_EVERY[0] / 60, SimScript.GUST_EVERY[1] / 60, wait])
	_say("the gust of snow: first %d s after FIGHT, then every %d to %d s; the swarm's rule (an arrow drops, a fighter is hidden)" % [
		SimScript.GUST_FIRST / 60, SimScript.GUST_EVERY[0] / 60, SimScript.GUST_EVERY[1] / 60])

# ------------------------------------------------------------------ part 2
# The gaps in the floor: [first px, last px + 1] of each.
func _gaps(lv) -> Array:
	var out: Array = []
	var run := -1
	for cx in lv.COLS + 1:
		var gap: bool = cx < lv.COLS and lv.cell(cx, lv.ROWS - 1) == 0
		if gap and run < 0:
			run = cx
		elif not gap and run >= 0:
			out.append([run * 30, cx * 30])
			run = -1
	return out

func _alleys() -> void:
	var lv = LevelScript.new(arena)
	var gaps := _gaps(lv)
	_check(gaps.size() >= 1, "the floor has gaps (%d)" % gaps.size())
	var falls := 0
	var landed := 0
	var slowest := 0
	var rows := {}
	for g in gaps:
		for way in [0, P.B_LEFT, P.B_RIGHT]:
			var x: int = g[0] + 18
			while x <= g[1] - 18:          # the body's middle, every 6 px across the gap
				var s = _stage(1, 80)
				s.bats_at = -1
				var f = s.fighters[0]
				s._place(f, Vector2i(x, FLOOR_Y + 2))   # just under the floor's top: in the gap, falling
				falls += 1
				for t in MAX_T:
					s.apply_input(f, way, 0)
					s.step()
					if f.on_ground and f.state != P.F_DEAD:
						landed += 1
						slowest = maxi(slowest, t + 1)
						rows[int(f.y + 63) / 30] = rows.get(int(f.y + 63) / 30, 0) + 1
						break
				x += 6
	var where: Array = rows.keys()
	where.sort()
	var parts: Array = []
	for r in where:
		parts.append("row %d: %d" % [r, rows[r]])
	_say("the alleys: %d gaps, %d falls (stick let go, held left, held right, every 6 px across): %d land within 4 s, the slowest in %.2f s; where: %s" % [
		gaps.size(), falls, landed, slowest / 60.0, ", ".join(parts)])
	_check(landed == falls, "every fall into an alley lands (%d of %d)" % [landed, falls])

# ------------------------------------------------------------------ part 3
# The parts of the floor: runs of places to stand on the bottom floor, cut where a block
# stands on it. [[feet x, ...], ...]
func _floor_parts(lv) -> Array:
	var out: Array = []
	var cur: Array = []
	for cx in range(0, lv.COLS):
		if lv.stands(Vector2i(cx * 30, FLOOR_Y)):
			cur.append(cx * 30)
		elif not cur.is_empty():
			out.append(cur)
			cur = []
	if not cur.is_empty():
		out.append(cur)
	return out

func _low_places() -> void:
	var lv = LevelScript.new(arena)
	var parts := _floor_parts(lv)
	_say("the low places: the floor has %d parts; a kid is up when it stands 3 rows above the floor or higher (%d tries of 4 s a row)" % [parts.size(), tries])
	var worst := [100.0, 100.0]       # the worst part: with jumps only, with jumps and dashes
	for dash in [false, true]:
		for part in parts:
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var got := 0
			var times: Array = []
			for i in tries:
				var s = _stage(1, 90)
				s.bats_at = -1
				var f = s.fighters[0]
				s._place(f, Vector2i(part[i % part.size()], FLOOR_Y))
				s.step()
				s.take_events()
				var kid = PitProbe.Kid.new()
				kid.rng.seed = rng.randi()
				kid.dash_habit = dash
				for t in MAX_T:
					s.apply_input(f, kid.buttons(s, f), 0)
					s.step()
					if f.on_ground and f.state != P.F_DEAD and f.y + 63 <= FLOOR_Y - 90:
						got += 1
						times.append(t + 1)
						break
			times.sort()
			var share := 100.0 * got / tries
			worst[1 if dash else 0] = minf(worst[1 if dash else 0], share)
			_say("  floor x %d to %d, %s: up in 4 s %d of %d (%d%%), median %s" % [part[0], part[-1], "jump and dash" if dash else "jumps only ",
				got, tries, roundi(share), "-" if times.is_empty() else "%.2f s" % (times[times.size() / 2] / 60.0)])
	_check(worst[0] >= 95.0 and worst[1] >= 85.0, "from every part of the floor the kid is up in 4 s: with jumps only at least 95%% of the time (the worst part: %d%%), with dashes too at least 85%% (%d%%)" % [
		roundi(worst[0]), roundi(worst[1])])

# ------------------------------------------------------------------ part 4
func _view() -> void:
	var lv = LevelScript.new(arena)
	var rv = RooftopsView.new()
	rv.level = lv
	rv._scan()
	var blocks := 0
	var unknown := 0
	var by_kind := {}
	for cy in lv.ROWS:
		for cx in lv.COLS:
			if lv.cell(cx, cy) == lv.SOLID:
				blocks += 1
				var k: int = rv._kind(cx, cy)
				by_kind[k] = by_kind.get(k, 0) + 1
				if k == 0:
					unknown += 1
	_check(unknown == 0, "every block has a kind (%d of %d have none)" % [unknown, blocks])
	for k in [RooftopsView.K_CLOUD, RooftopsView.K_FLOOR, RooftopsView.K_ROOF, RooftopsView.K_CHIM, RooftopsView.K_STACK,
			RooftopsView.K_TOWER, RooftopsView.K_DORMER]:
		_check(by_kind.get(k, 0) > 0, "the map has blocks of kind %d" % k)
	# each roof has a front under it, and its own colour (the view gives them out in turn)
	var roofs := {}                    # the roof's colour -> its cells
	for cy in lv.ROWS:
		for cx in lv.COLS:
			if rv._kind(cx, cy) == RooftopsView.K_ROOF:
				var id: int = rv.roof_of[cy * lv.COLS + cx]
				roofs[id] = roofs.get(id, 0) + 1
	_check(roofs.size() >= 4 and roofs.size() <= RooftopsView.ROOFS.size(),
		"the roofs wear different colours (%d roofs, %d colours to give)" % [roofs.size(), RooftopsView.ROOFS.size()])
	_check(rv.fronts.size() >= roofs.size(), "every roof has a house front under it (%d fronts, %d roofs)" % [rv.fronts.size(), roofs.size()])
	_check(rv.pots.size() >= 4, "the chimneys smoke (%d tops)" % rv.pots.size())
	_check(rv.belfry.size.x > 0.0 and rv.belfry.size.y >= 90.0, "the tower's open belfry is found (%s)" % str(rv.belfry))
	_check(rv.spire.x > 0.0, "the spire is found (%s)" % str(rv.spire))
	_check(rv.wires.size() == RooftopsView.SPANS.size(), "every string of lights hangs between two blocks (%d of %d)" % [rv.wires.size(), RooftopsView.SPANS.size()])
	var hung := 0
	for i in rv.lamps.size():
		var lamp: Array = rv.lamps[i]
		if int(lamp[1]) != 0 or float(lamp[2]) != lamp[0].y - 60.0:    # (60 px over the flame: nothing was found to hang it from)
			hung += 1
	_check(rv.lamps.size() == lv.torches.size() and lv.torches.size() == 8 and hung == rv.lamps.size(),
		"8 torches, each a lantern on a wall or on a chain from a block or a ledge (%d torches, %d hung)" % [lv.torches.size(), hung])
	_say("the page's reading: %d blocks (clouds %d, floor %d, roofs %d, chimneys %d, the stack %d, the tower %d, dormers %d); %d roofs, %d fronts, %d chimney tops, %d strings of lights, %d lanterns" % [
		blocks, by_kind.get(RooftopsView.K_CLOUD, 0), by_kind.get(RooftopsView.K_FLOOR, 0), by_kind.get(RooftopsView.K_ROOF, 0),
		by_kind.get(RooftopsView.K_CHIM, 0), by_kind.get(RooftopsView.K_STACK, 0), by_kind.get(RooftopsView.K_TOWER, 0),
		by_kind.get(RooftopsView.K_DORMER, 0), roofs.size(), rv.fronts.size(), rv.pots.size(), rv.wires.size(), rv.lamps.size()])
	rv.free()

# THE BOILER ROOM's probe (sim/boiler.gd, layout 4): its hazards' rules, offline.
#   godot --headless --path bench --script res://tools/boiler_probe.gd -- [--rounds=N] [--seed=N] [--level=easy|normal|hard]
# Checks: the hazards sit where the map has them (no spawn spot near any of them); a
# fighter in a furnace's fire dies (cause 10) and one outside lives; a plain arrow
# through the fire turns into a fire arrow; the steam shoves a fighter (a knock, no
# kill) and bends a flying arrow; a floor vent throws a fighter up; the hook knocks a
# fighter on the walkway; a bed holds a fighter that falls in, then drops it out of the
# opening above; flee() points a bot out of the fire, and a bot caught on a furnace's
# walkway at the start of a warning gets out alive; the snapshot part reads back the
# same through the page's reader (client/net.gd); a lone fighter (the route runs) never
# sees a hazard move. Then --rounds rounds (200 by default) of 8 bots as arena_probe.gd
# plays them (one life, the purple walls at 25 s): how they die (the furnace share
# must stay under 6%), the shoves, the bed holds, stuck bots (1 in 800 at most, about what
# the other arenas show with this check), and the timing rules
# (the first warning 5 s or more after FIGHT, one furnace and one pipe at a time but
# for the surge). Exits 1 when a check fails.
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const Boiler = preload("res://sim/boiler.gd")
const Brain = preload("res://sim/brain.gd")
const Net = preload("res://client/net.gd")

const ARENA := 4
var fails := 0

func _init() -> void:
	var rounds := 200
	var seed_value := 4004
	var level := Brain.NORMAL
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rounds="):
			rounds = int(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			seed_value = int(a.get_slice("=", 1))
		elif a.begins_with("--level="):
			level = maxi(1, Brain.NAMES.find(a.get_slice("=", 1).to_upper()))
	var lv = LevelScript.new(ARENA)
	print("== %s (layout %d, theme %s)" % [lv.name, ARENA, lv.theme])
	_check("the arena is THE BOILER ROOM with the nightmare theme, in the lobby's list", lv.theme == "nightmare" \
		and LevelScript.PLAY.has(ARENA), "theme %s, PLAY %s" % [lv.theme, str(LevelScript.PLAY)])
	_places(lv)
	_furnace_kills()
	_fire_arrow()
	_steam_shoves()
	_vent_lifts()
	_hook_knocks()
	_bed_holds()
	_flee()
	_lone_fighter()
	_snapshot()
	if rounds > 0:
		_rounds(rounds, seed_value, level)
	if fails == 0:
		print("✅ boiler_probe: every check passed")
		quit(0)
	else:
		printerr("❌ boiler_probe: %d check(s) failed" % fails)
		quit(1)

func _check(name: String, ok: bool, detail: String) -> void:
	if not ok:
		fails += 1
	print("%s %s: %s" % ["PASS" if ok else "FAIL", name, detail])

# A sim on the boiler room with n fighters (seat 0 a person, the rest bots), playing.
func _game(n: int, seed_value: int = 7):
	var sim = SimScript.new(0, 24, seed_value)
	sim.set_arena(ARENA)
	sim.respawn = false
	sim.power_arrows = false
	var seats: Array = []
	for i in n:
		seats.append({"id": i, "bot": i > 0})
	sim.start_round(seats)
	sim.frozen = false
	for f in sim.fighters:
		f.wait_t = 99999          # the bots stand still unless a test lets them play
	return sim

# Puts f with its feet at (x, feet), standing still.
func _put(sim, f, x: float, feet: float) -> void:
	sim._place(f, Vector2i(int(x), int(feet)))

# ------------------------------------------------------------------ where things are
func _places(lv) -> void:
	var bad: Array = []
	var areas: Array = []
	for i in Boiler.FURNACES.size():
		areas.append(["F%d" % i, Boiler.FURNACES[i][2]])
	for i in Boiler.PIPES.size():
		areas.append(["P%d" % i, Boiler.PIPES[i][2]])
	var hk := Boiler.HOOK_PIVOT
	areas.append(["hook", Rect2(hk.x - Boiler.HOOK_LONG, hk.y, Boiler.HOOK_LONG * 2.0, Boiler.HOOK_LONG + Boiler.HOOK_R)])
	var nearest := INF
	for s in lv.spawns:
		var body := Rect2(s.x - 18, s.y - 63, 36, 63)
		for ar in areas:
			var r: Rect2 = ar[1]
			var gap := _rect_gap(r, body)
			if ar[0] != "hook":
				nearest = minf(nearest, gap)
			if gap < 60.0:
				bad.append("spawn (%d, %d) is %d px from %s" % [s.x, s.y, gap, ar[0]])
	_check("no spawn spot within 60 px of a furnace's fire, a pipe's steam or the hook's swing", bad.is_empty(),
		"the nearest is %d px away" % nearest if bad.is_empty() else ", ".join(bad))
	# each furnace's mouth sits on a block's face and its fire is open air; each pipe's
	# valve on a block (or the floor) and its steam open air
	var odd: Array = []
	for i in Boiler.FURNACES.size():
		var spec: Array = Boiler.FURNACES[i]
		var back: Vector2 = spec[0] - Boiler.DIRS[spec[1]] * 6.0
		if lv.cell_at(back.x, back.y) != LevelScript.SOLID:
			odd.append("F%d's mouth is not on a block" % i)
		if _solid_in(lv, spec[2]):
			odd.append("F%d's fire runs into a block" % i)
	for i in Boiler.PIPES.size():
		var spec: Array = Boiler.PIPES[i]
		var back: Vector2 = spec[0] - Boiler.DIRS[spec[1]] * 6.0
		if lv.cell_at(back.x, back.y) != LevelScript.SOLID:
			odd.append("P%d's valve is not on a block" % i)
		if _solid_in(lv, spec[2]):
			odd.append("P%d's steam runs into a block" % i)
	for b in Boiler.BEDS:
		for x in range(b[0] + 1, b[1], 10):
			if lv.cell_at(x, 1025) != LevelScript.EMPTY or lv.cell_at(x, 15) != LevelScript.EMPTY:
				odd.append("bed %d-%d is not over a floor gap with an opening above" % [b[0], b[1]])
				break
	_check("the furnaces' mouths and the pipes' valves sit on blocks, their fire and steam in the open, the beds over the gaps",
		odd.is_empty(), "%d furnaces, %d pipes, %d beds" % [Boiler.FURNACES.size(), Boiler.PIPES.size(), Boiler.BEDS.size()] if odd.is_empty() else ", ".join(odd))

func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return sqrt(dx * dx + dy * dy)

func _solid_in(lv, r: Rect2) -> bool:
	for y in range(int(r.position.y) + 2, int(r.end.y) - 1, 10):
		for x in range(int(r.position.x) + 2, int(r.end.x) - 1, 10):
			if lv.cell_at(x, y) == LevelScript.SOLID:
				return true
	return false

# Runs the hazards' phase forward: hazard h of list (furnaces or pipes) starts its
# warning now (the rest wait).
func _force(sim, list: Array, i: int) -> void:
	var hz = sim.hazards
	for h in hz.furnaces + hz.pipes:
		h.wait = 99999
	hz.hook.wait = 99999
	hz.lights_wait = 99999
	hz.surge_wait = 99999
	hz.tick = 2                    # past the round's first tick (its jitter)
	hz._to_phase(list[i], Boiler.WARN)

# ------------------------------------------------------------------ the fire
func _furnace_kills() -> void:
	var lines: Array = []
	var ok := true
	for i in Boiler.FURNACES.size():
		var sim = _game(3)
		var spec: Array = Boiler.FURNACES[i]
		var r: Rect2 = spec[2]
		var victim = sim.fighters[0]
		var safe = sim.fighters[1]
		# the victim stands (or hangs) in the middle of the fire's area, the other just past its far end
		var c := r.get_center()
		_put(sim, victim, c.x, r.end.y)
		victim.vx = 0.0
		# (past a sideways fire's far end; beside an upward one)
		var far: Vector2 = c + Boiler.DIRS[spec[1]] * (r.size.x * 0.5 + 40.0)
		if spec[1] == 3:
			far = Vector2(r.end.x + 40.0, c.y)
		_put(sim, safe, far.x, r.end.y)
		_put(sim, sim.fighters[2], 1700, 240)
		_force(sim, sim.hazards.furnaces, i)
		var died := -1
		var cause := -1
		var blast_at := -1
		for t in Boiler.FURNACE_WARN + Boiler.FURNACE_BLAST + 5:
			# hold both still where they are (they would fall from a hanging spot)
			if victim.state != P.F_DEAD:
				_put(sim, victim, c.x, r.end.y)
			if safe.state != P.F_DEAD:
				_put(sim, safe, far.x, r.end.y)
			sim.step()
			for e in sim.take_events():
				if e[0] == P.E_FURNACE and e[3] == i:
					blast_at = t + 1
				if e[0] == P.E_DEATH and e[3] == victim.id and died < 0:
					died = t + 1
					cause = e[4]
		var good: bool = cause == 10 and safe.state != P.F_DEAD and blast_at == Boiler.FURNACE_WARN and died >= blast_at
		ok = ok and good
		lines.append("F%d: warning %d ticks, fire on tick %d, the one in it died on tick %d (cause %d: %s), the one past it %s" % [
			i, Boiler.FURNACE_WARN, blast_at, died, cause, P.CAUSES.get(cause, "-"), "lived" if safe.state != P.F_DEAD else "DIED"])
	_check("a fighter in a furnace's fire dies (cause 10), one just past it lives", ok, "; ".join(lines))

func _fire_arrow() -> void:
	var sim = _game(2)
	sim.fighters[0].x = 1700
	sim.fighters[0].y = 200
	sim.fighters[1].x = 1800
	sim.fighters[1].y = 200
	_force(sim, sim.hazards.furnaces, 0)
	sim.hazards.furnaces[0].phase = Boiler.BLAST
	sim.hazards.furnaces[0].t = 20
	var a = SimScript.Arrow.new()
	a.id = 900
	a.kind = P.A_NORMAL
	a.state = P.S_FLY
	a.x = 200.0
	a.y = 700.0
	a.vx = 12.0
	a.vy = 0.0
	a.owner = 5
	sim.arrows.append(a)
	sim.step()
	_check("a plain arrow flying through a furnace's fire turns into a fire arrow", a.kind == P.A_FIRE,
		"its kind after one tick in the fire: %d (fire is %d)" % [a.kind, P.A_FIRE])

# ------------------------------------------------------------------ the steam
func _steam_shoves() -> void:
	var sim = _game(2)
	var f = sim.fighters[0]
	var r: Rect2 = Boiler.PIPES[0][2]          # P0 blows left over the boiler's left catwalk
	_put(sim, f, r.get_center().x + 40.0, r.end.y)
	_put(sim, sim.fighters[1], 1700, 240)
	var x0: int = f.x
	_force(sim, sim.hazards.pipes, 0)
	# a flying arrow along the jet, and its twin in a sim with no steam
	var a = SimScript.Arrow.new()
	a.id = 901
	a.state = P.S_FLY
	a.x = r.end.x - 20.0
	a.y = r.position.y + 20.0
	a.vx = -2.0
	a.vy = -3.0
	a.owner = 5
	a.t = 30
	var twin = SimScript.new(0, 24, 7)
	twin.set_arena(ARENA)
	var b = SimScript.Arrow.new()
	b.id = 902
	b.state = P.S_FLY
	b.x = a.x
	b.y = a.y
	b.vx = a.vx
	b.vy = a.vy
	b.owner = 5
	b.t = 30
	twin.arrows.append(b)
	var hurt := false
	var vented := false
	var died := false
	for t in Boiler.PIPE_WARN + 12:
		if t == Boiler.PIPE_WARN:
			sim.arrows.append(a)
		if t >= Boiler.PIPE_WARN:
			twin.fly_arrows(1)
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_STEAM and e[3] == 0:
				vented = true
			if e[0] == P.E_HURT and e[3] == f.id:
				hurt = true
			if e[0] == P.E_DEATH and e[3] == f.id:
				died = true
	var moved: int = f.x - x0
	var bend: float = a.vx - b.vx
	_check("the steam shoves a fighter along the jet (a knock, not a kill)", vented and hurt and not died and moved < -40,
		"vented %s, knocked %s, moved %d px the jet's way (left) in 12 ticks, %s" % [vented, hurt, moved, "died" if died else "alive"])
	_check("the steam bends a flying arrow along the jet", bend < -3.0 and a.state == P.S_FLY,
		"after 12 ticks its speed along the jet is %.1f px a tick more than the same arrow with no steam (still flying: %s)" % [-bend, a.state == P.S_FLY])

func _vent_lifts() -> void:
	var sim = _game(2)
	var f = sim.fighters[0]
	var r: Rect2 = Boiler.PIPES[2][2]          # P2: the floor vent left of the firebox
	_put(sim, f, r.get_center().x, Boiler.FLOOR_Y)
	_put(sim, sim.fighters[1], 1700, 240)
	var feet0: int = f.y + 63
	_force(sim, sim.hazards.pipes, 2)
	var top := 9999
	for t in Boiler.PIPE_WARN + 60:
		sim.step()
		sim.take_events()
		top = mini(top, f.y + 63)
	var rise: int = feet0 - top
	_check("a floor vent throws a fighter up (onto the catwalk above it)", rise > 300 and f.state != P.F_DEAD,
		"its feet went from %d up to %d (%d px); it landed at %d (the catwalk over the vent is at 600)" % [feet0, top, rise, f.y + 63])

# ------------------------------------------------------------------ the hook
func _hook_knocks() -> void:
	var sim = _game(2)
	var f = sim.fighters[0]
	_put(sim, f, 960, 330)                      # on the big pipe walkway, under the hook
	_put(sim, sim.fighters[1], 1700, 240)
	var hz = sim.hazards
	for h in hz.furnaces + hz.pipes:
		h.wait = 99999
	hz.lights_wait = 99999
	hz.surge_wait = 99999
	hz.tick = 2
	hz._to_phase(hz.hook, Boiler.WARN)
	hz.hook_side = 1
	var knocked := -1
	var x0: int = f.x
	var far := 0
	var knocks := 0
	for t in Boiler.HOOK_WARN + Boiler.HOOK_SWING:
		if knocked < 0:
			_put(sim, f, 960, 330)
		sim.apply_input(f, 0, 0)
		sim.step()
		for e in sim.take_events():
			if e[0] == P.E_HURT and e[3] == f.id:
				knocks += 1
				if knocked < 0:
					knocked = t + 1
		if knocked > 0 and t < knocked + 40:
			far = maxi(far, absi(f.x - x0))
	_check("the swinging hook knocks a fighter standing on the walkway under it (off the walkway)", knocked > Boiler.HOOK_WARN and f.state != P.F_DEAD and far > 200,
		"knocked on tick %d (the swing starts on tick %d), shoved %d px (the walkway's ends are 240 px from the middle), %d knock(s) in the whole swing, %s" % [
		knocked, Boiler.HOOK_WARN, far, knocks, "alive" if f.state != P.F_DEAD else "DEAD"])

# ------------------------------------------------------------------ the beds
func _bed_holds() -> void:
	var sim = _game(2)
	var f = sim.fighters[0]
	_put(sim, sim.fighters[1], 1700, 240)
	var hz = sim.hazards
	for h in hz.furnaces + hz.pipes:
		h.wait = 99999
	hz.hook.wait = 99999
	hz.lights_wait = 99999
	hz.surge_wait = 99999
	var b: Array = Boiler.BEDS[0]
	_put(sim, f, (b[0] + b[1]) / 2.0, Boiler.FLOOR_Y)   # over the gap: it falls
	f.y -= 2
	var held := 0
	var top_at := -1
	var landed_y := -1
	for t in 120:
		sim.apply_input(f, 0, 0)
		sim.step()
		sim.take_events()
		if f.state == P.F_LEDGE:
			held += 1
		if top_at < 0 and f.y + 63 < 200:
			top_at = t + 1
		if top_at > 0 and f.on_ground and landed_y < 0:
			landed_y = f.y + 63
	var shown: bool = hz.beds[0][0] == -1     # shown for BED_SHOW ticks, then cleared
	_check("a bed holds a fighter that falls in (%d ticks), then drops it out of the opening above" % Boiler.BED_HOLD,
		held >= Boiler.BED_HOLD - 1 and held <= Boiler.BED_HOLD + 1 and top_at > 0 and landed_y > 0 and landed_y < 600,
		"held %d ticks, out at the top on tick %d, landed with its feet at %d (the catwalk under the opening: 360)" % [held, top_at, landed_y])

# ------------------------------------------------------------------ the bots
func _flee() -> void:
	var sim = _game(2)
	var bot = sim.fighters[1]
	bot.level = Brain.NORMAL
	var hz = sim.hazards
	var lines: Array = []
	var ok := true
	# out of each furnace's fire, during its warning
	for i in Boiler.FURNACES.size():
		var r: Rect2 = Boiler.FURNACES[i][2]
		_put(sim, bot, r.get_center().x - 20.0, r.end.y)
		for h in hz.furnaces:
			hz._to_phase(h, Boiler.IDLE)
		hz.furnaces[i].phase = Boiler.WARN
		hz.furnaces[i].t = 10
		var want: int = Boiler._away(Boiler.FURNACES[i], bot.x + 18.0)
		var got: int = hz.flee(sim, bot)
		hz.furnaces[i].phase = Boiler.IDLE
		var none: int = hz.flee(sim, bot)
		ok = ok and got == want and got != 0 and none == 0
		lines.append("F%d: %d (resting: %d)" % [i, got, none])
	_check("flee() points a bot out of a furnace's fire while it warns (and nowhere while it rests)", ok, ", ".join(lines))
	# a bot playing on F0's walkway when the warning starts gets out before the fire
	var lived := 0
	var tries := 0
	for k in 10:
		var s2 = _game(2, 50 + k)
		var b2 = s2.fighters[1]
		b2.level = Brain.NORMAL
		b2.wait_t = 0
		var r: Rect2 = Boiler.FURNACES[0][2]
		_put(s2, b2, r.position.x + 30.0 + k * 15.0, r.end.y)
		_put(s2, s2.fighters[0], 1700, 240)
		_force(s2, s2.hazards.furnaces, 0)
		tries += 1
		for t in Boiler.FURNACE_WARN + Boiler.FURNACE_BLAST:
			s2.step()
			s2.take_events()
		if b2.state != P.F_DEAD:
			lived += 1
	_check("a NORMAL bot on a furnace's walkway when its warning starts gets out alive", lived >= 9,
		"%d of %d lived (standing 30 to 165 px from the mouth)" % [lived, tries])

# ------------------------------------------------------------------ no round, no hazards
func _lone_fighter() -> void:
	var sim = SimScript.new(0, 24, 9)
	sim.set_arena(ARENA)
	sim.respawn = false
	sim.start_round([{"id": 0, "bot": false}])
	sim.frozen = false
	var f = sim.fighters[0]
	_put(sim, f, 250, 780)                     # on F0's walkway
	var moved := false
	for t in 2400:
		sim.apply_input(f, 0, 0)
		sim.step()
		sim.take_events()
		for h in sim.hazards.furnaces + sim.hazards.pipes:
			if h.phase != Boiler.IDLE:
				moved = true
	_check("a lone fighter (the route runs, the reach test) never sees a hazard go off", not moved and f.state != P.F_DEAD,
		"40 s on F0's walkway: %s" % ("nothing went off" if not moved else "a hazard went off"))

# ------------------------------------------------------------------ the snapshot
func _snapshot() -> void:
	var sim = _game(4)
	var hz = sim.hazards
	hz.tick = 77
	hz.furnaces[1].phase = Boiler.WARN
	hz.furnaces[1].t = 50
	hz.furnaces[1].surge = true
	hz.pipes[3].phase = Boiler.BLAST
	hz.pipes[3].t = 300
	hz.hook.phase = Boiler.BLAST
	hz.hook.t = 33
	hz.hook_side = -1
	hz.hook_ang = -0.512
	hz.hook_len = 240.0
	hz.lights = Boiler.LIGHTS_DARK
	hz.lights_t = 12
	hz.figure = 2
	hz.surge = Boiler.SURGE_WARN
	hz.surge_t = 40
	hz.beds[1] = [3, 7]
	var buf := StreamPeerBuffer.new()
	sim.write_snapshot(buf, [])
	var reader = Net.new()
	reader._on_snapshot(buf.data_array)
	var s: Dictionary = reader.newest()
	var h: Dictionary = s.get("hazards", {})
	var good: bool = not h.is_empty() and h["n"] == 77 and h["f"][1] == [Boiler.WARN, 50, true] and h["p"][3] == [Boiler.BLAST, 255] \
		and h["hook"]["phase"] == Boiler.BLAST and h["hook"]["side"] == -1 and absf(h["hook"]["ang"] + 0.512) < 0.001 \
		and h["hook"]["len"] == 240.0 and h["lights"] == [Boiler.LIGHTS_DARK, 12] and h["fig"] == 2 and h["surge"] == [Boiler.SURGE_WARN, 40] \
		and h["beds"][1] == [3, 7] and h["beds"][0] == [-1, 0]
	var raw := StreamPeerBuffer.new()
	hz.write(raw)
	_check("the snapshot's hazard part reads back the same through the page's reader (client/net.gd)", good,
		"%d bytes; read: %s" % [raw.data_array.size(), str(h).left(260)])

# ------------------------------------------------------------------ the bots' rounds
func _rounds(count: int, seed_value: int, level: int) -> void:
	var t0 := Time.get_ticks_msec()
	var sim = SimScript.new(0, 24, seed_value)
	sim.bot_level = level
	sim.set_arena(ARENA)
	sim.respawn = false
	sim.power_arrows = false
	sim.walls_start = 25 * 60
	var seats: Array = []
	for i in 8:
		seats.append({"id": i, "bot": true})
	var causes := {}
	var deaths := 0
	var lengths: Array = []
	var draws := 0
	var stuck := 0
	var blasts := 0
	var vents := 0
	var knocks := 0
	var grabs := 0
	var surges := 0
	var lights_out := 0
	var swings := 0
	var first_warn := 99999
	var overlap := 0                 # ticks two furnaces (or two pipes) warned or went off at once outside a surge
	var hz = sim.hazards
	for r in count:
		sim.start_round(seats)
		sim.frozen = false
		var trail := {}
		var stuck_now := {}
		var t := 0
		var was_grab := {}
		var was_lights: int = hz.lights
		var was_hook: int = hz.hook.phase
		var was_surge: int = hz.surge
		while t < 3600:
			sim.step()
			t += 1
			for e in sim.take_events():
				if e[0] == P.E_DEATH:
					deaths += 1
					causes[e[4]] = causes.get(e[4], 0) + 1
				elif e[0] == P.E_FURNACE:
					blasts += 1
				elif e[0] == P.E_STEAM:
					vents += 1
				elif e[0] == P.E_HURT:
					knocks += 1
			var busy_f := 0
			var busy_p := 0
			var surge_on := false
			for h in hz.furnaces:
				if h.phase == Boiler.WARN or h.phase == Boiler.BLAST:
					busy_f += 1
					first_warn = mini(first_warn, t) if h.phase == Boiler.WARN else first_warn
					surge_on = surge_on or h.surge
			for h in hz.pipes:
				if h.phase == Boiler.WARN or h.phase == Boiler.BLAST:
					busy_p += 1
					first_warn = mini(first_warn, t) if h.phase == Boiler.WARN else first_warn
			if (busy_f > 1 and not surge_on) or busy_p > 1:
				overlap += 1
			for seat in hz.held:
				if not was_grab.has(seat):
					grabs += 1
			was_grab = hz.held.duplicate()
			if hz.lights == Boiler.LIGHTS_DARK and was_lights != Boiler.LIGHTS_DARK:
				lights_out += 1
			was_lights = hz.lights
			if hz.hook.phase == Boiler.BLAST and was_hook != Boiler.BLAST:
				swings += 1
			was_hook = hz.hook.phase
			if hz.surge == Boiler.SURGE_WARN and was_surge != Boiler.SURGE_WARN:
				surges += 1
			was_surge = hz.surge
			if t % 30 == 0:
				for f in sim.fighters:
					if f.state == P.F_DEAD:
						continue
					var tr: Array = trail.get(f.id, [])
					tr.append(Vector2(f.x, f.y))
					if tr.size() > 10:
						tr.remove_at(0)
					trail[f.id] = tr
					if tr.size() == 10 and not stuck_now.has(f.id):
						var lo: Vector2 = tr[0]
						var hi: Vector2 = tr[0]
						for p in tr:
							lo = lo.min(p)
							hi = hi.max(p)
						if hi.x - lo.x < 90.0 and hi.y - lo.y < 90.0:
							stuck_now[f.id] = true
			if sim.alive_count() <= 1:
				break
		stuck += stuck_now.size()
		lengths.append(t / 60.0)
		if sim.alive_count() == 0 or t >= 3600:
			draws += 1
	lengths.sort()
	var parts: Array = []
	var ks: Array = causes.keys()
	ks.sort()
	for k in ks:
		parts.append("%s %d (%.1f%%)" % [P.CAUSES.get(k, str(k)), causes[k], 100.0 * causes[k] / maxi(1, deaths)])
	var share: float = 100.0 * causes.get(10, 0) / maxi(1, deaths)
	print("   %d rounds of 8 %s bots: length median %.1f s, p90 %.1f s; draws %d%%; %d deaths: %s" % [count, Brain.NAMES[level],
		lengths[count / 2], lengths[int(count * 0.9)], roundi(100.0 * draws / count), deaths, ", ".join(parts)])
	print("   in those rounds: %d furnace blasts (%d surges), %d steam vents, %d hook swings, %d times the lights went out, %d bed holds, %d knocks (steam, hook, bumps); (%.1f s)" % [
		blasts, surges, vents, swings, lights_out, grabs, knocks, (Time.get_ticks_msec() - t0) / 1000.0])
	_check("furnace deaths under 6%% of all deaths (%d rounds of 8 bots)" % count, share < 6.0, "%.1f%% (%d of %d)" % [share, causes.get(10, 0), deaths])
	# (the bot brain itself loops now and then: two bots hopping at each other, or one
	# walking back to a move's start where a warning pushes it away; this same check gives
	# THE KEEP 1-2 and THE HAUNTED HOUSE 0-4 of 1600 bot rounds; arena_probe.gd's own
	# --rounds=200 run on this arena shows 0)
	_check("bots stuck 5 s (inside a 90 px square while alive) no more than 1 bot round in 800", stuck * 800 <= count * 8,
		"%d of %d bot rounds" % [stuck, count * 8])
	_check("the first warning comes 5 s or more after FIGHT; one furnace and one pipe at a time (but the surge)", first_warn >= 300 and overlap == 0,
		"the first warning on tick %d; %d ticks with two at once" % [first_warn, overlap])

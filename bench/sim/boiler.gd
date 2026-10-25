# THE BOILER ROOM's hazards (theme "nightmare", sim/level.gd layout 4): the furnaces that
# blast fire, the pressure pipes that bulge and vent steam, the hook that swings on its
# chain, the lights that go out, the nightmare surge (every furnace at once) and the beds
# that pull you through. The sim makes one for an arena whose theme is "nightmare"
# (sim.gd hazards), calls reset() each round and step() each tick of play; the snapshot
# carries the state (write, read) for the page's look (client/boiler_view.gd); the bots
# ask flee() which way to step away. Everything is fair: each hazard warns first (a
# furnace 1.75 s, a pipe 1.25 s, the hook 1.25 s, the surge 3 s), the areas are small,
# none covers a spawn spot, the first one comes 5 s after FIGHT, and the timers are
# staggered (one furnace and one pipe at a time). Randomness comes from sim.rng: the
# server runs the rules, the page only draws them.
extends RefCounted

const P = preload("res://sim/proto.gd")

const W := 1920
const H := 1080
# a hazard's phases (furnace, pipe, hook): resting, warning, going off, cooling down
const IDLE := 0
const WARN := 1          # a furnace's grate glows, a pipe bulges, the hook's chain rattles
const BLAST := 2         # fire, steam, the swing
const COOL := 3          # smoke after the fire; the hook settles
# a direction (the events' b): 0 right, 1 down, 2 left, 3 up
const DIRS := [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)]

# The furnaces: [mouth (px), direction, the blast's area]. F0 is built into the left wall
# (its mouth at col 5, the fire over its walkway, row 26), F1 into the right wall (mouth
# at col 59, its walkway row 29), F2 is the great boiler's firebox (its fire goes up into
# the tunnel between the firebox, row 30, and the boiler, row 25).
const FURNACES := [
	[Vector2(150, 735), 0, Rect2(150, 690, 210, 90)],
	[Vector2(1770, 825), 2, Rect2(1560, 780, 210, 90)],
	[Vector2(960, 900), 3, Rect2(840, 780, 240, 120)],
]
const FURNACE_WARN := 105        # 1.75 s: the grate glows hotter, sparks, a low rumble
const FURNACE_BLAST := 60        # 1 s of fire
const FURNACE_GROW := 6          # the fire reaches its full length in this many ticks
const FURNACE_COOL := 45
const FURNACE_IDLE := [480, 780] # 8 to 13 s between a furnace's blasts
const FURNACE_FIRST := [300, 480, 660]   # the first warnings 5 s, 8 s and 11 s after FIGHT (+ up to 1 s), the furnaces in a new order each round
const BURN_MARGIN := 3           # a body this far inside the fire's edge burns (the fire's edge flickers)
const FLEE_MARGIN := 14.0        # flee: bots keep this far out of a fire's area (10 more in the surge)
const COLUMN_UP := 220.0         # flee: bots keep out of the open space this high over a sideways fire,
const COLUMN_DOWN := 260.0       # and this deep under it, in the fire's last second (a drop or a jump would land in it)

# The pressure pipes: [valve (px), direction, the steam's area]. P0 comes out of the
# boiler's left side over its catwalk (row 20), P1 out of its right side over the other
# catwalk (row 23); P2 and P3 are floor vents beside the firebox that blow straight up
# (each lifts you onto the catwalk above it).
const PIPES := [
	[Vector2(810, 560), 2, Rect2(600, 520, 210, 80)],
	[Vector2(1110, 650), 0, Rect2(1110, 610, 210, 80)],
	[Vector2(765, 1020), 3, Rect2(720, 640, 90, 380)],
	[Vector2(1155, 1020), 3, Rect2(1110, 700, 90, 320)],
]
const PIPE_WARN := 75            # 1.25 s: the pipe bulges, hisses, the gauge climbs
const PIPE_VENT := 90            # 1.5 s of steam
const PIPE_GROW := 6
const PIPE_IDLE := [360, 660]    # 6 to 11 s between a pipe's vents
const PIPE_FIRST := [330, 450, 570, 690] # (+ up to 1 s, in a new order each round)
const STEAM_KICK := 10.0         # the first touch of the steam shoves you this hard (a knock, no kill)
const STEAM_LIFT := 14.0         # a floor vent throws you up this fast
const STEAM_PUSH := 0.6          # then each tick in the steam pushes you on this much (sideways jets)
const STEAM_MAX := 12.0
const ARROW_PUSH := 0.9          # the steam bends arrows (flying and falling) along the jet
const ARROW_MAX := 22.0

# The hook: a heavy hook on a chain from the ceiling over the big pipe walkway (row 11).
# At rest it hangs high on a short chain; the chain rattles (the warning) as it is hauled
# back to one side; then it drops on a long chain and swings across twice, knocking
# anyone it meets (and bouncing arrows); then it is hauled up again.
const HOOK_PIVOT := Vector2(960, 60)
const HOOK_SHORT := 110.0
const HOOK_LONG := 240.0
const HOOK_R := 24.0
const HOOK_SWING_A := 1.05       # radians (60 degrees) out to each side
const HOOK_PERIOD := 75          # ticks for a swing there and back
const HOOK_WARN := 75
const HOOK_SWING := 150          # two swings there and back
const HOOK_SETTLE := 45
const HOOK_IDLE := [540, 900]
const HOOK_FIRST := 420          # (+ up to 4 s)
const HOOK_KNOCK := 14.0         # a hard knock: off the walkway, out of its way
const HOOK_REACH_X := 185.0      # it comes low enough to meet a body on the walkway this far either side of the middle

# The lights go out now and then: the caged bulbs flicker (the warning), then darkness
# (only the furnaces glow, and something tall stands in a furnace's light), then they
# flicker back on. Only the look changes.
const LIGHTS_ON := 0
const LIGHTS_FLICKER := 1
const LIGHTS_DARK := 2
const LIGHTS_BACK := 3
const LIGHTS_STEPS := [0, 120, 180, 30]  # ticks of each (on: until the next time)
const LIGHTS_FIRST := [420, 660]  # 7 to 11 s after FIGHT (rounds with 8 fighters often last 10 to 15 s)
const LIGHTS_GAP := [1080, 1560]
# where the tall shadow can stand (its feet; client/boiler_view.gd draws it): on each
# furnace's walkway and on the firebox in the tunnel. It picks one with nobody near.
const FIGURE_AT := [Vector2(262, 780), Vector2(1660, 870), Vector2(900, 900)]

# The nightmare surge: a long warning (the room turns red, a heartbeat), then every
# furnace blasts at once. The first comes 13 to 17 s after FIGHT, then every 25 to 32 s.
const SURGE_IDLE := 0
const SURGE_WARN := 1
const SURGE_WARN_T := 180
const SURGE_FIRST := [780, 1020]
const SURGE_GAP := [1500, 1920]

# The beds over the floor gaps (cols 12-15 and 48-51): fall in and the sheets grab you,
# hold you a moment (BED_HOLD) while hands pull you down, then drop you through: you
# fall out of the opening in the ceiling above. [gap's left x, right x].
const BEDS := [[360, 480], [1440, 1560]]
const FLOOR_Y := 1020
const BED_HOLD := 18             # 0.3 s held in the sheets (the fighter hangs, as from a ledge)
const BED_SINK := 1              # px a tick it sinks while held
const BED_DROP := 9.0            # then it is pulled down this fast
const BED_AGAIN := 45            # ticks before the same fighter can be grabbed again
const BED_SHOW := 40             # the bed's state shows a grab this long (the page's sheets and hands)

# A test knob (the server's --boiler-demo, for the review pictures): everything comes
# sooner and more often, an idle pipe goes off when someone stands in its steam's way,
# the bots do not step out of the steam, bots 5, 6 and 7 walk into the beds and through
# the lockers, and the server prints a timeline ([BOILER] lines). Off unless that flag
# is given (the page never has it).
static var demo: bool = OS.get_cmdline_user_args().has("--boiler-demo")
const DEMO := {"furnace_first": [240, 420, 600], "furnace_idle": [200, 320], "pipe_first": [210, 300, 390, 480],
	"pipe_idle": [150, 300], "hook_first": 300, "hook_idle": [300, 420], "lights_first": [600, 660],
	"lights_gap": [900, 1100], "surge_first": [270, 300], "surge_gap": [1000, 1200]}

class Hazard:
	var phase: int = IDLE
	var t: int = 0               # ticks in this phase
	var wait: int = 0            # ticks until the next warning (while idle)
	var surge: bool = false      # a furnace's warning and blast are the surge's
	var hit := {}                # seat -> true: the steam or the hook already shoved it this time

var level
var tick: int = 0                # ticks of play this round
var furnaces: Array = []
var pipes: Array = []
var hook := Hazard.new()
var hook_side: int = 1           # the hook is hauled back to this side (1 right, -1 left), then swings
var hook_ang: float = 0.0        # its angle from straight down (radians, + to the right)
var hook_len: float = HOOK_SHORT
var hook_x: float = HOOK_PIVOT.x
var hook_y: float = HOOK_PIVOT.y + HOOK_SHORT
var hook_vx: float = 0.0         # how fast it moves sideways (px a tick), for the knock's way
var hook_cd := {}                # seat -> ticks before the hook can knock it again
var lights: int = LIGHTS_ON
var lights_t: int = 0
var lights_wait: int = 0
var figure: int = -1             # the shadow's spot while the lights are out (-1: none)
var surge: int = SURGE_IDLE
var surge_t: int = 0
var surge_wait: int = 0
var beds: Array = []             # [the seat it holds (-1: none), ticks since the grab]
var held := {}                   # seat -> [bed, ticks held]
var bed_cd := {}                 # seat -> ticks before it can be grabbed again
var demo_x := {}                 # (the demo's timeline) seat -> x last tick
var demo_dir := {}               # (the demo) seat -> the way it walks through a locker
var timing := {"furnace_first": FURNACE_FIRST, "furnace_idle": FURNACE_IDLE, "pipe_first": PIPE_FIRST,
	"pipe_idle": PIPE_IDLE, "hook_first": HOOK_FIRST, "hook_idle": HOOK_IDLE, "lights_first": LIGHTS_FIRST,
	"lights_gap": LIGHTS_GAP, "surge_first": SURGE_FIRST, "surge_gap": SURGE_GAP}

func _init(lv) -> void:
	level = lv
	if demo:
		timing = DEMO.duplicate()
	for i in FURNACES.size():
		furnaces.append(Hazard.new())
	for i in PIPES.size():
		pipes.append(Hazard.new())
	for i in BEDS.size():
		beds.append([-1, 0])
	reset()

# A new round: everything rests; the first warnings are set (the randomness of the
# round comes later, from sim.rng in step, so a reset needs no sim).
func reset() -> void:
	tick = 0
	for i in furnaces.size():
		var h: Hazard = furnaces[i]
		h.phase = IDLE
		h.t = 0
		h.surge = false
		h.wait = timing["furnace_first"][i % FURNACE_FIRST.size()]
		h.hit.clear()
	for i in pipes.size():
		var h: Hazard = pipes[i]
		h.phase = IDLE
		h.t = 0
		h.wait = timing["pipe_first"][i % PIPE_FIRST.size()]
		h.hit.clear()
	hook.phase = IDLE
	hook.t = 0
	hook.wait = timing["hook_first"]
	hook.hit.clear()
	hook_cd.clear()
	hook_ang = 0.0
	hook_len = HOOK_SHORT
	_place_hook()
	hook_vx = 0.0
	lights = LIGHTS_ON
	lights_t = 0
	lights_wait = -1             # picked on the first tick (sim.rng)
	figure = -1
	surge = SURGE_IDLE
	surge_t = 0
	surge_wait = -1
	for b in beds:
		b[0] = -1
		b[1] = 0
	held.clear()
	bed_cd.clear()

# One tick of play (not while the round's first moment holds everyone still). With
# fewer than two fighters it is no round (a probe's lone fighter, the lobby): nothing
# moves. Once the round is decided (one fighter left, or none) nothing new starts and
# nothing hurts anyone, as with the power-ups and the purple walls.
func step(sim) -> void:
	if sim.fighters.size() < 2:
		return
	tick += 1
	var rng: RandomNumberGenerator = sim.rng
	if tick == 1:
		# the round's own randomness: which furnace and which pipe go first, a little
		# jitter, when the lights go out and the surge comes
		_deal(rng, furnaces, timing["furnace_first"])
		_deal(rng, pipes, timing["pipe_first"])
		hook.wait += rng.randi_range(0, 240 if not demo else 30)
		lights_wait = rng.randi_range(timing["lights_first"][0], timing["lights_first"][1])
		surge_wait = rng.randi_range(timing["surge_first"][0], timing["surge_first"][1])
	var live: bool = sim.alive_count() > 1
	if demo:   # (the timeline: someone through a locker, someone knocked)
		for f in sim.fighters:
			var lx: int = demo_x.get(f.id, f.x)
			if f.state != P.F_DEAD and absi(f.x - lx) > 900 and f.y + 63 > 420 and f.y < 540:
				_say("locker: seat %d from the %s" % [f.id, "left" if lx < 960 else "right"])
			demo_x[f.id] = f.x
			if f.state == P.F_HURT and f.state_t == 1:
				_say("knock: seat %d" % f.id)
	_step_surge(sim, live)
	for i in furnaces.size():
		_step_furnace(sim, i, live)
	for i in pipes.size():
		_step_pipe(sim, i, live)
	_step_hook(sim, live)
	_step_lights(sim)
	_step_beds(sim, live)

# ------------------------------------------------------------------ the furnaces
func _furnace_busy(except: int) -> bool:
	for i in furnaces.size():
		if i != except and (furnaces[i].phase == WARN or furnaces[i].phase == BLAST):
			return true
	return false

func _step_furnace(sim, i: int, live: bool) -> void:
	var h: Hazard = furnaces[i]
	h.t += 1
	if h.phase == IDLE:
		if surge == SURGE_WARN:
			return               # the surge holds every furnace for its own blast
		h.wait -= 1
		if h.wait <= 0 and live:
			if _furnace_busy(i):
				h.wait = 45      # one furnace at a time: try again in 0.75 s
			else:
				_to_phase(h, WARN)
				h.surge = false
	elif h.phase == WARN:
		var need: int = SURGE_WARN_T if h.surge else FURNACE_WARN
		if not live:
			_to_phase(h, IDLE)        # the round is decided: the warning dies down
			h.wait = FURNACE_IDLE[0]
		elif h.t >= need:
			_to_phase(h, BLAST)
			var f: Array = FURNACES[i]
			sim._event(P.E_FURNACE, int(f[0].x), int(f[0].y), i, int(f[1]))
	elif h.phase == BLAST:
		if live:
			_burn(sim, i, h.t)
		if h.t >= FURNACE_BLAST:
			_to_phase(h, COOL)
	elif h.phase == COOL:
		if h.t >= FURNACE_COOL:
			_to_phase(h, IDLE)
			h.surge = false
			h.wait = sim.rng.randi_range(timing["furnace_idle"][0], timing["furnace_idle"][1])

# The fire's area this tick: it grows out of the mouth over FURNACE_GROW ticks.
static func fire_rect(i: int, t: int) -> Rect2:
	var f: Array = FURNACES[i]
	var r: Rect2 = f[2]
	var k := clampf(float(t) / FURNACE_GROW, 0.0, 1.0)
	return _grown(r, int(f[1]), k)

# A jet's area at share k of its length, from its source along its direction.
static func _grown(r: Rect2, dir: int, k: float) -> Rect2:
	if dir == 0:
		return Rect2(r.position, Vector2(r.size.x * k, r.size.y))
	if dir == 2:
		return Rect2(r.end.x - r.size.x * k, r.position.y, r.size.x * k, r.size.y)
	if dir == 3:
		return Rect2(r.position.x, r.end.y - r.size.y * k, r.size.x, r.size.y * k)
	return Rect2(r.position, Vector2(r.size.x, r.size.y * k))

# The fire burns every living fighter whose body is in it (cause 10: a furnace), and
# a plain arrow flying through it catches fire (it lands as a fire arrow).
func _burn(sim, i: int, t: int) -> void:
	var r := fire_rect(i, t)
	var dir: Vector2 = DIRS[FURNACES[i][1]]
	for f in sim.fighters:
		if f.state == P.F_DEAD:
			continue
		var body := Rect2(f.x + BURN_MARGIN, f.y + BURN_MARGIN, 36 - BURN_MARGIN * 2, 63 - BURN_MARGIN * 2)
		if _hits(r, body):
			sim._kill(f, 255, 10)
			f.vx = dir.x * 7.0
			f.vy = -6.0 + dir.y * 5.0
	for a in sim.arrows:
		if not a.dead and a.state == P.S_FLY and a.kind == P.A_NORMAL and _point_in(r, a.x, a.y):
			a.kind = P.A_FIRE

# ------------------------------------------------------------------ the pipes
func _pipe_busy(except: int) -> bool:
	for i in pipes.size():
		if i != except and (pipes[i].phase == WARN or pipes[i].phase == BLAST):
			return true
	return false

func _step_pipe(sim, i: int, live: bool) -> void:
	var h: Hazard = pipes[i]
	h.t += 1
	if h.phase == IDLE:
		h.wait -= 1
		if demo and h.wait > 20 and _someone_in(sim, PIPES[i][2]):
			h.wait = 20
		if h.wait <= 0 and live:
			if _pipe_busy(i):
				h.wait = 40
			else:
				_to_phase(h, WARN)
	elif h.phase == WARN:
		if h.t >= PIPE_WARN:
			_to_phase(h, BLAST)
			h.hit.clear()
			var p: Array = PIPES[i]
			sim._event(P.E_STEAM, int(p[0].x), int(p[0].y), i, int(p[1]))
	elif h.phase == BLAST:
		if live:
			_steam(sim, i, h)
		if h.t >= PIPE_VENT:
			_to_phase(h, IDLE)
			h.wait = sim.rng.randi_range(timing["pipe_idle"][0], timing["pipe_idle"][1])

func _someone_in(sim, r: Rect2) -> bool:
	for f in sim.fighters:
		if f.state != P.F_DEAD and _hits(r, Rect2(f.x, f.y, 36, 63)):
			return true
	return false

static func steam_rect(i: int, t: int) -> Rect2:
	var p: Array = PIPES[i]
	return _grown(p[2], int(p[1]), clampf(float(t) / PIPE_GROW, 0.0, 1.0))

# The steam shoves each living fighter it first touches (a knock: no control for a
# moment, no kill), then keeps pushing it along the jet; a floor vent throws it up.
# Bodies are blown along, flying and falling arrows bend with the jet, and arrows
# stuck in its way are blown loose.
func _steam(sim, i: int, h: Hazard) -> void:
	var r := steam_rect(i, h.t)
	var d: int = PIPES[i][1]
	var dir: Vector2 = DIRS[d]
	for f in sim.fighters:
		var body := Rect2(f.x, f.y, 36, 63)
		if not _hits(r, body):
			continue
		if f.state == P.F_DEAD:
			if not f.pinned:
				if d == 3:
					f.vy = minf(f.vy, -STEAM_LIFT * 0.8)
				else:
					f.vx = clampf(f.vx + dir.x * STEAM_PUSH * 2.0, -STEAM_MAX, STEAM_MAX)
			continue
		if not h.hit.has(f.id):
			h.hit[f.id] = true
			if d == 3:
				sim._hurt(f, f.vx * 0.5, -STEAM_LIFT)
			else:
				sim._hurt(f, dir.x * STEAM_KICK, -5.0)
		elif d == 3:
			f.vy = minf(f.vy, -STEAM_LIFT)   # it keeps rising while it is in the steam
		else:
			f.vx = clampf(f.vx + dir.x * STEAM_PUSH, -STEAM_MAX, STEAM_MAX)
	for a in sim.arrows:
		if a.dead or a.state == P.S_BODY or a.pins >= 0 or not _point_in(r, a.x, a.y):
			continue
		if a.state == P.S_STUCK:
			if a.fuse < 0:
				a.state = P.S_FALL
				a.vx = dir.x * 9.0 + (sim.rng.randf_range(-2.0, 2.0) if d == 3 else 0.0)
				a.vy = -10.0 if d == 3 else -4.0
		else:
			a.vx = clampf(a.vx + dir.x * ARROW_PUSH, -ARROW_MAX, ARROW_MAX)
			a.vy = clampf(a.vy + dir.y * ARROW_PUSH - (0.3 if d == 3 else 0.0), -ARROW_MAX, ARROW_MAX)

# ------------------------------------------------------------------ the hook
func _step_hook(sim, live: bool) -> void:
	hook.t += 1
	for k in hook_cd.keys():
		hook_cd[k] -= 1
		if hook_cd[k] <= 0:
			hook_cd.erase(k)
	var x0 := hook_x
	if hook.phase == IDLE:
		hook_len = HOOK_SHORT
		hook_ang = sin(tick * TAU / 200.0) * 0.07      # a slow sway, high over the walkway
		hook.wait -= 1
		if hook.wait <= 0 and live:
			_to_phase(hook, WARN)
			hook_side = 1 if sim.rng.randf() < 0.5 else -1
	elif hook.phase == WARN:
		# hauled back to its side; the chain rattles (the page shakes it)
		var k := _ease(float(hook.t) / HOOK_WARN)
		hook_len = HOOK_SHORT
		hook_ang = hook_side * HOOK_SWING_A * k
		if hook.t >= HOOK_WARN:
			_to_phase(hook, BLAST)
			hook_cd.clear()
	elif hook.phase == BLAST:
		# let go: the chain pays out to its long length, and it swings across twice
		var u := float(hook.t)
		hook_len = lerpf(HOOK_SHORT, HOOK_LONG, clampf(u / 14.0, 0.0, 1.0))
		hook_ang = hook_side * HOOK_SWING_A * cos(u * TAU / HOOK_PERIOD) * (1.0 - 0.3 * u / HOOK_SWING)
		if hook.t >= HOOK_SWING:
			_to_phase(hook, COOL)
	elif hook.phase == COOL:
		var k := clampf(float(hook.t) / HOOK_SETTLE, 0.0, 1.0)
		hook_len = lerpf(HOOK_LONG, HOOK_SHORT, _ease(k))
		hook_ang = lerpf(hook_ang, 0.0, 0.12)
		if hook.t >= HOOK_SETTLE:
			_to_phase(hook, IDLE)
			hook.wait = sim.rng.randi_range(timing["hook_idle"][0], timing["hook_idle"][1])
	_place_hook()
	hook_vx = hook_x - x0
	if hook.phase == BLAST and live:
		_hook_hits(sim)

func _place_hook() -> void:
	hook_x = HOOK_PIVOT.x + sin(hook_ang) * hook_len
	hook_y = HOOK_PIVOT.y + cos(hook_ang) * hook_len

# The swinging hook knocks a fighter it meets the way it swings (once a pass) and
# bounces a flying or falling arrow.
func _hook_hits(sim) -> void:
	for f in sim.fighters:
		if f.state == P.F_DEAD or hook_cd.has(f.id):
			continue
		var dx: float = (f.x + 18.0) - hook_x
		var dy: float = (f.y + 31.0) - hook_y
		if absf(dx) < 18.0 + HOOK_R and absf(dy) < 31.0 + HOOK_R:
			var way := signf(hook_vx) if absf(hook_vx) > 0.5 else (signf(dx) if dx != 0.0 else 1.0)
			sim._hurt(f, way * HOOK_KNOCK, -8.0)
			hook_cd[f.id] = 24
	for a in sim.arrows:
		if a.dead or (a.state != P.S_FLY and a.state != P.S_FALL):
			continue
		var dx: float = a.x - hook_x
		var dy: float = a.y - hook_y
		if dx * dx + dy * dy < HOOK_R * HOOK_R:
			a.state = P.S_FALL
			a.vx = -a.vx * 0.3 + hook_vx * 0.6
			a.vy = -5.0
			sim._event(P.E_TINK, int(a.x), int(a.y), 0, 0)

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)

# ------------------------------------------------------------------ the lights, the surge
func _step_lights(sim) -> void:
	lights_t += 1
	if lights == LIGHTS_ON:
		lights_wait -= 1
		if lights_wait <= 0 and surge != SURGE_WARN:
			lights = LIGHTS_FLICKER
			lights_t = 0
	elif lights_t >= LIGHTS_STEPS[lights]:
		lights_t = 0
		if lights == LIGHTS_FLICKER:
			lights = LIGHTS_DARK
			figure = _figure_spot(sim)
			if demo:
				_say("lights out, the shadow at %d" % figure)
		elif lights == LIGHTS_DARK:
			lights = LIGHTS_BACK
			figure = -1
		else:
			lights = LIGHTS_ON
			lights_wait = sim.rng.randi_range(timing["lights_gap"][0], timing["lights_gap"][1])

# A spot for the tall shadow with no living fighter within 220 px (any spot if none is free).
func _figure_spot(sim) -> int:
	var free: Array = []
	for i in FIGURE_AT.size():
		var p: Vector2 = FIGURE_AT[i]
		var near := false
		for f in sim.fighters:
			if f.state != P.F_DEAD and Vector2(f.x + 18.0, f.y + 63.0).distance_to(p) < 220.0:
				near = true
		if not near:
			free.append(i)
	if free.is_empty():
		return sim.rng.randi() % FIGURE_AT.size()
	return free[sim.rng.randi() % free.size()]

func _step_surge(sim, live: bool) -> void:
	surge_t += 1
	if surge == SURGE_IDLE:
		surge_wait -= 1
		if surge_wait <= 0 and live:
			var busy := false
			for h in furnaces:
				if h.phase == WARN or h.phase == BLAST:
					busy = true
			if not busy and lights == LIGHTS_ON:
				surge = SURGE_WARN
				surge_t = 0
				if demo:
					_say("surge warn")
				for h in furnaces:   # (one still cooling down joins in)
					_to_phase(h, WARN)
					h.surge = true
			else:
				surge_wait = 30  # wait until no furnace warns or burns (and the lights are on)
	elif surge == SURGE_WARN:
		if not live or surge_t >= SURGE_WARN_T:
			surge = SURGE_IDLE
			surge_t = 0
			surge_wait = sim.rng.randi_range(timing["surge_gap"][0], timing["surge_gap"][1])

# ------------------------------------------------------------------ the beds
# A living fighter that falls into a bed (its middle over the gap, its feet below the
# floor) is held there a moment, as if hanging from a ledge (the page draws the sheets
# rising and the hands), sinking a little, then pulled down through: it falls out of
# the opening in the ceiling above the bed. Going up through a bed holds nobody.
func _step_beds(sim, live: bool) -> void:
	for k in bed_cd.keys():
		bed_cd[k] -= 1
		if bed_cd[k] <= 0:
			bed_cd.erase(k)
	for b in beds:
		if b[0] >= 0:
			b[1] += 1
			if b[1] >= BED_SHOW:
				b[0] = -1
	for seat in held.keys():
		var f = sim.fighter(seat)
		var hd: Array = held[seat]
		hd[1] += 1
		if f == null or f.state != P.F_LEDGE:
			held.erase(seat)     # killed (a stomp, an arrow) or freed some other way
			continue
		f.vx = 0.0
		f.vy = 0.0
		f.y += BED_SINK
		if hd[1] >= BED_HOLD:
			f.state = P.F_NORMAL
			f.state_t = 0
			f.ledge_t = 0
			f.vy = BED_DROP
			held.erase(seat)
			bed_cd[seat] = BED_AGAIN
	if not live:
		return
	for f in sim.fighters:
		if f.state == P.F_DEAD or f.state == P.F_LEDGE or held.has(f.id) or bed_cd.has(f.id) or f.vy < 0.0:
			continue
		var feet: int = f.y + 63
		if feet <= FLOOR_Y + 2 or feet >= H:
			continue
		var cx: float = f.x + 18.0
		for bi in BEDS.size():
			var bx: Array = BEDS[bi]
			if cx > bx[0] + 6 and cx < bx[1] - 6:
				f.state = P.F_LEDGE
				f.state_t = 0
				f.ledge_t = 99   # (it never runs out: the bed lets go first)
				f.vx = 0.0
				f.vy = 0.0
				f.rx = 0.0
				f.ry = 0.0
				f.aiming = false
				held[f.id] = [bi, 0]
				beds[bi][0] = f.id
				beds[bi][1] = 0
				if demo:
					_say("bed %d grabs seat %d" % [bi, f.id])
				break

# ------------------------------------------------------------------ helpers
# The first warnings (slots, in ticks after FIGHT) go to the hazards in a random
# order, each a little later by up to 1 s.
func _deal(rng: RandomNumberGenerator, list: Array, slots: Array) -> void:
	var order: Array = range(list.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	for k in list.size():
		list[order[k]].wait = slots[k % slots.size()] + rng.randi_range(0, 60)

func _to_phase(h: Hazard, phase: int) -> void:
	h.phase = phase
	h.t = 0
	if demo:
		var what := "furnace %d" % furnaces.find(h) if furnaces.has(h) else ("pipe %d" % pipes.find(h) if pipes.has(h) else "hook")
		_say("%s %s%s" % [what, ["rest", "warn", "go", "cool"][phase], " (surge)" if h.surge else ""])

# The demo's timeline (wall clock), printed by the server.
func _say(text: String) -> void:
	print("[BOILER] %.2f %s" % [Time.get_unix_time_from_system(), text])

static func _hits(a: Rect2, b: Rect2) -> bool:
	return a.size.x > 0.0 and a.size.y > 0.0 and a.position.x < b.end.x and b.position.x < a.end.x \
		and a.position.y < b.end.y and b.position.y < a.end.y

static func _point_in(r: Rect2, x: float, y: float) -> bool:
	return x >= r.position.x and x < r.end.x and y >= r.position.y and y < r.end.y

# ------------------------------------------------------------------ the snapshot
# The state for the page (sim.gd write_snapshot calls it after the ghosts):
#   u8 tick (low byte, the page sees each new snapshot), u8 furnaces, each u8 phase
#   (+ 0x80 the surge's), u8 ticks in it (at most 255); u8 pipes, each u8 phase, u8 ticks;
#   the hook: u8 phase, u8 ticks, s8 side, s16 angle (1/1000 rad), u8 chain length (px / 2);
#   the lights: u8 state, u8 ticks, u8 the shadow's spot (255: none); the surge: u8 state,
#   u8 ticks; u8 beds, each u8 the seat it holds (255: none), u8 ticks since the grab.
func write(buf: StreamPeerBuffer) -> void:
	buf.put_u8(tick & 255)
	buf.put_u8(furnaces.size())
	for h in furnaces:
		buf.put_u8(h.phase | (0x80 if h.surge else 0))
		buf.put_u8(mini(h.t, 255))
	buf.put_u8(pipes.size())
	for h in pipes:
		buf.put_u8(h.phase)
		buf.put_u8(mini(h.t, 255))
	buf.put_u8(hook.phase)
	buf.put_u8(mini(hook.t, 255))
	buf.put_8(hook_side)
	buf.put_16(clampi(roundi(hook_ang * 1000.0), -32000, 32000))
	buf.put_u8(clampi(roundi(hook_len / 2.0), 0, 255))
	buf.put_u8(lights)
	buf.put_u8(mini(lights_t, 255))
	buf.put_u8(figure if figure >= 0 else 255)
	buf.put_u8(surge)
	buf.put_u8(mini(surge_t, 255))
	buf.put_u8(beds.size())
	for b in beds:
		buf.put_u8(b[0] if b[0] >= 0 else 255)
		buf.put_u8(mini(b[1], 255))

# The page's side of write (client/net.gd): {"n": the tick byte, "f": [[phase, ticks,
# surge], ...], "p": [[phase, ticks], ...], "hook": {phase, t, side, ang, len},
# "lights": [state, ticks], "fig": spot (-1 none), "surge": [state, ticks],
# "beds": [[seat (-1 none), ticks], ...]}.
static func read(buf: StreamPeerBuffer) -> Dictionary:
	var d := {"n": buf.get_u8()}
	var fl: Array = []
	for i in buf.get_u8():
		var ph := buf.get_u8()
		fl.append([ph & 0x7F, buf.get_u8(), (ph & 0x80) != 0])
	d["f"] = fl
	var pl: Array = []
	for i in buf.get_u8():
		pl.append([buf.get_u8(), buf.get_u8()])
	d["p"] = pl
	d["hook"] = {"phase": buf.get_u8(), "t": buf.get_u8(), "side": buf.get_8(), "ang": buf.get_16() / 1000.0,
		"len": buf.get_u8() * 2.0}
	d["lights"] = [buf.get_u8(), buf.get_u8()]
	var fig := buf.get_u8()
	d["fig"] = -1 if fig == 255 else fig
	d["surge"] = [buf.get_u8(), buf.get_u8()]
	var bl: Array = []
	for i in buf.get_u8():
		var seat := buf.get_u8()
		bl.append([-1 if seat == 255 else seat, buf.get_u8()])
	d["beds"] = bl
	return d

# ------------------------------------------------------------------ the bots
# Which way a bot should step to get out of a hazard about to go off (1 right, -1
# left, 0 none): a furnace's fire (warning or blasting; EASY bots notice only the last
# second of a warning), a pipe's steam (bulging or venting), the swinging hook. Out of
# a sideways jet it runs on along the jet (its other end is the wall the jet comes
# from); out of an upward one, to the nearer side.
func flee(sim, f) -> int:
	var body := Rect2(f.x, f.y, 36, 63)
	var cx: float = f.x + 18.0
	for i in furnaces.size():
		var h: Hazard = furnaces[i]
		var left := FURNACE_BLAST
		if h.phase == WARN:
			left = (SURGE_WARN_T if h.surge else FURNACE_WARN) - h.t
		var hot: bool = h.phase == BLAST or (h.phase == WARN and (f.level != 1 or left <= 60))
		if not hot:
			continue
		var r: Rect2 = FURNACES[i][2]
		if _hits(r.grow(FLEE_MARGIN if not h.surge else FLEE_MARGIN + 10), body):
			return _away(FURNACES[i], cx)
		if FURNACES[i][1] == 3 or left > 60:
			continue
		# a sideways fire over a walkway: in its last second (and while it burns) keep out
		# of the space over it where a drop would fall into the fire (open air down to it),
		# and from under it, where a jump through the walkway would rise into it
		if cx < r.position.x or cx > r.end.x:
			continue
		var dir := -1 if cx < r.get_center().x else 1
		var feet: float = f.y + 63.0
		if feet <= r.position.y and feet > r.position.y - COLUMN_UP:
			if _open_down(sim, cx, feet, r.position.y):
				return dir
		elif f.y >= r.end.y and f.y < r.end.y + COLUMN_DOWN:
			# under it: step out from under it, never into a wall (a wall makes the brain jump)
			if sim.box_hits_solid(f.x + dir * 24, f.y, 36, 63):
				dir = -dir
				if sim.box_hits_solid(f.x + dir * 24, f.y, 36, 63):
					return 0
			return dir
	if demo and f.id >= 5:
		var feet: int = f.y + 63
		if feet == FLOOR_Y:
			for b in BEDS:
				var mx: float = (b[0] + b[1]) / 2.0
				if absf(cx - mx) < 220.0 and absf(cx - mx) > 8.0:
					return 1 if mx > cx else -1
		if feet == 540:
			# through a locker: in on one side, out of the other, on until well clear of it
			var edge := minf(cx, W - cx)
			if edge > 300.0:
				demo_dir.erase(f.id)
			else:
				if not demo_dir.has(f.id):
					demo_dir[f.id] = -1 if cx < 960.0 else 1
				return demo_dir[f.id]
		if feet == 360 and cx < 480.0:      # off the upper-left catwalk's end, down to the left locker
			return -1
		if feet == 390 and cx > 1440.0:     # and the upper-right one's, to the right locker
			return 1
	for i in pipes.size():
		var h: Hazard = pipes[i]
		if demo:
			break
		if (h.phase == WARN and h.t > 20) or h.phase == BLAST:
			if _hits(PIPES[i][2].grow(14), body):
				var way := _away(PIPES[i], cx)
				if _fire_near(Rect2(f.x + way * 40, f.y, 36, 63)):
					return 0     # never out of the steam into a fire: a knock is better than a burn
				return way
	if (hook.phase == WARN and hook.t > HOOK_WARN - 40) or hook.phase == BLAST:
		var dx: float = cx - HOOK_PIVOT.x
		var feet: float = f.y + 63.0
		if absf(dx) < HOOK_REACH_X and feet > HOOK_PIVOT.y + HOOK_LONG * 0.55 and f.y < HOOK_PIVOT.y + HOOK_LONG + HOOK_R:
			return 1 if dx >= 0.0 else -1
	return 0

# A furnace that warns or burns has this body in (or near) its fire.
func _fire_near(body: Rect2) -> bool:
	for i in furnaces.size():
		var h: Hazard = furnaces[i]
		if (h.phase == WARN or h.phase == BLAST) and _hits(FURNACES[i][2].grow(FLEE_MARGIN), body):
			return true
	return false

# No block straight down from y0 to y1 at x (a ledge counts as open: a bot may drop through it).
func _open_down(sim, x: float, y0: float, y1: float) -> bool:
	var col := floori(x / 30.0)
	for cy in range(floori(y0 / 30.0), floori(y1 / 30.0)):
		if sim.level.cell(col, cy) == 1:
			return false
	return true

static func _away(spec: Array, cx: float) -> int:
	var d: int = spec[1]
	if d == 0:
		return 1
	if d == 2:
		return -1
	var r: Rect2 = spec[2]
	return -1 if cx < r.get_center().x else 1

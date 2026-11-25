# SANTA'S WORKSHOP's toy train (theme "workshop", sim/level.gd layout 8): the arena's one
# hazard. A whistle and a blinking signal at one tunnel mouth (WARN_T, 2 s), then the
# train comes out of that tunnel, crosses the bottom floor (RUN_T, 2.25 s) and is gone into
# the other tunnel. The first whistle 5 to 7 s after FIGHT, then a train every 12 to
# 18 s, from a random side.
# The sim makes one for an arena whose theme is "workshop" (sim.gd set_arena), calls
# reset() each round and step() each tick of play; the snapshot carries the state (write,
# read) for the page's look (client/workshop_view.gd); the bots ask flee() what to do.
# The rules, all fair:
#   - it warns first, and it is low: its box is TRAIN_H (46 px) high on the floor. A jump
#     held a moment clears it; anyone standing on a ledge is safe (the lowest ledges are
#     90 px up); a drop through a trapdoor gets you out too;
#   - whoever it touches is knocked out (cause 13, "a toy train") and thrown along. Like
#     a furnace's fire it does not care about a dodge or a SHIELD (a SHIELD takes arrows);
#   - one train hits a fighter once. So a costume (f.mask) is knocked down by it and gets
#     up again; only a second hit ends it (sim.gd _kill);
#   - the round's winner is safe (sim.is_safe: _kill says E_PHEW), and once the round is
#     decided it hurts nobody else and no new train starts;
#   - its roof carries nobody: it is no platform, and it moves no living fighter but the
#     one it knocks out. It bumps a fallen body along and knocks arrows about;
#   - no spawn spot is on the track, and with fewer than two fighters (the route runs, a
#     probe's lone fighter) it never comes;
#   - the page's own copy of your fighter (sim.predicting) never runs it: sim.gd calls
#     step() only on the server.
# Randomness comes from sim.rng: the server runs the rules, the page only draws them.
# The page draws the train where it is on YOUR tick, like the arrows (client/present.gd):
# on_tick() rolls a state on to a later tick. A train drawn 10 ticks in the past would be
# 160 px behind the one that hits you.
extends RefCounted

const P = preload("res://sim/proto.gd")

const KIND := 2                  # the snapshot's hazards byte: 1 THE BOILER ROOM's state follows, 2 this one's
const W := 1920
const CELL := 30
# the phases (boiler.gd's numbers: resting, warning, going off)
const IDLE := 0
const WARN := 1                  # the whistle: the signal at the tunnel mouth blinks
const RUN := 2                   # the train crosses the floor

const FLOOR_Y := 1020            # the top of the bottom floor: the track
const TRAIN_H := 46              # the deadly box's height (the funnel and the presents stand taller: look only)
const TRAIN_LEN := 240           # the engine (92) and two wagons (68 each), 6 px between them
const SPEED := 16.0              # px a tick: an arrow's speed, more than twice a fighter's run
const WARN_T := 120              # 2 s of whistle and blinking (a slow player in the train's own tunnel still gets out)
const RUN_T := 135               # ticks from the front at one edge to the tail past the other: (W + TRAIN_LEN) / SPEED
const FIRST := [300, 420]        # the first whistle 5 to 7 s after FIGHT (the train out of its tunnel 7 to 9 s)
const EVERY := [720, 1080]       # then a train every 12 to 18 s (whistle to whistle)
const HIT_MARGIN := 3            # a body this far inside the box's edge is hit (boiler.gd BURN_MARGIN)
const BONK_VX := 9.0             # the one it knocks out flies along with it,
const BONK_VY := -9.0            # and up
const BODY_VX := 8.0             # a fallen body on the track is bumped along
const BODY_VY := -7.0
# the bots (flee)
const SAFE_Y := FLOOR_Y - TRAIN_H - 8   # feet at or above this are over the train
const PERCH_ROWS := [31, 30]     # a ledge on one of these rows is the low ledge to jump up to (90 and 120 px up)
const LOW_Y := FLOOR_Y - 130     # a bot standing between this and SAFE_Y is on a low ledge: it waits there while the train is near
const JUMP_AT := 10              # with no ledge in reach it jumps this many ticks before the train reaches it
const NEAR_TICKS := 45           # "near": the train reaches it within this many ticks
const WALK := 6.75               # a fighter's run (sim.gd RUN_MAX), for "is there time to walk there"
# A bot minds the train once it is this many ticks from reaching it, by its level (OLD,
# EASY, NORMAL, HARD): before that it plays on, whistle or not. An EASY bot leaves it
# late and is caught now and then; a HARD one has time to spare.
const REACT := [0, 26, 36, 60]
# what flee() answers (the brain: sim/brain.gd _play). 1 and -1 are boiler.gd's too.
const GO_RIGHT := 1
const GO_LEFT := -1
const JUMP_RIGHT := 2            # that way, with jump held
const JUMP_LEFT := -2
const JUMP_UP := 3               # jump on the spot (hold it)
const STAY := 4                  # stand still

# Test knobs (the server's flags, for the pictures; the page never has them). --train-demo:
# the first whistle 2 s after FIGHT and a train every 7 to 8 s, and the server prints a
# timeline ([TRAIN] lines). --train-hold: each train stops in the middle of the floor for
# 20 s (it still knocks out whoever touches it), then rolls on.
static var demo: bool = OS.get_cmdline_user_args().has("--train-demo")
static var hold: bool = OS.get_cmdline_user_args().has("--train-hold")
const DEMO_FIRST := [120, 150]
const DEMO_EVERY := [420, 480]
const HOLD_T := 1200

var level
var tick: int = 0                # ticks of play this round
var now: int = 0                 # the sim's tick at the last step (the page rolls the train on from it)
var phase: int = IDLE
var t: int = 0                   # ticks in this phase
var wait: int = -1               # ticks until the next whistle (while idle; -1: picked on the round's first tick)
var dir: int = 1                 # the train runs right (1) or left (-1)
var held: int = 0                # the demo: ticks the train still stands in the middle
var held_done: bool = false
var hit := {}                    # seat -> true: this train already hit it
var bumped := {}                 # seat -> ticks before this train bumps its body again
var knocked := {}                # arrow id -> true: this train already knocked it
var perch := PackedByteArray()   # each column: 1 when a jump straight up from the floor lands on a low ledge
var first: Array = FIRST
var every: Array = EVERY

func _init(lv) -> void:
	level = lv
	if demo:
		first = DEMO_FIRST
		every = DEMO_EVERY
	_find_perches()
	reset()

# A new round: no train; the first whistle's time is picked on the first tick (sim.rng).
func reset() -> void:
	tick = 0
	phase = IDLE
	t = 0
	wait = -1
	dir = 1
	held = 0
	held_done = false
	hit.clear()
	bumped.clear()
	knocked.clear()

# One tick of play (not while the round's first moment holds everyone still). With fewer
# than two fighters it is no round: no train.
func step(sim) -> void:
	now = sim.tick
	if sim.fighters.size() < 2:
		return
	tick += 1
	if tick == 1:
		wait = sim.rng.randi_range(first[0], first[1])
	var live: bool = not sim.decided()     # (TEAMS: decided when one team is left)
	if phase == IDLE:
		wait -= 1
		if wait <= 0 and live:
			dir = 1 if sim.rng.randf() < 0.5 else -1
			_to(WARN)
			sim._event(P.E_TRAIN_WARN, mouth_x(dir), FLOOR_Y - 45, 1 if dir > 0 else 0, 0)
	elif phase == WARN:
		t += 1
		if not live:
			_to(IDLE)                      # the round is decided: the whistle dies down, no train
			wait = every[0]
		elif t >= WARN_T:
			_to(RUN)
			hit.clear()
			bumped.clear()
			knocked.clear()
			held_done = false
			sim._event(P.E_TRAIN, mouth_x(dir), FLOOR_Y - 45, 1 if dir > 0 else 0, 0)
	elif phase == RUN:
		if held > 0:
			held -= 1                      # (the demo: it stands; t stands with it)
		else:
			t += 1
			if hold and not held_done and absf(box_at(t, dir).get_center().x - W * 0.5) < SPEED:
				held = HOLD_T
				held_done = true
		_roll(sim, live)
		if t >= RUN_T:
			_to(IDLE)
			wait = sim.rng.randi_range(every[0], every[1]) - RUN_T - WARN_T

func _to(p: int) -> void:
	phase = p
	t = 0
	if demo:
		print("[TRAIN] %.2f %s%s" % [Time.get_unix_time_from_system(), ["rest", "whistle", "go"][p],
			"" if p == IDLE else (" to the right" if dir > 0 else " to the left")])

# The tunnel mouth a train heading d comes out of: the arena's left edge, or its right one.
static func mouth_x(d: int) -> int:
	return 0 if d > 0 else W

# Where the train's front is tt ticks into its run: it starts at its mouth's edge.
static func front_at(tt: float, d: int) -> float:
	return tt * SPEED if d > 0 else W - tt * SPEED

# The train's deadly box tt ticks into its run, cut to the arena (the rest is in a tunnel).
static func box_at(tt: float, d: int) -> Rect2:
	var front := front_at(tt, d)
	var x0 := maxf(0.0, front - TRAIN_LEN if d > 0 else front)
	var x1 := minf(float(W), front if d > 0 else front + TRAIN_LEN)
	return Rect2(x0, FLOOR_Y - TRAIN_H, maxf(0.0, x1 - x0), TRAIN_H)

func box() -> Rect2:
	return box_at(t, dir) if phase == RUN else Rect2()

# A body (its top left corner) is in the box. The arena wraps: a body over the right edge
# has its other part at the left one.
static func _touches(r: Rect2, x: float, y: float) -> bool:
	if r.size.x <= 0.0:
		return false
	var m := float(HIT_MARGIN)
	for ox in [0.0, -float(W)]:
		var bx: float = x + ox + m
		if bx < r.end.x and r.position.x < bx + 36.0 - m * 2.0 and y + m < r.end.y and r.position.y < y + 63.0 - m:
			return true
	return false

# The train rolls on: it knocks out every living fighter its box touches (once a train),
# bumps the fallen along, and knocks arrows about.
func _roll(sim, live: bool) -> void:
	var r := box()
	if r.size.x <= 0.0:
		return
	for k in bumped.keys():
		bumped[k] -= 1
		if bumped[k] <= 0:
			bumped.erase(k)
	for f in sim.fighters:
		if not _touches(r, f.x, f.y):
			continue
		if f.state == P.F_DEAD:
			if not f.pinned and not bumped.has(f.id):      # a fallen body: bumped along, a little hop
				bumped[f.id] = 20
				f.vx = dir * BODY_VX
				f.vy = BODY_VY
			continue
		if hit.has(f.id) or (not live and not sim.is_safe(f)):
			continue
		hit[f.id] = true
		var was_down: bool = f.down_t > 0
		sim._kill(f, 255, 13)
		# out, or a costume knocked down: thrown along. (The round's winner is safe: _kill let
		# it be and said E_PHEW; nothing about it changes.)
		if f.state == P.F_DEAD or (f.down_t > 0 and not was_down):
			f.vx = dir * BONK_VX
			f.vy = BONK_VY
			if f.state == P.F_DEAD:
				bumped[f.id] = 20
			sim._event(P.E_TRAIN_HIT, f.x + 18, f.y + 31, f.id, 1 if dir > 0 else 0)
	for a in sim.arrows:
		if a.dead or a.state == P.S_BODY or a.pins >= 0 or a.fuse >= 0 or knocked.has(a.id):
			continue
		if a.x < r.position.x or a.x >= r.end.x or a.y < r.position.y - 6.0 or a.y > r.end.y + 8.0:
			continue
		knocked[a.id] = true
		if a.state == P.S_STUCK:
			a.state = P.S_FALL             # an arrow stuck in the track: scooped up and tossed ahead
			a.y = minf(a.y, r.position.y)
			a.vx = dir * (SPEED + 3.0 + sim.rng.randf_range(0.0, 3.0))
			a.vy = -9.0 - sim.rng.randf_range(0.0, 3.0)
		else:
			a.state = P.S_FALL             # one in the air: it bounces off
			a.vx = -a.vx * 0.3 + dir * SPEED * 0.6
			a.vy = -6.0
			sim._event(P.E_TINK, int(a.x), int(a.y), 0, 0)

# ------------------------------------------------------------------ the snapshot
# The state for the page (sim.gd write_snapshot, after its hazards byte 2):
#   u8 the round's tick (low byte), u8 the phase (+ 0x80 it runs right, + 0x40 the demo
#   holds it still), u8 ticks in the phase, u16 the sim's tick (low 16 bits).
func write(buf: StreamPeerBuffer) -> void:
	buf.put_u8(tick & 255)
	buf.put_u8(phase | (0x80 if dir > 0 else 0) | (0x40 if held > 0 else 0))
	buf.put_u8(mini(t, 255))
	buf.put_u16(now & 0xFFFF)

# The page's side of write (client/net.gd): {"k": KIND, "n": the tick byte, "phase", "t"
# (ticks in the phase, a float: on_tick and the page run it on), "dir" (1 right, -1 left),
# "held", "at": the sim's tick it is for}.
static func read(buf: StreamPeerBuffer) -> Dictionary:
	var n := buf.get_u8()
	var ph := buf.get_u8()
	var tt := buf.get_u8()
	return {"k": KIND, "n": n, "phase": ph & 0x3F, "t": float(tt), "dir": 1 if (ph & 0x80) != 0 else -1,
		"held": (ph & 0x40) != 0, "at": buf.get_u16()}

# The same state rolled on to sim tick `to` (its low bits will do): the whistle runs out
# and the train starts, the train rolls and is gone. At most AHEAD_MAX ticks on, and
# never back. The page calls it with your own predicted tick (client/game_client.gd).
const AHEAD_MAX := 30

static func on_tick(h: Dictionary, to: int) -> Dictionary:
	if int(h.get("k", 0)) != KIND or int(h["phase"]) == IDLE or bool(h["held"]):
		return h
	var n: int = ((to & 0xFFFF) - int(h["at"]) + 0x18000) % 0x10000 - 0x8000
	n = clampi(n, 0, AHEAD_MAX)
	if n == 0:
		return h
	var d := h.duplicate()
	d["at"] = (int(h["at"]) + n) & 0xFFFF
	var tt: float = float(h["t"]) + n
	if int(h["phase"]) == WARN and tt >= WARN_T:
		d["phase"] = RUN
		tt -= WARN_T
	if int(d["phase"]) == RUN and tt >= RUN_T:
		d["phase"] = IDLE
		tt = 0.0
	d["t"] = tt
	return d

# ------------------------------------------------------------------ the bots
# Which columns have a low ledge to jump up to: a ledge on row 31 or 30 over the floor,
# nothing solid on the way up, and room for a body on it.
func _find_perches() -> void:
	perch.resize(level.COLS)
	perch.fill(0)
	var floor_row: int = FLOOR_Y / CELL
	for cx in level.COLS:
		for row in PERCH_ROWS:
			var ok: bool = level.cell(cx, row) == level.LEDGE
			for cy in range(row - 3, floor_row):
				if level.cell(cx, cy) == level.SOLID:
					ok = false
			if ok:
				perch[cx] = 1
				break

# A body with its left edge at x stands under a low ledge with all its width.
func _under_perch(x: float) -> bool:
	for cx in range(floori(x / CELL), floori((x + 35.0) / CELL) + 1):
		if perch[posmod(cx, level.COLS)] == 0:
			return false
	return true

# Ticks until the train's front reaches a body at x (0 or less: it is there), and has its
# tail passed it? During the whistle the whistle's rest counts too.
func _eta(x: float) -> Array:
	var tt: float = t if phase == RUN else 0.0
	var front := front_at(tt, dir)
	var ahead: float = (x - front) if dir > 0 else (front - (x + 36.0))
	var gone: bool = phase == RUN and ahead < -(TRAIN_LEN + 36.0)
	var ticks: float = ahead / SPEED + (float(WARN_T - t) if phase == WARN else 0.0)
	if phase == RUN and held > 0:
		ticks = 9999.0 if ahead > 0.0 else 0.0
	return [ticks, gone]

# What a bot should do about the train (0: nothing; the answers are listed at the top).
# On the track (its feet lower than the train's roof) with a whistle blowing or a train
# coming: a low ledge right over it: jump up; else walk to the nearest one it can reach
# in time (it jumps once under it); none in time: jump over the train as it comes. On a
# low ledge with the train about to pass under: stay there. It minds the train only once
# it is near (REACT, by the bot's level).
func flee(sim, f) -> int:
	if phase == IDLE:
		return 0
	var e := _eta(float(f.x))
	if e[1]:
		return 0                           # it has passed
	var ticks: float = e[0]
	if ticks > REACT[clampi(f.level, 0, 3)]:
		return 0                           # not yet: it plays on until the train is this near
	var feet: int = f.y + 63
	if feet > FLOOR_Y + 4:
		return 0                           # falling through a trapdoor: under the track already
	if not f.on_ground and f.vy < 0.0 and feet > LOW_Y and _under_perch(float(f.x)):
		return JUMP_UP                     # on its way up to a low ledge: the jump stays held
	if feet <= SAFE_Y:
		# over the train: on a low ledge (or coming down on one) it waits while the train
		# passes under: a step off now lands in it
		if feet > LOW_Y - 40 and ticks < NEAR_TICKS:
			return STAY
		return 0
	if _under_perch(float(f.x)):
		return JUMP_UP
	# the nearest column under a low ledge, each way; is there time to walk there and get up?
	var best := 0
	var best_d := 99999.0
	for way in [-1, 1]:
		for step in range(1, 16):
			var x: float = f.x + way * step * 15.0
			if sim.box_hits_solid(int(x), f.y, 36, 63):
				break
			if _under_perch(fposmod(x, float(W))):
				var d: float = step * 15.0
				var there: Array = _eta(fposmod(x, float(W)))
				if (there[1] or d / WALK + 8.0 < float(there[0])) and d < best_d:   # (the train has passed there, or will not be there yet)
					best = way
					best_d = d
				break
	if ticks <= JUMP_AT:
		return JUMP_UP if best == 0 else (JUMP_RIGHT if best > 0 else JUMP_LEFT)   # no time left: over it
	if best != 0:
		return best
	return STAY if ticks < 60.0 else 0     # nowhere to go: wait for it and jump

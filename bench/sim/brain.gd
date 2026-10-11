# ==============================================================================
# The bot brain (G6, server bots): plays a seat with no person on it. It picks
# buttons each tick and presses them through sim.apply_input(), the same path a
# person's buttons take, so its jumps, drops, dodges and shots follow the
# person's rules (a shot gets the aim help). No scene nodes: the server, the
# probes and the benchmark page run it inside the sim (sim.gd calls think()
# for every bot fighter at the start of each tick; the client never does).
# Its memory between ticks is a Mind on the fighter (f.mind).
# Levels (f.level): OLD is p3.1's brain (kept as the probes' stand-in for a kid
# and as the baseline). EASY, NORMAL and HARD shoot only along a path where a
# copy of the arrow (fly(): the sim's own arrow numbers) reaches the target
# before a wall; they draw the bow a moment, then let go (the aim help applies).
# By level: the aim's error, how far they lead a runner, the draw, the pause.
# They fly each arrow coming at them forward, and with the level's chance (rolled
# once an arrow) dodge into it just before it lands: a dodge catches it.
# TowerFall has no archer bots; its quest skeleton archers draw for 10 frames,
# aim in 22.5 degree steps and are one step off half the time, and fail a dodge
# 1 time in 10 to 1 in 5, more after each dodge (numbers only).
# ==============================================================================
extends RefCounted

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")

const OLD := 0
const EASY := 1
const NORMAL := 2
const HARD := 3
const NAMES := ["OLD", "EASY", "NORMAL", "HARD"]
# By level (index: OLD, EASY, NORMAL, HARD; OLD uses none of them):
const AIM_ERR := [0.0, 0.18, 0.07, 0.025]       # the aim's error: a normal spread, radians
const LEAD := [0.0, 0.0, 0.5, 1.0]              # how far it aims ahead of a moving target (1: all the way)
const DRAW := [[1, 1], [16, 24], [10, 16], [8, 12]]       # ticks the bow is drawn before the shot
const PAUSE := [[20, 50], [70, 130], [40, 80], [25, 50]]  # ticks after a shot before the next one
const LOOK_EVERY := 6           # a shot is looked for every 6 ticks
const SHOT_RANGE := 900.0       # no shot at a target farther than this
const AIM_HOLD := 30            # drawn this long past the draw with no path, on the ground: lower the bow with a jump
const AIM_HOLD_MAX := 120       # and in the air, at most this long: then the shot goes anyway
const SHOT_OFFSETS := [0.0, -0.07, 0.07, -0.14, 0.14, -0.21, 0.21]   # radians tried around the straight line past 420 px
const CATCH := [0.0, 0.2, 0.5, 0.8]   # the chance it dodges into an arrow coming at it (rolled once an arrow)
const SEE_T := 12               # an arrow that will reach it within this many ticks is seen (about 216 px)
const DODGE_AT := 8             # from this many ticks away it looks for a dodge that meets the arrow
const SEE_R2 := 90000.0         # arrows farther than 300 px are not looked at
# the 8 ways, from right going clockwise (y grows down): the dodge into an arrow
const WAYS8 := [P.B_RIGHT, P.B_DOWN | P.B_RIGHT, P.B_DOWN, P.B_DOWN | P.B_LEFT, P.B_LEFT, P.B_UP | P.B_LEFT,
	P.B_UP, P.B_UP | P.B_RIGHT]

const W := 1920
const H := 1080
# The dodge's 7 ways as buttons (on the ground, down and a side is a slide)
const DODGE_WAYS := [P.B_RIGHT, P.B_LEFT, P.B_UP, P.B_UP | P.B_RIGHT, P.B_UP | P.B_LEFT,
	P.B_DOWN | P.B_RIGHT, P.B_DOWN | P.B_LEFT]

class Mind:
	var move := 0               # -1 left, 0, 1 right: held
	var jump := 0               # ticks left to hold jump
	var jump_wait := false      # a new jump while jump is still held: let go for a tick first
	var down := 0               # ticks left to hold down
	var draw := 0               # ticks left to hold shoot (the bow drawn); the tick after, it lets go: the shot
	var aim := 0                # the aim in 0.1 degree steps (proto's input aim)
	var prev := 0               # the buttons pressed last tick
	var target := -1            # the seat it aims at (the bot probe reads it)
	var drawing := false        # shoot held, the bow drawn (the new levels)
	var draw_t := 0             # ticks drawn so far
	var draw_need := 0          # ticks to draw before the shot
	var look_t := 0             # ticks until it looks for a shot again
	var lower := false          # the bow is being lowered with a jump (no path): shoot comes up next tick, no shot
	var seen := {}              # an arrow's id -> true: dodge into it when it is close; false: let it come
	var only_dodge := false     # a test knob (the bot probe's catch test): stand, hold fire, only dodge

# One tick of a bot seat: the buttons for this tick, pressed like a person's.
static func think(sim, f) -> void:
	if f.mind == null:
		f.mind = Mind.new()
	var m: Mind = f.mind
	var b := 0
	if f.state == P.F_NORMAL or f.state == P.F_DODGE:
		b = _old(sim, f, m) if f.level == OLD else _play(sim, f, m)
	elif m.drawing:
		m.drawing = false   # knocked out of it: the bow is down
	m.prev = b
	sim.apply_input(f, b, m.aim)

# A jump: press jump and hold it this many ticks (a longer hold, a higher jump).
static func _jump(m: Mind, hold: int) -> void:
	if m.prev & P.B_JUMP:
		m.jump_wait = true
	m.jump = maxi(m.jump, hold)

# The held buttons for this tick, from the mind.
static func _buttons(m: Mind) -> int:
	var b := P.B_RIGHT if m.move > 0 else (P.B_LEFT if m.move < 0 else 0)
	if m.jump > 0:
		if m.jump_wait:
			m.jump_wait = false
		else:
			b |= P.B_JUMP
			m.jump -= 1
	if m.down > 0:
		b |= P.B_DOWN
		m.down -= 1
	if m.draw > 0:
		b |= P.B_SHOOT
		m.draw -= 1
	elif m.drawing:
		b |= P.B_SHOOT
	return b

static func aim_steps(ang: float) -> int:
	return posmod(roundi(ang / TAU * 3600.0), 3600)

# ------------------------------------------------------------------ OLD (p3.1's brain)
# It walks toward the nearest enemy (or an arrow when its quiver is empty), jumps
# at walls and when the enemy is above, drops when it is below, leans into walls
# when it falls, dodges a random way now and then (more when an arrow comes), and
# shoots straight at the enemy now and then, wall or no wall.
static func _old(sim, f, m: Mind) -> int:
	if f.wait_t > 0:   # the round's first moment: stand still, people move first
		f.wait_t -= 1
		m.move = 0
		m.jump = 0
		return 0
	var rng: RandomNumberGenerator = sim.rng
	if f.shoot_cd > 0:
		f.shoot_cd -= 1
	var tgt = nearest_enemy(sim, f)
	m.target = tgt.id if tgt != null else -1
	_old_move(sim, f, m, tgt)
	var dodge := _old_dodge(sim, f)
	if dodge != 0:
		return dodge
	if tgt != null and f.arrows > 0 and f.shoot_cd == 0 and f.state != P.F_DODGE and m.draw == 0 and rng.randf() < 0.05:
		var ax := SimScript.wrap_d(f.x, tgt.x, W)
		var ay := SimScript.wrap_d(f.y, tgt.y, H) - 20.0
		m.aim = aim_steps(atan2(ay, ax) + rng.randf_range(-0.12, 0.12))
		m.draw = 1
		f.shoot_cd = rng.randi_range(20, 50)
	return _buttons(m)

# OLD's walking: toward the target (or an arrow with an empty quiver), jumps at
# walls and when the target is above, drops when it is below, the middle when the
# purple walls come, leans into walls when falling.
static func _old_move(sim, f, m: Mind, tgt) -> void:
	var rng: RandomNumberGenerator = sim.rng
	f.think_t -= 1
	if f.think_t <= 0:
		f.think_t = rng.randi_range(10, 36)
		if tgt != null and rng.randf() < 0.75:
			var dx := SimScript.wrap_d(f.x, tgt.x, W)
			var dy := SimScript.wrap_d(f.y, tgt.y, H)
			if f.arrows == 0:
				var st = nearest_loose_arrow(sim, f)
				if st != null:
					dx = SimScript.wrap_d(f.x + SimScript.HALF_W, st.x, W)
					dy = SimScript.wrap_d(f.y + SimScript.BODY_H, st.y, H)
			m.move = (1 if dx > 0.0 else -1) if absf(dx) > 50.0 else rng.randi_range(-1, 1)
			if dy < -80.0 and rng.randf() < 0.7:
				_jump(m, rng.randi_range(6, 16))
			if dy > 100.0 and rng.randf() < 0.5:
				m.down = 12
				_jump(m, 1)
		else:
			m.move = rng.randi_range(-1, 1)
			if rng.randf() < 0.35:
				_jump(m, 14)
	if sim.walls_share > 0.0:   # the purple walls are coming: head for the middle
		var reach: int = sim.walls_width() + SimScript.WALLS_KEEP_AWAY
		if f.x + SimScript.HALF_W < reach:
			m.move = 1
		elif f.x + SimScript.HALF_W > W - reach:
			m.move = -1
	if m.move != 0 and f.on_ground and sim.box_hits_solid(f.x + m.move * 4, f.y, SimScript.BODY_W, SimScript.BODY_H):
		_jump(m, 16)
	if f.wall != 0 and rng.randf() < 0.1:
		_jump(m, 12)
	# falling next to a wall: lean into it now and then (wall slides, ledge grabs)
	if not f.on_ground and f.vy > 2.0 and f.state == P.F_NORMAL and rng.randf() < 0.3:
		for dir in [-1, 1]:
			if sim.box_hits_solid(f.x + dir * 30, f.y, SimScript.BODY_W, SimScript.BODY_H):
				m.move = dir
				break

# OLD's dodge: a random way, often when an arrow comes near, now and then for no
# reason. The buttons for it, or 0.
static func _old_dodge(sim, f) -> int:
	var rng: RandomNumberGenerator = sim.rng
	if f.state != P.F_DODGE and f.dodge_cd == 0:
		if (rng.randf() < 0.4 and arrow_incoming(sim, f)) or rng.randf() < 0.004:
			return DODGE_WAYS[rng.randi() % DODGE_WAYS.size()] | P.B_DODGE
	return 0

# ------------------------------------------------------------------ EASY, NORMAL, HARD
# OLD's walking for now (G6 step 5 replaces it); the dodge (_dodge) and the shot are new:
# every LOOK_EVERY ticks it looks for a path to one of its 3 nearest enemies; with
# one it draws the bow (standing still on the ground, as a person does), aims at
# the target while it draws, and lets go when the draw is done and the path is
# still there (aimed with the level's error; the aim help applies).
static func _play(sim, f, m: Mind) -> int:
	if f.wait_t > 0:   # the round's first moment: stand still, people move first
		f.wait_t -= 1
		m.move = 0
		m.jump = 0
		m.drawing = false
		return 0
	if f.shoot_cd > 0:
		f.shoot_cd -= 1
	if m.only_dodge:
		return _dodge(sim, f, m)
	var tgt = nearest_enemy(sim, f)
	_old_move(sim, f, m, tgt)
	var dodge := _dodge(sim, f, m)
	if dodge != 0:
		if m.drawing:       # shoot stays down on the dodge tick: the dodge lowers the bow, no shot
			m.drawing = false
			return dodge | P.B_SHOOT
		return dodge
	if m.lower:             # the jump last tick lowered the bow: shoot comes up, no shot
		m.lower = false
		m.drawing = false
	elif m.drawing and m.draw_t > 1 and not f.aiming:
		m.drawing = false   # the bow never came up (a jump or a dodge took it): try again later
	elif m.drawing:
		m.jump = 0          # a jump would lower the bow
		m.jump_wait = false
		_draw(sim, f, m)
		if m.lower:
			m.down = 0      # down + jump on a ledge would drop through it, and the bow would stay up
			_jump(m, 4)
	elif f.arrows > 0 and f.shoot_cd == 0 and f.state == P.F_NORMAL and not f.aiming:
		m.look_t -= 1
		if m.look_t <= 0:
			m.look_t = LOOK_EVERY
			var pick := _pick_shot(sim, f)
			if not pick.is_empty():
				m.target = pick[0].id
				m.aim = aim_steps(pick[1])
				m.drawing = true
				m.draw_t = 0
				var d: Array = DRAW[f.level]
				m.draw_need = sim.rng.randi_range(d[0], d[1])
				m.jump = 0
				m.jump_wait = false
	return _buttons(m)

# The dodge into an arrow: each enemy arrow coming its way within 300 px is flown
# on SEE_T ticks against the bot's body (moving as it moves now); one that will
# land gets the level's roll once. With a yes, from DODGE_AT ticks away the bot
# tries its 8 dodge ways (a copy of the dodge: DODGE_SPEED slowing by DODGE_DECAY
# a tick, a slide on the ground) against a copy of the arrow and dodges the way
# that meets it soonest: a catch; with no way yet, it waits, and on the last tick
# dodges toward the arrow. With a no it lets it come. The buttons, or 0.
static func _dodge(sim, f, m: Mind) -> int:
	if f.state != P.F_NORMAL or f.dodge_cd > 0:
		return 0
	var cx := float(f.x + SimScript.HALF_W)
	var cy := float(f.y + SimScript.MID_Y)
	var best = null
	var best_k := 999
	for a in sim.arrows:
		if a.dead or a.state != P.S_FLY or (a.owner == f.id and a.t < SimScript.ARROW_NO_SELF):
			continue
		var dx := SimScript.wrap_d(a.x, cx, W)
		var dy := SimScript.wrap_d(a.y, cy, H)
		if dx * dx + dy * dy > SEE_R2 or dx * a.vx + dy * a.vy <= 0.0:
			continue
		var r := fly(sim, a.x, a.y, a.vx, a.vy, SEE_T, [float(f.x), float(f.y), f.vx, 0.0 if f.on_ground else f.vy], a.t)
		if r[0] != FLY_HIT:
			continue
		if not m.seen.has(a.id):
			if m.seen.size() > 12:
				m.seen.clear()
			m.seen[a.id] = sim.rng.randf() < CATCH[f.level]
		if m.seen[a.id] and r[1] <= DODGE_AT and r[1] < best_k:
			best = a
			best_k = r[1]
	if best == null:
		return 0
	var way := -1
	var soonest := 999
	for w in 8:
		var d := Vector2.from_angle(w * PI / 4.0)
		var speed := SimScript.DODGE_SPEED
		if f.on_ground and d.y > 0.1:   # a dodge down on the ground: a faster slide along it
			d = Vector2(signf(d.x) if absf(d.x) > 0.1 else float(f.facing), 0.0)
			speed *= SimScript.DODGE_SLIDE_MULT
		var r := fly(sim, best.x, best.y, best.vx, best.vy, best_k + 4,
			[float(f.x), float(f.y), d.x * speed, d.y * speed, SimScript.DODGE_DECAY], best.t)
		if r[0] == FLY_HIT and r[1] < soonest:
			soonest = r[1]
			way = w
	if way < 0:
		if best_k > 1:
			return 0       # no way meets it yet: wait a tick
		var ang := atan2(SimScript.wrap_d(cy, best.y, H), SimScript.wrap_d(cx, best.x, W))
		way = posmod(roundi(ang / (PI / 4.0)), 8)
	return WAYS8[way] | P.B_DODGE

# A tick of the drawn bow: aim at the target; once drawn long enough, let go along
# a path that reaches it (another target will do). With no path for AIM_HOLD more
# ticks on the ground, lower the bow with a jump (a jump lets go of the aim with
# no shot); in the air, wait to land, up to AIM_HOLD_MAX ticks, then shoot.
static func _draw(sim, f, m: Mind) -> void:
	m.draw_t += 1
	var tgt = sim.fighter(m.target)
	if tgt != null and tgt.state != P.F_DEAD:
		m.aim = aim_steps(atan2(SimScript.wrap_d(f.y + SimScript.ARROW_Y, tgt.y + SimScript.MID_Y, H),
			SimScript.wrap_d(f.x + SimScript.HALF_W, tgt.x + SimScript.HALF_W, W)))
	if m.draw_t < m.draw_need:
		return
	var past := m.draw_t - m.draw_need
	if past % 3 != 0:
		return
	var ang := NAN
	if tgt != null and tgt.state != P.F_DEAD:
		ang = find_shot(sim, f, tgt, LEAD[f.level])
	if is_nan(ang):
		var pick := _pick_shot(sim, f)
		if not pick.is_empty():
			m.target = pick[0].id
			ang = pick[1]
	if is_nan(ang):
		if past >= AIM_HOLD and f.on_ground:
			m.lower = true
			f.shoot_cd = 20
		if past < AIM_HOLD_MAX:
			return
	if not is_nan(ang):
		m.aim = aim_steps(ang + sim.rng.randfn(0.0, AIM_ERR[f.level]))
	m.drawing = false   # shoot is up this tick: the shot
	var pz: Array = PAUSE[f.level]
	f.shoot_cd = sim.rng.randi_range(pz[0], pz[1])

# The first of the 3 nearest enemies with a path: [the fighter, the angle], or [].
static func _pick_shot(sim, f) -> Array:
	var near: Array = []
	for o in sim.fighters:
		if o == f or o.state == P.F_DEAD:
			continue
		var dx := SimScript.wrap_d(f.x, o.x, W)
		var dy := SimScript.wrap_d(f.y, o.y, H)
		var d := dx * dx + dy * dy
		if o.in_smoke and d > 22500.0:
			continue
		near.append([d, o])
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in mini(3, near.size()):
		var ang := find_shot(sim, f, near[k][1], LEAD[f.level])
		if not is_nan(ang):
			return [near[k][1], ang]
	return []

# The angle of a shot from f's bow that reaches o (a copy of the arrow flown with
# the sim's numbers, through the wrap; lead: how far ahead of o's run to aim), or
# NAN when every try meets a wall first or falls short. The nearest wrap copy
# first; straight at it, then a little above and below (for the fall past 450 px).
static func find_shot(sim, f, o, lead: float) -> float:
	var bx := float(f.x + SimScript.HALF_W)
	var by := float(f.y + SimScript.ARROW_Y)
	var copies: Array = []
	for ox in [-1, 0, 1]:
		for oy in [-1, 0, 1]:
			var tx := float(o.x + ox * W)
			var ty := float(o.y + oy * H)
			var d := Vector2(tx + SimScript.HALF_W - bx, ty + SimScript.MID_Y - by).length()
			if d < SHOT_RANGE:
				copies.append([d, tx, ty])
	copies.sort_custom(func(a, b): return a[0] < b[0])
	for c in copies.slice(0, 2):
		var t_fly: float = c[0] / SimScript.ARROW_SPEED
		var vx: float = o.vx * lead
		var vy: float = o.vy * lead if not o.on_ground else 0.0
		var ax: float = c[1] + SimScript.HALF_W + vx * t_fly - bx
		var ay: float = c[2] + SimScript.MID_Y + vy * t_fly - by
		var straight := atan2(ay, ax)
		var tries: Array = SHOT_OFFSETS if c[0] > 420.0 else [0.0]
		for off in tries:
			var ang: float = straight + off
			var dir := Vector2.from_angle(ang)
			var r := fly(sim, bx + dir.x * 30.0, by + dir.y * 30.0, dir.x * SimScript.ARROW_SPEED, dir.y * SimScript.ARROW_SPEED,
				int(t_fly * 1.25) + 6, [c[1], c[2], vx, vy])
			if r[0] == FLY_HIT:
				return ang
	return NAN

# ------------------------------------------------------------------ a copy of an arrow
const FLY_NONE := 0     # still flying after max_t ticks
const FLY_WALL := 1     # stuck in a block or a ledge (from above)
const FLY_HIT := 2      # met the box

# A flying arrow's next max_t ticks, as sim._update_arrow moves it (straight for
# ARROW_STRAIGHT ticks after the shot, then falling; whole steps of 4 px; a block
# stops it, a ledge only from above). box: [x, y, vx, vy] (and a slow-down a
# tick, as a dodge has), a body's top-left and how it moves a tick, met the way
# sim._arrow_hit_fighters meets one; [] for none.
# t: the arrow's age now (0 for a shot not made yet). [FLY_*, ticks, x, y].
static func fly(sim, x: float, y: float, vx: float, vy: float, max_t: int, box: Array = [], t: int = 0) -> Array:
	var g: PackedByteArray = sim.level.grid   # level.cell_at inlined: this runs thousands of times a second
	var has_box := not box.is_empty()
	var bx: float = box[0] if has_box else 0.0
	var by: float = box[1] if has_box else 0.0
	var bvx: float = box[2] if has_box else 0.0
	var bvy: float = box[3] if has_box else 0.0
	var slow: float = box[4] if box.size() > 4 else 1.0
	for k in range(1, max_t + 1):
		t += 1
		if t > SimScript.ARROW_STRAIGHT:
			vy = minf(vy + SimScript.ARROW_GRAVITY, SimScript.ARROW_MAX_FALL)
			vx = move_toward(vx, 0.0, SimScript.ARROW_DRAG)
		var steps := maxi(1, ceili(maxf(absf(vx), absf(vy)) / 4.0))
		var sx := vx / steps
		var sy := vy / steps
		if has_box:      # the body moves before the arrows in a tick
			bvx *= slow
			bvy *= slow
			bx += bvx
			by += bvy
		for i in steps:
			var nx := x + sx
			var ny := y + sy
			var row := posmod(floori(ny / 30.0), 36)
			var c: int = g[row * 64 + posmod(floori(nx / 30.0), 64)]
			if c == 1 or (c == 2 and sy > 0.0 and floori(y / 30.0) < floori(ny / 30.0)):
				return [FLY_WALL, k, x, y]
			x = fposmod(nx, W)
			y = fposmod(ny, H)
			if has_box:
				var dx := x - bx
				dx -= roundf(dx / W) * W
				var dy := y - by
				dy -= roundf(dy / H) * H
				if dx >= -4.0 and dx <= SimScript.BODY_W + 4.0 and dy >= -4.0 and dy <= SimScript.BODY_H + 4.0:
					return [FLY_HIT, k, x, y]
	return [FLY_NONE, max_t, x, y]

# ------------------------------------------------------------------ what a bot sees
static func nearest_enemy(sim, f):
	var best = null
	var bd := INF
	for o in sim.fighters:
		if o == f or o.state == P.F_DEAD:
			continue
		var dx := SimScript.wrap_d(f.x, o.x, W)
		var dy := SimScript.wrap_d(f.y, o.y, H)
		var d := dx * dx + dy * dy
		if o.in_smoke and d > 22500.0:
			continue
		if d < bd:
			bd = d
			best = o
	return best

static func nearest_loose_arrow(sim, f):
	var best = null
	var bd := INF
	for a in sim.arrows:
		if a.dead or a.state != P.S_STUCK or a.fuse > 0:
			continue
		var dx := SimScript.wrap_d(f.x + SimScript.HALF_W, a.x, W)
		var dy := SimScript.wrap_d(f.y + SimScript.BODY_H, a.y, H)
		var d := dx * dx + dy * dy
		if d < bd:
			bd = d
			best = a
	return best

static func arrow_incoming(sim, f) -> bool:
	var cx := float(f.x + SimScript.HALF_W)
	var cy := float(f.y + SimScript.MID_Y)
	for a in sim.arrows:
		if a.dead or a.state != P.S_FLY or a.owner == f.id:
			continue
		var dx := SimScript.wrap_d(a.x, cx, W)
		var dy := SimScript.wrap_d(a.y, cy, H)
		if dx * dx + dy * dy < 40000.0 and dx * a.vx + dy * a.vy > 0.0:
			return true
	return false

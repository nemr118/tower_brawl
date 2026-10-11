# ==============================================================================
# The bot brain (G6, server bots): plays a seat with no person on it. It picks
# buttons each tick and presses them through sim.apply_input(), the same path a
# person's buttons take, so its jumps, drops, dodges and shots follow the
# person's rules (a shot gets the aim help). No scene nodes: the server, the
# probes and the benchmark page run it inside the sim (sim.gd calls think()
# for every bot fighter at the start of each tick; the client never does).
# Its memory between ticks is a Mind on the fighter (f.mind).
# Levels: OLD is p3.1's brain (kept as the probes' stand-in for a kid and as
# the baseline).
# ==============================================================================
extends RefCounted

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")

const OLD := 0
const NAMES := ["OLD"]

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

# One tick of a bot seat: the buttons for this tick, pressed like a person's.
static func think(sim, f) -> void:
	if f.mind == null:
		f.mind = Mind.new()
	var m: Mind = f.mind
	var b := 0
	if f.state == P.F_NORMAL or f.state == P.F_DODGE:
		b = _old(sim, f, m)
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
	if f.state != P.F_DODGE and f.dodge_cd == 0:
		if (rng.randf() < 0.4 and arrow_incoming(sim, f)) or rng.randf() < 0.004:
			return DODGE_WAYS[rng.randi() % DODGE_WAYS.size()] | P.B_DODGE
	if tgt != null and f.arrows > 0 and f.shoot_cd == 0 and f.state != P.F_DODGE and m.draw == 0 and rng.randf() < 0.05:
		var ax := SimScript.wrap_d(f.x, tgt.x, W)
		var ay := SimScript.wrap_d(f.y, tgt.y, H) - 20.0
		m.aim = aim_steps(atan2(ay, ax) + rng.randf_range(-0.12, 0.12))
		m.draw = 1
		f.shoot_cd = rng.randi_range(20, 50)
	return _buttons(m)

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

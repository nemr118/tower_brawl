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
# They get around by the route map (sim/routes.gd, from sim/routes.json): the
# fastest moves between floors and ledges, found offline with the sim's own
# movement; a bot walks to a move's start place and presses its buttons. Every 2
# to 4 s a bot either hunts (heads for its target's floor; more often at a higher
# level) or roams (heads for another floor somewhere), shooting whenever a path
# opens; one that has not moved for 2.5 s, or has stood by its target for 1 s with
# no shot, roams. With fewer than 2 arrows it fetches
# the arrow it can reach soonest (one by a floor or a ledge); with none and none to
# fetch, it goes for a stomp.
# TowerFall has no archer bots; its quest skeleton archers draw for 10 frames,
# aim in 22.5 degree steps and are one step off half the time, and fail a dodge
# 1 time in 10 to 1 in 5, more after each dodge (numbers only).
# ==============================================================================
extends RefCounted

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const Routes = preload("res://sim/routes.gd")

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
const AIM_HOLD := 30            # drawn this long past the draw with no path, on the ground: lower the bow (B_CANCEL)
const AIM_HOLD_MAX := 120       # and in the air, at most this long: then the shot goes anyway
const SHOT_OFFSETS := [0.0, -0.07, 0.07, -0.14, 0.14, -0.21, 0.21]   # radians tried around each arc's angle past 420 px
const NEAR_OFFSETS := [0.0, -0.035, 0.035]                          # and closer
const CATCH := [0.0, 0.2, 0.5, 0.8]   # the chance it dodges into an arrow coming at it (rolled once an arrow)
const PEOPLE := [1.0, 1.6, 1.0, 0.6]  # how far away a person seems when it picks a target (a factor on the
                                      # distance): EASY bots go for each other first, HARD bots for people
const SEE_T := 12               # an arrow that will reach it within this many ticks is seen (about 216 px)
const DODGE_AT := 8             # from this many ticks away it looks for a dodge that meets the arrow
const SEE_R2 := 90000.0         # arrows farther than 300 px are not looked at
const PLAN_EVERY := 30          # ticks between plans while it walks (its goal moves)
const WALK_GIVE_UP := 120       # ticks to reach a move's start place, then another way
const BAD_TICKS := 300          # a move that did not land where it should is not used for 5 s
const CROWD_TICKS := 40         # another fighter on the start place this long: another way
const NEAR_TARGET := 260.0      # on its target's floor it stops this far from it (and shoots)
const HUNT := [0.0, 0.3, 0.5, 0.8]    # by level: the chance a new plan hunts the target (else it roams)
const MODE_TICKS := [120, 240]  # a plan (hunt or roam) lasts 2 to 4 s
const IDLE_TICKS := 150         # not 90 px from where it was for 2.5 s with no shot: it lowers the bow and roams
const SEEK := [0.0, 0.35, 0.55, 0.75]   # p4.9: by level, the chance it goes for a power-up orb (rolled once an orb)
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
	var want_shot := false      # p4.4: this release is a shot; any other release gets B_CANCEL (think): no arrow
	var seen := {}              # an arrow's id -> true: dodge into it when it is close; false: let it come
	var only_dodge := false     # a test knob (the bot probe's catch test): stand, hold fire, only dodge
	var goal_s := -1            # the routes: the surface it heads for (-1: none yet)
	var goal_x := 960.0         # and the feet x it wants there
	var edge: Array = []        # the move it walks to: [from cx, move index, to cx, ticks, flags]
	var edge_to := -1           # the surface that move lands on
	var player = null           # a Routes.MovePlayer while a move plays
	var walk_t := 0             # ticks walking to the move's start place
	var plan_t := 0             # ticks to the next plan
	var bad := {}               # Vector3i(surface, from cx, move) -> the tick until which that move is not used
	var force_goal := -1        # a test knob (the bot probe's reach test): head for this surface
	var hunting := true         # the plan: hunt the target, or roam to roam_s
	var mode_t := 0             # ticks until it picks hunt or roam again
	var roam_s := -1
	var idle_at := Vector2.ZERO # where it was idle_t ticks ago (the idle check)
	var idle_t := 0
	var quit_draw := false      # idle while drawing: lower the bow this tick
	var walls_goal := false     # goal_s is a safe floor picked while the purple walls come
	var crowd_t := 0            # ticks another fighter has stood on the move's start place
	var still_t := 0            # ticks a playing move has stood still on the ground
	var still_x := 0            # and where
	var near_t := 0             # ticks it has stood near its target on the target's floor with no shot
	var fetch := -1             # the arrow it goes to fetch (its id), or -1
	var orb := -1               # p4.9: the power-up orb it goes for (its serial), or -1
	var orbs_seen := {}         # an orb's serial -> true: go for it; false: leave it

# One tick of a bot seat: the buttons for this tick, pressed like a person's.
static func think(sim, f) -> void:
	if f.mind == null:
		f.mind = Mind.new()
	var m: Mind = f.mind
	var b := 0
	if f.level != OLD and m.player != null:
		b = _play(sim, f, m)   # a move plays on in every state (a ledge hang is part of it)
	elif f.state == P.F_NORMAL or f.state == P.F_DODGE:
		b = _old(sim, f, m) if f.level == OLD else _play(sim, f, m)
	elif m.drawing:
		m.drawing = false   # knocked out of it: the bow is down
	if f.drawn and not (b & P.B_SHOOT):
		if m.want_shot:
			m.want_shot = false
		else:
			b |= P.B_CANCEL  # p4.4: a let-go shoot always fires now, so a release the brain does not mean says so
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
		m.want_shot = true   # the tick after the draw: the release, a shot
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
# The walking is the routes' (_route_move; OLD's walking when there is no route
# map); the dodge (_dodge) and the shot are their own:
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
	var tgt = nearest_enemy(sim, f, PEOPLE[f.level])
	var rm = Routes.map_for(sim.level)
	var walk := 0
	if rm != null:
		walk = _route_move(sim, f, m, rm, tgt)
	else:
		_old_move(sim, f, m, tgt)
	var dodge := _dodge(sim, f, m)
	if dodge != 0:
		m.player = null     # the dodge breaks a move: it plans again once it stands
		m.plan_t = 0
		m.drawing = false   # a drawn bow comes down on the dodge tick (B_CANCEL, think): no shot
		return dodge
	if m.drawing and m.draw_t > 1 and not f.aiming:
		m.drawing = false   # the bow never came up (knocked out of it): it comes down (B_CANCEL), try again later
	elif m.drawing:
		m.jump = 0          # it stands to shoot
		m.jump_wait = false
		if m.quit_draw and f.on_ground:
			m.drawing = false   # lower the bow: shoot comes up with B_CANCEL (think), no shot
			f.shoot_cd = 60
		else:
			_draw(sim, f, m)
		m.quit_draw = false
	elif f.arrows > 0 and f.shoot_cd == 0 and f.state == P.F_NORMAL and not f.aiming and m.player == null \
			and (m.edge.is_empty() or absf(SimScript.wrap_d(f.x + SimScript.HALF_W, m.edge[0] * 30.0, W)) > 40.0):
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
	if rm == null:
		return _buttons(m)
	var flee := _strike_flee(sim, f) if m.player == null else 0
	if flee != 0:
		m.drawing = false   # the bow comes down (B_CANCEL, think): it gets out of the way first
		return (walk & ~(P.B_LEFT | P.B_RIGHT | P.B_SHOOT)) | (P.B_RIGHT if flee > 0 else P.B_LEFT)
	if m.drawing:
		return (walk & (P.B_LEFT | P.B_RIGHT)) | P.B_SHOOT   # no jump or drop while the bow is drawn
	return walk

# ------------------------------------------------------------------ the routes
# The walking buttons for this tick, by the route map: a move that plays goes on
# until it lands; on the ground the bot plans every PLAN_EVERY ticks (its goal
# surface: _goal), walks to the start place of the fastest move toward it, stands
# still there, and plays the move. A move that lands on another surface, or a
# start place it cannot reach in WALK_GIVE_UP ticks, is not used for BAD_TICKS.
# In the air with no move (after a dodge, a knock) it steers toward its goal.
static func _route_move(sim, f, m: Mind, rm, tgt) -> int:
	if m.player != null:
		if m.player.airborne and f.on_ground and f.state == P.F_NORMAL:
			var landed: int = rm.surface_of(Routes.place_at(f, rm.at))
			if landed != m.edge_to and not m.edge.is_empty():
				m.bad[Vector3i(m.edge_to, m.edge[0], m.edge[1])] = sim.tick + BAD_TICKS
			m.player = null
			m.plan_t = 0
		elif m.player.t >= Routes.MAX_T:
			m.player = null
			m.plan_t = 0
		else:
			# a move that stands still on the ground (as the probe's runner gives up on one)
			if not m.player.airborne and f.on_ground and f.x == m.still_x:
				m.still_t += 1
			else:
				m.still_t = 0
			m.still_x = f.x
			if m.player.t > 40 and m.still_t > 10:
				m.bad[Vector3i(m.edge_to, m.edge[0], m.edge[1])] = sim.tick + BAD_TICKS
				m.player = null
				m.plan_t = 0
				return 0
			return m.player.buttons(f)
	if not f.on_ground or f.state != P.F_NORMAL:
		return _toward(f, m.goal_x, 0.0)
	var place := Routes.place_at(f, rm.at)
	var here: int = rm.surface_of(place)
	if here < 0:
		return _toward(f, m.goal_x, 0.0)
	# idle for IDLE_TICKS (no 90 px from where it was, no shot): roam somewhere else
	m.idle_t += 1
	if absf(SimScript.wrap_d(m.idle_at.x, f.x, W)) > 90.0 or absf(SimScript.wrap_d(m.idle_at.y, f.y, H)) > 90.0:
		m.idle_at = Vector2(f.x, f.y)
		m.idle_t = 0
	elif m.idle_t > IDLE_TICKS:
		m.idle_at = Vector2(f.x, f.y)
		m.idle_t = 0
		if m.drawing:
			m.quit_draw = true   # put the bow down (the drawing step lowers it with a jump), then go
		_roam(sim, m, rm, here)
		m.plan_t = 0
	m.mode_t -= 1
	if m.mode_t <= 0:
		m.mode_t = sim.rng.randi_range(MODE_TICKS[0], MODE_TICKS[1])
		if sim.rng.randf() < HUNT[f.level] and tgt != null:
			m.hunting = true
		else:
			_roam(sim, m, rm, here)
		m.plan_t = 0
	m.plan_t -= 1
	if m.plan_t <= 0 or m.goal_s < 0:
		m.plan_t = PLAN_EVERY
		_goal(sim, f, m, rm, tgt, here)
		_pick_edge(sim, m, rm, place, here)
		m.walk_t = 0
	if here == m.goal_s and m.walls_goal:
		m.plan_t = 0        # reached a safe floor: the next one
	elif here == m.goal_s and not m.hunting and m.force_goal < 0 and sim.walls_share <= 0.0:
		m.mode_t = 0        # roamed there: pick the next plan
	if here == m.goal_s and m.fetch >= 0:
		var a = _arrow_by_id(sim, m.fetch)
		if a == null or a.dead or a.state != P.S_STUCK:
			m.plan_t = 0        # someone took it: plan again
		else:
			m.goal_x = a.x
	if m.orb >= 0 and _orb_by_serial(sim, m.orb) == null:
		m.orb = -1
		m.plan_t = 0            # p4.9: someone took the orb (or it faded): plan again
	if here == m.goal_s or m.edge.is_empty():
		var near: bool = m.hunting and m.fetch < 0 and m.orb < 0 and f.arrows > 0 and m.force_goal < 0 and tgt != null and here == _surface_under(rm, tgt)
		var b := _toward(f, m.goal_x, NEAR_TARGET if near else 0.0)
		if f.arrows == 0 and m.fetch < 0 and tgt != null and here == _surface_under(rm, tgt) and b != 0 \
				and absf(SimScript.wrap_d(f.x, tgt.x, W)) < 90.0 and (m.prev & P.B_JUMP) == 0:
			b |= P.B_JUMP       # no arrows: jump at it, to come down on its head
		if near and b == 0 and not m.drawing:
			m.near_t += 1
			if m.near_t > 60:   # standing by its target with no shot for a second (a wall between): go round
				m.near_t = 0
				_roam(sim, m, rm, here)
				m.mode_t = sim.rng.randi_range(MODE_TICKS[0], MODE_TICKS[1])
				m.plan_t = 0
		else:
			m.near_t = 0
		return b
	var sx: float = m.edge[0] * 30.0
	if not m.drawing:
		m.walk_t += 1
	if m.walk_t > WALK_GIVE_UP:
		m.bad[Vector3i(m.edge_to, m.edge[0], m.edge[1])] = sim.tick + BAD_TICKS
		m.plan_t = 0
		return 0
	var dx := SimScript.wrap_d(f.x + SimScript.HALF_W, sx, W)
	if absf(dx) <= 40.0 and _crowded(sim, f, sx):
		m.crowd_t += 1
		if m.crowd_t > CROWD_TICKS:   # someone stands there: another way
			m.crowd_t = 0
			m.bad[Vector3i(m.edge_to, m.edge[0], m.edge[1])] = sim.tick + BAD_TICKS
			m.plan_t = 0
		return 0
	m.crowd_t = 0
	var go := _toward(f, sx, 0.0)
	if go != 0 and not m.drawing and (m.prev & P.B_JUMP) == 0 and _blocked(sim, f, 1 if go == P.B_RIGHT else -1):
		return go | P.B_JUMP   # someone stands in the way: hop over (or onto) them
	if absf(dx) <= 1.0 and absf(f.vx) < 0.1 and not m.drawing and not f.aiming \
			and (m.prev & (P.B_JUMP | P.B_DODGE | P.B_SHOOT)) == 0 \
			and (f.dodge_cd == 0 or (m.edge[4] & Routes.F_DODGE) == 0):
		# (the last tick's buttons were all up: the move's first jump or dodge is a fresh press, as in the probe)
		m.player = Routes.MovePlayer.new(rm.mvs[m.edge[1]])
		m.still_t = 0
		m.still_x = f.x
		return m.player.buttons(f)
	return go

# Another living fighter's body just ahead (within 45 px the way it walks) at about
# its height.
static func _blocked(sim, f, dir: int) -> bool:
	for o in sim.fighters:
		if o == f or o.state == P.F_DEAD:
			continue
		var dx := SimScript.wrap_d(f.x, o.x, W) * dir
		if dx > 0.0 and dx < 45.0 and absf(SimScript.wrap_d(f.y, o.y, H)) < 30.0:
			return true
	return false

# Another living fighter's body over the start place (feet x sx, on f's row).
static func _crowded(sim, f, sx: float) -> bool:
	for o in sim.fighters:
		if o != f and o.state != P.F_DEAD and absf(SimScript.wrap_d(o.x + SimScript.HALF_W, sx, W)) < 40.0 \
				and absf(SimScript.wrap_d(o.y, f.y, H)) < 70.0:
			return true
	return false

# Left or right toward feet x (none within near px; it lets go early enough to
# stop there: friction takes vx * vx / 1.8 px; the last pixels in taps).
static func _toward(f, x: float, near: float) -> int:
	var dx := SimScript.wrap_d(f.x + SimScript.HALF_W, x, W)
	if absf(dx) <= maxf(near, 1.0):
		return 0
	if absf(dx) <= 4.0 and absf(f.vx) > 0.0:
		return 0       # a tap at a time: let it stop first
	if f.on_ground and signf(dx) == signf(f.vx) and absf(dx) <= f.vx * f.vx / (2.0 * SimScript.FRICTION) + 1.0:
		return 0
	return P.B_RIGHT if dx > 0.0 else P.B_LEFT

# The goal: the test knob's surface; while the purple walls come, a safe floor
# (one with a place inside the band they leave), one after another; with fewer
# than 2 arrows, an arrow to fetch; roaming, the roam floor; else the surface
# under its target, at the target's x.
static func _goal(sim, f, m: Mind, rm, tgt, here: int) -> void:
	if m.force_goal >= 0:
		m.goal_s = m.force_goal
		var cols: Array = rm.surfs[m.goal_s][1]
		m.goal_x = cols[cols.size() / 2] * 30.0
		return
	if sim.walls_share > 0.0:
		# a safe floor (a place inside the band the walls leave), one after another
		var reach: float = sim.walls_width() + SimScript.WALLS_KEEP_AWAY
		if m.walls_goal and m.goal_s >= 0 and m.goal_s != here and _safe_x(rm, m.goal_s, reach) >= 0.0:
			return
		var safe: Array = []
		for s in rm.surfs.size():
			if s != here and rm.cost[here][s] < INF and _safe_x(rm, s, reach) >= 0.0:
				safe.append(s)
		if not safe.is_empty():
			m.goal_s = safe[sim.rng.randi() % safe.size()]
			m.goal_x = _safe_x(rm, m.goal_s, reach)
			m.walls_goal = true
			return
		if _safe_x(rm, here, reach) >= 0.0:
			m.goal_s = here
			m.goal_x = tgt.x + SimScript.HALF_W if tgt != null else 960.0
			m.walls_goal = true
			return
	m.walls_goal = false
	m.fetch = -1
	m.orb = -1
	if _orb_goal(sim, f, m, rm, here):
		return
	if f.arrows < 2:
		var got := _fetch_goal(sim, f, m, rm, here)
		if got:
			return
	if not m.hunting and m.roam_s >= 0:
		m.goal_s = m.roam_s
		var rc: Array = rm.surfs[m.roam_s][1]
		m.goal_x = rc[rc.size() / 2] * 30.0
		return
	if tgt != null:
		var s := _surface_under(rm, tgt)
		if s >= 0:
			m.goal_s = s
			m.goal_x = tgt.x + SimScript.HALF_W

# Fetch: of the stuck arrows (none of a bomb's fuse), the one whose floor it reaches
# soonest: a floor or ledge under it close enough that a body standing there picks
# it up (sim._pickups: within 50 px across and 68 px up or down of the middle).
# Sets the goal and returns true, or false with none in reach.
static func _fetch_goal(sim, f, m: Mind, rm, here: int) -> bool:
	var best_c := INF
	for a in sim.arrows:
		if a.dead or a.state != P.S_STUCK or a.fuse > 0:
			continue
		var cx := roundi(a.x / 30.0)
		var r0 := floori(a.y / 30.0)
		for dr in 4:           # the first floor under the arrow, close enough to reach it from
			var r := posmod(r0 + dr, 36)
			var s := -1
			for k in [0, -1, 1]:
				s = rm.at.get(Vector2i(posmod(cx + k, 64), r), -1)
				if s >= 0:
					break
			if s < 0:
				continue
			var feet := r * 30.0
			var mid := feet - SimScript.BODY_H + SimScript.MID_Y
			# the route to its floor, and on its own floor the walk to it
			var c: float = rm.cost[here][s] + (absf(SimScript.wrap_d(f.x + SimScript.HALF_W, a.x, W)) / 6.75 if s == here else 0.0)
			if absf(SimScript.wrap_d(mid, a.y, H)) < 66.0 and c < best_c:
				best_c = c
				m.goal_s = s
				m.goal_x = a.x
				m.fetch = a.id
			break
	return m.fetch >= 0

# p4.9: a power-up orb waiting to be taken (not FLYING or a BIG one: those are for
# people), if the level's roll for that orb said go and its floor is in reach: the
# goal is its floor, at its x. Returns true with a goal.
static func _orb_goal(sim, f, m: Mind, rm, here: int) -> bool:
	for o in sim.orbs:
		if o.state != P.ORB_LIVE or not sim.may_take(f, o):
			continue
		if not m.orbs_seen.has(o.serial):
			m.orbs_seen[o.serial] = sim.rng.randf() < SEEK[f.level]
		if not m.orbs_seen[o.serial]:
			continue
		var cx := roundi(o.x / 30.0)
		var r := posmod(roundi((o.y + SimScript.ORB_UP) / 30.0), 36)
		var s := -1
		for k in [0, -1, 1]:
			s = rm.at.get(Vector2i(posmod(cx + k, 64), r), -1)
			if s >= 0:
				break
		if s < 0 or rm.cost[here][s] == INF:
			continue
		m.goal_s = s
		m.goal_x = o.x
		m.orb = o.serial
		return true
	return false

static func _orb_by_serial(sim, serial: int):
	for o in sim.orbs:
		if o.serial == serial and o.state == P.ORB_LIVE:
			return o
	return null

# p4.9: an orb's lightning builds up near: step away from it (1 right, -1 left, 0:
# no need). EASY notices only half of them.
static func _strike_flee(sim, f) -> int:
	if f.level == OLD or not f.on_ground or f.state != P.F_NORMAL:
		return 0
	var r: float = SimScript.STRIKE_R + 60.0
	for o in sim.orbs:
		if o.state != P.ORB_WARN:
			continue
		var dx := SimScript.wrap_d(o.x, f.x + SimScript.HALF_W, W)
		var dy := SimScript.wrap_d(o.y, f.y + SimScript.MID_Y, H)
		if dx * dx + dy * dy < r * r:
			if f.level == EASY and (o.serial + f.id) % 2 == 0:
				continue
			return 1 if dx >= 0.0 else -1
	return 0

# The place of surface s inside the band the walls leave nearest the middle (its
# feet x), or -1.
static func _safe_x(rm, s: int, reach: float) -> float:
	var best := -1.0
	for cx in rm.surfs[s][1]:
		var x: float = cx * 30.0
		if x > reach and x < W - reach and (best < 0.0 or absf(x - 960.0) < absf(best - 960.0)):
			best = x
	return best

# Roam: a floor or ledge other than this one that it can reach, picked at random.
static func _roam(sim, m: Mind, rm, here: int) -> void:
	m.hunting = false
	var n: int = rm.surfs.size()
	for k in 8:
		var s: int = sim.rng.randi() % n
		if s != here and rm.cost[here][s] < INF:
			m.roam_s = s
			return
	m.roam_s = -1
	m.hunting = true

# The fastest move from here toward the goal: the next surface on the way
# (rm.hop), then of the moves that land there the one with the least walking plus
# ticks (the bad ones left out); with none, any move out of here that ends nearer.
static func _pick_edge(sim, m: Mind, rm, place: Vector2i, here: int) -> void:
	m.edge = []
	m.edge_to = -1
	if m.goal_s < 0 or here == m.goal_s:
		return
	var best_c := INF
	var nxt: int = rm.hop[here][m.goal_s]
	var row: int = rm.surfs[here][0]
	for key in ([Vector2i(here, nxt)] if nxt >= 0 else []):
		for e in rm.cand.get(key, []):
			if m.bad.get(Vector3i(key.y, e[0], e[1]), -1) > sim.tick:
				continue
			var c: float = rm.walk_ticks(place, Vector2i(e[0], row)) + e[3]
			if c < best_c:
				best_c = c
				m.edge = e
				m.edge_to = key.y
	if not m.edge.is_empty():
		return
	for key in rm.cand:
		if key.x != here or rm.cost[key.y][m.goal_s] == INF:
			continue
		for e in rm.cand[key]:
			if m.bad.get(Vector3i(key.y, e[0], e[1]), -1) > sim.tick:
				continue
			var c: float = rm.walk_ticks(place, Vector2i(e[0], row)) + e[3] + rm.cost[key.y][m.goal_s]
			if c < best_c:
				best_c = c
				m.edge = e
				m.edge_to = key.y

static func _arrow_by_id(sim, id: int):
	for a in sim.arrows:
		if a.id == id:
			return a
	return null

# The surface a fighter stands on, or the first one under its feet.
static func _surface_under(rm, o) -> int:
	var cx := roundi((o.x + SimScript.HALF_W) / 30.0)
	var r0 := floori((o.y + SimScript.BODY_H) / 30.0)
	for dr in 36:
		var r := posmod(r0 + dr, 36)
		for k in [0, -1, 1]:
			var s: int = rm.at.get(Vector2i(posmod(cx + k, 64), r), -1)
			if s >= 0:
				return s
	return -1

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
# ticks on the ground, lower the bow (shoot comes up with B_CANCEL: no shot); in
# the air, wait to land, up to AIM_HOLD_MAX ticks, then shoot.
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
			m.drawing = false   # lower the bow: shoot comes up with B_CANCEL (think), no shot
			f.shoot_cd = 60     # and move a while before drawing again
			return
		if past < AIM_HOLD_MAX:
			return
	if not is_nan(ang):
		m.aim = aim_steps(ang + sim.rng.randfn(0.0, AIM_ERR[f.level]))
	m.drawing = false   # shoot is up this tick: the shot
	m.want_shot = true
	m.idle_t = 0
	var pz: Array = PAUSE[f.level]
	f.shoot_cd = sim.rng.randi_range(pz[0], pz[1])

# The first of the 3 nearest enemies with a path: [the fighter, the angle], or [].
static func _pick_shot(sim, f) -> Array:
	var near: Array = []
	if f.in_smoke:
		return []          # p4.9: inside smoke it sees nobody
	for o in sim.fighters:
		if o == f or o.state == P.F_DEAD or SimScript.invisible(o):
			continue
		var dx := SimScript.wrap_d(f.x, o.x, W)
		var dy := SimScript.wrap_d(f.y, o.y, H)
		var d := dx * dx + dy * dy
		if o.in_smoke and d > 22500.0:
			continue
		if not o.bot:
			d *= PEOPLE[f.level] * PEOPLE[f.level]
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
# first; p4.4: the arrow lobs, so the tries are the low arc to the aim point, then
# the high one (lob_angles), each with a little above and below.
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
		var offs: Array = SHOT_OFFSETS if c[0] > 420.0 else NEAR_OFFSETS
		for arc in lob_angles(ax, ay):
			var t_arc: float = absf(ax) / maxf(1.0, absf(cos(arc)) * SimScript.ARROW_SPEED)
			for off in offs:
				var ang: float = arc + off
				var dir := Vector2.from_angle(ang)
				var r := fly(sim, bx + dir.x * 30.0, by + dir.y * 30.0, dir.x * SimScript.ARROW_SPEED, dir.y * SimScript.ARROW_SPEED,
					int(maxf(t_fly, t_arc) * 1.25) + 6, [c[1], c[2], vx, vy])
				if r[0] == FLY_HIT:
					return ang
	return NAN

# The angles that send an arrow (ARROW_SPEED, falling by ARROW_LOB_G a tick from
# the bow) through the point (x, y) from the bow, y down: the low arc, then the
# high one; [] out of reach; the line itself straight up or down.
static func lob_angles(x: float, y: float) -> Array:
	var v2: float = SimScript.ARROW_SPEED * SimScript.ARROW_SPEED
	var g: float = SimScript.ARROW_LOB_G
	var ax := absf(x)
	if ax < 1.0:
		return [atan2(y, x)]
	var disc := v2 * v2 - g * (g * ax * ax - 2.0 * y * v2)
	if disc < 0.0:
		return []
	var r := sqrt(disc)
	var out: Array = []
	for up in [atan((v2 - r) / (g * ax)), atan((v2 + r) / (g * ax))]:
		out.append(-up if x >= 0.0 else PI + up)
	return out

# ------------------------------------------------------------------ a copy of an arrow
const FLY_NONE := 0     # still flying after max_t ticks
const FLY_WALL := 1     # stuck in a block or a ledge (from above)
const FLY_HIT := 2      # met the box

# A flying arrow's next max_t ticks, as sim._update_arrow moves it (p4.4: falling
# by ARROW_LOB_G a tick from the bow, no drag; whole steps of 4 px; a block
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
		vy = minf(vy + SimScript.ARROW_LOB_G, SimScript.ARROW_MAX_FALL)
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
# The nearest living enemy (one hidden in smoke only up close); a person's distance
# times people_w (PEOPLE by level; OLD: 1). p4.9: none while it stands in smoke
# (smoke blinds whoever is inside), and never an INVISIBLE one out of sight.
static func nearest_enemy(sim, f, people_w := 1.0):
	var best = null
	var bd := INF
	if f.in_smoke:
		return null
	for o in sim.fighters:
		if o == f or o.state == P.F_DEAD or SimScript.invisible(o):
			continue
		var dx := SimScript.wrap_d(f.x, o.x, W)
		var dy := SimScript.wrap_d(f.y, o.y, H)
		var d := dx * dx + dy * dy
		if o.in_smoke and d > 22500.0:
			continue
		if not o.bot:
			d *= people_w * people_w
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

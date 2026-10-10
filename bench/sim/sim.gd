# ==============================================================================
# The simulation: the game's rules with no scene nodes, so the server runs it
# headless and a probe can run 10 000 ticks in a blink. It grew out of the
# 8-player benchmark's load model (branch beta, 2026-09) and keeps that use:
# `SimScript.new(8)` makes 8 bot fighters that respawn for ever.
# It does the same kind of work per tick as TowerFall's Player.cs and Arrow.cs
# (decompiled, ~/Work/towerfall_research, read for the numbers, never copied):
# bodies that move one whole pixel at a time against a tile grid, arrows that
# fly straight then fall, stick, are caught by a dodge and picked up, stomps,
# one-hit deaths, and the bench's power-up arrows (fire lights the ground, bombs
# blow up, miasma leaves a poison cloud). TowerFall's numbers are px per frame
# at 60 fps; x4.5 gives ours (a 63 px body in 1920 x 1080).
# A person's seat gets its buttons through apply_input(); a seat with no person
# is played by the bot brain (_brain). P1 (2026-10-10, first-playable-plan.md).
# ==============================================================================
extends RefCounted

const P = preload("res://sim/proto.gd")
const LevelScript = preload("res://sim/level.gd")

const S := 4.5
const RUN_MAX := 1.5 * S            # Player.cs MAX_RUN
const RUN_ACCEL := 0.15 * S         # RUN_ACCEL
const AIR_ACCEL := 0.1 * S          # AIR_RUN_ACCEL
const FRICTION := 0.2 * S           # FRICTION
const AIR_FRICTION := 0.14 * S      # AIR_FRICTION
const GRAVITY := 0.3 * S            # GRAVITY
const GRAVITY_HELD := 0.15 * S      # while jump is held on the way up
const JUMP := 3.2 * S               # JUMP
const JUMP_HBOOST := 0.5 * S        # JUMP_HBOOST
const JUMP_BUFFER := 5              # a jump pressed this many ticks before landing still jumps
const MAX_FALL := 2.8 * S           # MAX_FALL
const FAST_FALL := 3.5 * S          # FAST_FALL
const WALL_SLIDE_MAX := 1.6 * S     # WALLSTICK_MAX_FALL
const WALLJUMP_X := 2.0 * S
const DODGE_SPEED := 5.5 * S        # DODGE_SPEED
const DODGE_SLIDE_MULT := 1.4       # DODGE_SLIDE_SPEED_MULT: a dodge along the ground is faster
const DODGE_DECAY := 0.85           # DODGE_MULT per frame
const DODGE_TICKS := 20             # DODGE_TIME
const DODGE_COOLDOWN := 25          # DODGE_COOLDOWN
const DODGE_JUMP_TICKS := 12        # DODGE_JUMP_COUNTER: a jump in the first ticks of a ground dodge cancels it
const DODGE_JUMP_VX := 1.8 * S      # DODGE_JUMP_SPEED_MAX
const CATCH_HOLD := 10              # DODGE_CATCH_DELAY: a catch holds the fighter still this long
const COYOTE_TICKS := 6             # JUMP_GRACE
const AIM_HELP_R := 36.0 * S        # a shot snaps to an enemy this close (FindAutoLockAngle: 36 px)
const AIM_HELP_DEG := 65.0          # and within this angle of the aim (13/36 pi)
const ARROW_SPEED := 4.0 * S        # Arrow.cs SPEED
const ARROW_STRAIGHT := 25          # LIFE (the straight part)
const ARROW_GRAVITY := 0.2 * S      # GRAVITY
const ARROW_DRAG := 0.03 * S        # H_DRAG
const ARROW_MAX_FALL := 5.5 * S     # MAX_FALL
const ARROW_NO_SELF := 10
const PICKUP_DELAY := 15            # CANNOT_PICKUP_TIME
const MAX_QUIVER := 6               # ARROWS_MAX
const START_QUIVER := 3
const EXPLODE_R := 35.0 * S         # Explosion.cs HIT_RADIUS_SQ 1225 = 35 px
const BOMB_FUSE := 15
const FIRE_TICKS := 240             # Arrow.cs BURN_TIME 180, a bit longer on the ground
const FIRE_WIDTH := 150.0
const FIRE_KILL_TICKS := 20
const MIASMA_R := 150.0
const MIASMA_TICKS := 300
const MIASMA_KILL_TICKS := 45
const RESPAWN_TICKS := 90
const SMOKE_R := 230.0
const SMOKE_TICKS := 480
const HURT_TICKS := 18
const LEDGE_HOP := 3.0 * S
const MAX_ZONES := 32
const BODY_W := 36
const BODY_H := 63
const HALF_W := 18
const MID_Y := 31
const ARROW_Y := 28                 # the arrow leaves the body this far below its top
const W := 1920
const H := 1080
const DODGE_DIRS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, -1), Vector2(0.7071, -0.7071),
	Vector2(-0.7071, -0.7071), Vector2(0.7071, 0.7071), Vector2(-0.7071, 0.7071)]

class Fighter:
	var id: int = 0             # the seat, 0..7
	var bot: bool = true        # the brain presses the buttons (no person on this seat)
	var connected: bool = true  # false: a person's seat whose socket is gone (the brain plays it meanwhile)
	var x: int = 0              # top-left of the body box
	var y: int = 0
	var rx: float = 0.0         # the part of a pixel not moved yet
	var ry: float = 0.0
	var vx: float = 0.0         # px per tick
	var vy: float = 0.0
	var state: int = 0
	var state_t: int = 0
	var facing: int = 1
	var on_ground: bool = false
	var coyote: int = 0
	var wall: int = 0
	var dodge_t: int = 0
	var dodge_cd: int = 0
	var dodge_jump_t: int = 0
	var catch_t: int = 0
	var arrows: int = 3
	var aim: float = 0.0
	var aiming: bool = false
	var points: int = 0         # the server copies the seat's points here for the snapshot
	var dead_t: int = 0
	var burn_t: int = 0
	var miasma_t: int = 0
	var think_t: int = 0        # the bot brain
	var move_dir: int = 0
	var want_jump: bool = false
	var jump_buf: int = 0
	var hold_jump: int = 0
	var drop_t: int = 0         # down is held: fall faster; with jump, drop through a ledge
	var dropping: int = 0       # just dropped through a ledge: ledges are air for these ticks
	var shoot_cd: int = 0
	var wj_t: int = 0
	var ledge_t: int = 0
	var rolling: bool = false
	var in_smoke: bool = false
	var buttons: int = 0        # the last buttons applied, for the press edges

class Arrow:
	var id: int = 0
	var kind: int = 0
	var state: int = 0
	var x: float = 0.0
	var y: float = 0.0
	var vx: float = 0.0
	var vy: float = 0.0
	var ang: float = 0.0
	var owner: int = 0
	var t: int = 0
	var stuck_t: int = 0
	var fuse: int = -1
	var dead: bool = false

class Zone:
	var kind: int = 0
	var x: float = 0.0
	var y: float = 0.0
	var size: float = 0.0       # fire: width; miasma: radius
	var life: int = 0
	var max_life: int = 1

var level
var fighters: Array = []
var arrows: Array = []
var zones: Array = []
var events: Array = []
var tick: int = 0
var arrow_cap: int = 24
var respawn := true             # the benchmark: a death respawns after 1 s. The game: one life a round
var power_arrows := true        # the benchmark's arrow mix. The game: plain arrows unless --power-arrows
var frozen := false             # the round's first moment: nobody moves, nobody shoots
var rng := RandomNumberGenerator.new()
var _next_arrow_id: int = 1
var kind_weights: Array = [30, 17, 17, 17, 19]   # normal, fire, bomb, miasma, smoke

func _init(n_fighters: int = 8, cap: int = 24, seed_value: int = 7) -> void:
	level = LevelScript.new()
	arrow_cap = cap
	rng.seed = seed_value
	for i in n_fighters:
		var f := Fighter.new()
		f.id = i
		fighters.append(f)
		_respawn(f)

static func wrap_d(a: float, b: float, size: float) -> float:
	var d := b - a
	if d > size * 0.5:
		d -= size
	elif d < -size * 0.5:
		d += size
	return d

func take_events() -> Array:
	var e := events
	events = []
	return e

func step() -> void:
	tick += 1
	for f in fighters:
		_update_fighter(f)
	_stomps()
	for a in arrows:
		_update_arrow(a)
	_tinks()
	_pickups()
	_update_zones()
	_enforce_cap()
	for i in range(arrows.size() - 1, -1, -1):
		if arrows[i].dead:
			arrows.remove_at(i)

func _event(type: int, x: int, y: int, a: int, b: int) -> void:
	events.append([type, x, y, a, b])

# ------------------------------------------------------------------ the match
# A round: one fighter per seat in seat_list ([{"id": seat, "bot": true/false}]),
# each on its own spawn spot, with a full quiver. Arrows and zones go; the tick
# keeps counting (the clients' clock follows it).
func start_round(seat_list: Array) -> void:
	fighters.clear()
	arrows.clear()
	zones.clear()
	events.clear()
	var spots: Array = level.spawns.duplicate()
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	for i in seat_list.size():
		var f := Fighter.new()
		f.id = int(seat_list[i]["id"])
		f.bot = bool(seat_list[i]["bot"])
		fighters.append(f)
		_place(f, spots[i % spots.size()])

func clear() -> void:
	fighters.clear()
	arrows.clear()
	zones.clear()
	events.clear()

func fighter(id: int) -> Fighter:
	for f in fighters:
		if f.id == id:
			return f
	return null

func alive_count() -> int:
	var n := 0
	for f in fighters:
		if f.state != P.F_DEAD:
			n += 1
	return n

func last_alive() -> Fighter:
	for f in fighters:
		if f.state != P.F_DEAD:
			return f
	return null

# A person's buttons for this tick (proto B_*, aim in 0.1 degree steps). Sets
# what _update_fighter reads: move_dir, the jump (pressed: want_jump with a
# short buffer; held: hold_jump for the higher jump), down (drop_t), shoot
# (held: aiming; let go: the shot), and a dodge the way the stick points.
func apply_input(f: Fighter, buttons: int, aim: int) -> void:
	var prev := f.buttons
	f.buttons = buttons
	f.aim = fposmod(aim * TAU / 3600.0, TAU)
	if f.state == P.F_DEAD or frozen:
		f.move_dir = 0
		return
	f.move_dir = (1 if buttons & P.B_RIGHT else 0) - (1 if buttons & P.B_LEFT else 0)
	if buttons & P.B_DOWN:
		f.drop_t = 2
	if buttons & P.B_JUMP:
		f.hold_jump = 2
		if not (prev & P.B_JUMP):
			f.want_jump = true
			f.jump_buf = JUMP_BUFFER
	if buttons & P.B_SHOOT:
		if not f.aiming and not (prev & P.B_SHOOT) and f.state == P.F_NORMAL:
			f.aiming = true
	elif f.aiming:
		f.aiming = false
		if f.state == P.F_NORMAL:
			if f.arrows > 0:
				_shoot(f, _aim_help(f, f.aim), _pick_kind() if power_arrows else P.A_NORMAL)
			else:
				_event(P.E_DRYFIRE, f.x + HALF_W, f.y + MID_Y, f.id, 0)
	if (buttons & P.B_DODGE) and not (prev & P.B_DODGE):
		if f.state == P.F_DODGE:
			f.dodge_t = mini(f.dodge_t, 1)   # a second press ends the dodge
		elif f.state == P.F_NORMAL and f.dodge_cd == 0:
			var d := Vector2(float(f.move_dir), (1.0 if buttons & P.B_DOWN else 0.0) - (1.0 if buttons & P.B_UP else 0.0))
			_start_dodge(f, d)

# ------------------------------------------------------------------ collision
func box_hits_solid(x: int, y: int, w: int, h: int) -> bool:
	var cx0 := floori(x / 30.0)
	var cx1 := floori((x + w - 1) / 30.0)
	var cy0 := floori(y / 30.0)
	var cy1 := floori((y + h - 1) / 30.0)
	for cy in range(cy0, cy1 + 1):
		for cx in range(cx0, cx1 + 1):
			if level.cell(cx, cy) == 1:
				return true
	return false

func _ledge_below(x: int, bottom: int) -> bool:
	if posmod(bottom, 30) != 0:
		return false
	var cy := floori(bottom / 30.0)
	for cx in range(floori(x / 30.0), floori((x + BODY_W - 1) / 30.0) + 1):
		if level.cell(cx, cy) == 2:
			return true
	return false

func _on_ground(f: Fighter) -> bool:
	if box_hits_solid(f.x, f.y + 1, BODY_W, BODY_H):
		return true
	return f.dropping == 0 and _ledge_below(f.x, f.y + BODY_H)

func _move_h(f: Fighter, amount: float) -> bool:
	f.rx += amount
	var move := roundi(f.rx)
	if move == 0:
		return false
	f.rx -= move
	var sgn := signi(move)
	while move != 0:
		if box_hits_solid(f.x + sgn, f.y, BODY_W, BODY_H):
			f.rx = 0.0
			return true
		f.x += sgn
		move -= sgn
	return false

func _move_v(f: Fighter, amount: float) -> bool:
	f.ry += amount
	var move := roundi(f.ry)
	if move == 0:
		return false
	f.ry -= move
	var sgn := signi(move)
	while move != 0:
		if box_hits_solid(f.x, f.y + sgn, BODY_W, BODY_H) or (sgn > 0 and f.dropping == 0 and _ledge_below(f.x, f.y + BODY_H)):
			f.ry = 0.0
			return true
		f.y += sgn
		move -= sgn
	return false

# A straight line from (x, y) along (dx, dy) crosses a solid cell. 10 px steps.
func _line_blocked(x: float, y: float, dx: float, dy: float) -> bool:
	var n := maxi(1, ceili(maxf(absf(dx), absf(dy)) / 10.0))
	for i in range(1, n + 1):
		if level.cell_at(fposmod(x + dx * i / n, W), fposmod(y + dy * i / n, H)) == 1:
			return true
	return false

# ------------------------------------------------------------------ fighters
# A wall top the fighter can hang from: a solid cell with room above it, near
# the height of the fighter's head while it slides down (TowerFall's ledge grab).
func _ledge_top(f: Fighter) -> int:
	var cx := floori((f.x + (BODY_W if f.wall > 0 else -1)) / 30.0)
	for cy in range(floori((f.y - 6) / 30.0), floori((f.y + 24) / 30.0) + 1):
		if level.cell(cx, cy) == 1 and level.cell(cx, cy - 1) != 1:
			var top := cy * 30
			if f.y + 6 >= top - 4 and f.y + 6 <= top + 24 and not box_hits_solid(f.x, top + 6, BODY_W, BODY_H):
				return top
	return -1

func _hurt(f: Fighter, vx: float, vy: float) -> void:
	if f.state == P.F_DEAD:
		return
	f.state = P.F_HURT
	f.state_t = 0
	f.dodge_t = HURT_TICKS
	f.aiming = false
	f.vx = vx
	f.vy = vy
	_event(P.E_HURT, f.x + HALF_W, f.y + MID_Y, f.id, 0)

func _respawn(f: Fighter) -> void:
	var spot: Vector2i = level.spawns[rng.randi() % level.spawns.size()]
	for _i in 4:
		var s: Vector2i = level.spawns[rng.randi() % level.spawns.size()]
		var taken := false
		for o in fighters:
			if o != f and o.state != P.F_DEAD and absf(wrap_d(o.x + HALF_W, s.x, W)) < 120.0 and absf(wrap_d(o.y + BODY_H, s.y, H)) < 120.0:
				taken = true
				break
		if not taken:
			spot = s
			break
	_place(f, spot)

# The fighter stands on spot (its feet), alive, with a full quiver.
func _place(f: Fighter, spot: Vector2i) -> void:
	f.x = spot.x - HALF_W
	f.y = spot.y - BODY_H
	f.rx = 0.0
	f.ry = 0.0
	f.vx = 0.0
	f.vy = 0.0
	f.state = P.F_NORMAL
	f.state_t = 0
	f.arrows = START_QUIVER
	f.aiming = false
	f.dodge_t = 0
	f.dodge_cd = 0
	f.dodge_jump_t = 0
	f.catch_t = 0
	f.burn_t = 0
	f.miasma_t = 0
	f.drop_t = 0
	f.dropping = 0
	f.wj_t = 0
	f.move_dir = 0
	f.want_jump = false
	f.jump_buf = 0
	f.hold_jump = 0
	f.rolling = false
	_event(P.E_SPAWN, spot.x, spot.y, f.id, 0)

func _kill(f: Fighter, _killer: int, cause: int) -> void:
	if f.state == P.F_DEAD:
		return
	f.state = P.F_DEAD
	f.state_t = 0
	f.dead_t = RESPAWN_TICKS
	f.aiming = false
	_event(P.E_DEATH, f.x + HALF_W, f.y + MID_Y, f.id, cause)

func _update_fighter(f: Fighter) -> void:
	if f.state == P.F_DEAD:
		f.dead_t -= 1
		f.state_t += 1
		f.on_ground = _on_ground(f)
		if f.on_ground:
			f.vx = move_toward(f.vx, 0.0, FRICTION * 2.0)
		else:
			f.vy = move_toward(f.vy, MAX_FALL * 1.4, GRAVITY)
		if _move_h(f, f.vx):
			f.vx = -f.vx * 0.3
		if _move_v(f, f.vy):
			f.vy = -f.vy * 0.3 if f.vy > 6.0 else 0.0
		f.x = posmod(f.x, W)
		f.y = posmod(f.y, H)
		if f.dead_t <= 0 and respawn:
			_respawn(f)
		return
	f.state_t += 1
	if f.wj_t > 0:
		f.wj_t -= 1
	var was_ground := f.on_ground
	f.on_ground = _on_ground(f)
	if f.on_ground:
		f.coyote = COYOTE_TICKS
		if not was_ground:
			_event(P.E_LAND, f.x + HALF_W, f.y + BODY_H, f.id, clampi(int(absf(f.vy)), 0, 255))
	elif f.coyote > 0:
		f.coyote -= 1
	if f.dodge_cd > 0:
		f.dodge_cd -= 1
	if f.bot and not frozen and (f.state == P.F_NORMAL or f.state == P.F_DODGE):
		_brain(f)
	if f.state == P.F_HURT:
		f.dodge_t -= 1
		if f.on_ground:
			f.vx = move_toward(f.vx, 0.0, FRICTION)
		else:
			f.vy = move_toward(f.vy, MAX_FALL, GRAVITY)
		if f.dodge_t <= 0:
			f.state = P.F_NORMAL
			f.state_t = 0
	elif f.state == P.F_LEDGE:
		f.vx = 0.0
		f.vy = 0.0
		f.ledge_t -= 1
		if f.ledge_t <= 0:
			f.state = P.F_NORMAL
			f.state_t = 0
			f.vy = -JUMP * 0.95
			f.vx = f.facing * LEDGE_HOP
			f.hold_jump = 10
			_event(P.E_JUMP, f.x + HALF_W, f.y + BODY_H, f.id, 0)
	elif f.state == P.F_DODGE:
		f.dodge_t -= 1
		if f.catch_t > 0:
			f.catch_t -= 1
			f.vx = 0.0
			f.vy = 0.0
		else:
			f.vx *= DODGE_DECAY
			f.vy *= DODGE_DECAY
		if f.dodge_jump_t > 0:
			f.dodge_jump_t -= 1
		if f.want_jump and f.dodge_jump_t > 0 and (f.on_ground or f.coyote > 0):
			# a jump in the first ticks of a ground dodge: out of the dodge and up
			f.want_jump = false
			f.state = P.F_NORMAL
			f.state_t = 0
			f.dodge_cd = DODGE_COOLDOWN
			f.rolling = false
			f.vy = -JUMP
			f.vx = clampf(f.vx, -DODGE_JUMP_VX, DODGE_JUMP_VX)
			f.coyote = 0
			f.on_ground = false
			_event(P.E_JUMP, f.x + HALF_W, f.y + BODY_H, f.id, 0)
		elif f.dodge_t <= 0:
			f.state = P.F_NORMAL
			f.state_t = 0
			f.dodge_cd = DODGE_COOLDOWN
	else:
		var accel := RUN_ACCEL if f.on_ground else AIR_ACCEL
		var stand_aim := f.aiming and f.on_ground   # aiming on the ground: you stand still
		if f.move_dir != 0 and not stand_aim:
			f.facing = f.move_dir
			f.vx = move_toward(f.vx, RUN_MAX * f.move_dir, accel)
		else:
			f.vx = move_toward(f.vx, 0.0, FRICTION if f.on_ground else AIR_FRICTION)
		if f.aiming:
			f.facing = 1 if cos(f.aim) >= 0.0 else -1
		f.wall = 0
		if not f.on_ground and f.move_dir != 0 and box_hits_solid(f.x + f.move_dir, f.y, BODY_W, BODY_H):
			f.wall = f.move_dir
			if f.vy > 0.0:
				var top := _ledge_top(f)
				if top >= 0:
					f.state = P.F_LEDGE
					f.state_t = 0
					f.aiming = false
					f.ledge_t = rng.randi_range(12, 40) if f.bot else 8
					f.facing = f.wall
					f.y = top + 6
					f.ry = 0.0
					f.vx = 0.0
					f.vy = 0.0
					_event(P.E_LEDGE, f.x + (BODY_W if f.wall > 0 else 0), top, f.id, 1 if f.wall > 0 else 0)
					f.wall = 0
					return
		if not f.on_ground:
			var g := GRAVITY_HELD if (f.hold_jump > 0 and f.vy <= S) else GRAVITY
			var target := MAX_FALL
			if f.wall != 0 and f.vy > 0.0:
				target = WALL_SLIDE_MAX
			elif f.drop_t > 0 and f.vy > 0.0:
				target = FAST_FALL
			f.vy = move_toward(f.vy, target, g)
		if f.want_jump:
			var jumped := true
			if f.on_ground and f.drop_t > 0 and not box_hits_solid(f.x, f.y + 1, BODY_W, BODY_H) and _ledge_below(f.x, f.y + BODY_H):
				f.dropping = 8   # down + jump on a ledge: drop through it
				f.y += 1
				f.on_ground = false
				f.coyote = 0
			elif f.coyote > 0:
				f.vy = -JUMP
				f.vx += JUMP_HBOOST * f.move_dir
				f.coyote = 0
				f.on_ground = false
				f.aiming = false
				_event(P.E_JUMP, f.x + HALF_W, f.y + BODY_H, f.id, 0)
			elif f.wall != 0:
				f.vy = -JUMP
				f.vx = -f.wall * WALLJUMP_X
				f.facing = -f.wall
				f.wj_t = 12
				f.aiming = false
				_event(P.E_WALLJUMP, f.x + (BODY_W if f.wall > 0 else 0), f.y + MID_Y, f.id, 1 if f.wall > 0 else 0)
				f.wall = 0
			else:
				jumped = false
			if jumped or f.jump_buf <= 0:
				f.want_jump = false
			else:
				f.jump_buf -= 1
	if f.hold_jump > 0:
		f.hold_jump -= 1
	if f.drop_t > 0:
		f.drop_t -= 1
	if f.dropping > 0:
		f.dropping -= 1
	if _move_h(f, f.vx):
		f.vx = 0.0
	if _move_v(f, f.vy):
		f.vy = 0.0
	f.x = posmod(f.x, W)
	f.y = posmod(f.y, H)
	_fighter_zones(f)

func _brain(f: Fighter) -> void:
	if f.shoot_cd > 0:
		f.shoot_cd -= 1
	var tgt: Fighter = _nearest_enemy(f)
	f.think_t -= 1
	if f.think_t <= 0:
		f.think_t = rng.randi_range(10, 36)
		if tgt != null and rng.randf() < 0.75:
			var dx := wrap_d(f.x, tgt.x, W)
			var dy := wrap_d(f.y, tgt.y, H)
			if f.arrows == 0:
				var st: Arrow = _nearest_loose_arrow(f)
				if st != null:
					dx = wrap_d(f.x + HALF_W, st.x, W)
					dy = wrap_d(f.y + BODY_H, st.y, H)
			f.move_dir = (1 if dx > 0.0 else -1) if absf(dx) > 50.0 else rng.randi_range(-1, 1)
			if dy < -80.0 and rng.randf() < 0.7:
				f.want_jump = true
				f.hold_jump = rng.randi_range(6, 16)
			if dy > 100.0 and rng.randf() < 0.5:
				f.drop_t = 12
				f.want_jump = true
		else:
			f.move_dir = rng.randi_range(-1, 1)
			if rng.randf() < 0.35:
				f.want_jump = true
				f.hold_jump = 14
	if f.move_dir != 0 and f.on_ground and box_hits_solid(f.x + f.move_dir * 4, f.y, BODY_W, BODY_H):
		f.want_jump = true
		f.hold_jump = 16
	if f.wall != 0 and rng.randf() < 0.1:
		f.want_jump = true
		f.hold_jump = 12
	# falling next to a wall: lean into it now and then (wall slides, ledge grabs)
	if not f.on_ground and f.vy > 2.0 and f.state == P.F_NORMAL and rng.randf() < 0.3:
		for dir in [-1, 1]:
			if box_hits_solid(f.x + dir * 30, f.y, BODY_W, BODY_H):
				f.move_dir = dir
				break
	if f.state != P.F_DODGE and f.dodge_cd == 0:
		if (rng.randf() < 0.4 and _arrow_incoming(f)) or rng.randf() < 0.004:
			_start_dodge(f, DODGE_DIRS[rng.randi() % DODGE_DIRS.size()])
			return
	if tgt != null and f.arrows > 0 and f.shoot_cd == 0 and f.state != P.F_DODGE and rng.randf() < 0.05:
		var ax := wrap_d(f.x, tgt.x, W)
		var ay := wrap_d(f.y, tgt.y, H) - 20.0
		_shoot(f, atan2(ay, ax) + rng.randf_range(-0.12, 0.12), _pick_kind() if power_arrows else P.A_NORMAL)
		f.shoot_cd = rng.randi_range(20, 50)

func _pick_kind() -> int:
	var total := 0
	for w in kind_weights:
		total += w
	var r := rng.randi() % total
	for i in kind_weights.size():
		r -= kind_weights[i]
		if r < 0:
			return i
	return 0

func _nearest_enemy(f: Fighter) -> Fighter:
	var best: Fighter = null
	var bd := INF
	for o in fighters:
		if o == f or o.state == P.F_DEAD:
			continue
		var dx := wrap_d(f.x, o.x, W)
		var dy := wrap_d(f.y, o.y, H)
		var d := dx * dx + dy * dy
		if o.in_smoke and d > 22500.0:
			continue
		if d < bd:
			bd = d
			best = o
	return best

func _nearest_loose_arrow(f: Fighter) -> Arrow:
	var best: Arrow = null
	var bd := INF
	for a in arrows:
		if a.dead or a.state != P.S_STUCK or a.fuse > 0:
			continue
		var dx := wrap_d(f.x + HALF_W, a.x, W)
		var dy := wrap_d(f.y + BODY_H, a.y, H)
		var d := dx * dx + dy * dy
		if d < bd:
			bd = d
			best = a
	return best

func _arrow_incoming(f: Fighter) -> bool:
	var cx := float(f.x + HALF_W)
	var cy := float(f.y + MID_Y)
	for a in arrows:
		if a.dead or a.state != P.S_FLY or a.owner == f.id:
			continue
		var dx := wrap_d(a.x, cx, W)
		var dy := wrap_d(a.y, cy, H)
		if dx * dx + dy * dy < 40000.0 and dx * a.vx + dy * a.vy > 0.0:
			return true
	return false

# A dodge the way d points (8 ways; nothing = the way the fighter faces). On the
# ground a downward dodge becomes a faster slide along the floor.
func _start_dodge(f: Fighter, d: Vector2) -> void:
	if d == Vector2.ZERO:
		d = Vector2(float(f.facing), 0.0)
	var slide := f.on_ground and d.y > 0.0
	if slide:
		d = Vector2(signf(d.x) if d.x != 0.0 else float(f.facing), 0.0)
	d = d.normalized()
	f.state = P.F_DODGE
	f.state_t = 0
	f.dodge_t = DODGE_TICKS
	f.dodge_jump_t = DODGE_JUMP_TICKS if f.on_ground else 0
	f.catch_t = 0
	f.aiming = false
	f.rolling = f.on_ground and d.y == 0.0
	var speed := DODGE_SPEED * (DODGE_SLIDE_MULT if slide else 1.0)
	f.vx = d.x * speed
	f.vy = d.y * speed
	if d.x > 0.0:
		f.facing = 1
	elif d.x < 0.0:
		f.facing = -1
	_event(P.E_DODGE, f.x + HALF_W, f.y + MID_Y, f.id, posmod(roundi(rad_to_deg(d.angle()) / 45.0), 8))

# A person's shot snaps to an enemy within AIM_HELP_R and AIM_HELP_DEG of the
# aim, with nothing solid in between (TowerFall's auto-lock, D5).
func _aim_help(f: Fighter, ang: float) -> float:
	var ox := float(f.x + HALF_W)
	var oy := float(f.y + ARROW_Y)
	var best := ang
	var bd := INF
	for o in fighters:
		if o == f or o.state == P.F_DEAD:
			continue
		var dx := wrap_d(ox, o.x + HALF_W, W)
		var dy := wrap_d(oy, o.y + MID_Y, H)
		var d2 := dx * dx + dy * dy
		if d2 > AIM_HELP_R * AIM_HELP_R or d2 >= bd:
			continue
		var a2 := atan2(dy, dx)
		if absf(angle_difference(ang, a2)) > deg_to_rad(AIM_HELP_DEG):
			continue
		if _line_blocked(ox, oy, dx, dy):
			continue
		bd = d2
		best = a2
	return best

func _shoot(f: Fighter, ang: float, kind: int) -> void:
	f.arrows -= 1
	f.aim = ang
	var a := Arrow.new()
	a.id = _next_arrow_id
	_next_arrow_id = (_next_arrow_id % 65535) + 1
	a.kind = kind
	a.owner = f.id
	var dir := Vector2.from_angle(ang)
	a.x = f.x + HALF_W + dir.x * 30.0
	a.y = f.y + ARROW_Y + dir.y * 30.0
	a.vx = dir.x * ARROW_SPEED
	a.vy = dir.y * ARROW_SPEED
	a.ang = ang
	a.state = P.S_FLY
	arrows.append(a)
	_event(P.E_SHOOT, int(a.x), int(a.y), f.id, kind)

func _stomps() -> void:
	var n := fighters.size()
	for i in n:
		var a: Fighter = fighters[i]
		if a.state == P.F_DEAD:
			continue
		for j in range(i + 1, n):
			var b: Fighter = fighters[j]
			if b.state == P.F_DEAD or a.state == P.F_DEAD:
				continue
			var dx := wrap_d(a.x, b.x, W)
			var dy := wrap_d(a.y, b.y, H)
			if absf(dx) >= BODY_W or absf(dy) >= BODY_H:
				continue
			if dy >= 20.0 and a.vy > 0.0:
				_kill(b, a.id, 3)
				b.vy = 4.0
				b.vx = 0.0
				a.vy = -JUMP
				_event(P.E_JUMP, a.x + HALF_W, a.y + BODY_H, a.id, 1)
			elif dy <= -20.0 and b.vy > 0.0:
				_kill(a, b.id, 3)
				a.vy = 4.0
				a.vx = 0.0
				b.vy = -JUMP
				_event(P.E_JUMP, b.x + HALF_W, b.y + BODY_H, b.id, 1)
			elif absf(a.vx - b.vx) > 9.0 and a.state != P.F_HURT and b.state != P.F_HURT:
				var slow: Fighter = a if absf(a.vx) < absf(b.vx) else b
				var fast: Fighter = b if slow == a else a
				_hurt(slow, signf(fast.vx) * 10.0, -7.0)
			else:
				var push := 2.0 if dx >= 0.0 else -2.0
				a.vx -= push
				b.vx += push

# ------------------------------------------------------------------ arrows
func _update_arrow(a: Arrow) -> void:
	if a.dead:
		return
	a.t += 1
	if a.state == P.S_STUCK:
		a.stuck_t += 1
		if a.fuse > 0:
			a.fuse -= 1
			if a.fuse == 0:
				a.dead = true
				_explode(a.x, a.y, a.owner)
		return
	if a.state == P.S_FALL or a.t > ARROW_STRAIGHT:
		a.vy = minf(a.vy + ARROW_GRAVITY, ARROW_MAX_FALL)
		a.vx = move_toward(a.vx, 0.0, ARROW_DRAG)
	if a.vx != 0.0 or a.vy != 0.0:
		a.ang = atan2(a.vy, a.vx)
	var steps := maxi(1, ceili(maxf(absf(a.vx), absf(a.vy)) / 4.0))
	var sx := a.vx / steps
	var sy := a.vy / steps
	for i in steps:
		var nx := a.x + sx
		var ny := a.y + sy
		var c: int = level.cell_at(nx, ny)
		if c == 1 or (c == 2 and sy > 0.0 and floori(a.y / 30.0) < floori(ny / 30.0)):
			var floor_hit := sy > 0.0 and absf(sy) >= absf(sx)
			_arrow_hit_wall(a, floor_hit, floori(ny / 30.0) * 30.0)
			return
		a.x = fposmod(nx, W)
		a.y = fposmod(ny, H)
		if a.state == P.S_FLY and _arrow_hit_fighters(a):
			return

func _arrow_hit_wall(a: Arrow, floor_hit: bool, surface_y: float) -> void:
	var was_flying := a.state == P.S_FLY
	a.state = P.S_STUCK
	a.stuck_t = 0
	a.vx = 0.0
	a.vy = 0.0
	if not was_flying:
		return
	_event(P.E_STICK, int(a.x), int(a.y), a.kind, 1 if floor_hit else 0)
	if a.kind == P.A_FIRE:
		if floor_hit:
			_add_zone(P.Z_FIRE, a.x, surface_y, FIRE_WIDTH, FIRE_TICKS)
		else:
			_add_zone(P.Z_FIRE, a.x, a.y + 20.0, 60.0, FIRE_TICKS / 2)
		_event(P.E_IGNITE, int(a.x), int(surface_y if floor_hit else a.y), 1 if floor_hit else 0, 0)
	elif a.kind == P.A_BOMB:
		a.fuse = BOMB_FUSE
	elif a.kind == P.A_MIASMA:
		_add_zone(P.Z_MIASMA, a.x, a.y, MIASMA_R, MIASMA_TICKS)
		_event(P.E_MIASMA, int(a.x), int(a.y), 0, 0)
	elif a.kind == P.A_SMOKE:
		_add_zone(P.Z_SMOKE, a.x, a.y, SMOKE_R, SMOKE_TICKS)
		_event(P.E_SMOKE, int(a.x), int(a.y), 0, 0)

func _arrow_hit_fighters(a: Arrow) -> bool:
	for f in fighters:
		if f.state == P.F_DEAD or (f.id == a.owner and a.t < ARROW_NO_SELF):
			continue
		var dx := wrap_d(f.x, a.x, W)
		var dy := wrap_d(f.y, a.y, H)
		if dx < -4.0 or dx > BODY_W + 4.0 or dy < -4.0 or dy > BODY_H + 4.0:
			continue
		if f.state == P.F_DODGE:
			a.dead = true
			f.arrows = mini(MAX_QUIVER, f.arrows + 1)
			f.catch_t = CATCH_HOLD
			_event(P.E_CATCH, int(a.x), int(a.y), f.id, a.kind)
			return true
		_kill(f, a.owner, 1)
		f.vx = a.vx * 0.45
		f.vy = -7.0 + a.vy * 0.3
		if a.kind == P.A_SMOKE:
			_add_zone(P.Z_SMOKE, a.x, a.y, SMOKE_R, SMOKE_TICKS)
			_event(P.E_SMOKE, int(a.x), int(a.y), 0, 0)
		if a.kind == P.A_BOMB:
			a.dead = true
			_explode(a.x, a.y, a.owner)
		elif a.kind == P.A_MIASMA:
			a.dead = true
			_add_zone(P.Z_MIASMA, a.x, a.y, MIASMA_R, MIASMA_TICKS)
			_event(P.E_MIASMA, int(a.x), int(a.y), 0, 0)
		else:
			if a.kind == P.A_FIRE:
				_add_zone(P.Z_FIRE, a.x, f.y + BODY_H, 90.0, FIRE_TICKS / 2)
				_event(P.E_IGNITE, int(a.x), f.y + BODY_H, 1, 0)
			a.state = P.S_FALL
			a.vx *= -0.15
			a.vy = -8.0
		return true
	return false

func _explode(x: float, y: float, owner: int) -> void:
	_event(P.E_EXPLODE, int(x), int(y), owner, 0)
	var r2 := EXPLODE_R * EXPLODE_R
	for f in fighters:
		if f.state == P.F_DEAD:
			continue
		var dx := wrap_d(x, f.x + HALF_W, W)
		var dy := wrap_d(y, f.y + MID_Y, H)
		var fd2 := dx * dx + dy * dy
		var fd := maxf(1.0, sqrt(fd2))
		if fd2 <= r2:
			_kill(f, owner, 2)
			f.vx = dx / fd * 16.0
			f.vy = -12.0
		elif fd2 <= r2 * 3.2:
			_hurt(f, dx / fd * 14.0, -9.0)
	for a in arrows:
		if a.dead:
			continue
		var dx := wrap_d(x, a.x, W)
		var dy := wrap_d(y, a.y, H)
		var d2 := dx * dx + dy * dy
		if d2 < 25600.0 and d2 > 1.0:
			var d := sqrt(d2)
			a.state = P.S_FALL
			a.vx = dx / d * 12.0
			a.vy = dy / d * 12.0 - 6.0

func _tinks() -> void:
	var flying: Array = []
	for a in arrows:
		if not a.dead and a.state == P.S_FLY:
			flying.append(a)
	var n := flying.size()
	for i in n:
		var a: Arrow = flying[i]
		for j in range(i + 1, n):
			var b: Arrow = flying[j]
			if a.state != P.S_FLY or b.state != P.S_FLY:
				continue
			var dx := wrap_d(a.x, b.x, W)
			var dy := wrap_d(a.y, b.y, H)
			if dx * dx + dy * dy < 144.0 and a.vx * b.vx + a.vy * b.vy < 0.0:
				a.state = P.S_FALL
				b.state = P.S_FALL
				a.vy = -6.0
				b.vy = -6.0
				_event(P.E_TINK, int(a.x), int(a.y), 0, 0)

func _pickups() -> void:
	for f in fighters:
		if f.state == P.F_DEAD or f.arrows >= MAX_QUIVER:
			continue
		var cx := float(f.x + HALF_W)
		var cy := float(f.y + MID_Y)
		for a in arrows:
			if a.dead or a.state != P.S_STUCK or a.stuck_t < PICKUP_DELAY or a.fuse > 0:
				continue
			if absf(wrap_d(cx, a.x, W)) < 50.0 and absf(wrap_d(cy, a.y, H)) < 68.0:
				a.dead = true
				f.arrows += 1
				_event(P.E_PICKUP, int(a.x), int(a.y), f.id, a.kind)
				if f.arrows >= MAX_QUIVER:
					break

func _enforce_cap() -> void:
	var stuck := 0
	for a in arrows:
		if not a.dead and a.state == P.S_STUCK and a.fuse < 0:
			stuck += 1
	if stuck <= arrow_cap:
		return
	for a in arrows:
		if not a.dead and a.state == P.S_STUCK and a.fuse < 0:
			a.dead = true
			stuck -= 1
			if stuck <= arrow_cap:
				return

# ------------------------------------------------------------------ zones
func _add_zone(kind: int, x: float, y: float, size: float, life: int) -> void:
	if zones.size() >= MAX_ZONES:
		zones.remove_at(0)
	var z := Zone.new()
	z.kind = kind
	z.x = x
	z.y = y
	z.size = size
	z.life = life
	z.max_life = life
	zones.append(z)

func _update_zones() -> void:
	for i in range(zones.size() - 1, -1, -1):
		zones[i].life -= 1
		if zones[i].life <= 0:
			zones.remove_at(i)

func _fighter_zones(f: Fighter) -> void:
	var in_fire := false
	var in_miasma := false
	var in_smoke := false
	var fx := float(f.x + HALF_W)
	var feet := float(f.y + BODY_H)
	for z in zones:
		if z.kind == P.Z_FIRE:
			if absf(wrap_d(z.x, fx, W)) < z.size * 0.5 and absf(wrap_d(z.y, feet, H)) < 14.0:
				in_fire = true
		else:
			var dx := wrap_d(z.x, fx, W)
			var dy := wrap_d(z.y, f.y + MID_Y, H)
			if dx * dx + dy * dy < z.size * z.size:
				if z.kind == P.Z_SMOKE:
					in_smoke = true
				else:
					in_miasma = true
	f.in_smoke = in_smoke
	f.burn_t = f.burn_t + 1 if in_fire else 0
	f.miasma_t = f.miasma_t + 1 if in_miasma else 0
	if f.burn_t >= FIRE_KILL_TICKS:
		_kill(f, 255, 4)
	elif f.miasma_t >= MIASMA_KILL_TICKS:
		_kill(f, 255, 5)

# ------------------------------------------------------------------ snapshot
func live_arrow_count() -> int:
	var n := 0
	for a in arrows:
		if not a.dead:
			n += 1
	return n

# The whole state for the clients (the format: proto.gd). head carries the
# match: phase, round, left (ticks), goal, winner; the benchmark passes none.
func write_snapshot(buf: StreamPeerBuffer, evs: Array, head: Dictionary = {}) -> void:
	buf.clear()
	buf.put_u8(P.T_SNAP)
	buf.put_u32(tick)
	buf.put_u8(int(head.get("phase", P.PH_PLAY)))
	buf.put_u8(int(head.get("round", 0)))
	buf.put_u16(clampi(int(head.get("left", 0)), 0, 65535))
	buf.put_u8(int(head.get("goal", 0)))
	buf.put_u8(int(head.get("winner", P.NO_ONE)))
	buf.put_u8(fighters.size())
	buf.put_u16(live_arrow_count())
	buf.put_u8(zones.size())
	buf.put_u16(evs.size())
	for f in fighters:
		buf.put_u8(f.id)
		buf.put_u8(f.state)
		buf.put_16(f.x)
		buf.put_16(f.y)
		buf.put_8(clampi(roundi(f.vx), -127, 127))
		buf.put_8(clampi(roundi(f.vy), -127, 127))
		var pulling: bool = f.state == P.F_LEDGE and f.ledge_t <= 8
		var flags := (1 if f.facing > 0 else 0) | (2 if f.on_ground else 0) | (4 if f.wall != 0 else 0) \
			| (8 if f.burn_t > 0 else 0) | (16 if f.miasma_t > 0 else 0) \
			| (32 if (f.state == P.F_DODGE and f.rolling) or pulling else 0) | (64 if f.wj_t > 0 else 0) | (128 if f.in_smoke else 0)
		buf.put_u8(flags)
		buf.put_u8(int(fposmod(f.aim, TAU) / TAU * 256.0) & 255)
		buf.put_u8(f.arrows)
		buf.put_u8(mini(f.state_t, 255))
		buf.put_u8(mini(f.points, 255))
		buf.put_u8((P.F2_BOT if f.bot else 0) | (P.F2_AIMING if f.aiming else 0) | (0 if f.connected else P.F2_AWAY))
	for a in arrows:
		if a.dead:
			continue
		buf.put_u16(a.id)
		buf.put_u8(a.kind | (a.state << 4))
		buf.put_16(int(a.x))
		buf.put_16(int(a.y))
		buf.put_u8(int(fposmod(a.ang, TAU) / TAU * 256.0) & 255)
	for z in zones:
		buf.put_u8(z.kind)
		buf.put_16(int(z.x))
		buf.put_16(int(z.y))
		buf.put_u16(int(z.size))
		buf.put_u8(clampi(int(255.0 * z.life / z.max_life), 0, 255))
		buf.put_u8(0)
	for e in evs:
		buf.put_u8(e[0])
		buf.put_16(e[1])
		buf.put_16(e[2])
		buf.put_u8(e[3] & 255)
		buf.put_u8(e[4] & 255)

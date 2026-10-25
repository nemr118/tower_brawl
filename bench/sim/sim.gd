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
# is played by the bot brain (sim/brain.gd, G6), which presses buttons through
# apply_input too. P1 (2026-10-10, first-playable-plan.md).
# The game turns on the purple walls (walls_start, TowerFall's miasma): from 25 s
# after FIGHT they close in from the left and right edges and end a long round.
# P2: the client runs a copy for its own fighter (client/predict.gd) with
# `predicting` on: no deaths, no pickups, and an arrow that reaches a fighter
# stops there instead of hitting (the server settles all of those).
# p4.9 power-ups (the user, 2026-10-24): an orb's lightning builds up over a random
# floor spot, strikes (anyone close dies, the electricity runs through them), and the
# orb waits there; touch it and it is yours. The regular ones last the match (keep):
# an arrow kind (the newest wins), SHIELD, INFINITE ARROWS, FLYING, BIG ARROWS. BIG
# ones come near a person behind the leader (Mario Kart's help from the back) and run
# this round: GHOST CATS, RAIN, INVISIBLE, FREEZE, SPIKED SHIELD, SUPER SPEED. Every
# power-up that moves or arms a fighter lives in its Fighter (write_fighter_state),
# so the client's copy predicts it.
# ==============================================================================
extends RefCounted

const P = preload("res://sim/proto.gd")
const LevelScript = preload("res://sim/level.gd")
const BrainScript = preload("res://sim/brain.gd")

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
const ARROW_SPEED := 16.0           # p4.4: a lob, slower than TowerFall's 4.0 * S (Arrow.cs SPEED) so the arc shows
const ARROW_LOB_G := 0.2            # p4.4: a flying arrow falls from the moment it leaves the bow (the user's pick:
                                    # a true arc; TowerFall flies straight 25 ticks first): at 45 degrees it reaches 1 280 px
const ARROW_GRAVITY := 0.2 * S      # GRAVITY (a falling arrow: knocked out of its flight)
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
const BOT_WAIT_MIN := 60            # after FIGHT a bot stands still 1 to 1.5 s, then plays (ours: the
const BOT_WAIT_MAX := 90            # benchmark's brain shot or stomped within 0.1 s, before a person could move)
const WALLS_HALF := 960.0           # a purple wall's reach is a share of half the arena (Miasma.cs: 160 of 320)
const WALLS_DEADLY := 120           # the walls kill from 2 s after they appear
const WALLS_EDGE := 22              # the deadly part stops this far inside the drawn edge (Miasma.cs: 5 px)
const WALLS_GONE := -0.1            # the share before they come and after they melt
# The walls' steps, back to back: [ticks, from, to, ease] (ease 0: fast then slow,
# 1: slow, fast, slow; 2: slow then fast). They reach a third of the way in 9 s,
# pull back to 15% in 3 s, then close all the way (105%) in 11 s, then go in 4 s.
const WALLS_STEPS := [[540, -0.1, 0.33, 0], [180, 0.33, 0.15, 0], [660, 0.15, 1.05, 1], [240, 1.05, -0.1, 2]]
const WALLS_KEEP_AWAY := 240        # a bot keeps this far from a wall's edge
const SMOKE_R := 288.0              # p4.9: 25% bigger (was 230): standing in it, you cannot see anyone
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
# p4.9 power-ups: an orb's warning builds up PU_WARN ticks, then the bolt strikes
# (anyone within STRIKE_R of the orb dies) and the orb waits PU_LIFE ticks to be taken;
# PU_GAP after it is taken or gone, the next warning starts (the first PU_FIRST after FIGHT).
const PU_FIRST := 60
const PU_WARN := 150
const PU_GAP := 180
const PU_LIFE := 600
const STRIKE_R := 80.0
const ORB_R := 30.0
const ORB_UP := 34                  # the orb's middle sits this far above its floor spot
const BIG_CHANCE := 0.3             # a drop is BIG this often with a person 1 point behind the leader (+0.15 a point more)
const REGULAR_W := {P.PU_FIRE: 13, P.PU_BOMB: 13, P.PU_POISON: 12, P.PU_SMOKE: 12, P.PU_SHIELD: 14,
	P.PU_INF: 12, P.PU_FLY: 11, P.PU_BIG: 13}
const BIG_KINDS := [P.PU_CATS, P.PU_RAIN, P.PU_INVIS, P.PU_FREEZE, P.PU_SPIKES, P.PU_SPEED]
const FLY_MAX := 1.4 * S            # FLYING: the stick floats the fighter this fast, any way
const FLY_ACCEL := 0.12 * S
const SLOW_MULT := 0.55             # RAIN: everyone else runs at this share of their speed
const SPEED_MULT := 1.6             # SUPER SPEED
const FREEZE_TICKS := 150
const RAIN_TICKS := 480
const INVIS_TICKS := 720
const INVIS_CYCLE := 240            # INVISIBLE blinks: of each 4 s, 3 s out of sight, 1 s seen
const INVIS_SEEN := 60
const SPEED_TICKS := 600
const SPIKES_TICKS := 1200
const SPIKE_REGEN := 180
const CATS_N := 3
const CAT_TICKS := 420
const CAT_SPEED := 4.0              # a ghost cat starts this fast, speeds up by CAT_ACCEL a tick to CAT_MAX (a run is 6.75)
const CAT_MAX := 7.2
const CAT_ACCEL := 0.05
const CAT_R := 26.0
const BIG_FX := 1.75                # BIG ARROWS: a blast, a fire or a cloud this much wider (3 times the area)
const BIG_REACH := 22.0             # and the arrow meets a fighter this much farther out (it is drawn 3 times as big)

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
	var aiming: bool = false    # the bow is up (you stand still on the ground)
	var drawn: bool = false     # p4.4: shoot is held: a draw is on, through jumps, ledges, dodges and knocks
	var shot_wait: bool = false # p4.4: let go while the bow could not be up: it fires the first tick it can
	var shot_aim: float = 0.0   # and its aim, as it was let go
	var points: int = 0         # the server copies the seat's points here for the snapshot
	var killer: int = 255       # who killed this fighter (255: the arena itself)
	var dead_t: int = 0
	var burn_t: int = 0
	var miasma_t: int = 0
	var think_t: int = 0        # the bot brain
	var wait_t: int = 0         # the brain does nothing until this counts down (set at a round's start)
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
	var mind = null             # the bot brain's memory (sim/brain.gd Mind)
	var level: int = 0          # the brain's level (sim/brain.gd: OLD, EASY, NORMAL, HARD)
	var vdir: int = 0           # p4.9: the stick up (-1, or jump) or down (1): FLYING floats that way
	var pw_kind: int = 0        # p4.9 power-ups: the arrow kind every shot takes (0: plain)
	var shield: int = 0         # SHIELD: arrows it still takes (0 or 1)
	var inf: bool = false       # INFINITE ARROWS
	var fly: bool = false       # FLYING
	var big: bool = false       # BIG ARROWS
	var freeze_t: int = 0       # frozen this many more ticks (someone's FREEZE): no buttons
	var slow_t: int = 0         # slowed this many more ticks (someone's RAIN)
	var speed_t: int = 0        # SUPER SPEED ticks left
	var invis_t: int = 0        # INVISIBLE ticks left
	var umbrella_t: int = 0     # its RAIN's ticks left: not slowed, a stomp bounces off
	var spikes_t: int = 0       # SPIKED SHIELD ticks left
	var spike_up: bool = false  # the spiked shield is up
	var spike_regen: int = 0    # ticks until it is back after an arrow

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
	var big: bool = false       # p4.9 BIG ARROWS

class Orb:
	var serial: int = 0         # a number of its own (the brain remembers what it decided about it)
	var kind: int = 0           # proto PU_*
	var big: bool = false
	var state: int = 0          # proto ORB_WARN, ORB_LIVE
	var t: int = 0              # ticks in this state
	var x: float = 0.0          # its middle
	var y: float = 0.0
	var for_seat: int = -1      # a BIG one: the person it came for

class Cat:
	var owner: int = 0
	var target: int = 0
	var x: float = 0.0
	var y: float = 0.0
	var vx: float = 0.0
	var vy: float = 0.0
	var t: int = 0

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
var walls_start := 0            # the game: the purple walls come this many ticks after FIGHT (0: never, the benchmark)
var play_t := 0                 # ticks since FIGHT (counts while not frozen; start_round sets 0)
var walls_share := WALLS_GONE   # how far each wall reaches, a share of half the arena (0 or below: not there)
var walls_melt_t := -1          # ticks into the melt once the round is decided (-1: not melting)
var walls_melt_from := WALLS_GONE
var predicting := false         # the client's copy (P2): no deaths, no pickups, an arrow stops at a fighter
var bot_level := 2              # the level of the bot fighters a round makes (sim/brain.gd: NORMAL; the
                                # lobby's BOTS level; the benchmark's own 8 bots stay OLD)
var fixed_spots: Array = []     # a test knob (the server's --spots): fighter i always starts on spawns[fixed_spots[i]]
var rng := RandomNumberGenerator.new()
var _next_arrow_id: int = 1
var kind_weights: Array = [30, 17, 17, 17, 19]   # normal, fire, bomb, miasma, smoke
var powerups := false           # p4.9: power-up orbs drop (the lobby's POWER-UPS)
var orbs: Array = []            # Orb: one waits at a time
var cats: Array = []            # Cat
var pu_wait := PU_FIRST         # ticks until the next orb's warning (counts while no orb waits)
var pu_last := 0                # the last regular kind (never twice in a row)
var pu_last_big := 0
var pu_last_x := -9999.0        # the last drop's spot (the next one lands away from it)
var big_round := false          # a BIG one came this round (one a round)
var keep := {}                  # seat -> [pw_kind, shield, inf, fly, big]: the match's power-ups, back each round
var rain_owner := -1
var rain_t := 0
var spots: Array = []           # where an orb may land: feet spots on floors and ledges (for spots_level)
var spots_level := -1
var _orb_serial := 0

func _init(n_fighters: int = 8, cap: int = 24, seed_value: int = 7) -> void:
	level = LevelScript.new()
	arrow_cap = cap
	rng.seed = seed_value
	for i in n_fighters:
		var f := Fighter.new()
		f.id = i
		fighters.append(f)
		_respawn(f)

# The arena (sim/level.gd LAYOUTS; 0 the bench arena, the default). The server
# sets it before each round; the client's copies follow the snapshot's arena.
func set_arena(n: int) -> void:
	if level.id != n:
		level = LevelScript.new(n)

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
	if not frozen:
		play_t += 1
	if not frozen:
		for f in fighters:
			if f.bot and f.state != P.F_DEAD:
				_brain(f)
	for f in fighters:
		_update_fighter(f)
	_stomps()
	for a in arrows:
		_update_arrow(a)
	_tinks()
	_pickups()
	_update_powers()
	_update_zones()
	_update_walls()
	_enforce_cap()
	for i in range(arrows.size() - 1, -1, -1):
		if arrows[i].dead:
			arrows.remove_at(i)

func _event(type: int, x: int, y: int, a: int, b: int) -> void:
	events.append([type, x, y, a, b])

# ------------------------------------------------------------------ the match
# A round: one fighter per seat in seat_list ([{"id": seat, "bot": true/false},
# and "level" for a bot whose brain level is not bot_level]),
# each on its own spawn spot, with a full quiver. Arrows and zones go; the tick
# keeps counting (the clients' clock follows it).
func start_round(seat_list: Array) -> void:
	fighters.clear()
	arrows.clear()
	zones.clear()
	events.clear()
	_reset_walls()
	_reset_powers_round()
	var starts: Array = level.spawns.duplicate()
	for i in range(starts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = starts[i]
		starts[i] = starts[j]
		starts[j] = tmp
	if not fixed_spots.is_empty():
		starts.clear()
		for k in fixed_spots:
			starts.append(level.spawns[int(k) % level.spawns.size()])
	for i in seat_list.size():
		var f := Fighter.new()
		f.id = int(seat_list[i]["id"])
		f.bot = bool(seat_list[i]["bot"])
		f.level = int(seat_list[i].get("level", bot_level))
		fighters.append(f)
		_place(f, starts[i % starts.size()])
		f.wait_t = rng.randi_range(BOT_WAIT_MIN, BOT_WAIT_MAX)   # only the brain reads it; it counts from FIGHT
		_give_kept(f)

func clear() -> void:
	fighters.clear()
	arrows.clear()
	zones.clear()
	events.clear()
	_reset_walls()
	_reset_powers_round()

# p4.9: a new match (or the lobby): the power-ups kept for the match go.
func reset_powers() -> void:
	keep.clear()

func _reset_powers_round() -> void:
	orbs.clear()
	cats.clear()
	rain_owner = -1
	rain_t = 0
	pu_wait = PU_FIRST
	big_round = false

func _reset_walls() -> void:
	play_t = 0
	walls_share = WALLS_GONE
	walls_melt_t = -1
	walls_melt_from = WALLS_GONE

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
# (held: drawn, and the bow up whenever the fighter can; let go: the shot, at
# once or the first tick it can; with B_CANCEL: no shot), and a dodge the way
# the stick points. p4.4: a let-go shoot always fires (the user: about half the
# shots never left the bow): a jump, a ledge grab or a dodge no longer drops it.
func apply_input(f: Fighter, buttons: int, aim: int) -> void:
	var prev := f.buttons
	f.buttons = buttons
	f.aim = fposmod(aim * TAU / 3600.0, TAU)
	f.vdir = (1 if buttons & P.B_DOWN else 0) - (1 if buttons & (P.B_UP | P.B_JUMP) else 0)
	if f.state == P.F_DEAD or frozen or f.freeze_t > 0:
		f.move_dir = 0
		if f.freeze_t > 0:      # p4.9 FREEZE: frozen solid: no run, jump, shot or dodge
			f.vdir = 0
			f.drawn = false
			f.aiming = false
			f.shot_wait = false
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
		f.drawn = true
		if not f.aiming and f.state == P.F_NORMAL:
			f.aiming = true
	elif f.drawn:
		f.drawn = false
		f.aiming = false
		if buttons & P.B_CANCEL:
			pass                # let go inside the ring (or a bot lowering its bow): no arrow
		elif f.state == P.F_NORMAL:
			_fire(f, f.aim)
		else:
			f.shot_wait = true  # a dodge, a ledge hang, a knock: the shot leaves the first tick it can
			f.shot_aim = f.aim
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
	f.drawn = false
	f.shot_wait = false
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

func _kill(f: Fighter, killer: int, cause: int) -> void:
	if f.state == P.F_DEAD or predicting:
		return
	f.state = P.F_DEAD
	f.state_t = 0
	f.dead_t = RESPAWN_TICKS
	f.aiming = false
	f.drawn = false
	f.shot_wait = false
	f.killer = killer
	_event(P.E_DEATH, f.x + HALF_W, f.y + MID_Y, f.id, cause)
	_event(P.E_KILL, f.x + HALF_W, f.y + MID_Y, killer if killer >= 0 and killer < 255 else 255, f.id)   # p4.8: who did it

func _update_fighter(f: Fighter) -> void:
	if f.shot_wait and f.state == P.F_NORMAL:   # p4.4: let go in a dodge, a ledge hang or a knock: it fires now
		f.shot_wait = false
		_fire(f, f.shot_aim)
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
	_power_timers(f)
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
	elif f.fly:
		_fly(f)
	else:
		var mult := speed_mult(f)
		var accel := (RUN_ACCEL if f.on_ground else AIR_ACCEL) * mult
		var stand_aim := f.aiming and f.on_ground   # aiming on the ground: you stand still
		if f.move_dir != 0 and not stand_aim:
			f.facing = f.move_dir
			f.vx = move_toward(f.vx, RUN_MAX * mult * f.move_dir, accel)
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
					f.ledge_t = 8   # bots too (G6: a move from the route map replays exactly)
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
				_event(P.E_JUMP, f.x + HALF_W, f.y + BODY_H, f.id, 0)
			elif f.wall != 0:
				f.vy = -JUMP
				f.vx = -f.wall * WALLJUMP_X
				f.facing = -f.wall
				f.wj_t = 12
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

# p4.9: the power-ups' clocks, one tick (a living fighter's).
func _power_timers(f: Fighter) -> void:
	if f.freeze_t > 0:
		f.freeze_t -= 1
	if f.slow_t > 0:
		f.slow_t -= 1
	if f.speed_t > 0:
		f.speed_t -= 1
	if f.invis_t > 0:
		f.invis_t -= 1
	if f.umbrella_t > 0:
		f.umbrella_t -= 1
	if f.spikes_t > 0:
		f.spikes_t -= 1
		if f.spike_regen > 0:
			f.spike_regen -= 1
			if f.spike_regen == 0:
				f.spike_up = true
		if f.spikes_t == 0:
			f.spike_up = false

# The share of its run speed a fighter has now: RAIN slows (not the umbrella's
# owner), SUPER SPEED speeds up.
static func speed_mult(f: Fighter) -> float:
	return (SLOW_MULT if f.slow_t > 0 and f.umbrella_t <= 0 else 1.0) * (SPEED_MULT if f.speed_t > 0 else 1.0)

# INVISIBLE now: of each INVIS_CYCLE, out of sight the first part, seen INVIS_SEEN.
static func invisible(f: Fighter) -> bool:
	return f.invis_t > 0 and posmod(INVIS_TICKS - f.invis_t, INVIS_CYCLE) < INVIS_CYCLE - INVIS_SEEN

# FLYING (p4.9): no gravity; the stick (jump is up too) moves the body any way at
# FLY_MAX, speeding up and slowing by FLY_ACCEL; no wall slides, ledge grabs or wall
# jumps. Aiming on the ground still stands still; down on a ledge drops through it.
func _fly(f: Fighter) -> void:
	var mult := speed_mult(f)
	var mx: int = 0 if (f.aiming and f.on_ground) else f.move_dir
	if mx != 0:
		f.facing = mx
	if f.aiming:
		f.facing = 1 if cos(f.aim) >= 0.0 else -1
	f.vx = move_toward(f.vx, FLY_MAX * mult * mx, FLY_ACCEL * mult)
	if f.vdir > 0 and f.on_ground and not box_hits_solid(f.x, f.y + 1, BODY_W, BODY_H) and _ledge_below(f.x, f.y + BODY_H):
		f.dropping = 8
		f.y += 1
		f.on_ground = false
	f.vy = move_toward(f.vy, FLY_MAX * mult * f.vdir, FLY_ACCEL * mult)
	f.want_jump = false
	f.wall = 0

# A bot seat's buttons for this tick (sim/brain.gd presses them through
# apply_input). A hook of its own so the probes can time it.
func _brain(f: Fighter) -> void:
	BrainScript.think(self, f)

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

# A let-go shot: an arrow (the aim help on the angle), or a dry fire with an empty quiver.
func _fire(f: Fighter, ang: float) -> void:
	if f.arrows > 0 or f.inf:
		var kind: int = f.pw_kind if f.pw_kind > 0 else (_pick_kind() if power_arrows else P.A_NORMAL)
		_shoot(f, _aim_help(f, ang), kind)
	else:
		_event(P.E_DRYFIRE, f.x + HALF_W, f.y + MID_Y, f.id, 0)

func _shoot(f: Fighter, ang: float, kind: int) -> void:
	if not f.inf:
		f.arrows -= 1
	f.aim = ang
	var a := Arrow.new()
	a.id = _next_arrow_id
	_next_arrow_id = (_next_arrow_id % 65535) + 1
	a.kind = kind
	a.big = f.big
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
				_stomp(a, b)
			elif dy <= -20.0 and b.vy > 0.0:
				_stomp(b, a)
			elif absf(a.vx - b.vx) > 9.0 and a.state != P.F_HURT and b.state != P.F_HURT:
				var slow: Fighter = a if absf(a.vx) < absf(b.vx) else b
				var fast: Fighter = b if slow == a else a
				_hurt(slow, signf(fast.vx) * 10.0, -7.0)
			else:
				var push := 2.0 if dx >= 0.0 else -2.0
				a.vx -= push
				b.vx += push

# top comes down on under's head: a stomp. p4.9: SPIKED SHIELD's spikes kill the
# stomper instead; RAIN's umbrella bounces the stomper off, nobody dies.
func _stomp(top: Fighter, under: Fighter) -> void:
	if under.spikes_t > 0:
		_kill(top, under.id, 9)
		top.vy = -JUMP * 0.6
		return
	if under.umbrella_t > 0:
		top.vy = -JUMP
		_event(P.E_JUMP, top.x + HALF_W, top.y + BODY_H, top.id, 1)
		return
	_kill(under, top.id, 3)
	under.vy = 4.0
	under.vx = 0.0
	top.vy = -JUMP
	_event(P.E_JUMP, top.x + HALF_W, top.y + BODY_H, top.id, 1)

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
				_explode(a.x, a.y, a.owner, BIG_FX if a.big else 1.0)
		return
	if a.state == P.S_FALL:
		a.vy = minf(a.vy + ARROW_GRAVITY, ARROW_MAX_FALL)
		a.vx = move_toward(a.vx, 0.0, ARROW_DRAG)
	else:
		a.vy = minf(a.vy + ARROW_LOB_G, ARROW_MAX_FALL)   # the lob: no drag, a clean arc (brain.fly copies it)
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
	var k := BIG_FX if a.big else 1.0
	if a.kind == P.A_FIRE:
		if floor_hit:
			_add_zone(P.Z_FIRE, a.x, surface_y, FIRE_WIDTH * k, FIRE_TICKS)
		else:
			_add_zone(P.Z_FIRE, a.x, a.y + 20.0, 60.0 * k, FIRE_TICKS / 2)
		_event(P.E_IGNITE, int(a.x), int(surface_y if floor_hit else a.y), 1 if floor_hit else 0, 0)
	elif a.kind == P.A_BOMB:
		a.fuse = BOMB_FUSE
	elif a.kind == P.A_MIASMA:
		_add_zone(P.Z_MIASMA, a.x, a.y, MIASMA_R * k, MIASMA_TICKS)
		_event(P.E_MIASMA, int(a.x), int(a.y), 0, 0)
	elif a.kind == P.A_SMOKE:
		_add_zone(P.Z_SMOKE, a.x, a.y, SMOKE_R * k, SMOKE_TICKS)
		_event(P.E_SMOKE, int(a.x), int(a.y), 0, 0)

func _arrow_hit_fighters(a: Arrow) -> bool:
	for f in fighters:
		if f.state == P.F_DEAD or (f.id == a.owner and a.t < ARROW_NO_SELF):
			continue
		var dx := wrap_d(f.x, a.x, W)
		var dy := wrap_d(f.y, a.y, H)
		var reach := 4.0 + (BIG_REACH if a.big else 0.0)
		if dx < -reach or dx > BODY_W + reach or dy < -reach or dy > BODY_H + reach:
			continue
		if predicting:
			return true   # the client's copy: the arrow waits here for the server's word (a catch or a hit)
		if f.state == P.F_DODGE:
			a.dead = true
			f.arrows = mini(MAX_QUIVER, f.arrows + 1)
			f.catch_t = CATCH_HOLD
			_event(P.E_CATCH, int(a.x), int(a.y), f.id, a.kind)
			return true
		if f.shield > 0 or (f.spikes_t > 0 and f.spike_up):
			_block(f, a)
			return true
		var k := BIG_FX if a.big else 1.0
		_kill(f, a.owner, 1)
		f.vx = a.vx * 0.45
		f.vy = -7.0 + a.vy * 0.3
		if a.kind == P.A_SMOKE:
			_add_zone(P.Z_SMOKE, a.x, a.y, SMOKE_R * k, SMOKE_TICKS)
			_event(P.E_SMOKE, int(a.x), int(a.y), 0, 0)
		if a.kind == P.A_BOMB:
			a.dead = true
			_explode(a.x, a.y, a.owner, k)
		elif a.kind == P.A_MIASMA:
			a.dead = true
			_add_zone(P.Z_MIASMA, a.x, a.y, MIASMA_R * k, MIASMA_TICKS)
			_event(P.E_MIASMA, int(a.x), int(a.y), 0, 0)
		else:
			if a.kind == P.A_FIRE:
				_add_zone(P.Z_FIRE, a.x, f.y + BODY_H, 90.0 * k, FIRE_TICKS / 2)
				_event(P.E_IGNITE, int(a.x), f.y + BODY_H, 1, 0)
			a.state = P.S_FALL
			a.vx *= -0.15
			a.vy = -8.0
		return true
	return false

# A shield takes the arrow (p4.9): the arrow drops off with no blast or cloud. The
# spiked shield first (it comes back after SPIKE_REGEN); SHIELD is used up, for the
# match too.
func _block(f: Fighter, a: Arrow) -> void:
	if f.spikes_t > 0 and f.spike_up:
		f.spike_up = false
		f.spike_regen = SPIKE_REGEN
	else:
		f.shield = 0
		if keep.has(f.id):
			keep[f.id][1] = 0
	a.state = P.S_FALL
	a.vx *= -0.3
	a.vy = -7.0
	a.fuse = -1
	_event(P.E_SHIELD_POP, int(a.x), int(a.y), f.id, a.kind)

# A blast at (x, y): k > 1 for a BIG arrow's (the event's b says so).
func _explode(x: float, y: float, owner: int, k: float = 1.0) -> void:
	_event(P.E_EXPLODE, int(x), int(y), owner, 1 if k > 1.0 else 0)
	var r2 := EXPLODE_R * EXPLODE_R * k * k
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
	if predicting:
		return
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

# ------------------------------------------------------------------ power-ups (p4.9)
# One tick: the rain slows everyone but its owner, the ghost cats hunt, an orb's
# warning turns into the strike, a waiting orb is taken (or fades), and with no orb
# waiting the next one's clock runs. Once the round is decided nothing more happens.
func _update_powers() -> void:
	if predicting or frozen:
		return
	if rain_t > 0:
		rain_t -= 1
		for f in fighters:
			if f.id != rain_owner and f.state != P.F_DEAD:
				f.slow_t = maxi(f.slow_t, rain_t)
	if alive_count() <= 1 and fighters.size() > 1:
		# the round is decided: the power-ups hurt nobody now (as the purple walls melt):
		# the cats go, a warning never strikes
		for c in cats:
			_event(P.E_CAT_POOF, int(c.x), int(c.y), c.owner, 0)
		cats.clear()
		return
	_update_cats()
	if not powerups:
		return
	for i in range(orbs.size() - 1, -1, -1):
		var o: Orb = orbs[i]
		o.t += 1
		if o.state == P.ORB_WARN:
			if o.t >= PU_WARN:
				_strike(o)
		elif o.t >= PU_LIFE:
			_event(P.E_PU_GONE, int(o.x), int(o.y), o.kind, 1 if o.big else 0)
			orbs.remove_at(i)
			pu_wait = PU_GAP
		else:
			var f := _orb_taker(o)
			if f != null:
				orbs.remove_at(i)
				pu_wait = PU_GAP
				_give(f, o.kind)
	if orbs.is_empty() and alive_count() > 1 and walls_melt_t < 0:
		pu_wait -= 1
		if pu_wait <= 0:
			_drop()

# The bolt hits the orb's spot: everyone within STRIKE_R dies (cause 7: the page runs
# the electricity through them), and the orb is there to take.
func _strike(o: Orb) -> void:
	o.state = P.ORB_LIVE
	o.t = 0
	_event(P.E_STRIKE, int(o.x), int(o.y), o.kind, 1 if o.big else 0)
	for f in fighters:
		if f.state == P.F_DEAD:
			continue
		var dx := wrap_d(o.x, f.x + HALF_W, W)
		var dy := wrap_d(o.y, f.y + MID_Y, H)
		if dx * dx + dy * dy <= STRIKE_R * STRIKE_R:
			_kill(f, 255, 7)
			f.vx = signf(dx) * 5.0
			f.vy = -9.0

# The first living fighter touching the orb that may take it, or null.
func _orb_taker(o: Orb) -> Fighter:
	for f in fighters:
		if f.state == P.F_DEAD or not may_take(f, o):
			continue
		if absf(wrap_d(f.x + HALF_W, o.x, W)) < HALF_W + ORB_R and absf(wrap_d(f.y + MID_Y, o.y, H)) < MID_Y + ORB_R:
			return f
	return null

# A BIG orb: a person behind the leader only. FLYING: people only (a bot walks
# its routes). The rest: anyone.
func may_take(f: Fighter, o: Orb) -> bool:
	if o.big:
		return not f.bot and f.points < top_points()
	if o.kind == P.PU_FLY:
		return not f.bot
	return true

# The most points anyone in the round has (the BIG rule).
func top_points() -> int:
	var top := 0
	for f in fighters:
		top = maxi(top, f.points)
	return top

# The power-up is f's: a regular one is kept for the match (keep), a BIG one runs now.
func _give(f: Fighter, kind: int) -> void:
	_event(P.E_PU_GET, f.x + HALF_W, f.y, f.id, kind)
	if kind >= P.PU_FIRE and kind <= P.PU_SMOKE:
		f.pw_kind = kind          # the arrow kinds share the numbers 1..4
	elif kind == P.PU_SHIELD:
		f.shield = 1
	elif kind == P.PU_INF:
		f.inf = true
		f.arrows = maxi(f.arrows, START_QUIVER)
	elif kind == P.PU_FLY:
		f.fly = true
	elif kind == P.PU_BIG:
		f.big = true
	elif kind == P.PU_CATS:
		_send_cats(f)
	elif kind == P.PU_RAIN:
		rain_owner = f.id
		rain_t = RAIN_TICKS
		f.umbrella_t = RAIN_TICKS
		f.slow_t = 0
	elif kind == P.PU_INVIS:
		f.invis_t = INVIS_TICKS
	elif kind == P.PU_FREEZE:
		for o in fighters:
			if o != f and o.state != P.F_DEAD:
				o.freeze_t = FREEZE_TICKS
				o.drawn = false
				o.aiming = false
				o.shot_wait = false
		_event(P.E_FREEZE, f.x + HALF_W, f.y + MID_Y, f.id, 0)
	elif kind == P.PU_SPIKES:
		f.spikes_t = SPIKES_TICKS
		f.spike_up = true
		f.spike_regen = 0
	elif kind == P.PU_SPEED:
		f.speed_t = SPEED_TICKS
	if kind <= P.PU_BIG:
		keep[f.id] = [f.pw_kind, f.shield, f.inf, f.fly, f.big]

# A new round's fighter gets its seat's kept power-ups back (a bot never flies:
# a person's seat played by the brain for a while skips FLYING, the seat keeps it).
func _give_kept(f: Fighter) -> void:
	if not keep.has(f.id):
		return
	var k: Array = keep[f.id]
	f.pw_kind = k[0]
	f.shield = k[1]
	f.inf = k[2]
	f.fly = k[3] and not f.bot
	f.big = k[4]

# GHOST CATS: CATS_N cats leave f, each after one of the nearest enemies (more cats
# than enemies: some share one).
func _send_cats(f: Fighter) -> void:
	var near: Array = []
	for o in fighters:
		if o != f and o.state != P.F_DEAD:
			var dx := wrap_d(f.x, o.x, W)
			var dy := wrap_d(f.y, o.y, H)
			near.append([dx * dx + dy * dy, o.id])
	if near.is_empty():
		return
	near.sort_custom(func(a, b): return a[0] < b[0])
	for k in CATS_N:
		var c := Cat.new()
		c.owner = f.id
		c.target = near[k % near.size()][1]
		c.x = f.x + HALF_W
		c.y = f.y + 10.0
		var ang := -PI / 2.0 + (k - 1) * 0.9
		c.vx = cos(ang) * CAT_SPEED
		c.vy = sin(ang) * CAT_SPEED
		cats.append(c)

# The ghost cats (p4.9, the user's daughter: "sending a cat out at other people"):
# each floats through walls toward its target, faster and faster; touching it kills
# it (cause 8) unless it is dodging (a catch: the cat is gone). A cat whose target
# died hunts the nearest other enemy; after CAT_TICKS it fades.
func _update_cats() -> void:
	for i in range(cats.size() - 1, -1, -1):
		var c: Cat = cats[i]
		c.t += 1
		var tgt := fighter(c.target)
		if tgt == null or tgt.state == P.F_DEAD:
			tgt = _cat_target(c)
			if tgt != null:
				c.target = tgt.id
		if c.t >= CAT_TICKS or tgt == null:
			_event(P.E_CAT_POOF, int(c.x), int(c.y), c.owner, 0)
			cats.remove_at(i)
			continue
		var dx := wrap_d(c.x, tgt.x + HALF_W, W)
		var dy := wrap_d(c.y, tgt.y + MID_Y, H)
		var d := maxf(1.0, sqrt(dx * dx + dy * dy))
		var speed := clampf(CAT_SPEED + c.t * CAT_ACCEL, CAT_SPEED, CAT_MAX)
		c.vx = lerpf(c.vx, dx / d * speed, 0.12)
		c.vy = lerpf(c.vy, dy / d * speed, 0.12)
		c.x = fposmod(c.x + c.vx, W)
		c.y = fposmod(c.y + c.vy, H)
		var reach := CAT_R * (1.6 if tgt.state == P.F_DODGE else 0.5)   # a dodge catches a cat from farther
		if absf(dx) < HALF_W + reach and absf(dy) < MID_Y + reach:
			if tgt.state == P.F_DODGE:
				_event(P.E_CAT_POOF, int(c.x), int(c.y), c.owner, 1)
			else:
				_kill(tgt, c.owner, 8)
				tgt.vy = -6.0
			cats.remove_at(i)

func _cat_target(c: Cat) -> Fighter:
	var best: Fighter = null
	var bd := INF
	for f in fighters:
		if f.id == c.owner or f.state == P.F_DEAD:
			continue
		var dx := wrap_d(c.x, f.x + HALF_W, W)
		var dy := wrap_d(c.y, f.y + MID_Y, H)
		if dx * dx + dy * dy < bd:
			bd = dx * dx + dy * dy
			best = f
	return best

# The next orb: its warning starts over a floor spot. BIG (one a round) when a
# person is behind the leader, more often the further behind, near the person
# furthest behind (but clear of everyone, so its bolt kills nobody); else a regular
# kind, never the last one again, on a random spot away from the last.
func _drop() -> void:
	_ensure_spots()
	if spots.is_empty():
		pu_wait = PU_GAP
		return
	var top := top_points()
	var low: Fighter = null
	for f in fighters:
		if f.state != P.F_DEAD and not f.bot and f.points < top:
			if low == null or f.points < low.points or (f.points == low.points and rng.randf() < 0.5):
				low = f
	var o := Orb.new()
	_orb_serial += 1
	o.serial = _orb_serial
	o.state = P.ORB_WARN
	var spot := Vector2(-1.0, -1.0)
	if low != null and not big_round and rng.randf() < BIG_CHANCE + 0.15 * (top - low.points - 1):
		spot = _spot_near(low)
		if spot.x >= 0.0:
			o.big = true
			o.for_seat = low.id
			o.kind = _pick_big()
			big_round = true
	if spot.x < 0.0:
		o.kind = _pick_regular()
		spot = _spot_random()
	o.x = spot.x
	o.y = spot.y - ORB_UP
	pu_last_x = spot.x
	orbs.append(o)
	_event(P.E_PU_WARN, int(o.x), int(o.y), o.kind, 1 if o.big else 0)

# A regular kind by REGULAR_W, never the last one; FLYING only with a person alive
# to take it.
func _pick_regular() -> int:
	var person := false
	for f in fighters:
		if f.state != P.F_DEAD and not f.bot:
			person = true
	var total := 0
	for k in REGULAR_W:
		if k != pu_last and (k != P.PU_FLY or person):
			total += REGULAR_W[k]
	var r := rng.randi() % maxi(1, total)
	for k in REGULAR_W:
		if k == pu_last or (k == P.PU_FLY and not person):
			continue
		r -= REGULAR_W[k]
		if r < 0:
			pu_last = k
			return k
	pu_last = P.PU_SHIELD
	return P.PU_SHIELD

func _pick_big() -> int:
	var pick: int = BIG_KINDS[rng.randi() % BIG_KINDS.size()]
	if pick == pu_last_big:
		pick = BIG_KINDS[(BIG_KINDS.find(pick) + 1 + rng.randi() % (BIG_KINDS.size() - 1)) % BIG_KINDS.size()]
	pu_last_big = pick
	return pick

# A random orb spot: inside the band the purple walls leave, away from the last drop.
func _spot_random() -> Vector2:
	var reach: int = walls_width() + 150 if walls_share > 0.0 else 0
	for i in 16:
		var sp: Vector2 = spots[rng.randi() % spots.size()]
		if sp.x < reach or sp.x > W - reach:
			continue
		if absf(wrap_d(sp.x, pu_last_x, W)) < 300.0 and i < 12:
			continue
		return sp
	return spots[rng.randi() % spots.size()]

# A spot 150 to 520 px from f's feet (about 300 is best), with nobody within the
# bolt's reach of the orb; (-1, -1) for none.
func _spot_near(f: Fighter) -> Vector2:
	var best := Vector2(-1.0, -1.0)
	var bd := INF
	var fx := float(f.x + HALF_W)
	var fy := float(f.y + BODY_H)
	var reach: int = walls_width() + 150 if walls_share > 0.0 else 0
	for sp in spots:
		if sp.x < reach or sp.x > W - reach:
			continue
		var d := Vector2(wrap_d(fx, sp.x, W), wrap_d(fy, sp.y, H)).length()
		if d < 150.0 or d > 520.0:
			continue
		var clear := true
		for o in fighters:
			if o.state != P.F_DEAD and Vector2(wrap_d(o.x + HALF_W, sp.x, W), wrap_d(o.y + MID_Y, sp.y - ORB_UP, H)).length() < STRIKE_R + 40.0:
				clear = false
				break
		if not clear:
			continue
		var score := absf(d - 300.0) + rng.randf() * 60.0
		if score < bd:
			bd = score
			best = sp
	return best

# The orb spots of this arena: the feet spot over every floor or ledge cell a body
# can stand on (level.stands), not in the side walls' outer columns.
func _ensure_spots() -> void:
	if spots_level == level.id and not spots.is_empty():
		return
	spots_level = level.id
	spots.clear()
	for cy in range(1, level.ROWS):
		for cx in range(2, level.COLS - 2):
			var sp := Vector2i(cx * 30 + 15, cy * 30)
			if level.cell(cx, cy) != 0 and level.cell(cx, cy - 1) == 0 and level.stands(sp):
				spots.append(Vector2(sp))

# A test knob (the server's --pu-gallery): every power-up's look at once, for the
# pictures and the prediction test. Seat 0 flies (and the rain slows it); seats 1..7
# each get one (shield + bomb arrows, flying, spikes, rain, frozen, speed + big
# arrows, invisible), orbs of several kinds wait (one warns),
# and two ghost cats leave seat 1.
func gallery() -> void:
	_ensure_spots()
	var looks := {0: [P.PU_FLY], 1: [P.PU_SHIELD, P.PU_BOMB], 2: [P.PU_FLY], 3: [P.PU_SPIKES], 4: [P.PU_RAIN], 6: [P.PU_SPEED, P.PU_BIG], 7: [P.PU_INVIS]}
	for f in fighters:
		for k in looks.get(f.id, []):
			_give(f, k)
		if f.id == 5:
			f.freeze_t = 3600
		if f.id == 2:
			f.fly = true
	var kinds := [P.PU_FIRE, P.PU_INF, P.PU_CATS, P.PU_FREEZE, P.PU_SMOKE]
	for i in kinds.size():
		var o := Orb.new()
		_orb_serial += 1
		o.serial = _orb_serial
		o.kind = kinds[i]
		o.big = kinds[i] >= P.PU_CATS
		o.state = P.ORB_WARN if i == kinds.size() - 1 else P.ORB_LIVE
		o.t = PU_WARN / 2 if o.state == P.ORB_WARN else 0
		var sp: Vector2 = spots[(i * 37 + 11) % spots.size()]
		o.x = sp.x
		o.y = sp.y - ORB_UP
		orbs.append(o)
	var f1 := fighter(1)
	if f1 != null:
		_send_cats(f1)
		if cats.size() > 2:
			cats.resize(2)
	for c in cats:
		c.t = -600              # they take their time (the pictures)

# The quarter seconds left of f's BIG power-up (the longest that runs), for the page.
static func big_left(f: Fighter) -> int:
	return maxi(maxi(f.invis_t, f.speed_t), maxi(f.umbrella_t, f.spikes_t))

# The snapshot's power bits (proto PW_*).
static func power_bits(f: Fighter) -> int:
	return (P.PW_SHIELD if f.shield > 0 else 0) | (P.PW_INF if f.inf else 0) | (P.PW_FLY if f.fly else 0) \
		| (P.PW_BIG if f.big else 0) | (P.PW_INVIS if invisible(f) else 0) | (P.PW_INVIS_ON if f.invis_t > 0 else 0) \
		| (P.PW_FROZEN if f.freeze_t > 0 else 0) | (P.PW_SLOW if f.slow_t > 0 and f.umbrella_t <= 0 else 0) \
		| (P.PW_UMBRELLA if f.umbrella_t > 0 else 0) | (P.PW_SPIKES if f.spikes_t > 0 else 0) \
		| (P.PW_SPIKE_UP if f.spikes_t > 0 and f.spike_up else 0) | (P.PW_SPEED if f.speed_t > 0 else 0)

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

# ------------------------------------------------------------------ the walls
# The purple walls (TowerFall's miasma, D2): walls_start ticks after FIGHT they
# grow in from the left and right edges along WALLS_STEPS, and anyone touching a
# wall dies once it is deadly. When one fighter or none is left, they melt away
# at once (TowerFall melts them on a kill that leaves one; ours on any end, so the
# winner is never caught in the 1.5 s before the point).
func _update_walls() -> void:
	if walls_start <= 0 or play_t < walls_start:
		return
	if walls_melt_t < 0 and alive_count() <= 1:
		walls_melt_t = 0
		walls_melt_from = walls_share
	if walls_melt_t >= 0:
		walls_melt_t += 1
		var n := maxi(20, int(60.0 * walls_melt_from))
		walls_share = lerpf(walls_melt_from, WALLS_GONE, _ease(minf(1.0, float(walls_melt_t) / n), 1))
		return
	walls_share = walls_at(play_t - walls_start)
	if not walls_deadly():
		return
	var dw := walls_width() - WALLS_EDGE
	if dw <= 0:
		return
	for f in fighters:
		if f.state != P.F_DEAD and (f.x < dw or f.x + BODY_W > W - dw):
			_kill(f, 255, 6)

# The walls' share t ticks after they appear.
static func walls_at(t: int) -> float:
	for st in WALLS_STEPS:
		if t < st[0]:
			return lerpf(st[1], st[2], _ease(float(t) / st[0], st[3]))
		t -= st[0]
	return WALLS_GONE

static func _ease(x: float, kind: int) -> float:
	if kind == 0:
		return 1.0 - pow(1.0 - x, 3.0)
	if kind == 2:
		return x * x * x
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) * 0.5

# Each wall's width in px (0: no walls).
func walls_width() -> int:
	return maxi(0, roundi(walls_share * WALLS_HALF))

func walls_deadly() -> bool:
	return walls_start > 0 and walls_melt_t < 0 and play_t >= walls_start + WALLS_DEADLY and walls_share > 0.0

# ------------------------------------------------------------------ the arrows in the present (P2)
# The client's copy (client/present.gd): n ticks of its arrows alone, by the same
# arrow code. Its fighters stand still and only stop arrows (predicting is on).
func fly_arrows(n: int) -> void:
	for i in n:
		tick += 1
		for a in arrows:
			_update_arrow(a)
		_tinks()
		for j in range(arrows.size() - 1, -1, -1):
			if arrows[j].dead:
				arrows.remove_at(j)

# ------------------------------------------------------------------ snapshot
func live_arrow_count() -> int:
	var n := 0
	for a in arrows:
		if not a.dead:
			n += 1
	return n

# The whole state for the clients (the format: proto.gd). head carries the
# match: phase, round, left (ticks), goal, winner; the benchmark passes none.
# The walls' width comes from the sim itself.
func write_snapshot(buf: StreamPeerBuffer, evs: Array, head: Dictionary = {}) -> void:
	buf.clear()
	buf.put_u8(P.T_SNAP)
	buf.put_u32(tick)
	buf.put_u8(int(head.get("phase", P.PH_PLAY)))
	buf.put_u8(int(head.get("round", 0)))
	buf.put_u16(clampi(int(head.get("left", 0)), 0, 65535))
	buf.put_u8(int(head.get("goal", 0)))
	buf.put_u8(int(head.get("winner", P.NO_ONE)))
	buf.put_u16(walls_width() | (0x8000 if walls_deadly() else 0))
	buf.put_u8(level.id)
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
		buf.put_u8(fighter_flags(f))
		buf.put_u8(int(fposmod(f.aim, TAU) / TAU * 256.0) & 255)
		buf.put_u8(f.arrows)
		buf.put_u8(mini(f.state_t, 255))
		buf.put_u8(mini(f.points, 255))
		buf.put_u8((P.F2_BOT if f.bot else 0) | (P.F2_AIMING if f.aiming else 0) | (0 if f.connected else P.F2_AWAY))
	for a in arrows:
		if a.dead:
			continue
		buf.put_u16(a.id)
		buf.put_u8(a.kind | (a.state << 4) | (0x40 if a.big else 0))
		if a.state == P.S_STUCK:
			buf.put_16(int(a.x))
			buf.put_16(int(a.y))
			buf.put_u8(int(fposmod(a.ang, TAU) / TAU * 256.0) & 255)
		else:   # in the air: all a client needs to fly it on (P2, client/present.gd)
			buf.put_float(a.x)
			buf.put_float(a.y)
			buf.put_float(a.vx)
			buf.put_float(a.vy)
			buf.put_u8(mini(a.t, 255))
			buf.put_u8(a.owner & 255)
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
	# p4.9 the power-ups (the format: proto.gd; readers before p4.9 stop after the events)
	buf.put_u8(P.PW_TAG)
	var pf: Array = []
	for f in fighters:
		if power_bits(f) != 0 or f.pw_kind != 0:
			pf.append(f)
	buf.put_u8(pf.size())
	for f in pf:
		buf.put_u8(f.id)
		buf.put_u16(power_bits(f))
		buf.put_u8(f.pw_kind)
		buf.put_u8(mini(255, ceili(big_left(f) / 15.0)))
	buf.put_u8(orbs.size())
	for o in orbs:
		buf.put_u8(o.state)
		buf.put_u8(o.kind)
		buf.put_u8(1 if o.big else 0)
		buf.put_16(int(o.x))
		buf.put_16(int(o.y))
		buf.put_u8(clampi(int(255.0 * o.t / (PU_WARN if o.state == P.ORB_WARN else PU_LIFE)), 0, 255))
		buf.put_u8(o.for_seat & 255)
	buf.put_u8(cats.size())
	for c in cats:
		buf.put_u8(c.owner)
		buf.put_u8(c.target)
		buf.put_16(int(c.x))
		buf.put_16(int(c.y))
	buf.put_u8(rain_owner if rain_t > 0 and rain_owner >= 0 else P.NO_ONE)
	buf.put_u8(mini(255, ceili(rain_t / 15.0)))

# The snapshot's fighter flags (proto.gd): 1 facing right, 2 on the ground, 4 at a
# wall, 8 burning, 16 poisoned, 32 rolling or pulling up, 64 wall jump, 128 in smoke.
func fighter_flags(f: Fighter) -> int:
	var pulling: bool = f.state == P.F_LEDGE and f.ledge_t <= 8
	return (1 if f.facing > 0 else 0) | (2 if f.on_ground else 0) | (4 if f.wall != 0 else 0) \
		| (8 if f.burn_t > 0 else 0) | (16 if f.miasma_t > 0 else 0) \
		| (32 if (f.state == P.F_DODGE and f.rolling) or pulling else 0) | (64 if f.wj_t > 0 else 0) | (128 if f.in_smoke else 0)

# ------------------------------------------------------------------ the whole fighter (P2)
# Everything the next ticks of a person's fighter depend on, for T_OWN (proto.gd):
# the server writes it after each snapshot, and the client's prediction reads it
# and replays its own inputs from it (client/predict.gd). Left out: the seat,
# bot and connected, points, killer, and the brain's think_t, wait_t, shoot_cd, mind.
# A new Fighter field that moves a fighter goes in both functions; input_probe
# runs a read-back copy beside the original to catch one that is missing.
func write_fighter_state(buf: StreamPeerBuffer, f: Fighter) -> void:
	buf.put_16(f.x)
	buf.put_16(f.y)
	buf.put_double(f.rx)
	buf.put_double(f.ry)
	buf.put_double(f.vx)
	buf.put_double(f.vy)
	buf.put_double(f.aim)
	buf.put_u8(f.state)
	buf.put_u32(f.state_t)
	buf.put_8(f.facing)
	buf.put_8(f.wall)
	buf.put_8(f.move_dir)
	buf.put_u8(f.buttons)
	buf.put_u8(f.arrows)
	buf.put_16(f.dodge_t)
	buf.put_32(f.dead_t)
	buf.put_u8(f.coyote)
	buf.put_u8(f.dodge_cd)
	buf.put_u8(f.dodge_jump_t)
	buf.put_u8(f.catch_t)
	buf.put_u8(f.jump_buf)
	buf.put_u8(f.hold_jump)
	buf.put_u8(f.drop_t)
	buf.put_u8(f.dropping)
	buf.put_u8(f.wj_t)
	buf.put_u8(f.ledge_t)
	buf.put_u16(mini(f.burn_t, 65535))
	buf.put_u16(mini(f.miasma_t, 65535))
	buf.put_u8((1 if f.on_ground else 0) | (2 if f.aiming else 0) | (4 if f.want_jump else 0) \
		| (8 if f.rolling else 0) | (16 if f.in_smoke else 0) | (32 if f.drawn else 0) | (64 if f.shot_wait else 0))
	buf.put_double(f.shot_aim)
	buf.put_8(f.vdir)               # p4.9 the power-ups
	buf.put_u8(f.pw_kind)
	buf.put_u8(f.shield)
	buf.put_u8((1 if f.inf else 0) | (2 if f.fly else 0) | (4 if f.big else 0) | (8 if f.spike_up else 0))
	buf.put_u16(mini(f.freeze_t, 65535))
	buf.put_u16(mini(f.slow_t, 65535))
	buf.put_u16(mini(f.speed_t, 65535))
	buf.put_u16(mini(f.invis_t, 65535))
	buf.put_u16(mini(f.umbrella_t, 65535))
	buf.put_u16(mini(f.spikes_t, 65535))
	buf.put_u16(mini(f.spike_regen, 65535))

func read_fighter_state(buf: StreamPeerBuffer, f: Fighter) -> void:
	f.x = buf.get_16()
	f.y = buf.get_16()
	f.rx = buf.get_double()
	f.ry = buf.get_double()
	f.vx = buf.get_double()
	f.vy = buf.get_double()
	f.aim = buf.get_double()
	f.state = buf.get_u8()
	f.state_t = buf.get_u32()
	f.facing = buf.get_8()
	f.wall = buf.get_8()
	f.move_dir = buf.get_8()
	f.buttons = buf.get_u8()
	f.arrows = buf.get_u8()
	f.dodge_t = buf.get_16()
	f.dead_t = buf.get_32()
	f.coyote = buf.get_u8()
	f.dodge_cd = buf.get_u8()
	f.dodge_jump_t = buf.get_u8()
	f.catch_t = buf.get_u8()
	f.jump_buf = buf.get_u8()
	f.hold_jump = buf.get_u8()
	f.drop_t = buf.get_u8()
	f.dropping = buf.get_u8()
	f.wj_t = buf.get_u8()
	f.ledge_t = buf.get_u8()
	f.burn_t = buf.get_u16()
	f.miasma_t = buf.get_u16()
	var b := buf.get_u8()
	f.on_ground = (b & 1) != 0
	f.aiming = (b & 2) != 0
	f.want_jump = (b & 4) != 0
	f.rolling = (b & 8) != 0
	f.in_smoke = (b & 16) != 0
	f.drawn = (b & 32) != 0
	f.shot_wait = (b & 64) != 0
	f.shot_aim = buf.get_double()
	f.vdir = buf.get_8()
	f.pw_kind = buf.get_u8()
	f.shield = buf.get_u8()
	var pb := buf.get_u8()
	f.inf = (pb & 1) != 0
	f.fly = (pb & 2) != 0
	f.big = (pb & 4) != 0
	f.spike_up = (pb & 8) != 0
	f.freeze_t = buf.get_u16()
	f.slow_t = buf.get_u16()
	f.speed_t = buf.get_u16()
	f.invis_t = buf.get_u16()
	f.umbrella_t = buf.get_u16()
	f.spikes_t = buf.get_u16()
	f.spike_regen = buf.get_u16()

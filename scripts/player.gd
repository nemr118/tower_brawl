# ==============================================================================
# WELCOME TO PLAYER.GD! (The Character Script)
# ==============================================================================
# Hey there! This script acts as the "brain" for the characters on screen.
# Every time you move, jump, or attack, this file is doing the math.
# In programming, we use "variables" (think of them like labeled boxes) 
# to store information like how fast we can run or how many lives we have left.
# ==============================================================================

extends CharacterBody2D

signal player_died(killer_id, victim_id)

@export var player_id: int = 1
@export var class_type: Global.ClassType = Global.ClassType.RANGER

const SPEED = 220.0
const ACCEL = 1900.0
const FRICTION = 1500.0
const JUMP_VELOCITY = -430.0
const GRAVITY = 1150.0
const FALL_GRAVITY = 1600.0

const DASH_SPEED = 550.0
const DASH_DURATION = 0.14
const DASH_COOLDOWN = 0.65

# Movement states
var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_dir: Vector2 = Vector2.RIGHT

var is_shielding: bool = false
var is_bear_form: bool = false
var is_egg: bool = false
var egg_timer: float = 0.0
var shield_timer: float = 0.0

# Bubble spawn (v0.0.18). The story: fighters used to pop up on fixed spots,
# and when the arena was upside down those spots could be inside the floor or
# out of view. Now a fighter comes back in the air, inside a bubble, and floats
# down slowly. The bubble works like a shield: hits bounce off. It pops after
# BUBBLE_TIME seconds, when the feet touch the ground, or the moment the
# player attacks, dashes or uses a special.
var is_bubble: bool = false
var bubble_timer: float = 0.0
const BUBBLE_TIME = 5.0          # seconds the bubble lasts at most
# Round-start bubble (v0.0.19). At the start of a round the fighter stands
# still on a platform inside the bubble. Gravity is off. The first key press
# from that player pops it, or it pops by itself after BUBBLE_GROUND_TIME.
var bubble_on_ground: bool = false
const BUBBLE_GROUND_TIME = 1.5   # seconds the round-start bubble lasts at most
const BUBBLE_FALL_SLOW = 45.0    # px/s, the slow float down
const BUBBLE_FALL_FAST = 260.0   # px/s, when Down is held
const BUBBLE_SIDE_SPEED = 160.0  # px/s, left and right while floating

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0
var _jump_fired_last_frame: bool = false   # for the jump trap (v0.0.18)

var is_facing_right: bool = true
var is_dead: bool = false
var spawn_invuln_timer: float = 1.0
var anim_time: float = 0.0

# Aiming System
var aim_direction: Vector2 = Vector2.RIGHT

# Network state
var is_local_player: bool = true
var target_net_pos: Vector2 = Vector2.ZERO
var sync_timer: float = 0.0
var net_tick: int = 0                 # our 20 Hz sample counter (goes out in every sync_pos)
var _last_sync_bytes: PackedByteArray = PackedByteArray()   # last packet body (minus tick) actually sent
var _idle_since_send: float = 0.0     # seconds since the last packet went out
var _sent_last_tick: bool = false     # did the previous 50 ms slot go out? (for the "I stopped" repeat)
var _last_rx_tick: int = -1           # newest tick received for this puppet (stale packets are dropped)
# Snapshot interpolation (Phase 3b). Samples live in unwrapped tick space
# (_rx_tick_unwrapped grows without the u16 wrap) so the ring is always sorted.
var _snaps: Array = []                # [{t, pos, aim, facing, dash, shield, bear, egg, at_msec}], oldest first
var _rx_tick_unwrapped: int = 0
var _render_tick: float = -1.0        # free-running render clock, in unwrapped ticks
var _pj_extrapolating: bool = false   # this frame was rendered past the newest sample
var _pj_dipped: bool = false          # this frame the puppet was drawn below its newest floor sample
# puppet-jitter telemetry (remote fighters only; see Global.puppet_sample)
var _pj_last_pos: Vector2 = Vector2.INF
var _pj_last_speed: float = -1.0
var _pj_last_rx_msec: int = 0         # when the newest sample arrived
var _pj_sender_moving: bool = false   # the newest sample differed from the one before it

func _clear_snapshots() -> void:
	_snaps.clear()
	_render_tick = -1.0
	_rx_tick_unwrapped = 0


func reset_net_sequence() -> void:
	_clear_snapshots()
	# The sender (re)joined its seat: whatever tick comes next starts a new sequence.
	_last_rx_tick = -1
var _last_persisted: Array = []   # ammo/form snapshot last written to storage

# Class Resources
var max_arrows: int = 3
var current_arrows: int = 3

var mage_charges: int = 3
var mage_recharge_timer: float = 0.0

var rogue_kunai: int = 4
var rogue_recharge_timer: float = 0.0

var attack_cooldown: float = 0.0
var special_cooldown: float = 0.0

const ArrowScene = preload("res://scenes/arrow.tscn")
const FireboltScene = preload("res://scenes/firebolt.tscn")
const KunaiScene = preload("res://scenes/kunai.tscn")
const ThornScene = preload("res://scenes/thorn.tscn")

@onready var collision_shape = $CollisionShape2D
@onready var melee_area = $MeleeArea

func _ready():
	add_to_group("players")
	is_local_player = (player_id == Global.my_player_id)
	
	if not is_local_player:
		Global.connect("net_player_state_received", Callable(self, "_on_player_state_received"))
		Global.connect("net_projectile_spawned", Callable(self, "_on_remote_projectile"))
		
	_apply_class_defaults()
	melee_area.monitoring = false
	aim_direction = Vector2.RIGHT if player_id == 1 else Vector2.LEFT
	is_facing_right = (player_id == 1)

func _apply_class_defaults():
	match class_type:
		Global.ClassType.RANGER:
			max_arrows = 3
			current_arrows = 3
		Global.ClassType.KNIGHT:
			pass
		Global.ClassType.MAGE:
			mage_charges = 3
		Global.ClassType.ROGUE:
			rogue_kunai = 4


	# ------------------------------------------------------------------------------
	# THE GAME LOOP: _physics_process(delta)
	# This function is the heartbeat of the game! It runs 60 times every second.
	# "delta" is the tiny fraction of a second between frames. We use delta 
	# to make sure the game runs at the same speed on fast and slow computers.
	# ------------------------------------------------------------------------------
func _physics_process(delta: float):
	if is_dead:
		return
		
	anim_time += delta * 12.0
	
	# Timers tick down for BOTH Local and Remote players
	if is_egg:
		egg_timer -= delta
		if egg_timer <= 0.0:
			is_egg = false
			spawn_invuln_timer = 1.0
			_squash_and_stretch(1.5, 1.5)
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		velocity.y += GRAVITY * delta
		move_and_slide()
		_check_screen_wrap()   # an egg falling past the seam used to keep falling
		_sync_network_state(delta)
		queue_redraw()
		return
		
	if spawn_invuln_timer > 0.0:
		spawn_invuln_timer -= delta
	if is_bubble:
		bubble_timer -= delta
	if shield_timer > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			is_shielding = false
	if dash_timer > 0.0:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false
			
	# REMOTE PLAYER REPLICATION: snapshot interpolation ~100 ms behind the sender
	if not is_local_player:
		_render_snapshots(delta)
		_puppet_telemetry(delta)
		# The real player tells us when the bubble popped: the shield bit in the
		# movement packet goes off. A late safety timer covers a lost packet.
		if is_bubble and ((_snaps.size() > 0 and not is_shielding) or bubble_timer <= -0.5):
			is_bubble = false
		queue_redraw()
		return
		
	# LOCAL PLAYER CONTROLS
	if player_id < 1 or player_id > 4:
		return   # no input map for an unassigned id (guard: seen once in a fleet run as "p0_left")
	if attack_cooldown > 0.0: attack_cooldown -= delta
	if special_cooldown > 0.0: special_cooldown -= delta
	if dash_cooldown_timer > 0.0: dash_cooldown_timer -= delta
	
	if class_type == Global.ClassType.MAGE and mage_charges < 3:
		mage_recharge_timer += delta
		if mage_recharge_timer >= 1.4:
			mage_charges += 1
			mage_recharge_timer = 0.0
	elif class_type == Global.ClassType.ROGUE and rogue_kunai < 4:
		rogue_recharge_timer += delta
		if rogue_recharge_timer >= 0.9:
			rogue_kunai += 1
			rogue_recharge_timer = 0.0
			
	if is_bubble:
		var bprefix = "p" + str(player_id) + "_"
		var wants_action = Input.is_action_just_pressed(bprefix + "attack") \
			or Input.is_action_just_pressed(bprefix + "special") \
			or Input.is_action_just_pressed(bprefix + "dash")
		if bubble_on_ground:
			# The round-start bubble: stand still until the first key press.
			var any_press = wants_action \
				or Input.is_action_just_pressed(bprefix + "left") \
				or Input.is_action_just_pressed(bprefix + "right") \
				or Input.is_action_just_pressed(bprefix + "jump") \
				or Input.is_action_just_pressed(bprefix + "down")
			if any_press or bubble_timer <= 0.0:
				_pop_bubble()   # pop and keep going: the key press still counts below
			else:
				# A tiny push down keeps the feet touching the platform, so
				# is_on_floor() stays true and the "feet on the ground" bit in
				# our packets is right. The fighter does not visibly move.
				velocity = Vector2(0.0, 10.0)
				move_and_slide()
				velocity = Vector2.ZERO
				# v0.0.20: the fighter still turns and aims inside the bubble.
				_update_aim(Input.get_axis(bprefix + "left", bprefix + "right"),
					Input.get_axis(bprefix + "up", bprefix + "down"))
				_sync_network_state(delta)
				queue_redraw()
				return
		elif wants_action or bubble_timer <= 0.0:
			# Pop now and keep going: the normal code below runs in this same
			# frame, so the attack or dash the player pressed still happens.
			_pop_bubble()
		else:
			# Float down slowly. Left and right still work. Down drops faster.
			var bx = Input.get_axis(bprefix + "left", bprefix + "right")
			velocity.x = move_toward(velocity.x, bx * BUBBLE_SIDE_SPEED, ACCEL * delta)
			# v0.0.20: the fighter still turns and aims inside the bubble.
			_update_aim(bx, Input.get_axis(bprefix + "up", bprefix + "down"))
			var fast = Input.get_action_strength(bprefix + "down") > 0.5
			velocity.y = BUBBLE_FALL_FAST if fast else BUBBLE_FALL_SLOW
			move_and_slide()
			_check_screen_wrap()
			if is_on_floor():
				_pop_bubble()   # feet on the ground: the bubble is done
			_sync_network_state(delta)
			queue_redraw()
			return

	if is_dashing:
		velocity = dash_dir * DASH_SPEED
		move_and_slide()
		_check_screen_wrap()
		_sync_network_state(delta)
		queue_redraw()
		return
		
	if is_shielding:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		_check_screen_wrap()   # a druid air-shielding while falling dropped to y > 500
		_sync_network_state(delta)
		queue_redraw()
		return

	var prefix = "p" + str(player_id) + "_"
	
	var input_x = Input.get_axis(prefix + "left", prefix + "right")
	var input_y = Input.get_axis(prefix + "up", prefix + "down")
	
	_update_aim(input_x, input_y)

	if abs(input_x) > 0.1:
		velocity.x = move_toward(velocity.x, sign(input_x) * SPEED, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		
	if is_on_floor():
		coyote_timer = 0.12
		if velocity.y > 0:
			velocity.y = 0.0
	else:
		coyote_timer -= delta
		var current_gravity = FALL_GRAVITY if velocity.y > 0 else GRAVITY
		velocity.y += current_gravity * delta
		
	if Input.is_action_just_pressed(prefix + "jump"):
		jump_buffer_timer = 0.12
	else:
		jump_buffer_timer -= delta
		
	var jumped_now = false
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		jumped_now = true
		_squash_and_stretch(0.7, 1.3)

	# Jump trap (v0.0.18). In the playtest a fighter standing on a platform
	# sometimes could not jump with W until it walked off. We could not find
	# the reason in the code, so this trap prints one line to the console the
	# moment it happens, with the numbers we need to see. Two cases:
	#   1. jump was pressed on the floor but no jump fired;
	#   2. a jump fired last frame but the feet are already back on the floor.
	if Input.is_action_just_pressed(prefix + "jump") and is_on_floor() and not jumped_now:
		print("🪤 [JumpTrap] P", player_id, " pressed jump on the floor but no jump fired.",
			" coyote=", snapped(coyote_timer, 0.001), " buffer=", snapped(jump_buffer_timer, 0.001),
			" vel=", velocity.round(), " pos=", global_position.round(),
			" contacts=", get_slide_collision_count(), " floor_normal=", get_floor_normal(),
			" shield=", is_shielding, " dash=", is_dashing, " bubble=", is_bubble)
	if _jump_fired_last_frame and is_on_floor() and velocity.y >= 0.0:
		print("🪤 [JumpTrap] P", player_id, " jumped last frame but is back on the floor already.",
			" vel=", velocity.round(), " pos=", global_position.round(),
			" contacts=", get_slide_collision_count(), " floor_normal=", get_floor_normal())
	_jump_fired_last_frame = jumped_now
		
	if Input.is_action_just_released(prefix + "jump") and velocity.y < -120.0:
		velocity.y = -120.0
		
	if Input.is_action_just_pressed(prefix + "dash") and dash_cooldown_timer <= 0.0:
		_start_dash(input_x, input_y)
		
	if Input.is_action_just_pressed(prefix + "attack") and attack_cooldown <= 0.0:
		_perform_attack(aim_direction)
		
	if Input.is_action_just_pressed(prefix + "special") and special_cooldown <= 0.0:
		_perform_special(aim_direction)

	move_and_slide()
	_check_screen_wrap()
	_check_head_stomp()
	_sync_network_state(delta)
	queue_redraw()

func _update_aim(input_x: float, input_y: float) -> void:
	# "Where am I looking?" (v0.0.20). The story: inside the spawn bubble the
	# fighter stood like a statue. The aim line and the face were stuck, because
	# the bubble code returned before this block ran. Now this block is its own
	# little function, so the bubble code can call it too. On a PC we look at
	# the mouse. On a phone, or for a bot, we look where the stick points.
	if is_local_player and not Global.is_mobile:
		var raw_aim = get_global_mouse_position() - global_position
		if raw_aim.length_squared() > 0.08:
			aim_direction = raw_aim.normalized()
			is_facing_right = raw_aim.x > 0
	else:
		var raw_aim = Vector2(input_x, input_y)
		if raw_aim.length_squared() > 0.08:
			aim_direction = raw_aim.normalized()
			if input_x > 0.15:
				is_facing_right = true
			elif input_x < -0.15:
				is_facing_right = false
		else:
			aim_direction = Vector2.RIGHT if is_facing_right else Vector2.LEFT

func _sync_network_state(delta: float):
	sync_timer += delta
	_idle_since_send += delta
	if sync_timer < Global.NET_TICK_INTERVAL - 0.001:
		return
	sync_timer -= Global.NET_TICK_INTERVAL   # keep the slots at exactly 50 ms
	# The tick is a slot clock: it advances every 50 ms whether or not this slot
	# goes out, so a receiver can place every sample in time and read a gap as
	# "unchanged for that long" (Phase 3b interpolation).
	net_tick = (net_tick + 1) & 0xFFFF
	_persist_combat_state()
	# 20 Hz sample. Idle suppression: if nothing observable changed since the last
	# packet (position at 0.1 px, aim at 0.1 deg, flags), skip it, but repeat the
	# state every NET_IDLE_RESEND so a late joiner or a lost packet is corrected.
	var pkt := Global.encode_sync_pos(net_tick, global_position, aim_direction,
		is_facing_right, is_dashing, is_shielding, is_bear_form, is_egg, is_on_floor())
	var body := pkt.slice(4)   # everything after type, sender, tick
	if body == _last_sync_bytes and _idle_since_send < Global.NET_IDLE_RESEND:
		# v0.0.17 hotfix: the first quiet slot after a moving one still goes out.
		# The story: when we land or stop, the other screens only had our last
		# moving sample and kept guessing we were still moving (sinking through
		# the floor, sliding past the stop). One repeat of the same spot, one
		# tick later, tells them "I am standing right here now". Costs one
		# 11-byte packet per stop. The floor flag in the packet makes the
		# landing itself a change too, so a touchdown is never skipped.
		if not _sent_last_tick:
			return
		_sent_last_tick = false
		Global.send_net_binary(pkt)
		return
	_last_sync_bytes = body
	_idle_since_send = 0.0
	_sent_last_tick = true
	Global.send_net_binary(pkt)

# Per rendered physics frame: how much this puppet's speed changed since the
# last frame (the jitter a player sees), snaps, and frames starved of samples.
func _puppet_telemetry(delta: float) -> void:
	if _pj_last_pos == Vector2.INF:
		_pj_last_pos = global_position
		return
	var disp := global_position - _pj_last_pos
	_pj_last_pos = global_position
	# a seam crossing moves the drawn position by most of the arena: expected
	var wrapped := absf(disp.x) > 400.0 or absf(disp.y) > 300.0
	var snapped := not wrapped and disp.length() > Global.PUPPET_SNAP_PX
	var speed := disp.length() / delta
	var speed_delta := 0.0
	if snapped or wrapped or _pj_last_speed < 0.0:
		_pj_last_speed = -1.0 if (snapped or wrapped) else speed
	else:
		speed_delta = absf(speed - _pj_last_speed)
		_pj_last_speed = speed
	var starved := _pj_sender_moving and (Time.get_ticks_msec() - _pj_last_rx_msec) > Global.PUPPET_STALL_SEC * 1000.0
	Global.puppet_sample(player_id, speed_delta, snapped, starved, wrapped, _pj_extrapolating, _pj_dipped)


func _on_player_state_received(p_id: int, data: Dictionary):
	if p_id == player_id:
		# Drop a sample older than the newest one we have (wrap-aware u16 compare),
		# but a counter far behind (> 200 ticks = 10 s) means the sender restarted
		# (page reload, rejoin): treat it as a new sequence instead of freezing.
		var tick := int(data.get("tick", -1))
		if tick >= 0 and _last_rx_tick >= 0 and ((tick - _last_rx_tick) & 0xFFFF) >= 0x8000 \
				and ((_last_rx_tick - tick) & 0xFFFF) <= 200:
			return
		if tick >= 0 and tick == _last_rx_tick:
			return   # duplicate slot: the ring must never hold two samples with one tick
		var new_pos := Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
		_pj_sender_moving = new_pos.distance_squared_to(target_net_pos) > 0.25
		_pj_last_rx_msec = Time.get_ticks_msec()
		target_net_pos = new_pos
		if tick >= 0:
			if _last_rx_tick < 0 or ((_last_rx_tick - tick) & 0xFFFF) < 0x8000 and _last_rx_tick != tick:
				# a restart (counter far behind, see above) or the first sample: new sequence
				if _last_rx_tick >= 0:
					_clear_snapshots()
			else:
				_rx_tick_unwrapped += (tick - _last_rx_tick) & 0xFFFF
			_last_rx_tick = tick
		else:
			_rx_tick_unwrapped += 1
		var aim := Vector2(float(data.get("aim_x", 1.0)), float(data.get("aim_y", 0.0)))
		_snaps.append({"t": _rx_tick_unwrapped, "pos": new_pos, "aim": aim,
			"facing": bool(data.get("facing", true)), "dash": bool(data.get("dash", false)),
			"shield": bool(data.get("shield", false)), "bear": bool(data.get("bear", false)),
			"egg": bool(data.get("egg", false)), "floor": bool(data.get("floor", false)),
			"at_msec": _pj_last_rx_msec})
		while _snaps.size() > Global.SNAP_RING:
			_snaps.pop_front()


# Where the sender is now, in unwrapped ticks: its newest tick plus the time
# that sample has been sitting here. Robust to idle suppression (the sender's
# clock keeps running while it sends nothing).
func _estimated_sender_tick() -> float:
	var newest: Dictionary = _snaps[-1]
	return float(newest["t"]) + (Time.get_ticks_msec() - int(newest["at_msec"])) / 1000.0 * Global.NET_TICK_HZ


# Place the puppet at render time = sender time - RENDER_DELAY_TICKS, between the
# two samples that bracket it. A tick gap over 2 means the sender sent nothing
# because nothing changed (idle suppression), so the state holds at the older
# sample until one tick before the newer one. Deltas are unwrapped across the
# horizontal seam (640 px) and the bottom seam (386 px) so a crossing is a step
# of a few pixels, never a glide across the screen, and the result is wrapped
# back into the arena. Flags come from the sample at render time, so dash and
# shield windows sit on the drawn position.
func _render_snapshots(delta: float) -> void:
	_pj_extrapolating = false
	_pj_dipped = false
	if _snaps.is_empty():
		return
	var target := _estimated_sender_tick() - Global.RENDER_DELAY_TICKS
	if _render_tick < 0.0 or absf(target - _render_tick) > 5.0:
		_render_tick = target                       # first sample or a burst: resync
	else:
		_render_tick += delta * Global.NET_TICK_HZ  # free-running 20 Hz clock ...
		_render_tick += (target - _render_tick) * 0.05   # ... gently pulled to the estimate
	var r := _render_tick
	var a: Dictionary = _snaps[0]
	var b: Dictionary = _snaps[-1]
	if r >= float(b["t"]):
		_extrapolate(b, r - float(b["t"]))
		return
	if r <= float(a["t"]):
		_apply_snapshot(a, a, 0.0)
		return
	for i in range(_snaps.size() - 1, 0, -1):
		if float(_snaps[i - 1]["t"]) <= r:
			a = _snaps[i - 1]
			b = _snaps[i]
			break
	var ta := float(a["t"])
	var tb := float(b["t"])
	var u: float
	if tb - ta > 2.0:
		u = clampf(r - (tb - 1.0), 0.0, 1.0)       # idle hold, then the last tick's step
	else:
		u = clampf((r - ta) / (tb - ta), 0.0, 1.0)
	_apply_snapshot(a, b, u)


# Displacement from sample a to sample b, unwrapped across the horizontal seam
# (640 px) and the bottom seam (386 px): a crossing becomes a few-pixel step.
func _unwrapped_delta(a: Dictionary, b: Dictionary) -> Vector2:
	var d: Vector2 = b["pos"] - a["pos"]
	if d.x > 320.0:
		d.x -= 640.0
	elif d.x < -320.0:
		d.x += 640.0
	if d.y > 193.0:
		d.y -= 386.0
	elif d.y < -193.0:
		d.y += 386.0
	return d


func _wrap_into_arena(p: Vector2) -> Vector2:
	if p.x > 652.0:
		p.x -= 640.0
	elif p.x < -12.0:
		p.x += 640.0
	if p.y > 376.0:
		p.y -= 386.0
	elif p.y < -193.0:
		# v0.0.17: was -10. A fighter can really be above the top edge (a jump
		# from the apex platform, a mage blink, an upward dash). The sender never
		# wraps at the top, so neither may we: only a delta that crossed the
		# bottom seam (unwrapped in _unwrapped_delta, half a seam = 193 px) may
		# land here. Drawing a fighter at y = -50 down at y = 336 was wrong.
		p.y += 386.0
	return p


# The render clock has passed the newest sample (a late or missing packet).
# Follow the velocity of the last motion segment for up to EXTRAP_MAX_TICKS,
# then freeze there until a fresh sample arrives. No extrapolation off an idle
# gap (the sender was standing still) or off a teleport.
func _extrapolate(b: Dictionary, over_ticks: float) -> void:
	_pj_extrapolating = true
	var v := Vector2.ZERO
	if _snaps.size() >= 2:
		var a: Dictionary = _snaps[-2]
		var gap := float(b["t"]) - float(a["t"])
		if gap >= 1.0 and gap <= 2.0:
			var d := _unwrapped_delta(a, b)
			if d.length() / gap <= Global.TELEPORT_PX:
				v = d / gap
	# v0.0.17 hotfix. The story: the other player fell, landed, and stood still.
	# Their last sample was still falling, so we kept guessing "still falling"
	# and drew the puppet sinking through the platform. Now the sample says
	# "feet on the ground", so we stop the up-and-down guess and only keep the
	# sideways one. The sender also repeats one packet when it comes to rest
	# (see _sync_network_state), which makes v zero a tick later anyway.
	if bool(b["floor"]):
		v.y = 0.0
	var e := minf(over_ticks, Global.EXTRAP_MAX_TICKS)
	global_position = _wrap_into_arena(b["pos"] + v * e)
	# Feet were on the ground in the newest sample, yet we drew the puppet lower: it sank.
	_pj_dipped = bool(b["floor"]) and global_position.y > float(b["pos"].y) + 1.0
	_apply_state(b, b, 1.0)


func _apply_snapshot(a: Dictionary, b: Dictionary, u: float) -> void:
	var d := _unwrapped_delta(a, b)
	var gap := maxf(float(b["t"]) - float(a["t"]), 1.0)
	# A jump beyond TELEPORT_PX in one tick (mage blink, respawn, an idle gap
	# ending in a teleport) is shown as a step to b, not a 50 ms glide.
	var per_tick := d.length() / (gap if gap <= 2.0 else 1.0)
	if per_tick > Global.TELEPORT_PX and a != b:
		u = 1.0
	global_position = _wrap_into_arena(a["pos"] + d * u)
	_apply_state(a, b, u)


func _apply_state(a: Dictionary, b: Dictionary, u: float) -> void:
	var aa: Vector2 = a["aim"]
	var ab: Vector2 = b["aim"]
	if aa.length_squared() > 0.5 and ab.length_squared() > 0.5:
		aim_direction = aa.slerp(ab, u).normalized()
	else:
		aim_direction = ab if u >= 0.5 else aa
	var st: Dictionary = b if u >= 1.0 else a
	is_facing_right = st["facing"]
	is_dashing = st["dash"]
	is_shielding = st["shield"]
	is_bear_form = st["bear"]
	is_egg = st["egg"]

func _on_remote_projectile(data: Dictionary):
	var p_id = int(data.get("sender", 1))
	if p_id == player_id:
		var w_type = data.get("weapon", "arrow")
		var spawn_pos = Vector2(float(data.get("pos_x", 0.0)), float(data.get("pos_y", 0.0)))
		var dir = Vector2(float(data.get("dir_x", 1.0)), float(data.get("dir_y", 0.0)))
		
		if w_type == "arrow":
			var arrow = ArrowScene.instantiate()
			get_parent().add_child(arrow)
			arrow.init(player_id, spawn_pos, dir)
		elif w_type == "firebolt":
			var bolt = FireboltScene.instantiate()
			get_parent().add_child(bolt)
			bolt.init(player_id, spawn_pos, dir)
		elif w_type == "kunai":
			var kunai = KunaiScene.instantiate()
			get_parent().add_child(kunai)
			kunai.init(player_id, spawn_pos, dir)
		elif w_type == "thorn":
			var thorn = ThornScene.instantiate()
			get_parent().add_child(thorn)
			thorn.init(player_id, spawn_pos, dir)

func _start_dash(input_x: float, input_y: float):
	is_dashing = true
	dash_timer = DASH_DURATION
	dash_cooldown_timer = DASH_COOLDOWN
	
	var dir = Vector2(input_x, input_y)
	if dir.length_squared() < 0.1:
		dir = aim_direction
	dash_dir = dir.normalized()
	_squash_and_stretch(1.4, 0.6)


	# ------------------------------------------------------------------------------
	# ATTACKING
	# This function spawns arrows, fireballs, or sword slashes. 
	# It uses "if" statements (which ask a Yes/No question) to figure out 
	# which class you are playing before spawning the right weapon!
	# ------------------------------------------------------------------------------
func _perform_attack(aim_dir: Vector2):
	match class_type:
		Global.ClassType.RANGER:
			if current_arrows > 0:
				current_arrows -= 1
				attack_cooldown = 0.32
				var spawn_pos = global_position + aim_dir * 18.0
				var arrow = ArrowScene.instantiate()
				get_parent().add_child(arrow)
				arrow.init(player_id, spawn_pos, aim_dir)
				_squash_and_stretch(0.85, 1.15)
				Global.send_net_binary(Global.encode_projectile("arrow", spawn_pos, aim_dir))
		Global.ClassType.KNIGHT:
			attack_cooldown = 0.38
			_execute_sword_slash(aim_dir)
		Global.ClassType.MAGE:
			if mage_charges > 0:
				mage_charges -= 1
				attack_cooldown = 0.35
				var spawn_pos = global_position + aim_dir * 18.0
				var bolt = FireboltScene.instantiate()
				get_parent().add_child(bolt)
				bolt.init(player_id, spawn_pos, aim_dir)
				_squash_and_stretch(0.8, 1.2)
				Global.send_net_binary(Global.encode_projectile("firebolt", spawn_pos, aim_dir))
		Global.ClassType.DRUID:
			if is_bear_form:
				attack_cooldown = 0.5
				_squash_and_stretch(1.2, 0.8)
				_execute_shadow_slash()
			else:
				attack_cooldown = 0.35
				var spawn_pos = global_position + aim_dir * 18.0
				var thorn = ThornScene.instantiate()
				get_parent().add_child(thorn)
				thorn.init(player_id, spawn_pos, aim_dir)
				_squash_and_stretch(0.9, 1.1)
				# Thorns were never networked before: other clients saw no druid projectiles.
				Global.send_net_binary(Global.encode_projectile("thorn", spawn_pos, aim_dir))
		Global.ClassType.ROGUE:
			if rogue_kunai > 0:
				rogue_kunai -= 1
				attack_cooldown = 0.22
				var spawn_pos = global_position + aim_dir * 18.0
				var kunai = KunaiScene.instantiate()
				get_parent().add_child(kunai)
				kunai.init(player_id, spawn_pos, aim_dir)
				Global.send_net_binary(Global.encode_projectile("kunai", spawn_pos, aim_dir))

func _perform_special(aim_dir: Vector2):
	match class_type:
		Global.ClassType.RANGER:
			if current_arrows > 0:
				special_cooldown = 0.8
				current_arrows -= 1
				var arrow = ArrowScene.instantiate()
				get_parent().add_child(arrow)
				arrow.init(player_id, global_position + aim_dir * 18.0, aim_dir)
				velocity = -aim_dir * 310.0 + Vector2.UP * 160.0
				_squash_and_stretch(0.7, 1.3)
				Global.send_net_binary(Global.encode_projectile("arrow", global_position + aim_dir * 18.0, aim_dir))
		Global.ClassType.KNIGHT:
			special_cooldown = 0.75
			is_shielding = true
			shield_timer = 0.38
			_squash_and_stretch(1.25, 0.8)
		Global.ClassType.MAGE:
			special_cooldown = 1.0
			global_position += aim_dir * 95.0
			velocity = aim_dir * 80.0
			_squash_and_stretch(0.5, 1.5)
		Global.ClassType.DRUID:
			special_cooldown = 1.0
			if is_on_floor():
				is_bear_form = not is_bear_form
				_squash_and_stretch(1.5, 0.7)
			else:
				is_shielding = true
				shield_timer = 1.5
				velocity = Vector2.ZERO
				_squash_and_stretch(0.8, 1.2)
		Global.ClassType.ROGUE:
			special_cooldown = 1.1
			_start_dash(aim_dir.x, aim_dir.y)
			_execute_shadow_slash()

func _execute_sword_slash(dir: Vector2):
	melee_area.position = dir * 20.0
	melee_area.rotation = dir.angle()
	melee_area.monitoring = true
	_squash_and_stretch(1.3, 0.7)
	await get_tree().create_timer(0.12).timeout
	melee_area.monitoring = false

func _execute_shadow_slash():
	melee_area.position = Vector2.ZERO
	melee_area.monitoring = true
	await get_tree().create_timer(0.14).timeout
	melee_area.monitoring = false

func _on_melee_area_body_entered(body: Node2D):
	if body.is_in_group("players") and body != self:
		if not body.is_dashing and not body.is_shielding:
			var dir = (body.global_position - global_position).normalized()
			body.take_hit(player_id, dir, "Melee")
	elif body.is_in_group("projectiles"):
		if body.has_method("stick_into_wall") and not body.is_stuck:
			body.queue_free()

func _check_head_stomp():
	if velocity.y > 60.0 and not is_dashing:
		for i in get_slide_collision_count():
			var col = get_slide_collision(i)
			var collider = col.get_collider()
			if collider != null and collider.is_in_group("players") and collider != self:
				if col.get_normal().y < -0.6:
					velocity.y = -390.0
					_squash_and_stretch(0.6, 1.4)
					collider.take_hit(player_id, Vector2.DOWN, "Goomba Stomp")
					return

func _check_screen_wrap():
	var screen_w = 640.0
	var screen_h = 360.0
	if global_position.x < -12.0:
		global_position.x = screen_w + 10.0
	elif global_position.x > screen_w + 12.0:
		global_position.x = -10.0
		
	if global_position.y > screen_h + 16.0:
		global_position.y = -10.0
		velocity.y = 80.0

func take_hit(killer_id: int, _knockback_dir: Vector2, weapon_name: String = "Melee"):
	if is_dead or spawn_invuln_timer > 0.0 or is_dashing or is_bubble:
		return   # a fighter inside the spawn bubble cannot be hit (v0.0.18)
		
	if is_shielding:
		if class_type == Global.ClassType.DRUID:
			is_shielding = false
			is_egg = true
			egg_timer = 3.0
			velocity = Vector2.ZERO
			_squash_and_stretch(1.4, 0.7)
		return
		
	is_dead = true
	visible = false
	collision_shape.set_deferred("disabled", true)
	
	# Observer-authoritative: whichever client saw the hit reports it (the victim's
	# own client, the attacker's for melee and stomps, a spectator). The server
	# accepts the first report and ignores repeats of the same death. Before, only
	# the victim's client could report, so melee kills never counted and a puppet
	# that died on one screen stayed dead there and alive everywhere else.
	Global.send_net_data({
		"type": "player_died",
			"killer": killer_id,
			"victim": player_id,
			"weapon": weapon_name
	})

func _persist_combat_state() -> void:
	# Written only when something changed (a few times per round), read back by
	# arena.gd after a reload that rejoined the same fight.
	var snap := [current_arrows, mage_charges, rogue_kunai, is_bear_form, Global.current_round]
	if snap == _last_persisted:
		return
	_last_persisted = snap
	Global.save_combat_state({"arrows": current_arrows, "charges": mage_charges,
		"kunai": rogue_kunai, "bear": is_bear_form, "round": Global.current_round, "slot": player_id,
		"tick": net_tick})

func restore_combat_state(d: Dictionary) -> void:
	if d.is_empty() or int(d.get("slot", -1)) != player_id:
		return
	current_arrows = clampi(int(d.get("arrows", max_arrows)), 0, max_arrows)
	mage_charges = clampi(int(d.get("charges", 3)), 0, 3)
	rogue_kunai = clampi(int(d.get("kunai", 4)), 0, 4)
	is_bear_form = bool(d.get("bear", false)) and class_type == Global.ClassType.DRUID
	# Movement ticks continue after a reload so receivers never see the counter restart.
	net_tick = (int(d.get("tick", 0)) + 100) & 0xFFFF
	_last_persisted = [current_arrows, mage_charges, rogue_kunai, is_bear_form, Global.current_round]
	queue_redraw()

func force_die() -> void:
	# The server (via arena.gd) says this player is dead. Remote clients cannot
	# detect melee kills locally, so this is the only death path for puppets.
	# Idempotent (the victim's own client already ran take_hit) and sends nothing.
	if is_dead:
		return
	is_dead = true
	visible = false
	velocity = Vector2.ZERO
	is_dashing = false
	is_shielding = false
	is_bubble = false
	bubble_on_ground = false
	is_egg = false
	collision_shape.set_deferred("disabled", true)
	melee_area.monitoring = false

func respawn(spawn_pos: Vector2, on_ground: bool = false):
	# on_ground = true at round start: stand on a platform in a still bubble.
	# on_ground = false after a death: float down from the sky in the glide bubble.
	global_position = spawn_pos
	target_net_pos = spawn_pos
	_last_rx_tick = -1
	_clear_snapshots()
	_pj_last_pos = Vector2.INF
	_pj_last_speed = -1.0
	_pj_sender_moving = false
	_last_sync_bytes = PackedByteArray()
	velocity = Vector2.ZERO
	is_dead = false
	visible = true
	is_dashing = false
	is_shielding = false
	is_egg = false
	is_bear_form = false
	# v0.0.18: the bubble replaces the old one-second glow. The shield bit goes
	# out in every movement packet, so every screen draws the bubble and every
	# weapon bounces off it, just like a knight's shield.
	is_bubble = true
	bubble_on_ground = on_ground
	bubble_timer = BUBBLE_GROUND_TIME if on_ground else BUBBLE_TIME
	if on_ground:
		# Look at the middle of the arena, so the fight is in front of you.
		is_facing_right = spawn_pos.x < 320.0
		aim_direction = Vector2.RIGHT if is_facing_right else Vector2.LEFT
	is_shielding = true
	shield_timer = 0.0
	spawn_invuln_timer = 0.0
	collision_shape.set_deferred("disabled", false)
	_apply_class_defaults()
	_squash_and_stretch(0.5, 1.5)

func _pop_bubble() -> void:
	# The bubble is gone. From now on hits count.
	is_bubble = false
	bubble_on_ground = false
	is_shielding = false
	shield_timer = 0.0
	_squash_and_stretch(1.3, 0.7)

func pickup_arrow():
	if current_arrows < max_arrows:
		current_arrows += 1
		_squash_and_stretch(1.15, 0.85)

func catch_arrow():
	if current_arrows < max_arrows:
		current_arrows += 1
	_squash_and_stretch(1.3, 0.7)

func play_parry_effect():
	_squash_and_stretch(1.4, 0.6)

const NAME_TAG_Y = -40.0       # the text baseline sits this far above the fighter's middle
const NAME_TAG_SIZE = 10       # font size in px

func _draw_name_tag() -> void:
	# Name tag (v0.0.19). The story: in the playtest nobody knew which fighter
	# was theirs. Now the name floats above every head. Your own tag is pale
	# yellow, the others are white. The squash animation scales the whole
	# fighter, so we scale the text back the other way and it never stretches.
	var tag: String = str(Global.player_names.get(player_id, "P" + str(player_id)))
	var font: Font = ThemeDB.fallback_font
	var tag_col := Color(1.0, 0.95, 0.6) if is_local_player else Color(1.0, 1.0, 1.0)
	var inv := Vector2(1.0 / max(scale.x, 0.05), 1.0 / max(scale.y, 0.05))
	var w: float = font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_TAG_SIZE).x
	draw_set_transform(Vector2(0.0, NAME_TAG_Y * inv.y), 0.0, inv)
	draw_string_outline(font, Vector2(-w / 2.0, 0.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1,
		NAME_TAG_SIZE, 3, Color(0.0, 0.0, 0.0, 0.9))
	draw_string(font, Vector2(-w / 2.0, 0.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_TAG_SIZE, tag_col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _squash_and_stretch(sx: float, sy: float):
	var tween = create_tween()
	scale = Vector2(sx, sy)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


	# ------------------------------------------------------------------------------
	# DRAWING THE CHARACTER
	# We don't use 3D models here! Instead, we tell the computer to draw 
	# simple shapes (circles, lines, and rectangles) to build our pixel heroes.
	# ------------------------------------------------------------------------------
func _draw():
	if is_dead:
		return

	_draw_name_tag()

	var class_info = Global.CLASS_INFO[class_type]
	var base_col: Color = class_info["color"]

	var facing_mul = 1.0 if is_facing_right else -1.0
	var run_cycle = sin(anim_time) * 2.5 if abs(velocity.x) > 20.0 and is_on_floor() else 0.0
	var breath = sin(anim_time * 0.4) * 0.8
	
	if spawn_invuln_timer > 0.0:
		draw_arc(Vector2.ZERO, 18.0 + breath, 0.0, TAU, 20, Color(1.0, 0.9, 0.3, 0.6), 2.0)
		draw_circle(Vector2.ZERO, 16.0, Color(1.0, 1.0, 0.6, 0.25))

	if is_bubble and is_shielding:
		# The spawn bubble: a soft blue ball with a little shine on top.
		var bob = sin(anim_time * 0.6) * 1.5
		draw_circle(Vector2(0, -8 + bob), 24.0, Color(0.6, 0.9, 1.0, 0.18))
		draw_arc(Vector2(0, -8 + bob), 24.0 + breath, 0.0, TAU, 32, Color(0.85, 0.97, 1.0, 0.9), 2.0)
		draw_arc(Vector2(-6, -16 + bob), 9.0, PI * 1.05, PI * 1.55, 8, Color(1.0, 1.0, 1.0, 0.8), 1.5)
		
	# --- DRUID SHAPESHIFTING OVERRIDES ---
	# (not while inside the spawn bubble: the shield bit is on, but it is not the phoenix)
	var is_druid_special = (class_type == Global.ClassType.DRUID) and (is_bear_form or is_egg or is_dashing or (is_shielding and not is_bubble))
	
	if is_druid_special:
		if is_egg:
			# Large patterned egg
			draw_circle(Vector2(0, -9), 11.0, Color(0.9, 0.8, 0.6))
			draw_circle(Vector2(0, -11), 8.0, Color(0.95, 0.9, 0.8)) # Highlight
			draw_line(Vector2(-8, -9), Vector2(8, -9), Color(0.8, 0.4, 0.2), 3.0) # Pattern
			draw_line(Vector2(-6, -4), Vector2(6, -4), Color(0.8, 0.4, 0.2), 3.0)
		elif is_shielding:
			# Phoenix Form
			var flap = sin(Time.get_ticks_msec() * 0.015) * 8.0
			# Body core
			draw_circle(Vector2(0, -12 + breath), 8.0, Color(1.0, 0.5, 0.1))
			draw_circle(Vector2(0, -12 + breath), 5.0, Color(1.0, 0.8, 0.2))
			# Flaming wings
			var wing_pts = PackedVector2Array([
				Vector2(-4, -12 + breath),
				Vector2(-24, -16 + breath + flap),
				Vector2(-14, -6 + breath + flap * 0.5)
			])
			draw_colored_polygon(wing_pts, Color(0.9, 0.3, 0.1, 0.8))
			var wing_pts2 = PackedVector2Array([
				Vector2(4, -12 + breath),
				Vector2(24, -16 + breath + flap),
				Vector2(14, -6 + breath + flap * 0.5)
			])
			draw_colored_polygon(wing_pts2, Color(0.9, 0.3, 0.1, 0.8))
			# Tail feathers
			draw_line(Vector2(0, -8 + breath), Vector2(-6, 2 + breath), Color(1.0, 0.4, 0.1), 3.0)
			draw_line(Vector2(0, -8 + breath), Vector2(6, 2 + breath), Color(1.0, 0.4, 0.1), 3.0)
			# Beak
			draw_colored_polygon(PackedVector2Array([
				Vector2(4 * facing_mul, -14 + breath),
				Vector2(12 * facing_mul, -12 + breath),
				Vector2(4 * facing_mul, -10 + breath)
			]), Color(1.0, 0.9, 0.2))
			# Eye
			draw_circle(Vector2(3 * facing_mul, -14 + breath), 1.5, Color(1.0, 1.0, 1.0))
		elif is_dashing:
			# Storm Crow
			var flap = 14.0 if sin(Time.get_ticks_msec() * 0.03) > 0 else -4.0
			draw_circle(Vector2(0, -12), 9.0, Color(0.15, 0.15, 0.2)) # Body
			draw_circle(Vector2(6 * facing_mul, -14), 5.0, Color(0.15, 0.15, 0.2)) # Head
			draw_colored_polygon(PackedVector2Array([
				Vector2(9 * facing_mul, -16),
				Vector2(16 * facing_mul, -13),
				Vector2(9 * facing_mul, -12)
			]), Color(0.8, 0.7, 0.2)) # Beak
			draw_circle(Vector2(7 * facing_mul, -15), 1.0, Color(0.8, 0.1, 0.1)) # Red eye
			draw_line(Vector2(-12, -12), Vector2(-12, -12 + flap), Color(0.1, 0.1, 0.15), 6.0) # Wing back
			draw_line(Vector2(0, -12), Vector2(0, -12 + flap), Color(0.2, 0.2, 0.25), 6.0) # Wing front
			draw_line(Vector2(-8 * facing_mul, -10), Vector2(-16 * facing_mul, -8), Color(0.15, 0.15, 0.2), 4.0) # Tail
		elif is_bear_form:
			# Heavy Bear Form
			var bear_col = Color(0.4, 0.25, 0.15)
			var belly_col = Color(0.5, 0.35, 0.2)
			# Back leg
			draw_rect(Rect2(-8 - run_cycle, -6, 6, 8), Color(0.25, 0.15, 0.1), true)
			draw_rect(Rect2(4 + run_cycle, -6, 6, 8), Color(0.25, 0.15, 0.1), true)
			# Main Body (Huge Oval)
			draw_circle(Vector2(0, -15 + breath * 0.5), 16.0, bear_col)
			draw_circle(Vector2(-2, -12 + breath * 0.5), 12.0, belly_col)
			# Front leg
			draw_rect(Rect2(-12 + run_cycle, -4, 6, 8), bear_col, true)
			draw_rect(Rect2(8 - run_cycle, -4, 6, 8), bear_col, true)
			# Head
			draw_circle(Vector2(12 * facing_mul, -20 + breath * 0.5), 10.0, bear_col)
			# Snout
			draw_circle(Vector2(18 * facing_mul, -18 + breath * 0.5), 5.0, belly_col)
			draw_circle(Vector2(21 * facing_mul, -19 + breath * 0.5), 2.0, Color(0.1, 0.1, 0.1)) # Nose
			# Ears
			draw_circle(Vector2(6 * facing_mul, -28 + breath * 0.5), 4.0, bear_col)
			draw_circle(Vector2(6 * facing_mul, -28 + breath * 0.5), 2.0, Color(0.2, 0.1, 0.05))
			# Eye
			draw_circle(Vector2(14 * facing_mul, -22 + breath * 0.5), 1.5, Color(1.0, 1.0, 1.0))
			draw_circle(Vector2((14 * facing_mul) + (1 * facing_mul), -22 + breath * 0.5), 0.8, Color(0.0, 0.0, 0.0))
		return
		
	# --- NORMAL HUMANOID DRAWING ---

	if is_shielding and class_type == Global.ClassType.KNIGHT and not is_bubble:
		draw_circle(Vector2.ZERO, 19.0, Color(0.3, 0.6, 1.0, 0.45))
		draw_arc(Vector2.ZERO, 19.0, 0.0, TAU, 24, Color(0.8, 0.95, 1.0), 3.0)
		
	if is_dashing:
		draw_circle(-dash_dir * 12.0, 10.0, Color(base_col.r, base_col.g, base_col.b, 0.45))
		draw_circle(-dash_dir * 22.0, 7.0, Color(base_col.r, base_col.g, base_col.b, 0.25))

	var aim_len = 36.0
	var laser_start = aim_direction * 14.0
	var laser_end = aim_direction * aim_len
	draw_line(laser_start, laser_end, Color(1.0, 1.0, 1.0, 0.3), 1.0)
	draw_circle(laser_end, 2.0, Color(1.0, 0.9, 0.3, 0.75))

	var cape_col = Color(base_col.r * 0.6, base_col.g * 0.6, base_col.b * 0.6)
	# Clamped: at dash speed the offset reached ±17 px and flipped the quad into a
	# self-intersecting polygon ("Invalid polygon data, triangulation failed").
	var cape_wave = clampf(sin(anim_time * 0.8) * 3.0 - (velocity.x * 0.03), -8.0, 8.0)
	var cape_pts = PackedVector2Array([
		Vector2(-4 * facing_mul, -8),
		Vector2(2 * facing_mul, -8),
		Vector2((-9 * facing_mul) + cape_wave, 8),
		Vector2((-14 * facing_mul) + cape_wave * 1.3, 7)
	])
	draw_colored_polygon(cape_pts, cape_col)

	var foot_l = Vector2(-4, 9 + run_cycle)
	var foot_r = Vector2(4, 9 - run_cycle)
	draw_rect(Rect2(foot_l.x - 2, foot_l.y - 2, 4, 3), Color(0.18, 0.12, 0.1), true)
	draw_rect(Rect2(foot_r.x - 2, foot_r.y - 2, 4, 3), Color(0.18, 0.12, 0.1), true)

	draw_rect(Rect2(-7, -10 + breath, 14, 18), base_col, true)
	draw_rect(Rect2(-7, -10 + breath, 14, 18), Color(0.08, 0.08, 0.12), false, 1.5)
	draw_rect(Rect2(-7, -2 + breath, 14, 3), Color(0.3, 0.2, 0.1), true)
	draw_rect(Rect2(-2, -3 + breath, 4, 5), Color(0.95, 0.8, 0.2), true)
	
	draw_rect(Rect2(-6, -18 + breath, 12, 10), Color(0.98, 0.85, 0.72), true)
	draw_rect(Rect2(-6, -18 + breath, 12, 10), Color(0.1, 0.08, 0.1), false, 1.0)
	
	var eye_x = 2 * facing_mul
	draw_rect(Rect2(eye_x, -15 + breath, 2, 3), Color(0.1, 0.1, 0.2), true)
	draw_rect(Rect2(eye_x + (1 if is_facing_right else 0), -15 + breath, 1, 1), Color(1.0, 1.0, 1.0), true)
	
	match class_type:
		Global.ClassType.RANGER:
			draw_colored_polygon(PackedVector2Array([Vector2(-8, -17 + breath), Vector2(0, -24 + breath), Vector2(8, -17 + breath)]), Color(0.15, 0.55, 0.25))
			draw_line(Vector2(2 * facing_mul, -22 + breath), Vector2(7 * facing_mul, -28 + breath), Color(0.95, 0.2, 0.2), 2.5)
			var bow_pos = aim_direction * 12.0
			var bow_angle = aim_direction.angle()
			var bow_t = Transform2D(bow_angle, bow_pos)
			var b1 = bow_t * Vector2(-2, -10)
			var b2 = bow_t * Vector2(5, 0)
			var b3 = bow_t * Vector2(-2, 10)
			draw_line(b1, b2, Color(0.55, 0.35, 0.15), 2.5)
			draw_line(b2, b3, Color(0.55, 0.35, 0.15), 2.5)
			draw_line(b1, b3, Color(0.9, 0.9, 0.9, 0.8), 1.0)
		Global.ClassType.KNIGHT:
			draw_rect(Rect2(-7, -21 + breath, 14, 9), Color(0.7, 0.75, 0.8), true)
			draw_rect(Rect2(-7, -21 + breath, 14, 9), Color(0.2, 0.2, 0.25), false, 1.2)
			draw_line(Vector2(-4, -16 + breath), Vector2(4, -16 + breath), Color(0.1, 0.1, 0.15), 2.0)
			draw_line(Vector2(0, -21 + breath), Vector2(0, -28 + breath), Color(0.95, 0.2, 0.2), 3.5)
			var sword_pos = aim_direction * 10.0
			var sword_end = sword_pos + aim_direction * 18.0
			draw_line(sword_pos, sword_end, Color(0.9, 0.92, 0.98), 3.0)
			draw_line(sword_pos - aim_direction.orthogonal() * 5.0, sword_pos + aim_direction.orthogonal() * 5.0, Color(0.85, 0.7, 0.2), 2.5)
		Global.ClassType.MAGE:
			draw_colored_polygon(PackedVector2Array([Vector2(-9, -17 + breath), Vector2(0, -29 + breath), Vector2(9, -17 + breath)]), Color(0.25, 0.12, 0.45))
			draw_circle(Vector2(0, -29 + breath), 3.0, Color(1.0, 0.8, 0.2))
			var staff_end = aim_direction * 16.0
			draw_line(Vector2.ZERO, staff_end, Color(0.4, 0.25, 0.15), 2.0)
			draw_circle(staff_end, 4.5, Color(1.0, 0.5, 0.1, 0.9))
			draw_circle(staff_end, 2.5, Color(1.0, 0.9, 0.5))
		Global.ClassType.DRUID:
			# Normal human druid details
			draw_colored_polygon(PackedVector2Array([Vector2(-8, -17 + breath), Vector2(0, -28 + breath), Vector2(8, -17 + breath)]), Color(0.2, 0.6, 0.2))
			draw_circle(Vector2(0, -28 + breath), 4.0, Color(0.8, 0.9, 0.2))
			draw_circle(Vector2(-12, -20 + sin(Time.get_ticks_msec()*0.005)*3), 3.0, Color(0.4, 0.9, 0.4))
		Global.ClassType.ROGUE:
			draw_colored_polygon(PackedVector2Array([Vector2(-7, -20 + breath), Vector2(0, -25 + breath), Vector2(7, -20 + breath), Vector2(7, -11 + breath), Vector2(-7, -11 + breath)]), Color(0.18, 0.12, 0.25))
			draw_rect(Rect2(eye_x, -16 + breath, 3, 2), Color(0.85, 0.3, 1.0), true)
			var d1 = aim_direction * 14.0
			var d2 = aim_direction * 10.0 + aim_direction.orthogonal() * 6.0
			draw_line(Vector2.ZERO, d1, Color(0.9, 0.95, 1.0), 2.0)
			draw_line(Vector2.ZERO, d2, Color(0.9, 0.95, 1.0), 2.0)

	if class_type == Global.ClassType.RANGER:
		for i in range(max_arrows):
			var ax = -8 + i * 8
			var col = Color(1.0, 0.85, 0.2) if i < current_arrows else Color(0.3, 0.3, 0.3, 0.5)
			draw_line(Vector2(ax, -30 + breath), Vector2(ax, -36 + breath), col, 2.5)
			draw_line(Vector2(ax - 2, -34 + breath), Vector2(ax, -36 + breath), col, 1.5)
	elif class_type == Global.ClassType.MAGE:
		for i in range(3):
			var mx = -8 + i * 8
			var col = Color(1.0, 0.5, 0.1) if i < mage_charges else Color(0.3, 0.3, 0.3, 0.5)
			draw_circle(Vector2(mx, -32 + breath), 3.0, col)
	elif class_type == Global.ClassType.ROGUE:
		for i in range(4):
			var kx = -9 + i * 6
			var col = Color(0.85, 0.35, 1.0) if i < rogue_kunai else Color(0.3, 0.3, 0.3, 0.5)
			draw_circle(Vector2(kx, -32 + breath), 2.5, col)

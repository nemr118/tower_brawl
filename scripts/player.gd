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
var shield_timer: float = 0.0

var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0

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
	if spawn_invuln_timer > 0.0:
		spawn_invuln_timer -= delta
	if shield_timer > 0.0:
		shield_timer -= delta
		if shield_timer <= 0.0:
			is_shielding = false
	if dash_timer > 0.0:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false
			
	# REMOTE PLAYER REPLICATION
	if not is_local_player:
		if target_net_pos.length_squared() > 0.1:
			global_position = global_position.lerp(target_net_pos, 24.0 * delta)
		queue_redraw()
		return
		
	# LOCAL PLAYER CONTROLS
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
		_sync_network_state(delta)
		queue_redraw()
		return

	var prefix = "p" + str(player_id) + "_"
	
	var input_x = Input.get_axis(prefix + "left", prefix + "right")
	var input_y = Input.get_axis(prefix + "up", prefix + "down")
	
	var raw_aim = Vector2.ZERO
	if is_local_player and not OS.has_feature("web"):
		raw_aim = get_global_mouse_position() - global_position
		if raw_aim.length_squared() > 0.08:
			aim_direction = raw_aim.normalized()
			is_facing_right = raw_aim.x > 0
	else:
		raw_aim = Vector2(input_x, input_y)
		if raw_aim.length_squared() > 0.08:
			aim_direction = raw_aim.normalized()
			if input_x > 0.15:
				is_facing_right = true
			elif input_x < -0.15:
				is_facing_right = false
		else:
			aim_direction = Vector2.RIGHT if is_facing_right else Vector2.LEFT

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
		
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		_squash_and_stretch(0.7, 1.3)
		
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

func _sync_network_state(delta: float):
	sync_timer += delta
	if sync_timer >= 0.033:
		sync_timer = 0.0
		Global.send_net_data({
			"type": "sync_pos",
			"x": global_position.x,
			"y": global_position.y,
			"aim_x": aim_direction.x,
			"aim_y": aim_direction.y,
			"facing": is_facing_right,
			"dash": is_dashing,
			"shield": is_shielding
		})

func _on_player_state_received(p_id: int, data: Dictionary):
	if p_id == player_id:
		target_net_pos = Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
		aim_direction = Vector2(float(data.get("aim_x", 1.0)), float(data.get("aim_y", 0.0)))
		is_facing_right = bool(data.get("facing", true))
		is_dashing = bool(data.get("dash", false))
		is_shielding = bool(data.get("shield", false))

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
				Global.send_net_data({
					"type": "spawn_projectile",
					"weapon": "arrow",
					"pos_x": spawn_pos.x,
					"pos_y": spawn_pos.y,
					"dir_x": aim_dir.x,
					"dir_y": aim_dir.y
				})
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
				Global.send_net_data({
					"type": "spawn_projectile",
					"weapon": "firebolt",
					"pos_x": spawn_pos.x,
					"pos_y": spawn_pos.y,
					"dir_x": aim_dir.x,
					"dir_y": aim_dir.y
				})
		Global.ClassType.ROGUE:
			if rogue_kunai > 0:
				rogue_kunai -= 1
				attack_cooldown = 0.22
				var spawn_pos = global_position + aim_dir * 18.0
				var kunai = KunaiScene.instantiate()
				get_parent().add_child(kunai)
				kunai.init(player_id, spawn_pos, aim_dir)
				Global.send_net_data({
					"type": "spawn_projectile",
					"weapon": "kunai",
					"pos_x": spawn_pos.x,
					"pos_y": spawn_pos.y,
					"dir_x": aim_dir.x,
					"dir_y": aim_dir.y
				})

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
				Global.send_net_data({
					"type": "spawn_projectile",
					"weapon": "arrow",
					"pos_x": global_position.x + aim_dir.x * 18.0,
					"pos_y": global_position.y + aim_dir.y * 18.0,
					"dir_x": aim_dir.x,
					"dir_y": aim_dir.y
				})
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
			body.take_hit(player_id, dir)
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
					collider.take_hit(player_id, Vector2.DOWN)
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

func take_hit(killer_id: int, _knockback_dir: Vector2):
	if is_dead or spawn_invuln_timer > 0.0 or is_dashing or is_shielding:
		return
		
	is_dead = true
	visible = false
	collision_shape.set_deferred("disabled", true)
	emit_signal("player_died", killer_id, player_id)
	
	if is_local_player:
		Global.send_net_data({
			"type": "player_hit",
			"killer": killer_id,
			"victim": player_id
		})

func respawn(spawn_pos: Vector2):
	global_position = spawn_pos
	target_net_pos = spawn_pos
	velocity = Vector2.ZERO
	is_dead = false
	visible = true
	is_dashing = false
	is_shielding = false
	spawn_invuln_timer = 1.0
	collision_shape.set_deferred("disabled", false)
	_apply_class_defaults()
	_squash_and_stretch(0.5, 1.5)

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

	var class_info = Global.CLASS_INFO[class_type]
	var base_col: Color = class_info["color"]

	var facing_mul = 1.0 if is_facing_right else -1.0
	var run_cycle = sin(anim_time) * 2.5 if abs(velocity.x) > 20.0 and is_on_floor() else 0.0
	var breath = sin(anim_time * 0.4) * 0.8
	
	if spawn_invuln_timer > 0.0:
		draw_arc(Vector2.ZERO, 18.0 + breath, 0.0, TAU, 20, Color(1.0, 0.9, 0.3, 0.6), 2.0)
		draw_circle(Vector2.ZERO, 16.0, Color(1.0, 1.0, 0.6, 0.25))
		
	if is_shielding:
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
	var cape_wave = sin(anim_time * 0.8) * 3.0 - (velocity.x * 0.03)
	var cape_pts = [
		Vector2(-4 * facing_mul, -8),
		Vector2(2 * facing_mul, -8),
		Vector2((-9 * facing_mul) + cape_wave, 8),
		Vector2((-14 * facing_mul) + cape_wave * 1.3, 7)
	]
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
			draw_colored_polygon([Vector2(-8, -17 + breath), Vector2(0, -24 + breath), Vector2(8, -17 + breath)], Color(0.15, 0.55, 0.25))
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
			draw_colored_polygon([Vector2(-9, -17 + breath), Vector2(0, -29 + breath), Vector2(9, -17 + breath)], Color(0.25, 0.12, 0.45))
			draw_circle(Vector2(0, -29 + breath), 3.0, Color(1.0, 0.8, 0.2))
			var staff_end = aim_direction * 16.0
			draw_line(Vector2.ZERO, staff_end, Color(0.4, 0.25, 0.15), 2.0)
			draw_circle(staff_end, 4.5, Color(1.0, 0.5, 0.1, 0.9))
			draw_circle(staff_end, 2.5, Color(1.0, 0.9, 0.5))
		Global.ClassType.ROGUE:
			draw_colored_polygon([Vector2(-7, -20 + breath), Vector2(0, -25 + breath), Vector2(7, -20 + breath), Vector2(7, -11 + breath), Vector2(-7, -11 + breath)], Color(0.18, 0.12, 0.25))
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

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
var respawn_timer: float = 0.0
var spawn_invuln_timer: float = 1.2

# Class Resources
var max_arrows: int = 3
var current_arrows: int = 3

var mage_charges: int = 3
var mage_recharge_timer: float = 0.0

var rogue_kunai: int = 4
var rogue_recharge_timer: float = 0.0

var attack_cooldown: float = 0.0
var special_cooldown: float = 0.0

# Scenes for projectiles
const ArrowScene = preload("res://scenes/arrow.tscn")
const FireboltScene = preload("res://scenes/firebolt.tscn")
const KunaiScene = preload("res://scenes/kunai.tscn")

@onready var collision_shape = $CollisionShape2D
@onready var melee_area = $MeleeArea
@onready var melee_shape = $MeleeArea/CollisionShape2D

func _ready():
	add_to_group("players")
	_apply_class_defaults()
	melee_area.monitoring = false

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

func _physics_process(delta: float):
	if is_dead:
		return
		
	# Timers
	if attack_cooldown > 0.0: attack_cooldown -= delta
	if special_cooldown > 0.0: special_cooldown -= delta
	if spawn_invuln_timer > 0.0: spawn_invuln_timer -= delta
	if dash_cooldown_timer > 0.0: dash_cooldown_timer -= delta
	
	# Recharge Mage/Rogue charges
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
			
	# Dash Handling
	if is_dashing:
		dash_timer -= delta
		velocity = dash_dir * DASH_SPEED
		move_and_slide()
		_check_screen_wrap()
		queue_redraw()
		if dash_timer <= 0.0:
			is_dashing = false
			velocity = dash_dir * (SPEED * 0.5)
		return
		
	# Shield Handling (Knight)
	if is_shielding:
		shield_timer -= delta
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		if not is_on_floor():
			velocity.y += GRAVITY * delta
		move_and_slide()
		queue_redraw()
		if shield_timer <= 0.0:
			is_shielding = false
		return

	# Input Prefix (p1_, p2_, p3_, p4_)
	var prefix = "p" + str(player_id) + "_"
	
	# Horizontal Movement
	var input_x = Input.get_axis(prefix + "left", prefix + "right")
	var input_y = Input.get_axis(prefix + "up", prefix + "down")
	
	if input_x > 0.1:
		is_facing_right = true
		velocity.x = move_toward(velocity.x, SPEED, ACCEL * delta)
	elif input_x < -0.1:
		is_facing_right = false
		velocity.x = move_toward(velocity.x, -SPEED, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)
		
	# Gravity & Coyote Time
	if is_on_floor():
		coyote_timer = 0.12
		if velocity.y > 0:
			velocity.y = 0.0
	else:
		coyote_timer -= delta
		var current_gravity = FALL_GRAVITY if velocity.y > 0 else GRAVITY
		velocity.y += current_gravity * delta
		
	# Jump Buffering
	if Input.is_action_just_pressed(prefix + "jump"):
		jump_buffer_timer = 0.12
	else:
		jump_buffer_timer -= delta
		
	# Execute Jump
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		_squash_and_stretch(0.7, 1.3)
		
	# Variable Jump Cut
	if Input.is_action_just_released(prefix + "jump") and velocity.y < -120.0:
		velocity.y = -120.0
		
	# Dash / Dodge
	if Input.is_action_just_pressed(prefix + "dash") and dash_cooldown_timer <= 0.0:
		_start_dash(input_x, input_y)
		
	# Attack Input
	if Input.is_action_just_pressed(prefix + "attack") and attack_cooldown <= 0.0:
		_perform_attack(input_x, input_y)
		
	# Special Input
	if Input.is_action_just_pressed(prefix + "special") and special_cooldown <= 0.0:
		_perform_special(input_x, input_y)

	move_and_slide()
	_check_screen_wrap()
	_check_head_stomp()
	queue_redraw()

func _start_dash(input_x: float, input_y: float):
	is_dashing = true
	dash_timer = DASH_DURATION
	dash_cooldown_timer = DASH_COOLDOWN
	
	var dir = Vector2(input_x, input_y)
	if dir.length_squared() < 0.1:
		dir = Vector2.RIGHT if is_facing_right else Vector2.LEFT
	dash_dir = dir.normalized()
	_squash_and_stretch(1.4, 0.6)

func _perform_attack(input_x: float, input_y: float):
	var aim_dir = Vector2(input_x, input_y)
	if aim_dir.length_squared() < 0.1:
		aim_dir = Vector2.RIGHT if is_facing_right else Vector2.LEFT
	aim_dir = aim_dir.normalized()
	
	match class_type:
		Global.ClassType.RANGER:
			if current_arrows > 0:
				current_arrows -= 1
				attack_cooldown = 0.32
				var spawn_pos = global_position + aim_dir * 14.0
				var arrow = ArrowScene.instantiate()
				get_parent().add_child(arrow)
				arrow.init(player_id, spawn_pos, aim_dir)
				_squash_and_stretch(0.85, 1.15)
		Global.ClassType.KNIGHT:
			attack_cooldown = 0.38
			_execute_sword_slash(aim_dir)
		Global.ClassType.MAGE:
			if mage_charges > 0:
				mage_charges -= 1
				attack_cooldown = 0.35
				var spawn_pos = global_position + aim_dir * 14.0
				var bolt = FireboltScene.instantiate()
				get_parent().add_child(bolt)
				bolt.init(player_id, spawn_pos, aim_dir)
		Global.ClassType.ROGUE:
			if rogue_kunai > 0:
				rogue_kunai -= 1
				attack_cooldown = 0.22
				var spawn_pos = global_position + aim_dir * 14.0
				var kunai = KunaiScene.instantiate()
				get_parent().add_child(kunai)
				kunai.init(player_id, spawn_pos, aim_dir)

func _perform_special(input_x: float, input_y: float):
	match class_type:
		Global.ClassType.RANGER:
			# Backflip Retreat Shot
			if current_arrows > 0:
				special_cooldown = 0.8
				current_arrows -= 1
				var shoot_dir = Vector2.RIGHT if is_facing_right else Vector2.LEFT
				var arrow = ArrowScene.instantiate()
				get_parent().add_child(arrow)
				arrow.init(player_id, global_position + shoot_dir * 14.0, shoot_dir)
				# Vault backward
				velocity = Vector2(-shoot_dir.x * 260.0, -320.0)
				_squash_and_stretch(0.7, 1.3)
		Global.ClassType.KNIGHT:
			# Shield Parry Guard
			special_cooldown = 0.75
			is_shielding = true
			shield_timer = 0.38
			_squash_and_stretch(1.25, 0.8)
		Global.ClassType.MAGE:
			# Arcane Void Blink (Teleport 90px in direction)
			special_cooldown = 1.0
			var blink_dir = Vector2(input_x, input_y)
			if blink_dir.length_squared() < 0.1:
				blink_dir = Vector2.RIGHT if is_facing_right else Vector2.LEFT
			blink_dir = blink_dir.normalized()
			global_position += blink_dir * 85.0
			velocity = blink_dir * 80.0
			_squash_and_stretch(0.5, 1.5)
		Global.ClassType.ROGUE:
			# Shadow Dash Ambush
			special_cooldown = 1.1
			_start_dash(input_x, input_y)
			_execute_shadow_slash()

func _execute_sword_slash(dir: Vector2):
	melee_area.position = dir * 18.0
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
				if col.get_normal().y < -0.6: # Landing on head from above
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
	if is_dead or spawn_invuln_timer > 0.0:
		return
		
	is_dead = true
	visible = false
	collision_shape.set_deferred("disabled", true)
	emit_signal("player_died", killer_id, player_id)

func respawn(spawn_pos: Vector2):
	global_position = spawn_pos
	velocity = Vector2.ZERO
	is_dead = false
	visible = true
	is_dashing = false
	is_shielding = false
	spawn_invuln_timer = 1.3
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

func _draw():
	if is_dead:
		return
		
	var facing_mul = 1.0 if is_facing_right else -1.0
	var class_info = Global.CLASS_INFO[class_type]
	var base_col: Color = class_info["color"]
	
	if spawn_invuln_timer > 0.0:
		draw_circle(Vector2.ZERO, 15.0, Color(1.0, 1.0, 0.6, 0.35))
		
	if is_shielding:
		draw_circle(Vector2.ZERO, 16.0, Color(0.4, 0.7, 1.0, 0.5))
		draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 16, Color(0.8, 0.95, 1.0), 2.5)
		
	if is_dashing:
		draw_circle(-dash_dir * 10.0, 9.0, Color(base_col.r, base_col.g, base_col.b, 0.4))
		
	# Body / Tunic
	draw_rect(Rect2(-7, -10, 14, 18), base_col, true)
	draw_rect(Rect2(-7, -10, 14, 18), Color(0.1, 0.1, 0.15), false, 1.5)
	
	# Head
	draw_rect(Rect2(-6, -18, 12, 10), Color(0.98, 0.85, 0.72), true)
	
	# Eyes
	var eye_x = 2 * facing_mul
	draw_rect(Rect2(eye_x, -16, 2, 3), Color(0.1, 0.1, 0.2), true)
	
	match class_type:
		Global.ClassType.RANGER:
			draw_colored_polygon([Vector2(-8, -17), Vector2(0, -23), Vector2(8, -17)], Color(0.15, 0.6, 0.25))
			draw_line(Vector2(2 * facing_mul, -22), Vector2(6 * facing_mul, -27), Color(0.95, 0.2, 0.2), 2.0)
			draw_arc(Vector2(9 * facing_mul, -4), 8.0, -1.2, 1.2, 8, Color(0.65, 0.4, 0.2), 2.0)
		Global.ClassType.KNIGHT:
			draw_rect(Rect2(-7, -21, 14, 8), Color(0.7, 0.75, 0.8), true)
			draw_rect(Rect2(-7, -21, 14, 8), Color(0.2, 0.2, 0.25), false, 1.2)
			draw_line(Vector2(0, -21), Vector2(0, -26), Color(0.9, 0.15, 0.15), 3.0)
			draw_line(Vector2(8 * facing_mul, 4), Vector2(14 * facing_mul, -10), Color(0.85, 0.85, 0.9), 2.5)
		Global.ClassType.MAGE:
			draw_colored_polygon([Vector2(-9, -17), Vector2(0, -28), Vector2(9, -17)], Color(0.3, 0.15, 0.5))
			draw_circle(Vector2(0, -28), 2.5, Color(1.0, 0.8, 0.2))
			draw_circle(Vector2(10 * facing_mul, -4), 4.0, Color(1.0, 0.5, 0.1))
		Global.ClassType.ROGUE:
			draw_colored_polygon([Vector2(-7, -19), Vector2(0, -23), Vector2(7, -19), Vector2(7, -11), Vector2(-7, -11)], Color(0.2, 0.15, 0.25))
			draw_line(Vector2(7 * facing_mul, 0), Vector2(13 * facing_mul, -4), Color(0.9, 0.9, 0.95), 2.0)
			draw_line(Vector2(5 * facing_mul, 4), Vector2(11 * facing_mul, 2), Color(0.9, 0.9, 0.95), 2.0)

	if class_type == Global.ClassType.RANGER:
		for i in range(max_arrows):
			var ax = -8 + i * 8
			var col = Color(1.0, 0.85, 0.2) if i < current_arrows else Color(0.4, 0.4, 0.4, 0.5)
			draw_line(Vector2(ax, -25), Vector2(ax, -30), col, 2.0)
	elif class_type == Global.ClassType.MAGE:
		for i in range(3):
			var mx = -8 + i * 8
			var col = Color(1.0, 0.5, 0.1) if i < mage_charges else Color(0.4, 0.4, 0.4, 0.5)
			draw_circle(Vector2(mx, -26), 2.5, col)
	elif class_type == Global.ClassType.ROGUE:
		for i in range(4):
			var kx = -9 + i * 6
			var col = Color(0.8, 0.4, 1.0) if i < rogue_kunai else Color(0.4, 0.4, 0.4, 0.5)
			draw_circle(Vector2(kx, -26), 2.0, col)

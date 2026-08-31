extends Area2D

@export var speed: float = 650.0
@export var gravity_scale: float = 180.0

var velocity: Vector2 = Vector2.ZERO
var shooter_id: int = 1
var is_stuck: bool = false
var is_reflected: bool = false
var lifetime: float = 0.0

@onready var collision_shape = $CollisionShape2D

func _ready():
	add_to_group("projectiles")

func init(shooter: int, pos: Vector2, dir: Vector2):
	shooter_id = shooter
	global_position = pos
	velocity = dir.normalized() * speed
	rotation = velocity.angle()

func _physics_process(delta: float):
	if is_stuck:
		return
		
	lifetime += delta
	velocity.y += gravity_scale * delta
	rotation = velocity.angle()
	
	global_position += velocity * delta
	
	# Wrap around arena edges
	var screen_w = 640.0
	if global_position.x < -10.0:
		global_position.x = screen_w + 10.0
	elif global_position.x > screen_w + 10.0:
		global_position.x = -10.0
		
	for body in get_overlapping_bodies():
		_handle_body_collision(body)

func _handle_body_collision(body: Node2D):
	if is_stuck:
		if body.is_in_group("players") and body.player_id == shooter_id:
			# Pickup stuck arrow
			body.pickup_arrow()
			queue_free()
		return
		
	if body.is_in_group("players"):
		if body.player_id == shooter_id and lifetime < 0.12:
			return # Avoid hitting self right out of the bow
			
		# Check if player is dodging / dashing
		if body.is_dashing:
			# Arrow Catch mechanic!
			body.catch_arrow()
			queue_free()
			return
			
		# Check if player is shielding (Knight Parry)
		if body.is_shielding:
			# Reflect arrow!
			is_reflected = true
			shooter_id = body.player_id
			velocity = -velocity * 1.2
			rotation = velocity.angle()
			lifetime = 0.0
			body.play_parry_effect()
			return
			
		# Lethal hit!
		body.take_hit(shooter_id, velocity.normalized())
		queue_free()
	elif body is StaticBody2D or body is TileMap:
		# Stick into wall
		stick_into_wall()

func stick_into_wall():
	is_stuck = true
	velocity = Vector2.ZERO
	# Add slight stick wobble juice
	var tween = create_tween()
	var orig_rot = rotation
	tween.tween_property(self, "rotation", orig_rot + 0.12, 0.04)
	tween.tween_property(self, "rotation", orig_rot - 0.08, 0.04)
	tween.tween_property(self, "rotation", orig_rot, 0.04)

func _on_body_entered(body: Node2D):
	_handle_body_collision(body)

func _draw():
	if is_stuck:
		# Shaft
		draw_line(Vector2(-10, 0), Vector2(6, 0), Color(0.8, 0.7, 0.5), 2.0)
		# Fletching
		draw_line(Vector2(-10, -3), Vector2(-6, 0), Color(0.9, 0.3, 0.3), 1.5)
		draw_line(Vector2(-10, 3), Vector2(-6, 0), Color(0.9, 0.3, 0.3), 1.5)
		# Arrowhead
		draw_colored_polygon([Vector2(6, -3), Vector2(11, 0), Vector2(6, 3)], Color(0.9, 0.9, 0.95))
	else:
		# Glowing trail
		draw_line(Vector2(-16, 0), Vector2(-8, 0), Color(1.0, 0.8, 0.2, 0.4), 3.0)
		# Shaft
		draw_line(Vector2(-10, 0), Vector2(7, 0), Color(1.0, 0.95, 0.8), 2.0)
		# Fletching
		draw_line(Vector2(-10, -4), Vector2(-5, 0), Color(0.95, 0.2, 0.2), 2.0)
		draw_line(Vector2(-10, 4), Vector2(-5, 0), Color(0.95, 0.2, 0.2), 2.0)
		# Glowing Arrowhead
		draw_colored_polygon([Vector2(7, -4), Vector2(13, 0), Vector2(7, 4)], Color(1.0, 1.0, 1.0))

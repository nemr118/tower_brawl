extends Area2D

@export var speed: float = 720.0
var velocity: Vector2 = Vector2.ZERO
var shooter_id: int = 1
var lifetime: float = 0.0

func _ready():
	add_to_group("projectiles")

func init(shooter: int, pos: Vector2, dir: Vector2):
	shooter_id = shooter
	global_position = pos
	velocity = dir.normalized() * speed
	rotation = velocity.angle()

func _physics_process(delta: float):
	lifetime += delta
	if lifetime > 1.2:
		queue_free()
		return
		
	global_position += velocity * delta
	
	var screen_w = 640.0
	if global_position.x < -10.0:
		global_position.x = screen_w + 10.0
	elif global_position.x > screen_w + 10.0:
		global_position.x = -10.0
		
	for body in get_overlapping_bodies():
		_handle_body_collision(body)

func _handle_body_collision(body: Node2D):
	if body.is_in_group("players"):
		if body.player_id == shooter_id and lifetime < 0.1:
			return
		if body.is_dashing:
			return
		if body.is_shielding:
			shooter_id = body.player_id
			velocity = -velocity * 1.2
			rotation = velocity.angle()
			lifetime = 0.0
			body.play_parry_effect()
			return
		body.take_hit(shooter_id, velocity.normalized())
		queue_free()
	elif body is StaticBody2D or body is TileMap:
		queue_free()

func _on_body_entered(body: Node2D):
	_handle_body_collision(body)

func _draw():
	draw_colored_polygon([Vector2(-6, -2), Vector2(7, 0), Vector2(-6, 2)], Color(0.85, 0.85, 0.9))
	draw_line(Vector2(-6, 0), Vector2(-10, 0), Color(0.3, 0.3, 0.35), 2.0)
	draw_circle(Vector2(-10, 0), 2.0, Color(0.85, 0.85, 0.9))

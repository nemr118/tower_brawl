extends Area2D

const PlayerScript = preload("res://scripts/player.gd")   # arena_w / arena_h for the seams

@export var speed: float = 480.0   # was 550 (v0.1.3 pacing)
@export var gravity_scale: float = 200.0

var velocity: Vector2 = Vector2.ZERO
var shooter_id: int = 1
var lifetime: float = 0.0

func _ready():
	add_to_group("projectiles")
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 6.0
	col.shape = shape
	add_child(col)
	# thorn.tscn carries no signal wiring (the other projectile scenes do), so the
	# thorn used to depend entirely on the per-frame overlap scan. Event-driven now.
	body_entered.connect(_on_body_entered)

func init(shooter: int, pos: Vector2, dir: Vector2):
	shooter_id = shooter
	global_position = pos
	velocity = dir.normalized() * speed
	rotation = velocity.angle()

func _physics_process(delta: float):
	lifetime += delta
	velocity.y += gravity_scale * delta
	rotation = velocity.angle()
	
	global_position += velocity * delta
	
	# The tower's seams (v0.1.3): the walls stop a projectile everywhere but the
	# passages and the holes, so this only fires there.
	var aw: float = PlayerScript.arena_w
	var ah: float = PlayerScript.arena_h
	if global_position.x < -10.0:
		global_position.x = aw + 10.0
	elif global_position.x > aw + 10.0:
		global_position.x = -10.0
	if global_position.y > ah + 10.0:
		global_position.y = -10.0
	elif global_position.y < -10.0 and velocity.y < 0.0:
		global_position.y = ah + 10.0

func _on_body_entered(body: Node2D):
	_handle_body_collision(body)

func _handle_body_collision(body: Node2D):
	if body.is_in_group("players"):
		if body.player_id == shooter_id and lifetime < 0.12:
			return
		if body.is_shielding:
			shooter_id = body.player_id
			velocity = -velocity * 1.2
			rotation = velocity.angle()
			lifetime = 0.0
			body.play_parry_effect()
			return
		body.take_hit(shooter_id, velocity.normalized(), "Thorns")
		queue_free()
	elif body is StaticBody2D or body is TileMap:
		queue_free()

func _draw():
	draw_colored_polygon(PackedVector2Array([
		Vector2(8, 0), Vector2(-4, -4), Vector2(-6, 0), Vector2(-4, 4)
	]), Color(0.1, 0.6, 0.2))
	draw_circle(Vector2(-4, 0), 3.0, Color(0.4, 0.25, 0.1))


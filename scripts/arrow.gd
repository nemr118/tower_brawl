extends Area2D

const PlayerScript = preload("res://scripts/player.gd")   # arena_w / arena_h for the seams

@export var speed: float = 560.0   # was 650 (v0.1.3 pacing)
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
	# Collisions arrive through body_entered (wired in arrow.tscn); the per-frame
	# get_overlapping_bodies() scan that used to run here handled every hit twice.

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
			
		# Lethal hit! (v0.0.18) The arrow keeps flying after the hit. Before, it
		# vanished with the fighter it hit, and the archer could never pick it
		# up again. Now it flies on and sticks into the next platform.
		body.take_hit(shooter_id, velocity.normalized(), "Arrow")
	elif body is StaticBody2D or body is TileMap:
		# Stick into wall
		stick_into_wall(body)

func stick_into_wall(wall: Node = null):
	is_stuck = true
	velocity = Vector2.ZERO
	# Add slight stick wobble juice
	var tween = create_tween()
	var orig_rot = rotation
	tween.tween_property(self, "rotation", orig_rot + 0.12, 0.04)
	tween.tween_property(self, "rotation", orig_rot - 0.08, 0.04)
	tween.tween_property(self, "rotation", orig_rot, 0.04)
	# v0.0.18: become a child of the platform we hit, so when the arena turns
	# the arrow turns with it. Before, stuck arrows stayed put in the air.
	# The move waits until the wobble is over: the physics engine is busy right
	# now, and the wobble must finish in the old frame before we switch parents.
	if wall != null and wall != get_parent():
		tween.tween_callback(_stick_to.bind(wall))

func _stick_to(wall: Node) -> void:
	if is_instance_valid(wall) and is_inside_tree() and wall != get_parent():
		reparent(wall, true)

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

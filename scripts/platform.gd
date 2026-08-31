extends StaticBody2D

@export var size: Vector2 = Vector2(100, 14)
@export var is_ground: bool = false

func _ready():
	queue_redraw()

func _draw():
	var half_w = size.x / 2.0
	var half_h = size.y / 2.0
	var rect = Rect2(-half_w, -half_h, size.x, size.y)
	
	if is_ground:
		# Solid Stone Ground
		draw_rect(rect, Color(0.2, 0.22, 0.28), true)
		# Top grass/stone highlight
		draw_line(Vector2(-half_w, -half_h), Vector2(half_w, -half_h), Color(0.4, 0.75, 0.4), 3.0)
		draw_rect(rect, Color(0.1, 0.1, 0.15), false, 1.5)
	else:
		# Floating Wood/Stone Ledge
		draw_rect(rect, Color(0.35, 0.25, 0.2), true)
		# Top platform edge
		draw_line(Vector2(-half_w, -half_h), Vector2(half_w, -half_h), Color(0.65, 0.5, 0.35), 2.5)
		# Bottom shadow
		draw_line(Vector2(-half_w, half_h), Vector2(half_w, half_h), Color(0.15, 0.1, 0.08), 2.0)
		draw_rect(rect, Color(0.12, 0.08, 0.06), false, 1.0)

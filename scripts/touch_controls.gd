extends CanvasLayer

## In-Game Virtual Touch Controller for Mobile & Tablet Players
## Emulates joystick input and button presses directly into Godot's Input system.

@onready var joystick_base = $JoystickBase
@onready var joystick_thumb = $JoystickBase/Thumb
@onready var btn_jump = $Buttons/BtnJump
@onready var btn_attack = $Buttons/BtnAttack
@onready var btn_special = $Buttons/BtnSpecial
@onready var btn_dash = $Buttons/BtnDash

var is_touching_joystick: bool = false
var joy_touch_index: int = -1
var base_center: Vector2 = Vector2.ZERO
var max_radius: float = 45.0



func _ready():
	Global.connect("net_connected", Callable(self, "_on_net_connected"))
	# Automatically detect if running on mobile or touch device
	var is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()
	visible = is_mobile
	_update_base_center()


var my_input_prefix: String = "p1_"

func _on_net_connected(id: int):
	my_input_prefix = "p" + str(id) + "_"

func _update_base_center():
	base_center = joystick_base.global_position + joystick_base.size / 2.0

func _input(event):
	if not visible:
		return
		
	if event is InputEventScreenTouch:
		if event.pressed:
			# Left half of screen -> Joystick
			if event.position.x < 300.0 and joy_touch_index == -1:
				joy_touch_index = event.index
				is_touching_joystick = true
				joystick_base.global_position = event.position - joystick_base.size / 2.0
				_update_base_center()
				_handle_joystick_move(event.position)
		else:
			if event.index == joy_touch_index:
				is_touching_joystick = false
				joy_touch_index = -1
				joystick_thumb.position = joystick_base.size / 2.0 - joystick_thumb.size / 2.0
				_simulate_move(Vector2.ZERO)
				
	elif event is InputEventScreenDrag:
		if event.index == joy_touch_index and is_touching_joystick:
			_handle_joystick_move(event.position)

func _handle_joystick_move(touch_pos: Vector2):
	var offset = touch_pos - base_center
	var dist = offset.length()
	var dir = offset.normalized()
	
	var clamped_dist = min(dist, max_radius)
	var thumb_pos = dir * clamped_dist
	
	joystick_thumb.position = (joystick_base.size / 2.0 - joystick_thumb.size / 2.0) + thumb_pos
	
	var norm_vec = (dir * (clamped_dist / max_radius))
	_simulate_move(norm_vec)

func _simulate_move(vec: Vector2):
	_simulate_axis(my_input_prefix + "left", my_input_prefix + "right", vec.x)
	_simulate_axis(my_input_prefix + "up", my_input_prefix + "down", vec.y)

func _simulate_axis(neg_action: String, pos_action: String, val: float):
	if val > 0.18:
		Input.action_press(pos_action, abs(val))
		Input.action_release(neg_action)
	elif val < -0.18:
		Input.action_press(neg_action, abs(val))
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)

# Button Signals
func _on_btn_jump_pressed():
	Input.action_press(my_input_prefix + "jump")
func _on_btn_jump_released():
	Input.action_release(my_input_prefix + "jump")

func _on_btn_attack_pressed():
	Input.action_press(my_input_prefix + "attack")
func _on_btn_attack_released():
	Input.action_release(my_input_prefix + "attack")

func _on_btn_special_pressed():
	Input.action_press(my_input_prefix + "special")
func _on_btn_special_released():
	Input.action_release(my_input_prefix + "special")

func _on_btn_dash_pressed():
	Input.action_press(my_input_prefix + "dash")
func _on_btn_dash_released():
	Input.action_release(my_input_prefix + "dash")

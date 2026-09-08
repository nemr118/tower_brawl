extends CanvasLayer

## The phone controller (v0.1.1 rewrite).
##
## The story so far. The old layout was four 55 px squares in a plus shape at
## the bottom right, and the hit test grew every square by 20 px and then asked
## them in a fixed order with jump first. The grown squares overlapped, so a
## touch on the lower right part of the attack button counted as jump: "I kept
## trying to attack and hitting jump." The stick turned the thumb offset into
## four action strengths and cut each axis below 0.18, so a small tilt near an
## axis snapped to the axis (an 8-way stick by accident), and any tilt at all
## walked the fighter, so there was no way to aim while standing still.
##
## Now:
##   - One floating stick under the left thumb. One vector per touch, radial.
##     Inside the aim ring (the inner AIM_RING of STICK_RADIUS) the fighter aims
##     and does not move. Outside it, it moves and aims the same way, with the
##     move strength ramping from the ring edge. The aim is the raw direction at
##     any tilt past NOISE_RADIUS, a full circle, and it stays where the thumb
##     left it (Global.touch_aim). Movement still goes through the
##     p<N>_left/right/up/down actions, so player.gd, the bubble's first-press
##     pop and the bots see nothing new.
##   - Four round buttons on an arc under the right thumb, which pivots from the
##     bottom right corner: attack, the biggest, where the thumb rests; jump next
##     along the arc toward the bottom; special above; dash at the far end. A
##     touch goes to the nearest button centre inside its circle plus HIT_PAD,
##     never to the first match. A held touch keeps its button until it is
##     HOLD_PAD further out and another button is nearer (no re-press from a
##     wobbling thumb, which is the dash-chain theory of the speed burst).
##   - The scene file is untouched (CLAUDE.md rule 1): the four Buttons are
##     moved, resized and rounded from here in _ready(); the two ColorRects of
##     the old stick are hidden and the stick is drawn by StickGfx below.
## The viewport is 640 x 360 (stretch canvas_items, aspect keep), so every
## number here is in those units on every phone.

const STICK_RADIUS := 60.0       # thumb travel, viewport px (was 45)
const AIM_RING := 0.40           # inside this share of the radius: aim only, no walking
const NOISE_RADIUS := 0.08       # below this share: the thumb is still, aim unchanged
const STICK_REST := Vector2(96.0, 264.0)   # where the idle stick is drawn
const HIT_PAD := 14.0            # a touch this far outside a circle still hits it
const HOLD_PAD := 12.0           # a held touch leaves its button only this much further out

# The arc: centre, radius, label. Angles are measured at the bottom right
# corner (640, 360): 0 = straight up, 90 = straight left.
const CORNER := Vector2(640.0, 360.0)
const BUTTONS := {
	"attack":  {"arc": 105.0, "deg": 40.0, "r": 30.0, "text": "ATK"},
	"jump":    {"arc": 105.0, "deg": 70.0, "r": 24.0, "text": "JUMP"},
	"special": {"arc": 165.0, "deg": 18.0, "r": 22.0, "text": "SPEC"},
	"dash":    {"arc": 165.0, "deg": 52.0, "r": 22.0, "text": "DASH"},
}

@onready var joystick_base = $JoystickBase
@onready var joystick_thumb = $JoystickBase/Thumb
@onready var btn_jump = $Buttons/BtnJump
@onready var btn_attack = $Buttons/BtnAttack
@onready var btn_special = $Buttons/BtnSpecial
@onready var btn_dash = $Buttons/BtnDash

var my_input_prefix: String = "p1_"

var _buttons: Dictionary = {}          # action -> {node, center, r}
var _held: Dictionary = {}             # touch index -> action (right thumb)
var _stick_gfx: Node2D = null

var is_touching_joystick: bool = false
var joy_touch_index: int = -1
var base_center: Vector2 = STICK_REST
var thumb_offset: Vector2 = Vector2.ZERO   # the thumb's offset from the base, clamped
var _move_vec: Vector2 = Vector2.ZERO       # what the actions carry
var _aiming_only: bool = false              # inside the ring


func _ready():
	Global.connect("net_connected", Callable(self, "_on_net_connected"))
	# Show on anything that can be touched. The feature tags alone missed a phone in
	# the playtest (no controls at all), so also trust Global's user-agent check and
	# the display server, and reveal on the first screen touch no matter what.
	visible = Global.is_mobile or OS.has_feature("mobile") or OS.has_feature("web_android") \
		or OS.has_feature("web_ios") or DisplayServer.is_touchscreen_available()
	if visible:
		Global.is_mobile = true
		Global.strip_mouse_binds()

	_buttons = {
		"attack": {"node": btn_attack}, "jump": {"node": btn_jump},
		"special": {"node": btn_special}, "dash": {"node": btn_dash},
	}
	for action in _buttons:
		var spec: Dictionary = BUTTONS[action]
		var a: float = deg_to_rad(float(spec["deg"]))
		var center: Vector2 = CORNER + Vector2(-sin(a), -cos(a)) * float(spec["arc"])
		_buttons[action]["center"] = center
		_buttons[action]["r"] = float(spec["r"])
		_style_button(_buttons[action]["node"], center, float(spec["r"]), str(spec["text"]))

	# The old square stick is hidden; StickGfx draws circles in its place.
	joystick_base.visible = false
	joystick_thumb.visible = false
	_stick_gfx = StickGfx.new()
	_stick_gfx.owner_layer = self
	add_child(_stick_gfx)


func _style_button(btn: Button, center: Vector2, r: float, label: String) -> void:
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE   # touches are read in _input, not by the Button
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = label
	btn.custom_minimum_size = Vector2(2.0 * r, 2.0 * r)
	btn.size = Vector2(2.0 * r, 2.0 * r)
	btn.global_position = center - Vector2(r, r)
	btn.add_theme_font_size_override("font_size", 11 if r < 26.0 else 13)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 0.95))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.14, 0.2, 0.55)
	normal.border_color = Color(1.0, 1.0, 1.0, 0.55)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(int(r))
	normal.anti_aliasing = true
	var pressed := normal.duplicate()
	pressed.bg_color = Color(1.0, 0.85, 0.3, 0.7)
	pressed.border_color = Color(1.0, 1.0, 1.0, 0.95)
	for style_name in ["normal", "hover", "focus", "disabled"]:
		btn.add_theme_stylebox_override(style_name, normal)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.toggle_mode = true          # button_pressed shows the pressed look while a thumb is on it
	btn.button_pressed = false


func _on_net_connected(id: int):
	my_input_prefix = "p" + str(id) + "_"


func _input(event):
	if not visible:
		if event is InputEventScreenTouch and event.pressed:
			visible = true
			Global.is_mobile = true
			Global.strip_mouse_binds()
		return

	if event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.pressed:
			if event.position.x < 320.0 and joy_touch_index == -1:
				# Left half: the stick appears under the thumb.
				joy_touch_index = event.index
				is_touching_joystick = true
				base_center = event.position
				_handle_joystick_move(event.position)
			else:
				var action := _button_at(event.position, "")
				_held[event.index] = action
				if action != "":
					_press(action)
		else:
			if event.index == joy_touch_index:
				is_touching_joystick = false
				joy_touch_index = -1
				thumb_offset = Vector2.ZERO
				_set_move(Vector2.ZERO)   # the aim stays (Global.touch_aim)
			elif _held.has(event.index):
				var action: String = _held[event.index]
				if action != "":
					_release(action)
				_held.erase(event.index)
		_redraw_stick()

	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		if event.index == joy_touch_index and is_touching_joystick:
			_handle_joystick_move(event.position)
			_redraw_stick()
		elif _held.has(event.index):
			var old_action: String = _held[event.index]
			var new_action := _button_at(event.position, old_action)
			if new_action != old_action:
				if old_action != "":
					_release(old_action)
				if new_action != "":
					_press(new_action)
				_held[event.index] = new_action


# The button under a touch: the nearest centre whose circle (plus HIT_PAD) holds
# the point. `holding` is the button this touch already has; it keeps it until
# the touch is HOLD_PAD further out than the circle, so a wobble on an edge does
# not re-press anything.
func _button_at(pos: Vector2, holding: String) -> String:
	var best := ""
	var best_d := INF
	for action in _buttons:
		var b: Dictionary = _buttons[action]
		var d: float = pos.distance_to(b["center"])
		var reach: float = float(b["r"]) + HIT_PAD
		if action == holding:
			reach += HOLD_PAD
		if d <= reach and d < best_d:
			best = action
			best_d = d
	if holding != "" and best != "" and best != holding:
		# Only leave the held button once the touch is really outside it.
		var hb: Dictionary = _buttons[holding]
		if pos.distance_to(hb["center"]) <= float(hb["r"]) + HIT_PAD + HOLD_PAD:
			return holding
	return best


func _press(action: String) -> void:
	Input.action_press(my_input_prefix + action)
	_buttons[action]["node"].button_pressed = true


func _release(action: String) -> void:
	Input.action_release(my_input_prefix + action)
	_buttons[action]["node"].button_pressed = false


func _handle_joystick_move(touch_pos: Vector2):
	var offset := touch_pos - base_center
	var dist := offset.length()
	var dir := offset / dist if dist > 0.0 else Vector2.ZERO
	var share := minf(dist, STICK_RADIUS) / STICK_RADIUS   # 0..1 of the radius
	thumb_offset = dir * share * STICK_RADIUS

	if share > NOISE_RADIUS:
		Global.touch_aim = dir   # a full circle, at any tilt
	if share <= AIM_RING:
		_aiming_only = true
		_set_move(Vector2.ZERO)
	else:
		_aiming_only = false
		var strength := (share - AIM_RING) / (1.0 - AIM_RING)   # 0 at the ring, 1 at the rim
		_set_move(dir * strength)


# The four movement actions carry the move vector. Both axes at once, no per-axis
# cut: a tiny component is released so the fighter does not creep (player.gd
# walks at full speed above 0.1 anyway).
func _set_move(vec: Vector2) -> void:
	_move_vec = vec
	_simulate_axis(my_input_prefix + "left", my_input_prefix + "right", vec.x)
	_simulate_axis(my_input_prefix + "up", my_input_prefix + "down", vec.y)


func _simulate_axis(neg_action: String, pos_action: String, val: float) -> void:
	if val > 0.05:
		Input.action_press(pos_action, val)
		Input.action_release(neg_action)
	elif val < -0.05:
		Input.action_press(neg_action, -val)
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)


func _redraw_stick() -> void:
	if _stick_gfx != null:
		_stick_gfx.queue_redraw()


# Draws the stick: the base circle, the aim ring, the thumb, and the aim line.
class StickGfx extends Node2D:
	var owner_layer = null

	func _draw() -> void:
		if owner_layer == null:
			return
		var live: bool = owner_layer.is_touching_joystick
		var c: Vector2 = owner_layer.base_center if live else owner_layer.STICK_REST
		var R: float = owner_layer.STICK_RADIUS
		var ring: float = R * owner_layer.AIM_RING
		var alpha := 0.9 if live else 0.45
		draw_circle(c, R, Color(0.12, 0.14, 0.2, 0.35 * alpha))
		draw_arc(c, R, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.55 * alpha), 2.0, true)
		# The aim ring: inside it the fighter aims without walking.
		draw_arc(c, ring, 0.0, TAU, 32, Color(1.0, 0.85, 0.3, 0.6 * alpha), 1.5, true)
		var thumb: Vector2 = c + (owner_layer.thumb_offset if live else Vector2.ZERO)
		if live and owner_layer.thumb_offset.length() > R * owner_layer.NOISE_RADIUS:
			var aim: Vector2 = Global.touch_aim
			draw_line(c, c + aim * R, Color(1.0, 0.85, 0.3, 0.8), 2.0, true)
		var thumb_col := Color(1.0, 0.85, 0.3, 0.9) if (live and owner_layer._aiming_only) else Color(1.0, 1.0, 1.0, 0.85 * alpha)
		draw_circle(thumb, 16.0, thumb_col)
		draw_arc(thumb, 16.0, 0.0, TAU, 24, Color(0.0, 0.0, 0.0, 0.5 * alpha), 1.5, true)


# The scene still connects the Buttons' button_down / button_up signals here.
# They never fire (mouse_filter IGNORE; touches are read in _input), but the
# methods stay so the scene loads without warnings.
func _on_btn_jump_pressed(): pass
func _on_btn_jump_released(): pass
func _on_btn_attack_pressed(): pass
func _on_btn_attack_released(): pass
func _on_btn_special_pressed(): pass
func _on_btn_special_released(): pass
func _on_btn_dash_pressed(): pass
func _on_btn_dash_released(): pass

extends CanvasLayer

## The phone controller: two layouts in one script (v0.1.4).
##
## "arc" (v0.1.1): one floating stick under the left thumb (inside the inner
## AIM_RING it aims and does not move; outside it walks and aims the same way;
## the aim is a full circle and stays where the thumb left it, Global.touch_aim),
## and four round buttons on an arc pivoting from the bottom right corner:
## attack (the biggest, where the thumb rests), jump next along the arc, special
## above, dash at the far end. A touch goes to the nearest centre inside its
## circle plus HIT_PAD; a held touch keeps its button until it is HOLD_PAD
## further out (no re-press from a wobbling thumb). The story behind it (the
## plus-shaped squares that overlapped, the 8-way stick by accident) is in
## docs/Patch Notes/v0.1.1 - Phone Controller.md.
##
## "twin" (v0.1.4): two floating sticks. Left, MOVE_RADIUS: the fighter walks in
## the stick's direction; within DOWN_DEG of straight down it ducks (held 1.5 s:
## the look down, player.gd); above JUMP_DEG from horizontal it jumps once (the
## stick must drop under JUMP_REARM_DEG to jump again); RIM_PAD past the rim
## fires a dash that way (in the down sector the rim is a jump press instead:
## down + jump = the drop-through), re-armed inside RIM_REARM of the radius.
## Right, AIM_RADIUS: any tilt sets Global.touch_aim (a full circle, it stays
## when the thumb lifts; held straight up 1.5 s = the look up, player.gd);
## RIM_PAD past the rim fires one shot that way, re-armed inside RIM_REARM. A
## special button in the bottom right. The left stick never touches the aim, so
## walking left while shooting right works.
##
## A small SWAP button under the top bar switches the layout; the choice is
## saved as LAYOUT_KEY through Global's storage (localStorage on the web).
##
## Movement goes through the p<N>_left/right/up/down actions, buttons and rims
## through p<N>_jump/dash/attack/special, so player.gd, the bubble's first-press
## pop and the bots see nothing new. A rim or wedge press is a tap: pressed now,
## released two physics frames later (player.gd reads is_action_just_pressed).
## The scene file is untouched: the four Buttons are moved, resized and rounded
## from here; the old stick's ColorRects are hidden and StickGfx draws instead.
## The viewport is 640 x 360 (stretch canvas_items, aspect keep), so every
## number here is in those units on every phone.

const STICK_RADIUS := 60.0       # arc: thumb travel, viewport px
const AIM_RING := 0.40           # arc: inside this share of the radius: aim only, no walking
const NOISE_RADIUS := 0.08       # below this share: the thumb is still, aim unchanged
const STICK_REST := Vector2(96.0, 264.0)   # arc: where the idle stick is drawn
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

# Twin sticks (v0.1.4).
const LAYOUT_KEY := "towerbrawl_layout"   # "arc" or "twin"
const MOVE_RADIUS := 80.0        # left stick
const AIM_RADIUS := 70.0         # right stick
const RIM_PAD := 10.0            # this far past a rim: a dash (left) or a shot (right)
const RIM_REARM := 0.85          # back inside this share of the radius re-arms the rim
const JUMP_DEG := 45.0           # the stick above this angle from horizontal: a jump
const JUMP_REARM_DEG := 35.0     # and under this to jump again
const DOWN_DEG := 30.0           # within this of straight down: duck (its rim: drop-through)
const TAP_FRAMES := 2            # a rim or wedge press is released this many physics frames later
const MOVE_REST := Vector2(110.0, 250.0)
const AIM_REST := Vector2(500.0, 235.0)
const SPECIAL_TWIN := {"center": Vector2(612.0, 322.0), "r": 22.0}
const SWAP_CENTER := Vector2(26.0, 66.0)   # under the top bar (it ends at y 44)
const SWAP_R := 14.0

@onready var joystick_base = $JoystickBase
@onready var joystick_thumb = $JoystickBase/Thumb
@onready var btn_jump = $Buttons/BtnJump
@onready var btn_attack = $Buttons/BtnAttack
@onready var btn_special = $Buttons/BtnSpecial
@onready var btn_dash = $Buttons/BtnDash

var my_input_prefix: String = "p1_"
var layout: String = "arc"

var _buttons: Dictionary = {}          # action -> {node, center, r, visible}
var _held: Dictionary = {}             # touch index -> action (a button under a thumb)
var _stick_gfx: Node2D = null
var _swap_btn: Button = null
var _swap_touch: int = -1
var _taps: Array = []                  # [{action, frame}] pressed now, released later

# Arc: the one stick.
var is_touching_joystick: bool = false
var joy_touch_index: int = -1
var base_center: Vector2 = STICK_REST
var thumb_offset: Vector2 = Vector2.ZERO   # the thumb's offset from the base, clamped
var _move_vec: Vector2 = Vector2.ZERO       # what the actions carry
var _aiming_only: bool = false              # inside the ring

# Twin: the two sticks.
var move_touch: int = -1
var move_center: Vector2 = MOVE_REST
var move_offset: Vector2 = Vector2.ZERO    # clamped, for drawing
var move_dir: Vector2 = Vector2.ZERO       # the unit direction, ZERO when still
var move_in_down: bool = false
var move_in_jump: bool = false
var _move_rim_armed: bool = true
var _jump_armed: bool = true
var aim_touch: int = -1
var aim_center: Vector2 = AIM_REST
var aim_offset: Vector2 = Vector2.ZERO
var _aim_rim_armed: bool = true


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
		_style_button(_buttons[action]["node"], Vector2.ZERO, float(BUTTONS[action]["r"]), str(BUTTONS[action]["text"]))

	# The old square stick is hidden; StickGfx draws circles in its place.
	joystick_base.visible = false
	joystick_thumb.visible = false
	_stick_gfx = StickGfx.new()
	_stick_gfx.owner_layer = self
	add_child(_stick_gfx)

	_swap_btn = Button.new()
	add_child(_swap_btn)
	_style_button(_swap_btn, SWAP_CENTER, SWAP_R, "SWAP")
	_swap_btn.add_theme_font_size_override("font_size", 9)

	var saved: String = Global._storage_get(LAYOUT_KEY)
	layout = "twin" if saved == "twin" else "arc"
	_apply_layout()
	print("🎮 [Layout] ", layout, " saved=", saved != "")


# Places the buttons for the current layout. The arc: all four on their arc.
# Twin: only the special, in the bottom right corner.
func _apply_layout() -> void:
	for action in _buttons:
		var b: Dictionary = _buttons[action]
		var spec: Dictionary = BUTTONS[action]
		var center: Vector2
		var r: float
		var shown := true
		if layout == "twin":
			shown = action == "special"
			center = SPECIAL_TWIN["center"]
			r = float(SPECIAL_TWIN["r"])
		else:
			var a: float = deg_to_rad(float(spec["deg"]))
			center = CORNER + Vector2(-sin(a), -cos(a)) * float(spec["arc"])
			r = float(spec["r"])
		b["center"] = center
		b["r"] = r
		b["visible"] = shown
		var node: Button = b["node"]
		node.visible = shown
		_place_button(node, center, r)
	_redraw_stick()


func _place_button(btn: Button, center: Vector2, r: float) -> void:
	btn.custom_minimum_size = Vector2(2.0 * r, 2.0 * r)
	btn.size = Vector2(2.0 * r, 2.0 * r)
	btn.global_position = center - Vector2(r, r)


func _style_button(btn: Button, center: Vector2, r: float, label: String) -> void:
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE   # touches are read in _input, not by the Button
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = label
	_place_button(btn, center, r)
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


# Swaps the layout: every held action is let go first (no stuck keys), then the
# buttons move and the choice is saved.
func set_layout(name: String) -> void:
	for idx in _held.keys():
		if _held[idx] != "":
			_release(_held[idx])
	_held.clear()
	_release_all_taps()
	_set_move(Vector2.ZERO)
	is_touching_joystick = false
	joy_touch_index = -1
	thumb_offset = Vector2.ZERO
	move_touch = -1
	move_offset = Vector2.ZERO
	move_dir = Vector2.ZERO
	move_in_down = false
	move_in_jump = false
	aim_touch = -1
	aim_offset = Vector2.ZERO
	layout = name
	_apply_layout()
	Global._storage_set(LAYOUT_KEY, name)
	print("🎮 [Layout] ", name, " saved")


func _input(event):
	if not visible:
		if event is InputEventScreenTouch and event.pressed:
			visible = true
			Global.is_mobile = true
			Global.strip_mouse_binds()
		return

	if event is InputEventScreenTouch:
		get_viewport().set_input_as_handled()
		if event.pressed and _swap_touch == -1 and event.position.distance_to(SWAP_CENTER) <= SWAP_R + HIT_PAD:
			_swap_touch = event.index
			_swap_btn.button_pressed = true
			return
		if not event.pressed and event.index == _swap_touch:
			_swap_touch = -1
			_swap_btn.button_pressed = false
			if event.position.distance_to(SWAP_CENTER) <= SWAP_R + HIT_PAD + HOLD_PAD:
				set_layout("arc" if layout == "twin" else "twin")
			return
	elif event is InputEventScreenDrag:
		get_viewport().set_input_as_handled()
		if event.index == _swap_touch:
			return
	else:
		return

	if layout == "twin":
		_input_twin(event)
	else:
		_input_arc(event)


# ---------------------------------------------------------------- the arc

func _input_arc(event) -> void:
	if event is InputEventScreenTouch:
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


# The button under a touch: the nearest visible centre whose circle (plus
# HIT_PAD) holds the point. `holding` is the button this touch already has; it
# keeps it until the touch is HOLD_PAD further out than the circle, so a wobble
# on an edge does not re-press anything.
func _button_at(pos: Vector2, holding: String) -> String:
	var best := ""
	var best_d := INF
	for action in _buttons:
		var b: Dictionary = _buttons[action]
		if not bool(b.get("visible", true)):
			continue
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


# ---------------------------------------------------------------- twin sticks

func _input_twin(event) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			var action := _button_at(event.position, "")   # only the special is visible
			if action != "":
				_held[event.index] = action
				_press(action)
			elif event.position.x < 320.0 and move_touch == -1:
				move_touch = event.index
				move_center = event.position
				_move_rim_armed = true
				_jump_armed = true
				_twin_move(event.position)
			elif event.position.x >= 320.0 and aim_touch == -1:
				aim_touch = event.index
				aim_center = event.position
				_aim_rim_armed = true
				_twin_aim(event.position)
		else:
			if event.index == move_touch:
				move_touch = -1
				move_offset = Vector2.ZERO
				move_dir = Vector2.ZERO
				move_in_down = false
				move_in_jump = false
				_set_move(Vector2.ZERO)
			elif event.index == aim_touch:
				aim_touch = -1
				aim_offset = Vector2.ZERO   # the aim stays (Global.touch_aim)
			elif _held.has(event.index):
				var action: String = _held[event.index]
				if action != "":
					_release(action)
				_held.erase(event.index)
		_redraw_stick()

	elif event is InputEventScreenDrag:
		if event.index == move_touch:
			_twin_move(event.position)
			_redraw_stick()
		elif event.index == aim_touch:
			_twin_aim(event.position)
			_redraw_stick()
		# A thumb on the special keeps it until it lifts.


# The left stick. The full unit direction goes out on the move actions: x walks
# (player.gd walks at full speed above 0.1), y is the duck (down above 0.5) and
# the dash direction. The down sector sends a clean (0, 1) so the duck holds.
func _twin_move(pos: Vector2) -> void:
	var offset := pos - move_center
	var dist := offset.length()
	var dir := offset / dist if dist > 0.0 else Vector2.ZERO
	var share := dist / MOVE_RADIUS
	move_offset = dir * minf(dist, MOVE_RADIUS)

	if share <= NOISE_RADIUS:
		move_dir = Vector2.ZERO
		move_in_down = false
		move_in_jump = false
		_jump_armed = true
		_move_rim_armed = true
		_set_move(Vector2.ZERO)
		return

	move_dir = dir
	var up_deg := rad_to_deg(atan2(-dir.y, absf(dir.x)))   # +90 straight up, -90 straight down
	move_in_down = up_deg <= -(90.0 - DOWN_DEG)
	_set_move(Vector2(0.0, 1.0) if move_in_down else dir)

	# The jump wedge, with hysteresis.
	if up_deg >= JUMP_DEG:
		move_in_jump = true
		if _jump_armed:
			_jump_armed = false
			_tap("jump")
	else:
		move_in_jump = false
		if up_deg < JUMP_REARM_DEG:
			_jump_armed = true

	# The rim: a dash that way; in the down sector a jump press (the drop-through).
	if dist >= MOVE_RADIUS + RIM_PAD:
		if _move_rim_armed:
			_move_rim_armed = false
			_tap("jump" if move_in_down else "dash")
	elif share <= RIM_REARM:
		_move_rim_armed = true


# The right stick: the aim, and one shot per trip past the rim.
func _twin_aim(pos: Vector2) -> void:
	var offset := pos - aim_center
	var dist := offset.length()
	var dir := offset / dist if dist > 0.0 else Vector2.ZERO
	var share := dist / AIM_RADIUS
	aim_offset = dir * minf(dist, AIM_RADIUS)

	if share > NOISE_RADIUS:
		Global.touch_aim = dir
	if dist >= AIM_RADIUS + RIM_PAD:
		if _aim_rim_armed:
			_aim_rim_armed = false
			_tap("attack")
	elif share <= RIM_REARM:
		_aim_rim_armed = true


# A tap: the action is pressed now and released TAP_FRAMES physics frames later,
# so player.gd's is_action_just_pressed sees it once whatever the node order.
func _tap(action: String) -> void:
	Input.action_press(my_input_prefix + action)
	_taps.append({"action": action, "frame": Engine.get_physics_frames()})
	var node: Button = _buttons[action]["node"]
	if node.visible:
		node.button_pressed = true


func _physics_process(_delta: float) -> void:
	if _taps.is_empty():
		return
	var now := Engine.get_physics_frames()
	var keep: Array = []
	for t in _taps:
		if now - int(t["frame"]) >= TAP_FRAMES:
			_release_tap(str(t["action"]))
		else:
			keep.append(t)
	_taps = keep


func _release_tap(action: String) -> void:
	# A tap never fights a held button: only release if no thumb holds it.
	if not _held.values().has(action):
		_release(action)


func _release_all_taps() -> void:
	for t in _taps:
		_release_tap(str(t["action"]))
	_taps.clear()


# ---------------------------------------------------------------- shared

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


# Draws the sticks. Arc: the base circle, the aim ring, the thumb, the aim line.
# Twin: the move circle with its jump wedge and duck sector marked, the aim
# circle with the aim line, both thumbs, a faint outer ring at the dash / shot rim.
class StickGfx extends Node2D:
	var owner_layer = null
	const GOLD := Color(1.0, 0.85, 0.3)

	func _draw() -> void:
		if owner_layer == null:
			return
		if owner_layer.layout == "twin":
			_draw_twin()
		else:
			_draw_arc()

	func _base(c: Vector2, R: float, alpha: float) -> void:
		draw_circle(c, R, Color(0.12, 0.14, 0.2, 0.35 * alpha))
		draw_arc(c, R, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.55 * alpha), 2.0, true)

	func _thumb(p: Vector2, col: Color, alpha: float) -> void:
		draw_circle(p, 16.0, col)
		draw_arc(p, 16.0, 0.0, TAU, 24, Color(0.0, 0.0, 0.0, 0.5 * alpha), 1.5, true)

	func _draw_arc() -> void:
		var live: bool = owner_layer.is_touching_joystick
		var c: Vector2 = owner_layer.base_center if live else owner_layer.STICK_REST
		var R: float = owner_layer.STICK_RADIUS
		var ring: float = R * owner_layer.AIM_RING
		var alpha := 0.9 if live else 0.45
		_base(c, R, alpha)
		# The aim ring: inside it the fighter aims without walking.
		draw_arc(c, ring, 0.0, TAU, 32, Color(GOLD, 0.6 * alpha), 1.5, true)
		var thumb: Vector2 = c + (owner_layer.thumb_offset if live else Vector2.ZERO)
		if live and owner_layer.thumb_offset.length() > R * owner_layer.NOISE_RADIUS:
			var aim: Vector2 = Global.touch_aim
			draw_line(c, c + aim * R, Color(GOLD, 0.8), 2.0, true)
		var thumb_col := Color(GOLD, 0.9) if (live and owner_layer._aiming_only) else Color(1.0, 1.0, 1.0, 0.85 * alpha)
		_thumb(thumb, thumb_col, alpha)

	func _draw_twin() -> void:
		var pad: float = owner_layer.RIM_PAD
		# Left: move.
		var mlive: bool = owner_layer.move_touch != -1
		var mc: Vector2 = owner_layer.move_center if mlive else owner_layer.MOVE_REST
		var MR: float = owner_layer.MOVE_RADIUS
		var ma := 0.9 if mlive else 0.45
		_base(mc, MR, ma)
		draw_arc(mc, MR + pad, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.2 * ma), 1.0, true)
		# The jump wedge (above JUMP_DEG) and the duck sector (within DOWN_DEG of down).
		var j: float = deg_to_rad(owner_layer.JUMP_DEG)
		var jcol := Color(GOLD, (0.9 if owner_layer.move_in_jump else 0.5) * ma)
		draw_arc(mc, MR - 4.0, -PI + j, -j, 24, jcol, 3.0, true)
		var d: float = deg_to_rad(owner_layer.DOWN_DEG)
		var dcol := Color(0.5, 0.8, 1.0, (0.9 if owner_layer.move_in_down else 0.5) * ma)
		draw_arc(mc, MR - 4.0, PI * 0.5 - d, PI * 0.5 + d, 12, dcol, 3.0, true)
		var mthumb: Vector2 = mc + (owner_layer.move_offset if mlive else Vector2.ZERO)
		var mcol := Color(1.0, 1.0, 1.0, 0.85 * ma)
		if owner_layer.move_in_jump:
			mcol = Color(GOLD, 0.9)
		elif owner_layer.move_in_down:
			mcol = Color(0.5, 0.8, 1.0, 0.9)
		_thumb(mthumb, mcol, ma)
		# Right: aim.
		var alive: bool = owner_layer.aim_touch != -1
		var ac: Vector2 = owner_layer.aim_center if alive else owner_layer.AIM_REST
		var AR: float = owner_layer.AIM_RADIUS
		var aa := 0.9 if alive else 0.45
		_base(ac, AR, aa)
		draw_arc(ac, AR + pad, 0.0, TAU, 48, Color(GOLD, 0.25 * aa), 1.0, true)
		var aim: Vector2 = Global.touch_aim
		if aim != Vector2.ZERO:
			draw_line(ac, ac + aim * AR, Color(GOLD, 0.8 * aa), 2.0, true)
		var athumb: Vector2 = ac + (owner_layer.aim_offset if alive else Vector2.ZERO)
		_thumb(athumb, Color(GOLD, 0.9) if alive else Color(1.0, 1.0, 1.0, 0.85 * aa), aa)


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

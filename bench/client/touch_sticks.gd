# The phone controls (P1), ported from the brawler's twin layout
# (scripts/touch_controls.gd, v0.1.4), in window pixels scaled by the window's
# height. Left half: the move stick appears under the thumb and runs the way it
# points; above JUMP_DEG from level it jumps once and keeps the jump held while
# the thumb stays up (re-armed under JUMP_REARM_DEG); within DOWN_DEG of straight
# down it holds down, and past the rim there it presses jump (down + jump: the
# drop through a ledge); past the rim anywhere else it dodges that way. Right
# half (p4.4, the user's pick): pull back to shoot. The thumb down draws the bow
# (the fighter stands still on the ground); pulling it away aims the other way
# (pull left, the arrow flies right); past the ring (ARM_RADIUS) the shot is
# armed: the ring turns gold and "LET GO: ARROW!" shows, and letting go then
# always fires. Let go inside the ring: no shot (B_CANCEL, sent until the next
# touch so a skipped tick cannot lose it). A DODGE button sits at the right
# edge. buttons() and aim_deg10() feed net.send_input.
# p4.15 (the user: "hard to get the character to do exactly what you wanted"): with
# the thumb up, two more ways to jump again, as a climb out of a pit needs: pump it
# (down PUMP_DOWN of the reach from its highest, then up PUMP_UP) or swing it over
# the top to the other side. Before, only dipping under JUMP_DEG jumped again.
extends CanvasLayer

const P = preload("res://sim/proto.gd")
const MOVE_RADIUS := 240.0
const AIM_RADIUS := 210.0       # how far the thumb's knob follows
const ARM_RADIUS := 110.0       # p4.4: pull past this ring and the shot is armed
const RED := Color(1.0, 0.35, 0.3)
const RIM_PAD := 30.0
const RIM_REARM := 0.85
const NOISE := 0.08
const JUMP_DEG := 45.0
const JUMP_REARM_DEG := 35.0
const DOWN_DEG := 30.0
const TAP_TICKS := 2
const PUMP_DOWN := 0.22           # p4.15: the thumb comes down this share of the reach from its highest: jump lets go,
const PUMP_UP := 0.15             # then up this share from its lowest: jump again
const SWING := 0.3                # p4.15: the thumb leans a side when its direction's x is past this
const SWING_GAP := 2              # a swing's jump: these ticks with jump up first, so the server sees a new press
const DODGE_R := 78.0
const HIT_PAD := 16.0
const GOLD := Color(1.0, 0.85, 0.3)
const BLUE := Color(0.5, 0.8, 1.0)

var active := false
var k := 1.0                      # window px per design px (the window's height / 1080)
var win := Vector2(1920, 1080)
var move_touch := -1
var move_center := Vector2.ZERO
var move_offset := Vector2.ZERO
var move_dir := Vector2.ZERO
var in_down := false
var in_jump := false
var _jump_armed := true
var _rim_armed := true
var aim_touch := -1
var aim_center := Vector2.ZERO
var aim_offset := Vector2.ZERO
var aim_dir := Vector2.RIGHT
var aim_set := false
var aim_armed := false            # p4.4: the thumb is past the ring: letting go fires
var aim_cancel := false           # p4.4: the last let-go was inside the ring: B_CANCEL until the next touch
var arrows_left := 3              # the game client's count, for the ring (NO ARROWS)
var shots_armed := 0              # p4.7 (the phone report): let go past the ring
var shots_cancelled := 0          # and inside it
var dodge_touch := -1
var jump_tap := 0
var dodge_tap := 0
var pump := true                  # p4.15's pump and swing (false: p4.14's stick; ?stick=old, tools/pit_probe.gd)
var _up_hi := 0.0                 # the thumb's highest (a share of the reach) since this jump went off
var _up_lo := 0.0                 # its lowest since a pump let go
var _pumped := false              # a pump let go: the next jump needs a rise of PUMP_UP
var _side := 0                    # the side the thumb leans to while this jump is held (-1, 0, 1)
var _gap := 0
var jumps := 0                    # p4.15 (the phone report): jumps the stick made,
var rim_dodges := 0               # dodges from the stick's rim,
var button_dodges := 0            # and from the DODGE button
var gfx := _Gfx.new()

class _Gfx extends Node2D:
	var owner_layer
	func _draw() -> void:
		if owner_layer != null:
			owner_layer._paint(self)

func _init() -> void:
	layer = 15
	gfx.owner_layer = self
	add_child(gfx)

func fit(w: Vector2) -> void:
	win = w
	k = w.y / 1080.0
	gfx.queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not active:
			active = true   # a touch on anything: this is a phone after all
		if not visible:
			return
		get_viewport().set_input_as_handled()
		_touch(event)
	elif event is InputEventScreenDrag:
		if not visible:
			return
		get_viewport().set_input_as_handled()
		_drag(event)

func _dodge_center() -> Vector2:
	return Vector2(win.x - 118.0 * k, win.y * 0.42)

func _touch(e: InputEventScreenTouch) -> void:
	var p: Vector2 = e.position
	if e.pressed:
		if dodge_touch == -1 and p.distance_to(_dodge_center()) <= (DODGE_R + HIT_PAD) * k:
			dodge_touch = e.index
			button_dodges += 1
		elif p.x < win.x * 0.5 and move_touch == -1:
			move_touch = e.index
			move_center = p
			_jump_armed = true
			_rim_armed = true
			_move(p)
		elif p.x >= win.x * 0.5 and aim_touch == -1:
			aim_touch = e.index
			aim_center = p
			aim_armed = false
			aim_cancel = false
			_aim(p)
	else:
		if e.index == move_touch:
			move_touch = -1
			move_offset = Vector2.ZERO
			move_dir = Vector2.ZERO
			in_down = false
			in_jump = false
			_pumped = false
			_gap = 0
		elif e.index == aim_touch:
			aim_touch = -1          # let go: the next tick sends no shoot bit: past the ring it fires,
			aim_cancel = not aim_armed   # inside it B_CANCEL lowers the bow
			if aim_armed:
				shots_armed += 1
			else:
				shots_cancelled += 1
			aim_armed = false
			aim_offset = Vector2.ZERO
		elif e.index == dodge_touch:
			dodge_touch = -1
	gfx.queue_redraw()

func _drag(e: InputEventScreenDrag) -> void:
	if e.index == move_touch:
		_move(e.position)
	elif e.index == aim_touch:
		_aim(e.position)
	gfx.queue_redraw()

func _move(p: Vector2) -> void:
	var off := p - move_center
	var dist := off.length()
	var dir := off / dist if dist > 0.0 else Vector2.ZERO
	var share := dist / (MOVE_RADIUS * k)
	move_offset = dir * minf(dist, MOVE_RADIUS * k)
	if share <= NOISE:
		move_dir = Vector2.ZERO
		in_down = false
		in_jump = false
		_jump_armed = true
		_rim_armed = true
		_pumped = false
		return
	move_dir = dir
	var up_deg := rad_to_deg(atan2(-dir.y, absf(dir.x)))   # +90 straight up, -90 straight down
	var up := -off.y / (MOVE_RADIUS * k)                    # how high the thumb is, a share of the reach
	var side := int(signf(dir.x)) if absf(dir.x) >= SWING else 0
	in_down = up_deg <= -(90.0 - DOWN_DEG)
	if up_deg >= JUMP_DEG:
		if _jump_armed:
			_jump_now(up, side)
		elif not pump:
			in_jump = true
		elif _pumped:
			_up_lo = minf(_up_lo, up)
			if up - _up_lo >= PUMP_UP:
				_jump_now(up, side)        # pumped back up: jump again
		else:
			in_jump = true
			_up_hi = maxf(_up_hi, up)
			if _side == 0:
				_side = side
			if _up_hi - up >= PUMP_DOWN:
				in_jump = false            # pumped down: jump lets go
				_pumped = true
				_up_lo = up
			elif side != 0 and _side != 0 and side != _side:
				_jump_now(up, side)        # swung over the top: jump again
				_gap = SWING_GAP
	else:
		in_jump = false
		_pumped = false
		if up_deg < JUMP_REARM_DEG:
			_jump_armed = true
	if dist >= (MOVE_RADIUS + RIM_PAD) * k:
		if _rim_armed:
			_rim_armed = false
			if in_down:
				jump_tap = TAP_TICKS      # down + jump: the drop through a ledge
			else:
				dodge_tap = TAP_TICKS
				rim_dodges += 1
	elif share <= RIM_REARM:
		_rim_armed = true

func _jump_now(up: float, side: int) -> void:
	in_jump = true
	_jump_armed = false
	_pumped = false
	jump_tap = TAP_TICKS
	_up_hi = up
	_side = side
	jumps += 1

func _aim(p: Vector2) -> void:
	var off := p - aim_center
	var dist := off.length()
	aim_offset = off.limit_length(AIM_RADIUS * k)
	if dist > AIM_RADIUS * k * NOISE:
		aim_dir = -off / dist   # pull back: the arrow flies the other way
		aim_set = true
	aim_armed = dist >= ARM_RADIUS * k

# The buttons this physics tick (proto B_*). A tap lasts TAP_TICKS ticks.
func buttons() -> int:
	var b := 0
	if move_dir != Vector2.ZERO:
		if in_down:
			b |= P.B_DOWN
		else:
			if move_dir.x > 0.38:
				b |= P.B_RIGHT
			elif move_dir.x < -0.38:
				b |= P.B_LEFT
			if move_dir.y < -0.38:
				b |= P.B_UP
			elif move_dir.y > 0.38:
				b |= P.B_DOWN
	if _gap > 0:
		_gap -= 1                       # p4.15: a swing's jump: jump up first, then the new press
	else:
		if in_jump or jump_tap > 0:
			b |= P.B_JUMP
		if jump_tap > 0:
			jump_tap -= 1
	if aim_touch != -1:
		b |= P.B_SHOOT
	elif aim_cancel:
		b |= P.B_CANCEL
	if dodge_touch != -1 or dodge_tap > 0:
		b |= P.B_DODGE
	if dodge_tap > 0:
		dodge_tap -= 1
	return b

func aim_deg10() -> int:
	return posmod(roundi(rad_to_deg(aim_dir.angle()) * 10.0), 3600)

func _base(n: Node2D, c: Vector2, r: float, alpha: float) -> void:
	n.draw_circle(c, r, Color(0.12, 0.14, 0.2, 0.35 * alpha))
	n.draw_arc(c, r, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.55 * alpha), 2.0 * k, true)

func _thumb(n: Node2D, p: Vector2, col: Color, alpha: float) -> void:
	n.draw_circle(p, 48.0 * k, col)
	n.draw_arc(p, 48.0 * k, 0.0, TAU, 32, Color(0.0, 0.0, 0.0, 0.5 * alpha), 1.5 * k, true)

func _paint(n: Node2D) -> void:
	var font := ThemeDB.fallback_font
	# left: move
	var mlive := move_touch != -1
	var mc := move_center if mlive else Vector2(330.0 * k, win.y - 330.0 * k)
	var mr := MOVE_RADIUS * k
	var ma := 0.9 if mlive else 0.45
	_base(n, mc, mr, ma)
	n.draw_arc(mc, mr + RIM_PAD * k, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.2 * ma), 1.0 * k, true)
	var j := deg_to_rad(JUMP_DEG)
	n.draw_arc(mc, mr - 4.0 * k, -PI + j, -j, 24, Color(GOLD, (0.9 if in_jump else 0.5) * ma), 3.0 * k, true)
	var d := deg_to_rad(DOWN_DEG)
	n.draw_arc(mc, mr - 4.0 * k, PI * 0.5 - d, PI * 0.5 + d, 12, Color(BLUE, (0.9 if in_down else 0.5) * ma), 3.0 * k, true)
	var mcol := Color(1.0, 1.0, 1.0, 0.85 * ma)
	if in_jump:
		mcol = Color(GOLD, 0.9)
	elif in_down:
		mcol = Color(BLUE, 0.9)
	_thumb(n, mc + (move_offset if mlive else Vector2.ZERO), mcol, ma)
	n.draw_string(font, mc + Vector2(-mr, -mr - 14.0 * k), "MOVE · up jumps · down + rim drops · rim dodges", HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), Color(1, 1, 1, 0.35))
	# right: pull back to shoot (p4.4). The ring is the arming line; armed, it turns
	# gold (or red with an empty quiver) and says what letting go will do.
	var alive := aim_touch != -1
	var ac := aim_center if alive else Vector2(win.x - 420.0 * k, win.y - 375.0 * k)
	var ring := ARM_RADIUS * k
	var aa := 0.9 if alive else 0.45
	var armed := alive and aim_armed
	var col := (RED if arrows_left <= 0 else GOLD) if armed else Color(1, 1, 1)
	n.draw_circle(ac, ring, Color(col, 0.22) if armed else Color(0.12, 0.14, 0.2, 0.35 * aa))
	n.draw_arc(ac, ring, 0.0, TAU, 64, Color(col, 0.95 if armed else 0.55 * aa), (5.0 if armed else 2.0) * k, true)
	if alive and aim_set:
		var tip := ac + aim_dir * (ring + 40.0 * k)
		n.draw_line(ac, tip, Color(col, 0.9 if armed else 0.4), (4.0 if armed else 2.0) * k, true)
		if armed:
			var side := aim_dir.orthogonal() * 14.0 * k
			n.draw_colored_polygon(PackedVector2Array([tip + aim_dir * 22.0 * k, tip + side, tip - side]), Color(col, 0.95))
	_thumb(n, ac + (aim_offset if alive else Vector2.ZERO), Color(col, 0.9) if alive else Color(1.0, 1.0, 1.0, 0.85 * aa), aa)
	var say := "AIM · thumb down, pull back past the ring, let go"
	var say_col := Color(1, 1, 1, 0.35)
	var say_size := 20
	if alive:
		if not armed:
			say = "PULL PAST THE RING"
			say_col = Color(1, 1, 1, 0.8)
			say_size = 26
		elif arrows_left <= 0:
			say = "NO ARROWS"
			say_col = Color(RED, 1.0)
			say_size = 30
		else:
			say = "LET GO: ARROW!"
			say_col = Color(GOLD, 1.0)
			say_size = 30
	n.draw_string_outline(font, ac + Vector2(-ring * 2.0, -ring - 18.0 * k), say, HORIZONTAL_ALIGNMENT_CENTER, ring * 4.0, int(say_size * k), int(5 * k), Color(0, 0, 0, 0.8 if alive else 0.0))
	n.draw_string(font, ac + Vector2(-ring * 2.0, -ring - 18.0 * k), say, HORIZONTAL_ALIGNMENT_CENTER, ring * 4.0, int(say_size * k), say_col)
	# the dodge button
	var dc := _dodge_center()
	var held := dodge_touch != -1
	n.draw_circle(dc, DODGE_R * k, Color(1.0, 0.85, 0.3, 0.7) if held else Color(0.12, 0.14, 0.2, 0.55))
	n.draw_arc(dc, DODGE_R * k, 0.0, TAU, 48, Color(1, 1, 1, 0.95 if held else 0.55), 2.0 * k, true)
	n.draw_string(font, dc + Vector2(-DODGE_R * k, 9.0 * k), "DODGE", HORIZONTAL_ALIGNMENT_CENTER, DODGE_R * 2.0 * k, int(26 * k), Color(1, 1, 1, 0.95))

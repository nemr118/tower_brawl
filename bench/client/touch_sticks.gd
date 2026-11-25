# The phone controls (P1), ported from the brawler's twin layout
# (scripts/touch_controls.gd, v0.1.4), in window pixels scaled by the window's
# height. Left half: the move stick appears under the thumb and runs the way it
# points; above JUMP_DEG from level it jumps once and keeps the jump held while
# the thumb stays up (re-armed under JUMP_REARM_DEG); within DOWN_DEG of straight
# down it holds down, and past the rim there it presses jump (down + jump: the
# drop through a ledge); past the rim anywhere else it dodges that way. Right
# half (p4.4, the user's pick): pull back to shoot. The thumb down and pulling (p4.16:
# DRAW_MIN, so a resting thumb or a tap does nothing) draws the bow (the fighter stands
# still on the ground); pulling it away aims the other way
# (pull left, the arrow flies right); past the ring (ARM_RADIUS) the shot is
# armed: the ring turns gold and "LET GO: ARROW!" shows, and letting go then
# always fires. Let go inside the ring: no shot (B_CANCEL, sent until the next
# touch so a skipped tick cannot lose it). A DODGE button sits at the right
# edge. buttons() and aim_deg10() feed net.send_input.
# p4.16 BUTTONS (the lobby's CONTROLS; the user's pick after the gathering's logs): the
# stick only runs (its middle follows the thumb past the rim; no jump, no rim dodge),
# a JUMP button in the bottom-right corner (held: a higher jump; with the stick down: a
# drop through a ledge; its touch area runs to the screen's edges) and a DODGE button
# up and to the left of it (the stick's way; its cooldown shows on it); the rest of the
# right half pulls to shoot, as in CLASSIC.
# p4.15 (the user: "hard to get the character to do exactly what you wanted"): with
# the thumb up, two more ways to jump again, as a climb out of a pit needs: pump it
# (down PUMP_DOWN of the reach from its highest, then up PUMP_UP) or swing it over
# the top to the other side. Before, only dipping under JUMP_DEG jumped again.
# 2026-11-24 (the November review's bug 7): a thumb already on the glass when the sticks
# appear (kids rest their thumbs through 3-2-1) was ignored until it was lifted: its
# press came while the sticks were hidden, and a move of a touch nobody knew did
# nothing. Now the first move of a touch whose press was never seen counts as its
# press, there. And a touch the phone takes away (cancelled: a call, a notification
# pulled down, a palm) lowers the bow: before, it fired an armed shot.
extends CanvasLayer

signal taunt_pressed              # p4.19: the small taunt button (GOBBLE! in the Harvest season)
signal menu_pressed               # p4.20: the small MENU button at the bottom in the middle

const P = preload("res://sim/proto.gd")
const Season = preload("res://client/season.gd")
const TAUNT_R := 62.0             # p4.19: the taunt button, at the left edge above the move stick
const Art = preload("res://client/lobby_art.gd")     # p4.19 (polish "sticks2"): the lobby's letters on the buttons
const Polish = preload("res://client/polish.gd")
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
const SETTLE_MS := 60             # p4.16 (the let-go wobble): a let-go takes the aim the thumb held this long before,
const SETTLE_SHARE := 0.25        # unless it moved more than this share of the ring since (a meant flick)
const DRAW_MIN := 34.0            # p4.16: the bow comes up once the aim thumb has moved this far (about 2 mm on a phone)
const JUMP_R := 125.0             # p4.16 BUTTONS: the JUMP button (about 15 mm across on a phone), bottom right
const BDODGE_R := 95.0            # the DODGE button up and to the left of it
const BTN_PAD := 36.0             # their touch areas reach this much further than drawn (JUMP's to the screen's edges too)
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
var aim_drawn := false            # p4.16: the thumb has pulled DRAW_MIN: the bow is up (a resting thumb or a tap: not)
var aim_taps := 0                 # p4.16 (the phone report): right-side touches let go before they pulled
var buttons_mode := false         # p4.16: the BUTTONS layout (game_client.gd: the lobby's CONTROLS, kept on the device)
var jump_touch := -1              # BUTTONS: the touch on JUMP
var dodge_wait := 0.0             # BUTTONS: the dodge's cooldown still to go, 0..1 (game_client.gd, from your predicted fighter)
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
var _aim_hist: Array = []         # p4.16: [msec, offset] of the aim thumb's last moves (the let-go wobble)
var jumps := 0                    # p4.15 (the phone report): jumps the stick made,
var rim_dodges := 0               # dodges from the stick's rim,
var button_dodges := 0            # and from the DODGE button
var seen := {}                    # the touches whose press came while the sticks showed (index -> true)
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
	visibility_changed.connect(_on_visibility)

# p4.16: hidden (the lobby, the winner's screen), a lift is never seen: let go of every
# touch so nothing stays held (a JUMP held into the next round).
func _on_visibility() -> void:
	if visible:
		return
	taunt_touch = -1
	move_touch = -1
	aim_touch = -1
	dodge_touch = -1
	jump_touch = -1
	seen.clear()
	move_offset = Vector2.ZERO
	move_dir = Vector2.ZERO
	in_down = false
	in_jump = false
	aim_armed = false
	aim_drawn = false
	aim_offset = Vector2.ZERO

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
		if event.pressed:
			if event.index == taunt_touch:
				taunt_touch = -1            # a new touch with that number: the taunt finger is long gone
			if event.position.distance_to(_menu_center()) <= (MENU_R + HIT_PAD) * k:   # p4.20: the MENU button
				taunt_touch = event.index   # (this finger is no stick's either, to its lift)
				menu_pressed.emit()
				return
			if event.position.distance_to(_taunt_center()) <= (TAUNT_R + HIT_PAD) * k:   # p4.19: a tap on the taunt button
				_taunt_ms = Time.get_ticks_msec()
				taunt_touch = event.index
				taunt_pressed.emit()
				gfx.queue_redraw()
				return
		elif event.index == taunt_touch:    # the taunt finger lifts: it never was a stick's
			taunt_touch = -1
			return
		_touch(event)
	elif event is InputEventScreenDrag:
		if not visible:
			return
		get_viewport().set_input_as_handled()
		if event.index == taunt_touch:      # the taunt finger slid a little: not a stick (an unknown moving finger is taken as one)
			return
		_drag(event)

var _taunt_ms := -9999            # when the taunt button was last tapped (it flashes)
var taunt_touch := -1             # the finger on the taunt button

const MENU_R := 40.0

func _menu_center() -> Vector2:
	return Vector2(win.x * 0.5, win.y - 56.0 * k)

func _taunt_center() -> Vector2:
	return Vector2(118.0 * k, win.y - 690.0 * k)

func _dodge_center() -> Vector2:
	if buttons_mode:
		return Vector2(win.x - 400.0 * k, win.y - 360.0 * k)
	return Vector2(win.x - 118.0 * k, win.y * 0.42)

func _dodge_r() -> float:
	return BDODGE_R if buttons_mode else DODGE_R

func _jump_center() -> Vector2:
	return Vector2(win.x - 200.0 * k, win.y - 200.0 * k)

# BUTTONS: a touch on JUMP: its circle and a pad, or the corner beyond it.
func _on_jump(p: Vector2) -> bool:
	var c := _jump_center()
	return buttons_mode and (p.distance_to(c) <= (JUMP_R + BTN_PAD) * k or (p.x >= c.x and p.y >= c.y))

func _on_dodge(p: Vector2) -> bool:
	var pad := BTN_PAD if buttons_mode else HIT_PAD
	return p.distance_to(_dodge_center()) <= (_dodge_r() + pad) * k

# A touch comes down at p (or, bug 7, a touch that was down before the sticks showed
# moves for the first time): JUMP, DODGE, the move stick or the aim, whichever is there
# and free.
func _press(index: int, p: Vector2) -> void:
	seen[index] = true
	if jump_touch == -1 and _on_jump(p):
		jump_touch = index        # p4.16 BUTTONS: JUMP, held for a higher jump; a quick tap still jumps
		jump_tap = TAP_TICKS
		jumps += 1
	elif dodge_touch == -1 and _on_dodge(p):
		dodge_touch = index
		dodge_tap = TAP_TICKS     # p4.16: a quick tap (down and up between two ticks) still dodges
		button_dodges += 1
	elif p.x < win.x * 0.5 and move_touch == -1:
		move_touch = index
		move_center = p
		_jump_armed = true
		_rim_armed = true
		_move(p)
	elif p.x >= win.x * 0.5 and aim_touch == -1:
		aim_touch = index
		aim_center = p
		aim_armed = false
		aim_cancel = false
		aim_drawn = false
		_aim_hist.clear()
		_aim(p)

func _touch(e: InputEventScreenTouch) -> void:
	var p: Vector2 = e.position
	if e.pressed:
		_press(e.index, p)
	else:
		seen.erase(e.index)
		if e.index == move_touch:
			move_touch = -1
			move_offset = Vector2.ZERO
			move_dir = Vector2.ZERO
			in_down = false
			in_jump = false
			_pumped = false
			_gap = 0
		elif e.index == aim_touch:
			_settle_aim()
			if e.canceled:
				aim_armed = false   # bug 7: the phone took the touch away: that is no let-go, the bow comes down
			aim_touch = -1          # let go: the next tick sends no shoot bit: past the ring it fires,
			aim_cancel = aim_drawn and not aim_armed   # inside it B_CANCEL lowers the bow
			if not aim_drawn:
				aim_taps += 1       # p4.16: the bow never came up: nothing to fire or lower
			elif aim_armed:
				shots_armed += 1
			else:
				shots_cancelled += 1
			aim_drawn = false
			aim_armed = false
			aim_offset = Vector2.ZERO
		elif e.index == dodge_touch:
			dodge_touch = -1
		elif e.index == jump_touch:
			jump_touch = -1
	gfx.queue_redraw()

func _drag(e: InputEventScreenDrag) -> void:
	if e.index == move_touch:
		_move(e.position)
	elif e.index == aim_touch:
		_aim(e.position)
	elif not seen.has(e.index):
		_press(e.index, e.position)   # bug 7: it was on the glass before the sticks showed: this move is its press
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
	if buttons_mode:
		# p4.16 BUTTONS: the stick only runs (and points a dodge); past the rim its middle
		# follows the thumb, so turning round is always a short move
		in_jump = false
		if dist > MOVE_RADIUS * k:
			move_center = p - dir * MOVE_RADIUS * k
			move_offset = dir * MOVE_RADIUS * k
		return
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
	var now := Time.get_ticks_msec()
	_aim_hist.append([now, off])
	while _aim_hist.size() > 2 and now - int(_aim_hist[0][0]) > 300:
		_aim_hist.pop_front()
	aim_offset = off.limit_length(AIM_RADIUS * k)
	if dist > AIM_RADIUS * k * NOISE:
		aim_dir = -off / dist   # pull back: the arrow flies the other way
		aim_set = true
	aim_armed = dist >= ARM_RADIUS * k
	if dist >= DRAW_MIN * k:
		aim_drawn = true

# p4.16 (the let-go wobble): as a thumb lifts off the glass its touch point slides a
# little, and the shot took that last point. A let-go takes the aim the thumb held
# SETTLE_MS before, unless the thumb moved more than SETTLE_SHARE of the ring since
# (a flick meant as the aim). The ring's arming counts from there too.
func _settle_aim() -> void:
	if _aim_hist.size() < 2:
		return
	var now := Time.get_ticks_msec()
	var last: Vector2 = _aim_hist[-1][1]
	for i in range(_aim_hist.size() - 1, -1, -1):
		if now - int(_aim_hist[i][0]) >= SETTLE_MS:
			var off: Vector2 = _aim_hist[i][1]
			if (last - off).length() <= SETTLE_SHARE * ARM_RADIUS * k and off.length() > AIM_RADIUS * k * NOISE:
				aim_dir = -off.normalized()
				aim_armed = aim_armed or off.length() >= ARM_RADIUS * k
			return

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
		if in_jump or jump_tap > 0 or jump_touch != -1:
			b |= P.B_JUMP
		if jump_tap > 0:
			jump_tap -= 1
	if aim_touch != -1 and aim_drawn:   # p4.16: only once the thumb pulls (a thumb at rest roots nobody)
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
	if Polish.on("sticks2"):
		_paint2(n)
		return
	var font := ThemeDB.fallback_font
	# left: move
	var mlive := move_touch != -1
	var mc := move_center if mlive else Vector2(330.0 * k, win.y - 330.0 * k)
	var mr := MOVE_RADIUS * k
	var ma := 0.9 if mlive else 0.45
	_base(n, mc, mr, ma)
	if not buttons_mode:   # the rim that dodges, and the arc that jumps (CLASSIC only)
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
	n.draw_string(font, mc + Vector2(-mr, -mr - 14.0 * k), "MOVE · down + JUMP drops" if buttons_mode else "MOVE · up jumps · down + rim drops · rim dodges",
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(20 * k), Color(1, 1, 1, 0.35))
	# right: pull back to shoot (p4.4). The ring is the arming line; armed, it turns
	# gold (or red with an empty quiver) and says what letting go will do.
	var alive := aim_touch != -1
	var rest := Vector2(win.x - 640.0 * k, win.y - 470.0 * k) if buttons_mode else Vector2(win.x - 420.0 * k, win.y - 375.0 * k)
	var ac := aim_center if alive else rest
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
	# the dodge button (BUTTONS: up and to the left of JUMP, its cooldown a dark sweep)
	var dc := _dodge_center()
	var dr := _dodge_r() * k
	var held := dodge_touch != -1
	n.draw_circle(dc, dr, Color(1.0, 0.85, 0.3, 0.7) if held else Color(0.12, 0.14, 0.2, 0.55))
	if buttons_mode and dodge_wait > 0.0:
		var pts := PackedVector2Array([dc])
		for i in 33:
			pts.append(dc + Vector2.from_angle(-PI * 0.5 + TAU * dodge_wait * i / 32.0) * dr)
		n.draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.55))
	n.draw_arc(dc, dr, 0.0, TAU, 48, Color(1, 1, 1, 0.95 if held else 0.55), 2.0 * k, true)
	var dcol := Color(1, 1, 1, 0.5 if buttons_mode and dodge_wait > 0.0 else 0.95)
	n.draw_string(font, dc + Vector2(-dr, 9.0 * k), "DODGE", HORIZONTAL_ALIGNMENT_CENTER, dr * 2.0, int(26 * k), dcol)
	if buttons_mode:   # JUMP, bottom right
		var jc := _jump_center()
		var jr := JUMP_R * k
		var jheld := jump_touch != -1
		n.draw_circle(jc, jr, Color(GOLD, 0.75) if jheld else Color(0.12, 0.14, 0.2, 0.55))
		n.draw_arc(jc, jr, 0.0, TAU, 64, Color(1, 1, 1, 0.95 if jheld else 0.6), 3.0 * k, true)
		var tip := jc + Vector2(0.0, -jr * 0.42)   # an up arrow over the word
		n.draw_colored_polygon(PackedVector2Array([tip + Vector2(0.0, -14.0 * k), tip + Vector2(16.0 * k, 4.0 * k), tip + Vector2(-16.0 * k, 4.0 * k)]),
			Color(1, 1, 1, 0.85))
		n.draw_string(font, jc + Vector2(-jr, 12.0 * k), "JUMP", HORIZONTAL_ALIGNMENT_CENTER, jr * 2.0, int(34 * k), Color(1, 1, 1, 0.95))


# ---- p4.19 (polish "sticks2"; the user: "It should look app store quality"): the same sticks and
# buttons, drawn with depth: a pad with a double rim, a knob with a shadow and a shine, DODGE and
# JUMP as coloured buttons with a lip that goes down when held, the lobby's letters. The long
# hints go once the player has jumped and shot a few times (HOW TO PLAY teaches them now).

func _base2(n: Node2D, c: Vector2, r: float, alpha: float) -> void:
	n.draw_circle(c, r, Color(0.05, 0.05, 0.1, 0.3 * alpha))
	n.draw_arc(c, r, 0.0, TAU, 64, Color(0, 0, 0, 0.35 * alpha), 6.0 * k, true)      # a dark edge under the rim
	n.draw_arc(c, r, 0.0, TAU, 64, Color(1, 1, 1, 0.6 * alpha), 3.0 * k, true)
	n.draw_arc(c, r * 0.5, 0.0, TAU, 40, Color(1, 1, 1, 0.1 * alpha), 2.0 * k, true)

func _knob2(n: Node2D, p: Vector2, col: Color, alpha: float) -> void:
	var r := 50.0 * k
	n.draw_circle(p + Vector2(0, 6.0 * k), r, Color(0, 0, 0, 0.3 * alpha))            # its shadow
	n.draw_circle(p, r, Color(col.darkened(0.3), col.a))
	n.draw_circle(p - Vector2(0, 3.0 * k), r * 0.87, col)
	n.draw_circle(p - Vector2(r * 0.28, r * 0.38), r * 0.2, Color(1, 1, 1, 0.4 * col.a))   # a shine
	n.draw_arc(p, r, 0.0, TAU, 32, Color(0, 0, 0, 0.5 * alpha), 2.0 * k, true)

# A round button: a dark lip, a coloured face that sits on it when held, a white rim, a word.
func _button2(n: Node2D, c: Vector2, r: float, face: Color, word: String, held: bool, fsize: float, word_a: float) -> Vector2:
	var lip := 8.0 * k
	var fc := c + Vector2(0, lip if held else 0.0)
	# see-through at rest (a fighter can stand under a button), solid under a thumb
	n.draw_circle(c + Vector2(0, lip), r, Color(face.darkened(0.65), 0.9 if held else 0.55))
	n.draw_circle(fc, r, Color(face.lightened(0.2) if held else face, 0.9 if held else 0.6))
	n.draw_arc(fc, r * 0.82, PI * 1.15, PI * 1.85, 16, Color(1, 1, 1, 0.3), 4.0 * k, true)   # a shine along the top
	n.draw_arc(fc, r, 0.0, TAU, 48, Color(1, 1, 1, 0.92), 3.0 * k, true)
	var fs := maxi(8, int(fsize * k))
	var at := fc + Vector2(-r, fs * 0.36)
	n.draw_string_outline(Art.DISPLAY, at, word, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, maxi(2, int(6 * k)), Color(0.08, 0.04, 0.02, 0.85 * word_a))
	n.draw_string(Art.DISPLAY, at, word, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color(1, 1, 1, word_a))
	return fc

func _hint2(n: Node2D, at: Vector2, w: float, words: String, size: float, col: Color, edge_a: float) -> void:
	var fs := maxi(8, int(size * k))
	if edge_a > 0.0:
		n.draw_string_outline(Art.BODY, at, words, HORIZONTAL_ALIGNMENT_CENTER, w, fs, maxi(2, int(5 * k)), Color(0, 0, 0, edge_a))
	n.draw_string(Art.BODY, at, words, HORIZONTAL_ALIGNMENT_CENTER, w, fs, col)

func _paint2(n: Node2D) -> void:
	# left: move
	var mlive := move_touch != -1
	var mc := move_center if mlive else Vector2(330.0 * k, win.y - 330.0 * k)
	var mr := MOVE_RADIUS * k
	var ma := 0.9 if mlive else 0.5
	_base2(n, mc, mr, ma)
	if not buttons_mode:   # the rim that dodges, and the arc that jumps (CLASSIC only)
		n.draw_arc(mc, mr + RIM_PAD * k, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.2 * ma), 1.5 * k, true)
		var j := deg_to_rad(JUMP_DEG)
		n.draw_arc(mc, mr - 6.0 * k, -PI + j, -j, 24, Color(GOLD, (0.95 if in_jump else 0.55) * ma), 5.0 * k, true)
	var d := deg_to_rad(DOWN_DEG)
	n.draw_arc(mc, mr - 6.0 * k, PI * 0.5 - d, PI * 0.5 + d, 12, Color(BLUE, (0.95 if in_down else 0.55) * ma), 5.0 * k, true)
	var mcol := Color(0.92, 0.94, 1.0, 0.85 * ma)
	if in_jump:
		mcol = Color(GOLD, 0.95)
	elif in_down:
		mcol = Color(BLUE, 0.95)
	_knob2(n, mc + (move_offset if mlive else Vector2.ZERO), mcol, ma)
	var learned := jumps + button_dodges + rim_dodges >= 6 and shots_armed >= 4   # they know the sticks: the long hints go
	if not learned and not mlive:
		_hint2(n, mc + Vector2(-mr * 1.3, -mr - 16.0 * k), mr * 2.6, "MOVE · down + JUMP drops" if buttons_mode else "MOVE · up jumps · the rim dodges",
			22.0, Color(1, 1, 1, 0.5), 0.35)
	# right: pull back to shoot. The ring is the arming line; armed, it turns gold (red with an
	# empty quiver) and says what letting go will do.
	var alive := aim_touch != -1
	var rest := Vector2(win.x - 640.0 * k, win.y - 470.0 * k) if buttons_mode else Vector2(win.x - 420.0 * k, win.y - 375.0 * k)
	var ac := aim_center if alive else rest
	var ring := ARM_RADIUS * k
	var aa := 0.9 if alive else 0.5
	var armed := alive and aim_armed
	var col := (RED if arrows_left <= 0 else GOLD) if armed else Color(1, 1, 1)
	n.draw_circle(ac, ring, Color(col, 0.22) if armed else Color(0.05, 0.05, 0.1, 0.3 * aa))
	n.draw_arc(ac, ring, 0.0, TAU, 64, Color(0, 0, 0, 0.35 * aa), (9.0 if armed else 6.0) * k, true)
	n.draw_arc(ac, ring, 0.0, TAU, 64, Color(col, 0.95 if armed else 0.6 * aa), (6.0 if armed else 3.0) * k, true)
	if alive and aim_set:
		var tip := ac + aim_dir * (ring + 40.0 * k)
		n.draw_line(ac, tip, Color(0, 0, 0, 0.35), (8.0 if armed else 5.0) * k, true)
		n.draw_line(ac, tip, Color(col, 0.95 if armed else 0.45), (5.0 if armed else 2.5) * k, true)
		if armed:
			var side := aim_dir.orthogonal() * 16.0 * k
			n.draw_colored_polygon(PackedVector2Array([tip + aim_dir * 26.0 * k, tip + side, tip - side]), Color(col, 0.98))
	_knob2(n, ac + (aim_offset if alive else Vector2.ZERO), Color(col, 0.92) if alive else Color(0.92, 0.94, 1.0, 0.85 * aa), aa)
	var say_at := ac + Vector2(-ring * 2.2, -ring - 20.0 * k)
	if alive:
		if not armed:
			_hint2(n, say_at, ring * 4.4, "PULL PAST THE RING", 28.0, Color(1, 1, 1, 0.9), 0.8)
		elif arrows_left <= 0:
			_hint2(n, say_at, ring * 4.4, "NO ARROWS", 34.0, Color(RED, 1.0), 0.85)
		else:
			_hint2(n, say_at, ring * 4.4, "LET GO: ARROW!", 34.0, Color(GOLD, 1.0), 0.85)
	elif not learned:
		_hint2(n, say_at, ring * 4.4, "AIM · pull back past the ring, let go", 22.0, Color(1, 1, 1, 0.5), 0.35)
	# the dodge button (BUTTONS: up and to the left of JUMP, its cooldown a dark sweep)
	var dc := _dodge_center()
	var dr := _dodge_r() * k
	var cooling := buttons_mode and dodge_wait > 0.0
	var dfc := _button2(n, dc, dr, Color(1.0, 0.5, 0.18), "DODGE", dodge_touch != -1, 30.0, 0.5 if cooling else 1.0)
	if cooling:
		var pts := PackedVector2Array([dfc])
		for i in 33:
			pts.append(dfc + Vector2.from_angle(-PI * 0.5 + TAU * dodge_wait * i / 32.0) * dr)
		n.draw_colored_polygon(pts, Color(0.0, 0.0, 0.0, 0.5))
	# p4.20 MENU: a small quiet button at the bottom in the middle (three lines)
	var mn := _menu_center()
	n.draw_circle(mn, MENU_R * k, Color(0.05, 0.05, 0.1, 0.45))
	n.draw_arc(mn, MENU_R * k, 0.0, TAU, 32, Color(1, 1, 1, 0.55), 2.5 * k, true)
	for j in 3:
		n.draw_line(mn + Vector2(-16.0 * k, (j - 1) * 11.0 * k), mn + Vector2(16.0 * k, (j - 1) * 11.0 * k), Color(1, 1, 1, 0.85), 4.0 * k, true)
	# p4.19 the taunt: a small yellow button at the left edge (the word by the season)
	var word: String = {"harvest": "GOBBLE", "halloween": "BOO"}.get(Season.now, "HA HA")
	_button2(n, _taunt_center(), TAUNT_R * k, Color(0.95, 0.75, 0.15), word, Time.get_ticks_msec() - _taunt_ms < 180, 22.0, 1.0)
	if buttons_mode:   # JUMP, bottom right
		var jc := _jump_center()
		var jr := JUMP_R * k
		var jfc := _button2(n, jc + Vector2(0, 0), jr, Color(0.3, 0.72, 0.32), "JUMP", jump_touch != -1, 42.0, 1.0)
		var tip2 := jfc + Vector2(0.0, -jr * 0.5)   # an up arrow over the word
		n.draw_colored_polygon(PackedVector2Array([tip2 + Vector2(0.0, -16.0 * k), tip2 + Vector2(18.0 * k, 5.0 * k), tip2 + Vector2(-18.0 * k, 5.0 * k)]),
			Color(1, 1, 1, 0.92))

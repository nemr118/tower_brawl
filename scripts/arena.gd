# ==============================================================================
# WELCOME TO ARENA.GD! (The Game World Script)
# ==============================================================================
# This script is like the "Game Master" or Referee.
# It doesn't control a single player. Instead, it builds the arena, decides 
# where everyone spawns, keeps score, and drops power-ups from the sky.
# ==============================================================================

extends Node2D

@onready var platforms_node = $Platforms
@onready var cam: Camera2D = $Cam                 # v0.1.3: follows my fighter up and down the tower
@onready var markers_layer: CanvasLayer = $Markers
const ArenaLayouts = preload("res://scripts/arena_layouts.gd")
const PlayerScript = preload("res://scripts/player.gd")
const LAYOUT_NAME := "tower"
var layout: Dictionary = {}
var _marker_canvas: Node2D = null
# v0.1.3: the arena shift is off (user decision, the tower replaces it). The
# powerup timer is not started; the relay, the flip count, the tape's rot and
# the replay's turn all stay in place and read zero. Backlog 9 and 24 closed.
const ARENA_SHIFT_ENABLED := false
const VIEW_H := 360.0                             # the screen is 640 x 360; the camera shows one screen of the tower
const MARKER_R := 11.0                            # the off-screen marker bubble
var powerup_node: Area2D = null
var is_arena_rotating: bool = false
var spin_tween: Tween = null   # the running arena spin, so a round start can finish it at once
var platform_layers: Dictionary = {}   # v0.0.32: each platform's collision_layer while the stage turns (backlog 9)
# v0.0.38: the platforms stay solid during the shift again (user decision: the
# free-fall tumble of v0.0.32 felt terrible). false = the v0.0.31 ride, a fighter
# stands on its platform through the turn and may pass about 30 px above the top
# edge for a second (backlog 9, reopened). true = the v0.0.32 free fall. Kept as
# a switch so a future arena configuration can pick either per layout.
const SHIFT_SOFT_PLATFORMS: bool = false
# v0.0.39: the two ground slabs do not turn with the stage any more (user
# decision). At load they are moved out of `Platforms` into a sibling node,
# `Ground`, at the same place, so their local positions stay (±140, 155) and the
# spin tween never touches them. The floor is always the floor: the flipped
# ground at the top edge (backlog 22) is gone, and a fighter dropped by the
# shift lands on the floor instead of tumbling out of the bottom. The turning
# ledges do sweep through the slabs' corners mid-turn (backlog 24, accepted
# for now). Everything else under `Platforms` turns as a group, as before.
const ANCHORED_PLATFORMS: Array[String] = ["GroundLeft", "GroundRight"]
var ground_node: Node2D = null

const PlayerScene = preload("res://scenes/player.tscn")
const BotBrainScript = preload("res://scripts/bot_brain.gd")
const HistoryRingScript = preload("res://scripts/history_ring.gd")

# The tape (Phase 3c, v0.0.25): the last six seconds of the fight as this screen
# drew it, one frame per physics tick. See history_ring.gd. Made in code, so no
# scene edit. _physics_process here is sim recording, not network polling: the
# stamps and the freeze come from the server's signals.
var tape = null
var _tape_weapon_ids := {}   # projectile instance id -> weapon id, so a name lookup happens once per arrow
# The replay (v0.0.26): plays the frozen tape back when the server's round_end says
# "replay": true (the round ended on a kill). See replay_player.gd. Made in code.
const ReplayPlayerScript = preload("res://scripts/replay_player.gd")
const FontWarmupScript = preload("res://scripts/font_warmup.gd")
# v0.1.2 (backlog 27's other half): a fighter whose own death report got no echo
# comes back on its own after this. The server dropped a real second death as a
# repeat once (fixed on the server, DEATH_DEDUPE_S 0.6); should it ever happen
# again, or a report get lost, the fighter is not stuck dead for the round.
const SELF_RESPAWN_S := 1.0
var replay = null
var _replay_due: bool = false    # round_end said replay: true and no replay has started or been skipped yet
var _round_end_msec: int = 0     # when round_end arrived, for the late_ms number
# v0.0.35 (optimisation Step C, build 2): the tape card (history_status, ~380 B)
# used to go out on every kill stamp from every screen; Step B measured it as a
# third of a player's outbound bytes. A stamp now only marks the card dirty and
# _record_tape_frame sends it at most once per TAPE_CARD_MIN_S while recording.
# The freeze and the replay start / skip / end still send at once: that is the
# state the deck, the server's [TAPE] log and the harness read.
const TAPE_CARD_MIN_S := 10.0
var _tape_card_dirty: bool = false
var _tape_card_sent_msec: int = -100000
const REPLAY_WAIT_S := 1.5       # the tape must freeze this soon after round_end, or the replay is skipped

# HUD textures resolved once at load. _update_panel used to call load() for every
# icon on every HUD refresh (each a resource-cache lookup); these are plain constants.
const HEART_TEX = preload("res://assets/icons/heart.jpg")
const CROWN_TEX = preload("res://assets/icons/crown.jpg")
const PICKUP_TEX = preload("res://assets/icons/pickup.jpg")
const CLASS_ICON_TEX = {
	Global.ClassType.RANGER: preload("res://assets/icons/ranger.jpg"),
	Global.ClassType.KNIGHT: preload("res://assets/icons/knight.jpg"),
	Global.ClassType.MAGE: preload("res://assets/icons/pyro.jpg"),
	Global.ClassType.ROGUE: preload("res://assets/icons/rogue.jpg"),
	Global.ClassType.DRUID: preload("res://assets/icons/druid.jpg"),
}

# Bubble spawn spots (v0.0.18). The story: the four fixed spots did not move
# when the arena flipped, so a fighter could pop up inside the floor or out of
# view. Now every fighter comes back in the upper middle of the air, at a random
# x in the middle half of the arena, inside a bubble (see player.gd). The random
# number is seeded from things every screen already knows (round, player, lives,
# flips), so every screen picks the same spot without a new network packet.
const SPAWN_MIN_X = 300.0   # v0.1.3: inside the ceiling hole (x 256..384)
const SPAWN_MAX_X = 340.0
const SPAWN_Y = -10.0       # v0.1.3: the bubble drops in through the ceiling hole

func _spawn_spot(p_id: int) -> Vector2:
	var lives = int(player_stocks.get(p_id, Global.max_stocks))
	var rng = RandomNumberGenerator.new()
	rng.seed = current_round * 100000 + p_id * 10000 + lives * 100 + Global.arena_flips
	return Vector2(rng.randf_range(SPAWN_MIN_X, SPAWN_MAX_X), SPAWN_Y)

# Round-start spots (v0.0.19). The story: the air bubble is right for coming
# back after a death, but at the start of a round everyone should stand on a
# platform, spread out. We keep no list of spots. We look at the platforms as
# they are right now, flips and all, find every top edge that is on the screen,
# and pick spots that are far apart. Every screen has the same platforms, so
# every screen picks the same spots without a new network packet.
const FEET_OFFSET = 8.0     # the fighter's feet sit 8 px below its middle point
const SPOT_MIN_Y = 30.0     # a top edge above this line is out of view
const SPOT_MAX_Y = 340.0    # a top edge below this line is too close to the bottom

func _build_layout() -> void:
	# v0.1.3 (the tower): the pieces come from scripts/arena_layouts.gd, not the
	# scene. One StaticBody2D per piece under $Platforms (the node keeps its name:
	# the tape, the replay and the bot brain read it). Walls and bumps are solid
	# on the World layer; ledges are one-way and live on the ledge layer, so a
	# fighter can drop through one (player.gd LEDGE_LAYER).
	layout = ArenaLayouts.get_layout(LAYOUT_NAME)
	PlayerScript.arena_w = float(layout["width"])
	PlayerScript.arena_h = float(layout["height"])
	cam.limit_left = 0
	cam.limit_right = int(layout["width"])
	cam.limit_top = 0
	cam.limit_bottom = int(layout["height"])
	for piece in layout["pieces"]:
		var kind: String = str(piece["kind"])
		var w := float(piece["w"])
		var h := float(piece["h"])
		var body := StaticBody2D.new()
		body.name = str(piece["name"])
		body.position = Vector2(float(piece["x"]) + w / 2.0, float(piece["y"]) + h / 2.0)
		var shape := CollisionShape2D.new()
		shape.shape = RectangleShape2D.new()
		shape.shape.size = Vector2(w, h)
		shape.name = "CollisionShape2D"
		if kind == "ledge":
			body.collision_layer = 1 << (PlayerScript.LEDGE_LAYER - 1)
			shape.one_way_collision = true
			shape.one_way_collision_margin = 6.0
		else:
			body.collision_layer = 1
		body.collision_mask = 0
		body.add_child(shape)
		body.add_child(_piece_visual(kind, w, h))
		platforms_node.add_child(body)


func _piece_visual(kind: String, w: float, h: float) -> Control:
	var base := ColorRect.new()
	base.name = "VisualBase"
	base.offset_left = -w / 2.0
	base.offset_top = -h / 2.0
	base.offset_right = w / 2.0
	base.offset_bottom = h / 2.0
	# The trim is a child of the base, so its offsets count from the base's
	# top-left corner: a strip along the top edge.
	var trim := ColorRect.new()
	trim.name = "Trim"
	trim.offset_left = 0.0
	trim.offset_top = 0.0
	trim.offset_right = w
	if kind == "ledge":
		base.color = Color(0.35, 0.25, 0.2)
		trim.color = Color(0.65, 0.5, 0.35)
		trim.offset_bottom = 2.0
	elif kind == "bump":
		base.color = Color(0.24, 0.24, 0.3)
		trim.color = Color(0.45, 0.45, 0.55)
		trim.offset_bottom = 3.0
	else:
		base.color = Color(0.16, 0.16, 0.21)
		trim.color = Color(0.22, 0.22, 0.28)
		trim.offset_bottom = 2.0
	base.add_child(trim)
	return base


func _platform_tops() -> Array:
	# v0.1.3: the round-start spots are the layout's spawn ledges (the middle of
	# each top edge, the feet offset taken off). The same list on every screen.
	return ArenaLayouts.spawn_spots(layout, FEET_OFFSET)

func _ground_spawn_spots(count: int) -> Array:
	# Pick "count" spots that are far apart. Start with the leftmost top edge.
	# Then, again and again, take the spot whose nearest picked spot is the
	# farthest away. Ties go to the leftmost, so every screen agrees.
	var tops := _platform_tops()
	tops.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and a.y < b.y))
	var picked: Array = []
	if tops.is_empty():
		return picked
	picked.append(tops[0])
	while picked.size() < count and picked.size() < tops.size():
		var best := Vector2.ZERO
		var best_d := -1.0
		for t in tops:
			if t in picked:
				continue
			var d := INF
			for pk in picked:
				d = min(d, t.distance_to(pk))
			if d > best_d:
				best_d = d
				best = t
		picked.append(best)
	return picked

var player_stocks = {}
var player_instances = {}
var is_round_over: bool = false
var current_round: int = 1
var pause_overlay: ColorRect

# Global signal -> handler. Connected in _ready, disconnected in _exit_tree.
const NET_SIGNAL_HANDLERS = {
	"net_player_died": "_on_net_player_died",
	"net_round_end": "_on_round_end_sync",
	"net_new_round": "_on_new_round_sync",
	"net_return_to_lobby": "_on_return_to_lobby",
	"net_spawn_powerup": "_on_net_spawn_powerup",
	"net_activate_powerup": "_on_net_activate_powerup",
	"net_version_error": "_on_net_version_error",
	"net_player_joined": "_on_net_player_joined",
	"net_harness_status": "_on_harness_status",
	"net_join_locked": "_on_join_locked",
}

const HarnessTickerScript = preload("res://scripts/harness_ticker.gd")

@onready var hud = $HUD
@onready var banner_label = $HUD/CenterBanner/BannerLabel
@onready var p1_panel = $HUD/TopBar/P1Panel
@onready var p2_panel = $HUD/TopBar/P2Panel
@onready var p3_panel = $HUD/TopBar/P3Panel
@onready var p4_panel = $HUD/TopBar/P4Panel
@onready var touch_controls = $TouchControls


# ------------------------------------------------------------------------------
# SETUP TIME!
# _ready() is a special Godot function that runs exactly ONCE when the 
# level first loads. It's like setting up a board game before you start playing.
# ------------------------------------------------------------------------------
func _ready():
	_build_layout()
	var leave_btn = Button.new()
	leave_btn.text = "LEAVE MATCH"
	leave_btn.add_theme_font_size_override("font_size", 16)
	leave_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	leave_btn.position = Vector2(get_viewport_rect().size.x - 120, 10)
	leave_btn.connect("pressed", Callable(self, "_on_leave_match_pressed"))
	leave_btn.z_index = 100
	$HUD.add_child(leave_btn)
	if Global.my_player_id == 0:
		leave_btn.visible = false

	for sig_name in NET_SIGNAL_HANDLERS:
		Global.connect(sig_name, Callable(self, NET_SIGNAL_HANDLERS[sig_name]))

	if Global.my_player_id == 1 and ARENA_SHIFT_ENABLED:
		var pt = Timer.new()
		pt.wait_time = 15.0
		pt.autostart = true
		pt.connect("timeout", Callable(self, "_host_spawn_powerup"))
		add_child(pt)
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0, 0, 0, 0.8)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.z_index = 100
	pause_overlay.visible = false
	$HUD.add_child(pause_overlay)   # v0.1.3: on the HUD layer, so it does not scroll with the camera
	
	var spectate_btn = Button.new()
	spectate_btn.text = "SPECTATE (LEAVE MATCH)"
	spectate_btn.add_theme_font_size_override("font_size", 48)
	spectate_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	spectate_btn.connect("pressed", Callable(self, "_on_spectate_pressed"))
	pause_overlay.add_child(spectate_btn)
	
	var join_btn = Button.new()
	join_btn.name = "JoinBtn"
	join_btn.text = "JOIN NEXT MATCH"
	join_btn.add_theme_font_size_override("font_size", 24)
	join_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	join_btn.connect("pressed", Callable(self, "_on_arena_join_pressed"))
	join_btn.z_index = 100
	$HUD.add_child(join_btn)   # v0.1.3: on the HUD layer
	
	if Global.my_player_id > 0 or bool(Global.harness_info.get("active", false)):
		join_btn.visible = false

	# v0.0.23: one-line test ticker under the top bar, on the right, out of the fight.
	var ticker = HarnessTickerScript.new(true)
	ticker.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ticker.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ticker.offset_left = -10
	ticker.offset_right = -10
	ticker.offset_top = 48
	ticker.offset_bottom = 48
	$HUD.add_child(ticker)
	
	# Platforms the right way up for a client arriving mid-match (spectator
	# reconnect, late joiner): the server counts the flips for us.
	platforms_node.rotation = Global.arena_flips * PI
	# The tape records after the fighters have moved this tick (priority 10 runs
	# after the default 0 of every fighter).
	tape = HistoryRingScript.new()
	process_physics_priority = 10
	replay = ReplayPlayerScript.new()
	replay.name = "Replay"
	add_child(replay)
	replay.finished.connect(_on_replay_finished)
	# v0.1.2 (cut 1): draw the glyphs of the banner (20/4), the HUD and name tags
	# (10/3) and the replay overlay (18/3, 16/3, 12/3) once now, off-screen, so the
	# first "knocked out" banner and the first replay do not rasterize them mid-fight.
	if Global.warm_enabled:
		add_child(FontWarmupScript.new([[20, 4], [18, 3], [16, 3], [12, 3]]))
	Global.focus_canvas()   # v0.0.28: the browser keys go to the canvas only while it has the focus
	_marker_canvas = MarkerCanvas.new()
	_marker_canvas.arena = self
	markers_layer.add_child(_marker_canvas)
	cam.position = Vector2(float(layout["width"]) / 2.0, VIEW_H / 2.0)
	cam.reset_smoothing()
	_start_new_match()


# ------------------------------------------------------------------------------
# THE CAMERA AND THE MARKERS (v0.1.3, docs/reference/arena-tower.md sections 3 and 5)
# The camera follows my fighter up and down (never sideways: the tower is one
# screen wide), plus the look offset player.gd keeps. A spectator sees the
# middle of the living fighters. During a replay it follows the closing kill.
# A fighter above or below the view gets a small marker at the top or bottom
# edge, at its real x.
# ------------------------------------------------------------------------------
class MarkerCanvas extends Node2D:
	var arena = null
	func _draw() -> void:
		if arena != null:
			arena._draw_markers(self)


func _process(_delta: float) -> void:
	var target := _camera_target()
	if target != Vector2.INF:
		cam.global_position = target
	if _marker_canvas != null:
		_marker_canvas.queue_redraw()


func _camera_target() -> Vector2:
	if replay != null and replay.playing:
		var fp: Vector2 = replay.focus_point()
		if fp != Vector2.INF:
			return fp
		return Vector2.INF
	var me = player_instances.get(Global.my_player_id)
	if me != null and is_instance_valid(me):
		if me.is_dead:
			return Vector2.INF   # stay where the fighter fell until the respawn
		return me.global_position + Vector2(0.0, float(me.look_offset_y))
	# A spectator: the middle of the living fighters.
	var sum := Vector2.ZERO
	var n := 0
	for pid in player_instances:
		var p = player_instances[pid]
		if is_instance_valid(p) and not p.is_dead:
			sum += p.global_position
			n += 1
	return sum / float(n) if n > 0 else Vector2.INF


func _draw_markers(c: CanvasItem) -> void:
	var me = player_instances.get(Global.my_player_id)
	if me == null or not is_instance_valid(me):
		return
	var top: float = cam.get_screen_center_position().y - VIEW_H / 2.0
	var bottom: float = top + VIEW_H
	for pid in player_instances:
		if pid == Global.my_player_id:
			continue
		var p = player_instances[pid]
		if not is_instance_valid(p) or p.is_dead or not p.visible:
			continue
		var y: float = p.global_position.y
		var at: Vector2
		if y < top - 4.0:
			at = Vector2(p.global_position.x, MARKER_R + 4.0)
		elif y > bottom + 4.0:
			at = Vector2(p.global_position.x, VIEW_H - MARKER_R - 4.0)
		else:
			continue
		at.x = clampf(at.x, MARKER_R + 2.0, float(layout["width"]) - MARKER_R - 2.0)
		c.draw_circle(at, MARKER_R + 2.0, Color(0.0, 0.0, 0.0, 0.6))
		c.draw_circle(at, MARKER_R, Color(0.95, 0.95, 0.95, 0.9))
		var tex: Texture2D = CLASS_ICON_TEX.get(p.class_type)
		if tex != null:
			var side := MARKER_R * 1.5
			c.draw_texture_rect(tex, Rect2(at - Vector2(side, side) / 2.0, Vector2(side, side)), false)
		# A little arrow on the side the fighter is.
		var dir := -1.0 if y < top else 1.0
		var tip := at + Vector2(0.0, dir * (MARKER_R + 6.0))
		c.draw_colored_polygon(PackedVector2Array([tip, tip - Vector2(4.0, dir * 5.0), tip + Vector2(4.0, -dir * 5.0)]), Color(1.0, 0.85, 0.3, 0.95))


# ------------------------------------------------------------------------------
# THE TAPE (Phase 3c)
# One frame per physics tick: where every fighter and projectile is drawn right
# now, plus the arena spin. history_ring.gd keeps the last 360 frames.
# ------------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	_self_respawn_check()
	if tape == null or not tape.recording:
		return
	_record_tape_frame()


func _self_respawn_check() -> void:
	# v0.1.2: my fighter reported its own death and nothing came back for SELF_RESPAWN_S.
	# The server thinks it is alive (the report was folded into an older death, or lost),
	# so a local respawn puts both sides in step. The mark is cleared by the echo
	# (_on_net_player_died) and by respawn() itself.
	if is_round_over or Global.my_player_id <= 0:
		return
	var p = player_instances.get(Global.my_player_id)
	if p == null or not is_instance_valid(p) or not p.is_dead or p.death_report_msec <= 0:
		return
	var waited: int = Time.get_ticks_msec() - int(p.death_report_msec)
	if waited < int(SELF_RESPAWN_S * 1000.0):
		return
	p.death_report_msec = 0
	print("🩹 [SelfRespawn] slot=%d round=%d waited_ms=%d stock=%d" % [Global.my_player_id, current_round, waited, int(player_stocks.get(Global.my_player_id, -1))])
	p.respawn(_spawn_spot(Global.my_player_id))


func _record_tape_frame() -> void:
	var f: Dictionary = tape.next_frame()
	f["rot"] = platforms_node.rotation
	f["flips"] = Global.arena_flips
	var present := 0
	for pid in player_instances:
		var p = player_instances[pid]
		if not is_instance_valid(p) or pid < 1 or pid > 4:
			continue
		var a: PackedFloat32Array = f["fighters"][pid]
		a[0] = p.global_position.x
		a[1] = p.global_position.y
		a[2] = p.aim_direction.x
		a[3] = p.aim_direction.y
		var flags := 0
		if p.is_facing_right: flags |= Global.FLAG_FACING
		if p.is_dashing: flags |= Global.FLAG_DASH
		if p.is_shielding: flags |= Global.FLAG_SHIELD
		if p.is_bear_form: flags |= Global.FLAG_BEAR
		if p.is_egg: flags |= Global.FLAG_EGG
		if p.is_on_floor(): flags |= Global.FLAG_FLOOR
		if p.is_bubble: flags |= HistoryRingScript.FLAG_BUBBLE
		if p.is_ducking: flags |= HistoryRingScript.FLAG_DUCK
		if p.is_dead or not p.visible: flags |= HistoryRingScript.FLAG_DEAD
		a[4] = float(flags)
		present |= 1 << (pid - 1)
	f["present"] = present
	var n := 0
	for node in get_tree().get_nodes_in_group("projectiles"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		var slot: PackedFloat32Array = tape.projectile_slot(f, n)
		slot[0] = float(_tape_weapon_id(node))
		slot[1] = node.global_position.x
		slot[2] = node.global_position.y
		slot[3] = node.rotation
		slot[4] = 1.0 if node.get("is_stuck") == true else 0.0
		slot[5] = float(node.get("shooter_id") if node.get("shooter_id") != null else 0)
		n += 1
	f["n_proj"] = n
	var pu: PackedFloat32Array = f["powerup"]
	if is_instance_valid(powerup_node):
		pu[0] = powerup_node.global_position.x
		pu[1] = powerup_node.global_position.y
		pu[2] = 1.0
	else:
		pu[2] = 0.0
	if tape.commit(Time.get_ticks_msec()):
		var t0 := Time.get_ticks_usec()
		_tape_report()   # the tail is recorded: the tape just froze; the card goes now
		if _replay_due:
			_start_replay()
		if replay != null and replay.playing:
			replay.tick_ms = (Time.get_ticks_usec() - t0) / 1000.0   # v0.1.2 probe: the freeze tick's script cost
	elif _tape_card_dirty and Time.get_ticks_msec() - _tape_card_sent_msec >= int(TAPE_CARD_MIN_S * 1000.0):
		_send_tape_card()   # a stamp happened since the last card and the floor has passed


func _tape_weapon_id(node: Node) -> int:
	# arrow.gd -> 0, firebolt.gd -> 1, kunai.gd -> 2, thorn.gd -> 3 (Global.BIN_WEAPONS order)
	var key := node.get_instance_id()
	if key in _tape_weapon_ids:
		return _tape_weapon_ids[key]
	var wid := 0
	var script = node.get_script()
	if script != null:
		wid = maxi(Global.BIN_WEAPONS.find(str(script.resource_path).get_file().get_basename()), 0)
	if _tape_weapon_ids.size() > 256:
		_tape_weapon_ids.clear()
	_tape_weapon_ids[key] = wid
	return wid


func _tape_report(send_now: bool = true) -> void:
	# One 📼 [Tape] line for the harness, always. The history_status card for the
	# deck goes now (freeze) or waits for the TAPE_CARD_MIN_S floor (a kill stamp).
	print(tape.status_line())
	if send_now:
		_send_tape_card()
	else:
		_tape_card_dirty = true


func _send_tape_card() -> void:
	_tape_card_dirty = false
	_tape_card_sent_msec = Time.get_ticks_msec()
	Global.send_net_data(tape.status_card())


# ------------------------------------------------------------------------------
# THE REPLAY (v0.0.26)
# The server's round_end carries "replay": true when the round ended on a kill.
# The tape freezes about one second later; that is the moment the replay starts.
# It ends by itself after about 5.1 s, or the next round cuts it.
# ------------------------------------------------------------------------------
func _start_replay() -> void:
	_replay_due = false
	var live: Array = []
	for pid in player_instances:
		if is_instance_valid(player_instances[pid]):
			live.append(player_instances[pid])
	for node in get_tree().get_nodes_in_group("projectiles"):
		if is_instance_valid(node) and not node.is_queued_for_deletion():
			live.append(node)
	var why: String = replay.start(tape, platforms_node, live, _round_end_msec)
	if why != "":
		_skip_replay(why)
		return
	banner_label.visible = false   # the VHS caption takes the banner's place
	_send_tape_card()   # the card says playing: true


func _skip_replay(reason: String) -> void:
	_replay_due = false
	tape.replay = {"playing": false, "played": false, "round": tape.round_num, "frames": 0, "drawn": 0,
		"dur_ms": 0, "late_ms": Time.get_ticks_msec() - _round_end_msec, "cut": false, "skipped": reason}
	print(ReplayPlayerScript.status_line(tape, tape.replay))
	_send_tape_card()


func _on_replay_finished(result: Dictionary) -> void:
	banner_label.visible = true
	print(ReplayPlayerScript.status_line(tape, result))
	_send_tape_card()


func _stop_replay_now() -> void:
	# A new round (or the lobby) arrived: whatever the replay was doing, it ends here.
	# A replay that was due but never started (a slow screen whose tape did not
	# freeze in time; its 1.5 s wait runs on process time, which crawls with the
	# ticks) still gets its one line, so every screen reports every due replay.
	if _replay_due and (replay == null or not replay.playing):
		_skip_replay("cut-before-start")
	_replay_due = false
	if replay != null and replay.playing:
		replay.stop(true)

func _exit_tree():
	# change_scene_to_file() removes this scene immediately but frees it at the end
	# of the frame. Any packet handled in between used to reach a node with no tree
	# and crash on get_tree() (the return_to_lobby null-tree crash). Drop the
	# subscriptions the moment we leave the tree.
	_stop_replay_now()
	for sig_name in NET_SIGNAL_HANDLERS:
		var sig := Signal(Global, sig_name)
		var handler := Callable(self, NET_SIGNAL_HANDLERS[sig_name])
		if sig.is_connected(handler):
			sig.disconnect(handler)

# (v0.0.18: the old R key that wiped the crown counters on this screen is gone.)


func _on_net_player_joined(p_id: int, _active_list):
	# A fighter came back to its seat (reload): its movement sequence starts over.
	if p_id in player_instances and is_instance_valid(player_instances[p_id]):
		player_instances[p_id].reset_net_sequence()

func _on_return_to_lobby():
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _on_harness_status(info: Dictionary):
	# v0.0.23: the gate closed or opened. A spectator's JOIN NEXT MATCH button
	# hides while the tests run and comes back, ready to press, when they end.
	var j_btn = get_node_or_null("JoinBtn")
	if j_btn:
		var locked := bool(info.get("active", false))
		j_btn.visible = Global.my_player_id == 0 and not locked
		# v0.1.6: not while "QUEUED FOR LOBBY..." waits for its answer (a second press sent a second request_join).
		if not locked and j_btn.disabled and j_btn.text != "RELOAD THE PAGE TO JOIN" and j_btn.text != "QUEUED FOR LOBBY...":
			j_btn.text = "JOIN NEXT MATCH"
			j_btn.disabled = false

func _on_join_locked(demoted: bool, old_id: int):
	# The server said no to JOIN NEXT MATCH, or took our seat back for the tests.
	var j_btn = get_node_or_null("JoinBtn")
	if j_btn:
		j_btn.text = "JOIN NEXT MATCH"
		j_btn.disabled = false
		j_btn.visible = false
	if not demoted:
		return
	# Same steps as SPECTATE (LEAVE MATCH), but the server already freed the seat.
	if pause_overlay:
		pause_overlay.visible = false
	var p_node = get_node_or_null("Player" + str(old_id))
	if p_node:
		p_node.queue_free()
	player_instances.erase(old_id)
	for child in $HUD.get_children():
		if child is Button and child.text == "LEAVE MATCH":
			child.visible = false
	_show_banner("THE TESTS TOOK YOUR SEAT. WATCH UNTIL THEY FINISH.", 4.0)

func _on_net_version_error(server_version: String):
	# The server refused our JOIN NEXT MATCH: the browser is running a cached build.
	_show_banner("UPDATE REQUIRED: this build is " + Global.GAME_VERSION + ", the server runs "
		+ server_version + ".\nReload the page to get the new version.", 999.0)
	var j_btn = get_node_or_null("JoinBtn")
	if j_btn:
		j_btn.text = "RELOAD THE PAGE TO JOIN"
		j_btn.disabled = true

func _start_new_match():
	current_round = Global.current_round
	_start_round()


# ------------------------------------------------------------------------------
# ROUND START
# We use this function to clear out old projectiles, put players on their
# starting platforms, and reset everyone's health.
# ------------------------------------------------------------------------------
func _on_leave_match_pressed():
	Global.send_net_data({"type": "leave_slot"})
	Global.my_player_id = 0
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _start_round():
	is_round_over = false
	_stop_replay_now()   # v0.0.26: a replay still running is cut; its line is printed before the tape is cleared
	_clear_projectiles()
	_finish_spin_now()
	if tape != null:
		tape.clear(current_round)   # a fresh tape for every round
	
	if touch_controls:
		touch_controls.my_input_prefix = "p" + str(Global.my_player_id) + "_"
	
	# Fighters exist only for the slots the server says are in this match. A client
	# that arrives straight from scene_transition, or joins mid-match, never ran the
	# lobby countdown, so the default configs (all four active) cannot be trusted.
	var roster: Array[int] = Global.playing_players.duplicate()
	if roster.is_empty():
		roster = Global.active_players.duplicate()
	roster.sort()   # the same order on every screen, so spot 1 goes to the same player everywhere
	# v0.0.19: at round start every fighter stands on its own platform spot.
	var ground_spots := _ground_spawn_spots(roster.size())
	var spot_index := 0
	print("🧭 [Spawn] round ", current_round, " flips=", Global.arena_flips, " roster=", roster, " spots=", ground_spots)
	for p_id in Global.player_configs:
		Global.player_configs[p_id]["active"] = p_id in roster
	for p_id in player_instances.keys():
		if not p_id in roster and is_instance_valid(player_instances[p_id]):
			player_instances[p_id].queue_free()
			player_instances.erase(p_id)

	for p_id in roster:
		if p_id < 1 or p_id > 4:
			continue
		# Stocks come from the server (snapshot / player_died / new_round), so a client
		# that rejoins mid-round shows the real count instead of a fresh 3.
		player_stocks[p_id] = Global.server_stocks.get(p_id, Global.max_stocks)
		var on_ground := spot_index < ground_spots.size()
		var spawn_pos: Vector2
		if on_ground:
			spawn_pos = ground_spots[spot_index]
		else:
			spawn_pos = _spawn_spot(p_id)   # no platform top in view: fall back to the air bubble
		spot_index += 1
		if p_id in player_instances and is_instance_valid(player_instances[p_id]):
			player_instances[p_id].respawn(spawn_pos, on_ground)
		else:
			var p = PlayerScene.instantiate()
			p.player_id = p_id
			p.class_type = Global.player_configs[p_id]["class"]
			add_child(p)
			p.respawn(spawn_pos, on_ground)
			player_instances[p_id] = p
			if p_id == Global.my_player_id and Global.ai_persona != "":
				# Headless --ai client: the brain drives this fighter through the
				# input actions (player.gd does not know it exists).
				var brain = BotBrainScript.new()
				brain.setup(Global.ai_persona, Global.ai_seed, Global.ai_difficulty)
				p.add_child(brain)
			if Global.rejoined_mid_match and p_id == Global.my_player_id:
				# Same fight after a reload: no free quiver.
				p.restore_combat_state(Global.load_combat_state())
				Global.rejoined_mid_match = false

	_update_hud()
	_show_banner("ROUND " + str(current_round) + " - FIGHT!", 1.5)
	var queued := Global.my_player_id > 0 and not Global.my_player_id in roster
	if Global.is_spectator or queued:
		await get_tree().create_timer(1.5).timeout
		if not is_inside_tree():
			return
		if queued:
			_show_banner("YOU'RE IN THE QUEUE: NEXT MATCH STARTS AFTER THIS ROUND", 999.0)
		else:
			_show_banner("SPECTATING... WAITING FOR ROUND END", 999.0)


func _clear_projectiles():
	for p in get_tree().get_nodes_in_group("projectiles"):
		p.queue_free()

func _on_net_player_died(killer_id: int, victim_id: int, new_stock: int, weapon: String = "?"):
	player_stocks[victim_id] = new_stock
	if victim_id == Global.my_player_id and victim_id in player_instances and is_instance_valid(player_instances[victim_id]):
		player_instances[victim_id].death_report_msec = 0   # the echo came: the normal 1.2 s respawn below
	# Phase 3c: stamp the tape with this kill (the server's word, so every screen stamps the same).
	if tape != null and not tape.stamp(killer_id, victim_id, weapon).is_empty():
		_tape_report(false)   # v0.0.35: the line now, the card within TAPE_CARD_MIN_S
	if victim_id in player_instances and is_instance_valid(player_instances[victim_id]):
		player_instances[victim_id].force_die()
		
	var victim_name = Global.player_names.get(victim_id, "Player " + str(victim_id))
	var killer_name = Global.player_names.get(killer_id, "Player " + str(killer_id))
	
	if killer_id == victim_id:
		_show_banner(victim_name + " fell!", 1.0)
	else:
		_show_banner(killer_name + " knocked out " + victim_name + "!", 1.0)
		
	_update_hud()
	
	if new_stock > 0:
		await get_tree().create_timer(1.2).timeout
		if not is_inside_tree():
			return
		if not is_round_over and victim_id in player_instances and is_instance_valid(player_instances[victim_id]):
			var spawn_pos = _spawn_spot(victim_id)
			player_instances[victim_id].respawn(spawn_pos)

# Obsolete: We don't check round end locally anymore! The server does it!
func _check_round_end():
	pass

func _on_round_end_sync(winner_id: int, scores: Dictionary, round_num: int, match_over: bool = false, replay_due: bool = false):
	if is_round_over:
		return # Ignore duplicate network triggers

	is_round_over = true
	current_round = round_num
	_round_end_msec = Time.get_ticks_msec()
	_replay_due = replay_due and tape != null
	if tape != null:
		tape.close_round()   # the newest stamp is the closing kill; one more second, then freeze

	# Sync the scores from the server
	for p_id in scores:
		Global.player_scores[int(p_id)] = int(scores[p_id])

	_update_hud()
	_display_round_winner(winner_id, match_over)

	if _replay_due:
		if tape.frozen:
			_skip_replay("empty-tape")   # nothing was recorded this round
			return
		# The freeze normally lands 1.0 s from now. A screen whose ticks stalled
		# (hidden tab) skips the replay instead of starting it late.
		await get_tree().create_timer(REPLAY_WAIT_S).timeout
		if not is_inside_tree():
			return
		if _replay_due and not replay.playing:
			_skip_replay("not-frozen")

func _display_round_winner(winner_id: int, match_over: bool = false):
	if winner_id <= 0:
		_show_banner("*** NO SURVIVORS: ROUND " + str(current_round) + " IS A DRAW ***", 2.2)
		return
	var winner_class = Global.CLASS_INFO[Global.player_configs[winner_id]["class"]]["name"]
	var is_me = (winner_id == Global.my_player_id)

	# The server decides when the match is won (5 crowns) and sends match_over;
	# it returns everyone to the lobby a few seconds later.
	if match_over:
		var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
		var txt = "*** " + ("YOU WON THE MATCH!" if is_me else w_name + " (" + winner_class + ") WINS THE MATCH!") + " ***\nReturning to lobby..."
		_show_banner(txt, 999.0)
	else:
		var w_name = Global.player_names.get(winner_id, "PLAYER " + str(winner_id))
		var txt = "*** " + ("YOU WON ROUND " + str(current_round) + "!" if is_me else w_name + " (" + winner_class + ") WINS ROUND " + str(current_round) + "!") + " ***"
		_show_banner(txt, 2.2)
		# The next round starts ONLY when the server sends new_round (see
		# _on_new_round_sync). The old local 2.6 s timer here made every client
		# start the round twice and let the round counter drift.

func _on_new_round_sync(round_num: int):
	current_round = round_num
	_start_round()

func _show_banner(text: String, duration: float):
	banner_label.text = text
	banner_label.visible = true
	var tween = create_tween()
	banner_label.modulate.a = 0.0
	tween.tween_property(banner_label, "modulate:a", 1.0, 0.15)
	if duration < 900.0:
		await get_tree().create_timer(duration).timeout
		if not is_inside_tree():
			return
		if banner_label.text == text:
			var fade = create_tween()
			fade.tween_property(banner_label, "modulate:a", 0.0, 0.25)

func _update_hud():
	_update_panel(p1_panel, 1)
	_update_panel(p2_panel, 2)
	_update_panel(p3_panel, 3)
	_update_panel(p4_panel, 4)

func _pad_label(lbl: Label) -> void:
	# v0.0.18. The story: each top-bar label has a little 16 px icon drawn on
	# top of its left edge. The text used to be pushed right with three spaces,
	# but three spaces are only about 9 px wide, so the first letter hid under
	# the icon: "Andrew" read "ndrew" and the crown number was gone. Now the
	# label starts its text 20 px in, past the icon, with no spaces needed.
	if lbl.has_theme_stylebox_override("normal"):
		return
	var pad = StyleBoxEmpty.new()
	pad.content_margin_left = 20.0
	lbl.add_theme_stylebox_override("normal", pad)

func _update_panel(panel: Control, p_id: int):
	if not Global.player_configs[p_id]["active"]:
		panel.visible = false
		return
		
	panel.visible = true
	var c_type = Global.player_configs[p_id]["class"]
	var c_info = Global.CLASS_INFO[c_type]
	
	var name_lbl = panel.get_node("NameLabel")
	var stock_lbl = panel.get_node("StockLabel")
	var score_lbl = panel.get_node("ScoreLabel")
	_pad_label(name_lbl)
	_pad_label(stock_lbl)
	_pad_label(score_lbl)
	
	var disp_name = Global.player_names.get(p_id, "P" + str(p_id))
	if p_id == Global.my_player_id and Global.my_player_name != "":
		disp_name = Global.my_player_name
		
	var class_icon = name_lbl.get_node_or_null("ClassIcon")
	if not class_icon:
		class_icon = TextureRect.new()
		class_icon.name = "ClassIcon"
		class_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		class_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		class_icon.size = Vector2(16, 16)
		class_icon.position = Vector2(0, 2)
		name_lbl.add_child(class_icon)
	class_icon.texture = CLASS_ICON_TEX.get(c_type)
	name_lbl.text = disp_name + (" (You)" if p_id == Global.my_player_id else "")
	name_lbl.modulate = c_info["color"]
	
	var stocks = player_stocks.get(p_id, Global.max_stocks)
	var stock_icon = stock_lbl.get_node_or_null("StockIcon")
	if not stock_icon:
		stock_icon = TextureRect.new()
		stock_icon.name = "StockIcon"
		stock_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stock_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stock_icon.size = Vector2(16, 16)
		stock_icon.position = Vector2(0, 2)
		stock_lbl.add_child(stock_icon)
	stock_icon.texture = HEART_TEX
	stock_lbl.text = "x " + str(stocks)
	
	var score_icon = score_lbl.get_node_or_null("ScoreIcon")
	if not score_icon:
		score_icon = TextureRect.new()
		score_icon.name = "ScoreIcon"
		score_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		score_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		score_icon.size = Vector2(16, 16)
		score_icon.position = Vector2(0, 2)
		score_lbl.add_child(score_icon)
	score_icon.texture = CROWN_TEX
	score_lbl.text = str(Global.player_scores[p_id])

func _host_spawn_powerup():
	if not is_instance_valid(powerup_node) and not is_arena_rotating:
		Global.send_net_data({"type": "spawn_powerup", "x": 320.0, "y": 40.0})
		_spawn_powerup(320.0, 40.0)

func _on_net_spawn_powerup(x: float, y: float):
	if Global.my_player_id != 1:
		_spawn_powerup(x, y)

func _spawn_powerup(px: float, py: float):
	if is_instance_valid(powerup_node):
		return
		
	powerup_node = Area2D.new()
	powerup_node.global_position = Vector2(px, py)
	powerup_node.collision_mask = 2
	
	var col = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = 16.0
	col.shape = shape
	powerup_node.add_child(col)
	
	var tex = Sprite2D.new()
	tex.texture = PICKUP_TEX
	tex.scale = Vector2(0.12, 0.12)  # Scale a 256x256 image to ~30x30
	powerup_node.add_child(tex)
	
	add_child(powerup_node)
	powerup_node.connect("body_entered", Callable(self, "_on_powerup_body_entered"))

func _on_powerup_body_entered(body: Node2D):
	if body.is_in_group("players") and body.player_id == Global.my_player_id:
		Global.send_net_data({"type": "activate_powerup", "powerup_id": 1})
		_activate_rotation()

func _on_net_activate_powerup(pid: int):
	_activate_rotation()
	
func _activate_rotation():
	if is_instance_valid(powerup_node):
		powerup_node.queue_free()
		powerup_node = null
		
	if is_arena_rotating:
		return
		
	is_arena_rotating = true
	if SHIFT_SOFT_PLATFORMS:
		_set_platforms_solid(false)
	Global.arena_flips += 1
	_show_banner("** ARENA SHIFT! **", 2.5)
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(platforms_node, "rotation", platforms_node.rotation + PI, 2.5)
	spin_tween = tween

	await get_tree().create_timer(2.5).timeout
	if not is_inside_tree():
		return
	if spin_tween == tween:   # still our spin: a round start may have finished it already
		spin_tween = null
		is_arena_rotating = false
		_set_platforms_solid(true)

func _set_platforms_solid(solid: bool) -> void:
	# v0.0.32, backlog 9. The story: the half turn swings the outer platforms
	# 29 to 36 px above the top edge, and a fighter standing on one rode it out
	# of the screen for about a second. Now the platforms are not solid while
	# the stage turns: collision_layer goes to 0, so fighters fall through the
	# turning stage and land on the new layout when it locks. collision_mask is
	# left alone. Each body's own layer is stashed and given back, so nothing
	# here needs to know the layer numbers.
	for plat in platforms_node.get_children():
		if not plat is StaticBody2D:
			continue
		if solid:
			if platform_layers.has(plat):
				plat.collision_layer = platform_layers[plat]
		else:
			if not platform_layers.has(plat):
				platform_layers[plat] = plat.collision_layer
			plat.collision_layer = 0
	if solid:
		platform_layers.clear()

func _finish_spin_now() -> void:
	# v0.0.20. The story: a round could start while the arena was still turning
	# (the spin takes 2.5 s, the next round comes 2.6 s after the last kill).
	# Fighters were then put on platforms that had not arrived yet. Now a round
	# start jumps the platforms to where the spin was going and stops the spin.
	if spin_tween != null and spin_tween.is_valid():
		spin_tween.kill()
	spin_tween = null
	platforms_node.rotation = Global.arena_flips * PI
	is_arena_rotating = false
	_set_platforms_solid(true)

func _on_arena_join_pressed():
	Global.request_join(Global._load_saved_player_id())
	var j_btn = get_node_or_null("JoinBtn")
	if j_btn:
		j_btn.text = "QUEUED FOR LOBBY..."
		j_btn.disabled = true

func _on_spectate_pressed():
	if pause_overlay:
		pause_overlay.visible = false
	Global.send_net_data({"type": "leave_slot"})
	var p_node = get_node_or_null("Player" + str(Global.my_player_id))
	if p_node:
		p_node.queue_free()
	Global.my_player_id = 0

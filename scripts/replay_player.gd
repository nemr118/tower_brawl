# ==============================================================================
# REPLAY_PLAYER.GD (The VHS Replay)
# ==============================================================================
# v0.0.26. When a round ends on a kill, every screen plays its own frozen tape
# back (history_ring.gd). This node does the playing:
#   1. It pauses the live world (fighters and projectiles: process_mode DISABLED,
#      hidden). Nothing has to be put back later: the next round respawns everyone.
#   2. It draws "ghosts": real player.tscn and projectile scenes with is_ghost /
#      no physics, moved to where the tape says, one tape frame at a time.
#   3. The platforms turn as the tape says (rot), then go back to the flip count.
#   4. A VHS overlay on top: scanlines, a rolling tracking bar, a little shake,
#      the PLAY / REW / SLOW / STOP label, a counter and the kill caption.
#
# The plan for a tape with closing kill K (see docs/PASSDOWN.md):
#   0.0-0.4 s  ◄◄ REW   K+60 back to K-150 at 10x backwards
#   0.4-2.4 s  ► PLAY   K-150 to K-30 at 1x
#   2.4-4.4 s  ► SLOW   K-30 to K+30 at 0.5x, a white flash on frame K
#   4.4-4.9 s  ► PLAY   K+30 to K+60 (the fall) at 1x
#   4.9-5.1 s  ■ STOP   the last frame held, fade to black
# Stepping runs on the render clock (_process). This is local tape, not network
# state, so CLAUDE.md rule 3 is not touched. arena.gd starts and stops it.
# ==============================================================================
extends Node2D

const PlayerScene = preload("res://scenes/player.tscn")
const PROJ_SCENES = [                          # Global.BIN_WEAPONS order: arrow, firebolt, kunai, thorn
	preload("res://scenes/arrow.tscn"), preload("res://scenes/firebolt.tscn"),
	preload("res://scenes/kunai.tscn"), preload("res://scenes/thorn.tscn")]
const HistoryRingScript = preload("res://scripts/history_ring.gd")

const BEFORE_FRAMES := 150      # tape frames before the kill on the replay (2.5 s)
const AFTER_FRAMES := 60        # tape frames after the kill (the 1 s tail)
const SLOW_FRAMES := 30         # frames each side of the kill played at SLOW_SPEED
const SLOW_SPEED := 0.5
const REW_SPEED := 10.0         # tape frames per real frame while rewinding
const STOP_S := 0.2             # the fade to black at the end
const TAPE_FPS := 60.0
const ARENA_W := 640.0
const ARENA_H := 360.0
const MAX_GHOST_PROJ := 32
const TRACK_PERIOD_S := 1.5     # the tracking bar rolls down the screen this often

signal finished(result: Dictionary)

var playing: bool = false
var tape = null                 # the frozen history ring
var _platforms: Node2D = null
var _phase: String = ""         # rew, play, slow, tail, stop
var _pos: float = 0.0           # tape position, in frames from _first
var _first: int = 0             # first seq on the replay (K - BEFORE_FRAMES, or the oldest frame)
var _kill: int = 0              # K, the closing kill's frame
var _last: int = 0              # last seq on the replay (K + AFTER_FRAMES, or the newest frame)
var _shown_seq: int = -1
var _drawn: Dictionary = {}     # seq -> true, distinct frames shown
var _started_msec: int = 0
var _round_end_msec: int = 0
var _stamp: Dictionary = {}
var _clock: float = 0.0         # seconds since the replay started
var _stop_t: float = 0.0
var _flash: float = 0.0
var _fade: float = 0.0
var _shake: Vector2 = Vector2.ZERO
var _track_y: float = -20.0
var _rng := RandomNumberGenerator.new()
var _ghosts: Dictionary = {}    # pid -> ghost fighter (player.tscn with is_ghost)
var _ghost_prev: Dictionary = {}   # pid -> [seq, Vector2] the last spot shown, for the run cycle
var _ghost_proj: Array = []     # [{wid, node}] pooled ghost projectiles by list index
var _powerup: Array = [0.0, 0.0, false]
var _frozen_live: Array = []    # [[node, was_visible, process_mode]] the paused live world
var _overlay: Node2D = null
var _victim_pos: Vector2 = Vector2.INF
# v0.1.2 probe (cut 1): what the start cost. start_ms = start() itself, tick_ms = the
# whole freeze tick (set by arena.gd), first_ms = the slowest of the first three
# drawn frames (the one that drew the overlay for the first time).
var start_ms: float = 0.0
var tick_ms: float = 0.0
var first_ms: float = 0.0
var _first_frames: int = 0


# The overlay draws above the ghosts. A child with a higher z_index, so its
# _draw lands on top of every ghost fighter and projectile.
class VhsOverlay extends Node2D:
	var owner_replay = null
	func _draw() -> void:
		if owner_replay != null:
			owner_replay._draw_overlay(self)


func _ready() -> void:
	z_index = 20
	_rng.randomize()
	_overlay = VhsOverlay.new()
	_overlay.owner_replay = self
	_overlay.z_index = 30
	add_child(_overlay)
	set_process(false)
	if Global.warm_enabled:
		prepare_ghosts()


# Start playing `ring` (frozen, with a closing kill). `live` = the nodes to pause
# (fighters and projectiles). Returns "" when the replay started, else the reason
# it could not (the skipped= word on the 📼 [Replay] line).
func start(ring, platforms: Node2D, live: Array, round_end_msec: int) -> String:
	var t0 := Time.get_ticks_usec()
	if playing:
		return "already-playing"
	if ring == null or not ring.frozen:
		return "not-frozen"
	if ring.closing_seq < 0 or ring.frame_at(ring.closing_seq).is_empty():
		return "no-closing-stamp"
	tape = ring
	_platforms = platforms
	_stamp = ring.report_stamp()   # the closing kill, not a death stamped in the tail (v0.1.1)
	_kill = ring.closing_seq
	_first = maxi(_kill - BEFORE_FRAMES, ring.oldest_seq())
	_last = mini(_kill + AFTER_FRAMES, ring.newest_seq())
	if _last <= _first:
		return "too-short"
	_round_end_msec = round_end_msec
	_started_msec = Time.get_ticks_msec()
	_drawn.clear()
	_ghost_prev.clear()
	_shown_seq = -1
	_clock = 0.0
	_stop_t = 0.0
	_flash = 0.0
	_fade = 0.0
	_track_y = -20.0
	_victim_pos = Vector2.INF
	start_ms = 0.0
	tick_ms = 0.0
	first_ms = 0.0
	_first_frames = 0
	_phase = "rew"
	_pos = float(_last - _first)
	# Pause the live world. Nothing moves or draws under the ghosts.
	_frozen_live.clear()
	for node in live:
		if is_instance_valid(node) and node is Node:
			_frozen_live.append([node, node.visible if node is CanvasItem else true, node.process_mode])
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if node is CanvasItem:
				node.visible = false
	playing = true
	tape.replay = {"playing": true, "played": false, "round": tape.round_num, "frames": _last - _first + 1,
		"drawn": 0, "dur_ms": 0, "late_ms": _started_msec - _round_end_msec, "cut": false, "skipped": null}
	visible = true
	set_process(true)
	_show_frame(_last)
	_overlay.queue_redraw()
	start_ms = (Time.get_ticks_usec() - t0) / 1000.0
	return ""


# Stop now. cut = true when the next round arrived before the tape ran out.
func stop(cut: bool) -> void:
	if not playing:
		return
	playing = false
	set_process(false)
	var now := Time.get_ticks_msec()
	var result := {"playing": false, "played": true, "round": tape.round_num, "frames": _last - _first + 1,
		"drawn": _drawn.size(), "dur_ms": now - _started_msec, "late_ms": _started_msec - _round_end_msec,
		"cut": cut, "skipped": null, "kill_seq": _kill, "from": _first, "to": _last,
		"start_ms": snappedf(start_ms, 0.1), "tick_ms": snappedf(tick_ms, 0.1), "first_ms": snappedf(first_ms, 0.1)}
	tape.replay = result
	# Ghosts hidden (kept for the next replay, v0.1.2), live world back.
	for pid in _ghosts:
		if is_instance_valid(_ghosts[pid]):
			_ghosts[pid].visible = false
	for entry in _ghost_proj:
		if is_instance_valid(entry["node"]):
			entry["node"].visible = false
	for entry in _frozen_live:
		var node = entry[0]
		if is_instance_valid(node):
			node.process_mode = entry[2]
			if node is CanvasItem:
				node.visible = entry[1]
	_frozen_live.clear()
	if is_instance_valid(_platforms):
		_platforms.rotation = Global.arena_flips * PI
	position = Vector2.ZERO
	visible = false
	_overlay.queue_redraw()
	finished.emit(result)


func _process(delta: float) -> void:
	if not playing:
		return
	_clock += delta
	if _first_frames < 3:
		_first_frames += 1
		first_ms = maxf(first_ms, delta * 1000.0)
	var slow_start := float(_kill - SLOW_FRAMES - _first)
	var slow_end := float(_kill + SLOW_FRAMES - _first)
	var end_pos := float(_last - _first)
	match _phase:
		"rew":
			_pos -= delta * TAPE_FPS * REW_SPEED
			if _pos <= 0.0:
				_pos = 0.0
				_phase = "play"
		"play":
			_pos += delta * TAPE_FPS
			if _pos >= slow_start:
				_phase = "slow"
		"slow":
			var before := _pos
			_pos += delta * TAPE_FPS * SLOW_SPEED
			if before < float(_kill - _first) and _pos >= float(_kill - _first):
				_flash = 1.0   # the kill frame
			if _pos >= slow_end:
				_phase = "tail"
		"tail":
			_pos += delta * TAPE_FPS
			if _pos >= end_pos:
				_pos = end_pos
				_phase = "stop"
		"stop":
			_stop_t += delta
			_fade = clampf(_stop_t / STOP_S, 0.0, 1.0)
			if _stop_t >= STOP_S:
				stop(false)
				return
	_pos = clampf(_pos, 0.0, end_pos)
	var seq := _first + int(_pos)
	if seq != _shown_seq:
		_show_frame(seq)
	# VHS motion: the tracking bar rolls, the picture shakes a little (a lot while rewinding).
	_track_y = -20.0 + fmod(_clock, TRACK_PERIOD_S) / TRACK_PERIOD_S * (ARENA_H + 40.0)
	var shake_chance := 0.6 if _phase == "rew" else 0.05
	if _rng.randf() < shake_chance:
		_shake = Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-1.0, 1.0) if _phase == "rew" else 0.0)
	else:
		_shake = Vector2.ZERO
	position = _shake
	if _flash > 0.0:
		_flash = maxf(_flash - delta * 6.0, 0.0)
	_overlay.queue_redraw()


# Put every ghost where tape frame `seq` says.
func _show_frame(seq: int) -> void:
	var f: Dictionary = tape.frame_at(seq)
	if f.is_empty():
		return
	_shown_seq = seq
	_drawn[seq] = true
	if is_instance_valid(_platforms):
		_platforms.rotation = float(f["rot"])
	var present: int = f["present"]
	var victim: int = int(_stamp.get("victim", 0))
	_victim_pos = Vector2.INF
	for pid in range(1, 5):
		var on := (present & (1 << (pid - 1))) != 0
		var a: PackedFloat32Array = f["fighters"][pid] if on else PackedFloat32Array()
		var flags := int(a[4]) if on else 0
		if not on or (flags & HistoryRingScript.FLAG_DEAD) != 0:
			if pid in _ghosts and is_instance_valid(_ghosts[pid]):
				_ghosts[pid].visible = false
			_ghost_prev.erase(pid)
			continue
		var g = _ghost_for(pid)
		if g == null:
			continue
		var pos := Vector2(a[0], a[1])
		var prev: Array = _ghost_prev.get(pid, [])
		var vel := Vector2.ZERO
		if not prev.is_empty() and int(prev[0]) != seq:
			vel = (pos - prev[1]) / (absf(float(seq - int(prev[0]))) / TAPE_FPS)
		_ghost_prev[pid] = [seq, pos]
		g.visible = true
		g.global_position = pos
		g.velocity = vel
		g.aim_direction = Vector2(a[2], a[3]) if Vector2(a[2], a[3]).length_squared() > 0.01 else Vector2.RIGHT
		g.is_facing_right = (flags & Global.FLAG_FACING) != 0
		g.is_dashing = (flags & Global.FLAG_DASH) != 0
		g.is_shielding = (flags & Global.FLAG_SHIELD) != 0
		g.is_bear_form = (flags & Global.FLAG_BEAR) != 0
		g.is_egg = (flags & Global.FLAG_EGG) != 0
		g.is_bubble = (flags & HistoryRingScript.FLAG_BUBBLE) != 0
		g.ghost_on_floor = (flags & Global.FLAG_FLOOR) != 0
		g.dash_dir = vel.normalized() if vel.length_squared() > 1.0 else g.aim_direction
		g.anim_time = float(f["msec"]) * 0.012   # the same 12 x seconds the live fighter counts
		g.queue_redraw()
		if pid == victim:
			_victim_pos = pos
	var n: int = f["n_proj"]
	for i in range(mini(n, MAX_GHOST_PROJ)):
		var slot: PackedFloat32Array = f["projectiles"][i]
		var node = _ghost_projectile(i, int(slot[0]))
		if node == null:
			continue
		node.visible = true
		node.global_position = Vector2(slot[1], slot[2])
		node.rotation = slot[3]
		if "is_stuck" in node:
			node.is_stuck = slot[4] >= 0.5
		if "shooter_id" in node:
			node.shooter_id = int(slot[5])
		node.queue_redraw()
	for i in range(mini(n, MAX_GHOST_PROJ), _ghost_proj.size()):
		if is_instance_valid(_ghost_proj[i]["node"]):
			_ghost_proj[i]["node"].visible = false
	var pu: PackedFloat32Array = f["powerup"]
	_powerup = [pu[0], pu[1], pu[2] >= 0.5]


# One hidden ghost per seated fighter, made at the arena's load (v0.1.2, cut 1).
# The first replay used to instantiate them inside the freeze tick.
func prepare_ghosts() -> void:
	for pid in Global.active_players:
		if pid >= 1 and pid <= 4:
			var g = _ghost_for(pid)
			if g != null:
				g.visible = false


func _ghost_for(pid: int):
	if pid in _ghosts and is_instance_valid(_ghosts[pid]):
		var kept = _ghosts[pid]
		var want = Global.player_configs.get(pid, {}).get("class", kept.class_type)
		if kept.class_type != want:   # a seat that changed hands mid-match
			kept.class_type = want
			kept._apply_class_defaults()
		return kept
	var cfg: Dictionary = Global.player_configs.get(pid, {})
	var g = PlayerScene.instantiate()
	g.is_ghost = true
	g.player_id = pid
	g.class_type = cfg.get("class", Global.ClassType.RANGER)
	g.z_index = 1
	add_child(g)
	g.is_dead = false
	g.spawn_invuln_timer = 0.0
	_ghosts[pid] = g
	return g


func _ghost_projectile(i: int, wid: int):
	wid = clampi(wid, 0, PROJ_SCENES.size() - 1)
	if i < _ghost_proj.size():
		var entry: Dictionary = _ghost_proj[i]
		if entry["wid"] == wid and is_instance_valid(entry["node"]):
			return entry["node"]
		if is_instance_valid(entry["node"]):
			entry["node"].queue_free()
		_ghost_proj.remove_at(i)
	var node = PROJ_SCENES[wid].instantiate()
	add_child(node)
	# A ghost: not a real projectile. Out of the group (the tape and the round
	# start must not see it), no physics, no hits.
	node.remove_from_group("projectiles")
	node.set_physics_process(false)
	node.set_process(false)
	node.monitoring = false
	node.monitorable = false
	node.collision_layer = 0
	node.collision_mask = 0
	node.z_index = 1
	var entry := {"wid": wid, "node": node}
	if i < _ghost_proj.size():
		_ghost_proj.insert(i, entry)
	else:
		_ghost_proj.append(entry)
	return node


func _label() -> String:
	# v0.0.41: the word only. The ◄◄ ► ■ marks used to be characters, and the
	# font the web build ships has no glyph for them, so a browser drew boxes.
	# The mark is now a shape from _draw_icon, which needs no font at all.
	match _phase:
		"rew": return "REW"
		"slow": return "SLOW"
		"stop": return "STOP"
		_: return "PLAY"


const ICON_H := 14.0            # the icon's height in px; it sits on the label's baseline
const ICON_W := 12.0            # one triangle or the square; REW is two triangles

func _draw_icon(c: CanvasItem, at: Vector2, col: Color) -> float:
	# Draws the mark for the current phase with its bottom-left corner at `at`
	# (the text baseline) and returns its width, so the word can follow it.
	var y0 := at.y - ICON_H
	var y1 := at.y
	var ym := at.y - ICON_H / 2.0
	var shapes: Array = []
	match _phase:
		"rew":
			shapes.append(PackedVector2Array([Vector2(at.x + ICON_W, y0), Vector2(at.x, ym), Vector2(at.x + ICON_W, y1)]))
			shapes.append(PackedVector2Array([Vector2(at.x + ICON_W * 2.0, y0), Vector2(at.x + ICON_W, ym), Vector2(at.x + ICON_W * 2.0, y1)]))
		"stop":
			shapes.append(PackedVector2Array([Vector2(at.x, y0), Vector2(at.x + ICON_W, y0), Vector2(at.x + ICON_W, y1), Vector2(at.x, y1)]))
		_:
			shapes.append(PackedVector2Array([Vector2(at.x, y0), Vector2(at.x + ICON_W, ym), Vector2(at.x, y1)]))
	var outline := Color(0.0, 0.0, 0.0, 0.9)
	for poly in shapes:
		var closed := PackedVector2Array(poly)
		closed.append(poly[0])
		c.draw_polyline(closed, outline, 3.0, true)
	for poly in shapes:
		c.draw_colored_polygon(poly, col)
	return ICON_W * 2.0 if _phase == "rew" else ICON_W


func _caption() -> String:
	if _stamp.is_empty():
		return ""
	var k := int(_stamp.get("killer", 0))
	var v := int(_stamp.get("victim", 0))
	var kn: String = str(Global.player_names.get(k, "P" + str(k)))
	var vn: String = str(Global.player_names.get(v, "P" + str(v)))
	var w: String = str(_stamp.get("weapon", "?"))
	if k == v or k <= 0:
		return "%s fell to %s" % [vn, w]
	return "%s killed %s · %s" % [kn, vn, w]


# The VHS look, drawn by the overlay child on top of the ghosts.
func _draw_overlay(c: CanvasItem) -> void:
	if not playing:
		return
	var font: Font = ThemeDB.fallback_font
	# A faint cool tint and the scanlines: every other row a little darker.
	c.draw_rect(Rect2(-8, -8, ARENA_W + 16, ARENA_H + 16), Color(0.75, 0.8, 1.0, 0.06), true)
	var y := 0.5
	while y < ARENA_H:
		c.draw_line(Vector2(-8, y), Vector2(ARENA_W + 8, y), Color(0.0, 0.0, 0.0, 0.16), 1.0)
		y += 2.0
	# The tracking bar: a pale band rolling down, with a brighter line inside.
	c.draw_rect(Rect2(-8, _track_y, ARENA_W + 16, 12.0), Color(1.0, 1.0, 1.0, 0.05), true)
	c.draw_line(Vector2(-8, _track_y + 6.0), Vector2(ARENA_W + 8, _track_y + 6.0), Color(1.0, 1.0, 1.0, 0.10), 2.0)
	# The power-up, when the tape had one.
	if _powerup[2]:
		c.draw_arc(Vector2(_powerup[0], _powerup[1]), 14.0, 0.0, TAU, 20, Color(1.0, 0.9, 0.3, 0.8), 2.0)
		c.draw_circle(Vector2(_powerup[0], _powerup[1]), 5.0, Color(1.0, 0.8, 0.2, 0.7))
	# A red ring around the one who is about to fall, during the slow part.
	if _phase == "slow" and _victim_pos != Vector2.INF:
		var pulse := 26.0 + sin(_clock * 12.0) * 3.0
		c.draw_arc(_victim_pos + Vector2(0, -8), pulse, 0.0, TAU, 32, Color(1.0, 0.25, 0.2, 0.85), 2.5)
	# Label and counter, bottom left, in the void column beside the seam (the top
	# row belongs to the HUD panels). Counter = seconds from the kill frame.
	var row := ARENA_H - 12.0
	var secs := float(_shown_seq - _kill) / TAPE_FPS
	var counter := ("+%.1fs" if secs >= 0.0 else "%.1fs") % secs
	var icon_w := _draw_icon(c, Vector2(12, row - 1.0), Color(1.0, 1.0, 1.0))
	_text(c, font, Vector2(12 + icon_w + 6.0, row), _label(), 18, Color(1.0, 1.0, 1.0))
	_text(c, font, Vector2(104, row), counter, 16, Color(0.9, 0.9, 0.9))
	# REPLAY and the blinking red dot, bottom right.
	var w := font.get_string_size("REPLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	_text(c, font, Vector2(ARENA_W - 12 - w, row), "REPLAY", 18, Color(1.0, 1.0, 1.0))
	if fmod(_clock, 1.0) < 0.5:
		c.draw_circle(Vector2(ARENA_W - 22 - w, row - 7.0), 5.0, Color(1.0, 0.2, 0.2))
	# The caption at the bottom: who got whom, with what, and the round.
	var cap := _caption()
	if cap != "":
		var cw := font.get_string_size(cap, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		_text(c, font, Vector2((ARENA_W - cw) / 2.0, ARENA_H - 22), cap, 16, Color(1.0, 0.95, 0.7))
	var rl := "ROUND %d" % (tape.round_num if tape != null else 0)
	var rw := font.get_string_size(rl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	_text(c, font, Vector2((ARENA_W - rw) / 2.0, ARENA_H - 42), rl, 12, Color(0.85, 0.85, 0.9))
	# The white flash on the kill frame, then the fade to black at the end.
	if _flash > 0.0:
		c.draw_rect(Rect2(-8, -8, ARENA_W + 16, ARENA_H + 16), Color(1.0, 1.0, 1.0, _flash * 0.7), true)
	if _fade > 0.0:
		c.draw_rect(Rect2(-8, -8, ARENA_W + 16, ARENA_H + 16), Color(0.0, 0.0, 0.0, _fade), true)


func _text(c: CanvasItem, font: Font, at: Vector2, s: String, size: int, col: Color) -> void:
	c.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0.0, 0.0, 0.0, 0.9))
	c.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# The log line the harness reads: one per replay, printed by arena.gd when the
# replay ends or is skipped.
static func status_line(ring, result: Dictionary) -> String:
	var last: Dictionary = ring.report_stamp() if ring != null else {}
	var weapon: String = str(last.get("weapon", "-")).replace(" ", "_") if not last.is_empty() else "-"
	var skipped = result.get("skipped")
	return ("📼 [Replay] round=%d killer=%d victim=%d weapon=%s from=%d to=%d frames=%d drawn=%d dur_ms=%d late_ms=%d cut=%d skipped=%s" % [
		int(result.get("round", 0)), int(last.get("killer", 0)), int(last.get("victim", 0)), weapon,
		int(result.get("from", -1)), int(result.get("to", -1)), int(result.get("frames", 0)),
		int(result.get("drawn", 0)), int(result.get("dur_ms", 0)), int(result.get("late_ms", 0)),
		1 if bool(result.get("cut", false)) else 0, str(skipped) if skipped != null else "-"]) + (
		" start_ms=%.1f tick_ms=%.1f first_ms=%.0f" % [float(result.get("start_ms", 0.0)),
		float(result.get("tick_ms", 0.0)), float(result.get("first_ms", 0.0))])

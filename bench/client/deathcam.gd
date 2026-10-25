# The deathcam (p4.8). The user: "an accelerating montage of the kills the match
# winner performed with a climax of a slow motion final kill for the match win;
# VHS style replay like we did in the last version of tower brawl" (only at a
# match's end; no red ring). Every screen records a rolling few seconds of what
# the arena draws (its views, REC_HZ a second, with their events); each kill
# (E_KILL: the killer, the one who died) keeps a clip: KEEP_S before, AFTER_S
# after. When the match ends, the winner's kills play: the earlier ones faster and
# faster (SPEEDS), then the match's last one in time, slow around the kill with a
# white flash, and a fade. The VHS look on top (old game: scripts/replay_player.gd):
# a cool tint, scanlines, a rolling tracking bar, PLAY and SLOW marks drawn as
# shapes (the web font has no symbols), the speed, a counter to the kill, REPLAY
# with a blinking dot, a caption. Each kill pops (the user: "a nice little pop as
# each kill happens"): the camera punches in toward the kill and eases back, a
# flash, a gold KILL!; the last kill: the camera pushes in and holds close through
# the slow motion, FINAL KILL. A seated player's SKIP button (or Esc, space, enter
# on a PC) asks the server to end the match's end for everyone (the user: "skip
# the montage for everyone and go back to the lobby"): skip_pressed, the JSON skip.
extends CanvasLayer

signal skip_pressed

const P = preload("res://sim/proto.gd")
const World = preload("res://client/world.gd")
const REC_HZ := 20.0
const KEEP_S := 3.0               # a clip's run-up
const AFTER_S := 0.8              # and what follows the kill
const MAX_PER_KILLER := 6
const EARLY := 5                  # at most this many earlier kills play, oldest first, faster and faster:
const SPEED_FIRST := 1.0          # from this speed
const SPEED_LAST := 3.4           # to this one (one earlier kill: SPEED_ONE)
const SPEED_ONE := 1.6
const EARLY_BEFORE := 1.6         # an earlier kill: this much run-up
const EARLY_AFTER := 0.35
const FINAL_BEFORE := 2.2         # the last kill: this run-up in time,
const SLOW_FROM := 0.6            # slow from this long before the kill
const SLOW_TO := 0.3              # to this long after it,
const SLOW_SPEED := 0.3
const FINAL_AFTER := 0.8          # then the rest a little slow
const TAIL_SPEED := 0.6
const FADE_S := 0.4
const TITLE_S := 1.6              # "NAME WINS THE MATCH" over the first moments
const PUNCH := 0.25               # a kill's punch-in (the camera's zoom, on top of 1)
const PUNCH_UP_S := 0.1
const PUNCH_DOWN_S := 0.6
const FINAL_ZOOM := 1.5           # the last kill: held this close
const POP_S := 0.7                # the KILL! pop
const SKIP_RECT := Rect2(1620, 958, 240, 76)   # the SKIP button, in the arena's 1920 x 1080

var recording := true
var clock := 0.0
var rec_acc := 0.0
var buf: Array = []               # the last KEEP_S and a little: {t, view, evs}
var pending: Array = []           # events since the last recorded frame
var open: Array = []              # clips still recording what follows their kill
var clips := {}                   # killer seat -> [clip], oldest first; clip: {killer, victim, frames, kill_i, open_s}

var playing := false
var winner := -1
var names: Array = []
var segs: Array = []              # {clip, from, to, speed, slow, n, of}
var seg_i := 0
var pos := 0.0                    # the clip's time shown (its frames' own times: a slow phone records fewer)
var shown := -1                   # the frame shown: the last one at or before pos (its events went to the effects)
var ending := -1.0                # the fade's time left, once the last segment is done
var flash := 0.0
var t_play := 0.0
var track_y := 0.0
var punch := 9.0                  # seconds since the last kill (the pop and the punch-in)
var pop_at := Vector2(960, 540)   # where it happened
var zoom := 1.0                   # the arena camera's zoom while the montage plays (the page sets it)
var focus := Vector2(960, 540)    # and where it looks, kept inside the arena
var win := Vector2(1920, 1080)
var can_skip := false             # a seated player (the page sets it): the SKIP button shows
var skip_sent := false
var gfx := _Gfx.new()

class _Gfx extends Control:
	var owner_layer
	func _draw() -> void:
		if owner_layer != null:
			owner_layer._paint(self)

func _init() -> void:
	layer = 18                    # over the HUD (10) and the sticks (15), under the lobby (20)
	gfx.owner_layer = self
	gfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(gfx)

func fit(w: Vector2) -> void:
	win = w
	gfx.size = w
	gfx.queue_redraw()

# ------------------------------------------------------------------ recording
# Each frame the page draws: the view the arena renders and the events it got.
func record(view: Dictionary, evs: Array, delta: float) -> void:
	if not recording or view.is_empty():
		return
	clock += delta
	pending.append_array(evs)
	for e in evs:
		if e[0] == P.E_KILL and e[3] < 8 and e[3] != e[4]:
			var c := {"killer": int(e[3]), "victim": int(e[4]), "frames": buf.duplicate(), "kill_i": buf.size(), "open_s": AFTER_S,
				"at": Vector2(e[1], e[2])}
			open.append(c)
			var list: Array = clips.get(int(e[3]), [])
			list.append(c)
			if list.size() > MAX_PER_KILLER:
				list.pop_front()
			clips[int(e[3])] = list
	rec_acc += delta
	if rec_acc < 1.0 / REC_HZ:
		return
	rec_acc = fmod(rec_acc, 1.0 / REC_HZ)
	var fr := {"t": clock, "view": _copy(view), "evs": pending}
	pending = []
	buf.append(fr)
	while buf.size() > int((KEEP_S + 0.5) * REC_HZ):
		buf.pop_front()
	var still: Array = []
	for c in open:
		c["frames"].append(fr)
		c["open_s"] -= 1.0 / REC_HZ
		if c["open_s"] > 0.0:
			still.append(c)
	open = still

# A new match: the old clips go.
func clear() -> void:
	clips = {}
	open = []

static func _copy(v: Dictionary) -> Dictionary:
	var fl: Array = []
	for f in v.get("fighters", []):
		fl.append(f.duplicate())
	var al := {}
	var src: Dictionary = v.get("arrows", {})
	for id in src:
		al[id] = src[id].duplicate()
	var zl: Array = []
	for z in v.get("zones", []):
		zl.append(z.duplicate())
	return {"fighters": fl, "arrows": al, "zones": zl, "arena": v.get("arena", 0), "walls": v.get("walls", 0.0),
		"walls_deadly": v.get("walls_deadly", false)}

# ------------------------------------------------------------------ the montage
# True when the winner has a kill to show.
func start(seat: int, seat_names: Array) -> bool:
	var list: Array = clips.get(seat, [])
	if list.is_empty():
		return false
	winner = seat
	names = seat_names
	var fin: Dictionary = list[list.size() - 1]
	var early: Array = list.slice(maxi(0, list.size() - 1 - EARLY), list.size() - 1)
	var of := early.size() + 1
	segs = []
	for k in early.size():
		var c: Dictionary = early[k]
		var speed := SPEED_ONE if early.size() == 1 else lerpf(SPEED_FIRST, SPEED_LAST, float(k) / float(early.size() - 1))
		segs.append(_seg(c, -EARLY_BEFORE, EARLY_AFTER, speed, false, k + 1, of))
	segs.append(_seg(fin, -FINAL_BEFORE, -SLOW_FROM, 1.0, false, of, of))
	segs.append(_seg(fin, -SLOW_FROM, SLOW_TO, SLOW_SPEED, true, of, of))
	segs.append(_seg(fin, SLOW_TO, FINAL_AFTER, TAIL_SPEED, false, of, of))
	seg_i = 0
	pos = segs[0]["from"]
	shown = _frame_at(segs[0]["clip"], pos) - 1
	ending = -1.0
	flash = 0.0
	t_play = 0.0
	punch = 9.0
	zoom = 1.0
	focus = Vector2(960, 540)
	skip_sent = false
	playing = true
	recording = false
	print("🎬 [Deathcam] the match's montage: seat %d, %d kills (%d earlier, then the last in slow motion)" % [seat, of, early.size()])
	return true

# A part of a clip, in the clip's own time around its kill.
func _seg(c: Dictionary, from_s: float, to_s: float, speed: float, slow: bool, n: int, of: int) -> Dictionary:
	var fr: Array = c["frames"]
	var k := _kill_t(c)
	return {"clip": c, "from": clampf(k + from_s, fr[0]["t"], fr[fr.size() - 1]["t"]),
		"to": clampf(k + to_s, fr[0]["t"], fr[fr.size() - 1]["t"]), "speed": speed, "slow": slow, "n": n, "of": of}

static func _kill_t(c: Dictionary) -> float:
	var fr: Array = c["frames"]
	return fr[mini(int(c["kill_i"]), fr.size() - 1)]["t"]

# The last frame at or before the time t (0 if none).
static func _frame_at(c: Dictionary, t: float) -> int:
	var fr: Array = c["frames"]
	var i := 0
	while i + 1 < fr.size() and fr[i + 1]["t"] <= t:
		i += 1
	return i

func stop() -> void:
	if playing:
		print("🎬 [Deathcam] done")
	playing = false
	recording = true
	zoom = 1.0
	focus = Vector2(960, 540)
	gfx.queue_redraw()

# One frame of the montage: [the view to draw, the events of the frames passed].
func step(delta: float) -> Array:
	if not playing:
		return [{}, []]
	t_play += delta
	punch += delta
	track_y = fmod(track_y + delta * 720.0, 1150.0)
	flash = maxf(0.0, flash - delta * 2.2)
	var sg: Dictionary = segs[seg_i]
	var c: Dictionary = sg["clip"]
	var evs: Array = []
	if ending >= 0.0:
		ending -= delta
		if ending <= 0.0:
			stop()
			return [{}, []]
	else:
		pos = minf(pos + delta * float(sg["speed"]), float(sg["to"]))
		var fr: Array = c["frames"]
		while shown + 1 < fr.size() and fr[shown + 1]["t"] <= pos:
			shown += 1
			evs.append_array(fr[shown]["evs"])
			if shown == int(c["kill_i"]):
				flash = 1.0 if sg["slow"] else 0.45
				punch = 0.0
				pop_at = c["at"]
		if pos >= float(sg["to"]):
			if seg_i + 1 >= segs.size():
				ending = FADE_S
			else:
				seg_i += 1
				var nx: Dictionary = segs[seg_i]
				if nx["clip"] != c:
					c = nx["clip"]
					pos = float(nx["from"])
					shown = _frame_at(c, pos) - 1
	_aim_camera(delta)
	gfx.queue_redraw()
	return [c["frames"][clampi(shown, 0, c["frames"].size() - 1)]["view"], evs]

# The camera: a quick punch-in toward each kill that eases back; on the last kill
# (its slow part and after) a slow push-in that holds. Kept inside the arena.
func _aim_camera(delta: float) -> void:
	var sg: Dictionary = segs[seg_i]
	var on_last: bool = int(sg["n"]) == int(sg["of"]) and (sg["slow"] or seg_i == segs.size() - 1)
	var zt := 1.0
	var ft := Vector2(960, 540)
	var rate := 14.0
	if on_last:
		zt = FINAL_ZOOM
		ft = sg["clip"]["at"]
		rate = 3.0
	elif punch < PUNCH_UP_S + PUNCH_DOWN_S:
		var k := clampf(punch / PUNCH_UP_S, 0.0, 1.0)
		if punch > PUNCH_UP_S:
			var d := clampf((punch - PUNCH_UP_S) / PUNCH_DOWN_S, 0.0, 1.0)
			k = 1.0 - d * d * (3.0 - 2.0 * d)
		zt = 1.0 + PUNCH * k
		ft = pop_at
	var a := minf(1.0, delta * rate)
	zoom = lerpf(zoom, zt, a)
	focus = focus.lerp(ft, a)
	var half := Vector2(960.0, 540.0) / zoom
	focus = Vector2(clampf(focus.x, half.x, 1920.0 - half.x), clampf(focus.y, half.y, 1080.0 - half.y))

func _input(event: InputEvent) -> void:
	if not playing or not can_skip or skip_sent:
		return
	var hit := false
	if (event is InputEventScreenTouch or event is InputEventMouseButton) and event.pressed:
		hit = _skip_rect().has_point(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		hit = event.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]
	if hit:
		get_viewport().set_input_as_handled()
		skip_sent = true
		print("🎬 [Deathcam] SKIP pressed: back to the lobby for everyone")
		skip_pressed.emit()
		gfx.queue_redraw()

# The SKIP button in window pixels (the arena is scaled by height and centred).
func _skip_rect() -> Rect2:
	var sc := minf(win.x / 1920.0, win.y / 1080.0)
	var off := (win - Vector2(1920.0, 1080.0) * sc) / 2.0
	return Rect2(off + SKIP_RECT.position * sc, SKIP_RECT.size * sc)

# ------------------------------------------------------------------ the VHS look
func _paint(n: Control) -> void:
	if not playing:
		return
	var sc := minf(win.x / 1920.0, win.y / 1080.0)
	var size := Vector2(1920.0, 1080.0) * sc
	var off := (win - size) / 2.0
	var r := Rect2(off, size)
	var font: Font = ThemeDB.fallback_font
	var sg: Dictionary = segs[seg_i]
	var c: Dictionary = sg["clip"]
	n.draw_rect(r, Color(0.72, 0.78, 1.0, 0.07), true)
	var y := off.y + 0.5
	while y < off.y + size.y:
		n.draw_line(Vector2(off.x, y), Vector2(off.x + size.x, y), Color(0.0, 0.0, 0.0, 0.18), 1.0)
		y += 3.0
	var ty := off.y + (track_y - 40.0) * sc
	n.draw_rect(Rect2(off.x, ty, size.x, 18.0 * sc), Color(1.0, 1.0, 1.0, 0.05), true)
	n.draw_line(Vector2(off.x, ty + 9.0 * sc), Vector2(off.x + size.x, ty + 9.0 * sc), Color(1.0, 1.0, 1.0, 0.12), 2.0 * sc)
	var seed := int(t_play * 24.0)
	for i in 6:   # tape specks
		var h := hash(seed * 7 + i)
		var px := off.x + float(h % 1920) * sc
		var py := off.y + float((h / 1920) % 1080) * sc
		n.draw_rect(Rect2(px, py, (6 + h % 18) * sc, 1.5 * sc), Color(1, 1, 1, 0.25), true)
	# the mark and the word, the speed, and the counter to the kill: bottom left
	var row := off.y + size.y - 34.0 * sc
	var white := Color(1, 1, 1)
	var x := off.x + 34.0 * sc
	var ih := 26.0 * sc
	var iw := 22.0 * sc
	var tri := PackedVector2Array([Vector2(x, row - ih), Vector2(x + iw, row - ih / 2.0), Vector2(x, row)])
	n.draw_colored_polygon(tri, white)
	var word := "SLOW" if sg["slow"] else "PLAY"
	if not sg["slow"] and float(sg["speed"]) > 1.05:
		word = "PLAY x%.1f" % float(sg["speed"])
	_text(n, font, Vector2(x + iw + 10.0 * sc, row), word, int(34 * sc), white)
	var secs := pos - _kill_t(c)
	_text(n, font, Vector2(x + 300.0 * sc, row), ("+%.1fs" if secs >= 0.0 else "%.1fs") % secs, int(28 * sc), Color(0.9, 0.9, 0.9))
	# REPLAY with its blinking dot: top left; the kill count: top right
	var top := off.y + 58.0 * sc
	if fmod(t_play, 1.0) < 0.5:
		n.draw_circle(Vector2(off.x + 46.0 * sc, top - 11.0 * sc), 10.0 * sc, Color(1.0, 0.2, 0.2))
	_text(n, font, Vector2(off.x + 66.0 * sc, top), "REPLAY", int(34 * sc), white)
	var count := "KILL %d OF %d" % [int(sg["n"]), int(sg["of"])]
	var cw := font.get_string_size(count, HORIZONTAL_ALIGNMENT_LEFT, -1, int(34 * sc)).x
	_text(n, font, Vector2(off.x + size.x - 150.0 * sc - cw, top), count, int(34 * sc), white)   # clear of the page's full-screen button
	if can_skip:
		var br := _skip_rect()
		n.draw_rect(br, Color(0.05, 0.06, 0.1, 0.7), true)
		n.draw_rect(br, Color(1, 1, 1, 0.35 if skip_sent else 0.85), false, 3.0 * sc)
		var label := "SKIPPING" if skip_sent else "SKIP"
		var ls := int(36 * sc)
		var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, ls).x
		var bx := br.position.x + (br.size.x - lw - (0.0 if skip_sent else 40.0 * sc)) / 2.0
		var by := br.position.y + br.size.y / 2.0 + 13.0 * sc
		_text(n, font, Vector2(bx, by), label, ls, Color(1, 1, 1, 0.5 if skip_sent else 1.0))
		if not skip_sent:   # two small triangles: fast forward
			var ax := bx + lw + 10.0 * sc
			var h := 13.0 * sc
			for j in 2:
				var x0 := ax + j * 15.0 * sc
				n.draw_colored_polygon(PackedVector2Array([Vector2(x0, by - 2.0 * h + 4.0 * sc), Vector2(x0 + 14.0 * sc, by - h + 4.0 * sc), Vector2(x0, by + 4.0 * sc)]), white)
	# the caption: who and whom, and MATCH POINT on the last kill
	var wn := _name(winner)
	var col: Color = World.TEAM[winner % 8].lightened(0.25)
	var last: bool = int(sg["n"]) == int(sg["of"])
	if last:
		_center(n, font, off.y + size.y - 120.0 * sc, off.x, size.x, "MATCH POINT", int(64 * sc), Color(1.0, 0.85, 0.3))
	_center(n, font, off.y + size.y - 70.0 * sc, off.x, size.x, "%s got %s" % [wn, _name(int(c["victim"]))], int(36 * sc), col)
	# the pop: KILL! (FINAL KILL on the last) at the kill, big then settling, fading
	if punch < POP_S:
		var k := punch / POP_S
		var at := off + ((pop_at - focus) * zoom + Vector2(960.0, 540.0)) * sc
		var word2 := "FINAL KILL" if last else "KILL!"
		var size2 := int((96.0 - 30.0 * k) * sc * (1.3 if last else 1.0))
		var sw := font.get_string_size(word2, HORIZONTAL_ALIGNMENT_LEFT, -1, size2).x
		_text(n, font, at + Vector2(-sw / 2.0, -90.0 * sc - 40.0 * k * sc), word2, size2, Color(1.0, 0.86, 0.3, 1.0 - k * k))
	if t_play < TITLE_S:
		var a := clampf((TITLE_S - t_play) / 0.4, 0.0, 1.0)
		_center(n, font, off.y + 200.0 * sc, off.x, size.x, "%s WINS THE MATCH" % wn.to_upper(), int(80 * sc), Color(col, a))
	if flash > 0.0:
		n.draw_rect(r, Color(1, 1, 1, flash * 0.7), true)
	if ending >= 0.0:
		n.draw_rect(r, Color(0, 0, 0, clampf(1.0 - ending / FADE_S, 0.0, 1.0)), true)

func _name(seat: int) -> String:
	return str(names[seat]) if seat >= 0 and seat < names.size() and str(names[seat]) != "" else "Player %d" % (seat + 1)

func _center(n: Control, font: Font, y: float, x0: float, w: float, s: String, size: int, col: Color) -> void:
	var sw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	_text(n, font, Vector2(x0 + (w - sw) / 2.0, y), s, size, col)

func _text(n: Control, font: Font, at: Vector2, s: String, size: int, col: Color) -> void:
	n.draw_string_outline(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, maxi(3, size / 9), Color(0, 0, 0, 0.9 * col.a))
	n.draw_string(font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

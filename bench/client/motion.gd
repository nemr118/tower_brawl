# p4.21 MOTION (the user, 2026-11-25: "Add animation to menus, character select, etc.").
# The lobby's parts already rose in and its fighters breathed. But every panel (SETTINGS,
# the match's MENU, TONIGHT'S CHAMPIONS, WHO ARE YOU?, PICK AN ARENA, HOW TO PLAY) came and
# went in one frame, and a button only changed its shade when pressed. This is the shared
# part of polish "motion": a panel that grows in with a soft bounce and shrinks away, and
# the timing its rows use to come in one after another.
# The rule that keeps a phone's memory flat: only sizes, places and see-through change
# (transforms and modulate). No new text size (each is its own sheet of letters), and no
# box in a new shade (lobby_art.gd keeps every box it makes).
extends RefCounted

const Art = preload("res://client/lobby_art.gd")
const Polish = preload("res://client/polish.gd")
const IN_S := 0.26       # a panel grows in this long
const OUT_S := 0.13      # and shrinks away this long

static func on() -> bool:
	return Polish.on("motion")

# How far in a part is, 0..1 and a little past 1 on the way (a soft bounce): it starts
# `wait` seconds after its panel opened and takes `dur` seconds. Motion off: 1 at once.
static func rise(t: float, wait: float, dur: float = 0.3) -> float:
	return Art.ease_out_back((t - wait) / dur) if on() else 1.0

# The same without the bounce (for see-through and for counting numbers up).
static func ramp(t: float, wait: float, dur: float = 0.15) -> float:
	return clampf((t - wait) / dur, 0.0, 1.0) if on() else 1.0

# A panel's coming and going. The host is the panel's own Control (it draws the dark
# layer and the card, on the lobby's 1920 x 1080 frame); it calls open() and close() in
# place of setting `visible`, and step() every frame while it shows.
class Pane extends RefCounted:
	var host: Control
	var pivot := Vector2(960, 540)   # it grows from here (its card's middle)
	var from := 0.9                  # its size when it starts to grow
	var t := 0.0                     # seconds since it opened
	var out := -1.0                  # seconds since it began to close (under 0: it is not closing)
	var live := false                # is the polish on? (read at each open)

	func _init(h: Control, piv: Vector2 = Vector2(960, 540), from_size: float = 0.9) -> void:
		host = h
		pivot = piv
		from = from_size

	func open() -> void:
		live = Polish.on("motion")
		t = 0.0
		out = -1.0
		host.visible = true
		_apply()
		host.queue_redraw()

	# With the polish on it shrinks away first; it is gone OUT_S later.
	func close() -> void:
		if not host.visible:
			return
		if not live:
			host.visible = false
		elif out < 0.0:
			out = 0.0

	func closing() -> bool:
		return out >= 0.0

	# Every frame while the host shows. True while something still moves (draw again).
	func step(delta: float) -> bool:
		t += delta
		if out >= 0.0:
			out += delta
			if out >= OUT_S:
				out = -1.0
				host.visible = false
				host.scale = Vector2.ONE
				host.modulate.a = 1.0
				return false
		_apply()
		return live and (t < 1.0 or out >= 0.0)

	func _apply() -> void:
		if not live:
			return
		var k := Art.ease_out_back(t / IN_S)
		var a := clampf(t / 0.12, 0.0, 1.0)
		if out >= 0.0:
			var o := clampf(out / OUT_S, 0.0, 1.0)
			k = 1.0 - 0.7 * o * o
			a = minf(a, 1.0 - o)
		host.pivot_offset = pivot
		host.scale = Vector2.ONE * lerpf(from, 1.0, k)
		host.modulate.a = a

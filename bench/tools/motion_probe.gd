# p4.21 polish "motion" (client/motion.gd), headless: the menus' coming and going.
# Nothing is drawn here (a headless run has no picture); this checks the moving parts end
# where they should, so a panel can never be left half open, a button never left squeezed,
# and that with the polish off everything is as it was before:
#   1. each panel (SETTINGS, the match's MENU, TONIGHT'S CHAMPIONS, WHO ARE YOU?,
#      PICK AN ARENA, HOW TO PLAY) starts small and see-through, ends at its full size,
#      and after close() it is gone within a quarter second, back at its full size;
#   2. SETTINGS' buttons end in their own places, and the choice just picked jumps;
#   3. a button squeezes while held, ends at its own size, and then stops running;
#   4. the seat cards: a card dips when its person leaves, a flag drops in when TEAMS
#      comes on (one after another), a change of sides pops the card, a tap hops;
#   5. with the polish off: a panel opens and closes in one step and nothing else moves.
# Exit 1 on a failed check.
#   godot --headless --path bench --script res://tools/motion_probe.gd
extends SceneTree

const Polish = preload("res://client/polish.gd")
const Motion = preload("res://client/motion.gd")
const Art = preload("res://client/lobby_art.gd")
const Settings = preload("res://client/lobby_settings.gd")
const Champs = preload("res://client/lobby_champs.gd")
const Names = preload("res://client/lobby_names.gd")
const Arenas = preload("res://client/lobby_arenas.gd")
const Howto = preload("res://client/lobby_howto.gd")
const Cards = preload("res://client/lobby_cards.gd")
const Teams = preload("res://client/teams_view.gd")
const P = preload("res://sim/proto.gd")
const DT := 1.0 / 60.0

var fails := 0
var checks := 0

func _check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("🧪 [MotionProbe] PASS " + what)
	else:
		fails += 1
		print("🧪 [MotionProbe] FAIL " + what)

func _run(node: Node, secs: float) -> void:
	var n := int(ceil(secs / DT))
	for i in n:
		node._process(DT)

func _open(name: String, node) -> void:
	match name:
		"TONIGHT'S CHAMPIONS":
			node.open([["Tav", 2, 5, 9, false], ["GRAVY", 1, 3, 4, true]])
		"WHO ARE YOU?":
			node.open(["Tav", "Dad", "Grandma"], ["Dad"])
		"PICK AN ARENA":
			node.open(P.ARENA_MIX)
		"HOW TO PLAY":
			node.open("classic")
		_:
			node.open()

func _panels(live: bool) -> void:
	var menu = Settings.new()
	menu.in_match = true
	var list := [["SETTINGS", Settings.new()], ["MENU", menu], ["TONIGHT'S CHAMPIONS", Champs.new()], ["WHO ARE YOU?", Names.new()],
		["PICK AN ARENA", Arenas.new()], ["HOW TO PLAY", Howto.new()]]
	for pair in list:
		var name: String = pair[0]
		var node = pair[1]
		root.add_child(node)
		_open(name, node)
		if live:
			_check(node.visible and node.scale.x < 0.97 and node.modulate.a < 0.2,
				"%s opens small and see-through (size %.2f, shown %.2f)" % [name, node.scale.x, node.modulate.a])
			var biggest := 0.0
			for i in 40:
				node._process(DT)
				biggest = maxf(biggest, node.scale.x)
			_check(absf(node.scale.x - 1.0) < 0.002 and is_equal_approx(node.modulate.a, 1.0) and biggest < 1.04,
				"%s is at its full size 0.67 s later (size %.3f, shown %.2f; never over %.3f on the way)" % [name, node.scale.x, node.modulate.a, biggest])
			if name == "SETTINGS" or name == "MENU":
				var off := 0.0
				var faint := 1.0
				for r in node.rows:
					for b in r["btns"]:
						if b.visible:
							off = maxf(off, absf(b.position.x - float(b.get_meta("x0"))))
							faint = minf(faint, b.modulate.a)
				_check(off < 0.5 and faint > 0.99 and absf(node.done.position.y - node.done_y) < 0.5 and node.done.modulate.a > 0.99,
					"%s: every button is in its own place and solid (the farthest %.2f px off)" % [name, off])
			node.close()
			_check(node.visible and node.pane.closing(), "%s: close() starts it shrinking (still there for a moment)" % name)
			var gone_at := -1.0
			for i in 30:
				node._process(DT)
				if not node.visible and gone_at < 0.0:
					gone_at = (i + 1) * DT
			_check(not node.visible and gone_at > 0.0 and gone_at <= 0.25 and is_equal_approx(node.scale.x, 1.0) and is_equal_approx(node.modulate.a, 1.0),
				"%s is gone %.2f s after close(), back at its full size" % [name, gone_at])
			_open(name, node)          # open, close at once, open again: it must not stay half way
			node._process(DT)
			node.close()
			_open(name, node)
			_run(node, 0.7)
			_check(node.visible and absf(node.scale.x - 1.0) < 0.002 and is_equal_approx(node.modulate.a, 1.0) and not node.pane.closing(),
				"%s: opened again while it closed: fully open" % name)
		else:
			_check(node.visible and is_equal_approx(node.scale.x, 1.0) and is_equal_approx(node.modulate.a, 1.0),
				"polish off: %s is open at once, at its full size" % name)
			_run(node, 0.4)
			node.close()
			_check(not node.visible, "polish off: %s is gone at once" % name)
		node.queue_free()

func _settings_pick() -> void:
	var s = Settings.new()
	root.add_child(s)
	s.set_sound(false, true)
	s.open()
	_run(s, 0.8)
	var row: Dictionary = s._row_of("sound")
	var on_btn = row["btns"][1]
	s.set_sound(true, true)             # the lobby says: SOUND is on now
	var grew := 0.0
	for i in 30:
		on_btn._process(DT)
		grew = maxf(grew, on_btn.scale.x)
	_check(grew > 1.04 and is_equal_approx(on_btn.scale.x, 1.0) and not on_btn.is_processing(),
		"SETTINGS: the choice just picked jumps (to %.2f) and settles at 1, then rests" % grew)
	s.queue_free()

func _button(live: bool) -> void:
	var b = Art.Btn.new()
	b.setup(Color(0.4, 0.2, 0.1), Color.WHITE, 40)
	b.size = Vector2(300, 90)
	root.add_child(b)
	b.say("", "START")
	b.toggle_mode = true                 # (the probe's way to hold a button down with no finger)
	b.set_pressed_no_signal(true)
	b.button_down.emit()
	var smallest := 1.0
	for i in 12:
		b._process(DT)
		smallest = minf(smallest, b.scale.x)
	if not live:
		_check(is_equal_approx(smallest, 1.0), "polish off: a held button keeps its size")
		b.set_pressed_no_signal(false)
		b.button_up.emit()
		b.queue_free()
		return
	_check(smallest < 0.96 and smallest > 0.93, "a held button squeezes to %.2f of its size" % smallest)
	b.set_pressed_no_signal(false)
	b.button_up.emit()
	var biggest := 0.0
	for i in 40:
		b._process(DT)
		biggest = maxf(biggest, b.scale.x)
	_check(biggest > 1.01 and biggest < 1.06 and is_equal_approx(b.scale.x, 1.0) and not b.is_processing(),
		"let go: it springs to %.3f, ends at its own size and stops running" % biggest)
	b.say("", "GET READY")       # its words change while it shows
	_check(b._bump < 0.01 and b.is_processing(), "changed words bump (the button runs again)")
	_run(b, 0.6)
	_check(not b.is_processing() and is_equal_approx(b.scale.x, 1.0), "and it rests again 0.6 s later")
	# held, then switched off under the finger: no "up" ever comes, and it must not stay squeezed
	b.set_pressed_no_signal(true)
	b.button_down.emit()
	_run(b, 0.2)
	b.set_pressed_no_signal(false)
	_run(b, 0.6)
	_check(is_equal_approx(b.scale.x, 1.0) and not b.is_processing(), "held, then let go with no \"up\" signal: it is not left squeezed")
	b.pulse = 1.02               # the lobby's own breathing (START) goes into the size
	b.apply_size()
	_check(is_equal_approx(b.scale.x, 1.02), "the lobby's pulse is the button's size when nothing else moves")
	b.queue_free()

func _seats(kinds: Array, teams: Array) -> Array:
	var list: Array = []
	for i in 8:
		list.append({"kind": kinds[i], "name": "P%d" % i if kinds[i] == 1 else "", "on": true, "in": true, "team": teams[i]})
	Teams.seat_team.clear()
	for i in 8:
		Teams.seat_team.append(teams[i] if Teams.on else -1)
	return list

func _cards(live: bool) -> void:
	var c = Cards.new()
	c.set_dress(Art.DRESSES["harvest"], false)
	root.add_child(c)
	c.intro = 3.0
	Teams.on = false
	var none := [-1, -1, -1, -1, -1, -1, -1, -1]
	c.set_seats(_seats([1, 1, 0, 0, 0, 0, 0, 0], none), 0, P.PH_LOBBY, 2, [])
	_run(c, 1.0)
	c.set_seats(_seats([1, 0, 0, 0, 0, 0, 0, 0], none), 0, P.PH_LOBBY, 2, [])      # seat 2's person leaves (a bot's seat now)
	if live:
		_check(float(c.cards[1]["dip"]) < 0.01, "a card dips when its person leaves")
		_run(c, 0.16)
		_check(float(c._xf(1)[1]) < 0.95, "(it is %.2f of its size at the dip's middle)" % float(c._xf(1)[1]))
	else:
		_check(float(c.cards[1]["dip"]) > 1.0, "polish off: a card does not dip when its person leaves")
	_run(c, 1.0)
	_check(is_equal_approx(float(c._xf(1)[1]), 1.0), "and it is back at its own size a second later")
	# TEAMS comes on: the flags drop in one after another
	Teams.on = true
	var tm := [0, 1, 0, 1, -1, -1, -1, -1]
	c.set_seats(_seats([1, 0, 0, 0, 0, 0, 0, 0], tm), 0, P.PH_LOBBY, 3, [])
	if live:
		_check(float(c.cards[0]["flag_t"]) == 0.0 and float(c.cards[3]["flag_t"]) < float(c.cards[1]["flag_t"]) and float(c.cards[1]["flag_t"]) < 0.0,
			"TEAMS comes on: the flags drop in one after another (seat 1 now, seat 4 %.2f s later)" % -float(c.cards[3]["flag_t"]))
	else:
		_check(float(c.cards[0]["flag_t"]) > 1.0, "polish off: the flags are there at once")
	_run(c, 1.0)
	# your own side changes
	tm[0] = 1
	c.set_seats(_seats([1, 0, 0, 0, 0, 0, 0, 0], tm), 0, P.PH_LOBBY, 3, [])
	if live:
		_check(float(c.cards[0]["flag_t"]) == 0.0 and float(c.cards[0]["pop"]) == 0.0 and float(c.cards[0]["hop"]) == 0.0 and not c.cards[0]["sparks"].is_empty(),
			"a change of sides: a new flag drops in, the card pops, the fighter hops, sparks fly")
	else:
		_check(float(c.cards[0]["pop"]) > 0.5, "polish off: a change of sides moves nothing")
	_run(c, 1.2)
	c.fidget()
	_check(float(c.cards[0]["hop"]) == 0.0, "a tap on your own card: your fighter hops")
	_run(c, 1.0)
	var fine := true
	for i in 8:
		var xf: Array = c._xf(i)
		fine = fine and is_finite(xf[0].x) and is_finite(xf[0].y) and float(xf[1]) > 0.5 and float(xf[1]) < 1.3
	_check(fine, "every card's place and size is sane after all of it")
	Teams.on = false
	Teams.seat_team.clear()
	c.queue_free()

# (After the first frame: only then are the nodes this adds "in the tree", which a button's
# bump and a card's dip ask before they move.)
func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	await process_frame
	Art.fonts_ready()
	_check(root.is_inside_tree(), "(the probe's own set-up: the scene is live)")
	Polish._read = true
	_check(Polish.on("motion") and Motion.on(), "the polish switch \"motion\" is on")
	_panels(true)
	_settings_pick()
	_button(true)
	_cards(true)
	Polish._off["motion"] = true      # as ?polish_off=motion on the page
	_check(not Motion.on() and is_equal_approx(Motion.rise(0.0, 0.5), 1.0), "polish off: nothing rises (every part is in place at once)")
	_panels(false)
	_button(false)
	_cards(false)
	Polish._off.erase("motion")
	if fails == 0:
		print("✅ motion_probe: %d of %d checks passed" % [checks, checks])
	else:
		print("✗ motion_probe: %d of %d checks FAILED" % [fails, checks])
	quit(1 if fails > 0 else 0)

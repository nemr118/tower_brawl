extends PanelContainer
# Harness ticker (v0.0.23).
#
# The story: while tools/chaos_bots.py runs its tests, the server keeps every
# seat for the bots. A person who opens the game in that time only watches.
# This little panel tells them why. It shows three things: that tests are
# running, the name of the scenario, and how many tests are done out of the
# total ("Tests done: 5 / 19").
#
# The lobby (character_select.gd) makes one in the top-left corner, where the
# JOIN MATCH button normally sits. The arena (arena.gd) makes a one-line one
# under the top bar on the right, so it never covers the fighters.
#
# It listens to Global.net_harness_status and hides itself when the run is
# over. No polling (CLAUDE.md rule 3): the server sends a harness_status
# packet only when the numbers change.

var compact: bool = false          # true = one line (arena), false = three lines (lobby)
var _label: Label = null

func _init(p_compact: bool = false) -> void:
	compact = p_compact

func _ready() -> void:
	name = "HarnessTicker"
	z_index = 150
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.08, 0.08, 0.10, 0.85)
	box.border_color = Color(1.0, 0.75, 0.2, 0.9)
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	add_theme_stylebox_override("panel", box)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 11 if compact else 12)
	_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	Global.net_harness_status.connect(_on_harness_status)
	_on_harness_status(Global.harness_info)

func _exit_tree() -> void:
	if Global.net_harness_status.is_connected(_on_harness_status):
		Global.net_harness_status.disconnect(_on_harness_status)

func _on_harness_status(info: Dictionary) -> void:
	visible = bool(info.get("active", false))
	if visible:
		_label.text = text_for(info, compact)

static func text_for(info: Dictionary, one_line: bool) -> String:
	# The words on the panel, built from the harness_status packet.
	var state := str(info.get("state", ""))
	var scenario := ""
	if info.get("scenario") != null:
		scenario = str(info.get("scenario"))
	var what := scenario
	if what == "":
		what = "restarting the server" if state == "restarting" else "getting ready"
	var count := "Tests done: %d / %d" % [int(info.get("done", 0)), int(info.get("total", 0))]
	var failed := int(info.get("failed", 0))
	if failed > 0:
		count += " (%d failed)" % failed
	if one_line:
		return "TEST LOCK  |  " + what + "  |  " + count
	return "TESTS RUNNING - JOIN IS LOCKED\nScenario: " + what + "\n" + count

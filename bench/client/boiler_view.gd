# THE BOILER ROOM's look (theme "nightmare"): its backdrop, its moving parts and its
# hazards' warnings and blasts, drawn from the snapshot's hazard state (sim/boiler.gd).
# world.gd makes one, calls setup once, set_theme on each arena, show_view each frame
# and on_event for each event. (A stub until the arena is built.)
extends Node2D

var world

func setup(w) -> void:
	world = w
	visible = false

func set_theme(level) -> void:
	visible = level.theme == "nightmare"

func show_view(_s: Dictionary, _delta: float) -> void:
	pass

func on_event(_e: Array) -> void:
	pass

# Times each part of a simulation tick (fighters, bot brains, arrows, pickups, zones,
# snapshot) at 8, 16 and 32 fighters, with no network. Shows what could run on other cores.
#   godot --headless --path bench --script res://tools/sim_prof.gd
extends SceneTree

class Prof extends "res://sim/sim.gd":
	var brain_us := 0
	func _brain(f: Fighter) -> void:
		var t := Time.get_ticks_usec()
		super._brain(f)
		brain_us += Time.get_ticks_usec() - t

func _run(n: int, cap: int) -> void:
	var s := Prof.new(n, cap, 7)
	var buf := StreamPeerBuffer.new()
	var parts := {"fighters": 0, "arrows": 0, "tinks+pickups": 0, "zones+cap": 0, "snapshot": 0}
	var ticks := 3600
	for i in 600 + ticks:
		if i == 600:
			for k in parts: parts[k] = 0
			s.brain_us = 0
		var t0 := Time.get_ticks_usec()
		s.tick += 1
		for f in s.fighters:
			s._update_fighter(f)
		var t1 := Time.get_ticks_usec()
		s._stomps()
		for a in s.arrows:
			s._update_arrow(a)
		var t2 := Time.get_ticks_usec()
		s._tinks()
		s._pickups()
		var t3 := Time.get_ticks_usec()
		s._update_zones()
		s._enforce_cap()
		for j in range(s.arrows.size() - 1, -1, -1):
			if s.arrows[j].dead:
				s.arrows.remove_at(j)
		var t4 := Time.get_ticks_usec()
		if i % 2 == 0:
			buf.clear()
			s.write_snapshot(buf, s.take_events())
		var t5 := Time.get_ticks_usec()
		parts["fighters"] += t1 - t0
		parts["arrows"] += t2 - t1
		parts["tinks+pickups"] += t3 - t2
		parts["zones+cap"] += t4 - t3
		parts["snapshot"] += t5 - t4
	var total := 0
	for k in parts: total += parts[k]
	var line := "%2d fighters: tick %.3f ms |" % [n, total / 1000.0 / ticks]
	line += " brains %.3f (%.0f%%) |" % [s.brain_us / 1000.0 / ticks, 100.0 * s.brain_us / total]
	line += " movement %.3f (%.0f%%) |" % [(parts["fighters"] - s.brain_us) / 1000.0 / ticks, 100.0 * (parts["fighters"] - s.brain_us) / total]
	for k in ["arrows", "tinks+pickups", "zones+cap", "snapshot"]:
		line += " %s %.3f (%.0f%%) |" % [k, parts[k] / 1000.0 / ticks, 100.0 * parts[k] / total]
	print(line)

func _init() -> void:
	_run(8, 24)
	_run(16, 64)
	_run(32, 128)
	quit()

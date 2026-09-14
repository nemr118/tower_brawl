# Runs the stand-in simulation with no network and no drawing, and prints what a
# tick costs and what happened. A check that the load model is alive (bots move,
# shoot, die, pick up) before the server and phones measure it.
#   godot --headless --path bench --script res://tools/sim_probe.gd -- --fighters=8 --cap=24 --ticks=3600
extends SceneTree

const SimScript = preload("res://sim/sim.gd")
const NAMES := {1: "jump", 2: "land", 3: "dodge", 4: "shoot", 5: "stick", 6: "explode", 7: "ignite",
	8: "miasma", 9: "death", 10: "catch", 11: "pickup", 12: "spawn", 13: "walljump", 14: "tink", 15: "hurt", 16: "ledge", 17: "smoke"}

func _init() -> void:
	var n := 8
	var cap := 24
	var ticks := 3600
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--fighters="):
			n = int(a.get_slice("=", 1))
		elif a.begins_with("--cap="):
			cap = int(a.get_slice("=", 1))
		elif a.begins_with("--ticks="):
			ticks = int(a.get_slice("=", 1))
	var sim = SimScript.new(n, cap, 7)
	var times := PackedInt64Array()
	var counts := {}
	var buf := StreamPeerBuffer.new()
	var pending: Array = []
	var bytes_sum := 0
	var bytes_max := 0
	var snaps := 0
	var arrows_sum := 0
	var arrows_max := 0
	var zones_max := 0
	var cells := {}
	for t in ticks:
		var t0 := Time.get_ticks_usec()
		sim.step()
		times.append(Time.get_ticks_usec() - t0)
		var ev: Array = sim.take_events()
		pending.append_array(ev)
		for e in ev:
			counts[e[0]] = counts.get(e[0], 0) + 1
		if t % 2 == 1:
			sim.write_snapshot(buf, pending)
			pending.clear()
			bytes_sum += buf.data_array.size()
			bytes_max = maxi(bytes_max, buf.data_array.size())
			snaps += 1
		var na: int = sim.live_arrow_count()
		arrows_sum += na
		arrows_max = maxi(arrows_max, na)
		zones_max = maxi(zones_max, sim.zones.size())
		if t % 30 == 0:
			for f in sim.fighters:
				cells["%d:%d:%d" % [f.id, f.x / 120, f.y / 120]] = true
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0
	for v in times:
		total += v
	print("🧪 [SimProbe] fighters=%d cap=%d ticks=%d" % [n, cap, ticks])
	print("   tick ms: mean %.3f  p50 %.3f  p99 %.3f  max %.3f" % [total / 1000.0 / ticks,
		sorted[ticks / 2] / 1000.0, sorted[int(ticks * 0.99)] / 1000.0, sorted[ticks - 1] / 1000.0])
	print("   snapshot bytes: mean %.0f  max %d  (%.1f KB/s per client at 30 Hz)" % [float(bytes_sum) / snaps, bytes_max, bytes_sum / float(snaps) * 30.0 / 1000.0])
	print("   arrows alive: mean %.1f  max %d   zones max %d" % [float(arrows_sum) / ticks, arrows_max, zones_max])
	var parts: Array = []
	for k in NAMES:
		parts.append("%s=%d" % [NAMES[k], counts.get(k, 0)])
	print("   events: " + " ".join(parts))
	print("   map cells visited (120 px squares, all fighters): %d" % cells.size())
	quit()

# p4.19 the sounds, headless and silent (nothing is played). Three checks:
#   1. the list of names in client/sfx.gd and the files in assets/sfx/ are the same;
#   2. every file loads, and plays back clean as the engine will decode it: its
#      length, its peak (under 1.0: no clipping), a start and an end at zero (no click);
#   3. every event, phase and message is sent to the player with sound "on" in a
#      test mode that only writes down the names: each name must be a real sound.
#      It prints which sound each event gives, and the sounds no event reaches.
# Exit 1 on a failed check.
#   godot --headless --path bench --script res://tools/sfx_probe.gd
extends SceneTree

const Sfx = preload("res://client/sfx.gd")
const Season = preload("res://client/season.gd")
const P = preload("res://sim/proto.gd")
const DIR := "res://assets/sfx/"

var fails := 0

func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("🧪 [SfxProbe] FAIL: " + what)

func _say(s: String) -> void:
	print("🧪 [SfxProbe] " + s)

func _init() -> void:
	# 1. the names and the files
	var files: Array = []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".wav.import"):
			files.append(f.trim_suffix(".wav.import"))
	for n in Sfx.NAMES:
		_check(files.has(n), "client/sfx.gd names '%s' but %s%s.wav is not there (run tools/make_sfx.py, then godot --import)" % [n, DIR, n])
	for f in files:
		_check(Sfx.NAMES.has(f), "%s%s.wav is not in client/sfx.gd's NAMES" % [DIR, f])
	# 2. each file, as the engine decodes it
	var total_s := 0.0
	var total_b := 0
	for n in Sfx.NAMES:
		if not ResourceLoader.exists(DIR + n + ".wav"):
			continue
		var st = load(DIR + n + ".wav")
		_check(st is AudioStreamWAV, "%s does not load as a sound" % n)
		if not (st is AudioStreamWAV):
			continue
		var secs: float = st.get_length()
		total_s += secs
		total_b += st.data.size()
		_check(secs > 0.02 and secs < 3.2, "%s is %.2f s long" % [n, secs])
		_check(not st.stereo and st.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s should be mono with no loop" % n)
		var pb: AudioStreamPlayback = st.instantiate_playback()
		pb.start(0.0)
		var frames: PackedVector2Array = pb.mix_audio(1.0, int(secs * AudioServer.get_mix_rate()) + 64)
		var peak := 0.0
		for v in frames:
			peak = maxf(peak, maxf(absf(v.x), absf(v.y)))
		var first := absf(frames[0].x) if frames.size() > 0 else 1.0
		var last := 0.0
		for i in range(maxi(0, frames.size() - 64), frames.size()):
			last = maxf(last, absf(frames[i].x))
		_check(peak > 0.05 and peak <= 0.75, "%s peaks at %.3f once decoded (wanted 0.05 to 0.75)" % [n, peak])
		_check(first < 0.02 and last < 0.02, "%s starts at %.3f and ends at %.3f once decoded: a click" % [n, first, last])
		_say("%-16s %.2f s  %6d bytes in the pack (format %d, %d Hz)  decoded peak %.3f  start %.4f  end %.4f" % [
			n, secs, st.data.size(), st.format, st.mix_rate, peak, first, last])
	_say("%d sounds, %.1f s, %d bytes of sound data in the pack" % [Sfx.NAMES.size(), total_s, total_b])
	# 3. every event, phase and message: the names asked for
	var sfx = Sfx.new()
	sfx.on = true
	sfx.trace = []
	var used := {}
	var kinds := {}
	var consts: Dictionary = (P as Script).get_script_constant_map()
	for c in consts:
		if str(c).begins_with("E_"):
			kinds[int(consts[c])] = str(c)
	kinds[Sfx.E_PHEW] = "E_PHEW"
	for season in ["", "halloween", "harvest"]:
		Season.now = season
		var lines := {}
		for type in range(1, 61):
			for a in [0, 1, 3, 255]:
				for b in [0, 1, 2, 3, 4, 7, 8, 9, 12, 17, 255]:
					for me in [0, -1]:
						sfx.trace.clear()
						sfx.on_event([type, 960, 540, a, b], me)
						for n in sfx.trace:
							used[n] = true
							_check(Sfx.NAMES.has(n), "event %d asks for '%s': no such sound" % [type, n])
							if not lines.has(type):
								lines[type] = {}
							lines[type][n] = true
		var parts: Array = []
		for type in lines:
			parts.append("%s: %s" % [kinds.get(type, str(type)), "/".join(lines[type].keys())])
		_say("season '%s': %s" % [season, "; ".join(parts)])
	# the sweep on THE HARVEST BARN is a gust of leaves (the page tells the arena's theme)
	Season.now = "harvest"
	sfx.client = {"world": {"level": {"theme": "barn"}}, "lobby": {"visible": false}}
	sfx.trace.clear()
	sfx.on_event([P.E_BATS, 0, 500, 1, 0], 0)
	_check(sfx.trace == ["gust"], "the barn's sweep should give 'gust': %s" % str(sfx.trace))
	used["gust"] = true
	# someone still in the lobby (it is on their screen) hears no match, only the lobby
	sfx.client["lobby"]["visible"] = true
	sfx.trace.clear()
	sfx.last_phase = P.PH_ROUND_START
	sfx.on_event([P.E_SHOOT, 0, 0, 1, 0], 0)
	sfx.on_phase(P.PH_PLAY, {"left": 0})
	sfx.on_message({"kind": "round_end", "draw": true}, 0)
	sfx.on_message({"kind": "match_end", "winner": 1}, 0)
	_check(sfx.trace.is_empty(), "with the lobby on screen the match should be silent: %s" % str(sfx.trace))
	sfx.last_phase = -1
	sfx.client = null
	Season.now = ""
	sfx.trace.clear()
	var before := Time.get_ticks_msec()
	sfx.on_phase(P.PH_LOBBY, {"left": 0})
	sfx.on_phase(P.PH_COUNTDOWN, {"left": 180})
	_check(sfx.beeps.size() == 3 and int(sfx.beeps[0]) - before < 50 and absi(int(sfx.beeps[2]) - before - 2000) < 50,
		"the countdown should beep now, 1 s on and 2 s on: %s" % str(sfx.beeps))
	sfx.on_phase(P.PH_ROUND_START, {"left": 90})
	_check(sfx.beeps.is_empty(), "the beeps should stop when the countdown is over")
	sfx.on_phase(P.PH_PLAY, {"left": 0})
	_check(sfx.trace == ["fight"], "ROUND START to PLAY should give 'fight': %s" % str(sfx.trace))
	sfx.trace.clear()
	sfx.last_phase = -1
	sfx.on_phase(P.PH_PLAY, {"left": 0})
	_check(sfx.trace.is_empty(), "a page that opens in the middle of a round should not hear FIGHT")
	sfx.on_message({"kind": "seats", "people": 1, "phase": P.PH_LOBBY}, 0)
	_check(sfx.trace.is_empty(), "the first seats message is no join")
	sfx.on_message({"kind": "seats", "people": 2, "phase": P.PH_LOBBY}, 0)
	sfx.on_message({"kind": "round_end", "draw": false, "winner": 0}, 0)
	sfx.on_message({"kind": "round_end", "draw": true}, 0)
	sfx.on_message({"kind": "match_end", "winner": 1}, 0)
	_check(sfx.trace == ["join", "round_win", "draw", "fanfare"], "the messages should give join, round_win, draw, fanfare: %s" % str(sfx.trace))
	sfx.trace.clear()
	sfx.play("taunt", true, 100.0, 3)
	sfx._click()
	sfx._play("count")
	_check(sfx.trace == ["taunt", "click", "count"], "play() by name: %s" % str(sfx.trace))
	for n in sfx.trace + ["join", "round_win", "draw", "fanfare", "fight"]:
		used[n] = true
	var unused: Array = []
	for n in Sfx.NAMES:
		if not used.has(n):
			unused.append(n)
	_say("sounds nothing asks for: %s" % ("none" if unused.is_empty() else ", ".join(unused)))
	# sound off: nothing is asked for, nothing is loaded
	var off = Sfx.new()
	off.on_event([P.E_SHOOT, 0, 0, 0, 0], 0)
	off.on_phase(P.PH_COUNTDOWN, {"left": 180})
	off.on_message({"kind": "match_end"}, 0)
	off.play("ko", true)
	off._click()
	_check(off.players.is_empty() and off.streams.is_empty() and off.beeps.is_empty() and off.last_ms.is_empty() and off.waiting.is_empty(),
		"with sound off nothing should be loaded, kept or timed")
	sfx.free()
	off.free()
	if fails == 0:
		_say("PASS")
	else:
		_say("%d check(s) FAILED" % fails)
	quit(0 if fails == 0 else 1)

# p4.20 MUSIC (the user, 2026-11-24: "ACE-Step songs on the GPU"): a tune for the lobby, a
# tune for the match, and in the Harvest season a short song for the winner ("Winner, winner,
# turkey dinner!"). The songs were made by ACE-Step in ComfyUI (tools/comfy/run_music.py) and
# cut for the game by tools/comfy/make_music.py: bench/assets/music/<name>.wav.
#
# It has its own switch, apart from SOUND (SETTINGS has a MUSIC row), kept on the device, and
# it starts OFF everywhere: nobody had heard the songs when this was written. A test knob on
# the page: ?music=1 or ?music=0. With music off nothing is loaded and nothing runs.
#
# One song plays at a time, quieter than the sound effects. The lobby's and the match's
# start again when they end; the winner's plays once. A change of song fades the old one
# out first. Only the song in use is kept in memory.
# A browser plays nothing before the player's first tap (the shell's window.tbAudio says
# when it may), so a song waits for that.
extends Node

const Season = preload("res://client/season.gd")
const DIR := "res://assets/music/"
const MUSIC_KEY := "towerbrawl_v2_music"   # "1" or "0" once picked on this device
const DB := -9.0             # how loud a song plays (0 = as loud as its file): under the sound effects
const FADE_S := 0.45         # a song fades out this long before the next starts
const ONCE := ["winner"]     # played once, not again and again

var on := false
var client                   # game_client.gd: its options and its saved values
var player: AudioStreamPlayer
var want := ""               # the song that should play: "lobby", "match", "winner" or "" (none)
var now := ""                # the one in the player
var now_file := ""           # and its file (p4.22: a season can have its own take)
var done := false            # a play-once song has played
var fade := 0.0              # seconds of fade-out left
var unlocked := false
var tapped := false
var _ask_ms := -1000
var log_on := false

func setup(c) -> void:
	client = c
	log_on = c.opts.has("sfxlog")
	var pick := str(c.opts.get("music", c._storage_get(MUSIC_KEY)))
	set_process(false)
	set_process_input(false)
	set_on(pick == "1" or pick == "true", false)

# SETTINGS' MUSIC row calls this. keep: remember the pick on this device.
func set_on(v: bool, keep := true) -> void:
	if keep and client != null:
		client._storage_set(MUSIC_KEY, "1" if v else "0")
	if v == on:
		return
	on = v
	set_process(on)
	set_process_input(on)
	if on:
		player = AudioStreamPlayer.new()
		player.volume_db = DB
		add_child(player)
	else:
		if player != null:
			player.queue_free()      # a freed player stops, and its song leaves memory
		player = null
		now = ""
		now_file = ""
		done = false
		fade = 0.0
	print("🎵 [Music] %s" % ("ON" if on else "OFF"))

# Is there a song for the winner now? (The sound effects' fanfare stays quiet then.)
func has_winner() -> bool:
	return on and ((Season.now == "harvest" and ResourceLoader.exists(DIR + "winner.wav")) \
		or (Season.now == "christmas" and ResourceLoader.exists(DIR + "winner_xmas.wav")))

# A song's file: in the Christmas season its own take (<name>_xmas.wav) when there is one (p4.22).
func _file(name: String) -> String:
	if Season.now == "christmas" and ResourceLoader.exists(DIR + name + "_xmas.wav"):
		return DIR + name + "_xmas.wav"
	return DIR + name + ".wav"

# What is on the screen: the page calls this every frame.
func set_scene(lobby_shown: bool, phase: int, match_end_phase: int) -> void:
	if not on:
		return
	if phase == match_end_phase and not lobby_shown:
		want = "winner" if has_winner() else ""
	elif lobby_shown:
		want = "lobby"
	else:
		want = "match"

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec()
	if t - _ask_ms > 250:
		_ask_ms = t
		if not OS.has_feature("web"):
			unlocked = true
		else:
			var st = JavaScriptBridge.eval("(window.tbAudio && window.tbAudio.state) || ''", true)
			unlocked = tapped if (st == null or str(st) == "") else str(st) == "running"
	if not unlocked or player == null:
		return
	var want_file := _file(want) if want != "" else ""      # (the season's own take: a change of season changes the song)
	if want_file != now_file:
		if now != "" and player.playing and fade <= 0.0:
			fade = FADE_S                 # the old song goes out first
		if fade > 0.0:
			fade -= delta
			player.volume_db = DB - 40.0 * (1.0 - maxf(fade, 0.0) / FADE_S)
			if fade > 0.0:
				return
		player.stop()
		player.stream = null
		now = want
		now_file = want_file
		done = false
		fade = 0.0
		if now != "":
			var path := now_file
			var st: AudioStream = load(path) if ResourceLoader.exists(path) else null
			if st == null:
				done = true               # no file: nothing to play, and no asking again
				return
			player.stream = st
			player.volume_db = DB
			player.play()
			if log_on:
				print("🎵 [Music] %s" % now)
	elif now != "" and not done and not player.playing:
		if ONCE.has(now):
			done = true
		else:
			player.play()                 # the lobby's and the match's song start again

func _input(ev: InputEvent) -> void:
	if not tapped and ev.is_pressed() and (ev is InputEventMouseButton or ev is InputEventScreenTouch or ev is InputEventKey):
		tapped = true

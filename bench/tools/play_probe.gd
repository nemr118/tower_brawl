# A headless person: joins server/game_server.gd as a real client (client/net.gd),
# takes a seat, and either stands still, runs the move proof, or watches the
# match and reports what happened. The first-playable plan, 3.7.
#   godot --headless --path bench --script res://tools/play_probe.gd -- \
#       --server=ws://127.0.0.1:8091 --name=Probe [--bots=N] [--start] [--idle]
#       [--move] [--watch=SECONDS] [--token=abc] [--lag=MS] [--jitter=MS]
# --start: press START once seated (the lobby needs 2 fighters: bots or others).
# --move: at the first FIGHT, hold right for 60 ticks, then jump (held 30 ticks),
#   then stand; the server's answer is checked against the same buttons run on a
#   local copy of the simulation from the same spot. --watch=N: stay up to N s
#   and expect a round end with a winner, a point counted, a match end and the
#   lobby back. --idle: just sit there (a second fighter for a proof).
# --lag, --jitter: the test knob in client/net.gd (every packet waits lag/2 each
# way, plus up to jitter). P2: inputs carry the tick they are for (net.ticks_now);
# at the end a clock line says how many came late and how early they came.
# Exit 0 when every expected thing happened, 1 otherwise. Lines start with 🧪.
extends SceneTree

const P = preload("res://sim/proto.gd")
const Net = preload("res://client/net.gd")
const SimScript = preload("res://sim/sim.gd")
const PHASES := ["LOBBY", "COUNTDOWN", "ROUND_START", "PLAY", "ROUND_END", "MATCH_END"]
const SCRIPT_LEN := 150

var net
var opts := {}
var seat := -1
var phase := -1
var seen_seats := {}
var started_ms := 0
var watch_s := 0.0
var mode_move := false
var mode_idle := false
var start_sent := false
var bots_sent := false
var script_t := -1
var x0 := 0
var y0 := 0
var top_y := 0
var move_done := false
var move_ok := false
var seen := {"round_end": 0, "point": false, "match_end": false, "lobby_back": false, "fight": 0}
var fails := 0
var done := false

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var p := a.trim_prefix("--")
		if "=" in p:
			opts[p.get_slice("=", 0)] = p.substr(p.find("=") + 1)
		else:
			opts[p] = true
	mode_move = opts.has("move")
	mode_idle = opts.has("idle")
	watch_s = float(opts.get("watch", 0))
	var url := str(opts.get("server", "ws://127.0.0.1:%d" % P.PORT))
	net = Net.new()
	net.lag_ms = float(opts.get("lag", 0))
	net.jitter_ms = float(opts.get("jitter", 0))
	net.open(url, str(opts.get("name", "Probe")), str(opts.get("token", "")))
	started_ms = Time.get_ticks_msec()
	print("🧪 [PlayProbe] %s connecting to %s (version %s)" % [opts.get("name", "Probe"), url, P.VERSION])

func _process(_delta: float) -> bool:
	if done:
		return false
	net.poll()
	for m in net.take_messages():
		_on_message(m)
	var s: Dictionary = net.newest()
	if not s.is_empty():
		if s["phase"] != phase:
			phase = s["phase"]
			print("🧪 [PlayProbe] phase %s (round %d, goal %d, tick %d)" % [PHASES[phase], s["round"], s["goal"], s["tick"]])
			if phase == P.PH_PLAY:
				seen["fight"] += 1
				if mode_move and script_t < 0 and s["by_id"].has(seat):
					var me: Dictionary = s["by_id"][seat]
					x0 = int(me["x"])
					y0 = int(me["y"])
					top_y = y0
					_pick_run()
					script_t = 0
					print("🧪 [PlayProbe] move proof starts at x=%d y=%d: %s for %d ticks, then a held jump" % [x0, y0, "right" if run_dir > 0 else "left", run_ticks])
			if phase == P.PH_LOBBY and seen["match_end"]:
				seen["lobby_back"] = true
		if script_t >= 0 and not move_done and s["by_id"].has(seat):
			top_y = mini(top_y, int(s["by_id"][seat]["y"]))
		if seat >= 0 and s["by_id"].has(seat) and s["by_id"][seat]["points"] > 0:
			seen["point"] = true
	var up := (Time.get_ticks_msec() - started_ms) / 1000.0
	var limit := watch_s if watch_s > 0.0 else 60.0
	if mode_idle:
		if up > limit:   # --idle --watch=N: sit there N seconds, that is the job
			_finish(false)
		return false
	var wanted_done: bool = (not mode_move or move_done) and (watch_s <= 0.0 or bool(seen["lobby_back"]))
	if wanted_done or up > limit:
		_finish(up > limit and not wanted_done)
	return false

func _physics_process(_delta: float) -> bool:
	if done or seat < 0 or net.state != WebSocketPeer.STATE_OPEN:
		return false
	for t in net.ticks_now():
		var buttons := 0
		if script_t >= 0 and script_t < SCRIPT_LEN:
			buttons = _script_buttons(script_t)
			script_t += 1
			script_end_tick = t
		net.send_input(buttons, 0, t)
		inputs_sent += 1
	if net.jumped:
		net.jumped = false
		if clock_from_ms == 0:
			clock_from_ms = Time.get_ticks_msec() + 1000   # the clock line counts from 1 s after the first sync
	if clock_from_ms > 0 and not clock_counting and Time.get_ticks_msec() >= clock_from_ms:
		clock_counting = true
		net.late_total = 0
		net.margin_log.clear()
		inputs_from = inputs_sent
	# the move proof: judge once the server has run the script's last tick
	if script_t >= SCRIPT_LEN and not move_done and not net.newest().is_empty() and int(net.newest()["tick"]) >= script_end_tick + 2:
		_judge_move()
	return false

var script_end_tick := 0
var inputs_sent := 0
var inputs_from := 0
var clock_from_ms := 0
var clock_counting := false

var run_dir := 1
var run_ticks := 60

func _script_buttons(t: int) -> int:
	if t < run_ticks:
		return P.B_RIGHT if run_dir > 0 else P.B_LEFT
	if t < run_ticks + 30:
		return P.B_JUMP
	return 0

# The spawn spot is random and most spots are short ledges: try the run on the
# local simulation first and keep the first one that ends on the ground with a
# clear jump (right 60, left 60, right 20, left 20 ticks). A spot with none (a
# low ceiling) runs right 60 and is judged on the match with the local sim alone.
var clear_jump := true

func _pick_run() -> void:
	for cand in [[1, 60], [-1, 60], [1, 20], [-1, 20]]:
		run_dir = cand[0]
		run_ticks = cand[1]
		var r := _local_run()
		if r["ground"] and r["rise"] >= 140:
			clear_jump = true
			return
	run_dir = 1
	run_ticks = 60
	clear_jump = false

# The same buttons on a local copy of the simulation, from the same spot:
# {dx, rise, ground (on the ground when the jump came)}.
func _local_run() -> Dictionary:
	var sim = SimScript.new(0, 24, 7)
	sim.respawn = false
	sim.start_round([{"id": 0, "bot": false}])
	var f = sim.fighters[0]
	sim._place(f, Vector2i(x0 + sim.HALF_W, y0 + sim.BODY_H))
	var ltop: int = y0
	var ground := false
	for t in SCRIPT_LEN + 8:
		if t == run_ticks:
			ground = f.on_ground
		sim.apply_input(f, _script_buttons(t) if t < SCRIPT_LEN else 0, 0)
		sim.step()
		ltop = mini(ltop, f.y)
	return {"dx": int(SimScript.wrap_d(x0, f.x, 1920.0)), "rise": y0 - ltop, "ground": ground}

func _judge_move() -> void:
	move_done = true
	var s: Dictionary = net.newest()
	if not s["by_id"].has(seat):
		print("🧪 [PlayProbe] FAIL move: my fighter is gone from the snapshot")
		fails += 1
		return
	var me: Dictionary = s["by_id"][seat]
	var dx := int(SimScript.wrap_d(x0, me["x"], 1920.0))
	var rise := y0 - top_y
	var local := _local_run()
	var ldx: int = local["dx"]
	var lrise: int = local["rise"]
	var ok_dx := absi(dx - ldx) <= 1    # P2: the inputs land on their ticks, so the server matches the local sim
	var ok_rise := absi(rise - lrise) <= 1
	move_ok = ok_dx and ok_rise and absi(dx) > 100 and (rise > 140 or not clear_jump)
	if not move_ok:
		fails += 1
	print("🧪 [PlayProbe] %s move proof: %s %d ticks then a held jump: the server moved me %d px (local sim %d, ±1) and I rose %d px (local sim %d, ±1)%s" % [
		"PASS" if move_ok else "FAIL", "right" if run_dir > 0 else "left", run_ticks, dx, ldx, rise, lrise,
		"" if clear_jump else " (this spot has no clear jump: judged on the match alone)"])

func _on_message(m: Dictionary) -> void:
	var kind := str(m.get("kind", ""))
	if kind == "welcome":
		seat = int(m.get("seat", -1))
		print("🧪 [PlayProbe] welcome: seat %d, server %s, phase %s" % [seat, m.get("version", "?"), PHASES[int(m.get("phase", 0))]])
		if seat < 0 and not mode_idle_watch_only():
			net.send({"kind": "join", "name": str(opts.get("name", "Probe"))})
		elif seat >= 0:
			if opts.has("bots") and not bots_sent:
				bots_sent = true
				net.send({"kind": "bots", "n": int(opts["bots"])})
	elif kind == "version_error":
		print("🧪 [PlayProbe] FAIL: version_error (server %s, mine %s)" % [m.get("server"), m.get("yours")])
		fails += 1
		_finish(false)
	elif kind == "full":
		print("🧪 [PlayProbe] FAIL: the server is full")
		fails += 1
		_finish(false)
	elif kind == "note":
		print("🧪 [PlayProbe] note from the server: %s" % m.get("text", ""))
	elif kind == "seats":
		seen_seats = m
		var names: Array = []
		for s in m["seats"]:
			if s["kind"] != 0:
				names.append("%d:%s%s" % [s["i"], s["name"], "" if s["on"] else "(away)"])
		print("🧪 [PlayProbe] seats: %s | people %d bots %d goal %d phase %s" % [" ".join(names), m["people"], m["bots"], m["goal"], PHASES[int(m["phase"])]])
		if opts.has("start") and not start_sent and seat >= 0 and int(m["phase"]) == P.PH_LOBBY and int(m["people"]) + int(m["bots"]) >= 2:
			start_sent = true
			net.send({"kind": "start"})
			print("🧪 [PlayProbe] START pressed")
	elif kind == "round_end":
		if bool(m["draw"]):
			print("🧪 [PlayProbe] round %d: a draw" % int(m["round"]))
		else:
			seen["round_end"] += 1
			print("🧪 [PlayProbe] round %d: seat %d '%s' wins; points %s" % [int(m["round"]), int(m["winner"]), m["name"], str(m["points"])])
	elif kind == "match_end":
		seen["match_end"] = true
		print("🧪 [PlayProbe] MATCH END: seat %d '%s' wins; points %s" % [int(m["winner"]), m["name"], str(m["points"])])

func mode_idle_watch_only() -> bool:
	return opts.has("spectate")

func _finish(timed_out: bool) -> void:
	done = true
	_clock_line()
	if watch_s > 0.0 and not mode_idle:
		var want := {"round_end": seen["round_end"] > 0, "point": seen["point"] or seen["round_end"] > 0, "match_end": seen["match_end"], "lobby_back": seen["lobby_back"]}
		for k in want:
			if not want[k]:
				fails += 1
		print("🧪 [PlayProbe] watch: rounds won %d, a point counted %s, match end %s, lobby back %s%s" % [
			seen["round_end"], want["point"], seen["match_end"], seen["lobby_back"], " (TIMED OUT)" if timed_out else ""])
	if mode_move and not move_done:
		fails += 1
		print("🧪 [PlayProbe] FAIL: the move proof never ran (no FIGHT seen)")
	if timed_out and not mode_move and watch_s <= 0.0:
		pass
	print("🧪 [PlayProbe] %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	net.ws.close()
	quit(0 if fails == 0 else 1)

# P2: the inputs since 1 s after the first sync: how many came late (T_OWN says),
# and how early they came (the smallest margin in each T_OWN window, in ticks).
func _clock_line() -> void:
	if not clock_counting:
		print("🧪 [PlayProbe] clock: never synced")
		return
	var m: PackedInt32Array = net.margin_log.duplicate()
	m.sort()
	var n: int = inputs_sent - inputs_from
	var hist := {}
	for v in m:
		hist[v] = hist.get(v, 0) + 1
	var parts: Array = []
	for k in hist.keys():
		parts.append("%d:%d" % [k, hist[k]])
	print("🧪 [PlayProbe] clock: lag %d ms jitter %d ms, rtt %d ms: %d inputs, %d late (%.2f%%); margin min %d median %d max %d (ticks: windows %s); %d clock changes, %d jumps; draw delay %.1f ticks" % [
		int(net.lag_ms), int(net.jitter_ms), net.last_rtt, n, net.late_total, 100.0 * net.late_total / maxf(1.0, n),
		m[0] if m.size() > 0 else 0, m[m.size() / 2] if m.size() > 0 else 0, m[m.size() - 1] if m.size() > 0 else 0,
		" ".join(parts), net.clock_changes, net.clock_jumps, net.delay_ticks])

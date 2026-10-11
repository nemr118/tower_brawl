# A headless person: joins server/game_server.gd as a real client (client/net.gd),
# takes a seat, and either stands still, runs the move proof, or watches the
# match and reports what happened. The first-playable plan, 3.7.
#   godot --headless --path bench --script res://tools/play_probe.gd -- \
#       --server=ws://127.0.0.1:8091 --name=Probe [--bots=N] [--arena=N] [--start] [--idle]
#       [--move] [--watch=SECONDS] [--token=abc] [--lag=MS] [--jitter=MS]
#       [--predict [--exact=PCT]] [--shooter] [--catcher[=old]]
# --start: press START once seated (the lobby needs 2 fighters: bots or others).
# --arena=N: the lobby's ARENA once seated (-1 MIX, 1 THE KEEP, 2 THE BRIDGES, 0
#   the bench); the move proof's local copy runs on the round's arena (G5).
# --move: at the first FIGHT, hold right for 60 ticks, then jump (held 30 ticks),
#   then stand; the server's answer is checked against the same buttons run on a
#   local copy of the simulation from the same spot. --watch=N: stay up to N s
#   and expect a round end with a winner, a point counted, a match end and the
#   lobby back. --idle: just sit there (a second fighter for a proof).
# --lag, --jitter: the test knob in client/net.gd (every packet waits lag/2 each
# way, plus up to jitter). P2: inputs carry the tick they are for (net.ticks_now);
# at the end a clock line says how many came late and how early they came.
# --predict: my fighter is predicted as on the page (client/predict.gd), with
#   random buttons in every round (held 4 to 30 ticks: runs, jumps, drops,
#   dodges, shots), START again in each lobby; at the end a line says how big the
#   server's corrections were. --exact=95: fail unless 95% of them are 0 px.
# --shooter / --catcher: the catch test (P2 step 3), two people, no bots (a server
#   with --arena bench --spots 2,3 puts them on the bench arena's two ledge ends
#   that face each other: the new arenas have no spawn spots in a clear line). The
#   shooter stands and shoots at the other one every 90 ticks. The catcher stands
#   and dodges up on the tick an arrow reaches its body as the page draws it: the
#   arrows in the present (client/present.gd), or with --catcher=old as P1 drew it
#   (the arrows at the draw clock, you from the newest snapshot).
#   When the shooter's quiver is empty, the catcher shoots back to end the round.
#   At the end: how many arrows reached it, caught or killed it.
# Exit 0 when every expected thing happened, 1 otherwise. Lines start with 🧪.
extends SceneTree

const P = preload("res://sim/proto.gd")
const Net = preload("res://client/net.gd")
const SimScript = preload("res://sim/sim.gd")
const Predict = preload("res://client/predict.gd")
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
var arena_sent := false
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
	mode_predict = opts.has("predict")
	mode_shooter = opts.has("shooter")
	mode_catcher = str(opts.get("catcher", "")) if opts.has("catcher") else ""
	if mode_catcher == "true":
		mode_catcher = "present"
	pred = Predict.new()
	rng.seed = int(opts.get("seed", 5))
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
	for o in net.take_owns():
		pred.reconcile(o)
	if mode_catcher != "":
		_catch_events()
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
			if phase == P.PH_LOBBY and (mode_predict or mode_shooter):
				start_sent = false   # play on: START again
			if phase == P.PH_PLAY:
				play_ticks = 0
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
	if mode_predict or mode_shooter or mode_catcher != "":
		if up > limit:
			_finish(false)
		return false
	var wanted_done: bool = (not mode_move or move_done) and (watch_s <= 0.0 or bool(seen["lobby_back"]))
	if wanted_done or up > limit:
		_finish(up > limit and not wanted_done)
	return false

func _physics_process(_delta: float) -> bool:
	if done or seat < 0 or net.state != WebSocketPeer.STATE_OPEN:
		return false
	var ticks: Array = net.ticks_now()
	if net.jumped:
		net.jumped = false
		if not ticks.is_empty():
			pred.jump_to(ticks[0] - 1)
	for t in ticks:
		var buttons := 0
		var aim := 0
		if script_t >= 0 and script_t < SCRIPT_LEN:
			buttons = _script_buttons(script_t)
			script_t += 1
			script_end_tick = t
		elif mode_predict and phase == P.PH_PLAY:
			if hold[2] <= 0:
				hold = _random_buttons()
			hold[2] -= 1
			buttons = hold[0]
			aim = hold[1]
		elif (mode_shooter or mode_catcher != "") and phase == P.PH_PLAY:
			var ba := _duel_buttons(t)
			buttons = ba[0]
			aim = ba[1]
		pred.on_tick(t, buttons, aim)
		net.send_input(buttons, aim, t)
		inputs_sent += 1
	if clock_from_ms == 0 and net.synced:
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
var mode_predict := false
var mode_shooter := false
var mode_catcher := ""
var present = preload("res://client/present.gd").new()
var play_ticks := 0         # ticks run since FIGHT
var reached := {}           # arrow id -> true: it reached the catcher as the chosen view drew it
var caught := 0
var killed := 0
var pred
var rng := RandomNumberGenerator.new()
var hold := [0, 0, 0]

# Random buttons held 4 to 30 ticks (as input_probe.gd's): runs, jumps, drops,
# dodges, shots.
func _random_buttons() -> Array:
	var b := 0
	if rng.randf() < 0.7:
		b |= P.B_LEFT if rng.randf() < 0.5 else P.B_RIGHT
	if rng.randf() < 0.35:
		b |= P.B_JUMP
	if rng.randf() < 0.15:
		b |= P.B_DOWN
	if rng.randf() < 0.1:
		b |= P.B_UP
	if rng.randf() < 0.12:
		b |= P.B_DODGE
	if rng.randf() < 0.2:
		b |= P.B_SHOOT
	return [b, rng.randi_range(0, 3599), rng.randi_range(4, 30)]
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
		if r["ground"] and r["rise"] >= 140 and absi(int(r["dx"])) > 100:   # G5: a run a wall stops short is no proof
			clear_jump = true
			return
	run_dir = 1
	run_ticks = 60
	clear_jump = false

# The same buttons on a local copy of the simulation, from the same spot:
# {dx, rise, ground (on the ground when the jump came)}.
func _local_run() -> Dictionary:
	var sim = SimScript.new(0, 24, 7)
	sim.set_arena(int(net.newest().get("arena", 0)))   # G5: the round's arena
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
	move_ok = ok_dx and ok_rise and ((absi(dx) > 100 and rise > 140) or not clear_jump)
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
		pred.seat = seat
		if seat < 0 and not mode_idle_watch_only():
			net.send({"kind": "join", "name": str(opts.get("name", "Probe"))})
		elif seat >= 0:
			if opts.has("bots") and not bots_sent:
				bots_sent = true
				net.send({"kind": "bots", "n": int(opts["bots"])})
			if opts.has("arena") and not arena_sent:
				arena_sent = true
				net.send({"kind": "arena", "n": int(opts["arena"])})
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
	if mode_predict:
		_predict_line()
	if mode_catcher != "":
		_catch_line()
	if watch_s > 0.0 and not mode_idle and not mode_predict and not mode_shooter and mode_catcher == "":
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

# P2: the server's corrections to my predicted fighter (client/predict.gd): each
# T_OWN in a round compared with where the prediction had me on its tick.
func _predict_line() -> void:
	var e: PackedFloat32Array = pred.errors.duplicate()
	e.sort()
	var n := e.size()
	var zero := 0
	var two := 0
	for v in e:
		if v < 0.5:
			zero += 1
		if v <= 2.0:
			two += 1
	var zero_pct := 100.0 * zero / maxf(1.0, n)
	var bar := float(opts.get("exact", 0))
	var ok: bool = n >= 100 and zero_pct >= bar
	if not ok:
		fails += 1
	print("🧪 [PlayProbe] %s prediction: %d corrections, 0 px on %.1f%%, 2 px or less on %.1f%%, p99 %.1f px, the worst %.1f px; %d jumps (over %d px); %.1f ticks run again per T_OWN%s" % [
		"PASS" if ok else "FAIL", n, zero_pct, 100.0 * two / maxf(1.0, n), e[mini(n - 1, int(n * 0.99))] if n > 0 else 0.0,
		e[n - 1] if n > 0 else 0.0, pred.jumps, int(Predict.SNAP_PX), pred.replayed / maxf(1.0, n),
		(" (the bar: %.0f%% at 0 px)" % bar) if bar > 0.0 else ""])

# The catch test's buttons for tick t (--shooter, --catcher).
func _duel_buttons(t: int) -> Array:
	play_ticks += 1
	var s: Dictionary = net.newest()
	if s.is_empty() or pred.me == null or pred.me.state == P.F_DEAD:
		return [0, 0]
	var other: Dictionary = {}
	for f in s["fighters"]:
		if int(f["id"]) != seat and int(f["state"]) != P.F_DEAD:
			other = f
	if other.is_empty():
		return [0, 0]
	var bow := Vector2(pred.me.x + 18.0, pred.me.y + 28.0)
	var to := Vector2(SimScript.wrap_d(bow.x, other["x"] + 18.0, 1920.0), SimScript.wrap_d(bow.y, other["y"] + 31.0, 1080.0))
	var aim := posmod(roundi(rad_to_deg(to.angle()) * 10.0), 3600)
	if mode_shooter:
		var cyc := play_ticks % 90
		if play_ticks > 30 and cyc < 10 and pred.me.arrows > 0:
			return [P.B_SHOOT, aim]
		return [0, aim]
	# the catcher stands; it dodges up (and lands back) on the tick an arrow reaches it
	if _arrow_reaches_me(t) and pred.me.state == P.F_NORMAL and pred.me.dodge_cd == 0:
		return [P.B_DODGE | P.B_UP, aim]
	if int(other["arrows"]) == 0 and pred.me.arrows > 0 and play_ticks % 60 < 10:
		return [P.B_SHOOT, aim]   # the shooter is empty: end the round
	return [0, aim]

# An enemy arrow in the air touches my body on tick t, as the chosen view draws it.
func _arrow_reaches_me(t: int) -> bool:
	var s: Dictionary = net.newest()
	var arrows: Dictionary
	var mx: float
	var my: float
	if mode_catcher == "old":
		arrows = net.sample(net.render_tick())["arrows"]
		if not s["by_id"].has(seat):
			return false
		mx = s["by_id"][seat]["x"]
		my = s["by_id"][seat]["y"]
	else:
		arrows = present.arrows_at(s, t, pred.me, seat, [], [], 0.0)
		mx = pred.me.x
		my = pred.me.y
	var hit := false
	for id in arrows:
		var a: Dictionary = arrows[id]
		if int(a["state"]) != P.S_FLY or int(a.get("owner", -1)) == seat:
			continue
		if mode_catcher == "old" and int(s["arrows"].get(id, {}).get("owner", -1)) == seat:
			continue
		var dx := SimScript.wrap_d(mx, a["x"], 1920.0)
		var dy := SimScript.wrap_d(my, a["y"], 1080.0)
		if dx >= -4.0 and dx <= 40.0 and dy >= -4.0 and dy <= 67.0:
			if not reached.has(id):
				reached[id] = true
			hit = true
	return hit

func _catch_events() -> void:
	for e in net.take_events(1e12):
		if e[3] != seat:
			continue
		if e[0] == P.E_CATCH:
			caught += 1
		elif e[0] == P.E_DEATH and e[4] == 1:
			killed += 1

func _catch_line() -> void:
	var n := reached.size()
	var ok: bool = mode_catcher == "old" or (n >= 5 and caught >= n and killed == 0)
	if not ok:
		fails += 1
	print("🧪 [PlayProbe] %s catches (%s view, lag %d ms): %d arrows reached me as drawn; I dodged on that tick: %d caught, %d killed me" % [
		"REPORT" if mode_catcher == "old" else ("PASS" if ok else "FAIL"), "P1's old" if mode_catcher == "old" else "the present",
		int(net.lag_ms), n, caught, killed])

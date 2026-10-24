# ==============================================================================
# The game server (P1, the first playable; grown from bench_server.gd). Headless
# Godot. It owns the seats, the lobby, the rounds and the points, runs the
# simulation (sim/sim.gd) at 60 ticks a second from the players' buttons, sends
# every client a snapshot every second tick over wss (ws with --no-tls), and
# writes a line every REPORT_S seconds about its own cost.
#   godot --headless --path bench res://server/game_server.tscn -- \
#       [--port 8091] [--no-tls] [--cert <pem>] [--key <pem>] [--bots 7]
#       [--power-arrows] [--goal N] [--walls-s N] [--out <dir>] [--seconds N] [--quiet] [--spots 2,3]
#       [--arena mix|keep|bridges|bench|N] [--bot-level old|easy|normal|hard] [--soak]
#       [--net-thread 0|1] [--net-sleep-ms 4] [--admin-port 8092] [--admin-bind 127.0.0.1]
# --bots N: how many bots fill the empty seats (0..7; the lobby can change it).
# --power-arrows: the benchmark's arrow mix (fire, bomb, poison, smoke) for all.
# --goal N: points to win, instead of the rule by player count (a test knob).
# --walls-s N: the purple walls come N s after FIGHT (default 25, TowerFall's; 0: never).
# --spots 2,3: a test knob: the first fighter always starts on spawn spot 2, the
#   second on 3 (sim/level.gd spawns), not shuffled (play_probe's catch test, on
#   the bench arena: --arena bench).
# --arena: the lobby's ARENA to start with (G5): mix (the default: THE KEEP and
#   THE BRIDGES take turns each round), keep, bridges, or bench (the test arena,
#   not in the lobby's list), or a layout number. The lobby can change it.
# --bot-level: the bots' brain level to start with (sim/brain.gd, G6): easy,
#   normal (the default), hard, or old (p3.1's brain, a test knob). The lobby's
#   BOTS level button changes it (EASY, NORMAL, HARD).
# --soak: a bot soak (G6): bots in all 8 seats, no people needed, and a match
#   starts by itself whenever the lobby comes back (tools/v2_soak_report.py).
# --admin-port N: the host port (p4.2, for the host page in Ignition,
#   ~/Work/tower_brawl_ignition/build_host.py): plain http on 127.0.0.1 only
#   (--admin-bind to change that), JSON in and out. GET /state: the seats (with
#   each person's address and ping), the settings, the players' numbers tonight,
#   the last 80 events. POST /bots {n} (0..7), /bot_level {n} (1..3), /arena {n}
#   (P.ARENA_MIX or an arena of LevelScript.PLAY): any time, in a match from the
#   next round; /power {n} (p4.5: the power arrows on or off, from the next shot);
#   /kick {seat} (a person goes back to watching), /start, /stop (the match ends,
#   back to the lobby). A reply: {ok, text, state}. 0 (the default): off.
# Inputs land on their tick (P2): each input carries the server tick it is for,
# the server keeps a small queue per seat and applies input N just before tick N
# (a late one at once, so no press is lost; the held buttons when none came), and
# after each snapshot each seated person gets a T_OWN packet (proto.gd): how early
# their inputs came, and their fighter's whole state for the client's prediction.
# Two threads, as in the benchmark: the network thread owns the sockets (TLS and
# websocket handshakes, reading, pongs, sending); this thread owns the seats and
# the simulation. They trade messages under net_mutex: net_in (open, text, input,
# close) comes up, net_out (a snapshot for all, a JSON text for one) goes down.
# The JSON (text frames). From a client: hello {name, version, token},
# join {name}, leave, start, bots {n}, arena {n} (P.ARENA_MIX or a layout),
# bot_level {n} (1 EASY, 2 NORMAL, 3 HARD), power {n} (p4.5: 1 the power arrows on, 0 off), name {name}. From the server: welcome {seat, version, name, phase},
# version_error {server, yours}, full, note {text}, seats {phase, round, goal,
# bots, bots_wanted, bot_level, power, people, arena (the pick), arena_now (the round's,
# or the next one's in the lobby), seats: [{i, name, kind, on, points, crowns, in}]},
# round_end {round, winner, name,
# draw, points}, match_end {winner, name, points}.
# Output: <out>/<date>/v2_server.jsonl (a report line every REPORT_S s; G6: a
# round line at each round's end with every death, its cause and spot, and a
# match line at each match's end), <out>/<date>/v2_stats.json (the players'
# numbers tonight, p4.2: saved after each round, read back when the server
# starts again that day), and tagged lines on stdout: [NET] [JOIN] [LEAVE]
# [LOBBY] [ROUND] [KILL] [MATCH] [HOST].
# ==============================================================================
extends Node

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")

const SEATS := 8
const MAX_BOTS := 7
const HOLD_TICKS := 480          # a dropped person's seat is held 8 s
const COUNTDOWN_TICKS := 180     # START to the first round: 3 s
const ROUND_START_TICKS := 90    # the ROUND N banner, nobody moves: 1.5 s
const ROUND_MAX_TICKS := 3600    # a round with no end is a draw at 60 s (a backstop: the purple walls kill everyone left by 48 s)
const WALLS_S := 25              # the purple walls (TowerFall's miasma) come 25 s after FIGHT
const ROUND_END_TICKS := 90      # one fighter left: TowerFall waits 1.5 s before the point
const DRAW_TICKS := 60           # nobody left: a shorter DRAW banner
const MATCH_END_TICKS := 420     # the winner's screen: 7 s, then the lobby
const REPORT_S := 5
const NAME_MAX := 12
const MAX_EARLY := 60            # an input more than 1 s early is applied at once (the client's clock is off)
const EVENTS_MAX := 80           # the host page's recent events
const HOST_MAX := 16384          # the largest request the host port reads
const PHASE_NAMES := ["LOBBY", "COUNTDOWN", "ROUND START", "PLAYING", "ROUND END", "MATCH END"]
const STAT_KEYS := ["matches", "match_wins", "rounds", "round_wins", "kills", "arrow_kills", "stomp_kills",
	"other_kills", "deaths", "self_kills", "catches", "shots"]

class Client:
	var id: int = 0
	var ip: String = ""
	var tcp: StreamPeerTCP
	var tls: StreamPeerTLS
	var ws: WebSocketPeer
	var state: int = 0          # 0 TLS handshake, 1 websocket
	var opened: bool = false
	var since_ms: int = 0
	var bytes_out: int = 0
	var bytes_in: int = 0
	var rtt: int = -1
	var gap: int = -1
	var send_fail: int = 0

class Conn:                     # what this thread knows about a socket
	var id: int = 0
	var ip: String = ""
	var ok: bool = false        # said hello with the right version
	var seat: int = -1
	var name: String = ""
	var token: String = ""
	var last_tick: int = 0      # the newest client input tick applied

class Seat:
	var i: int = 0
	var kind: int = 0           # 0 empty, 1 a person, 2 a bot (for this match)
	var name: String = ""
	var client_id: int = 0      # 0: no socket (a held seat, or a bot)
	var token: String = ""
	var hold_t: int = 0
	var points: int = 0
	var crowns: int = 0
	var buttons: int = 0        # the last buttons applied (held while no input comes)
	var aim: int = 0
	var in_round: bool = false  # has a fighter this round
	var input_tick: int = -1    # the sim tick a late input was applied on
	var queue := {}             # input tick -> [buttons, aim]: applied just before that tick
	var used: int = 0           # the newest input tick applied
	var margin_min: int = P.NO_MARGIN   # the smallest margin (ticks early) since the last T_OWN
	var late_n: int = 0         # inputs that came after their tick, since the last T_OWN
	var late_all: int = 0       # and in all, with the inputs counted, for the report
	var inputs_all: int = 0

class HostConn:                 # one request on the host port
	var tcp: StreamPeerTCP
	var buf := PackedByteArray()
	var ms: int = 0

var sim
var seats: Array = []
var conns := {}                 # client id -> Conn
var phase := P.PH_LOBBY
var phase_t := 0
var round_no := 0
var match_no := 0                # matches started since the server came up
var round_deaths: Array = []     # this round's deaths: [victim, killer, cause, x, y, s after FIGHT]
var soak := false
var goal := 0
var winner := P.NO_ONE
var bots_wanted := MAX_BOTS
var arena_pick := P.ARENA_MIX    # the lobby's ARENA (G5): MIX or one layout of sim/level.gd
var mix_i := 0                   # MIX: the next arena in LevelScript.PLAY
var goal_override := 0
var seats_dirty := true
var next_client_id := 1
var server := TCPServer.new()
var tls_opts: TLSOptions = null
var clients: Array = []
var buf := StreamPeerBuffer.new()
var own_buf := StreamPeerBuffer.new()
var pending_events: Array = []
var tick_us := PackedInt64Array()
var interval_us := PackedInt64Array()
var sim_us_sum := 0
var last_tick_usec := 0
var sec_start_ms := 0
var started_ms := 0
var bytes_out_sec := 0
var bytes_in_sec := 0
var cpu_last := -1.0
var cpu_last_ms := 0
var server_log: FileAccess
var seconds_limit := 0
var port := P.PORT
var quiet := false
var net_thread_on := true
var net_sleep_us := 4000
var net_thread: Thread
var net_mutex := Mutex.new()
var net_quit := false
var net_in: Array = []           # [kind, client id, payload] from the network thread
var net_out: Array = []          # [client id or 0 for all, PackedByteArray or String]
var net_tick := 0
var net_per_client: Array = []
var net_out_pub := 0
var net_in_pub := 0
var net_busy_pub := 0
var host_port := 0               # the host port (p4.2): --admin-port; 0 off
var host := TCPServer.new()
var host_conns: Array = []       # HostConn
var events_ring: Array = []      # the last EVENTS_MAX tagged lines: {t, hhmm, tag, text}
var stats := {}                  # "name" or "bot:name" -> the player's numbers tonight
var stats_since := 0.0
var stats_path := ""
var last_rec := {}               # the last report line (the host page shows its tick numbers)

func _ready() -> void:
	var o := _args()
	port = int(o.get("port", P.PORT))
	bots_wanted = clampi(int(o.get("bots", MAX_BOTS)), 0, MAX_BOTS)
	goal_override = int(o.get("goal", 0))
	seconds_limit = int(o.get("seconds", 0))
	quiet = o.has("quiet")
	soak = o.has("soak")
	if soak:
		bots_wanted = SEATS
	net_thread_on = str(o.get("net-thread", "1")) != "0"
	host_port = int(o.get("admin-port", 0))
	net_sleep_us = int(float(o.get("net-sleep-ms", 4)) * 1000.0)
	var root_dir := ProjectSettings.globalize_path("res://").path_join("..").simplify_path()
	var out_dir := str(o.get("out", root_dir.path_join("bench_results"))).path_join(Time.get_date_string_from_system())
	DirAccess.make_dir_recursive_absolute(out_dir)
	var log_path := out_dir.path_join("v2_server.jsonl")
	server_log = FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	server_log.seek_end()
	_load_stats(out_dir.path_join("v2_stats.json"))
	Engine.max_fps = 120     # no busy loop in headless; physics stays at 60
	sim = SimScript.new(0, 24, int(Time.get_unix_time_from_system()))
	sim.respawn = false
	sim.power_arrows = o.has("power-arrows")
	sim.walls_start = maxi(0, int(o.get("walls-s", WALLS_S))) * 60
	if o.has("spots"):
		for k in str(o["spots"]).split(",", false):
			sim.fixed_spots.append(int(k))
	if o.has("arena"):
		arena_pick = _arena_arg(str(o["arena"]))
	if o.has("bot-level"):
		sim.bot_level = maxi(0, SimScript.BrainScript.NAMES.find(str(o["bot-level"]).to_upper()))
	sim.set_arena(_next_arena())   # the lobby shows the arena that comes next
	for i in SEATS:
		var s := Seat.new()
		s.i = i
		seats.append(s)
	if not o.has("no-tls"):
		var cert := X509Certificate.new()
		var key := CryptoKey.new()
		var cert_path := str(o.get("cert", root_dir.path_join("cert.pem")))
		var key_path := str(o.get("key", root_dir.path_join("key.pem")))
		if cert.load(cert_path) != OK or key.load(key_path) != OK:
			printerr("🏰 [NET] cannot load the TLS pair %s / %s (use --no-tls for ws)" % [cert_path, key_path])
			get_tree().quit(1)
			return
		tls_opts = TLSOptions.server(key, cert)
	var err := server.listen(port, "*")
	if err != OK:
		printerr("🏰 [NET] cannot listen on %d (error %d)" % [port, err])
		get_tree().quit(1)
		return
	if host_port > 0:
		var bind := str(o.get("admin-bind", "127.0.0.1"))
		if host.listen(host_port, bind) != OK:
			printerr("🏰 [NET] cannot open the host port %s:%d" % [bind, host_port])
			host_port = 0
		else:
			print("🏰 [NET] the host port: http://%s:%d (GET /state; POST /bots /bot_level /arena /kick /start /stop)" % [bind, host_port])
	started_ms = Time.get_ticks_msec()
	sec_start_ms = started_ms
	var info := {"kind": "start", "t": Time.get_unix_time_from_system(), "version": P.VERSION, "port": port,
		"tls": tls_opts != null, "bots": bots_wanted, "power_arrows": sim.power_arrows, "goal_override": goal_override,
		"walls_s": sim.walls_start / 60, "arena": _arena_label(arena_pick), "bot_level": SimScript.BrainScript.NAMES[sim.bot_level],
		"godot": Engine.get_version_info().string, "cpu": _cpu_model(), "cores": OS.get_processor_count(), "soak": soak,
		"host": OS.get_environment("HOSTNAME"), "net_thread": net_thread_on, "admin_port": host_port}
	server_log.store_line(JSON.stringify(info))
	server_log.flush()
	print("🏰 [NET] Tower Brawl %s: %s on %d, %d bots (%s) fill the empty seats, power arrows %s, %s, arena %s, cpu %s x%d, report in %s" % [
		P.VERSION, "wss" if tls_opts != null else "ws", port, bots_wanted, SimScript.BrainScript.NAMES[sim.bot_level], "on" if sim.power_arrows else "off",
		("the walls at %d s" % (sim.walls_start / 60)) if sim.walls_start > 0 else "no walls", _arena_label(arena_pick),
		info["cpu"], info["cores"], log_path])
	if net_thread_on:
		net_thread = Thread.new()
		net_thread.start(_net_loop)

func _args() -> Dictionary:
	var o := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		var k: String = a[i]
		if k.begins_with("--"):
			k = k.substr(2)
			if "=" in k:
				o[k.get_slice("=", 0)] = k.get_slice("=", 1)
			elif i + 1 < a.size() and not a[i + 1].begins_with("--"):
				o[k] = a[i + 1]
				i += 1
			else:
				o[k] = true
		i += 1
	return o

# ------------------------------------------------------------------ the tick
func _process(_dt: float) -> void:
	if server.is_listening() and not net_thread_on:
		_poll_clients()
	if host_port > 0:
		_host_poll()

func _physics_process(_dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	if last_tick_usec > 0:
		interval_us.append(t0 - last_tick_usec)
	last_tick_usec = t0
	if not net_thread_on:
		_accept()
		_poll_clients()
	_drain_inbox()
	_hold_seats()
	_match_tick()
	var t1 := Time.get_ticks_usec()
	_apply_inputs()
	sim.step()
	var evs: Array = sim.take_events()
	_log_deaths(evs)
	_count_events(evs)
	pending_events.append_array(evs)
	var t2 := Time.get_ticks_usec()
	if seats_dirty:
		_send_seats(0)
	if sim.tick % 2 == 0:
		sim.write_snapshot(buf, pending_events, _head())
		pending_events.clear()
		_out(0, buf.data_array)
		_send_own()
	var t3 := Time.get_ticks_usec()
	tick_us.append(t3 - t0)
	sim_us_sum += t2 - t1
	if Time.get_ticks_msec() - sec_start_ms >= REPORT_S * 1000:
		_report()
	if seconds_limit > 0 and Time.get_ticks_msec() - started_ms >= seconds_limit * 1000:
		print("🏰 [NET] --seconds %d reached, stopping" % seconds_limit)
		_stop_net()
		server_log.flush()
		get_tree().quit(0)

func _head() -> Dictionary:
	var left := 0
	if phase == P.PH_PLAY:
		left = ROUND_MAX_TICKS - phase_t
	elif phase != P.PH_LOBBY:
		left = phase_t
	return {"phase": phase, "round": round_no, "left": left, "goal": goal, "winner": winner}

# The messages the network thread read since the last tick.
func _drain_inbox() -> void:
	var msgs: Array
	if net_thread_on:
		net_mutex.lock()
		msgs = net_in
		net_in = []
		net_mutex.unlock()
	else:
		msgs = net_in
		net_in = []
	for m in msgs:
		var kind: String = m[0]
		var id: int = m[1]
		if kind == "open":
			var c := Conn.new()
			c.id = id
			c.ip = str(m[2])
			conns[id] = c
		elif not conns.has(id):
			continue
		elif kind == "text":
			_on_text(conns[id], str(m[2]))
		elif kind == "input":
			_on_input(conns[id], m[2])
		elif kind == "close":
			_on_close(conns[id])

func _on_text(c: Conn, txt: String) -> void:
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return
	var kind := str(d.get("kind", ""))
	if kind == "hello":
		var yours := str(d.get("version", "?"))
		if yours != P.VERSION:
			_say("🏰 [JOIN] client %d from %s has version %s, the server runs %s: turned away" % [c.id, c.ip, yours, P.VERSION])
			_out(c.id, JSON.stringify({"kind": "version_error", "server": P.VERSION, "yours": yours}))
			return
		c.ok = true
		c.name = _clean_name(str(d.get("name", "")), -1)
		c.token = str(d.get("token", "")).substr(0, 32)
		# a held seat with this token: the same person is back
		if c.token != "":
			for s in seats:
				if s.kind == 1 and s.client_id == 0 and s.token == c.token:
					_seat_person(s, c, true)
					break
		_out(c.id, JSON.stringify({"kind": "welcome", "seat": c.seat, "version": P.VERSION, "name": c.name, "phase": phase}))
		_send_seats(c.id)
		return
	if not c.ok:
		return
	if kind == "join":
		if c.seat >= 0:
			return
		if d.has("name"):
			c.name = _clean_name(str(d.get("name", "")), -1)
		var s := _free_seat()
		if s == null:
			_out(c.id, JSON.stringify({"kind": "full"}))
			_say("🏰 [JOIN] rejected %s from %s: all %d seats are taken" % [c.name, c.ip, SEATS])
			return
		_seat_person(s, c, false)
		_out(c.id, JSON.stringify({"kind": "welcome", "seat": c.seat, "version": P.VERSION, "name": c.name, "phase": phase}))
	elif kind == "leave":
		if c.seat >= 0:
			var s: Seat = seats[c.seat]
			_say("🏰 [LEAVE] seat %d '%s' left on purpose" % [s.i, s.name])
			_free_seat_now(s)
			c.seat = -1
			_out(c.id, JSON.stringify({"kind": "welcome", "seat": -1, "version": P.VERSION, "name": c.name, "phase": phase}))
	elif kind == "start":
		if c.seat < 0:
			_out(c.id, JSON.stringify({"kind": "note", "text": "Take a seat first."}))
		elif phase != P.PH_LOBBY:
			pass
		elif _people() + _bots_now() < 2:
			_out(c.id, JSON.stringify({"kind": "note", "text": "A match needs 2 fighters: add a bot or a friend."}))
		else:
			phase = P.PH_COUNTDOWN
			phase_t = COUNTDOWN_TICKS
			_say("🏰 [LOBBY] START by seat %d '%s': %d people + %d bots" % [c.seat, seats[c.seat].name, _people(), _bots_now()])
			seats_dirty = true
	elif kind == "bots":
		if c.seat >= 0 and (phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN):
			bots_wanted = clampi(int(d.get("n", bots_wanted)), 0, MAX_BOTS)
			seats_dirty = true
	elif kind == "bot_level":
		var lv := int(d.get("n", sim.bot_level))
		if c.seat >= 0 and (phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN) and lv != sim.bot_level \
				and lv >= SimScript.BrainScript.EASY and lv <= SimScript.BrainScript.HARD:
			sim.bot_level = lv
			_say("🏰 [LOBBY] bots %s, picked by seat %d '%s'" % [SimScript.BrainScript.NAMES[lv], c.seat, seats[c.seat].name])
			seats_dirty = true
	elif kind == "arena":
		var n := int(d.get("n", arena_pick))
		if c.seat >= 0 and (phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN) and n != arena_pick \
				and (n == P.ARENA_MIX or (n >= 0 and n < SimScript.LevelScript.count())):
			arena_pick = n
			sim.set_arena(_next_arena())
			_say("🏰 [LOBBY] arena %s, picked by seat %d '%s'" % [_arena_label(arena_pick), c.seat, seats[c.seat].name])
			seats_dirty = true
	elif kind == "power":
		var on := int(d.get("n", 0)) != 0
		if c.seat >= 0 and (phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN) and on != sim.power_arrows:
			sim.power_arrows = on
			_say("🏰 [LOBBY] power arrows %s, picked by seat %d '%s'" % ["ON" if on else "OFF", c.seat, seats[c.seat].name])
			seats_dirty = true
	elif kind == "name":
		if c.seat >= 0:
			c.name = _clean_name(str(d.get("name", "")), c.seat)
			seats[c.seat].name = c.name
			seats_dirty = true

func _clean_name(raw: String, seat: int) -> String:
	var n := ""
	for ch in raw.strip_edges():
		var code := ch.unicode_at(0)
		if code >= 32 and code != 127:
			n += ch
		if n.length() >= NAME_MAX:
			break
	if n == "":
		n = "Player %d" % (seat + 1) if seat >= 0 else "Player"
	return n

func _people() -> int:
	var n := 0
	for s in seats:
		if s.kind == 1:
			n += 1
	return n

# How many bots play: as many as wanted, never more than the free seats.
func _bots_now() -> int:
	return mini(bots_wanted, SEATS - _people())

# The lowest empty seat; in a match a bot's seat will do (the person takes over
# at the next round).
func _free_seat() -> Seat:
	for s in seats:
		if s.kind == 0:
			return s
	if phase != P.PH_LOBBY and phase != P.PH_COUNTDOWN:
		for s in seats:
			if s.kind == 2:
				return s
	return null

func _seat_person(s: Seat, c: Conn, back: bool) -> void:
	var was_bot := s.kind == 2
	s.kind = 1
	s.client_id = c.id
	s.hold_t = 0
	if not back:
		s.name = c.name if c.name != "Player" else "Player %d" % (s.i + 1)
		s.token = c.token
		s.points = 0
		s.crowns = 0
		s.in_round = false
		s.buttons = 0
		s.aim = 0
	s.queue.clear()
	s.margin_min = P.NO_MARGIN
	s.late_n = 0
	c.seat = s.i
	c.name = s.name
	var f = sim.fighter(s.i)
	if f != null and s.in_round:
		f.bot = false
		f.connected = true
	if back:
		_say("🏰 [JOIN] seat %d '%s' is back from %s (client %d)" % [s.i, s.name, c.ip, c.id])
	else:
		_say("🏰 [JOIN] seat %d '%s' from %s (client %d)%s" % [s.i, s.name, c.ip, c.id,
			" takes a bot's seat, plays from the next round" if was_bot else (" plays from the next round" if phase > P.PH_COUNTDOWN else "")])
	seats_dirty = true

func _free_seat_now(s: Seat) -> void:
	var f = sim.fighter(s.i)
	if f != null:
		f.bot = true
		f.connected = true
	s.kind = 0
	s.name = ""
	s.client_id = 0
	s.token = ""
	s.hold_t = 0
	s.in_round = false
	s.points = 0
	s.crowns = 0
	s.queue.clear()
	seats_dirty = true

func _on_close(c: Conn) -> void:
	if c.seat >= 0:
		var s: Seat = seats[c.seat]
		if s.client_id == c.id:
			s.client_id = 0
			s.hold_t = HOLD_TICKS
			s.queue.clear()
			var f = sim.fighter(s.i)
			if f != null and s.in_round:
				f.bot = true
				f.connected = false
			_say("🏰 [LEAVE] seat %d '%s' (client %d, %s) dropped: held %d s" % [s.i, s.name, c.id, c.ip, HOLD_TICKS / 60])
			seats_dirty = true
	elif c.ok:
		_say("🏰 [LEAVE] watcher '%s' (client %d, %s) left" % [c.name, c.id, c.ip])
	conns.erase(c.id)

# Held seats count down; at 0 the seat is free again.
func _hold_seats() -> void:
	for s in seats:
		if s.kind == 1 and s.client_id == 0 and s.hold_t > 0:
			s.hold_t -= 1
			if s.hold_t == 0:
				_say("🏰 [LEAVE] seat %d '%s' is free again (nobody came back)" % [s.i, s.name])
				_free_seat_now(s)

# An input packet: up to 4 ticks of buttons (proto), each for the server tick it
# carries. A new one goes in the seat's queue for its tick. One whose tick is gone
# (late) or more than MAX_EARLY ahead is applied at once, in order, so a one-tick
# press is never lost. The margin (how many ticks early) goes back in T_OWN.
func _on_input(c: Conn, pkt: PackedByteArray) -> void:
	if c.seat < 0:
		return
	var s: Seat = seats[c.seat]
	var next: int = sim.tick + 1     # the tick the coming step makes
	var n := pkt.size() / 8
	for i in n:
		var off := i * 8
		if pkt[off] != P.T_INPUT:
			continue
		var t := pkt.decode_u32(off + 1)
		if t <= c.last_tick:
			continue
		c.last_tick = t
		var b: int = pkt[off + 5]
		var aim := pkt.decode_u16(off + 6) % 3600
		var margin: int = t - next
		s.margin_min = mini(s.margin_min, margin)
		s.inputs_all += 1
		if margin >= 0 and margin <= MAX_EARLY:
			s.queue[t] = [b, aim]
			continue
		if margin < 0:
			s.late_n += 1
			s.late_all += 1
		s.buttons = b
		s.aim = aim
		s.used = t
		if s.in_round:
			var f = sim.fighter(s.i)
			if f != null and not f.bot:
				sim.apply_input(f, b, aim)
				s.input_tick = sim.tick

# Just before the step: each person's input for this tick from the queue, or the
# held buttons when it has not come (it is applied when it comes, see _on_input),
# so a late packet never drops the jump height or the aim.
func _apply_inputs() -> void:
	var t: int = sim.tick + 1
	for s in seats:
		if s.kind != 1 or s.client_id == 0:
			continue
		var q = s.queue.get(t)
		if q != null:
			s.queue.erase(t)
			s.buttons = q[0]
			s.aim = q[1]
			s.used = t
		if s.queue.size() > MAX_EARLY + 8:
			s.queue.clear()   # only a client whose clock jumped back leaves old ticks here
		if not s.in_round:
			continue
		var f = sim.fighter(s.i)
		if f != null and not f.bot and (q != null or s.input_tick != sim.tick):
			sim.apply_input(f, s.buttons, s.aim)

# After each snapshot, each seated person's T_OWN (proto.gd): the tick, the newest
# input used, the margin and the late count since the last one, the first tick the
# fighters move after ROUND START, and their fighter's whole state.
func _send_own() -> void:
	for s in seats:
		if s.kind != 1 or s.client_id == 0:
			continue
		var f = sim.fighter(s.i) if s.in_round else null
		own_buf.clear()
		own_buf.put_u8(P.T_OWN)
		own_buf.put_u32(sim.tick)
		own_buf.put_u32(s.used)
		own_buf.put_8(clampi(s.margin_min, -128, 127))
		own_buf.put_u8(mini(s.late_n, 255))
		own_buf.put_u8((P.OWN_FIGHTER if f != null else 0) | (P.OWN_BRAIN if f != null and f.bot else 0))
		own_buf.put_u32(sim.tick + phase_t if phase == P.PH_ROUND_START else 0)
		if f != null:
			sim.write_fighter_state(own_buf, f)
		_out(s.client_id, own_buf.data_array)
		s.margin_min = P.NO_MARGIN
		s.late_n = 0

# ------------------------------------------------------------------ the match
func _match_tick() -> void:
	if phase == P.PH_LOBBY and soak and _people() + _bots_now() >= 2:
		phase = P.PH_COUNTDOWN
		phase_t = COUNTDOWN_TICKS
		_say("🏰 [LOBBY] soak: the next match starts in %d s" % (COUNTDOWN_TICKS / 60))
		seats_dirty = true
	if phase == P.PH_COUNTDOWN:
		phase_t -= 1
		if _people() + _bots_now() < 2:
			_say("🏰 [LOBBY] countdown stopped: not enough fighters")
			phase = P.PH_LOBBY
			seats_dirty = true
		elif phase_t <= 0:
			_begin_match()
	elif phase == P.PH_ROUND_START:
		phase_t -= 1
		if phase_t <= 0:
			sim.frozen = false
			phase = P.PH_PLAY
			phase_t = 0
			_say("🏰 [ROUND] %d FIGHT" % round_no)
	elif phase == P.PH_PLAY:
		phase_t += 1
		var alive: int = sim.alive_count()
		if alive <= 1 or phase_t >= ROUND_MAX_TICKS:
			var draw := alive != 1
			winner = P.NO_ONE if draw else sim.last_alive().id
			phase = P.PH_ROUND_END
			phase_t = DRAW_TICKS if draw else ROUND_END_TICKS
			var msg := {"kind": "round_end", "round": round_no, "winner": winner, "draw": draw,
				"name": "" if draw else seats[winner].name, "points": _points()}
			_out(0, JSON.stringify(msg))
			if draw:
				_say("🏰 [ROUND] %d end after %.1f s: a draw (%d alive)" % [round_no, _round_secs(), alive])
			else:
				_say("🏰 [ROUND] %d end after %.1f s: seat %d '%s' is the last one standing" % [round_no, _round_secs(), winner, seats[winner].name])
			server_log.store_line(JSON.stringify({"kind": "round", "t": Time.get_unix_time_from_system(), "match": match_no,
				"round": round_no, "arena": sim.level.id, "secs": snappedf(_round_secs(), 0.01), "winner": winner, "draw": draw,
				"fighters": sim.fighters.size(), "people": _people(), "bot_level": sim.bot_level, "deaths": round_deaths,
				"names": _seat_names()}))
			server_log.flush()
			for s in seats:
				if s.kind != 0 and (s.in_round or (not draw and s.i == winner)):
					var r := _stat(s)
					r["rounds"] += 1
					if not draw and s.i == winner:
						r["round_wins"] += 1
			_save_stats()
	elif phase == P.PH_ROUND_END:
		phase_t -= 1
		if phase_t <= 0:
			if winner != P.NO_ONE:
				seats[winner].points += 1
				_sync_points()
			if winner != P.NO_ONE and seats[winner].points >= goal:
				seats[winner].crowns += 1
				if seats[winner].kind != 0:
					var rw := _stat(seats[winner])
					rw["match_wins"] += 1
					_save_stats()
				phase = P.PH_MATCH_END
				phase_t = MATCH_END_TICKS
				_out(0, JSON.stringify({"kind": "match_end", "winner": winner, "name": seats[winner].name, "points": _points()}))
				_say("🏰 [MATCH] end after %d rounds: seat %d '%s' wins %s" % [round_no, winner, seats[winner].name, _score_line()])
				server_log.store_line(JSON.stringify({"kind": "match", "t": Time.get_unix_time_from_system(), "match": match_no,
					"rounds": round_no, "winner": winner, "people": _people(), "bot_level": sim.bot_level}))
				server_log.flush()
				seats_dirty = true
			elif _people() + _bots_now() < 2:
				_stop_match()
			else:
				round_no += 1
				_start_round()
	elif phase == P.PH_MATCH_END:
		phase_t -= 1
		if phase_t <= 0:
			_to_lobby()

var _round_start_tick := 0
func _round_secs() -> float:
	return (sim.tick - _round_start_tick) / 60.0

func _begin_match() -> void:
	match_no += 1
	for s in seats:
		s.points = 0
	round_no = 1
	var n := _people() + _bots_now()
	goal = goal_override if goal_override > 0 else _goal_for(n)
	_say("🏰 [MATCH] start: %d people + %d bots (%s), first to %d points" % [_people(), _bots_now(), SimScript.BrainScript.NAMES[sim.bot_level], goal])
	_start_round()

# The arena of the next round: the pick, or MIX's next one (G5).
func _next_arena() -> int:
	if arena_pick == P.ARENA_MIX:
		var play: Array = SimScript.LevelScript.PLAY
		return play[mix_i % play.size()]
	return arena_pick

static func _arena_label(n: int) -> String:
	return "MIX" if n == P.ARENA_MIX else SimScript.LevelScript.name_of(n)

# --arena: mix, a layout number, or a layout's name without THE (keep, bridges, bench).
static func _arena_arg(v: String) -> int:
	if v.is_valid_int():
		return clampi(int(v), 0, SimScript.LevelScript.count() - 1)
	for n in SimScript.LevelScript.count():
		if SimScript.LevelScript.name_of(n).to_lower().trim_prefix("the ") == v.to_lower():
			return n
	return P.ARENA_MIX

# TowerFall's points to win: 5, 4, 3 for 2, 3, 4 players; 3 for more.
static func _goal_for(n: int) -> int:
	if n <= 2:
		return 5
	if n == 3:
		return 4
	return 3

# Bots take the lowest empty seats, as many as wanted and fit; then every seated
# person and bot gets a fighter.
func _start_round() -> void:
	for s in seats:
		if s.kind == 2:
			s.kind = 0
	var to_place := _bots_now()
	for s in seats:
		if to_place > 0 and s.kind == 0:
			s.kind = 2
			s.name = "BOT %d" % (s.i + 1)
			s.points = s.points if round_no > 1 else 0
			to_place -= 1
	var seat_list: Array = []
	for s in seats:
		s.in_round = s.kind != 0
		if s.in_round:
			seat_list.append({"id": s.i, "bot": s.kind == 2 or s.client_id == 0})
			var r := _stat(s)
			if r.get("_m", 0) != match_no:   # this server's match number, kept in memory only
				r["_m"] = match_no
				r["matches"] += 1
	sim.set_arena(_next_arena())
	if arena_pick == P.ARENA_MIX:
		mix_i += 1
	sim.start_round(seat_list)
	round_deaths = []
	for s in seats:
		var f = sim.fighter(s.i)
		if f != null:
			f.connected = not (s.kind == 1 and s.client_id == 0)
			f.buttons = 0
	_sync_points()
	sim.frozen = true
	winner = P.NO_ONE
	phase = P.PH_ROUND_START
	phase_t = ROUND_START_TICKS
	_round_start_tick = sim.tick + ROUND_START_TICKS
	_say("🏰 [ROUND] %d start on %s: %d fighters (%d people, %d bots) %s" % [round_no, sim.level.name, seat_list.size(), _people(), _bots_now(), _score_line()])
	seats_dirty = true

# Fewer than 2 fighters for the next round (people left, no bots fill in):
# nobody wins the match, everyone goes back to the lobby (backlog 35).
func _stop_match() -> void:
	var n := _people() + _bots_now()
	_say("🏰 [MATCH] stopped after %d round%s: %d fighter%s left %s" % [round_no, "" if round_no == 1 else "s", n, "" if n == 1 else "s", _score_line()])
	_out(0, JSON.stringify({"kind": "note", "text": "The match stopped: a match needs 2 fighters."}))
	_to_lobby()

func _to_lobby() -> void:
	sim.clear()
	sim.frozen = false
	for s in seats:
		if s.kind == 2:
			s.kind = 0
			s.name = ""
		s.in_round = false
	phase = P.PH_LOBBY
	phase_t = 0
	round_no = 0
	winner = P.NO_ONE
	sim.set_arena(_next_arena())
	_say("🏰 [LOBBY] back in the lobby: %d people seated" % _people())
	seats_dirty = true

func _sync_points() -> void:
	for s in seats:
		var f = sim.fighter(s.i)
		if f != null:
			f.points = s.points

func _points() -> Array:
	var out: Array = []
	for s in seats:
		out.append(s.points)
	return out

func _score_line() -> String:
	var parts: Array = []
	for s in seats:
		if s.kind != 0:
			parts.append("%s %d" % [s.name, s.points])
	return "(" + ", ".join(parts) + ")"

func _log_deaths(evs: Array) -> void:
	for e in evs:
		if e[0] != P.E_DEATH:
			continue
		var victim: int = e[3]
		var f = sim.fighter(victim)
		var killer: int = f.killer if f != null else 255
		var cause: String = P.CAUSES.get(e[4], str(e[4]))
		var vn: String = seats[victim].name if victim < SEATS else "?"
		var when := _round_secs()
		round_deaths.append([victim, killer, e[4], e[1], e[2], snappedf(when, 0.01)])
		if victim < SEATS and seats[victim].kind != 0:
			var rv := _stat(seats[victim])
			rv["deaths"] += 1
			if killer == victim:
				rv["self_kills"] += 1
		if killer < SEATS and killer != victim and seats[killer].kind != 0:
			var rk := _stat(seats[killer])
			rk["kills"] += 1
			if e[4] == 1:
				rk["arrow_kills"] += 1
			elif e[4] == 3:
				rk["stomp_kills"] += 1
			else:
				rk["other_kills"] += 1
		if killer == victim:
			_say("🏰 [KILL] seat %d '%s' killed themselves (%s) %.2f s after FIGHT, %d left" % [victim, vn, cause, when, sim.alive_count()])
		elif killer < SEATS:
			_say("🏰 [KILL] seat %d '%s' killed seat %d '%s' (%s) %.2f s after FIGHT, %d left" % [killer, seats[killer].name, victim, vn, cause, when, sim.alive_count()])
		else:
			_say("🏰 [KILL] seat %d '%s' died (%s) %.2f s after FIGHT, %d left" % [victim, vn, cause, when, sim.alive_count()])

# The seat list, to one client (id) or to all (0).
func _send_seats(target: int) -> void:
	var list: Array = []
	for s in seats:
		list.append({"i": s.i, "name": s.name, "kind": s.kind, "on": s.kind == 2 or s.client_id != 0,
			"points": s.points, "crowns": s.crowns, "in": s.in_round})
	var msg := {"kind": "seats", "phase": phase, "round": round_no, "goal": goal if goal > 0 else (goal_override if goal_override > 0 else _goal_for(_people() + _bots_now())),
		"bots": _bots_now(), "bots_wanted": bots_wanted, "bot_level": sim.bot_level, "power": 1 if sim.power_arrows else 0,
		"people": _people(), "arena": arena_pick, "arena_now": sim.level.id,
		"seats": list}
	_out(target, JSON.stringify(msg))
	if target == 0:
		seats_dirty = false

# ------------------------------------------------------------------ network
func _out(target: int, data) -> void:
	if net_thread_on:
		net_mutex.lock()
		net_out.append([target, data])
		net_tick = sim.tick   # what a pong reports
		net_mutex.unlock()
	else:
		_deliver(target, data)

func _deliver(target: int, data) -> void:
	for c in clients:
		if c.state != 1 or (target != 0 and c.id != target):
			continue
		if c.ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
			continue
		var err: int
		if data is String:
			err = c.ws.send_text(data)
		else:
			err = c.ws.put_packet(data)
		if err == OK:
			var n: int = data.length() if data is String else data.size()
			c.bytes_out += n
			bytes_out_sec += n
		else:
			c.send_fail += 1
		if target != 0:
			return

func _accept() -> void:
	while server.is_connection_available():
		var tcp := server.take_connection()
		tcp.set_no_delay(true)
		var c := Client.new()
		c.id = next_client_id
		next_client_id += 1
		c.ip = tcp.get_connected_host()
		c.tcp = tcp
		c.since_ms = Time.get_ticks_msec()
		if tls_opts != null:
			c.tls = StreamPeerTLS.new()
			if c.tls.accept_stream(tcp, tls_opts) != OK:
				print("🏰 [NET] TLS accept failed from %s" % c.ip)
				continue
			c.state = 0
		else:
			_start_ws(c, tcp)
		clients.append(c)

func _start_ws(c: Client, stream: StreamPeer) -> void:
	c.ws = WebSocketPeer.new()
	c.ws.outbound_buffer_size = 1 << 20
	c.ws.inbound_buffer_size = 1 << 16
	c.ws.max_queued_packets = 4096
	c.ws.accept_stream(stream)
	c.state = 1

func _inbox(kind: String, id: int, payload) -> void:
	if net_thread_on:
		net_mutex.lock()
		net_in.append([kind, id, payload])
		net_mutex.unlock()
	else:
		net_in.append([kind, id, payload])

func _poll_clients() -> void:
	var now := Time.get_ticks_msec()
	for i in range(clients.size() - 1, -1, -1):
		var c: Client = clients[i]
		if c.state == 0:
			c.tls.poll()
			var st := c.tls.get_status()
			if st == StreamPeerTLS.STATUS_CONNECTED:
				_start_ws(c, c.tls)
			elif st != StreamPeerTLS.STATUS_HANDSHAKING or now - c.since_ms > 5000:
				print("🏰 [NET] TLS handshake failed from %s (status %d)" % [c.ip, st])
				clients.remove_at(i)
			continue
		c.ws.poll()
		var rs := c.ws.get_ready_state()
		if rs == WebSocketPeer.STATE_CLOSED:
			if c.opened:
				_inbox("close", c.id, c.ws.get_close_code())
			clients.remove_at(i)
			continue
		if rs != WebSocketPeer.STATE_OPEN:
			if now - c.since_ms > 8000:
				print("🏰 [NET] client %d (%s) never finished the websocket handshake" % [c.id, c.ip])
				clients.remove_at(i)
			continue
		if not c.opened:
			c.opened = true
			_inbox("open", c.id, c.ip)
		while c.ws.get_available_packet_count() > 0:
			var pkt := c.ws.get_packet()
			c.bytes_in += pkt.size()
			bytes_in_sec += pkt.size()
			if c.ws.was_string_packet():
				_inbox("text", c.id, pkt.get_string_from_utf8())
			elif pkt.size() > 0:
				_on_binary(c, pkt)

func _on_binary(c: Client, pkt: PackedByteArray) -> void:
	if pkt[0] == P.T_INPUT:
		_inbox("input", c.id, pkt)
	elif pkt[0] == P.T_PING and pkt.size() >= 9:
		c.rtt = pkt.decode_u16(5)
		c.gap = pkt.decode_u16(7)
		var out := PackedByteArray()
		out.resize(9)
		out[0] = P.T_PONG
		out.encode_u32(1, pkt.decode_u32(1))
		out.encode_u32(5, _pong_tick())
		c.ws.put_packet(out)
		c.bytes_out += 9
		bytes_out_sec += 9

func _pong_tick() -> int:
	if not net_thread_on:
		return sim.tick
	net_mutex.lock()
	var t := net_tick
	net_mutex.unlock()
	return t

func _client_list() -> Array:
	var out: Array = []
	for c in clients:
		if c.state == 1:
			out.append({"id": c.id, "ip": c.ip, "rtt": c.rtt, "gap": c.gap, "fail": c.send_fail})
	return out

# The network thread: owns the listening socket and every client. The sim thread
# only hands over finished snapshots and texts, and reads what came in.
func _net_loop() -> void:
	var last_pub := 0
	while true:
		net_mutex.lock()
		var quit := net_quit
		var outs: Array = net_out
		net_out = []
		net_mutex.unlock()
		if quit:
			break
		var t0 := Time.get_ticks_usec()
		_accept()
		_poll_clients()
		for o in outs:
			_deliver(o[0], o[1])
		var busy := Time.get_ticks_usec() - t0
		var now := Time.get_ticks_msec()
		net_mutex.lock()
		net_busy_pub += busy
		net_out_pub += bytes_out_sec
		net_in_pub += bytes_in_sec
		if now - last_pub >= 200:
			net_per_client = _client_list()
			last_pub = now
		net_mutex.unlock()
		bytes_out_sec = 0
		bytes_in_sec = 0
		OS.delay_usec(net_sleep_us)

func _stop_net() -> void:
	if net_thread == null:
		return
	net_mutex.lock()
	net_quit = true
	net_mutex.unlock()
	net_thread.wait_to_finish()
	net_thread = null

func _exit_tree() -> void:
	_stop_net()

# ------------------------------------------------------------------ the report
func _report() -> void:
	var now := Time.get_ticks_msec()
	var secs := (now - sec_start_ms) / 1000.0
	sec_start_ms = now
	var n := tick_us.size()
	var sorted := tick_us.duplicate()
	sorted.sort()
	var total := 0
	for v in tick_us:
		total += v
	var iv := interval_us.duplicate()
	iv.sort()
	var cpu := _cpu_percent(now)
	var per_client: Array
	var out_b := bytes_out_sec
	var in_b := bytes_in_sec
	var net_busy := 0
	if net_thread_on:
		net_mutex.lock()
		per_client = net_per_client.duplicate(true)
		out_b = net_out_pub
		in_b = net_in_pub
		net_busy = net_busy_pub
		net_out_pub = 0
		net_in_pub = 0
		net_busy_pub = 0
		net_mutex.unlock()
	else:
		per_client = _client_list()
	var inputs: Array = []   # [seat, inputs, late] for each person since the last report
	for st in seats:
		if st.kind == 1 and st.inputs_all > 0:
			inputs.append([st.i, st.inputs_all, st.late_all])
		st.inputs_all = 0
		st.late_all = 0
	var rec := {
		"kind": "report", "t": Time.get_unix_time_from_system(), "up_s": (now - started_ms) / 1000.0,
		"clients": per_client.size(), "people": _people(), "bots": _bots_now(), "phase": phase, "round": round_no,
		"arena": sim.level.id, "fighters": sim.fighters.size(), "arrows": sim.live_arrow_count(), "zones": sim.zones.size(),
		"ticks": n, "tick_mean_ms": (total / 1000.0 / n) if n > 0 else 0.0,
		"tick_p99_ms": (sorted[int(n * 0.99)] / 1000.0) if n > 0 else 0.0,
		"tick_max_ms": (sorted[n - 1] / 1000.0) if n > 0 else 0.0,
		"sim_mean_ms": (sim_us_sum / 1000.0 / n) if n > 0 else 0.0,
		"interval_p99_ms": (iv[int(iv.size() * 0.99)] / 1000.0) if iv.size() > 0 else 0.0,
		"interval_max_ms": (iv[iv.size() - 1] / 1000.0) if iv.size() > 0 else 0.0,
		"out_kbps": out_b / 1000.0 / secs, "in_kbps": in_b / 1000.0 / secs,
		"net_busy_ms": net_busy / 1000.0 / secs, "cpu_pct": cpu, "rss_mb": _rss_mb(), "per_client": per_client,
		"inputs": inputs,
	}
	server_log.store_line(JSON.stringify(rec))
	server_log.flush()
	last_rec = rec
	if not quiet:
		var rtts: Array = []
		for pc in per_client:
			rtts.append("%d:%d" % [pc["id"], pc["rtt"]])
		var lates: Array = []
		for v in inputs:
			lates.append("%d:%d/%d" % v)
		print("📊 [Server %4.0fs] clients=%d people=%d bots=%d phase=%d round=%d fighters=%d arrows=%d | tick mean %.2f p99 %.2f max %.2f ms (sim %.2f) | interval p99 %.1f max %.1f ms | out %.1f KB/s in %.1f KB/s | net %.1f ms/s | cpu %.1f%% rss %.0f MB | rtt %s | late %s" % [
			rec["up_s"], rec["clients"], rec["people"], rec["bots"], phase, round_no, rec["fighters"], rec["arrows"],
			rec["tick_mean_ms"], rec["tick_p99_ms"], rec["tick_max_ms"], rec["sim_mean_ms"],
			rec["interval_p99_ms"], rec["interval_max_ms"], rec["out_kbps"], rec["in_kbps"], rec["net_busy_ms"], cpu, rec["rss_mb"], " ".join(rtts), " ".join(lates)])
	tick_us.clear()
	interval_us.clear()
	sim_us_sum = 0
	if not net_thread_on:
		bytes_out_sec = 0
		bytes_in_sec = 0

func _cpu_percent(now_ms: int) -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return -1.0
	var s := f.get_line()   # /proc files report length 0, so read by line
	var fields := s.substr(s.rfind(")") + 2).split(" ")
	if fields.size() < 13:
		return -1.0
	var ticks := float(fields[11]) + float(fields[12])
	var pct := -1.0
	if cpu_last >= 0.0 and now_ms > cpu_last_ms:
		pct = (ticks - cpu_last) / 100.0 / ((now_ms - cpu_last_ms) / 1000.0) * 100.0
	cpu_last = ticks
	cpu_last_ms = now_ms
	return pct

func _rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f == null:
		return -1.0
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("VmRSS:"):
			return float(line.split(":")[1].strip_edges().split(" ")[0]) / 1024.0
	return -1.0

func _cpu_model() -> String:
	var f := FileAccess.open("/proc/cpuinfo", FileAccess.READ)
	if f == null:
		return "?"
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("model name"):
			return line.split(":")[1].strip_edges()
	return "?"

# ------------------------------------------------------------------ the host port (p4.2)
# A tagged line: printed, and kept for the host page's recent events.
func _say(line: String) -> void:
	print(line)
	var tag := ""
	var text := line
	var a := line.find("[")
	var b := line.find("]", a + 1)
	if a >= 0 and b > a:
		tag = line.substr(a + 1, b - a - 1)
		text = line.substr(b + 1).strip_edges()
	events_ring.append({"t": Time.get_unix_time_from_system(), "hhmm": Time.get_time_string_from_system().substr(0, 5),
		"tag": tag, "text": text})
	if events_ring.size() > EVENTS_MAX:
		events_ring.pop_front()

func _seat_names() -> Array:
	var out: Array = []
	for s in seats:
		out.append(s.name)
	return out

# The players' numbers tonight, by name (a bot's as "bot:" + its name).
func _stat(s: Seat) -> Dictionary:
	var bot := s.kind == 2
	var key := ("bot:" if bot else "") + s.name
	if not stats.has(key):
		var r := {"name": s.name, "bot": bot}
		for k in STAT_KEYS:
			r[k] = 0
		stats[key] = r
	return stats[key]

func _count_events(evs: Array) -> void:
	for e in evs:
		var k: int = e[0]
		if k != P.E_SHOOT and k != P.E_CATCH:
			continue
		var i: int = e[3]
		if i < 0 or i >= SEATS or seats[i].kind == 0:
			continue
		var r := _stat(seats[i])
		if k == P.E_SHOOT:
			r["shots"] += 1
		else:
			r["catches"] += 1

func _save_stats() -> void:
	if stats_path == "":
		return
	var f := FileAccess.open(stats_path, FileAccess.WRITE)
	if f == null:
		return
	var rows: Array = []
	for r in stats.values():
		var row: Dictionary = r.duplicate()
		row.erase("_m")
		rows.append(row)
	f.store_string(JSON.stringify({"since": stats_since, "players": rows}))
	f.close()

# Tonight's numbers come back when the server starts again the same day.
func _load_stats(path: String) -> void:
	stats_path = path
	stats_since = Time.get_unix_time_from_system()
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(d) != TYPE_DICTIONARY:
		return
	stats_since = float(d.get("since", stats_since))
	for r in d.get("players", []):
		if typeof(r) != TYPE_DICTIONARY or not r.has("name"):
			continue
		var rec := {"name": str(r["name"]), "bot": bool(r.get("bot", false))}
		for k in STAT_KEYS:
			rec[k] = int(r.get(k, 0))
		stats[("bot:" if rec["bot"] else "") + rec["name"]] = rec

# One request a connection, answered on this thread (it owns the seats), then closed.
func _host_poll() -> void:
	while host.is_connection_available():
		var t := host.take_connection()
		if host_conns.size() >= 8:
			t.disconnect_from_host()
			continue
		var h := HostConn.new()
		h.tcp = t
		h.ms = Time.get_ticks_msec()
		host_conns.append(h)
	if host_conns.is_empty():
		return
	var keep: Array = []
	for h in host_conns:
		h.tcp.poll()
		if h.tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var n: int = h.tcp.get_available_bytes()
		if n > 0:
			var got: Array = h.tcp.get_partial_data(n)
			if got[0] == OK:
				h.buf = h.buf + got[1]
		if _host_try(h):
			continue
		if Time.get_ticks_msec() - h.ms > 3000 or h.buf.size() > HOST_MAX:
			h.tcp.disconnect_from_host()
			continue
		keep.append(h)
	host_conns = keep

# true: answered (the connection is closed); false: the request is not all here yet.
func _host_try(h: HostConn) -> bool:
	var head := h.buf.get_string_from_ascii()
	var end := head.find("\r\n\r\n")
	if end < 0:
		return false
	var lines := head.substr(0, end).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 2:
		_host_reply(h.tcp, 400, {"ok": false, "text": "Not an http request."})
		return true
	var length := 0
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon > 0 and lines[i].substr(0, colon).strip_edges().to_lower() == "content-length":
			length = int(lines[i].substr(colon + 1).strip_edges())
	if length > HOST_MAX:
		_host_reply(h.tcp, 400, {"ok": false, "text": "Too big."})
		return true
	if h.buf.size() < end + 4 + length:
		return false
	var body := {}
	if length > 0:
		var parsed = JSON.parse_string(h.buf.slice(end + 4, end + 4 + length).get_string_from_utf8())
		if typeof(parsed) == TYPE_DICTIONARY:
			body = parsed
	var method := first[0]
	var path := first[1].get_slice("?", 0)
	if method == "GET" and (path == "/state" or path == "/"):
		_host_reply(h.tcp, 200, _host_state())
	elif method == "POST":
		var r: Array = _host_cmd(path.trim_prefix("/"), body)
		var code := 200 if r[0] else (404 if str(r[1]).begins_with("Unknown") else 400)
		_host_reply(h.tcp, code, {"ok": r[0], "text": r[1], "state": _host_state()})
	else:
		_host_reply(h.tcp, 404, {"ok": false, "text": "Unknown: %s %s" % [method, path]})
	return true

func _host_reply(t: StreamPeerTCP, code: int, data: Dictionary) -> void:
	var body := JSON.stringify(data).to_utf8_buffer()
	var reason: String = {200: "OK", 400: "Bad Request", 404: "Not Found"}.get(code, "Error")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % [code, reason, body.size()]
	t.put_data(head.to_ascii_buffer() + body)
	t.disconnect_from_host()

# The commands: any time; a bots, level or arena change made in a match counts from the next round.
func _host_cmd(cmd: String, d: Dictionary) -> Array:
	var in_match := phase != P.PH_LOBBY and phase != P.PH_COUNTDOWN
	var later := " from the next round" if in_match else ""
	match cmd:
		"bots":
			var n := clampi(int(d.get("n", bots_wanted)), 0, MAX_BOTS)
			bots_wanted = n
			seats_dirty = true
			_say("🏰 [HOST] bots %d%s" % [n, later])
			return [true, "Bots: %d%s." % [n, later]]
		"bot_level":
			var lv := int(d.get("n", -1))
			if lv < SimScript.BrainScript.EASY or lv > SimScript.BrainScript.HARD:
				return [false, "The bots' level is 1 (EASY), 2 (NORMAL) or 3 (HARD)."]
			sim.bot_level = lv
			seats_dirty = true
			_say("🏰 [HOST] bots %s%s" % [SimScript.BrainScript.NAMES[lv], later])
			return [true, "Bots %s%s." % [SimScript.BrainScript.NAMES[lv], later]]
		"arena":
			var n := int(d.get("n", -99))
			if n != P.ARENA_MIX and not SimScript.LevelScript.PLAY.has(n):
				return [false, "No arena %d." % n]
			arena_pick = n
			if not in_match:
				sim.set_arena(_next_arena())
			seats_dirty = true
			_say("🏰 [HOST] arena %s%s" % [_arena_label(n), later])
			return [true, "Arena %s%s." % [_arena_label(n), later]]
		"kick":
			var i := int(d.get("seat", -1))
			if i < 0 or i >= SEATS or seats[i].kind != 1:
				return [false, "Seat %d has no person in it." % i]
			var s: Seat = seats[i]
			var who := s.name
			var cid := s.client_id
			_free_seat_now(s)
			if cid != 0 and conns.has(cid):
				var c: Conn = conns[cid]
				c.seat = -1
				_out(cid, JSON.stringify({"kind": "welcome", "seat": -1, "version": P.VERSION, "name": c.name, "phase": phase}))
				_out(cid, JSON.stringify({"kind": "note", "text": "The host took your seat. Press JOIN to play again."}))
			_say("🏰 [HOST] kicked seat %d '%s': back to watching" % [i, who])
			return [true, "%s is back to watching." % who]
		"power":
			sim.power_arrows = int(d.get("n", 0)) != 0
			seats_dirty = true
			_say("🏰 [HOST] power arrows %s" % ("ON" if sim.power_arrows else "OFF"))
			return [true, "Power arrows %s, from the next shot." % ("ON" if sim.power_arrows else "OFF")]
		"start":
			if phase != P.PH_LOBBY:
				return [false, "A match is already on."]
			if _people() + _bots_now() < 2:
				return [false, "A match needs 2 fighters: add a bot."]
			phase = P.PH_COUNTDOWN
			phase_t = COUNTDOWN_TICKS
			seats_dirty = true
			_say("🏰 [LOBBY] START by the host: %d people + %d bots" % [_people(), _bots_now()])
			return [true, "The match starts in %d s." % (COUNTDOWN_TICKS / 60)]
		"stop":
			if phase == P.PH_LOBBY:
				return [false, "No match to end: the lobby is open."]
			_say("🏰 [HOST] ended the match in round %d %s" % [round_no, _score_line()])
			_out(0, JSON.stringify({"kind": "note", "text": "The host ended the match."}))
			_to_lobby()
			return [true, "The match ended: back to the lobby."]
	return [false, "Unknown command: %s" % cmd]

# The addresses phones on this network use (no loopback, Tailscale or Docker ones).
func _lan_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10."):
			out.append(a)
	out.sort()
	return out

func _host_state() -> Dictionary:
	var pings := {}
	var per: Array
	if net_thread_on:
		net_mutex.lock()
		per = net_per_client.duplicate(true)
		net_mutex.unlock()
	else:
		per = _client_list()
	for pc in per:
		pings[int(pc["id"])] = int(pc["rtt"])
	var seat_list: Array = []
	for s in seats:
		var c: Conn = conns.get(s.client_id) if s.client_id != 0 else null
		var held: bool = s.kind == 1 and s.client_id == 0
		seat_list.append({"i": s.i, "name": s.name, "kind": s.kind, "who": ["empty", "person", "bot"][s.kind],
			"online": s.kind == 2 or s.client_id != 0, "held_s": ceili(s.hold_t / 60.0) if held else 0,
			"points": s.points, "crowns": s.crowns, "in_round": s.in_round,
			"ip": c.ip if c != null else "", "ping_ms": pings.get(s.client_id, -1), "client": s.client_id})
	var watching: Array = []
	for id in conns:
		var c: Conn = conns[id]
		if c.ok and c.seat < 0:
			watching.append({"client": c.id, "name": c.name, "ip": c.ip, "ping_ms": pings.get(c.id, -1)})
	var arenas: Array = [{"n": P.ARENA_MIX, "name": "MIX"}]
	for n in SimScript.LevelScript.PLAY:
		arenas.append({"n": n, "name": SimScript.LevelScript.name_of(n)})
	var levels: Array = []
	for lv in range(SimScript.BrainScript.EASY, SimScript.BrainScript.HARD + 1):
		levels.append({"n": lv, "name": SimScript.BrainScript.NAMES[lv]})
	var people_rows: Array = []
	var bot_rows: Array = []
	for k in stats:
		var r: Dictionary = stats[k].duplicate()
		r.erase("_m")
		var shots: int = r["shots"]
		r["hit_pct"] = snappedf(100.0 * r["arrow_kills"] / shots, 0.1) if shots > 0 else 0.0
		r["kd"] = snappedf(float(r["kills"]) / maxi(1, r["deaths"]), 0.01)
		if r["bot"]:
			bot_rows.append(r)
		else:
			people_rows.append(r)
	var by_kills := func(x: Dictionary, y: Dictionary) -> bool:
		return x["kills"] > y["kills"] or (x["kills"] == y["kills"] and str(x["name"]) < str(y["name"]))
	people_rows.sort_custom(by_kills)
	bot_rows.sort_custom(by_kills)
	return {"ok": true, "version": P.VERSION, "t": Time.get_unix_time_from_system(),
		"up_s": (Time.get_ticks_msec() - started_ms) / 1000.0,
		"phase": phase, "phase_name": PHASE_NAMES[phase], "round": round_no,
		"goal": goal if goal > 0 else (goal_override if goal_override > 0 else _goal_for(_people() + _bots_now())),
		"match": match_no, "arena_pick": arena_pick, "arena_pick_name": _arena_label(arena_pick),
		"arena_now": sim.level.id, "arena_now_name": sim.level.name, "arenas": arenas,
		"bots_wanted": bots_wanted, "bots_now": _bots_now(), "max_bots": MAX_BOTS,
		"bot_level": sim.bot_level, "bot_level_name": SimScript.BrainScript.NAMES[sim.bot_level], "levels": levels,
		"power_arrows": sim.power_arrows,
		"people": _people(), "watchers": watching.size(), "lan": _lan_ips(), "page_port": 8443, "game_port": port,
		"seats": seat_list, "watching": watching,
		"tick": {"mean_ms": last_rec.get("tick_mean_ms", 0.0), "max_ms": last_rec.get("tick_max_ms", 0.0),
			"cpu_pct": last_rec.get("cpu_pct", 0.0), "rss_mb": last_rec.get("rss_mb", 0.0)},
		"stats_since": stats_since, "stats": people_rows + bot_rows, "events": events_ring}

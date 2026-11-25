# p4.22 WINTER HATS, proved (the Christmas update: "a hat on every fighter in the seat's
# colour", "Pick your hat ... The server keeps it with your name"). No network and no
# picture: the server is run in here tick by tick (as tools/teams_probe.gd does), and the
# page's parts are run as nodes (as tools/motion_probe.gd does).
#   1. THE SERVER (server/game_server.gd, server/hat_book.gd): a new person starts with the
#      hat of their seat's number; the "hat" message changes your own hat and nothing else;
#      it is refused out of range, for another seat, from a watcher, and in a match; the
#      seats message carries every seat's hat; a name gets its hat back after it leaves and
#      after the server starts again; bots wear their seat's hat; a person who takes a bot's
#      seat or comes back on a new socket keeps theirs; out of the season nothing changes.
#   2. THE PAGE'S COPY (client/hats.gd): it reads the hats from the seats message; out of
#      the season, or with the polish switch "hats" off, there are no hats and no button.
#   3. THE MOTION: the tail lags behind a run, swings back and comes to rest; the dip on a
#      landing; nothing ever leaves its limits, also on a page that draws 2 frames a second.
#   4. THE ARENA: a hat follows its fighter's sprite (place, facing, size, tint), hides with
#      it, pops off on a knockout, comes to rest on a floor, and is back the next round.
#   5. THE LOBBY: a changed hat pops its card; the HAT button asks for the next hat, sits
#      under the fighter, and leaves the card's own tap (TEAMS, the hop) as it was: real
#      taps on the card's free part reach the card, taps on the button reach the button;
#      the button keeps to its card while the card pops, also at 3 frames a second.
#   godot --headless --path bench --script res://tools/hat_probe.gd
# Prints a PASS/FAIL line per check and exits 1 on a fail.
extends SceneTree

const P = preload("res://sim/proto.gd")
const SimScript = preload("res://sim/sim.gd")
const LevelScript = preload("res://sim/level.gd")
const ServerScript = preload("res://server/game_server.gd")
const HatBook = preload("res://server/hat_book.gd")
const Hats = preload("res://client/hats.gd")
const Polish = preload("res://client/polish.gd")
const Season = preload("res://client/season.gd")
const Teams = preload("res://client/teams_view.gd")
const Art = preload("res://client/lobby_art.gd")
const Cards = preload("res://client/lobby_cards.gd")
const Lobby = preload("res://client/lobby.gd")
const World = preload("res://client/world.gd")
const DT := 1.0 / 60.0
const NAMES := ["Ava", "Ben", "Cleo", "Dan", "Eve", "Finn", "Gus", "Hana"]

var fails := 0
var checks := 0

func _check(name: String, ok: bool, detail: String = "") -> void:
	checks += 1
	fails += 0 if ok else 1
	print("%s %s%s" % ["PASS" if ok else "FAIL", name, "" if detail == "" else ": " + detail])

# ------------------------------------------------------------------ helpers (the server)
# A game server with no sockets (tools/teams_probe.gd's way): the probe puts the players'
# messages into its inbox and reads what it sends out of its outbox. Its hats are kept in
# the probe's own folder (dir), never in the real bench_results.
var srv_n := 0
var next_client := 1
var sent: Array = []              # every JSON message the server sent since the last _take: [client id (0: all), message]
var log_dir := ""

func _folder(name: String) -> String:
	var d := ProjectSettings.globalize_path("res://").path_join("../bench_results/hat_probe").path_join(name).simplify_path()
	DirAccess.make_dir_recursive_absolute(d)
	if FileAccess.file_exists(d.path_join("known_hats.json")):
		DirAccess.remove_absolute(d.path_join("known_hats.json"))
	return d

func _server(bots: int, season: String, dir: String):
	var srv = ServerScript.new()
	srv_n += 1
	if log_dir == "":
		log_dir = _folder("logs")
	srv.quiet = true
	srv.sim = SimScript.new(0, 24, 300 + srv_n)
	srv.sim.respawn = false
	srv.sim.powerups = false          # nothing falls from the sky: the probe decides who is knocked out
	srv.sim.walls_start = 0
	srv.season_pick = season if season != "" else "off"
	srv.sim.season = season
	srv.arena_pick = 0                # the bench arena
	srv.sim.set_arena(0)
	srv.bots_wanted = bots
	srv.server_log = FileAccess.open(log_dir.path_join("server_%d.jsonl" % srv_n), FileAccess.WRITE)
	for i in 8:
		var s = ServerScript.Seat.new()
		s.i = i
		srv.seats.append(s)
	srv.started_ms = Time.get_ticks_msec()
	srv.sec_start_ms = srv.started_ms
	if dir != "":
		srv.hat_book.load_from(dir)   # (as _ready does with the folder known_names.json is in)
	sent.clear()
	return srv

func _tick(srv, n: int = 1) -> void:
	for i in n:
		srv._physics_process(0.0)
		for o in srv.net_out:
			if o[1] is String:
				sent.append([o[0], JSON.parse_string(o[1])])
		srv.net_out.clear()

# A page opens and says hello (token: its browser's own); join: it takes a seat too.
func _open(srv, name: String, join: bool = true, token: String = "") -> int:
	var id := next_client
	next_client += 1
	srv.net_in.append(["open", id, "10.0.0.%d" % id])
	srv.net_in.append(["text", id, JSON.stringify({"kind": "hello", "name": name, "version": P.VERSION, "token": token if token != "" else "probe%d" % id})])
	if join:
		srv.net_in.append(["text", id, JSON.stringify({"kind": "join", "name": name})])
	_tick(srv)
	return id

func _send(srv, id: int, d: Dictionary) -> void:
	srv.net_in.append(["text", id, JSON.stringify(d)])
	_tick(srv)

# The newest seats message the server sent to everyone since the last call ({}: none).
func _seats_msg() -> Dictionary:
	var out := {}
	for m in sent:
		if int(m[0]) == 0 and typeof(m[1]) == TYPE_DICTIONARY and str(m[1].get("kind", "")) == "seats":
			out = m[1]
	sent.clear()
	return out

# The hats a seats message carries, seat by seat (-1: that seat has none).
func _msg_hats(m: Dictionary) -> Array:
	var out: Array = []
	for st in m.get("seats", []):
		out.append(int(st.get("hat", -1)))
	return out

func _own_hats(srv) -> Array:
	var out: Array = []
	for s in srv.seats:
		out.append(s.hat if s.kind == 1 else -1)
	return out

func _start(srv, id: int) -> void:
	_send(srv, id, {"kind": "start"})
	_tick(srv, ServerScript.COUNTDOWN_TICKS + ServerScript.ROUND_START_TICKS + 2)

# ------------------------------------------------------------------ 1. the server
func _server_checks() -> void:
	var dir := _folder("book")
	# eight new people: each starts with the hat of their seat's number
	var srv = _server(0, "christmas", dir)
	var ids: Array = []
	for nm in NAMES:
		ids.append(_open(srv, nm))
	var m := _seats_msg()
	_check("a new person starts with the hat of their seat's number (8 people, 6 hats: a mix)",
		_own_hats(srv) == [0, 1, 2, 3, 4, 5, 0, 1] and _msg_hats(m) == [0, 1, 2, 3, 4, 5, 0, 1],
		"the server has %s, the seats message says %s" % [str(_own_hats(srv)), str(_msg_hats(m))])
	# the HAT button: your own hat changes, nobody else's, and everyone is told
	_send(srv, ids[0], {"kind": "hat", "hat": 4})
	m = _seats_msg()
	_check("the \"hat\" message puts that hat on your own seat, and the next seats message says so to everyone",
		_own_hats(srv) == [4, 1, 2, 3, 4, 5, 0, 1] and _msg_hats(m) == [4, 1, 2, 3, 4, 5, 0, 1], "now %s" % str(_msg_hats(m)))
	# refused: not a hat's number
	var before := _own_hats(srv)
	var junk: Array = [-1, 6, 99, 1000000000, -7.5, "x", "", null, [], {}, [3], {"hat": 3}]
	for v in junk:
		_send(srv, ids[1], {"kind": "hat", "hat": v})
	_send(srv, ids[1], {"kind": "hat"})
	_check("a hat that is no hat's number is refused (%d tries: -1, 6, 99, words, lists, nothing)" % (junk.size() + 1),
		_own_hats(srv) == before and _seats_msg().is_empty(), "the hats stay %s, no seats message goes out" % str(_own_hats(srv)))
	# refused: another seat's hat, and a watcher's
	_send(srv, ids[1], {"kind": "hat", "hat": 3, "seat": 0})
	_send(srv, ids[1], {"kind": "hat", "hat": 3, "seat": 5})
	var other_ok: bool = _own_hats(srv) == before
	_send(srv, ids[1], {"kind": "hat", "hat": 3, "seat": 1})          # (its own seat by number: fine)
	var own_ok: bool = srv.seats[1].hat == 3
	_send(srv, ids[7], {"kind": "leave"})
	var watcher := _open(srv, "Zed", false)
	_send(srv, watcher, {"kind": "hat", "hat": 2})
	var after := _own_hats(srv)
	_check("a hat for another seat is refused, and so is one from a page with no seat", other_ok and own_ok and after == [4, 3, 2, 3, 4, 5, 0, -1],
		"Ben asked for seats 1 and 6: nothing; for his own seat 2: hat 3; a watcher: nothing (%s)" % str(after))
	# the same hat again: nothing to say
	_seats_msg()
	_send(srv, ids[0], {"kind": "hat", "hat": 4})
	_check("the hat you already wear: no new seats message", _seats_msg().is_empty())
	# in the countdown: still allowed; in a match: refused
	_send(srv, ids[0], {"kind": "start"})
	var counting: bool = srv.phase == P.PH_COUNTDOWN
	_send(srv, ids[2], {"kind": "hat", "hat": 5})
	var in_count: int = srv.seats[2].hat
	_tick(srv, ServerScript.COUNTDOWN_TICKS + 2)
	var ph_start: int = srv.phase
	_send(srv, ids[3], {"kind": "hat", "hat": 0})
	_tick(srv, ServerScript.ROUND_START_TICKS + 2)
	var ph_play: int = srv.phase
	_send(srv, ids[3], {"kind": "hat", "hat": 1})
	for v in range(1, 7):
		srv.sim._kill(srv.sim.fighter(v), 0, 1)
	_tick(srv, 2)
	var ph_end: int = srv.phase
	_send(srv, ids[3], {"kind": "hat", "hat": 2})
	_check("a hat changes in the lobby and in the countdown, never in a match",
		counting and in_count == 5 and ph_start == P.PH_ROUND_START and ph_play == P.PH_PLAY and ph_end == P.PH_ROUND_END and srv.seats[3].hat == 3,
		"in the countdown Cleo got hat 5; Dan asked at ROUND START, in the round and at its end: still hat %d" % srv.seats[3].hat)
	# the match's seats messages carry the hats too
	m = _seats_msg()
	_check("the seats messages of a match carry the hats too", _msg_hats(m) == [4, 3, 5, 3, 4, 5, 0, -1] or _msg_hats(m).slice(0, 7) == [4, 3, 5, 3, 4, 5, 0],
		"%s (seat 8 is empty: its own hat, %d)" % [str(_msg_hats(m)), HatBook.for_seat(7)])
	srv.free()

	# a name gets its hat back: after leaving, and on another seat
	srv = _server(0, "christmas", dir)
	var ava := _open(srv, "Ava")
	var had: int = srv.seats[0].hat           # (her pick of the server before: the file)
	_send(srv, ava, {"kind": "hat", "hat": 2})
	var cleo := _open(srv, "Cleo")            # (Cleo picked 5 in the countdown above)
	var gus := _open(srv, "Gus")              # never picked: seat 3's own hat
	var gus_hat: int = srv.seats[2].hat
	_send(srv, ava, {"kind": "leave"})
	_send(srv, gus, {"kind": "leave"})
	var ben := _open(srv, "Ben")              # takes seat 1; he picked 3 before
	var ava2 := _open(srv, "AVA")             # the same name in capitals, on another seat
	var gus2 := _open(srv, "Gus")
	var hats_now := _own_hats(srv)
	_check("a name gets its hat back after it leaves, on any seat (capitals do not count)",
		had == 4 and srv.seats[0].name == "Ben" and srv.seats[0].hat == 3 and srv.seats[1].hat == 5 and srv.seats[2].name == "AVA" and srv.seats[2].hat == 2,
		"Ava came with hat %d from the file, picked 2, left; Ben sat on her seat (his own hat 3); AVA on seat 3 wears 2 (%s)" % [had, str(hats_now)])
	_check("a name that never picked keeps tonight the hat it was first given", gus_hat == 2 and srv.seats[3].name == "Gus" and srv.seats[3].hat == 2,
		"Gus got seat 3's hat (%d), left, came back on seat 4: hat %d (seat 4's own is %d)" % [gus_hat, srv.seats[3].hat, HatBook.for_seat(3)])
	srv.free()

	# after the server starts again: the file
	srv = _server(0, "christmas", dir)
	var file = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("known_hats.json")))
	var a3 := _open(srv, "Zoe")
	var a4 := _open(srv, "Ava")
	var c4 := _open(srv, "Gus")
	_check("after the server starts again a name still gets its hat back (known_hats.json, beside known_names.json)",
		srv.hat_book.path == dir.path_join("known_hats.json") and typeof(file) == TYPE_DICTIONARY and int(file.get("ava", -1)) == 2 and int(file.get("cleo", -1)) == 5
		and int(file.get("ben", -1)) == 3 and not file.has("gus") and srv.seats[1].hat == 2 and srv.seats[0].hat == 0 and srv.seats[2].hat == 2,
		"the file holds %s; Zoe (new) wears seat 1's hat, Ava wears 2 on seat 2, Gus (never picked) seat 3's own" % JSON.stringify(file))
	srv.free()

	# bots wear their seat's hat
	srv = _server(7, "christmas", dir)
	var one := _open(srv, "Ava")
	m = _seats_msg()
	var lobby_hats := _msg_hats(m)
	_start(srv, one)
	m = _seats_msg()
	var kinds: Array = []
	for st in m["seats"]:
		kinds.append(int(st["kind"]))
	_check("bots wear hats too, by their seat's number", lobby_hats == [2, 1, 2, 3, 4, 5, 0, 1] and _msg_hats(m) == [2, 1, 2, 3, 4, 5, 0, 1] and kinds == [1, 2, 2, 2, 2, 2, 2, 2],
		"the lobby shows %s for the seats bots will fill; in the match the 7 bots wear %s" % [str(lobby_hats.slice(1)), str(_msg_hats(m).slice(1))])
	# a person who takes a bot's seat keeps their own hat
	var late := _open(srv, "Cleo")            # all 8 seats are taken: she waits for a bot's seat (hat 5 is hers)
	var waits: bool = srv.conns[late].wait_seat >= 0 and srv.conns[late].seat < 0
	var seat_w: int = srv.conns[late].wait_seat
	_send(srv, late, {"kind": "hat", "hat": 0})                       # (no seat yet: refused)
	for v in range(1, 8):
		srv.sim._kill(srv.sim.fighter(v), 0, 1)
	_tick(srv, ServerScript.ROUND_END_TICKS + ServerScript.ROUND_START_TICKS + 4)
	m = _seats_msg()
	_check("a person who takes a bot's seat keeps their own hat", waits and srv.seats[seat_w].kind == 1 and srv.seats[seat_w].name == "Cleo" and srv.seats[seat_w].hat == 5
		and int(m["seats"][seat_w]["hat"]) == 5 and HatBook.for_seat(seat_w) != 5,
		"Cleo waited for seat %d (its bot wore %d), sat down at the next round with her hat 5" % [seat_w + 1, HatBook.for_seat(seat_w)])
	srv.free()

	# back on a new socket (a phone that lost the Wi-Fi): the same hat, picked but also unpicked
	srv = _server(0, "christmas", _folder("rejoin"))
	var p1 := _open(srv, "Hana", true, "tok-hana")
	var p2 := _open(srv, "Finn", true, "tok-finn")
	_send(srv, p1, {"kind": "hat", "hat": 5})
	srv.net_in.append(["close", p1, 0])
	srv.net_in.append(["close", p2, 0])
	_tick(srv, 30)
	var held: bool = srv.seats[0].kind == 1 and srv.seats[0].client_id == 0 and srv.seats[1].client_id == 0
	var p1b := _open(srv, "Hana", false, "tok-hana")                  # hello with the same token: the held seat is hers again
	var p2b := _open(srv, "Finn", false, "tok-finn")
	m = _seats_msg()
	_check("a person who comes back on a new socket keeps their hat", held and srv.conns[p1b].seat == 0 and srv.conns[p2b].seat == 1 and _msg_hats(m).slice(0, 2) == [5, 1],
		"Hana (picked 5) and Finn (seat 2's own, 1) dropped and came back: %s" % str(_msg_hats(m).slice(0, 2)))
	srv.free()

	# out of the season: nothing changes
	var keys_xmas: Array = []
	srv = _server(3, "christmas", _folder("keys"))
	_open(srv, "Ava")
	m = _seats_msg()
	var top_keys: Array = m.keys()
	for k in m["seats"][0]:
		if str(k) != "hat":
			keys_xmas.append(str(k))
	srv.free()
	var lines: Array = []
	var ok := true
	for season in ["harvest", "halloween", ""]:
		var odir := _folder("off_%s" % (season if season != "" else "none"))
		srv = _server(3, season, odir)
		var o1 := _open(srv, "Ava")
		m = _seats_msg()
		var has_hat := false
		for st in m["seats"]:
			has_hat = has_hat or st.has("hat")
		var same_keys: bool = m["seats"][0].keys() == keys_xmas and m.keys() == top_keys
		var hat0: int = srv.seats[0].hat
		_send(srv, o1, {"kind": "hat", "hat": 4})
		var quiet: bool = _seats_msg().is_empty() and srv.seats[0].hat == hat0 and not FileAccess.file_exists(odir.path_join("known_hats.json"))
		ok = ok and not has_hat and same_keys and quiet
		lines.append("%s: %s, %s, %s" % [season.to_upper() if season != "" else "NO SEASON", "no hats in the seats message" if not has_hat else "HATS IN THE MESSAGE",
			"its other fields as in the season" if same_keys else "OTHER FIELDS DIFFER", "a \"hat\" message does nothing and writes no file" if quiet else "A \"hat\" MESSAGE DID SOMETHING"])
		srv.free()
	_check("out of the Christmas season nothing changes", ok, "; ".join(lines))

# ------------------------------------------------------------------ 2. the page's copy
func _seats(hats: Array, kinds: Array = []) -> Dictionary:
	var list: Array = []
	for i in 8:
		var st := {"i": i, "kind": int(kinds[i]) if i < kinds.size() else 1, "name": NAMES[i], "on": true, "in": true, "team": -1, "points": 0, "crowns": 0}
		if i < hats.size() and hats[i] != null:
			st["hat"] = hats[i]
		list.append(st)
	return {"kind": "seats", "seats": list}

func _page_checks() -> void:
	var tables_ok: bool = Hats.COUNT == HatBook.COUNT and Hats.NAMES.size() == Hats.COUNT
	for table in [Hats.PIVOT, Hats.TAIL_BEHIND, Hats.RUN_GAIN, Hats.FALL_GAIN, Hats.LIMIT, Hats.LIFT, Hats.FOOT, Hats.HERO_DIR, Hats.Pick.ICON_AT]:
		tables_ok = tables_ok and table.size() == Hats.COUNT
	_check("the page and the server know the same %d hats; every table has a line for each; every frame of the fighter's sheet (0 to 27) has a place for the hat" % Hats.COUNT,
		tables_ok and Hats.HEAD.size() == 28 and Hats.HERO_TOP.size() == 8)
	Season.now = "christmas"
	Hats.read(_seats([0, 1, 2, 3, 4, 5, 0, 1]))
	var got: Array = []
	for i in 8:
		got.append(Hats.of(i))
	_check("the page reads each seat's hat from the seats message", Hats.on() and got == [0, 1, 2, 3, 4, 5, 0, 1] and Hats.of(8) == -1 and Hats.of(-1) == -1
		and is_equal_approx(Hats.lift(1), Hats.LIFT[1]), str(got))
	Hats.read(_seats([6, -1, "x", null, 2.0, 99, [], {}]))
	got.clear()
	for i in 8:
		got.append(Hats.of(i))
	_check("a hat the page does not know (6, -1, a word, nothing) is no hat", got == [-1, -1, -1, -1, 2, -1, -1, -1], str(got))
	Hats.read(_seats([0, 1, 2, 3, 4, 5, 0, 1]))
	var off: Array = []
	for season in ["", "harvest", "halloween"]:
		Season.now = season
		off.append(Hats.on() or Hats.of(0) >= 0 or Hats.lift(0) != 0.0)
	Season.now = "christmas"
	_check("out of the Christmas season the page draws no hat, whatever the message says", off == [false, false, false])
	Polish._off["hats"] = true           # as ?polish_off=hats on the page
	var none: bool = not Hats.on() and Hats.of(0) == -1 and Hats.lift(0) == 0.0
	Polish._off.erase("hats")
	_check("the polish switch \"hats\" is there and on; ?polish_off=hats: no hats", bool(Polish.SWITCHES.get("hats", false)) and none and Hats.on())

# ------------------------------------------------------------------ 3. the motion
func _motion_checks() -> void:
	# a run to the right for a second, then a stop: the tail lags, swings back past rest, and rests
	var lines: Array = []
	var ok := true
	for kind in Hats.COUNT:
		var sw = Hats.Swing.new()
		var x := 0.0
		var lag := 0.0
		var worst := 0.0
		for i in 60:
			x += 420.0 * DT
			sw.step(Vector2(x, 0), true, 1.0, DT, kind)
			worst = maxf(worst, absf(sw.a))
		lag = sw.a
		var lean: float = sw.lean
		var back := 0.0            # the farthest it swings to the other side after the stop
		for i in 150:
			sw.step(Vector2(x, 0), true, 1.0, DT, kind)
			worst = maxf(worst, absf(sw.a))
			back = minf(back, sw.a * signf(lag)) if lag != 0.0 else 0.0
		var lim: float = Hats.LIMIT[kind]
		if lim == 0.0:
			ok = ok and worst == 0.0 and lean < -0.05
			lines.append("%s: nothing dangles (it leans back %.0f degrees in a run)" % [Hats.NAMES[kind], -rad_to_deg(lean)])
		else:
			ok = ok and absf(lag) > lim * absf(Hats.RUN_GAIN[kind]) * 0.8 and signf(lag) == signf(Hats.RUN_GAIN[kind]) and back < -0.01 and absf(sw.a) < 0.01 \
				and absf(sw.av) < 0.1 and worst <= lim + 0.0001
			lines.append("%s: %.0f degrees behind in a run, %.0f past rest after the stop, at rest 2.5 s later" % [Hats.NAMES[kind], rad_to_deg(lag), rad_to_deg(-back)])
	_check("each hat's tail lags behind a run, swings back past rest when the run stops, and comes to rest", ok, "; ".join(lines))
	# a landing: the hat dips, and comes back
	var sw = Hats.Swing.new()
	sw.step(Vector2(0, -100), false, 1.0, DT, Hats.SANTA)
	var dip := 0.0
	for i in 90:
		var air := i < 10
		sw.step(Vector2(0, -100.0 + minf(i, 10) * 10.0), not air, 1.0, DT, Hats.SANTA)
		dip = maxf(dip, sw.bob)
	_check("a landing dips the hat and it comes back up", dip > 1.5 and dip <= 5.5 and absf(sw.bob) < 0.05, "%.1f px down at the most, %.2f px 1.3 s later" % [dip, sw.bob])
	# the facing flips: the tail is flung, then rests
	sw = Hats.Swing.new()
	for i in 10:
		sw.step(Vector2.ZERO, true, 1.0, DT, Hats.BEANIE)
	var flung := 0.0
	for i in 150:
		sw.step(Vector2.ZERO, true, -1.0, DT, Hats.BEANIE)
		flung = maxf(flung, absf(sw.a))
	_check("a turn flings the tail, and it rests again", flung > 0.15 and flung <= Hats.LIMIT[Hats.BEANIE] and absf(sw.a) < 0.01, "%.0f degrees at the most" % rad_to_deg(flung))
	# a page that draws 2 frames a second, wild places: nothing leaves its limits; a jump across the arena is no speed
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var sane := true
	for kind in Hats.COUNT:
		sw = Hats.Swing.new()
		for i in 400:
			var dt: float = [0.5, 0.016, 0.2, 1.5, 0.004][i % 5]
			sw.step(Vector2(rng.randf_range(-60, 60) * (i % 7), rng.randf_range(-40, 40)), rng.randf() < 0.5, 1.0 if rng.randf() < 0.5 else -1.0, dt, kind)
			sane = sane and is_finite(sw.a) and is_finite(sw.bob) and absf(sw.a) <= Hats.LIMIT[kind] + 0.0001 and sw.bob >= -3.0 and sw.bob <= 5.5 and absf(sw.lean) <= 0.12
	sw = Hats.Swing.new()
	for i in 30:
		sw.step(Vector2(1900.0 if i % 2 == 0 else 20.0, 500.0), true, 1.0, DT, Hats.SANTA)       # around the arena's edge, back and forth
	_check("slow frames and wild places never push a hat past its limits; a jump across the arena swings nothing", sane and absf(sw.a) < 0.001 and sw.vel.length() < 1.0,
		"2 000 steps of 4 ms to 1.5 s; after 30 jumps of 1 880 px the tail is at %.3f" % sw.a)

# ------------------------------------------------------------------ 4. the arena
func _sprite(feet: Vector2, frame: int, flip: bool, s: float = 1.0) -> Sprite2D:
	var spr := Sprite2D.new()
	spr.region_enabled = true
	spr.region_rect = Rect2((frame % 16) * 128, (frame / 16) * 128, 128, 128)
	spr.position = feet
	spr.flip_h = flip
	spr.scale = Vector2.ONE * s
	return spr

func _fighter(id: int, state: int = P.F_NORMAL, flags: int = 3) -> Dictionary:
	return {"id": id, "state": state, "flags": flags, "vx": 0, "vy": 0, "st": 0}

func _arena_checks() -> void:
	var level = LevelScript.new(0)
	# a floor to stand on: the first solid cell under an empty one in column 8
	var floor_y := -1.0
	for cy in range(12, LevelScript.ROWS):
		if level.cell(8, cy) != 0 and level.cell(8, cy - 1) == 0:
			floor_y = cy * 30.0
			break
	var feet := Vector2(8 * 30.0 + 15.0, floor_y)
	Season.now = "christmas"
	Hats.read(_seats([0, 1, 2, 3, 4, 5, 0, 1]))
	var layer = Hats.Arena.new()
	root.add_child(layer)
	layer.setup(World.TEAM)
	var sprites: Array = []
	for i in 8:
		var spr := _sprite(feet + Vector2(i * 4.0, 0), 0, i % 2 == 1, 0.55 if i == 3 else 1.0)
		root.add_child(spr)
		sprites.append([spr])
	var fl: Array = []
	for i in 8:
		fl.append(_fighter(i))
	layer.show_view(fl, sprites, {}, DT, level, false)
	var ok := true
	var lines: Array = []
	for i in 8:
		var w = layer.worn[i]
		var s: float = 0.55 if i == 3 else 1.0
		var dir := -1.0 if i % 2 == 1 else 1.0
		var want: Vector2 = sprites[i][0].position + Vector2(float(Hats.HEAD[0][0]) * dir, float(Hats.HEAD[0][1])) * s
		# (a point 10 to the front of the hat's origin and 10 under it lands where the facing and the size say)
		ok = ok and w != null and w.visible and w.kind == Hats.of(i) and w.col == World.TEAM[i] and w.position.distance_to(want) < 0.01 \
			and (w.transform * Vector2(10, 10)).distance_to(want + Vector2(10.0 * dir * s, 10.0 * s)) < 0.01
	_check("in the arena every fighter wears its seat's hat on its hood, in its colour, turned the way it faces; a TINY fighter wears a tiny hat", ok,
		"8 hats; seat 4 is TINY: its hat is %.2f of the size" % layer.worn[3].big)
	# every pose has its own place: the hat moves with the head
	var moved := 0
	for frame in [3, 8, 13, 14, 19, 21, 27]:
		sprites[0][0].region_rect = Rect2((frame % 16) * 128, (frame / 16) * 128, 128, 128)
		layer.show_view(fl, sprites, {}, DT, level, false)
		var want: Vector2 = sprites[0][0].position + Vector2(float(Hats.HEAD[frame][0]), float(Hats.HEAD[frame][1]))
		if layer.worn[0].position.distance_to(want) < 6.0 and absf(layer.worn[0].rotation - deg_to_rad(float(Hats.HEAD[frame][2]))) < 0.2:
			moved += 1
	_check("the hat sits on the head in every pose (running, jumping, the dodge, the roll, aiming, the ledge, landing)", moved == 7, "%d of 7 poses" % moved)
	sprites[0][0].region_rect = Rect2(0, 0, 128, 128)
	# hidden with the fighter; faint with a faint fighter; no hat on a costume or a trick's form
	sprites[1][0].visible = false                     # INVISIBLE, in bats, in smoke: world.gd hides the sprite
	sprites[2][0].modulate = Color(1, 1, 1, 0.0)      # the costume, a trick's form: the sprite is there but clear
	sprites[4][0].modulate = Color(1, 1, 1, 0.35)     # your own INVISIBLE fighter: faint
	sprites[5][0].modulate = Color(0.6, 0.85, 1.0)    # FROZEN: icy blue
	var places: Array = []
	for k in 20:
		sprites[5][0].position.x += 6.0
		layer.show_view(fl, sprites, {5: {"bits": P.PW_FROZEN}}, DT, level, false)
		places.append(layer.worn[5].position)
	_check("a hat hides with its fighter (INVISIBLE, the costume, a trick's form), is faint on your own faint fighter",
		not layer.worn[1].visible and not layer.worn[2].visible and layer.worn[4].visible and is_equal_approx(layer.worn[4].modulate.a, 0.35)
		and layer.worn[0].visible, "hidden 2, faint 1 (0.35), seat 1 as it was")
	# p4.22: in the Christmas season a FROZEN fighter is packed into a snowman (powers_view.gd draws it, world.gd
	# hides the archer): the hat sits on the snowman's head (a frozen fighter can still slide and fall: it goes
	# along), a little bigger, not tinted, and its tail holds still
	var on_head := true
	for k in places.size():
		var sm_feet: Vector2 = sprites[5][0].position - Vector2(6.0 * (places.size() - 1 - k), 0.0)
		on_head = on_head and places[k].distance_to(sm_feet - Vector2(0.0, Hats.SNOWMAN_TOP)) < 0.01
	_check("a FROZEN fighter is a snowman: its hat sits on the snowman's head, bigger, not tinted, its tail still",
		layer.worn[5].visible and on_head and layer.worn[5].modulate.is_equal_approx(Color.WHITE) and is_equal_approx(layer.worn[5].big, Hats.SNOWMAN_HAT)
		and layer.worn[5].swing.a == 0.0, "20 frames of sliding: the hat stayed %.0f px over the snowman's feet" % Hats.SNOWMAN_TOP)
	for i in [1, 2, 4, 5]:
		sprites[i][0].visible = true
		sprites[i][0].modulate = Color.WHITE
	layer.show_view(fl, sprites, {}, DT, level, false)
	# a knockout: the hat pops off, flies, comes to rest on the floor beside the body, upright
	fl[0] = _fighter(0, P.F_DEAD)
	layer.show_view(fl, sprites, {}, DT, level, false)
	var w0 = layer.worn[0]
	var popped: bool = w0.loose and w0.visible and w0.vel.y < -300.0
	var top_y: float = w0.position.y
	var rest_at := -1.0
	for i in 400:
		layer.show_view(fl, sprites, {}, DT, level, false)
		top_y = minf(top_y, w0.position.y)
		if w0.rest and rest_at < 0.0:
			rest_at = (i + 1) * DT
	var base_y: float = w0.position.y + float(Hats.FOOT[w0.kind])          # its lowest edge: on the top of a solid cell
	var on_floor: bool = level.cell_at(w0.position.x, base_y + 1.0) != 0 and level.cell_at(w0.position.x, base_y - 1.0) == 0 and is_equal_approx(fmod(base_y, 30.0), 0.0)
	_check("a knockout pops the hat off: it flies up, falls, and lies upright on the floor beside the body",
		popped and rest_at > 0.2 and rest_at < 4.0 and w0.visible and on_floor and absf(w0.position.x - feet.x) < 260.0 and absf(wrapf(w0.turn, -PI, PI)) < 0.05
		and top_y < feet.y - 110.0,
		"it rose %.0f px over the head, lay still %.1f s after the knockout, %.0f px from the body" % [(feet.y + float(Hats.HEAD[0][1])) - top_y, rest_at, absf(w0.position.x - feet.x)])
	# someone already knocked out when the page first sees them: no hat appears from nowhere
	var layer2 = Hats.Arena.new()
	root.add_child(layer2)
	layer2.setup(World.TEAM)
	layer2.show_view(fl, sprites, {}, DT, level, false)
	_check("a fighter the page first sees knocked out has no hat (none pops from nowhere)", layer2.worn[0] == null or not layer2.worn[0].visible)
	layer2.queue_free()
	# the next round: back on the head
	fl[0] = _fighter(0)
	layer.show_view(fl, sprites, {}, DT, level, false)
	var want0: Vector2 = sprites[0][0].position + Vector2(float(Hats.HEAD[0][0]), float(Hats.HEAD[0][1]))
	_check("the next round the hat is back on its fighter's head", not w0.loose and w0.visible and w0.position.distance_to(want0) < 6.0)
	# a new hat for a seat: the same node, drawn again; the LOW look draws fewer small parts
	Hats.read(_seats([3, 1, 2, 3, 4, 5, 0, 1]))
	layer.show_view(fl, sprites, {}, DT, level, true)
	_check("a new hat for a seat is worn at once; on the LOW look a hat has fewer small parts", w0.kind == 3 and not w0.detail and layer.get_child_count() == 8,
		"8 hats are 8 nodes, drawn once and then only moved")
	# no fighter, no hat; out of the season: nothing is shown, and a layer that never showed a hat makes no node
	layer.show_view([fl[1]], sprites, {}, DT, level, false)
	var only_one := 0
	for w in layer.worn:
		only_one += 1 if w != null and w.visible else 0
	Season.now = "harvest"
	layer.show_view(fl, sprites, {}, DT, level, false)
	var shown := 0
	for w in layer.worn:
		shown += 1 if w != null and w.visible else 0
	var layer3 = Hats.Arena.new()
	root.add_child(layer3)
	layer3.setup(World.TEAM)
	layer3.show_view(fl, sprites, {}, DT, level, false)
	_check("no fighter, no hat; out of the season the arena shows none and makes nothing for them", only_one == 1 and shown == 0 and layer3.get_child_count() == 0,
		"with one fighter left: %d hat; in the Harvest season: %d shown, %d nodes made by a fresh arena" % [only_one, shown, layer3.get_child_count()])
	Season.now = "christmas"
	layer.queue_free()
	layer3.queue_free()
	for sl in sprites:
		sl[0].queue_free()

# ------------------------------------------------------------------ 5. the lobby
func _run(node: Node, secs: float) -> void:
	for i in int(ceil(secs / DT)):
		node._process(DT)

# A real tap at a point of the 1920 x 1080 page: a press and a let go, through the page's own input.
func _tap(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		e.position = at
		e.global_position = at
		root.push_input(e)

# The hats drawn outside the arena run to their end without a script error (a draw that
# breaks stops before `done`).
class _Canvas extends Control:
	var done := 0
	var hats = load("res://client/hats.gd")
	func _draw() -> void:
		for k in hats.COUNT:
			hats.draw(self, k, Color("e8413c"), Transform2D(0.0, Vector2(60.0 + k * 50.0, 60.0)), 0.3, Color.WHITE, true)
			hats.draw(self, k, Color("3c8ce8"), Transform2D(0.0, Vector2(-1.6, 1.6), 0.0, Vector2(60.0 + k * 50.0, 160.0)), -0.2, Color(0.5, 0.5, 0.5), false, 1.5, true)
			hats.seat_hat[0] = k
			hats.on_hud(self, 0, Rect2(10, 10, 56, 56), Color("5fd35a"), 0.45)
			hats.on_podium(self, 0, Vector2(400, 800), 3.0, [9, 27, 10, 0, 1][k % 5], 0.1 * k, Color("f2c230"))
			hats.on_hero(self, 0, Rect2(100, 100, 540, 720), 0.1 * k, Color("a85ae8"), 1.0)
		done += 1

func _lobby_checks() -> void:
	Season.now = "christmas"
	Teams.on = false
	Teams.seat_team.clear()
	Hats.read(_seats([0, 1, 2, 3, 4, 5, 0, 1]))
	var canvas := _Canvas.new()
	root.add_child(canvas)
	canvas.size = Vector2(1920, 1080)
	await process_frame
	await process_frame
	_check("every hat draws to its end on a card, a HUD card, the podium and the painted hero (six hats, no script error)", canvas.done >= 1)
	canvas.queue_free()
	Hats.read(_seats([0, 1, 2, 3, 4, 5, 0, 1]))
	# the seat cards: a changed hat pops its card; the season coming on drops the hats on one after another
	var c = Cards.new()
	c.set_dress(Art.DRESSES["castle"], false)
	root.add_child(c)
	c.intro = 3.0
	var msg := _seats([0, 1, 2, 3, 4, 5, 0, 1], [1, 1, 1, 2, 0, 0, 0, 0])
	c.set_seats(msg["seats"], 0, P.PH_LOBBY, 2, [])
	_run(c, 1.0)
	var calm: bool = float(c.cards[1]["pop"]) > 0.5 and float(c.t) - float(c.cards[1]["hat_at"]) > 1.0
	Hats.read(_seats([0, 4, 2, 3, 4, 5, 0, 1], [1, 1, 1, 2, 0, 0, 0, 0]))
	c.set_seats(msg["seats"], 0, P.PH_LOBBY, 2, [])
	_check("a changed hat pops its card: a hop, sparks, and the new hat drops on", calm and float(c.cards[1]["pop"]) == 0.0 and float(c.cards[1]["hop"]) == 0.0
		and not c.cards[1]["sparks"].is_empty() and is_equal_approx(float(c.cards[1]["hat_at"]), float(c.t)) and float(c.cards[0]["pop"]) > 0.5,
		"seat 2 changed: its card pops; seat 1's does not")
	_run(c, 1.0)
	Season.now = "harvest"
	c.set_seats(msg["seats"], 0, P.PH_LOBBY, 2, [])
	_run(c, 0.5)
	Season.now = "christmas"
	c.set_seats(msg["seats"], 0, P.PH_LOBBY, 2, [])
	var t0: float = c.t
	_check("the season comes on: the hats drop onto the cards one after another, and no card pops",
		is_equal_approx(float(c.cards[0]["hat_at"]), t0) and float(c.cards[3]["hat_at"]) > float(c.cards[1]["hat_at"]) and float(c.cards[1]["hat_at"]) > t0 and float(c.cards[1]["pop"]) > 0.4,
		"seat 4's hat comes %.2f s after seat 1's" % (float(c.cards[3]["hat_at"]) - t0))
	# after a match: an award's ribbon hangs where the hat is, so they take turns
	var aws := [{"seat": 1, "name": NAMES[1], "title": "PIN MASTER", "why": "pinned 1 to the wall"}]
	c.set_seats(msg["seats"], 0, P.PH_LOBBY, 2, aws)
	var turn: float = Cards.AWARD_S
	c.t = turn * 10.5
	var shown: float = c._view(1)["award_sy"]
	c.t = turn * 11.5
	var folded: float = c._view(1)["award_sy"]
	c.t = turn * 12.5
	Hats.read(_seats([0, 5, 2, 3, 4, 5, 0, 1], [1, 1, 1, 2, 0, 0, 0, 0]))
	c.set_seats(msg["seats"], 0, P.PH_LOBBY, 2, aws)          # a new hat in the ribbon's own turn: the hat shows at once
	var fresh: float = c._view(1)["award_sy"]
	Season.now = "harvest"
	c.t = turn * 11.5
	var plain: float = c._view(1)["award_sy"]
	Season.now = "christmas"
	_check("after a match a card's award ribbon and its hat take turns (the ribbon hangs where the hat is); a new hat shows at once; out of the season the ribbon stays",
		is_equal_approx(shown, 1.0) and folded < 0.01 and fresh < 0.01 and is_equal_approx(plain, 1.0) and c._view(1).has("award"),
		"the ribbon's height: %.2f in its turn, %.3f in the hat's turn, %.3f right after a new hat, %.2f out of the season" % [shown, folded, fresh, plain])
	_run(c, 0.2)
	Polish._off["motion"] = true
	Hats.read(_seats([5, 4, 2, 3, 4, 5, 0, 1], [1, 1, 1, 2, 0, 0, 0, 0]))
	c.set_seats(msg["seats"], 0, P.PH_LOBBY, 2, [])
	_check("with the polish \"motion\" off a changed hat is just there (no pop)", float(c.cards[0]["pop"]) > 0.4 and float(c.cards[0]["hat_at"]) < 0.0)
	Polish._off.erase("motion")
	c.queue_free()

	# the whole lobby: the HAT button
	var lobby = Lobby.new()
	root.add_child(lobby)
	await process_frame
	var picked: Array = []
	var team_taps := [0]
	lobby.hat_picked.connect(func(n): picked.append(n))
	lobby.team_pressed.connect(func(): team_taps[0] += 1)
	var full := _seats([2, 1, 2, 3, 4, 5, 0, 1], [1, 1, 0, 0, 0, 0, 0, 0])
	full.merge({"bots": 2, "people": 2, "bots_wanted": 2, "phase": P.PH_LOBBY})
	Hats.read(full)
	lobby.intro = 3.0
	lobby.cards.intro = 3.0
	lobby.update(full, 0, P.PH_LOBBY, 0, "", true, false)
	_run(lobby.cards, 0.5)
	lobby.update(full, 0, P.PH_LOBBY, 0, "", true, false)
	var btn = lobby.hat_btn
	var xf: Array = lobby.cards._xf(0)
	var card := Rect2(xf[0] - Vector2(Cards.W, Cards.H) * 0.5, Vector2(Cards.W, Cards.H))
	var face := Rect2(btn.position, btn.size)
	var hit := Rect2(btn.position + Vector2(-8, -38), btn.size + Vector2(16, 44))
	var head: Vector2 = xf[0] + Vector2(0, -60)          # the fighter on the card: the card's own tap
	_check("your own lobby card has a HAT button under the fighter, where its YOU tag was; the card's own tap keeps the fighter",
		btn.visible and btn.worn == 2 and lobby.cards.hat_button and str(lobby.cards._view(0)["tag"]) == "" and str(lobby.cards._view(1)["tag"]) == "READY"
		and face.position.x >= card.position.x and face.end.x <= card.end.x and face.position.y > xf[0].y + 100.0
		and btn._has_point(btn.size * 0.5) and btn._has_point(Vector2(btn.size.x * 0.5, -30.0)) and not hit.has_point(head) and not hit.has_point(xf[0])
		and lobby.team_tap.visible and Rect2(lobby.team_tap.position, lobby.team_tap.size).has_point(head),
		"the button is %d x %d on a %d x %d card; a thumb's target %d x %d (the name counts too)" % [int(face.size.x), int(face.size.y), int(card.size.x), int(card.size.y), int(hit.size.x), int(hit.size.y)])
	# a tap: the next hat; a second quick tap: the one after; the server's word ends the wait
	btn.pressed.emit()
	btn.pressed.emit()
	var two: Array = picked.duplicate()
	full["seats"][0]["hat"] = 4
	Hats.read(full)
	lobby.update(full, 0, P.PH_LOBBY, 0, "", true, false)
	var settled: bool = btn.asked == -1 and btn.worn == 4 and btn.shown() == 4
	btn.pressed.emit()
	btn.pressed.emit()
	_check("a tap asks for the next hat, a quick second tap for the one after; past the last hat comes the first", two == [3, 4] and settled and picked == [3, 4, 5, 0],
		"from hat 2: taps asked for %s" % str(picked))
	# The card's own tap still does its job. Real taps through the page's input (a press and a
	# let go at one point, as a finger does), on a lobby that has settled: on the card's free
	# part FREE FOR ALL hops and TEAMS changes sides, and the HAT button never hears it; on the
	# HAT button and on the name just over it (the button's strip for a thumb) the button takes
	# the tap, and the card's tap never hears it. (A headless page has no pointer over anything,
	# so a button's own "pressed" cannot fire from a real tap here: the taps above prove that.)
	await process_frame
	lobby.update(full, 0, P.PH_LOBBY, 0, "", true, false)
	await process_frame          # (the HAT button follows its card at the end of the frame)
	var at: Array = lobby.cards._xf(0)
	var k := float(at[1])
	var face2 := Rect2(btn.position, btn.size)
	var free_spots := {"the fighter's head": Vector2(0, -60), "the card's middle": Vector2.ZERO,
		"the card's top corner": Vector2(-Cards.W * 0.4, -Cards.H * 0.45), "the flag's place over the card": Vector2(0, -Cards.H * 0.5 - 20.0),
		"the fighter's feet": Vector2(0, Cards.FEET - 6.0)}
	var hat_spots := {"the button's middle": face2.get_center(), "the button's left end": face2.position + Vector2(12.0, face2.size.y * 0.5),
		"the button's right end": face2.end - Vector2(12.0, face2.size.y * 0.5), "the name over the button": at[0] + Vector2(0, Cards.FEET + 46.0) * k}
	var got: Array = []           # which of the two a press reached
	btn.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: got.append("hat"))
	lobby.team_tap.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: got.append("card"))
	var wrong: Array = []
	var asks := picked.size()
	for what in free_spots.keys() + hat_spots.keys():
		var on_card: bool = free_spots.has(what)
		var p: Vector2 = at[0] + free_spots[what] * k if on_card else hat_spots[what]
		for teams in [false, true]:
			Teams.on = teams
			lobby.cards.cards[0]["hop"] = 9.0        # (free to hop: a fighter still in the air ignores a tap)
			lobby.team_tap.last_ms = -100000          # (the card's tap takes one tap in 300 ms: a shaky thumb does not flip twice)
			var sides: int = team_taps[0]
			got.clear()
			_tap(p)
			var hopped: bool = float(lobby.cards.cards[0]["hop"]) == 0.0
			var changed: bool = team_taps[0] == sides + 1
			var ok: bool = (got == ["card"] and (changed if teams else hopped) and not (hopped if teams else changed)) if on_card else (got == ["hat"] and not hopped and not changed)
			if not ok:
				wrong.append("%s, %s: the press reached %s, hop %s, sides %s" % [what, "TEAMS" if teams else "FREE FOR ALL", str(got), hopped, changed])
	Teams.on = false
	_check("a tap on the card itself still does what it did: a hop in FREE FOR ALL, a change of sides in TEAMS",
		wrong.is_empty() and picked.size() == asks,
		"real taps: %d spots on the card's free part reach the card's tap, %d on the HAT button and the name over it reach the button%s" % [free_spots.size(), hat_spots.size(), "" if wrong.is_empty() else "; WRONG: " + "; ".join(wrong)])
	# The button keeps to its card while the card pops, also on a slow page. Each frame the
	# page places the button (game_client.gd calls lobby.update), then the cards move (their
	# _process: here a third of a second at a time, a page that draws 3 frames a second), then
	# the frame ends. (The cards' own clock is stopped here, so only that step moves them.)
	full["seats"][0]["hat"] = 0
	Hats.read(full)
	lobby.cards.set_process(false)
	lobby.update(full, 0, P.PH_LOBBY, 0, "", true, false)      # a new hat: the card pops
	var popped: bool = float(lobby.cards.cards[0]["pop"]) == 0.0
	var off := 0.0
	var size_off := 0.0
	var grew := 1.0
	for f in 2:
		lobby.update(full, 0, P.PH_LOBBY, 0, "", true, false)
		lobby.cards._process(0.33)
		await process_frame
		var cx: Array = lobby.cards._xf(0)
		var want: Vector2 = cx[0] + Vector2(0.0, Cards.FEET + 101.0) * float(cx[1]) - btn.size * 0.5
		off = maxf(off, btn.position.distance_to(want))
		size_off = maxf(size_off, absf(btn.pulse - float(cx[1])))
		grew = maxf(grew, float(cx[1]))
	lobby.cards.set_process(true)
	_check("the HAT button keeps to its card while the card pops, also on a page that draws 3 frames a second",
		popped and grew > 1.05 and off < 0.5 and size_off < 0.001,
		"the card grew to %.2f; the button %.1f px from its place at the most (one frame behind it was 15 px)" % [grew, off])
	# gone: in a match, with no seat, on THE BIG SCREEN, out of the season, with the polish off
	var gone: Array = []
	lobby.update(full, 0, P.PH_COUNTDOWN, 100, "", true, false)
	var in_count: bool = btn.visible
	lobby.update(full, 0, P.PH_PLAY, 0, "", true, false)
	gone.append(btn.visible)
	lobby.update(full, -1, P.PH_LOBBY, 0, "", true, false)
	gone.append(btn.visible)
	lobby.update(full, 0, P.PH_LOBBY, 0, "", false, false)
	gone.append(btn.visible)
	Season.now = "harvest"
	lobby.update(full, 0, P.PH_LOBBY, 0, "", true, false)
	gone.append(btn.visible or lobby.cards.hat_button or str(lobby.cards._view(0)["tag"]) != "YOU")
	Season.now = "christmas"
	Polish._off["hats"] = true
	lobby.update(full, 0, P.PH_LOBBY, 0, "", true, false)
	gone.append(btn.visible or str(lobby.cards._view(0)["tag"]) != "YOU")
	Polish._off.erase("hats")
	lobby.update(full, 0, P.PH_LOBBY, 0, "", true, false)
	var back: bool = btn.visible
	lobby.set_tv([], [])
	lobby.update(full, -1, P.PH_LOBBY, 0, "", true, false)
	gone.append(btn.visible)
	_check("the HAT button shows in the lobby and the countdown only: not in a match, with no seat, with no connection, out of the season, with the polish off, on THE BIG SCREEN",
		in_count and back and gone == [false, false, false, false, false, false], "out of the season and with the polish off the card says YOU again")
	lobby.queue_free()

# (After the first frame: only then are the nodes this adds "in the tree".)
func _initialize() -> void:
	_go.call_deferred()

func _go() -> void:
	await process_frame
	Art.fonts_ready()
	Polish._read = true
	_server_checks()
	_page_checks()
	_motion_checks()
	_arena_checks()
	await _lobby_checks()
	Season.now = ""
	if fails == 0:
		print("✅ hat_probe: %d of %d checks passed" % [checks, checks])
	else:
		printerr("❌ hat_probe: %d of %d checks failed" % [fails, checks])
	quit(1 if fails > 0 else 0)

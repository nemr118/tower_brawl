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
# --no-powerups: no power-up orbs (p4.9; the lobby's POWER-UPS switch starts ON).
# --pu-gallery: a test knob: every round starts with every power-up's look (sim.gallery).
# --pin-demo: a test knob: at FIGHT seat 7 is pinned to a wall, seat 6 carried (sim.pin_demo).
# --hw-gallery: a test knob: at FIGHT the Halloween looks (GHOSTFACE, the tricks, the cat, bats; sim.hw_gallery).
# --xmas-gallery: p4.22 a test knob: at FIGHT the Christmas looks (KRAMPUS, the snowmen, a rider, the reindeer, presents; sim.xmas_gallery).
# --candy-trick N: a test knob: every candy gives N (0 a treat, 1 PUMPKIN HEAD, 2 BACKWARDS, 3 TINY, 4 GHOSTFACE).
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
# --mode ffa|teams: the lobby's MODE to start with: ffa (FREE FOR ALL, the default)
#   or teams (two teams, no friendly fire: "TEAMS" below). The lobby's SETTINGS and
#   the host port's /mode change it.
# --admin-port N: the host port (p4.2, for the host page in Ignition,
#   ~/Work/tower_brawl_ignition/build_host.py): plain http on 127.0.0.1 only
#   (--admin-bind to change that), JSON in and out. GET /state: the seats (with
#   each person's address and ping), the settings, the players' numbers tonight,
#   the last 80 events. POST /bots {n} (0..7), /bot_level {n} (1..3), /arena {n}
#   (P.ARENA_MIX or an arena of LevelScript.PLAY): any time, in a match from the
#   next round; /power {n} (p4.9: the power-up orbs on or off, at once; it was p4.5's power arrows);
#   /kick {seat} (a person goes back to watching), /start, /stop (the match ends,
#   back to the lobby), /mode {pick} ("ffa" or "teams"; in a match: from the next
#   match). A reply: {ok, text, state}. 0 (the default): off.
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
# join {name, seat (the seat it had before its socket went: it gets that one again when it is free)}, leave, start, bots {n}, arena {n} (P.ARENA_MIX or a layout),
# bot_level {n} (1 EASY, 2 NORMAL, 3 HARD), power {n} (p4.9: 1 the power-up orbs on, 0 off), name {name},
# skip (p4.8: a seated player ends the match's end, the deathcam's montage, for everyone: the lobby),
# mode {pick} ("ffa" or "teams": the lobby's MODE, for everyone), team (TEAMS: you change sides; both only in the lobby),
# report {why, device, ua, screen, pick, look, fps, slow_pct, frame_max_ms, frames, ping_ms, reconnects,
# step_downs, shots_armed, shots_cancelled, mouse_shots, errors [], errors_total; p4.15: stick, jumps, rim_dodges,
# button_dodges, mem_mb, tex_mb; p4.16: late_pct, eased, eased_px; quiet_ms, watchdog (net.gd's watchdog)} (p4.7: a phone's own
# numbers every 30 s and at a look change or a page error; logged as a "client" line, kept for /state). From the server: welcome {seat, version, name, phase},
# version_error {server, yours}, full, note {text}, seats {phase, round, goal,
# bots, bots_wanted, bot_level, power, people, arena (the pick), arena_now (the round's,
# or the next one's in the lobby), seats: [{i, name, kind, on, points, crowns, in, team}]},
# round_end {round, winner, name,
# draw, points}, match_end {winner, name, points, awards, replay_s (how long the replay of the winner's kills
# plays), screen_s (the winner's screen after it)}.
# TEAMS adds to seats: mode ("ffa" or "teams": what is played now), mode_pick (the lobby's
# MODE), team_names [2], team_points [2], teams_ok (both teams have a fighter), and each
# seat's team (0, 1, or -1); to round_end and match_end: team (the winning team), members
# (its seats), and name is the team's name; match_end also best (the name of its player
# with the most knockouts, whose seat is winner: the page shows that hero and those kills).
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
const Routes = preload("res://sim/routes.gd")

const SEATS := 8
const MAX_BOTS := 7
# A dropped person's seat is held for them: the brain plays their fighter, and the same
# token gets the seat, the colour and the points back (hello). In a match: 60 s. It was
# 8 s: on 25 October 33 phones dropped, 17 came back within 8 s and 16 lost their seat
# and points (the review's bug 1). In the lobby: 20 s (nobody is in a fight; it was 8 s,
# but a sleeping phone is now dropped after SILENT_MS, so a short nap must fit).
const HOLD_TICKS := 3600
const HOLD_LOBBY_TICKS := 1200
const COUNTDOWN_TICKS := 180     # START to the first round: 3 s
const ROUND_START_TICKS := 90    # the ROUND N banner, nobody moves: 1.5 s
const ROUND_MAX_TICKS := 3600    # a round with no end is a draw at 60 s (a backstop: the purple walls kill everyone left by 48 s)
const WALLS_S := 25              # the purple walls (TowerFall's miasma) come 25 s after FIGHT
const ROUND_END_TICKS := 90      # one fighter left: TowerFall waits 1.5 s before the point
const DRAW_TICKS := 60           # nobody left: a shorter DRAW banner
# The match's end: the replay of the winner's kills plays first on every page, then the
# winner's screen with the awards, then the lobby. The winner's screen gets 8 s, always:
# the server adds the replay's length (P.replay_secs, from the winner's kills). Before
# (the review's bug 9) both shared 12 s: 6.2 s of winner's screen after a 1-kill replay,
# 3.6 s after 3 kills, 0.8 s after 6.
const MATCH_END_TICKS := 480
const REPORT_S := 5
const SLOW_TICK_US := 12000      # a tick this slow (12 ms of its 16.7) gets a [SLOW] line
# A socket that sends nothing for 3 s is a drop (the review's bug 5). A page sends a
# ping every 0.5 s and 60 inputs a second, so 3 s of nothing is a frozen page or a dead
# link. Before, the server never noticed: the fighter ran on with its last buttons held
# down, round after round. Now the socket is closed, the brain plays, the seat is held
# (HOLD_TICKS), and the page gets its seat back when it opens a new socket.
const SILENT_MS := 3000
const CLOSE_SILENT := 4001       # the close code the server gives a silent socket
# Bug 12 (the review): a socket whose reading side is stuck. The server's packets pile
# up, and when that socket says goodbye, the server's own goodbye cannot leave: the
# socket hangs half closed. It was then dropped as one that "never finished the
# handshake", with no word to the seats: its seat stayed "on" for ever (only a host
# kick cleared it). Now: half closed for CLOSING_MS is a drop the seats hear about, and
# so are SEND_FAIL_MAX packets in a row that could not be queued (1 MB waiting).
const CLOSING_MS := 1000
const SEND_FAIL_MAX := 120
const CLOSE_STUCK := 4002        # the inbox code for a socket that hung half closed
const CLOSE_BLOCKED := 4003      # and for one that could not be sent to
const NAME_MAX := 12
const MAX_EARLY := 60            # an input more than 1 s early is applied at once (the client's clock is off)
# T_OWN tells a page how early its inputs came, in one signed byte, and 127 (P.NO_MARGIN)
# means "no input came". An input 200 ticks early was cut to 127, so a page whose clock
# ran far ahead was told "nothing came" and never slowed down (the review's bug 2). Now
# the most the byte says is 126, and "none" has a number of its own in here.
const MARGIN_NONE := 1 << 30
const EVENTS_MAX := 80           # the host page's recent events
const HOST_MAX := 16384          # the largest request the host port reads
const PHASE_NAMES := ["LOBBY", "COUNTDOWN", "ROUND START", "PLAYING", "ROUND END", "MATCH END"]
# p4.11 the awards at a match's end (the user: "awards for a wide variety of things, many
# of them silly, so the kids get awards even if they didn't perform well"): [title, the
# match number it reads, max or min, the least that counts, the line under it, unit ("":
# a count, "s": ticks shown as seconds, "steps": px shown as steps of 30 px)]. Everyone
# gets one: the rarest award they lead, else a silly one from FALLBACK.
const AWARDS := [
	["SHARPSHOOTER", "arrow_kills", "max", 2, "%d arrow knockouts", ""],
	["STOMP CHAMP", "stomp_kills", "max", 1, "%d stomps on heads", ""],
	["BOOM BOOM", "blast_kills", "max", 1, "%d knockouts with a blast", ""],
	["CAT WHISPERER", "cat_kills", "max", 1, "the ghost cats got %d", ""],
	["CATCH OF THE DAY", "catches", "max", 1, "caught %d arrows", ""],
	["TREASURE HUNTER", "powers", "max", 2, "grabbed %d power-ups", ""],
	["PARTY ANIMAL", "bigs", "max", 1, "grabbed %d BIG power-ups", ""],
	["PIN MASTER", "pin_kills", "max", 1, "pinned %d to the wall", ""],
	["WALL DECORATION", "pinned", "max", 1, "pinned to the wall %d times", ""],
	["LIGHTNING ROD", "d_lightning", "max", 1, "zapped by lightning %d times", ""],
	["EXTRA CRISPY", "d_fire", "max", 1, "burned %d times", ""],
	["STINKY", "d_poison", "max", 1, "poisoned %d times", ""],
	["PANCAKE", "d_stomp", "max", 1, "squished %d times", ""],
	["PINCUSHION", "d_arrow", "max", 2, "hit by %d arrows", ""],
	["CAT FOOD", "d_cat", "max", 1, "caught by ghost cats %d times", ""],
	["OOPS!", "self_kills", "max", 1, "knocked themselves out %d times", ""],
	["BUTTERFINGERS", "dryfires", "max", 3, "shot an empty bow %d times", ""],
	["TRIGGER HAPPY", "shots", "max", 15, "%d arrows shot", ""],
	["PEACEMAKER", "shots", "min", 0, "only %d arrows shot", ""],
	["BOUNCY CASTLE", "jumps", "max", 15, "%d jumps", ""],
	["NINJA ROLL", "dodges", "max", 6, "%d dodges", ""],
	["SPEED DEMON", "distance", "max", 3000, "ran %d steps", "steps"],
	["COUCH POTATO", "distance", "min", 0, "only ran %d steps", "steps"],
	["THE FLOOR IS LAVA", "air", "max", 900, "%d seconds in the air", "s"],
	["FREQUENT FLYER", "fly", "max", 180, "flew for %d seconds", "s"],
	["SURVIVOR", "alive", "max", 1200, "in the fight for %d seconds", "s"],
	["NAP TIME", "first_out", "max", 1, "first one out %d times", ""],
	["SPOOKY", "boos", "max", 1, "BOO'd %d players as a ghost", ""],
	["FRIENDLY GHOST", "ghost", "max", 300, "a ghost for %d seconds", "s"],
	["NOW YOU SEE ME", "invis", "max", 120, "invisible for %d seconds", "s"],
	["ARROW COLLECTOR", "pickups", "max", 6, "picked up %d arrows", ""],
	["ROUND WINNER", "round_wins", "max", 2, "won %d rounds", ""],
	["GOOD KITTY", "pets", "max", 1, "petted the cat %d times", ""],
	["TRICKED!", "tricks", "max", 1, "got tricked %d times", ""],
	["SLASHER", "knife_kills", "max", 1, "%d knockouts with the knife", ""],
	["SWEET TOOTH", "candies", "max", 1, "opened %d candies", ""],
	["SCARY MOVIE STAR", "masks", "max", 1, "turned into GHOSTFACE %d times", ""],
	["GHOST BUSTER", "mask_kills", "max", 1, "finished off GHOSTFACE %d times", ""],
	# p4.18 the Harvest season's own (their numbers are counted only in that season: _match_events)
	["GOBBLE GOBBLE", "turkeys", "max", 1, "caught the turkey %d times", ""],
	["PIE FACE", "pied", "max", 1, "got a pie in the face %d times", ""],
	["STUFFED", "dishes", "max", 1, "opened %d dishes", ""],
	["LEFTOVERS", "leftovers", "max", 6, "picked up %d arrows", ""],
	["GOBBLER", "big_turkeys", "max", 1, "turned into THE BIG TURKEY %d times", ""],
	["PECKING ORDER", "peck_kills", "max", 1, "%d knockouts with a peck", ""],
	["TURKEY DINNER", "turkey_ends", "max", 1, "finished off THE BIG TURKEY %d times", ""],
	# p4.22 the Christmas season's own (counted only in that season: _match_events)
	["NAUGHTY LIST", "naughty", "max", 3, "%d knockouts", ""],
	["NICE LIST", "nice", "max", 2, "knocked nobody out in %d rounds", ""],
	["SNOWBALL CHAMP", "snowed", "max", 1, "packed %d players into snowmen", ""],
	["LUMP OF COAL", "coal", "max", 1, "%d tricks out of presents", ""],
	["SLEIGH RIDE", "rides", "max", 1, "rode the reindeer %d times", ""],
	["UNWRAPPED", "presents", "max", 1, "opened %d presents", ""],
	["FRUITCAKE", "fruitcake", "max", 1, "first one out %d times", ""],
	["HORNS AND BELLS", "krampuses", "max", 1, "turned into KRAMPUS %d times", ""],
	["IN THE SACK", "sack_kills", "max", 1, "put %d players in the sack", ""],
	["KRAMPUS CATCHER", "krampus_ends", "max", 1, "finished off KRAMPUS %d times", ""],
]
const FALLBACK := [["GOOD SPORT", "played the whole match"], ["BEST WIGGLE", "the wiggliest archer"],
	["MAIN CHARACTER", "every story needs one"], ["WILL WIN NEXT TIME", "just warming up"],
	["FASHION ICON", "looked great doing it"], ["CERTIFIED SILLY", "the silliest moves"],
	["FAN FAVORITE", "everybody's favorite"], ["NEVER GAVE UP", "kept on going"]]
const CAUSE_KEY := {1: "d_arrow", 2: "d_blast", 3: "d_stomp", 4: "d_fire", 5: "d_poison", 6: "d_walls", 7: "d_lightning", 8: "d_cat", 9: "d_spikes", 11: "d_knife"}
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
	var fail_run: int = 0       # packets in a row that could not be queued for it (SEND_FAIL_MAX)
	var closing_ms: int = 0     # when it was first seen half closed (CLOSING_MS)
	var last_in_ms: int = 0     # when its last packet came (SILENT_MS)

class Conn:                     # what this thread knows about a socket
	var id: int = 0
	var ip: String = ""
	var ok: bool = false        # said hello with the right version
	var seat: int = -1
	var name: String = ""
	var token: String = ""
	var last_tick: int = 0      # the newest client input tick applied
	var wait_seat: int = -1     # the bot's seat it sits down on when this round is over (_wait_for_seat); its seat is -1 till then
	var report := {}            # p4.7: the phone's last report (cleaned), for the host page
	var report_ms: int = 0
	var fps_seen := -1.0        # its frame rate from the last report that had match frames (-1: none yet)

class Seat:
	var i: int = 0
	var kind: int = 0           # 0 empty, 1 a person, 2 a bot (for this match)
	var name: String = ""
	var client_id: int = 0      # 0: no socket (a held seat, or a bot)
	var token: String = ""
	var hold_t: int = 0
	var guest: int = 0          # a bot's seat: the client that sits down here when this round is over (0: nobody waits)
	var points: int = 0
	var crowns: int = 0
	var buttons: int = 0        # the last buttons applied (held while no input comes)
	var aim: int = 0
	var in_round: bool = false  # has a fighter this round
	var team: int = 0           # TEAMS: the seat's team, 0 or 1 (a person picks it in the lobby; a bot gets one each round)
	var input_tick: int = -1    # the sim tick a late input was applied on
	var queue := {}             # input tick -> [buttons, aim]: applied just before that tick
	var used: int = 0           # the newest input tick applied
	var margin_min: int = MARGIN_NONE   # the smallest margin (ticks early) since the last T_OWN (MARGIN_NONE: no input came)
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
var season_pick := "auto"        # p4.18 the lobby's SEASON (proto.gd SEASON_PICKS): auto = by this computer's date
var start_power := 0             # a test knob (--start-power N): every fighter starts each round with power-up N
var silly := 0                   # p4.20: this round's surprise for everyone (proto.gd SILLY_*; 0: a plain round)
var silly_last := 0              # the last one played (never the same twice in a row)
var silly_every := 3             # every third round (--silly-every N; 0: never). The lobby's POWER-UPS OFF turns them off too
var silly_force := 0             # a test knob (--silly N): every round is silly round N
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
var pu_gallery := false          # --pu-gallery (a test knob: sim.gallery each round)
var mstats := {}                 # p4.11: this match's numbers by seat (for the awards)
var round_first := true          # no death yet this round (NAP TIME)
var round_kills := {}            # p4.22: seat -> its knockouts this round (the Christmas season's NICE LIST: a round with none)
var snow_by := -1                # p4.22: who threw the snowball whose burst is being read (E_SNOW, then its E_SNOWED)
var last_pos := {}               # seat -> where its fighter was last tick (the steps it ran)
var last_cause := {}             # seat -> its last death's cause (a kill's kind)
var last_awards: Array = []      # the last match's awards (match_end, and the lobby's seats message)
var pin_demo := false            # --pin-demo (a test knob: sim.pin_demo at each FIGHT)
var hw_gallery := false          # --hw-gallery (a test knob: sim.hw_gallery at each FIGHT)
var xmas_gallery := false        # --xmas-gallery (p4.22 a test knob: sim.xmas_gallery at each FIGHT)
var last_rec := {}               # the last report line (the host page shows its tick numbers)
# TEAMS (the rules: the "TEAMS" part below, and sim.gd friends / decided / safe_team)
var mode_teams := false          # the lobby's MODE: false FREE FOR ALL, true TEAMS
var match_teams := false         # is the match that is on played in TEAMS? (the MODE as it was when the match began)
var team_points := [0, 0]        # TEAMS: each team's points in this match (every seat of a team shows its team's)
var win_team := -1               # TEAMS: the team that won the round just called (-1: none, a draw, or FREE FOR ALL)

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
	_load_names(str(o.get("out", root_dir.path_join("bench_results"))))   # p4.18: the names seen on other nights
	DirAccess.make_dir_recursive_absolute(out_dir)
	var log_path := out_dir.path_join("v2_server.jsonl")
	server_log = FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	server_log.seek_end()
	_load_stats(out_dir.path_join("v2_stats.json"))
	Engine.max_fps = 120     # no busy loop in headless; physics stays at 60
	sim = SimScript.new(0, 24, int(Time.get_unix_time_from_system()))
	sim.respawn = false
	sim.power_arrows = o.has("power-arrows")
	sim.powerups = not o.has("no-powerups")
	pu_gallery = o.has("pu-gallery")
	pin_demo = o.has("pin-demo")
	hw_gallery = o.has("hw-gallery")
	xmas_gallery = o.has("xmas-gallery")
	sim.candy_trick = int(o.get("candy-trick", -1))
	sim.pet_always = o.has("pet-always")
	start_power = int(o.get("start-power", 0))
	silly_every = maxi(0, int(o.get("silly-every", 3)))
	silly_force = int(o.get("silly", 0))
	if o.has("season") and P.SEASON_PICKS.has(str(o["season"]).to_lower()):
		season_pick = str(o["season"]).to_lower()
	sim.season = _season()
	sim.walls_start = maxi(0, int(o.get("walls-s", WALLS_S))) * 60
	if o.has("spots"):
		for k in str(o["spots"]).split(",", false):
			sim.fixed_spots.append(int(k))
	if o.has("arena"):
		arena_pick = _arena_arg(str(o["arena"]))
	if o.has("bot-level"):
		sim.bot_level = maxi(0, SimScript.BrainScript.NAMES.find(str(o["bot-level"]).to_upper()))
	mode_teams = str(o.get("mode", "ffa")).to_lower() == "teams"
	_load_lobby(str(o.get("out", root_dir.path_join("bench_results"))), o)   # p4.19: what the lobby picked last time
	sim.set_arena(_next_arena())   # the lobby shows the arena that comes next
	# The bots' route maps for every arena, now, while nobody is here yet (about 50 ms).
	# Before, each was built about 1 s after FIGHT in the first round on its arena:
	# one tick of 14 to 33 ms where a tick has 16.7 (sim/routes.gd build_all).
	var routes_us := Routes.build_all()
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
			print("🏰 [NET] the host port: http://%s:%d (GET /state; POST /bots /bot_level /arena /kick /start /stop /mode)" % [bind, host_port])
	started_ms = Time.get_ticks_msec()
	sec_start_ms = started_ms
	var info := {"kind": "start", "t": Time.get_unix_time_from_system(), "version": P.VERSION, "port": port,
		"tls": tls_opts != null, "bots": bots_wanted, "power_arrows": sim.power_arrows, "powerups": sim.powerups, "goal_override": goal_override,
		"walls_s": sim.walls_start / 60, "arena": _arena_label(arena_pick), "bot_level": SimScript.BrainScript.NAMES[sim.bot_level],
		"godot": Engine.get_version_info().string, "cpu": _cpu_model(), "cores": OS.get_processor_count(), "soak": soak,
		"host": OS.get_environment("HOSTNAME"), "net_thread": net_thread_on, "admin_port": host_port,
		"season": _season(), "season_pick": season_pick, "mode": _mode_word(mode_teams)}
	server_log.store_line(JSON.stringify(info))
	server_log.flush()
	print("🏰 [NET] Tower Brawl %s: %s on %d, %d bots (%s) fill the empty seats, power-ups %s, %s, arena %s, mode %s, cpu %s x%d, report in %s" % [
		P.VERSION, "wss" if tls_opts != null else "ws", port, bots_wanted, SimScript.BrainScript.NAMES[sim.bot_level], "on" if sim.powerups else "off",
		("the walls at %d s" % (sim.walls_start / 60)) if sim.walls_start > 0 else "no walls", _arena_label(arena_pick), P.MODE_LABEL[_mode_word(mode_teams)],
		info["cpu"], info["cores"], log_path])
	print("🏰 [NET] the bots' route maps for all %d arenas were built in %.0f ms, before the first match" % [SimScript.LevelScript.count(), routes_us / 1000.0])
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
	_log_powers(evs)
	_match_events(evs)
	if phase == P.PH_PLAY:
		_match_sample()
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
	if t3 - t0 > SLOW_TICK_US:
		# A tick has 16.7 ms. The chaos soak saw 6 ticks over 16 ms in 42 minutes (the worst
		# 33 ms), most in a server's first minute. This line says where such a tick's time
		# went, for the night's log (print, not _say: it is no event for the host page).
		print("🏰 [SLOW] tick %d took %.1f ms: the inbox, the seats and the match %.1f, the inputs and the simulation %.1f, the snapshot and the sends %.1f; phase %s, round %d on %s, %d fighters, %.1f s after FIGHT" % [
			sim.tick, (t3 - t0) / 1000.0, (t1 - t0) / 1000.0, (t2 - t1) / 1000.0, (t3 - t2) / 1000.0, PHASE_NAMES[phase], round_no,
			sim.level.name, sim.fighters.size(), sim.play_t / 60.0])
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
			_on_close(conns[id], int(m[2]))

func _on_text(c: Conn, txt: String) -> void:
	# (JSON.new().parse, not JSON.parse_string: that one prints an ERROR line in the log for
	# every text that is no JSON, and a client can send anything: the chaos soak's junk)
	var js := JSON.new()
	if js.parse(txt) != OK:
		return
	var d = js.data
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
		if c.seat < 0:      # (a second hello from a seated socket changes nothing about its seat)
			c.token = str(d.get("token", "")).substr(0, 32)
			# a held seat with this token: the same person is back. (A seat that is still on
			# another socket is not taken here: a second tab that only looks, or THE BIG
			# SCREEN in the same browser, says hello with the same token. join takes it over.)
			var mine := _seat_of(c.token)
			if mine != null and mine.client_id == 0:
				_take_seat(mine, c)
		_out(c.id, JSON.stringify({"kind": "welcome", "seat": c.seat if c.seat >= 0 else c.wait_seat, "version": P.VERSION, "name": c.name, "phase": phase}))
		_send_seats(c.id)
		return
	if not c.ok:
		return
	if kind == "tv":       # p4.18 THE BIG SCREEN asks where phones join
		_out(c.id, JSON.stringify(_tv_info()))
		return
	if kind == "report":
		_on_report(c, d)
		return
	if kind == "taunt":      # p4.19 the GOBBLE button: a speech bubble (and a sound) over your fighter, for everyone
		if c.seat >= 0 and (phase == P.PH_PLAY or phase == P.PH_ROUND_END):
			sim.taunt(c.seat)
		return
	if kind == "skip":
		if (c.seat >= 0 or c.wait_seat >= 0) and phase == P.PH_MATCH_END:
			_say("🏰 [MATCH] seat %d '%s' skipped the montage: back to the lobby" % [maxi(c.seat, c.wait_seat), c.name])
			_to_lobby()
		return
	if kind == "join":
		if c.seat >= 0 or c.wait_seat >= 0:
			return
		var mine := _seat_of(c.token)
		if mine != null:    # bug 5: this token has a seat already (on a socket that hangs, or in another tab): that one, never a second seat
			_take_seat(mine, c)
			_out(c.id, JSON.stringify({"kind": "welcome", "seat": c.seat, "version": P.VERSION, "name": c.name, "phase": phase}))
			return
		if d.has("name"):
			c.name = _clean_name(str(d.get("name", "")), -1)
		# this token waits for a bot's seat already, on a socket that hangs or in another
		# tab: this socket waits there in its place, never for a second seat (as bug 5)
		for w in seats:
			var g: Conn = conns.get(w.guest) if w.guest != 0 else null
			if g != null and g.token == c.token and c.token != "":
				g.wait_seat = -1
				_out(g.id, JSON.stringify({"kind": "welcome", "seat": -1, "version": P.VERSION, "name": g.name, "phase": phase}))
				_wait_for_seat(w, c)
				return
		var s := _free_seat(_int(d.get("seat"), -1))
		if s == null:
			_out(c.id, JSON.stringify({"kind": "full"}))
			_say("🏰 [JOIN] rejected %s from %s: all %d seats are taken" % [c.name, c.ip, SEATS])
			return
		if s.kind == 2 and s.in_round and (phase == P.PH_ROUND_START or phase == P.PH_PLAY or phase == P.PH_ROUND_END):
			_wait_for_seat(s, c)     # a bot's seat, and its fighter is in a round: the bot plays that round out first
			return
		_seat_person(s, c, false)
		_know(c.name)       # p4.18: the join screen offers this name next time (WHO ARE YOU?)
		_out(c.id, JSON.stringify({"kind": "welcome", "seat": c.seat, "version": P.VERSION, "name": c.name, "phase": phase}))
	elif kind == "leave":
		if c.seat >= 0:
			var s: Seat = seats[c.seat]
			_say("🏰 [LEAVE] seat %d '%s' left on purpose" % [s.i, s.name])
			_free_seat_now(s)
			c.seat = -1
			_out(c.id, JSON.stringify({"kind": "welcome", "seat": -1, "version": P.VERSION, "name": c.name, "phase": phase}))
		elif c.wait_seat >= 0:
			_say("🏰 [LEAVE] '%s' waited for seat %d and left on purpose: the bot keeps it" % [c.name, c.wait_seat])
			seats[c.wait_seat].guest = 0
			c.wait_seat = -1
			_out(c.id, JSON.stringify({"kind": "welcome", "seat": -1, "version": P.VERSION, "name": c.name, "phase": phase}))
	elif kind == "start":
		if c.seat < 0:
			_out(c.id, JSON.stringify({"kind": "note", "text": "Take a seat first."}))
		elif phase != P.PH_LOBBY:
			pass
		elif _people() + _bots_now() < 2:
			_out(c.id, JSON.stringify({"kind": "note", "text": "A match needs 2 fighters: add a bot or a friend."}))
		elif mode_teams and not _teams_ok():
			_out(c.id, JSON.stringify({"kind": "note", "text": TEAMS_NEED}))
		else:
			phase = P.PH_COUNTDOWN
			phase_t = COUNTDOWN_TICKS
			_say("🏰 [LOBBY] START by seat %d '%s': %d people + %d bots" % [c.seat, seats[c.seat].name, _people(), _bots_now()])
			seats_dirty = true
	elif kind == "bots":
		if c.seat >= 0 and (phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN):
			bots_wanted = clampi(_int(d.get("n"), bots_wanted), 0, MAX_BOTS)
			seats_dirty = true
			_save_lobby()
	elif kind == "bot_level":
		var lv := _int(d.get("n"), sim.bot_level)
		if c.seat >= 0 and (phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN) and lv != sim.bot_level \
				and lv >= SimScript.BrainScript.EASY and lv <= SimScript.BrainScript.HARD:
			sim.bot_level = lv
			_say("🏰 [LOBBY] bots %s, picked by seat %d '%s'" % [SimScript.BrainScript.NAMES[lv], c.seat, seats[c.seat].name])
			seats_dirty = true
			_save_lobby()
	elif kind == "arena":
		var n := _int(d.get("n"), arena_pick)
		if c.seat >= 0 and (phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN) and n != arena_pick \
				and (n == P.ARENA_MIX or (n >= 0 and n < SimScript.LevelScript.count())):
			arena_pick = n
			sim.set_arena(_next_arena())
			_say("🏰 [LOBBY] arena %s, picked by seat %d '%s'" % [_arena_label(arena_pick), c.seat, seats[c.seat].name])
			seats_dirty = true
			_save_lobby()
	elif kind == "season":
		var pick := str(d.get("pick", ""))
		if c.seat >= 0 and (phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN) and pick != season_pick and P.SEASON_PICKS.has(pick):
			_set_season(pick, "seat %d '%s'" % [c.seat, seats[c.seat].name])
	elif kind == "power":
		var on := _int(d.get("n"), 0) != 0
		if c.seat >= 0 and (phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN) and on != sim.powerups:
			sim.powerups = on
			_say("🏰 [LOBBY] power-ups %s, picked by seat %d '%s'" % ["ON" if on else "OFF", c.seat, seats[c.seat].name])
			seats_dirty = true
			_save_lobby()
	elif kind == "mode":      # TEAMS: the lobby's MODE, for everyone (SETTINGS)
		var pick := str(d.get("pick", ""))
		if c.seat >= 0 and phase == P.PH_LOBBY and P.MODES.has(pick) and (pick == "teams") != mode_teams:
			_set_mode(pick == "teams", "seat %d '%s'" % [c.seat, seats[c.seat].name])
	elif kind == "team":      # TEAMS: a tap on your own card: you change sides
		if c.seat >= 0 and phase == P.PH_LOBBY and mode_teams:
			var ts: Seat = seats[c.seat]
			ts.team = 1 - ts.team
			_say("🏰 [LOBBY] seat %d '%s' joins %s" % [ts.i, ts.name, P.team_name(ts.team, _season())])
			seats_dirty = true
	elif kind == "name":
		if c.seat >= 0:
			c.name = _clean_name(str(d.get("name", "")), c.seat)
			seats[c.seat].name = c.name
			seats_dirty = true

# p4.7: a phone's report: cleaned (known fields only, numbers clamped, text cut), logged
# as a "client" line in v2_server.jsonl with who sent it, kept for the host page; a
# step-down or page errors also make a [PHONE] line.
func _on_report(c: Conn, d: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	var why := str(d.get("why", "")).substr(0, 10)
	if why == "timer" and now - c.report_ms < 2000:
		return
	var r := {"why": why}
	for k in ["device", "pick", "look", "stick", "controls"]:
		r[k] = str(d.get(k, "")).substr(0, 10)
	r["ua"] = str(d.get("ua", "")).substr(0, 140)
	r["screen"] = str(d.get("screen", "")).substr(0, 12)
	for k in ["fps", "slow_pct", "frame_max_ms", "mem_mb", "tex_mb", "late_pct", "eased_px", "res"]:
		r[k] = snappedf(clampf(_num(d.get(k)), 0.0, 100000.0), 0.1)
	for k in ["frames", "ping_ms", "reconnects", "step_downs", "shots_armed", "shots_cancelled", "mouse_shots", "errors_total",
			"jumps", "rim_dodges", "button_dodges", "eased", "aim_taps", "quiet_ms", "watchdog"]:
		r[k] = clampi(_int(d.get(k), 0), 0, 100000000)
	var errs: Array = []
	var raw = d.get("errors", [])
	if typeof(raw) == TYPE_ARRAY:
		for e in raw.slice(0, 10):
			errs.append(str(e).substr(0, 240))
	r["errors"] = errs
	# the page's own watchdog (client/net.gd QUIET_MAX_MS) gave a dead link up since this socket's last report
	var gave_up: bool = r["watchdog"] > int(c.report.get("watchdog", 0))
	c.report = r
	c.report_ms = now
	if r["frames"] >= 30:
		c.fps_seen = r["fps"]
	var line := {"kind": "client", "t": Time.get_unix_time_from_system(), "client": c.id, "seat": c.seat, "name": c.name, "ip": c.ip}
	line.merge(r)
	server_log.store_line(JSON.stringify(line))
	server_log.flush()
	var who := "seat %d '%s'" % [c.seat, c.name] if c.seat >= 0 else "watcher '%s'" % c.name
	if why == "step":
		_say("🏰 [PHONE] %s (%s): the look stepped down to %s (%.0f fps)" % [who, r["device"], r["look"].to_upper(), r["fps"]])
	if not errs.is_empty():
		_say("🏰 [PHONE] %s (%s): %d page error%s: %s" % [who, r["device"], errs.size(), "" if errs.size() == 1 else "s", errs[0]])
	if gave_up:
		_say("🏰 [PHONE] %s (%s): its page closed a dead link by itself and came back (%d time%s since it loaded)" % [who, r["device"],
			r["watchdog"], "" if r["watchdog"] == 1 else "s"])

# The host page's view of a phone (p4.7), or null before its first report.
func _phone(c: Conn):
	if c == null or c.report.is_empty():
		return null
	var r: Dictionary = c.report
	return {"device": r["device"], "pick": r["pick"], "look": r["look"], "fps": c.fps_seen if c.fps_seen >= 0.0 else null,
		"slow_pct": r["slow_pct"], "ping_ms": r["ping_ms"], "reconnects": r["reconnects"], "step_downs": r["step_downs"],
		"errors": r["errors_total"], "age_s": snappedf((Time.get_ticks_msec() - c.report_ms) / 1000.0, 0.1)}

# A name as every screen and every log line shows it: NAME_MAX (12) characters at most.
# What stays: letters of any language, digits, single spaces, and the marks - _ . ' ! ?
# What goes, and why:
#  - the direction characters (U+202E and its family). A name with one made the rest
#    of its line read from right to left, on every screen and in the logs;
#  - every other character that draws nothing, so no name looks empty and none hides
#    letters nobody sees;
#  - < > [ ] & { } / \ : % and the like: a page that shows the name (the host page, a
#    report) could read them as markup. "<b>Bob</b>" comes out as "bBobb";
#  - accents past NAME_STACK (3) on one letter: stacked by the dozen they grow over
#    the lines above and below;
#  - everything before the first letter or digit: no name starts with a mark.
# It was: anything from code 32 up except 127 stayed.
const NAME_MARKS := "-_.'!?"
const NAME_SCAN := 64            # only the first 64 characters are read: a page sends 12, a junk packet 5 000
const NAME_STACK := 3            # Thai, Hebrew and Hindi put up to 3 marks on one letter
# Characters Unicode counts as letters or accents that draw nothing: a joiner, Korean's
# fillers, Khmer's two silent vowels, the two zero-width joiners. (The variation
# selectors, FE00 to FE0F and the like, go by their ranges in _name_kind.)
const NAME_BLANK := [0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, 0x200C, 0x200D, 0x3164, 0xFFA0]
# Other scripts' digits 0 to 9: ten in a row from each of these (Arabic, Persian,
# Hindi, Bengali, Gurmukhi, Gujarati, Oriya, Tamil, Telugu, Kannada, Malayalam, Thai,
# Lao, Tibetan, Burmese, Khmer, full-width). A rarer script's digits count as accents.
const NAME_DIGITS := [0x0660, 0x06F0, 0x0966, 0x09E6, 0x0A66, 0x0AE6, 0x0B66, 0x0BE6, 0x0C66, 0x0CE6, 0x0D66,
	0x0E50, 0x0ED0, 0x0F20, 0x1040, 0x17E0, 0xFF10]

# What one character is in a name: 0 it goes, 1 a letter or a digit, 2 an accent (it
# sits on the letter before it), 3 one of NAME_MARKS, 4 a space of any kind.
static func _name_kind(ch: String) -> int:
	var code := ch.unicode_at(0)
	if code == 32 or (code >= 9 and code <= 13) or code == 0x85 or code == 0xA0 or code == 0x1680 \
			or (code >= 0x2000 and code <= 0x200A) or code == 0x2028 or code == 0x2029 or code == 0x202F \
			or code == 0x205F or code == 0x3000:
		return 4
	if code < 128:
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122):
			return 1
		return 3 if NAME_MARKS.contains(ch) else 0
	if NAME_BLANK.has(code) or (code >= 0xFE00 and code <= 0xFE0F) or (code >= 0x180B and code <= 0x180F) \
			or (code >= 0xE0100 and code <= 0xE01EF):
		return 0
	# Godot knows Unicode's two lists for names in code: what may start a word (the
	# letters), and what may follow a letter (the letters, the digits, the accents).
	if ch.is_valid_unicode_identifier():
		return 1
	if ("a" + ch).is_valid_unicode_identifier():
		for d in NAME_DIGITS:
			if code >= d and code < d + 10:
				return 1
		return 2
	return 0

# The clean name, or "" when nothing of it may stay.
static func clean_name(raw: String) -> String:
	var n := ""
	var gap := false         # a space waits: it goes in before the next character that stays
	var on_letter := false   # the last character kept was a letter, a digit or an accent
	var stack := 0           # accents on that letter so far
	for c0 in raw.substr(0, NAME_SCAN):
		var ch: String = c0
		if ch == "\u2019" or ch == "\u2018":
			ch = "'"         # a phone's keyboard types a curly apostrophe (O'Neil)
		var kind := _name_kind(ch)
		if kind == 0:
			continue
		if kind == 4:
			gap = n != ""
			continue
		if n == "" and kind != 1:
			continue         # a name starts with a letter or a digit
		if kind == 2 and (gap or not on_letter or stack >= NAME_STACK):
			continue         # an accent with no letter under it, or one too many
		if n.length() + (2 if gap else 1) > NAME_MAX:
			break
		if gap:
			n += " "
			gap = false
		n += ch
		stack = stack + 1 if kind == 2 else 0
		on_letter = kind != 3
	return n

func _clean_name(raw: String, seat: int) -> String:
	var n := clean_name(raw)
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
# at the next round), unless someone waits for that one already (Seat.guest). want:
# the seat a page had before its socket went (bug 1): it gets that one again when
# nobody else sits there, so it keeps its colour.
func _free_seat(want: int = -1) -> Seat:
	var in_match := phase != P.PH_LOBBY and phase != P.PH_COUNTDOWN
	if want >= 0 and want < SEATS and (seats[want].kind == 0 or (in_match and seats[want].kind == 2 and seats[want].guest == 0)):
		return seats[want]
	for s in seats:
		if s.kind == 0:
			return s
	if in_match:
		for s in seats:
			if s.kind == 2 and s.guest == 0:
				return s
	return null

# A number from a client's JSON (or the host page's), or the fallback when it is no
# number (a list, a word, nothing). int() of a list or of null is a script error, and a
# client can send anything: the chaos soak's junk ({"kind": "bot_level", "n": {}}) made
# "SCRIPT ERROR: Nonexistent 'int' constructor" in _on_text. A number as text ("3")
# still counts, as before.
static func _int(v, fallback: int) -> int:
	var t := typeof(v)
	if t == TYPE_INT or t == TYPE_FLOAT:
		return int(clampf(float(v), -2147483648.0, 2147483647.0)) if not is_nan(float(v)) else fallback
	if t == TYPE_BOOL:
		return 1 if v else 0
	if t == TYPE_STRING and (v.is_valid_int() or v.is_valid_float()):
		return int(clampf(float(v), -2147483648.0, 2147483647.0))
	return fallback

# The same for a number with a fraction (a phone report's fps): 0 when it is no number.
static func _num(v) -> float:
	var t := typeof(v)
	if t == TYPE_INT or t == TYPE_FLOAT:
		return 0.0 if is_nan(float(v)) else float(v)
	if t == TYPE_STRING and v.is_valid_float():
		return float(v)
	return 0.0

# The seat this token sits on (held, or on another socket), or null.
func _seat_of(token: String) -> Seat:
	if token == "":
		return null
	for s in seats:
		if s.kind == 1 and s.token == token:
			return s
	return null

# c gets the seat its token already has. A held seat: the person is back (hello). A seat
# still on another socket (join; bug 5: a phone that came back on a new socket while
# the old one hung, or a second tab): the old socket is told it has no seat, and this
# one plays. Before, the new socket got a second seat and the old seat stayed "on" with
# its last buttons held.
func _take_seat(s: Seat, c: Conn) -> void:
	if s.client_id == c.id:
		return
	if s.client_id != 0:
		var old: Conn = conns.get(s.client_id)
		if old != null:
			old.seat = -1
			_out(old.id, JSON.stringify({"kind": "welcome", "seat": -1, "version": P.VERSION, "name": old.name, "phase": phase}))
			_out(old.id, JSON.stringify({"kind": "note", "text": "You joined again from another tab or phone: that one plays now."}))
		_say("🏰 [JOIN] seat %d '%s': the same token on a new socket (client %d took over from client %d)" % [s.i, s.name, c.id, s.client_id])
		s.buttons = 0
	_seat_person(s, c, true)

func _seat_person(s: Seat, c: Conn, back: bool) -> void:
	var was_bot := s.kind == 2
	s.kind = 1
	s.client_id = c.id
	s.hold_t = 0
	if not back:
		s.name = c.name if c.name != "Player" else "Player %d" % (s.i + 1)
		s.token = c.token
		sim.keep.erase(s.i)   # p4.9: a new person: none of the seat's kept power-ups
		mstats.erase(s.i)     # nor the match's numbers of a bot that sat here (they made the person's award)
		s.points = 0
		s.team = _smaller_team(s.i)      # TEAMS: a new person goes to the smaller team
		if match_teams:
			s.points = team_points[s.team]   # and shows that team's points from the start
		s.crowns = 0
		s.in_round = false
		s.buttons = 0
		s.aim = 0
	s.queue.clear()
	s.margin_min = MARGIN_NONE
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

# A person sits down on a bot's seat in the middle of a round (all 8 seats are taken).
# The rule: the bot plays that round out under its own name and keeps what it wins,
# and the person gets the seat when the round is over (_seat_guests), with no points.
# Before, the seat changed hands at once while the bot's fighter played on: when it
# won, the banner said "AVA WINS THE ROUND" and Ava got a point for a round she never
# played; the bot's kills and deaths went into her numbers and her award as well.
# The page is told the seat number now (welcome), so it shows the match and waits; for
# the server that socket has no seat yet (Conn.seat stays -1: its buttons, its taunt
# and a new name are not used; Conn.wait_seat and Seat.guest remember who waits where).
func _wait_for_seat(s: Seat, c: Conn) -> void:
	s.guest = c.id
	c.wait_seat = s.i
	_know(c.name)
	_say("🏰 [JOIN] '%s' from %s (client %d) gets seat %d when this round is over: the bot '%s' plays it out" % [c.name, c.ip, c.id, s.i, s.name])
	_out(c.id, JSON.stringify({"kind": "welcome", "seat": s.i, "version": P.VERSION, "name": c.name, "phase": phase}))
	_out(c.id, JSON.stringify({"kind": "note", "text": "%s plays this round out. You are in from the next round." % s.name}))

# The round is over (or the match was stopped): the people who wait for a bot's seat
# sit down, and those bots go. A socket that went away while it waited gets nothing:
# the bot stays.
func _seat_guests() -> void:
	for s in seats:
		if s.guest == 0:
			continue
		var c: Conn = conns.get(s.guest)
		s.guest = 0
		if c == null or c.wait_seat != s.i:
			continue
		c.wait_seat = -1
		if c.seat < 0 and s.kind != 1:
			_seat_person(s, c, false)
		_out(c.id, JSON.stringify({"kind": "welcome", "seat": c.seat, "version": P.VERSION, "name": c.name, "phase": phase}))

# A bot keeps its seat for the whole match, and with the seat its name and its points.
# Before, every round took all the bots off their seats and put them back on the lowest
# empty ones. When a person left a low seat, the bots moved down, and the points stayed
# behind on the seats: a bot could lose its points, or get another bot's.
# Now a round only sets the count right. Too many bots (the host asked for fewer): the
# highest seats go. Too few: it gives back how many NEW bots the round still needs, and
# _start_round puts them on the lowest empty seats with no points.
func _keep_bots() -> int:
	var want := _bots_now()
	var have := 0
	for s in seats:
		if s.kind == 2:
			have += 1
	for i in range(SEATS - 1, -1, -1):
		if have > want and seats[i].kind == 2:
			seats[i].kind = 0      # (_start_round's next loop takes its name and its points away)
			have -= 1
	return want - have

# The seat is empty from now. Its fighter, if it is still in a round, goes out with a
# normal death (sim.leave): before, it played on as a bot, could win the round, and the
# point went to an empty seat with no name (the review's bug 3: 6 times in two nights).
func _free_seat_now(s: Seat) -> void:
	sim.keep.erase(s.i)     # p4.9: the seat's kept power-ups go with its person
	sim.leave(s.i)
	mstats.erase(s.i)       # the match's numbers (the awards) were that person's: the next one on this seat starts fresh
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

func _on_close(c: Conn, code: int = 0) -> void:
	if c.seat >= 0:
		var s: Seat = seats[c.seat]
		if s.client_id == c.id:
			s.client_id = 0
			s.hold_t = HOLD_LOBBY_TICKS if phase == P.PH_LOBBY else HOLD_TICKS
			s.queue.clear()
			s.buttons = 0       # (the last buttons are not held on for the person's return)
			var f = sim.fighter(s.i)
			if f != null and s.in_round:
				f.bot = true
				f.connected = false
			var how := "dropped"
			if code == CLOSE_SILENT:
				how = "went silent for %d s" % (SILENT_MS / 1000)
			elif code == CLOSE_STUCK:
				how = "hung half closed"
			elif code == CLOSE_BLOCKED:
				how = "could not be sent to"
			_say("🏰 [LEAVE] seat %d '%s' (client %d, %s) %s: held %d s" % [s.i, s.name, c.id, c.ip, how, s.hold_t / 60])
			seats_dirty = true
	elif c.ok and c.wait_seat >= 0:
		_say("🏰 [LEAVE] '%s' (client %d, %s) waited for seat %d and went away: the bot keeps it" % [c.name, c.id, c.ip, c.wait_seat])
	elif c.ok:
		_say("🏰 [LEAVE] watcher '%s' (client %d, %s) left" % [c.name, c.id, c.ip])
	if c.wait_seat >= 0 and seats[c.wait_seat].guest == c.id:
		seats[c.wait_seat].guest = 0      # it waited for a bot's seat: the bot keeps it
	conns.erase(c.id)

# Held seats count down; at 0 the seat is free again. A seat whose time runs out while
# its fighter is in a round waits for that round to end (_free_expired): the brain
# plays the round out under the seat's name, so nobody sees a fighter drop dead for no
# reason, and a point it wins still has a name.
func _hold_seats() -> void:
	var live := phase == P.PH_ROUND_START or phase == P.PH_PLAY or phase == P.PH_ROUND_END
	for s in seats:
		if s.kind == 1 and s.client_id == 0 and s.hold_t > 0:
			if s.hold_t == 1 and live and s.in_round:
				continue
			s.hold_t -= 1
			if s.hold_t == 0:
				_say("🏰 [LEAVE] seat %d '%s' is free again (nobody came back)" % [s.i, s.name])
				_free_seat_now(s)

# Between two rounds: the held seats whose time ran out during the round (_hold_seats).
func _free_expired() -> void:
	for s in seats:
		if s.kind == 1 and s.client_id == 0 and s.hold_t <= 1:
			_say("🏰 [LEAVE] seat %d '%s' is free again (nobody came back; its fighter played the round out)" % [s.i, s.name])
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
		own_buf.put_8(P.NO_MARGIN if s.margin_min >= MARGIN_NONE else clampi(s.margin_min, -128, 126))
		own_buf.put_u8(mini(s.late_n, 255))
		own_buf.put_u8((P.OWN_FIGHTER if f != null else 0) | (P.OWN_BRAIN if f != null and f.bot else 0)
			| (P.OWN_SAFE if f != null and sim.is_safe(f) else 0))   # (TEAMS: every living fighter of the winning team)
		own_buf.put_u32(sim.tick + phase_t if phase == P.PH_ROUND_START else 0)
		if f != null:
			sim.write_fighter_state(own_buf, f)
		_out(s.client_id, own_buf.data_array)
		s.margin_min = MARGIN_NONE
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
		elif mode_teams and not _teams_ok():     # TEAMS: someone left in these 3 s and a team is empty
			_say("🏰 [LOBBY] countdown stopped: a team has no fighter")
			_out(0, JSON.stringify({"kind": "note", "text": TEAMS_NEED}))
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
			if pin_demo:
				sim.pin_demo()
			if hw_gallery:
				sim.hw_gallery()
			if xmas_gallery:
				sim.xmas_gallery()
			_say("🏰 [ROUND] %d FIGHT" % round_no)
	elif phase == P.PH_PLAY:
		phase_t += 1
		var alive: int = sim.alive_count()
		var over: bool = sim.decided()     # one fighter left, or none (TEAMS: one team left, or none)
		if over or phase_t >= ROUND_MAX_TICKS:
			var draw := alive == 0 or not over     # (FREE FOR ALL: the same as "not exactly one alive")
			winner = P.NO_ONE if draw else sim.last_alive().id
			# TEAMS: the round goes to a team. `winner` is one of its living fighters (the first).
			win_team = int(sim.teams.get(winner, -1)) if match_teams and not draw else -1
			# The winner is safe from this tick on (the review's bug 4: on 25 October the winner
			# died in the 1.5 s before the point in 10 of 248 rounds, once on a match point).
			# TEAMS: every living fighter of the winning team is.
			sim.safe = -1 if draw or win_team >= 0 else winner
			sim.safe_team = win_team
			phase = P.PH_ROUND_END
			phase_t = DRAW_TICKS if draw else ROUND_END_TICKS
			var msg := {"kind": "round_end", "round": round_no, "winner": winner, "draw": draw,
				"name": "" if draw else seats[winner].name, "points": _points()}
			if win_team >= 0:      # TEAMS: the banner says the team's name
				msg["name"] = P.team_name(win_team, sim.season)
				msg["team"] = win_team
				msg["members"] = _team_seats(win_team)
			_out(0, JSON.stringify(msg))
			if draw:
				_say("🏰 [ROUND] %d end after %.1f s: a draw (%d alive)" % [round_no, _round_secs(), alive])
			elif win_team >= 0:
				_say("🏰 [ROUND] %d end after %.1f s: %s is the last team standing (%d of its fighters still up; the team: %s)" % [round_no, _round_secs(),
					msg["name"], alive, _team_line(win_team)])
			else:
				_say("🏰 [ROUND] %d end after %.1f s: seat %d '%s' is the last one standing" % [round_no, _round_secs(), winner, seats[winner].name])
			var line := {"kind": "round", "t": Time.get_unix_time_from_system(), "match": match_no,
				"round": round_no, "arena": sim.level.id, "secs": snappedf(_round_secs(), 0.01), "winner": winner, "draw": draw,
				"fighters": sim.fighters.size(), "people": _people(), "bot_level": sim.bot_level, "deaths": round_deaths,
				"names": _seat_names(), "arena_name": sim.level.name, "season": sim.season,   # p4.18: the arena by name (numbers move), the season
				"bots": _bot_seats(),     # p4.19: the bots' seats (a bot is GRAVY now, not BOT 3)
				"silly": P.silly_name(silly, sim.season),     # p4.20: "" for a plain round
				"mode": _mode_word(match_teams)}     # TEAMS: the mode, on every round's line
			if match_teams:        # and each seat's team (-1: no fighter), the team that won (-1: a draw), the two names
				line["teams"] = _round_teams()
				line["team_won"] = win_team
				line["team_names"] = P.team_names(sim.season)
			server_log.store_line(JSON.stringify(line))
			server_log.flush()
			for s in seats:
				if _won(s.i):
					_mcount(s.i, "round_wins")   # p4.11 (TEAMS: every seat of the winning team)
				if sim.season == "christmas" and s.kind != 0 and sim.fighter(s.i) != null and int(round_kills.get(s.i, 0)) == 0:
					_mcount(s.i, "nice")         # p4.22 NICE LIST: a whole round with no knockout
				if s.kind != 0 and (s.in_round or _won(s.i)):
					var r := _stat(s)
					r["rounds"] += 1
					if _won(s.i):
						r["round_wins"] += 1
			_save_stats()
	elif phase == P.PH_ROUND_END:
		phase_t -= 1
		if phase_t <= 0:
			# The point never goes to an empty seat (the winner left in these 1.5 s: bug 3).
			# (A person who sits down on a bot's seat during a round waits for the round's end:
			# the bot wins under its own name and the point is the bot's, _wait_for_seat.)
			if match_teams:
				winner = _team_point()     # TEAMS: one point for the team; `winner` is now its best player's seat (or nobody)
			elif winner != P.NO_ONE and seats[winner].kind == 0:
				_say("🏰 [ROUND] %d: no point: the winner's seat %d is empty now" % [round_no, winner])
				winner = P.NO_ONE
			if winner != P.NO_ONE:
				if not match_teams:        # (TEAMS: _team_point gave it)
					seats[winner].points += 1
				_sync_points()
			_free_expired()
			if match_teams and winner != P.NO_ONE:
				winner = _team_best(win_team)     # (its best player's held seat may have been freed just now: another one stands for the team)
				if winner == P.NO_ONE:            # (every seat of the team was a held one, freed just now: nobody is left to have the point)
					team_points[win_team] -= 1
					_say("🏰 [ROUND] %d: no point: nobody of %s is left" % [round_no, P.team_name(win_team, sim.season)])
			if winner != P.NO_ONE and seats[winner].kind != 0 and seats[winner].points >= goal:
				# the match is won: a crown for the winner (TEAMS: for every seat of the winning team)
				for wi in (_team_seats(win_team) if match_teams else [winner]):
					seats[wi].crowns += 1
					_stat(seats[wi])["match_wins"] += 1
				_save_stats()
				phase = P.PH_MATCH_END
				var replay_s: float = P.replay_secs(int(mstats.get(winner, {}).get("kills", 0)))
				phase_t = MATCH_END_TICKS + roundi(replay_s * 60.0)
				last_awards = _awards()   # p4.11
				var end_msg := {"kind": "match_end", "winner": winner, "name": seats[winner].name, "points": _points(),
					"awards": last_awards, "replay_s": snappedf(replay_s, 0.01), "screen_s": MATCH_END_TICKS / 60}
				var who := "seat %d '%s'" % [winner, seats[winner].name]
				if match_teams:    # TEAMS: the team's name; `winner` stays its best player (the hero, the replay)
					end_msg["name"] = P.team_name(win_team, sim.season)
					end_msg["team"] = win_team
					end_msg["members"] = _team_seats(win_team)
					end_msg["best"] = seats[winner].name
					who = "%s (%s; the most knockouts: seat %d '%s')" % [end_msg["name"], _team_line(win_team), winner, seats[winner].name]
				_out(0, JSON.stringify(end_msg))
				for aw in last_awards:
					_say("🏰 [AWARD] %s: %s (%s)" % [aw["name"], aw["title"], aw["why"]])
				_say("🏰 [MATCH] end after %d rounds: %s wins %s; the replay %.1f s, then the winner's screen %d s" % [round_no, who,
					_score_line(), replay_s, MATCH_END_TICKS / 60])
				var mline := {"kind": "match", "t": Time.get_unix_time_from_system(), "match": match_no,
					"rounds": round_no, "winner": winner, "people": _people(), "bot_level": sim.bot_level, "mode": _mode_word(match_teams)}
				if match_teams:
					mline["team_won"] = win_team
					mline["team_points"] = team_points.duplicate()
				server_log.store_line(JSON.stringify(mline))
				server_log.flush()
				seats_dirty = true
			elif _people() + _bots_now() < 2 or (match_teams and not _teams_ok()):
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
	sim.reset_powers()     # p4.9: a new match: no power-ups kept
	mstats.clear()         # p4.11: the awards count from here
	last_awards = []
	for s in seats:
		s.points = 0
	round_no = 1
	match_teams = mode_teams     # the MODE is fixed for the whole match (a change in a match counts from the next one)
	team_points = [0, 0]
	win_team = -1
	var n := _people() + _bots_now()
	goal = goal_override if goal_override > 0 else _goal_for(2 if match_teams else n)   # (TEAMS: two sides share the points, as two players do)
	_say("🏰 [MATCH] start: %d people + %d bots (%s), %s, first to %d points" % [_people(), _bots_now(), SimScript.BrainScript.NAMES[sim.bot_level],
		P.MODE_LABEL[_mode_word(match_teams)], goal])
	_start_round()

# The arena of the next round: the pick, or MIX's next one (G5; p4.18: MIX's list follows the season).
func _next_arena() -> int:
	if arena_pick == P.ARENA_MIX:
		var play: Array = SimScript.LevelScript.mix_for(_season())
		return play[mix_i % play.size()]
	return arena_pick

# p4.22 the nights left to Christmas Day by this computer's date: 24 on 1 December, 0 on the
# 25th; -1 any other day. The lobby counts them down in the Christmas season.
func _sleeps() -> int:
	var d := Time.get_date_dict_from_system()
	return 25 - int(d["day"]) if int(d["month"]) == 12 and int(d["day"]) <= 25 else -1

# p4.18 the season now: the pick, or by this computer's date (proto.gd season_for).
func _season() -> String:
	if season_pick == "off":
		return ""
	if season_pick == "auto":
		var d := Time.get_date_dict_from_system()
		return P.season_for(int(d["month"]), int(d["day"]))
	return season_pick

# p4.19: the lobby's settings are kept over a restart (the October nights: the server came
# up with 7 bots every time, and the family plays with 0 or 1). <out>/lobby_settings.json
# holds the bots, their level, the arena, the power-ups, the season and the mode; an option
# on the command line wins over it. A soak never reads or writes it.
var lobby_path := ""

func _load_lobby(root: String, o: Dictionary) -> void:
	if soak:
		return
	lobby_path = root.path_join("lobby_settings.json")
	if not FileAccess.file_exists(lobby_path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(lobby_path))
	if typeof(d) != TYPE_DICTIONARY:
		return
	if not o.has("bots"):
		bots_wanted = clampi(int(d.get("bots", bots_wanted)), 0, MAX_BOTS)
	if not o.has("bot-level"):
		var lv := int(d.get("bot_level", sim.bot_level))
		if lv >= SimScript.BrainScript.EASY and lv <= SimScript.BrainScript.HARD:
			sim.bot_level = lv
	if not o.has("arena"):
		var n := int(d.get("arena", arena_pick))
		if n == P.ARENA_MIX or SimScript.LevelScript.PLAY.has(n):
			arena_pick = n
	if not o.has("no-powerups"):
		sim.powerups = bool(d.get("power", sim.powerups))
	if not o.has("season") and P.SEASON_PICKS.has(str(d.get("season", ""))):
		season_pick = str(d["season"])
		sim.season = _season()
	if not o.has("mode"):
		mode_teams = str(d.get("mode", "ffa")) == "teams"
	_say("🏰 [LOBBY] the settings of last time: %d bots %s, arena %s, power-ups %s, season %s, mode %s" % [bots_wanted,
		SimScript.BrainScript.NAMES[sim.bot_level], _arena_label(arena_pick), "ON" if sim.powerups else "OFF", season_pick.to_upper(),
		P.MODE_LABEL[_mode_word(mode_teams)]])

func _save_lobby() -> void:
	if lobby_path == "" or soak:
		return
	var f := FileAccess.open(lobby_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"bots": bots_wanted, "bot_level": sim.bot_level, "arena": arena_pick, "power": sim.powerups,
			"season": season_pick, "mode": _mode_word(mode_teams)}))

# p4.20 TONIGHT'S CHAMPIONS: the 8 names with the most matches won tonight (then rounds won,
# then knockouts), each [name, matches won, rounds won, knockouts, a bot?]. Only who played a match.
func _champs() -> Array:
	var out: Array = []
	for r in stats.values():
		if int(r.get("matches", 0)) > 0 or int(r.get("round_wins", 0)) > 0:
			out.append([str(r["name"]), int(r.get("match_wins", 0)), int(r.get("round_wins", 0)), int(r.get("kills", 0)), bool(r.get("bot", false))])
	out.sort_custom(func(a, b):
		if a[1] != b[1]:
			return a[1] > b[1]
		if a[2] != b[2]:
			return a[2] > b[2]
		return a[3] > b[3])
	return out.slice(0, 8)

# The seats bots sit on now (the logs: a bot's name does not say it is one).
func _bot_seats() -> Array:
	var out: Array = []
	for s in seats:
		if s.kind == 2:
			out.append(s.i)
	return out

func _set_season(pick: String, by: String) -> void:
	season_pick = pick
	sim.season = _season()
	_save_lobby()
	if phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN:
		sim.set_arena(_next_arena())     # MIX's list may have changed
	_say("🏰 [LOBBY] season %s (now %s), picked by %s" % [pick.to_upper(), P.SEASON_LABEL.get(sim.season, "NONE"), by])
	seats_dirty = true

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

# The people who waited for a bot's seat sit down (_seat_guests). The bots stay where
# they are (_keep_bots); new ones take the lowest empty seats, as many as wanted and
# fit. Then every seated person and bot gets a fighter.
func _start_round() -> void:
	_seat_guests()
	var to_place := _keep_bots()
	for s in seats:
		if to_place > 0 and s.kind == 0:
			s.kind = 2
			s.name = P.bot_name(s.i, sim.season)     # p4.19: GRAVY, STUFFING... by the season (proto.gd BOT_NAMES)
			s.points = 0                             # a new bot starts with nothing
			to_place -= 1
	for s in seats:
		# A seat a bot sat on last round and nobody sits on now (fewer bots this round): its
		# name and points go. The chaos soak found empty seats still called BOT 8 with a point.
		if s.kind == 0 and (s.name != "" or s.points != 0):
			s.name = ""
			s.points = 0
	var seat_list: Array = []
	for s in seats:
		s.in_round = s.kind != 0
		if s.in_round:
			seat_list.append({"id": s.i, "bot": s.kind == 2 or s.client_id == 0})
			var r := _stat(s)
			if r.get("_m", 0) != match_no:   # this server's match number, kept in memory only
				r["_m"] = match_no
				r["matches"] += 1
	sim.season = _season()     # p4.18 (by date too: a server left running into the next season follows it)
	sim.set_arena(_next_arena())
	if arena_pick == P.ARENA_MIX:
		mix_i += 1
	sim.start_round(seat_list)
	if start_power > 0:
		for f in sim.fighters:
			sim._give(f, start_power)
	silly = _pick_silly()      # p4.20: every third round is a silly one (0: a plain round)
	if silly > 0:
		sim.silly_round(silly)
		_say("🏰 [ROUND] %d is a silly round: %s" % [round_no, P.silly_name(silly, sim.season)])
	seats_dirty = true         # (the pages read the round's surprise from the seats message)
	round_first = true     # p4.11
	round_kills.clear()
	last_pos.clear()
	if pu_gallery:
		sim.gallery()
	round_deaths = []
	for s in seats:
		var f = sim.fighter(s.i)
		if f != null:
			f.connected = not (s.kind == 1 and s.client_id == 0)
			f.buttons = 0
	_teams_round()         # TEAMS: the bots' teams, the team's points on every seat, the sim's teams (nothing in FREE FOR ALL)
	_sync_points()
	sim.catch_up()         # p4.18: a person 2 or more points behind starts with a SHIELD
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
	# (TEAMS: 2 or more can be left, all on one team)
	_say("🏰 [MATCH] stopped after %d round%s: %d fighter%s left%s %s" % [round_no, "" if round_no == 1 else "s", n, "" if n == 1 else "s",
		"" if n < 2 else " (a team has none)", _score_line()])
	_out(0, JSON.stringify({"kind": "note", "text": "The match stopped: a match needs 2 fighters." if n < 2 else "The match stopped: a team has no fighter left."}))
	_to_lobby()

# p4.20: this round's surprise. Rounds 3, 6, 9... of a match, when power-ups are on; one the
# season plays, and not the one played last.
func _pick_silly() -> int:
	if silly_force > 0:
		return silly_force
	if silly_every <= 0 or not sim.powerups or round_no < silly_every or round_no % silly_every != 0:
		return 0
	var kinds: Array = P.silly_kinds(sim.season)
	if kinds.size() > 1:
		kinds.erase(silly_last)
	if kinds.is_empty():
		return 0
	silly_last = int(kinds[randi() % kinds.size()])
	return silly_last

func _to_lobby() -> void:
	silly = 0
	sim.clear()
	sim.reset_powers()
	sim.frozen = false
	for s in seats:
		if s.kind == 2:
			s.kind = 0
			s.name = ""
			s.points = 0      # (the match is over: an empty seat keeps no points; the soak found one with 1)
		s.in_round = false
	phase = P.PH_LOBBY
	phase_t = 0
	round_no = 0
	winner = P.NO_ONE
	match_teams = false       # TEAMS: the match is over: no teams in the sim, no team points
	team_points = [0, 0]
	win_team = -1
	sim.teams = {}
	_seat_guests()         # the bots are gone: who waited for a bot's seat sits down now
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
		# (a fighter whose seat was given up is no death in the night's numbers: and by now
		# the seat may have its next person, who must not get it. tools/v2_host_check.py
		# found that: Kid, kicked and back at once, had one death too many.)
		if victim < SEATS and seats[victim].kind != 0 and e[4] != P.C_LEFT:
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
		if e[4] == P.C_LEFT:
			_say("🏰 [KILL] seat %d's fighter left the round (its seat was given up) %.2f s after FIGHT, %d left" % [victim, when, sim.alive_count()])
		elif killer == victim:
			_say("🏰 [KILL] seat %d '%s' killed themselves (%s) %.2f s after FIGHT, %d left" % [victim, vn, cause, when, sim.alive_count()])
		elif killer < SEATS:
			_say("🏰 [KILL] seat %d '%s' killed seat %d '%s' (%s) %.2f s after FIGHT, %d left" % [killer, seats[killer].name, victim, vn, cause, when, sim.alive_count()])
		else:
			_say("🏰 [KILL] seat %d '%s' died (%s) %.2f s after FIGHT, %d left" % [victim, vn, cause, when, sim.alive_count()])

# The seat list, to one client (id) or to all (0).
func _send_seats(target: int) -> void:
	var list: Array = []
	var in_lobby := phase == P.PH_LOBBY or phase == P.PH_COUNTDOWN
	var teams_now: bool = mode_teams if in_lobby else match_teams     # TEAMS: is it what the page should show now?
	var plan: Array = _team_plan() if teams_now and in_lobby else []  # in the lobby: the bots' teams as the first round will have them
	for s in seats:
		list.append({"i": s.i, "name": s.name, "kind": s.kind, "on": s.kind == 2 or s.client_id != 0,
			"points": s.points, "crowns": s.crowns, "in": s.in_round,
			"team": -1 if not teams_now else (int(plan[s.i]) if not plan.is_empty() else (s.team if s.kind != 0 else -1))})
	var msg := {"kind": "seats", "phase": phase, "round": round_no, "goal": goal if goal > 0 else _goal_next(),
		"bots": _bots_now(), "bots_wanted": bots_wanted, "bot_level": sim.bot_level, "power": 1 if sim.powerups else 0,
		"awards": last_awards,
		"people": _people(), "arena": arena_pick, "arena_now": sim.level.id,
		"season": _season(), "season_pick": season_pick,
		"sleeps": _sleeps(),      # p4.22: nights to Christmas by this computer's date (-1: not 1 to 25 December)
		"silly": silly if phase >= P.PH_ROUND_START else 0,     # p4.20: this round's surprise (the ROUND banner says it)
		"champs": _champs(),      # p4.20 TONIGHT'S CHAMPIONS (client/lobby_champs.gd)
		"names": _names_list(),
		"mode": _mode_word(teams_now), "mode_pick": _mode_word(mode_teams), "team_names": P.team_names(_season()),
		"team_points": team_points, "teams_ok": not mode_teams or _teams_ok(),
		"seats": list}
	_out(target, JSON.stringify(msg))
	if target == 0:
		seats_dirty = false

# ------------------------------------------------------------------ TEAMS
# The lobby's MODE is FREE FOR ALL or TEAMS (mode_teams; kept in lobby_settings.json).
# In TEAMS every seat has a team, 0 or 1 (Seat.team):
#   - a new person goes to the team with fewer people (_smaller_team);
#   - a person changes sides with a tap on their own card ("team"), only in the lobby;
#   - the bots are spread at each round's start so the teams are as even as they can
#     be (_team_plan, _teams_round);
#   - a match starts only when both teams have a fighter (_teams_ok, TEAMS_NEED).
# A match keeps the mode it began with (match_teams). The sim knows the round's teams
# (sim.teams): a teammate cannot hurt you, and a round ends when one team is left
# (sim.gd). The winning team gets ONE point (team_points), shown on every one of its
# seats, so the snapshot, the HUD, the catch-up SHIELD and the BIG power-ups all work
# from a seat's points as they do in FREE FOR ALL.
const TEAMS_NEED := "TEAMS needs a fighter on each team: tap your card to change sides, or add a bot."

static func _mode_word(teams: bool) -> String:
	return "teams" if teams else "ffa"

# The lobby's MODE changes (a player in the lobby, or the host at any time: then it
# counts from the next match).
func _set_mode(teams: bool, by: String) -> void:
	mode_teams = teams
	_save_lobby()
	_say("🏰 [LOBBY] mode %s, picked by %s" % [P.MODE_LABEL[_mode_word(teams)], by])
	seats_dirty = true

# The team with fewer people (a tie: the first team). skip: a seat that does not count
# (the one being seated right now).
func _smaller_team(skip: int = -1) -> int:
	var n := [0, 0]
	for s in seats:
		if s.kind == 1 and s.i != skip:
			n[s.team] += 1
	return 1 if n[1] < n[0] else 0

# Each seat's team as the next round will have it: a person's own team; then the bots
# (they take the lowest seats no person sits on, as _start_round places them), one by
# one, each to the team with fewer fighters so far. A tie: the team with fewer people
# (the spare bot helps the side with fewer people), then the first team. -1: nobody
# will sit there.
func _team_plan() -> Array:
	var plan: Array = []
	var n := [0, 0]
	var people := [0, 0]
	for s in seats:
		plan.append(s.team if s.kind == 1 else -1)
		if s.kind == 1:
			n[s.team] += 1
			people[s.team] += 1
	var bots := _bots_now()
	for s in seats:
		if bots > 0 and s.kind != 1:
			var t := 0
			if n[1] != n[0]:
				t = 1 if n[1] < n[0] else 0
			elif people[1] != people[0]:
				t = 1 if people[1] < people[0] else 0
			plan[s.i] = t
			n[t] += 1
			bots -= 1
	return plan

# Will both teams have a fighter (people and bots) in the next round?
func _teams_ok() -> bool:
	var plan := _team_plan()
	return plan.has(0) and plan.has(1)

# A round starts (_start_round calls it once the bots sit and the fighters stand): the
# bots get their teams, every seat shows its team's points, and the sim learns who is
# with whom. In FREE FOR ALL: the sim has no teams, and nothing else happens.
func _teams_round() -> void:
	sim.teams = {}
	win_team = -1
	if not match_teams:
		return
	var plan := _team_plan()
	for s in seats:
		if s.kind == 0:
			continue
		if s.kind == 2 and int(plan[s.i]) >= 0:
			s.team = int(plan[s.i])
		s.points = team_points[s.team]
		if s.in_round:
			sim.teams[s.i] = s.team

# The seats on a team now (people and bots).
func _team_seats(team: int) -> Array:
	var out: Array = []
	for s in seats:
		if s.kind != 0 and s.team == team:
			out.append(s.i)
	return out

# A team's members by name, for a log line.
func _team_line(team: int) -> String:
	var names: Array = []
	for i in _team_seats(team):
		names.append(seats[i].name)
	return ", ".join(names)

# The round's teams by seat for the round's log line: -1 for a seat with no fighter.
func _round_teams() -> Array:
	var out: Array = []
	for s in seats:
		out.append(int(sim.teams.get(s.i, -1)))
	return out

# Did seat i win the round that was just called? FREE FOR ALL: the winner's seat.
# TEAMS: every seat that fought for the winning team (alive at the end or not).
func _won(i: int) -> bool:
	if winner == P.NO_ONE:
		return false
	return i == winner if win_team < 0 else int(sim.teams.get(i, -1)) == win_team

# TEAMS, 1.5 s after a round is called: the winning team's point. One point for the
# team, shown on every seat of it. Returns the seat that stands for the team from here
# on (the match's end shows that player's hero and replays their knockouts): the one
# with the most knockouts in the match, a person before a bot, then the lowest seat.
# Nobody (P.NO_ONE) after a draw, or when nobody of the team is left on a seat (they
# all left in these 1.5 s: no point, as for an empty seat in FREE FOR ALL).
func _team_point() -> int:
	if win_team < 0:
		return P.NO_ONE
	var members := _team_seats(win_team)
	if members.is_empty():
		_say("🏰 [ROUND] %d: no point: nobody of %s is left" % [round_no, P.team_name(win_team, sim.season)])
		return P.NO_ONE
	team_points[win_team] += 1
	for i in members:
		seats[i].points = team_points[win_team]
	return _team_best(win_team)

# A team's best player: the seat with the most knockouts in this match, a person before
# a bot, then the lowest seat. P.NO_ONE when the team has no seat.
func _team_best(team: int) -> int:
	var best: int = P.NO_ONE
	for i in _team_seats(team):
		if best == P.NO_ONE:
			best = i
			continue
		var k := int(mstats.get(i, {}).get("kills", 0))
		var bk := int(mstats.get(best, {}).get("kills", 0))
		if k > bk or (k == bk and seats[i].kind == 1 and seats[best].kind != 1):
			best = i
	return best

# The points a match would be played to if it started now (the lobby shows it).
# TowerFall's rule by the number of sides: in TEAMS there are two.
func _goal_next() -> int:
	return goal_override if goal_override > 0 else _goal_for(2 if mode_teams else _people() + _bots_now())

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
			c.fail_run = 0
		else:
			c.send_fail += 1
			c.fail_run += 1
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
			if c.opened:
				# bug 12: it was open and is half closed now. A goodbye takes a moment; one that
				# hangs (the server cannot send to it) is a drop, and the seats must hear of it.
				if c.closing_ms == 0:
					c.closing_ms = now
				elif now - c.closing_ms > CLOSING_MS:
					_inbox("close", c.id, CLOSE_STUCK)
					clients.remove_at(i)
			elif now - c.since_ms > 8000:
				print("🏰 [NET] client %d (%s) never finished the websocket handshake" % [c.id, c.ip])
				clients.remove_at(i)
			continue
		if not c.opened:
			c.opened = true
			c.last_in_ms = now
			_inbox("open", c.id, c.ip)
		var got := false
		while c.ws.get_available_packet_count() > 0:
			var pkt := c.ws.get_packet()
			got = true
			c.bytes_in += pkt.size()
			bytes_in_sec += pkt.size()
			if c.ws.was_string_packet():
				_inbox("text", c.id, pkt.get_string_from_utf8())
			elif pkt.size() > 0:
				_on_binary(c, pkt)
		if got:
			c.last_in_ms = now
		elif now - c.last_in_ms > SILENT_MS:
			# bug 5: nothing for 3 s: a frozen page or a dead link. Close it and tell the seats.
			c.ws.close(CLOSE_SILENT, "silent")
			c.ws.poll()
			_inbox("close", c.id, CLOSE_SILENT)
			clients.remove_at(i)
		elif c.fail_run >= SEND_FAIL_MAX:
			# bug 12: it talks but does not read: 1 MB waits for it. A drop too.
			_inbox("close", c.id, CLOSE_BLOCKED)
			clients.remove_at(i)

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

# p4.9: who took which power-up (a [POWER] line and a "power" line in v2_server.jsonl),
# and the lightning, the freeze and the BIG drops for the log.
func _log_powers(evs: Array) -> void:
	for e in evs:
		var k: int = e[0]
		if k == P.E_PU_GET:
			var i: int = e[3]
			var who: String = seats[i].name if i >= 0 and i < SEATS else "?"
			_say("🏰 [POWER] seat %d '%s' took %s%s" % [i, who, P.pu_name(e[4], sim.season), " (BIG)" if P.is_big(e[4]) else ""])
			server_log.store_line(JSON.stringify({"kind": "power", "t": Time.get_unix_time_from_system(), "match": match_no,
				"round": round_no, "seat": i, "name": who, "power": P.pu_name(e[4], sim.season), "s": snappedf(_round_secs(), 0.01)}))
		elif k == P.E_PU_WARN and e[4] == 1:
			_say("🏰 [POWER] a BIG %s comes for someone behind" % P.pu_name(e[3], sim.season))
		elif k == P.E_TRICK and e[4] > 0:
			# p4.18: every result has a name now (the costume, 4, had none: a script error on each GHOSTFACE)
			var ti: int = e[3]
			_say("🏰 [POWER] seat %d '%s' got a TRICK: %s" % [ti, seats[ti].name if ti < SEATS else "?", P.trick_name(e[4], sim.season)])
		elif k == P.E_CANDY_GET:
			var ci: int = e[3]
			_say("🏰 [POWER] seat %d '%s' opened a %s" % [ci, seats[ci].name if ci < SEATS else "?", P.candy_word(sim.season)])
		elif k == P.E_PET:
			var pi: int = e[3]
			_say("🏰 [POWER] seat %d '%s' %s" % [pi, seats[pi].name if pi < SEATS else "?", ["petted the black cat: a SHIELD", "caught the turkey", "rides the reindeer"][clampi(e[4], 0, 2)]])
		elif k == P.E_CATCH_UP:
			var ui: int = e[3]
			_say("🏰 [POWER] seat %d '%s' starts with a SHIELD (behind the leader)" % [ui, seats[ui].name if ui < SEATS else "?"])
		elif k == P.E_PHEW:
			# the winner is safe: a hit after the round was called did not kill it (a line for the night's report)
			var wi: int = e[3]
			var what: String = ["an arrow", "a blast", "something else"][clampi(e[4], 0, 2)]
			_say("🏰 [ROUND] %d PHEW: %s could not kill the winner, seat %d '%s' (the round was called)" % [round_no, what, wi, seats[wi].name if wi < SEATS else "?"])
			server_log.store_line(JSON.stringify({"kind": "phew", "t": Time.get_unix_time_from_system(), "match": match_no,
				"round": round_no, "seat": wi, "name": seats[wi].name if wi < SEATS else "?", "what": e[4]}))

# p4.11: this match's numbers by seat (the awards), from the events.
func _mcount(seat: int, key: String, n: int = 1) -> void:
	if seat < 0 or seat >= SEATS or key == "":
		return
	if not mstats.has(seat):
		mstats[seat] = {}
	mstats[seat][key] = int(mstats[seat].get(key, 0)) + n

func _match_events(evs: Array) -> void:
	if phase < P.PH_PLAY or phase > P.PH_ROUND_END:
		return
	var hv: bool = sim.season == "harvest"   # p4.18: the Harvest season's awards have their own numbers
	var xm: bool = sim.season == "christmas" # p4.22: and the Christmas season's
	for e in evs:
		var k: int = e[0]
		if k == P.E_JUMP and e[4] != 1:
			_mcount(e[3], "jumps")
		elif k == P.E_DODGE:
			_mcount(e[3], "dodges")
		elif k == P.E_SHOOT:
			_mcount(e[3], "shots")
		elif k == P.E_DRYFIRE:
			_mcount(e[3], "dryfires")
		elif k == P.E_CATCH:
			_mcount(e[3], "catches")
		elif k == P.E_PICKUP:
			_mcount(e[3], "leftovers" if hv else "pickups")
		elif k == P.E_PU_GET:
			_mcount(e[3], "powers")
			if P.is_big(e[4]):
				_mcount(e[3], "bigs")
			if e[4] == P.PU_MASK:
				_mcount(e[3], "big_turkeys" if hv else ("krampuses" if xm else "masks"))
		elif k == P.E_DEATH and e[4] != P.C_LEFT:   # (a fighter whose seat was given up is no death for the awards)
			_mcount(e[3], "deaths")
			_mcount(e[3], CAUSE_KEY.get(e[4], ""))
			last_cause[e[3]] = e[4]
			if round_first:
				round_first = false
				_mcount(e[3], "fruitcake" if xm else "first_out")
		elif k == P.E_KILL and e[3] < SEATS:
			if e[3] == e[4]:
				_mcount(e[3], "self_kills")
			else:
				_mcount(e[3], "kills")
				round_kills[e[3]] = int(round_kills.get(e[3], 0)) + 1
				if xm:
					_mcount(e[3], "naughty")
				var c: int = last_cause.get(e[4], 0)
				_mcount(e[3], {1: "arrow_kills", 2: "blast_kills", 3: "stomp_kills", 8: "cat_kills", 11: "peck_kills" if hv else ("sack_kills" if xm else "knife_kills")}.get(c, ""))
				if e[4] < SEATS and sim.fighter(e[4]) != null and sim.fighter(e[4]).mask:
					_mcount(e[3], "turkey_ends" if hv else ("krampus_ends" if xm else "mask_kills"))   # finished GHOSTFACE off while it was down
		elif k == P.E_PIN:
			_mcount(e[3], "pinned")
			var pf = sim.fighter(e[3])
			if pf != null and pf.killer < SEATS:
				_mcount(pf.killer, "pin_kills")
		elif k == P.E_BOO and e[4] != 255:
			_mcount(e[3], "boos")
		elif k == P.E_PET:
			_mcount(e[3], ["pets", "turkeys", "rides"][clampi(e[4], 0, 2)])
		elif k == P.E_TRICK and e[4] > 0:
			_mcount(e[3], "coal" if xm and e[4] <= 3 else "tricks")
		elif k == P.E_CANDY_GET:
			_mcount(e[3], "dishes" if hv else ("presents" if xm else "candies"))
		elif k == P.E_SNOW:
			snow_by = e[3]
		elif k == P.E_SNOWED and snow_by >= 0 and snow_by != e[3]:
			_mcount(snow_by, "snowed")
		elif k == P.E_PIED:
			_mcount(e[3], "pied")

# Each tick of play: who is in the fight, in the air, flying, invisible, a ghost, and the steps run.
func _match_sample() -> void:
	for f in sim.fighters:
		if f.state != P.F_DEAD:
			_mcount(f.id, "alive")
			if not f.on_ground:
				_mcount(f.id, "air")
			if f.fly:
				_mcount(f.id, "fly")
			if f.invis_t > 0:
				_mcount(f.id, "invis")
			if last_pos.has(f.id):
				var dx := absf(SimScript.wrap_d(last_pos[f.id].x, f.x, 1920.0))
				if dx < 40.0:
					_mcount(f.id, "distance", int(dx))
			last_pos[f.id] = Vector2(f.x, f.y)
		elif f.ghost:
			_mcount(f.id, "ghost")

# The match's awards: [{seat, name, title, why}]. Each award goes to whoever leads it
# (a tie of 3 or more: nobody; a "min" award only with 3 players or more and one clear
# one). Everyone gets one: the rarest award they lead, else a silly one; then up to 3
# more of the awards nobody got yet.
func _awards() -> Array:
	var played: Array = []
	for st in seats:
		if st.kind != 0 and mstats.has(st.i):
			played.append(st.i)
	if played.is_empty():
		return []
	var leads: Array = []      # [award index, [seats], value]
	for ai in AWARDS.size():
		var aw: Array = AWARDS[ai]
		var best := NAN
		var who: Array = []
		for i in played:
			var v := float(mstats[i].get(aw[1], 0))
			if is_nan(best) or (aw[2] == "max" and v > best) or (aw[2] == "min" and v < best):
				best = v
				who = [i]
			elif v == best:
				who.append(i)
		if is_nan(best) or who.size() > 2:
			continue
		if aw[2] == "max" and best < float(aw[3]):
			continue
		if aw[2] == "min" and (played.size() < 3 or who.size() > 1):
			continue
		leads.append([ai, who, best])
	var order := played.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j: int = sim.rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var out: Array = []
	var used := {}
	var got := {}
	for i in order:
		var pick = null
		for L in leads:
			if used.has(L[0]) or not (i in L[1]):
				continue
			if pick == null or L[1].size() < pick[1].size():
				pick = L
		if pick != null:
			used[pick[0]] = true
			got[i] = true
			out.append(_award_line(i, AWARDS[pick[0]], pick[2]))
	var fb: int = sim.rng.randi() % FALLBACK.size()
	for i in order:
		if not got.has(i):
			var f: Array = FALLBACK[fb % FALLBACK.size()]
			fb += 1
			out.append({"seat": i, "name": seats[i].name, "title": f[0], "why": f[1], "bot": seats[i].kind == 2})
	var extra := 0
	for L in leads:
		if extra >= 3:
			break
		if used.has(L[0]):
			continue
		used[L[0]] = true
		extra += 1
		out.append(_award_line(L[1][0], AWARDS[L[0]], L[2]))
	return out

func _award_line(seat: int, aw: Array, value: float) -> Dictionary:
	var n := int(value)
	if aw[5] == "s":
		n = int(round(value / 60.0))
	elif aw[5] == "steps":
		n = int(round(value / 30.0))
	var why: String = aw[4] % n
	if n == 1:   # one of them, not ones
		for pl in [" knockouts", " times", " power-ups", " stomps", " arrows", " jumps", " dodges", " players", " rounds", " seconds", " steps"]:
			why = why.replace(pl, pl.substr(0, pl.length() - 1))
	return {"seat": seat, "name": seats[seat].name, "title": aw[0], "why": why, "bot": seats[seat].kind == 2}

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
# p4.18 WHO ARE YOU? (the page's name picker): the names people typed, with how often each
# took a seat, kept across nights in <out>/known_names.json. The first time, it is filled
# from the old nights' v2_stats.json files. Default names (Player 3) and bots do not count,
# and a name that differs only in its capitals joins the one already there.
var known_names := {}
var names_path := ""

func _load_names(root: String) -> void:
	names_path = root.path_join("known_names.json")
	if FileAccess.file_exists(names_path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(names_path))
		if typeof(d) == TYPE_DICTIONARY:
			for k in d:
				var kn := clean_name(str(k))    # (a name kept under the old rule may hold what clean_name drops now)
				if kn != "":
					known_names[kn] = int(known_names.get(kn, 0)) + _int(d[k], 0)
		return
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for sub in dir.get_directories():
		var sp := root.path_join(sub).path_join("v2_stats.json")
		if not FileAccess.file_exists(sp):
			continue
		var sd = JSON.parse_string(FileAccess.get_file_as_string(sp))
		if typeof(sd) != TYPE_DICTIONARY:
			continue
		for r in sd.get("players", []):
			if typeof(r) == TYPE_DICTIONARY and not bool(r.get("bot", false)):
				_know(str(r.get("name", "")), maxi(1, int(r.get("matches", 1))), false)
	_save_names()

func _know(name: String, n: int = 1, save: bool = true) -> void:
	name = clean_name(name)     # (the old nights' v2_stats.json files hold names from before the cleaning)
	if name == "" or name.begins_with("Player") or name.begins_with("BOT "):
		return
	var key := name
	for k in known_names:
		if str(k).to_lower() == name.to_lower():
			key = str(k)
			break
	known_names[key] = int(known_names.get(key, 0)) + n
	if save:
		_save_names()
		seats_dirty = true

func _save_names() -> void:
	if names_path == "":
		return
	var f := FileAccess.open(names_path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(known_names))

# The 12 names that sat down most often, the most often first.
func _names_list() -> Array:
	var ks: Array = known_names.keys()
	ks.sort_custom(func(a, b): return int(known_names[a]) > int(known_names[b]) or (int(known_names[a]) == int(known_names[b]) and str(a) < str(b)))
	return ks.slice(0, 12)

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
			var n := clampi(_int(d.get("n"), bots_wanted), 0, MAX_BOTS)
			bots_wanted = n
			seats_dirty = true
			_save_lobby()
			_say("🏰 [HOST] bots %d%s" % [n, later])
			return [true, "Bots: %d%s." % [n, later]]
		"bot_level":
			var lv := _int(d.get("n"), -1)
			if lv < SimScript.BrainScript.EASY or lv > SimScript.BrainScript.HARD:
				return [false, "The bots' level is 1 (EASY), 2 (NORMAL) or 3 (HARD)."]
			sim.bot_level = lv
			seats_dirty = true
			_save_lobby()
			_say("🏰 [HOST] bots %s%s" % [SimScript.BrainScript.NAMES[lv], later])
			return [true, "Bots %s%s." % [SimScript.BrainScript.NAMES[lv], later]]
		"arena":
			var n := _int(d.get("n"), -99)
			if n != P.ARENA_MIX and not SimScript.LevelScript.PLAY.has(n):
				return [false, "No arena %d." % n]
			arena_pick = n
			if not in_match:
				sim.set_arena(_next_arena())
			seats_dirty = true
			_save_lobby()
			_say("🏰 [HOST] arena %s%s" % [_arena_label(n), later])
			return [true, "Arena %s%s." % [_arena_label(n), later]]
		"kick":
			var i := _int(d.get("seat"), -1)
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
		"season":
			var pick := str(d.get("pick", ""))
			if not P.SEASON_PICKS.has(pick):
				return [false, "A season is one of: %s." % ", ".join(P.SEASON_PICKS)]
			_set_season(pick, "the host")
			return [true, "Season %s (now %s)." % [pick.to_upper(), P.SEASON_LABEL.get(sim.season, "NONE")]]
		"power":
			sim.powerups = _int(d.get("n"), 0) != 0
			seats_dirty = true
			_save_lobby()
			_say("🏰 [HOST] power-ups %s" % ("ON" if sim.powerups else "OFF"))
			return [true, "Power-ups %s, from now." % ("ON" if sim.powerups else "OFF")]
		"mode":
			var pick := str(d.get("pick", ""))
			if not P.MODES.has(pick):
				return [false, "A mode is one of: %s." % ", ".join(P.MODES)]
			var next := " from the next match" if in_match else ""
			_set_mode(pick == "teams", "the host" + next)
			return [true, "Mode %s%s." % [P.MODE_LABEL[pick], next]]
		"start":
			if phase != P.PH_LOBBY:
				return [false, "A match is already on."]
			if _people() + _bots_now() < 2:
				return [false, "A match needs 2 fighters: add a bot."]
			if mode_teams and not _teams_ok():
				return [false, TEAMS_NEED]
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
# p4.18 THE BIG SCREEN (the page's ?tv): the addresses phones open, and a QR code of the first
# one as rows of 0 and 1 (made by the qrencode tool once and kept; none without the tool: the
# page then shows the address alone).
var _tv_cache := {}
func _tv_info() -> Dictionary:
	var urls: Array = []
	for ip in _lan_ips():
		urls.append("https://%s:8443/v2/" % ip)
	var key := ",".join(urls)
	if str(_tv_cache.get("key", "?")) != key:
		var rows: Array = []
		if not urls.is_empty():
			var out: Array = []
			if OS.execute("qrencode", ["-t", "ASCII", "-m", "0", str(urls[0])], out) == 0 and not out.is_empty():
				for line in str(out[0]).split("\n", false):
					var row := ""
					for i in range(0, line.length(), 2):
						row += "1" if line[i] == "#" else "0"
					rows.append(row)
		_tv_cache = {"key": key, "kind": "tv", "urls": urls, "qr": rows}
	return _tv_cache

func _lan_ips() -> Array:
	var out: Array = []
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10."):
			out.append(a)
	out.sort()
	return out

func _host_state() -> Dictionary:
	var in_match_now := phase != P.PH_LOBBY and phase != P.PH_COUNTDOWN
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
			"points": s.points, "crowns": s.crowns, "in_round": s.in_round, "team": s.team if s.kind != 0 else -1,
			"ip": c.ip if c != null else "", "ping_ms": pings.get(s.client_id, -1), "client": s.client_id, "phone": _phone(c)})
	var watching: Array = []
	for id in conns:
		var c: Conn = conns[id]
		if c.ok and c.seat < 0:
			watching.append({"client": c.id, "name": c.name, "ip": c.ip, "ping_ms": pings.get(c.id, -1), "phone": _phone(c),
				"waits_for": c.wait_seat})   # the bot's seat this one gets when the round is over (-1: it only watches)
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
		"goal": goal if goal > 0 else _goal_next(),
		"match": match_no, "arena_pick": arena_pick, "arena_pick_name": _arena_label(arena_pick),
		"arena_now": sim.level.id, "arena_now_name": sim.level.name, "arenas": arenas,
		"bots_wanted": bots_wanted, "bots_now": _bots_now(), "max_bots": MAX_BOTS,
		"bot_level": sim.bot_level, "bot_level_name": SimScript.BrainScript.NAMES[sim.bot_level], "levels": levels,
		"power_arrows": sim.powerups, "powerups": sim.powerups,   # p4.9: the host page's switch is the power-ups
		"people": _people(), "watchers": watching.size(), "lan": _lan_ips(), "page_port": 8443, "game_port": port,
		"season": _season(), "season_pick": season_pick, "seasons": P.SEASON_PICKS,
		"mode": _mode_word(mode_teams), "mode_now": _mode_word(match_teams if in_match_now else mode_teams), "modes": P.MODES,
		"team_names": P.team_names(_season()), "team_points": team_points, "teams_ok": not mode_teams or _teams_ok(),
		"seats": seat_list, "watching": watching,
		"tick": {"mean_ms": last_rec.get("tick_mean_ms", 0.0), "max_ms": last_rec.get("tick_max_ms", 0.0),
			"cpu_pct": last_rec.get("cpu_pct", 0.0), "rss_mb": last_rec.get("rss_mb", 0.0)},
		"stats_since": stats_since, "stats": people_rows + bot_rows, "events": events_ring}

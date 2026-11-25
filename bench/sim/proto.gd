# The game's packet and entity codes, shared by the server (server/game_server.gd),
# the clients (client/net.gd), the benchmark (server/bench_server.gd) and the Python
# fake players (tools/v2_synth.py, tools/bench_synth.py copy the numbers).
# All binary, little endian.
#   snapshot  u8 T_SNAP, u32 tick, u8 phase, u8 round, u16 phase ticks left, u8 goal,
#             u8 winner (NO_ONE = none), u16 walls (each purple wall's width in px,
#             + 0x8000 when they kill), u8 arena (G5: the layout in sim/level.gd),
#             u8 fighters, u16 arrows, u8 zones, u16 events,
#             fighter x14 B, arrow x8 B (stuck) or x21 B (in the air), zone x9 B, event x7 B,
#             then (p4.9, the power-ups; older readers stop after the events) u8 PW_TAG,
#             u8 n, n x (u8 seat, u16 PW_* bits, u8 arrow kind, u8 quarter seconds left of
#             its BIG power-up), u8 orbs, orb x (u8 state, u8 kind, u8 big, s16 x, s16 y,
#             u8 progress 0..255, u8 the seat a BIG one came for), u8 cats, cat x (u8 owner,
#             u8 target, s16 x, s16 y), u8 the rain's owner (NO_ONE: no rain), u8 its quarter
#             seconds left, u8 ghosts, ghost x (p4.11: u8 seat, s16 x, s16 y, u8 flags: 1 popped,
#             2 dashing, 4 ready to BOO), (p4.12) u8 the black cat is here, then s16 x, s16 y,
#             s8 dir, u8 leaving (p4.12: each power-up row has one more byte: 1 GHOSTFACE, 2 down,
#             4 swinging, 8 the knife up); u8 a bat swarm's phase (p4.13: then u8 candies, each s16 x,
#             s16 y, u8 life left / 4 ticks, u8 1 resting, 2 from the sky) (255: none; 0 screeching, 1 sweeping),
#             then s16 x, s16 y, s8 dir; then u8 1 with THE BOILER ROOM's state (sim/boiler.gd)
#   fighter   u8 seat, u8 state, s16 x, s16 y, s8 vx, s8 vy, u8 flags, u8 aim (256 steps),
#             u8 arrows, u8 state ticks, u8 points, u8 flags2
#   arrow     u16 id, u8 kind | state << 4 | 0x40 a BIG arrow (p4.9), then stuck or in a body (p4.10): s16 x, s16 y, u8 angle (256 steps);
#             in the air (P2: the client flies it on to its own tick): f32 x, f32 y,
#             f32 vx, f32 vy (px per tick), u8 age (ticks, at most 255), u8 owner (seat)
#   input     (u8 T_INPUT, u32 tick, u8 buttons, u16 aim in 0.1 degree steps) x4 (the last 4 ticks).
#             The tick is the server tick the input is for (P2): the client runs ahead
#             of the server, and the server applies input N just before tick N.
#   ping      u8 T_PING, u32 client ms, u16 last rtt ms, u16 worst snapshot gap ms
#   pong      u8 T_PONG, u32 client ms (echoed), u32 server tick
#   own       u8 T_OWN, u32 tick, u32 the newest input tick used, s8 margin (how many
#             ticks early the inputs that came since the last T_OWN were, the smallest;
#             NO_MARGIN: none came), u8 late (inputs that came after their tick, since
#             the last), u8 OWN_* flags, u32 moves_from (the first tick the fighters move
#             after ROUND START; 0 when that is not ahead), then the fighter's whole
#             state (sim.gd write_fighter_state) when OWN_FIGHTER. To each seated person
#             after each snapshot (P2: their clock, prediction and reconciliation).
# Text frames are JSON, {"kind": ...}: hello, join, leave, start, bots, arena, name from a
# client; welcome, version_error, full, seats, round_end, match_end from the server
# (the fields are listed in server/game_server.gd). The benchmark adds bench_card.
extends RefCounted

# The game's version. tools/v2_build.sh bumps the last number on every build and
# names the pck after it; the server turns away a client with another version.
const VERSION := "v0.2.0-p4.18"

const PORT := 8091
const T_SNAP := 1
const T_INPUT := 2
const T_PING := 3
const T_PONG := 4
const T_OWN := 5
const NO_MARGIN := 127
const OWN_FIGHTER := 1    # T_OWN flags: you have a fighter this round (its state follows)
const OWN_BRAIN := 2      # the brain plays it (your socket was gone)

# input buttons (one byte)
const B_LEFT := 1
const B_RIGHT := 2
const B_UP := 4           # the stick points up: a dodge goes that way (W on the keyboard also jumps)
const B_DOWN := 8         # held: fall faster, drop through a ledge with jump, a dodge goes down
const B_JUMP := 16        # held: a higher jump
const B_SHOOT := 32       # held: aim (standing still on the ground); let go: fire
const B_DODGE := 64
const B_CANCEL := 128      # p4.4: let go of shoot with this: the bow comes down, no arrow (a phone's thumb let go inside the ring; a bot that lowers its bow)

# the match, in the snapshot header
const PH_LOBBY := 0
const PH_COUNTDOWN := 1   # START was pressed: 3 s
const PH_ROUND_START := 2 # the fighters stand on their spots, nobody moves: 1.5 s
const PH_PLAY := 3
const PH_ROUND_END := 4   # one fighter left (1.5 s), or none (a draw)
const PH_MATCH_END := 5   # the winner, 7 s, then the lobby
const NO_ONE := 255
const ARENA_MIX := -1     # the lobby's ARENA (G5): MIX, the arenas take turns each round; else one layout

# fighter states
const F_NORMAL := 0
const F_DODGE := 1
const F_DEAD := 2
const F_HURT := 3         # knocked back by a blast or a hard bump, no control
const F_LEDGE := 4        # hanging from a ledge

# arrow kinds (the bench's power-ups) and states
const A_NORMAL := 0
const A_FIRE := 1
const A_BOMB := 2
const A_MIASMA := 3
const A_SMOKE := 4        # a thick smoke cloud: no damage, bots cannot see through it
const A_PUMPKIN := 5      # p4.12 PUMPKIN BOMBS: a smaller blast, then 5 seeds fly out and pop
const A_SEED := 6         # a pumpkin's seed: it pops in a small blast on a wall, a fighter, or after a moment
const A_PIE := 7          # p4.18 PIE: it splats where it lands: a small blast, cream on everyone near
const S_FLY := 0
const S_FALL := 1
const S_STUCK := 2
const S_BODY := 3         # p4.10: in the body it killed (carried with it; it pins the body to a wall it meets)

# zones left on the ground
const Z_FIRE := 1
const Z_MIASMA := 2
const Z_SMOKE := 3

# p4.9 power-ups (the user, 2026-10-24: the power arrows' randomness made them hard to
# use; orbs dropped by lightning instead). The kinds an orb holds: 1..4 are the arrow
# kinds (a fighter's shots take that kind for the rest of the match), then the other
# regular ones (p4.10: one round), then the BIG ones (for whoever is behind the leader,
# p4.10 bots too; they land near the person furthest behind; this round).
const PU_FIRE := 1
const PU_BOMB := 2
const PU_POISON := 3
const PU_SMOKE := 4
const PU_SHIELD := 5       # takes one arrow (not a stomp); p4.10: SHIELD, INF, FLY and BIG last one round
const PU_INF := 6          # the quiver never empties
const PU_FLY := 7          # the stick floats you any way (p4.10: bots fly too)
const PU_BIG := 8          # arrows 3 times as big, their blast, fire and clouds 3 times the area
const PU_CATS := 9         # BIG: 3 ghost cats hunt the nearest enemies (the user's daughter's idea)
const PU_RAIN := 10        # BIG: everyone else runs slower for 8 s; your umbrella stops stomps
const PU_INVIS := 11       # BIG: invisible 3 s, seen 1 s, for 12 s
const PU_FREEZE := 12      # BIG: everyone else frozen for 2.5 s
const PU_SPIKES := 13      # BIG: a shield that comes back 3 s after each arrow, spikes kill a stomper, 20 s
const PU_SPEED := 14       # BIG: run 1.6 times as fast for 10 s
const PU_TRICK := 15       # p4.12 TRICK OR TREAT: a treat (a random power-up) or a silly trick (pumpkin, backwards, tiny)
const PU_PUMPKIN := 16     # PUMPKIN BOMBS (BOMB ARROWS' Halloween twin, on THE HAUNTED HOUSE): an arrow kind, all match
const PU_BATS := 17        # BIG: a bat swarm circles you 8 s, knocks arrows away and hides you
const PU_MASK := 18        # GHOSTFACE, from TRICK OR TREAT (the user's daughter's favourite): no bow this round,
                           # a knife swing instead; a hit knocks you down 2 s, a hit while down is the end
const PU_PIE := 19        # p4.18 the Harvest season: every arrow is a cream pie: a small blast, and whoever is near the
                           # splat is covered in cream PIED_TICKS (they see nobody, like in smoke); an arrow kind, all match
const PU_NAMES := {1: "FIRE ARROWS", 2: "BOMB ARROWS", 3: "POISON ARROWS", 4: "SMOKE ARROWS", 5: "SHIELD",
	6: "INFINITE ARROWS", 7: "FLYING", 8: "BIG ARROWS", 9: "GHOST CATS", 10: "RAIN", 11: "INVISIBLE",
	12: "FREEZE", 13: "SPIKED SHIELD", 14: "SUPER SPEED", 15: "TRICK OR TREAT", 16: "PUMPKIN BOMBS", 17: "BAT SWARM",
	18: "GHOSTFACE", 19: "PIE"}
const PU_SHORT := {1: "FIRE", 2: "BOMB", 3: "POISON", 4: "SMOKE", 5: "SHIELD", 6: "INFINITE", 7: "FLY", 8: "BIG",
	9: "CATS", 10: "RAIN", 11: "INVISIBLE", 12: "FREEZE", 13: "SPIKES", 14: "SPEED", 15: "TRICK?", 16: "PUMPKIN", 17: "BATS",
	18: "GHOSTFACE", 19: "PIE"}
# what each one does, in a line (the page says it when you take one)
const PU_HELP := {1: "every arrow you shoot sets the floor on fire, all match",
	2: "every arrow you shoot blows up, all match", 3: "every arrow you shoot leaves a poison cloud, all match",
	4: "every arrow leaves smoke: whoever stands in it cannot see anyone, all match",
	5: "the next arrow that hits you bounces off this round (stomps still count)", 6: "your arrows never run out, this round",
	7: "move the stick any way to float around, this round", 8: "your arrows and their blasts are huge, this round",
	9: "three ghost cats hunt the nearest players (dodge one to stop it)", 10: "everyone else is slow in the rain; your umbrella stops stomps",
	11: "you blink out of sight: 3 seconds gone, 1 second seen", 12: "everyone else is frozen solid for a moment",
	13: "arrows bounce off (it comes back), and spikes on top kill anyone who stomps you", 14: "you run super fast",
	15: "a treat (a power-up) or a silly trick", 16: "every arrow is a pumpkin: it bursts into seeds that pop, all match",
	17: "bats circle you: they knock arrows away and hide you",
	18: "no bow this round: let go of shoot to swing your knife; a hit knocks you down 2 seconds, a hit while you're down ends you",
	19: "every arrow is a cream pie: it bursts, and everyone near the splat cannot see for 3 seconds, all match"}
const ORB_WARN := 0        # an orb's states: the lightning builds up over its spot
const ORB_LIVE := 1        # it struck: the orb waits to be taken
const PW_TAG := 0xB5       # the snapshot's power-up part starts with this byte
# a fighter's power bits (the snapshot's power-up part)
const PW_SHIELD := 1
const PW_INF := 2
const PW_FLY := 4
const PW_BIG := 8
const PW_INVIS := 16       # out of sight now (the blink: the server says when)
const PW_INVIS_ON := 32    # has INVISIBLE (its own page draws it faint)
const PW_FROZEN := 64
const PW_SLOW := 128       # slowed by someone's rain
const PW_UMBRELLA := 256
const PW_SPIKES := 512
const PW_SPIKE_UP := 1024  # the spiked shield is up (not waiting to come back)
const PW_SPEED := 2048
const PW_PUMPKIN := 4096   # p4.12 tricks: a hopping pumpkin,
const PW_BACKWARDS := 8192 # left and right swapped,
const PW_TINY := 16384     # tiny (only the look)
const PW_BATS := 32768     # hidden in bats (a swarm sweeping by, or BAT SWARM)

# events: [type, x, y, a, b]
const E_JUMP := 1        # a = fighter
const E_LAND := 2        # a = fighter, b = fall speed
const E_DODGE := 3       # a = fighter, b = direction 0..7 (45 degree steps)
const E_SHOOT := 4       # a = fighter, b = kind
const E_STICK := 5       # a = kind, b = 1 floor / 0 wall
const E_EXPLODE := 6     # a = owner
const E_IGNITE := 7      # a = 1 floor / 0 wall
const E_MIASMA := 8
const E_DEATH := 9       # a = fighter, b = cause (1 arrow, 2 blast, 3 stomp, 4 fire, 5 miasma, 6 the walls, 7 lightning, 8 a ghost cat, 9 spikes)
const E_CATCH := 10      # a = fighter, b = kind
const E_PICKUP := 11     # a = fighter, b = kind
const E_SPAWN := 12      # a = fighter
const E_WALLJUMP := 13   # a = fighter, b = 1 wall on the right
const E_TINK := 14
const E_HURT := 15       # a = fighter
const E_LEDGE := 16      # a = fighter, b = 1 wall on the right
const E_SMOKE := 17
const E_DRYFIRE := 18    # a = fighter: let go of shoot with an empty quiver
const E_KILL := 19       # p4.8 (the deathcam): a = the killer (255: none, the arena), b = the fighter who died
const E_PU_WARN := 20    # p4.9: an orb's lightning starts to build up: x, y its middle; a = kind; b = 1 BIG
const E_STRIKE := 21     # the lightning strikes there (anyone close dies): a = kind; b = 1 BIG
const E_PU_GET := 22     # a = fighter, b = kind: it took the orb
const E_PU_GONE := 23    # an orb nobody took fades: a = kind
const E_SHIELD_POP := 24 # a = fighter: its shield took an arrow; b = the arrow's kind
const E_CAT_POOF := 25   # a ghost cat is gone: a = owner; b = 1 caught by a dodge
const E_FREEZE := 26     # a = the fighter who froze everyone else
const E_PIN := 27        # p4.10: an arrow pins a body to a wall: x, y the arrow in the wall; a = fighter, b = 1 the wall on the right
const E_GHOST := 28      # p4.11: a person's ghost rises from the body: a = fighter
const E_BOO := 29        # a ghost BOOs: a = the ghost, b = the one it shoved (255: the dash starts)
const E_GHOST_POP := 30  # an arrow pops a ghost (gone 3 s): a = the ghost, b = the shooter
const E_PET := 31        # p4.12: someone pets the black cat (a SHIELD): a = fighter; b = 1: it caught the turkey (p4.18: its power-up follows)
const E_CAT_COME := 32   # the black cat shows up: x, y its feet; a = 1: the turkey (p4.18)
const E_TRICK := 33      # TRICK OR TREAT: a = fighter, b = 0 a treat (its power-up follows), 1 pumpkin, 2 backwards, 3 tiny
const E_BATS := 34       # a bat swarm screeches before it sweeps in: x, y where it comes in; a = 1 it flies right, 0 left
# p4.12: two or three words beside the name on your own screen (the user: "graphics or
# small stylized text that disrupts the game as little as possible").
const PU_TIP := {1: "burning arrows", 2: "boom arrows", 3: "poison arrows", 4: "smoke arrows", 5: "blocks one hit",
	6: "endless arrows", 7: "fly with the stick", 8: "huge arrows", 9: "cats hunt them", 10: "they slow down",
	11: "you're hidden", 12: "they freeze", 13: "spikes up", 14: "run fast", 15: "", 16: "seed bombs",
	17: "bats guard you", 18: "knife: let go to swing", 19: "pie in the face"}
const E_KNIFE := 35      # GHOSTFACE swings the knife: a = fighter, b = 1 to the right
const E_MASK_DOWN := 36  # GHOSTFACE is knocked down (2 s): a = fighter
const E_MASK_UP := 37    # and gets back up: a = fighter
const E_CANDY_DROP := 38 # p4.13 a candy appears: x, y; b = 0 out of a body, 1 from the sky
const E_CANDY_GET := 39  # someone opens a candy (TRICK OR TREAT, then its E_TRICK): x, y; a = fighter
const E_FURNACE := 40    # THE BOILER ROOM (sim/boiler.gd): a furnace blasts fire: x, y its mouth; a = which one; b = its direction
const E_STEAM := 41      # a pressure pipe vents steam: x, y its valve; a = which one; b = its direction
const E_PIE := 42        # p4.18 a pie splats: x, y; a = the shooter; b = 1 BIG
const E_PIED := 43       # a fighter is covered in cream (it sees nobody for sim.gd's PIED_TICKS): a = fighter
const E_CATCH_UP := 44   # a person far behind starts the round with a SHIELD (sim.gd catch_up): a = fighter
const E_PHEW := 45       # p4.19 the round's winner would have died after the round was called: x, y where the hit landed; a = the fighter (the winner); b = what hit: 0 an arrow, 1 a blast, 2 anything else
const E_TAUNT := 46      # p4.19 a fighter taunts (the GOBBLE button; a bot after a knockout): x, y its head; a = fighter
# fighter flags: 1 facing right, 2 on the ground, 4 at a wall, 8 burning, 16 poisoned,
# 32 rolling (a dodge on the ground) or pulling up (on a ledge), 64 wall jump just now, 128 in smoke
# fighter flags2: 1 a bot plays this seat, 2 aiming, 4 the person's socket is gone (the seat is held)
const F2_BOT := 1
const F2_AIMING := 2
const F2_AWAY := 4

# the death causes, for the log lines
const CAUSES := {1: "arrow", 2: "blast", 3: "stomp", 4: "fire", 5: "miasma", 6: "the walls", 7: "lightning",
	8: "a ghost cat", 9: "spikes", 10: "a furnace", 11: "a knife"}
const WALLS_DEADLY_BIT := 0x8000

# p4.18 the seasons (docs/reference/game-review-2026-11.md). The server is in one season: by
# its own date (AUTO), or the lobby's SEASON button picks one. It sends it with the seats, so
# every phone matches. A season gives the candies, their tricks, the costume, the pet and
# some power-ups new names and pictures; the rules under them stay the same. "" is no season:
# the lobby wears the castle, and the candies stay Halloween's (as before p4.18).
const SEASON_PICKS := ["auto", "off", "halloween", "harvest"]   # the SEASON button's choices
const SEASON_LABEL := {"": "NONE", "halloween": "HALLOWEEN", "harvest": "HARVEST"}
const HARVEST_NAMES := {15: "WHAT'S FOR DINNER?", 16: "POPCORN ARROWS", 17: "CROWS", 18: "THE BIG TURKEY"}
const HARVEST_SHORT := {15: "DISH?", 16: "POPCORN", 17: "CROWS", 18: "BIG TURKEY"}
const HARVEST_HELP := {16: "every arrow is a corn cob: it bursts into popcorn that pops, all match",
	17: "crows circle you: they knock arrows away and hide you",
	18: "no bow this round: let go of shoot to peck; a hit knocks you down 2 seconds, a hit while you're down ends you"}
const HARVEST_TIP := {16: "popcorn bombs", 17: "crows guard you", 18: "peck: let go to lunge"}
# a candy's tricks (sim.gd's trick numbers 1..3), then the costume (4)
const TRICK_NAMES := ["TREAT", "PUMPKIN HEAD", "BACKWARDS", "TINY", "GHOSTFACE"]
const HARVEST_TRICKS := ["TREAT", "TURKEY TIME", "TOO MUCH PIE", "PEA-SIZED", "THE BIG TURKEY"]
const TRICK_TIPS := ["", "no shooting", "left is right!", "so small", ""]

# p4.19 the bots' names, by the season (the user: "a fun, balanced, silly game"): seat i's
# bot is BOT_NAMES[season][i], so a banner says GRAVY WINS THE ROUND, not BOT 3. The lobby's
# cards and the HUD still mark them as bots.
const BOT_NAMES := {
	"harvest": ["GRAVY", "STUFFING", "YAMS", "BISCUIT", "DRUMSTICK", "CRANBERRY", "CORNBREAD", "WISHBONE"],
	"halloween": ["BOO", "FANG", "CREEPY", "GOOP", "BONES", "SPOOKS", "WEBBY", "CACKLE"],
	"": ["BOLT", "RUSTY", "CLANK", "BEEP", "GIZMO", "SPROCKET", "WIDGET", "ZAP"],
}

static func bot_name(seat: int, season: String) -> String:
	var list: Array = BOT_NAMES.get(season, BOT_NAMES[""])
	return str(list[posmod(seat, list.size())])

# Is this one of the bots' names, in any season? (A person may not take one: the logs and
# the night's numbers tell people from bots by the seat's kind, and a name must not blur it.)
static func is_bot_name(name: String) -> bool:
	var n := name.strip_edges().to_upper()
	if n.begins_with("BOT "):
		return true
	for k in BOT_NAMES:
		if n in BOT_NAMES[k]:
			return true
	return false

# The season on a day: Halloween 1 October to 2 November, the Harvest 3 to 30 November.
static func season_for(month: int, day: int) -> String:
	if month == 10 or (month == 11 and day <= 2):
		return "halloween"
	if month == 11:
		return "harvest"
	return ""

# A power-up's name, short name, help line and tip in a season.
static func pu_name(kind: int, season: String) -> String:
	return str(HARVEST_NAMES[kind]) if season == "harvest" and HARVEST_NAMES.has(kind) else str(PU_NAMES.get(kind, str(kind)))

static func pu_short(kind: int, season: String) -> String:
	return str(HARVEST_SHORT[kind]) if season == "harvest" and HARVEST_SHORT.has(kind) else str(PU_SHORT.get(kind, ""))

static func pu_help(kind: int, season: String) -> String:
	return str(HARVEST_HELP[kind]) if season == "harvest" and HARVEST_HELP.has(kind) else str(PU_HELP.get(kind, ""))

static func pu_tip(kind: int, season: String) -> String:
	return str(HARVEST_TIP[kind]) if season == "harvest" and HARVEST_TIP.has(kind) else str(PU_TIP.get(kind, ""))

# A candy's result by name: 0 a treat, 1..3 the tricks, 4 the costume.
static func trick_name(n: int, season: String) -> String:
	var list: Array = HARVEST_TRICKS if season == "harvest" else TRICK_NAMES
	return str(list[clampi(n, 0, list.size() - 1)])

# p4.12: a BIG power-up (the numbers after SUPER SPEED are regular ones again, but BAT SWARM).
static func is_big(k: int) -> bool:
	return (k >= PU_CATS and k <= PU_SPEED) or k == PU_BATS

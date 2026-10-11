# The game's packet and entity codes, shared by the server (server/game_server.gd),
# the clients (client/net.gd), the benchmark (server/bench_server.gd) and the Python
# fake players (tools/v2_synth.py, tools/bench_synth.py copy the numbers).
# All binary, little endian.
#   snapshot  u8 T_SNAP, u32 tick, u8 phase, u8 round, u16 phase ticks left, u8 goal,
#             u8 winner (NO_ONE = none), u16 walls (each purple wall's width in px,
#             + 0x8000 when they kill), u8 fighters, u16 arrows, u8 zones, u16 events,
#             fighter x14 B, arrow x8 B, zone x9 B, event x7 B
#   fighter   u8 seat, u8 state, s16 x, s16 y, s8 vx, s8 vy, u8 flags, u8 aim (256 steps),
#             u8 arrows, u8 state ticks, u8 points, u8 flags2
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
# Text frames are JSON, {"kind": ...}: hello, join, leave, start, bots, name from a
# client; welcome, version_error, full, seats, round_end, match_end from the server
# (the fields are listed in server/game_server.gd). The benchmark adds bench_card.
extends RefCounted

# The game's version. tools/v2_build.sh bumps the last number on every build and
# names the pck after it; the server turns away a client with another version.
const VERSION := "v0.2.0-p1.3"

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

# the match, in the snapshot header
const PH_LOBBY := 0
const PH_COUNTDOWN := 1   # START was pressed: 3 s
const PH_ROUND_START := 2 # the fighters stand on their spots, nobody moves: 1.5 s
const PH_PLAY := 3
const PH_ROUND_END := 4   # one fighter left (1.5 s), or none (a draw)
const PH_MATCH_END := 5   # the winner, 7 s, then the lobby
const NO_ONE := 255

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
const S_FLY := 0
const S_FALL := 1
const S_STUCK := 2

# zones left on the ground
const Z_FIRE := 1
const Z_MIASMA := 2
const Z_SMOKE := 3

# events: [type, x, y, a, b]
const E_JUMP := 1        # a = fighter
const E_LAND := 2        # a = fighter, b = fall speed
const E_DODGE := 3       # a = fighter, b = direction 0..7 (45 degree steps)
const E_SHOOT := 4       # a = fighter, b = kind
const E_STICK := 5       # a = kind, b = 1 floor / 0 wall
const E_EXPLODE := 6     # a = owner
const E_IGNITE := 7      # a = 1 floor / 0 wall
const E_MIASMA := 8
const E_DEATH := 9       # a = fighter, b = cause (1 arrow, 2 blast, 3 stomp, 4 fire, 5 miasma, 6 the walls)
const E_CATCH := 10      # a = fighter, b = kind
const E_PICKUP := 11     # a = fighter, b = kind
const E_SPAWN := 12      # a = fighter
const E_WALLJUMP := 13   # a = fighter, b = 1 wall on the right
const E_TINK := 14
const E_HURT := 15       # a = fighter
const E_LEDGE := 16      # a = fighter, b = 1 wall on the right
const E_SMOKE := 17
const E_DRYFIRE := 18    # a = fighter: let go of shoot with an empty quiver
# fighter flags: 1 facing right, 2 on the ground, 4 at a wall, 8 burning, 16 poisoned,
# 32 rolling (a dodge on the ground) or pulling up (on a ledge), 64 wall jump just now, 128 in smoke
# fighter flags2: 1 a bot plays this seat, 2 aiming, 4 the person's socket is gone (the seat is held)
const F2_BOT := 1
const F2_AIMING := 2
const F2_AWAY := 4

# the death causes, for the log lines
const CAUSES := {1: "arrow", 2: "blast", 3: "stomp", 4: "fire", 5: "miasma", 6: "the walls"}
const WALLS_DEADLY_BIT := 0x8000

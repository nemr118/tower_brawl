# The benchmark's packet and entity codes, shared by the server, the clients and
# tools/bench_synth.py (which copies the numbers). All binary, little endian.
#   snapshot  u8 T_SNAP, u32 tick, u8 fighters, u16 arrows, u8 zones, u16 events,
#             fighter x12 B, arrow x8 B, zone x9 B, event x7 B
#   input     (u8 T_INPUT, u32 client tick, u8 buttons, u16 aim) x4 (the last 4 ticks)
#   ping      u8 T_PING, u32 client ms, u16 last rtt ms, u16 worst snapshot gap ms
#   pong      u8 T_PONG, u32 client ms (echoed), u32 server tick
# Text frames are JSON: {"kind": "bench_card", ...} and {"kind": "hello", ...}.
extends RefCounted

const PORT := 8091
const T_SNAP := 1
const T_INPUT := 2
const T_PING := 3
const T_PONG := 4

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
const E_DEATH := 9       # a = fighter, b = cause (1 arrow, 2 blast, 3 stomp, 4 fire, 5 miasma)
const E_CATCH := 10      # a = fighter, b = kind
const E_PICKUP := 11     # a = fighter, b = kind
const E_SPAWN := 12      # a = fighter
const E_WALLJUMP := 13   # a = fighter, b = 1 wall on the right
const E_TINK := 14
const E_HURT := 15       # a = fighter
const E_LEDGE := 16      # a = fighter, b = 1 wall on the right
const E_SMOKE := 17
# fighter flags: 1 facing right, 2 on the ground, 4 at a wall, 8 burning, 16 poisoned,
# 32 rolling (a dodge on the ground) or pulling up (on a ledge), 64 wall jump just now, 128 in smoke

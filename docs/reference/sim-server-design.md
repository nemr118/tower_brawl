---
tags: [reference, design, network]
status: design draft 2026-09-10 (the user chose a simulation server)
---
# The simulation server (design draft)

On 2026-09-10 the user chose to replace the Python relay with a simulation server. This page compares the ways to build one and recommends one. Gameplay numbers: [[towerfall-research]]. The phases: [[v0.2-transformation-plan]].

## 1. What changes
| | Today: the relay | Tomorrow: the simulation server |
|---|---|---|
| Who moves a fighter | its own client; the server passes the position on (`sync_pos`) | the server, from the player's buttons |
| Who decides a hit | whoever saw it (`player_died`) | the server |
| Arrows | each screen flies its own copy | the server owns them; screens show them |
| A client sends | its position, 20 times a second | its buttons and aim, 60 times a second |
| A client gets | other players' positions, bundled every 50 ms | the game state (a "snapshot"), 30 times a second |
| Screens that disagree | possible | one truth |
| Bots | separate headless Godot clients | brains inside the server that press buttons |

## 2. Four ways, compared
**A. The server simulates, clients predict their own fighter** (recommended). The server runs the game. Your client also moves your own fighter at once from your buttons ("prediction"), so there is no input lag. When the server's answer comes back, the client checks it: if they disagree, it takes the server's position and replays your last few inputs ("reconciliation"). Other fighters are drawn a little in the past, smoothly between snapshots ("interpolation"). This is the standard model in Gabriel Gambetta's series. Only your own fighter is replayed, so a phone does little extra work.

**B. Rollback (GGPO style).** Every client runs the whole game for everyone. A late input rewinds and re-runs the last frames. Great for 2-player fighting games. With 8 players each rewind re-runs 8 fighters and every arrow for several frames, on a phone, in a single-threaded web build, and every device must get bit-identical numbers. Too heavy and too fragile for 8 on phones.

**C. Lockstep.** Everyone waits for everyone's input before each frame. The slowest phone slows everybody. No.

**D. netfox** (a Godot 4 add-on with prediction and rollback). It would save writing A. But it is built on Godot's high-level multiplayer API: its `network-time.gd` uses `@rpc`, `multiplayer.is_server()` and `MultiplayerPeer`. `CLAUDE.md` rules that API out, because the Python harness bots, the deck and the stats cards all speak our own packets. Borrow its ideas (a 30-tick default, a client clock that runs 0.8x to 1.25x speed to stay in step), not the add-on.

## 3. The recommended shape
**One Godot project, two roles.** `godot --headless --path . -- --server` runs the server; the web export is the client. The same GDScript runs the game on both. `GAME_VERSION` lives in one place; the Python mirror goes away.

**The game logic is separate from the drawing.** The simulation is plain GDScript objects (fighters, arrows, chests, the round), not scene nodes. It steps one tick at a time from inputs. Scenes only read it and draw. So the server needs no scene, a client can replay 5 ticks in a blink, and a probe can run 10 000 ticks headless.

**Ticks:** the simulation runs at **60 ticks a second** on both sides (TowerFall's numbers are per 60 Hz frame).
- **Client → server, every tick:** the tick number, the buttons (left, right, up, down, jump, shoot, dodge, a spare), the aim in 0.1° steps (like `sync_pos`), and the same for the three ticks before, so a late packet loses nothing. About 32 bytes.
- **Server → client, every second tick:** the server tick; the last input tick it used from you (for reconciliation); every fighter (seat, position, speed, state, flags, aim, arrow count: about 16 bytes) and every arrow (id, position, speed, state: about 11 bytes). With 8 fighters and 24 arrows, about 400 bytes: 12 KB/s per client, 96 KB/s for all 8. Nothing for Wi-Fi.
- **Rare events stay JSON:** joins, the lobby, deaths, pickups, round start and end.

**Your input lands on the tick you pressed it.** The client runs a little ahead of the server (about half the round trip plus one tick), so each input reaches the server just before the server gets to that tick. The server keeps a small queue per player and runs input N on tick N. So a dodge on tick N on your screen is a dodge on tick N on the server. This matters most for the catch: an arrow's flight has no randomness, so your screen and the server agree where it is on tick N. A catch you saw, is a catch. The client nudges its clock a few percent faster or slower to stay ahead by the right amount.

**Arrows are drawn in the present.** A plain arrow's path depends only on where and when it was fired, so a client draws it where it is *now*, not in the past like the other fighters. The arrow you have to dodge is where the server has it. Arrows that steer (the guided arrow, a bolt) come from the snapshots.

**The same numbers everywhere.** Positions are whole pixels plus a remainder, like TowerFall's mover. An arrow's speed comes from its aim in 0.1° steps through a lookup table, not a fresh `sin` / `cos` on each machine (the web build and the Linux server might round the last bit differently). Anything that still drifts is fixed by the next snapshot.

**The server settles:** every hit, catch, stomp and death; arrow pickups, chests and steals (first come); the round clock and the miasma; the score.

**A client shows before the server agrees:** its own movement, dodge and shot (a fired arrow appears at once). Not pickups or deaths: those wait for the server, one or two ticks on a LAN.

**Lag compensation** (rewinding other fighters to where the shooter saw them) is left out at first: the server flies arrows itself, and a LAN round trip is 5 to 40 ms. Stomps are the one to watch, because the stomper sees the other fighter slightly in the past. Measure, then decide.

## 4. The transport
- **WebSocket over TLS (wss)**, as today. A Godot server can accept wss itself: `WebSocketMultiplayerPeer.create_server()` takes `TLSOptions.server(key, cert)`, and the lower-level `WebSocketPeer` can sit on the same TLS stream, which keeps our own packet framing. The existing cert pair works.
- TCP's weak spot: one lost packet holds up everything behind it. Snapshots are whole states (no deltas), so a late one is simply replaced by the next, and each input packet carries the three before. If family-night logs still show stalls, **WebRTC data channels** (unreliable, like UDP) are the upgrade: Godot web builds have them, the server needs the webrtc-native extension. Not in the first build.

## 5. The Python server
- **Recommended:** the Godot server owns the game socket completely: lobby, seats, tokens, the rejoin grace, the version check, rounds, the harness gate, `status.json`, the tagged log lines (`server.log`, `debug.log`, one `.1` each), `client_stats.jsonl`. Python only serves the web files over HTTPS (and `/play`). `tbdash`, `stats_table.py` and `soak_report.py` read the same files as today.
- **Not recommended:** Python keeps the lobby and starts a Godot process per match. Two sockets or a proxy, and the rules split over two languages.
- The laptop runs both as systemd services; `deploy_laptop.sh` also copies the server pck and a Godot binary.

## 6. Bots
- **Bots live inside the server.** A bot is a brain that fills in the input for its seat each tick. No extra processes, no network in the way; 8 bots cost the laptop almost nothing. `tbbot add chaser` becomes a command to the server.
- **The harness still uses real clients** for network tests: headless Godot clients, and small Python clients that send inputs and read snapshots (simpler than today's protocol bots). `--latency-ms` stays.

## 7. The replay
Every client already gets the snapshots. It keeps the last few seconds in a ring, like `history_ring.gd` today. At a round end the server names the ticks to replay, and every screen plays the same thing from its own ring. No new packets.

## 8. Proofs to build along the way
| Proof | What it shows |
|---|---|
| `prediction_error` scenario, `--latency-ms 60` | your own fighter is corrected by 2 px or less on 95% of ticks |
| `catch_on_tick` scenario | a dodge on the tick the arrow reaches you always catches, at 0, 60 and 120 ms |
| `sim_join_8`, `sim_rejoin`, `sim_version_mismatch` | the lobby rules survived the move out of Python |
| `tick_budget` probe on the laptop | one server tick with 8 fighters, 24 arrows and 8 bots takes under 4 ms |
| the net spike (plan G0a) | the phones' round trip and the longest stall on the family Wi-Fi |

## Sources
- Gabriel Gambetta, [Fast-Paced Multiplayer](https://www.gabrielgambetta.com/client-server-game-architecture.html)
- [netfox](https://github.com/foxssake/netfox), its [docs](https://foxssake.github.io/netfox/latest/) and [`network-time.gd`](https://raw.githubusercontent.com/foxssake/netfox/main/addons/netfox/network-time.gd)
- Godot: [WebSocketMultiplayerPeer](https://docs.godotengine.org/en/stable/classes/class_websocketmultiplayerpeer.html)

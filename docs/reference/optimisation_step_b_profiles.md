---
tags: [reference, optimisation]
---
# Optimisation Step B — the three profiles (measured on v0.0.33, 2026-09-05)

Step B of the optimisation plan: measure first, change nothing. Three profiles on one PC: the Godot client under a 4-brain fleet, the server and its `status_loop`, and the network bytes per client. Step C ranks the cut list from these numbers. Nothing in the game changed for this page.

## How the numbers were taken
- **Machine:** the dev PC (Arch Linux, kernel 7.1.9, Wayland). Godot 4.7.2, Python 3.14.7. Everything on one box over `127.0.0.1`, so the round trip is 4 to 7 ms and there is no packet loss.
- **The fleet:** the service was stopped and `./venv/bin/python serve_game.py` started by hand. Three headless brains (`godot --headless --path . -- --autojoin --ai=chaser|sniper|turtle --ai-seed=1|2|3`) and one **windowed** brain (`godot --max-fps 60 --print-fps --gpu-profile --path . -- --autojoin --ai=rusher --ai-seed=4`), so the fourth client really draws. A fifth socket, a spectator (a browser tab on the play page), was attached during every run; the server counts show `players=4 spectators=1 sockets=5`.
- **CPU:** `/proc/<pid>/task/*/stat` sampled over 100 s of play, summed per thread (Python 3.14 names its threads, so the server's `writer` and `status` threads show by name). Percent = share of one core.
- **Server call shape:** `py-spy record --format raw --threads --rate 250` around the server for 150 s. py-spy counts a sleeping thread at every wake-up, so its totals are not CPU time; only the split inside `status_loop` is used, turned into milliseconds at 4 ms per sample.
- **Bandwidth:** the `📈 [NetStats]` lines of the four client logs (payload bytes per packet type, 5 s buckets, arena scene only), summed over 120 s; the server's `[STATS 10s]` lines for the other side.
- **Draw:** Godot's own `--gpu-profile` and `--print-fps` lines from the windowed client, plus the `fps draw= phys= worst= hitches=` field of NetStats.
- Three runs: run 1 (py-spy on, window at vsync 60), run 2 (per-thread CPU, the window lost vsync and drew at 239 fps), run 3 (per-thread CPU with `--max-fps 60`). Runs 2 and 3 give the CPU tables; run 1 gives the py-spy shape and the GPU profile; the bandwidth is the same in all three.

## Profile 1 — the Godot client
### Whole process
| Client | CPU (share of one core) | Main thread | Render threads (`gl0`, `cs0`, `gdrv0`) | 24 `WorkerThread`s together | RSS |
|---|---|---|---|---|---|
| Headless brain (chaser, sniper, turtle; run 2) | 6.6 to 6.8 % | 2.5 % | none | 4.2 % (0.17 % each, idle spinning) | 172 MB |
| Windowed brain, vsync lost, 239 fps (run 2) | 18.0 % | 11.4 % | 2.8 % | 3.8 % | 320 MB |
| **Windowed brain, `--max-fps 60`, vsync 60 fps (run 3)** | **11.2 %** | **6.2 %** | 0.8 % | 4.2 % | 320 MB |

- **The main thread is the whole cost.** Godot draws 2D from the main thread (the compatibility renderer, single-threaded, the same mode the web export uses). The GPU threads together stay under 3 %.
- **The GPU does almost nothing.** `--gpu-profile` over 131 frames: `Render CanvasItems` mean **55 to 82 µs** (runs 3 and 1), max 157 µs, in a 16.67 ms frame. The draw list is not the problem; building it on the CPU might be.
- **Sim versus render, from the two window speeds.** The main thread costs 62 ms a second at 60 fps (run 3) and 114 ms a second at 239 fps (run 2). That splits into about **0.29 ms per drawn frame** of render-side CPU and about **0.74 ms per physics tick** for everything else (the fighter, the puppets, the brain, the tape frame, the packets). At 60 fps that is roughly 17 ms of render CPU and 45 ms of sim per second: **about 1 ms per frame in all, of a 16.7 ms budget**, on this PC. A headless brain's main thread (no renderer at all) is 23 ms a second, so about half of the per-tick work only exists when there is a screen to draw for.
- **The 24 worker threads** burn 4 % of a core doing nothing (Godot's thread pool waking up). The web export runs single-threaded, so this does not exist in a browser. Not ours.
- **Hitches:** every client logged exactly 2 frames over 50 ms (worst 97 to 141 ms) and both sit at the first arena load (`🧭 [Spawn] round 1`). **No hitch during play** in 130 s on any client, in any run. `phys=60.0` on every line.
- **The brain adds to the main thread.** A human client has no `bot_brain.gd` (751 to 901 decisions per 2 min, an aim self-check every frame); the sim figure above is an upper bound for a real player.
- **Limit of this profile.** Without the editor profiler the main thread cannot be split into `_record_tape_frame`, `_render_snapshots`, the `VhsOverlay` redraw and so on. The cheapest next measurement (Step C, one line of code) is two `Performance` monitors, `TIME_PROCESS` and `TIME_PHYSICS_PROCESS`, on the NetStats `fps` field, so a phone reports its own milliseconds.

## Profile 2 — the server and `status_loop`
### Per thread, 100 s of play, 4 brains + 1 spectator (run 2)
| Thread | CPU (share of one core) | What it is |
|---|---|---|
| `writer` (all `ClientConn` writer threads together) | 1.11 % | every broadcast: one `ws_send` per socket per packet, about 215 packets a second out |
| reader threads (`Thread-4` to `Thread-8`) | 0.53 % | one `ws_read` loop per socket, about 60 packets a second in |
| `status` (`status_loop`) | **0.07 %** | `_harness_tick`, `_build_status`, `json.dump`, `os.replace`, once a second |
| everything else (`stats_loop`, grace timers, listeners) | 0.01 % | |
| **whole process** | **1.7 %** | 16 threads, 7 MB RSS |

### Inside `status_loop` (py-spy, run 1, 150 writes)
| Piece | Time per write |
|---|---|
| `_harness_tick` → `_read_harness_state` (opens and parses `harness_state.json`) | 1.1 ms (of which the file read 0.9 ms) |
| `json.dump` of the status | 0.5 ms |
| `_build_status` (locks, seats, timeline, `ring.snapshot`) | 0.24 ms |
| `os.replace` and the rest | under 0.8 ms |
| **one write, in all** | **about 2.6 ms**, once a second = 0.26 % of a core at most; the `/proc` count says 0.07 % |

### `status.json` by size (mid-match copy, 4 seats, 22 kills on the timeline)
| Part | Bytes | Share |
|---|---|---|
| `seats` (4 × 1 304 B; a seat carries a 599 B `bot` card and a 369 B `tape` card) | 5 234 | 44 % |
| `events` (the 40 log lines) | 4 965 | 42 % |
| `match` (state, timeline of kills and rounds) | 804 | 7 % |
| `traffic` | 492 | 4 % |
| the rest (`harness`, version, pid, counts) | 313 | 3 % |
| **whole file** | **11 808** | written once a second, 12 KB/s to disk |

- **`status_loop` is not a cost.** 0.07 % of a core and 12 KB/s of disk. The 40 log lines are 42 % of the file but the file is small. Cutting them saves nothing a player can feel; keep them for the deck.
- **The writer threads are the server's cost, and it is still tiny:** 1.1 % of a core for 215 packets a second. `fail=0 drop=0` on every `[STATS]` line; no queue ever filled.
- The largest single item in the status thread is reading `harness_state.json` every second, not building or writing the status. Harmless.

## Profile 3 — bytes per client (payload only, 120 s of play, run 2)
### In to a client (what the server relays to it)
| Packet | pkt/s | B/s | Share of inbound bytes |
|---|---|---|---|
| `sync_pos` (11 B binary, 3 puppets × 12 to 13 pkt/s) | 37 to 39 | 405 to 430 | **84 %** |
| `pong` | 0.9 | 24 | 5 % |
| `player_died` | 0.3 | 22 | 4 % |
| `spawn_projectile` (9 B binary) | 0.4 to 0.8 | 3 to 7 | 1 % |
| everything else (`round_end`, `new_round`, `spawn_powerup`, `activate_powerup`, `player_joined`, names, `lock_in`) | 0.2 | 15 | 3 % |
| **in, per client** | **39 to 42** | **477 to 511** | |

### Out of a client (what it sends)
| Packet | pkt/s | B/s | Share of outbound bytes |
|---|---|---|---|
| `sync_pos` (20 Hz with idle suppression) | 12 to 15 | 128 to 163 | 33 to 36 % |
| `history_status` (the tape card, about 380 B every 2.6 s) | 0.38 | 143 | **31 to 36 %** |
| `bot_status` (the brain card, about 600 B every 8 s; brains only) | 0.12 | 68 to 88 | 17 to 19 % |
| `ping` (44 B once a second) | 1.0 | 44 | 10 to 11 % |
| `player_died` and the rest | 0.2 | 12 | 3 % |
| **out, per client** | **13 to 17** | **395 to 456** | |

### The server side (the same 120 s, run 2)
| | pkt/s | B/s |
|---|---|---|
| in to the server, 4 clients | 60 | 1 850 |
| out of the server, 5 sockets | 215 | 3 040 |

- **A client moves about half a kilobyte each way.** Payload only. On the wire every packet also carries a WebSocket header (2 B down, 6 B up) and TCP/IP headers (40 to 52 B): if every packet rides its own TCP segment, 41 packets a second in cost about **2.5 KB/s** on the wire, five times the payload. The packet count matters more than the byte count.
- **`sync_pos` is already tight** at 11 B. Its cost is its rate: 3 puppets × 13 pkt/s. The only lever there is the send rate (20 Hz) or coalescing.
- **The tape card is the biggest thing a player sends,** bigger than its own movement. `history_status` is 380 B every 2.6 s from every screen, all match long, whether or not the tape changed. That is the one outbound cut that shows in the numbers. `bot_status` only exists on brains.
- **JSON events are 3 to 4 % of the bytes.** Turning them into binary would not show.
- **The spectator socket** doubles nothing on the clients but adds a fifth copy of every broadcast on the server (the 215 pkt/s out is 5 sockets' worth).

## What looks biggest (for Step C to rank)
1. **The client main thread on a phone.** Everything a player feels lives there: about 1 ms per frame on this PC, with the render-side CPU (building the draw list: `VhsOverlay`, puppets, HUD) about a third of it and the 60 Hz sim two thirds, and half of that sim only present when there is a renderer. A phone browser is several times slower per frame, and the playtest sheets already ask for the `fps` field there. First cut: add `TIME_PROCESS` / `TIME_PHYSICS_PROCESS` to the NetStats line and read a phone before cutting anything.
2. **`history_status` every 2.6 s from every screen.** A third of a player's outbound bytes for a deck column. Send it on change or every 10 s.
3. **Packet count, not size.** 41 packets a second into each client; header cost is five times the payload. Coalescing two puppets' `sync_pos` into one frame would halve the count. A bigger change than it looks (the relay sends per sender).
4. **Not worth a build:** `status_loop` (0.07 % of a core), the 40 log lines in `status.json` (5 KB once a second), JSON events to binary (3 % of bytes), the server writer threads (1.1 %). Backlog 4 (log rotation) stays a housekeeping item, not a performance one.
5. **No hitches in play** on the PC. The two per client at the arena load are the scene change, not the game loop.

## Caveats
- The windowed brain's synthetic mouse does not reach `player.gd` on a real display (`WARNING: [BotBrain] synthetic mouse aim is not reaching player.gd`, mean error 110 to 121°). It still moved, jumped and attacked (193 to 231 moves, 132 to 181 attacks in 2 min); its aim was wrong. The CPU figures stand; its kills do not.
- Everything ran on one PC over loopback. The phone is the platform that matters and was not measured here; that is what the `fps` field and the sheets are for.
- py-spy's raw counts include sleeping threads at wake-up (`time.sleep`, `accept`, `recv` show as leaves). Only the split inside the `status` thread is quoted from it; the CPU totals come from `/proc`.

## To repeat it
```bash
systemctl --user stop towerbrawl
./venv/bin/py-spy record --format raw --threads --rate 250 --duration 150 -o server.raw -- ./venv/bin/python serve_game.py &   # or plain serve_game.py for /proc sampling
godot --headless --path . -- --autojoin --name=BotA --ai=chaser --ai-seed=1 > chaser.log 2>&1 &   # ×3 personas
godot --max-fps 60 --print-fps --gpu-profile --path . -- --autojoin --name=Screen --ai=rusher --ai-seed=4 > screen.log 2>&1 &
# per-thread CPU: sum utime+stime from /proc/<pid>/task/*/stat over 100 s; bandwidth: sum the NetStats "in:"/"out:" type lists
systemctl --user restart towerbrawl
```
`py-spy` is in `./venv` only (`./venv/bin/py-spy`, 0.4.2). Client logs of the runs are not kept; the numbers above are the record.

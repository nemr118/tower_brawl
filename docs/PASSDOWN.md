---
tags: [handoff]
---
# PASSDOWN — Tower Brawl (read this first in a new session)

Godot 4.7 web game (4-player LAN brawler), custom WebSocket relay in Python. `docs/` is the Obsidian vault. Kickoff reads: `CLAUDE.md`, this file, the newest page in `Patch Notes/`, [[Commands]]. History: [[Changelog]]. Deep dives: `docs/reference/`. Closed: [[closed]].

## Now (2026-09-05)
- **Tagged `v0.0.33`** on `master`, working tree clean at handoff. **Harness 23/23 with `--restart-each`, no Minor**, report `harness_report_v0.0.33.json`. Heavy fleet seed 13: **PASS**, 0 `🧗 [TopEdge]` lines, longest loop 2 (backlog 23 closed, the tumble stays).
- **Next: optimisation Step C, rank the cut list from the Step B numbers** in [[optimisation_step_b_profiles]] (PC, 4 brains): a windowed client's main thread is about 1 ms per 60 Hz frame (a third render-side CPU, two thirds sim), the GPU draw 55 to 82 µs, no hitch in play; the server 1.7 % of a core, `status_loop` 0.07 %; per client about 0.5 KB/s each way, `sync_pos` 84 % of inbound bytes at 41 pkt/s, `history_status` a third of a player's outbound bytes. Biggest first: (1) a phone's main thread, first add `TIME_PROCESS` / `TIME_PHYSICS_PROCESS` to the NetStats `fps` field and read a phone; (2) `history_status` every 2.6 s, send on change; (3) packet count over packet size. Not worth a build: `status_loop`, the 40 log lines, JSON events to binary. D. one build per cut, gated by the harness. Then `v0.1.0`. Backlog 20 moves up if a playtest gives a `🪤 [JumpTrap]` line.
- **Waiting on a human:** [[Playtest Backlog 1 — Ranger Reload Quiver]], [[Playtest Backlog 13 — PC Reload Input Probe]] and [[Playtest v0.0.32 — Free-Fall Arena Shift]] (the feel of the free fall). All stay in `docs/` until their verdicts are ticked.
- **v0.1.0 ideas, not scheduled:** replay skip key, virtual stick, touch buttons, spread air spawns, spawn shield, death animations, zoomed replay, montage, sound on the flash, replay on demand. Detail: [[PASSDOWN-2026-09-05]].
- **v0.0.33 "Shift Tumble Kept" (bug build 6, backlog 23 closed):** `bot_brain.gd` `_track_wraps` counts a bottom wrap while `arena.is_arena_rotating` as `shift_wraps` (`shift=` on the `🧠 [Bot]` line, read by `chaos_bots.py`), never as a fall loop; the gate stays at 4. The game is unchanged. See [[v0.0.33 - Shift Tumble Kept]].
- **v0.0.32 "Free-Fall Arena Shift" (bug build 5, backlog 9 closed, option A):** `arena.gd` `_set_platforms_solid` zeroes `collision_layer` on the eight `StaticBody2D` under `Platforms` while the stage turns, restores it at the timer end and in `_finish_spin_now`. Fighters drop through the turning stage. See [[v0.0.32 - Free-Fall Arena Shift]].

## Open backlog
`N. **Title** — state — next action — where the detail lives`. Numbers are never reused; closed items are in [[closed]].
3. **Second tab spectating stalls the game tab** — open, mitigated — spectate from a second device or profile — [[PASSDOWN-2026-09-05]].
4. **`server.log` / `debug.log` never rotate** — open — add rotation inside the optimisation plan — [[PASSDOWN-2026-09-05]].
5. **`player_configs` still carries a default class per slot** — open, harmless — clean up when `global.gd` is next touched.
11. **Arena voids are a mechanic, not a bug** — user decision (v0.0.11) — nothing to do (`bot_brain.gd` routes through the seams).
12. **One-off `fleet.client-silent`** — seen once (v0.0.27 run 1) — if it shows again keep `.harness_logs/godot2.log` — `harness_report_v0.0.27_run1.json`.
13. **PC keyboard dead after a reload in the replay gap** — waiting on a human — run the sheet and read `keys= focus=` (the sheet says what each answer means) — [[Playtest Backlog 13 — PC Reload Input Probe]], [[v0.0.28 - Rejoin in the Replay Gap]].
14. **Stall report from the playtest** — open, vague — ask for exact steps at the next playtest, do not guess a fix — [[Playtest v0.0.26]].
16. **The stomp-egg has no author over the network** — design call — a `player_hit` event from the observer, relayed like `player_died`; the victim's client runs `take_hit` on itself — [[v0.0.29 - Egg-Form Puppet]].
17. **Seam hiding** — design call — a fighter is drawn on one side of the seam only; draw a second copy near the edge — [[Playtest v0.0.17]].
18. **Archer kit revisit (the proper fix behind backlog 1, 6, 15)** — design call — slow regen, steal enemy arrows, arrows in the join snapshot, ammo count on other screens, the two-arrow frame — [[v0.0.30 - Ranger Rejoin Quiver]].
19. **Fill-with-bots button** — design call — the server would have to start headless bot processes.
20. **The W jump lock** — waiting on a `🪤 [JumpTrap]` line from a real game — then fix — [[v0.0.18 - Playtest Fixes: Bubble Spawn, Arrows, Bots, HUD]].
21. **Slope traction and air shield feel** — design call — fighters slide off tilted platforms; an air shield kills sideways speed — [[Playtest v0.0.17]].
22. **Hiding on top of the flipped ground** — design call — upside down, the old floor sits at the top edge — [[Playtest v0.0.17]].

## How to work here
- **Rules:** `CLAUDE.md` (plain words, rule 7; wrap up with the trim step, rule 8; no `.tscn` edits; GDScript ships via `./bump_build.sh --title "..."`). One approved phase at a time; report bugs found outside it, don't fix them unasked. Every human-validation ask gets a `Playtest ....md` sheet in `docs/`.
- **Verify:** `godot --headless --path . --script tools/check_scripts.gd -- --no-net`, then `./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json` (bump first; run detached, wait for `23/23 scenarios passed`).
- **Serve:** `systemctl --user restart towerbrawl` after any `serve_game.py` change. Play at `https://192.168.4.21:8443/play`. Live view: `tbdash`. The rest: [[Commands]].

## Architecture now
- `serve_game.py`: authoritative lobby/match state (slots, alive, stocks, scores, rounds, 5-crown match end), relay for the rest. One reader thread per socket, one `ClientConn` writer thread with a bounded queue (movement dropped first, stalled peers dropped after ~5 s). Client token gates slot reclaim; 8 s rejoin grace mid-match, a held seat counts as present at `new_round`; observer-authoritative deaths deduped per 1.5 s. Round gaps `NEXT_ROUND_DELAY = 2.6`, `REPLAY_ROUND_DELAY = 6.5`, `MATCH_END_DELAY = 7.0`. Harness gate (`_harness_tick`). Tagged log lines; `status.json` once a second (`status_loop`).
- `scripts/global.gd`: the only network code on the client. JSON for events, binary for movement: `sync_pos` 11 B `[type, sender, tick u16, x*10 s16, y*10 s16, aim 0.1° u16, flags]` (bits: facing, dash, shield, bear, egg, feet-on-the-ground), `spawn_projectile` 9 B; mirrored in `serve_game.py BIN_TYPES` and `tools/chaos_bots.py`. Signals out to `arena.gd` / `character_select.gd`. Auto-rejoin, scene correction, combat state persisted for reloads.
- `scripts/player.gd`: local sim + 20 Hz send with idle suppression; puppets render from a 16-sample ring 100 ms behind the sender (`_render_snapshots`). `_physics_process` order: shared timers, puppet branch (early return), local egg branch, local controls. `restore_combat_state` on a rejoin. Deaths reported by whoever saw the hit.
- `scripts/history_ring.gd` the tape (360 frames) and `scripts/replay_player.gd` the VHS replay (211 frames around the closing kill), both driven by `arena.gd`. `scripts/harness_ticker.gd` the join-locked panel. `scripts/bot_brain.gd` the personas (`wanderer chaser sniper turtle rusher griefer`). `web/shell.html` the page with the phone helpers and the canvas focus self-heal.
- `tools/watch_server.py` + `tools/deck_input.py`: the deck (`tbdash`), reads `status.json` and `harness_state.json` only. `tools/chaos_bots.py`: protocol oracle, 23 scenarios, fuzz, fault injection, soak, `GodotClient` fleet runner, puppet / tape / replay gates.

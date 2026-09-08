---
tags: [handoff]
---
# PASSDOWN — Tower Brawl (read this first in a new session)

Godot 4.7 web game (4-player LAN brawler), Python WebSocket relay; `docs/` is the Obsidian vault. Kickoff reads: `CLAUDE.md`, this file, the newest page in `Patch Notes/`, [[Commands]]. History: [[Changelog]]. Deep dives: `docs/reference/`. Closed: [[closed]].

## Now (2026-09-08, night)
- **v0.1.1 "Phone Controller" built** (build 1 of the v0.1.1 decision), harness 24/24 with `--restart-each`, no Minor, report `harness_report_v0.1.1.json`. Last tag: `v0.1.0`.
- **Backlog 27 closed the same afternoon, server only, no bump:** `DEATH_DEDUPE_S` 1.5 -> 0.6 (under the 1.2 s respawn), harness scenario `respawn_death`, suite 25/25 with `--restart-each`, no Minor, report `harness_report_v0.1.1_backlog27.json`; PC service restarted, deployed on the laptop ([[laptop-server]]). Story on the v0.1.1 page.
- **Waiting on a human:** [[Playtest — Master Validation Suite v0.1]], two phones on the laptop: section 1 the new controller, 2 the kill cam circle, 3 the speed burst (backlog 25).
- **Night soak 2026-09-08 (4 bots on the laptop):** 27 matches, 190 rounds, no "no closing kill" line, server 33 MB after 15 h; then backlog 27 deadlocked a round for 13 h (closed, see above). Numbers on the v0.1.1 page.
- **Next: build 2 = cut 1 proper** from the phones' rows: the first replay's start hitch (89 ms S25 Ultra, 52 ms Pixel) and the lobby's 21 to 35 ms worst frames on the S25; in play the phones sit at 7 to 8 ms, 60 ticks, no hitch. Then the arena configurations (backlog 9, 24). The Android app + PCK loader is an idea, not a plan.
- **Ideas, not scheduled:** a twin-stick toggle, `stats_table.py --devices` printing the screen size (Chrome hides the model), the Speed line as a server card, replay skip key, sound; later a headless Godot sim server. Detail: [[PASSDOWN-2026-09-05]].
- **v0.1.1 "Phone Controller":** round buttons on an arc, nearest-centre hit test (the old grown squares overlapped and jump won); a stick aim ring (aim without walking, 360°, kept after lift-off, `Global.touch_aim`); the replay circles the closing kill (`report_stamp()`); a `🏃 [Speed]` probe. See [[v0.1.1 - Phone Controller]].
- **v0.1.0 "Release":** v0.0.41 with a new number. See [[v0.1.0 - Release]].

## Open backlog
`N. **Title** — state — next action — where the detail lives`. Numbers are never reused; closed items are in [[closed]].
3. **Second tab spectating stalls the game tab** — open, mitigated — [[PASSDOWN-2026-09-05]].
4. **`server.log` / `debug.log` never rotate on the PC** — open (the laptop has logrotate) — [[PASSDOWN-2026-09-05]].
5. **`player_configs` still carries a default class per slot** — open, harmless — clean up when `global.gd` is touched.
9. **An outer ledge carries a fighter out of the top of the screen mid-shift** — open — arena configurations: outer ledges inside 165 px of the pivot, or wrap a fighter above the top edge to the bottom — [[v0.0.31 - Top Edge Probe]].
11. **Arena voids are a mechanic, not a bug** — user decision (v0.0.11) — nothing to do (`bot_brain.gd` routes through the seams).
12. **One-off `fleet.client-silent`** — seen once (v0.0.27) — if seen again keep `.harness_logs/godot2.log`.
13. **PC keyboard dead after a reload in the replay gap** — open, low, seen once — a clock time is enough (cards carry `keys=` `focus=`) — [[v0.0.28 - Rejoin in the Replay Gap]].
14. **Stall report from the playtest** — open, vague — ask for steps at the next playtest — [[Playtest v0.0.26]].
16. **The stomp-egg has no author over the network** — design call — a `player_hit` event relayed like `player_died` — [[v0.0.29 - Egg-Form Puppet]].
17. **Seam hiding** — design call — draw a second copy of a fighter near the seam — [[Playtest v0.0.17]].
18. **Archer kit revisit** — design call — slow regen, steal arrows, arrows in the join snapshot — [[v0.0.30 - Ranger Rejoin Quiver]].
20. **The W jump lock** — waiting on a `🪤 [JumpTrap]` line — [[v0.0.18 - Playtest Fixes: Bubble Spawn, Arrows, Bots, HUD]].
21. **Slope traction and air shield feel** — design call — fighters slide off tilted platforms (the Speed probe shows it) — [[Playtest v0.0.17]].
24. **Turning ledges sweep the anchored slab corners mid-turn** — open, accepted for v0.1.0 — arena configurations: soft turning pieces (`SHIFT_SOFT_PLATFORMS`) or outer ledges inward — [[v0.0.39 - Anchored Ground]].
25. **A fighter "went into super speed" for a second or two at a round start** — seen once (S25 Ultra, 2026-09-07) — the `🏃 [Speed]` probe (v0.1.1) prints the numbers; sheet section 3 wants a clock time — [[v0.1.1 - Phone Controller]].
26. **A death in the tail second after `round_end` still counts a stock** — open, low, design call — the winner's own kunai killed them after the round (rounds 2 and 7); should `serve_game.py` ignore it? — [[v0.1.1 - Phone Controller]].
28. **A round has no clock: two fighters that never meet play for ever** — design call — a round timer; backlog 27 showed it (closed; the client self-respawn safety net is the other half, build 2) — [[v0.1.1 - Phone Controller]].

## How to work here
- **Rules:** `CLAUDE.md` (rule 7 plain words; rule 8 trim step; no `.tscn` edits; GDScript ships via `./bump_build.sh`). One approved phase at a time; report bugs outside it, don't fix them. Every human-validation ask goes into [[Playtest — Master Validation Suite v0.1]] as a section with its own verdict.
- **Verify:** `godot --headless --path . --script tools/check_scripts.gd -- --no-net`, then `./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json` (bump first; detached; wait for `25/25`).
- **Serve:** `systemctl --user restart towerbrawl` after a `serve_game.py` change. Family nights: [[laptop-server]]. Deck: `tbdash`. The rest: [[Commands]].

## Architecture now
- `serve_game.py`: authoritative lobby/match state (slots, stocks, scores, rounds, 5-crown match end), relay for the rest. A reader thread per socket, a `ClientConn` writer thread with a bounded queue; `sync_pos` goes through the `MovementBatcher`, one `sync_bundle` per client every 50 ms. Client token gates slot reclaim; 8 s rejoin grace mid-match; deaths deduped per `DEATH_DEDUPE_S` 0.6 s (under the client's 1.2 s respawn, backlog 27). Round gaps `NEXT_ROUND_DELAY = 2.6`, `REPLAY_ROUND_DELAY = 6.5`, `MATCH_END_DELAY = 7.0`. Harness gate (`_harness_tick`). Tagged log lines; `status.json` once a second; `client_stats.jsonl` (cards and match / round / join / lock / kill / leave records).
- `scripts/global.gd`: the only network code on the client. JSON for events, binary for movement: `sync_pos` 11 B `[type, sender, tick u16, x*10 s16, y*10 s16, aim 0.1° u16, flags]` (bits: facing, dash, shield, bear, egg, on-ground), relayed inside `sync_bundle`, `spawn_projectile` 9 B; mirrored in `serve_game.py BIN_TYPES` and `tools/chaos_bots.py`. Signals out to `arena.gd` / `character_select.gd`; auto-rejoin, scene correction, combat state kept over reloads.
- `scripts/player.gd`: local sim + 20 Hz send with idle suppression; puppets render from a 16-sample ring 100 ms behind the sender. `_physics_process` order: shared timers, puppet branch, local egg branch, local controls; a respawn 1.2 s after a relayed death. Deaths reported by whoever saw the hit.
- `scripts/history_ring.gd` the tape (360 frames), `scripts/replay_player.gd` the VHS replay (211 frames around the closing kill), `scripts/touch_controls.gd` the phone controller, `scripts/bot_brain.gd` the personas (`wanderer chaser sniper turtle rusher griefer`). `web/shell.html` the page.
- `tools/watch_server.py`: the deck (`tbdash`). `tools/stats_table.py`: rows and match summaries from `client_stats.jsonl`. `tools/tbbot.py`: headless bots (logs in `.bots/`). `tools/chaos_bots.py`: 25 scenarios, the gates.

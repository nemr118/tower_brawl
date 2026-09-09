---
tags: [handoff]
---
# PASSDOWN — Tower Brawl (read this first in a new session)

Godot 4.7 web game (4-player LAN brawler), Python WebSocket relay; `docs/` is the Obsidian vault. Kickoff reads: `CLAUDE.md`, this file, the newest page in `Patch Notes/`, [[Commands]]. History: [[Changelog]]. Deep dives: `docs/reference/`. Closed: [[closed]].

## Now (2026-09-08, late night)
- **v0.1.3 "The Tower" built**, harness 25/25 with `--restart-each`, no Minor, report `harness_report_v0.1.3.json`, deployed on the laptop ([[laptop-server]]). Last tag: `v0.1.0` (v0.1.1 to v0.1.3 untagged).
- **Waiting on a human:** [[Playtest — Master Validation Suite v0.1]], two phones on the laptop: sections 1 to 5 (controller, kill cam circle, speed burst, respawn mash, cut 1) and **section 6 (the tower: map, holes, passages, camera, duck, look, markers, pace)**.
- **Next:** twin-stick phone controls (user, 2026-09-08): left stick moves, past its circle = a dash, above 45° = a jump; right stick aims, past its circle = a shot; a special button lower right; a switch button upper left. Then a playtest (sheet §7), then the §6 verdict.
- **Ideas, not scheduled:** `stats_table.py --devices` with the screen size and a `--replays` view, the Speed line as a server card, a replay skip key, sound, a headless Godot sim server. Detail: [[PASSDOWN-2026-09-05]].
- **v0.1.3 "The Tower":** the arena is a tower, 640 x 1080, walls outside the screen, holes in the floor and ceiling (x 256..384), side passages at y 380 and 800, one-way ledges every 70 px, built from `arena_layouts.gd` at load; a camera that follows up and down, duck (`FLAG_DUCK` 0x40), look (1.5 s hold, 200 px), off-screen markers, the shift off (`ARENA_SHIFT_ENABLED`), the pacing table. Scene edits allowed now (rule 1). See [[v0.1.3 - The Tower]], [[arena-tower]].
- **v0.1.2 "Cut 1":** lobby icons 256 px loaded once (`ICON_TEX`), a font warm-up at scene load (`🔤 [FontWarm]`), the ghost pool, a replay start probe (`start_ms tick_ms first_ms`), the self-respawn net (`🩹 [SelfRespawn]`, 1.0 s), a web client on the PC (`tools/webbot.sh`); `.pck` 21.9 -> 12.9 MB. See [[v0.1.2 - Cut 1]].

## Open backlog
`N. **Title** — state — next action — where the detail lives`. Numbers are never reused; closed items are in [[closed]].
3. **Second tab spectating stalls the game tab** — open, mitigated — [[PASSDOWN-2026-09-05]].
4. **`server.log` / `debug.log` never rotate on the PC** — open (the laptop has logrotate) — [[PASSDOWN-2026-09-05]].
5. **`player_configs` still carries a default class per slot** — open, harmless — clean up when `global.gd` is touched.
11. **Arena voids are a mechanic, not a bug** — user decision (v0.0.11) — nothing to do (`bot_brain.gd` routes through the seams).
12. **One-off `fleet.client-silent`** — seen once (v0.0.27) — if seen again keep the godot log.
13. **PC keyboard dead after a reload in the replay gap** — open, low, seen once — a clock time is enough — [[v0.0.28 - Rejoin in the Replay Gap]].
14. **Stall report from the playtest** — open, vague — ask for steps next time — [[Playtest v0.0.26]].
16. **The stomp-egg has no author over the network** — design call — a `player_hit` event relayed like `player_died` — [[v0.0.29 - Egg-Form Puppet]].
17. **Seam hiding** — design call — draw a second copy of a fighter near the seam — [[Playtest v0.0.17]].
18. **Archer kit revisit** — design call — slow regen, steal arrows, arrows in the join snapshot — [[v0.0.30 - Ranger Rejoin Quiver]].
20. **The W jump lock** — waiting on a `🪤 [JumpTrap]` line — [[v0.0.18 - Playtest Fixes: Bubble Spawn, Arrows, Bots, HUD]].
21. **Slope traction and air shield feel** — design call — fighters slide off tilted platforms (the Speed probe shows it) — [[Playtest v0.0.17]].
25. **A fighter "went into super speed" for a second or two at a round start** — seen once (S25 Ultra, 2026-09-07) — the `🏃 [Speed]` probe (v0.1.1) prints the numbers; sheet section 3 wants a clock time — [[v0.1.1 - Phone Controller]].
26. **A death in the tail second after `round_end` still counts a stock** — open, low, design call — the winner's own kunai killed them after the round (rounds 2 and 7); should `serve_game.py` ignore it? — [[v0.1.1 - Phone Controller]].
28. **A round has no clock: two fighters that never meet play for ever** — design call — a round timer; backlog 27 showed it (closed; the client's self-respawn safety net shipped in v0.1.2) — [[v0.1.1 - Phone Controller]].
29. **More than four players** — idea (user, 2026-09-08) — `range(1, 5)` in `serve_game.py`, four HUD panels, four spawn ledges — [[arena-tower]].

## How to work here
- **Rules:** `CLAUDE.md` (rule 7 plain words; rule 8 trim step; scene edits allowed (v0.1.3), load check after; GDScript ships via `./bump_build.sh`). One approved phase at a time; report bugs outside it, don't fix them. Every human-validation ask goes into [[Playtest — Master Validation Suite v0.1]] as a section with its own verdict.
- **Verify:** `godot --headless --path . --script tools/check_scripts.gd -- --no-net` (scripts and scenes), then `./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json` (bump first; detached; wait for `25/25`; it restarts the PC service per scenario: leave the service alone meanwhile).
- **Serve:** `systemctl --user restart towerbrawl` after a `serve_game.py` change. Laptop: [[laptop-server]]. Deck: `tbdash`. [[Commands]].

## Architecture now
- `serve_game.py`: authoritative lobby/match state (slots, stocks, scores, rounds, 5-crown match end), relay for the rest. A reader thread per socket, a `ClientConn` writer thread with a bounded queue; `sync_pos` goes through the `MovementBatcher`, one `sync_bundle` per client every 50 ms. Client token gates slot reclaim; 8 s rejoin grace mid-match; deaths deduped per `DEATH_DEDUPE_S` 0.6 s (under the client's 1.2 s respawn, backlog 27). Round gaps `NEXT_ROUND_DELAY = 2.6`, `REPLAY_ROUND_DELAY = 6.5`, `MATCH_END_DELAY = 7.0`. Harness gate (`_harness_tick`). Tagged log lines; `status.json` once a second; `client_stats.jsonl` (cards and match / round / join / lock / kill / leave records).
- `scripts/global.gd`: the only network code on the client. JSON for events, binary for movement: `sync_pos` 11 B `[type, sender, tick u16, x*10 s16, y*10 s16, aim 0.1° u16, flags]` (bits: facing, dash, shield, bear, egg, on-ground, duck), relayed inside `sync_bundle`, `spawn_projectile` 9 B; mirrored in `serve_game.py BIN_TYPES` and `tools/chaos_bots.py`. Signals out to `arena.gd` / `character_select.gd`; auto-rejoin, scene correction, combat state kept over reloads.
- `scripts/arena.gd` + `arena_layouts.gd` (v0.1.3): the tower is built at load from the table (walls layer 1, one-way ledges layer 6); the camera (`_camera_target`), the markers (`_draw_markers`), the spawn ledges (`_platform_tops`), the ceiling-hole respawn (`_spawn_spot`).
- `scripts/player.gd`: local sim + 20 Hz send with idle suppression; puppets render from a 16-sample ring 100 ms behind the sender. `_physics_process` order: shared timers, puppet branch, local egg branch, local controls (duck, drop-through, look); seams `arena_w` / `arena_h` (static); `MAX_FALL_SPEED` 600; a respawn 1.2 s after a relayed death. Deaths reported by whoever saw the hit.
- `scripts/history_ring.gd` the tape (360 frames), `scripts/replay_player.gd` the VHS replay (211 frames around the closing kill; ghosts pooled at load, a start probe), `scripts/font_warmup.gd` the glyph warm-up at scene load, `scripts/touch_controls.gd` the phone controller, `scripts/bot_brain.gd` the personas (`wanderer chaser sniper turtle rusher griefer`). `web/shell.html` the page.
- `tools/watch_server.py`: the deck (`tbdash`). `tools/stats_table.py`: rows and match summaries from `client_stats.jsonl`. `tools/tbbot.py`: headless bots (logs in `.bots/`). `tools/chaos_bots.py`: 25 scenarios, the gates.

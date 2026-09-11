---
tags: [handoff]
---
# PASSDOWN — Tower Brawl (read this first in a new session)

Godot 4.7 web game (4-player LAN brawler), Python WebSocket relay; `docs/` is the vault. Kickoff: `CLAUDE.md`, this file, the newest `Patch Notes/` page, [[Commands]]. History: [[Changelog]]. Deep dives: `reference/`.

## Now (2026-09-10)
- **v0.1.7 "Bug Sweep" built, not committed**, harness 25/25 with --restart-each, no Minor. The PC runs it with a new TLS pair. The laptop keeps v0.1.5 ([[laptop-server]]) for the soak (4 chasers since 18:16; at 1 h no stall). Last tag: `v0.1.0` (v0.1.1 to v0.1.7 untagged).
- **Waiting on a human:** [[Playtest v0.1.7]]: the soak's morning reading first, then the laptop deploy (the new pair, its logrotate file goes), then the yes/no lines and the verdict.
- **Next:** the decisions below. Still open: a focused read of `ws_client_thread` and its locks. Old master sheet: `archive/playtests/`.
- **Ideas:** stats views, a replay skip key, sound, a sim server. [[PASSDOWN-2026-09-05]].
- **v0.1.7 "Bug Sweep":** down + jump drops within `LEDGE_GRACE_S` (31); `--autojoin` asks again on `server_full` (32); ALL SEATS TAKEN on both JOIN buttons, and the arena finds `HUD/JoinBtn` again (33); new TLS pair, untracked (34); logs keep one `.1` (4); one `DEFAULT_CLASS` (5); the jump trap skips an eaten jump (20). [[v0.1.7 - Bug Sweep]].
- **v0.1.6 "Review Fixes":** the first code review (ultrareview, 7 findings checked by hand). Fixed in `serve_game.py`: spectator `client_stats` cards were dropped, the gate's demoted ip was `"(:'"`; in GDScript: names with `'` never saved (`JSON.stringify`). [[v0.1.6 - Review Fixes]].

## Open backlog
`N. **Title** — state — next action — detail`. Numbers are never reused; closed: [[closed]].
**Watching** (open; each has a trap or log line, nothing to do until one shows): 3 a second tab stalls the game tab ([[PASSDOWN-2026-09-05]]) · 13 PC keyboard dead after a reload in the replay gap ([[v0.0.28 - Rejoin in the Replay Gap]]) · 20 the W jump lock, `🪤 [JumpTrap]` ([[v0.1.7 - Bug Sweep]]) · 25 super speed, `🏃 [Speed]` ([[bot-soak-2026-09-08]]) · 26 a death after `round_end` counts a stock ([[bot-soak-2026-09-08]]).

**Decisions** (for the design session):
16. **The stomp-egg has no author over the network** — design call — relay a `player_hit` like `player_died` — [[v0.0.29 - Egg-Form Puppet]].
17. **Seam hiding** — design call — draw a second copy of a fighter near the seam — [[Playtest v0.0.17]].
18. **Archer kit revisit** — design call — slow regen, steal arrows, arrows in the join snapshot — [[v0.0.30 - Ranger Rejoin Quiver]].
21. **Air shield feel** — design call — slope traction is gone (the tower has no tilted pieces) — [[Playtest v0.0.17]].
28. **A round has no clock: two fighters that never meet play for ever** — design call — a round timer, a shrinking arena, or pull the fighters together — [[bot-soak-2026-09-08]].
29. **More than four players** — idea (user, 2026-09-08) — `range(1, 5)` in `serve_game.py`, four HUD panels, four spawn ledges — [[arena-tower]].
- **Tower build 2** — the next arena pass — [[arena-tower]].
- **A `v0.2.0` tag** — the runbook — [[release-v0.1.0]].

## How to work here
- **Rules:** `CLAUDE.md` (rule 7 plain words; rule 8 trim; scene edits allowed since v0.1.3, load check after; GDScript ships via `./bump_build.sh`). One approved phase at a time; report bugs outside it, don't fix them. **Human checks:** one short open sheet in `docs/` at a time (`Playtest vX.Y.Z.md`, named for the build that opens it): a yes/no line per thing only a person can judge, one verdict; proofs Claude runs go in the patch page.
- **Verify:** `godot --headless --path . --script tools/check_scripts.gd -- --no-net` (scripts and scenes), then `./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json` (bump first; detached; wait for `25/25`; it restarts the PC service per scenario: leave the service alone, and clear any bots first).
- **Serve:** `systemctl --user restart towerbrawl` after a `serve_game.py` change. Laptop: [[laptop-server]]. Deck: `tbdash`.

## Architecture now
- `serve_game.py`: authoritative lobby/match state (slots, stocks, scores, rounds, 5-crown match end), relay for the rest. A reader thread per socket, a `ClientConn` writer thread with a bounded queue; `sync_pos` via the `MovementBatcher`, one `sync_bundle` per client every 50 ms. Client token gates slot reclaim; 8 s rejoin grace mid-match; deaths deduped per `DEATH_DEDUPE_S` 0.6 s (under the client's 1.2 s respawn). Round gaps `NEXT_ROUND_DELAY = 2.6`, `REPLAY_ROUND_DELAY = 6.5`, `MATCH_END_DELAY = 7.0`. No round timer (backlog 28). Harness gate (`_harness_tick`). Tagged log lines (`server.log`, `debug.log`: `.1` at 50 MB); `status.json` once a second; `client_stats.jsonl`.
- `scripts/global.gd`: the only network code on the client. JSON for events, binary for movement: `sync_pos` 11 B `[type, sender, tick u16, x*10 s16, y*10 s16, aim 0.1° u16, flags]` (bits: facing, dash, shield, bear, egg, on-ground, duck), relayed inside `sync_bundle`, `spawn_projectile` 9 B; mirrored in `serve_game.py BIN_TYPES` and `tools/chaos_bots.py`. Signals to `arena.gd` / `character_select.gd`; auto-rejoin, `--autojoin` retry on `server_full`, scene correction, combat state kept over reloads.
- `scripts/arena.gd` + `arena_layouts.gd` (v0.1.3): the tower built at load from the table (walls layer 1, one-way ledges layer 6); camera `_camera_target`, markers `_draw_markers`, spawn ledges `_platform_tops`, ceiling-hole respawn `_spawn_spot`.
- `scripts/player.gd`: local sim + 20 Hz send with idle suppression; puppets render from a 16-sample ring 100 ms behind the sender. `_physics_process` order: shared timers, puppet branch, local egg branch, local controls (duck with `DUCK_GRACE_S`, drop-through with `LEDGE_GRACE_S`, look); seams `arena_w` / `arena_h`; `MAX_FALL_SPEED` 600; respawn 1.2 s after a relayed death. Deaths reported by whoever saw the hit.
- `scripts/history_ring.gd` the tape (360 frames), `scripts/replay_player.gd` the VHS replay (211 frames around the closing kill), `scripts/font_warmup.gd` the glyph warm-up, `scripts/touch_controls.gd` the phone controller (two layouts), `scripts/bot_brain.gd` the personas (`wanderer chaser sniper turtle rusher griefer`). `web/shell.html` the page.
- `tools/`: `watch_server.py` the deck (`tbdash`), `stats_table.py` rows and summaries from `client_stats.jsonl`, `tbbot.py` headless bots (logs in `.bots/`), `chaos_bots.py` 25 scenarios, `webshot.py` web screenshots over CDP, `duck_probe.gd` the duck check, `nav_probe.gd` routes and `--drop-test`, `join_full_probe.gd` JOIN on a full server.

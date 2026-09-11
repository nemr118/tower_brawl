---
tags: [handoff]
---
# PASSDOWN — Tower Brawl (read this first in a new session)

Godot 4.7 web game (4-player LAN brawler), Python WebSocket relay; `docs/` is the vault. Kickoff: `CLAUDE.md`, this file, the newest `Patch Notes/` page, [[Commands]]. History: [[Changelog]]. Deep dives: `reference/`.

## Now (2026-09-10)
- **v0.1.5 "Bot Routes" committed and pushed** (`663903c`), harness 25/25 with --restart-each, no Minor, deployed on the laptop ([[laptop-server]]). Last tag: `v0.1.0` (v0.1.1 to v0.1.5 untagged).
- **Waiting on a human:** [[Playtest — Master Validation Suite v0.1]] §1 to §7 (§6 the tower, §7 twin sticks; played 2026-09-08, no verdict). **§8, the laptop soak (4 chasers since 18:16):** at 1 h no stall (81 rounds, longest 82 s, 0 errors); the morning column and the verdict are left.
- **Next:** the §8 morning check; the user's whole-code ultrareview (`review/core` in `~/Work/tower_brawl_review`: `/code-review ultra` there), its findings as a phase; the §6 and §7 verdicts; or tower build 2 (themes, moving platforms, traps).
- **Ideas:** stats views, a replay skip key, sound, a sim server. [[PASSDOWN-2026-09-05]].
- **v0.1.5 "Bot Routes":** every soak stalled (a bot whose target stood above or below it froze, [[bot-soak-2026-09-08]]). `bot_nav.gd` (new) makes the layout 25 places to stand and the jumps, drops and walk-offs between them; `bot_brain.gd` follows the route, drops with down first (backlog 31), and has two stall guards (hunt after 20 s with no kill, a detour after 4 s stuck). Tools: `nav_probe.gd`, `soak_report.py`. [[v0.1.5 - Bot Routes]].
- **v0.1.4 "Twin Sticks":** a second phone layout in `touch_controls.gd` (`arc` / `twin`, saved as `towerbrawl_layout`, a SWAP button): the left stick walks, jumps and ducks, and past its rim dashes or drops through; the right stick aims, and past its rim shoots. The duck flicker fix: `DUCK_GRACE_S` 0.1 in `player.gd`. Tools: `webshot.py`, `duck_probe.gd`. [[v0.1.4 - Twin Sticks]].

## Open backlog
`N. **Title** — state — next action — detail`. Numbers are never reused; closed: [[closed]].
3. **Second tab spectating stalls the game tab** — open, mitigated — [[PASSDOWN-2026-09-05]].
4. **Logs: no rotation on the PC; the laptop rotates but keeps no `.1`** — open — [[bot-soak-2026-09-08]].
5. **`player_configs` carries a default class per slot** — open, harmless — clean up when `global.gd` is touched.
11. **Arena voids are a mechanic, not a bug** — user decision (v0.0.11) — nothing to do.
12. **One-off `fleet.client-silent`** — seen once (v0.0.27) — keep the godot log if seen again.
13. **PC keyboard dead after a reload in the replay gap** — open, low, seen once — a clock time is enough — [[v0.0.28 - Rejoin in the Replay Gap]].
14. **Stall report from the playtest** — open, vague — ask for steps — [[Playtest v0.0.26]].
16. **The stomp-egg has no author over the network** — design call — relay a `player_hit` like `player_died` — [[v0.0.29 - Egg-Form Puppet]].
17. **Seam hiding** — design call — draw a second copy of a fighter near the seam — [[Playtest v0.0.17]].
18. **Archer kit revisit** — design call — slow regen, steal arrows, arrows in the join snapshot — [[v0.0.30 - Ranger Rejoin Quiver]].
20. **The W jump lock** — 6 `🪤 [JumpTrap]` lines caught, all on ledge rows, contacts 1 to 3 — read them, then fix — [[bot-soak-2026-09-08]].
21. **Slope traction and air shield feel** — design call — fighters slide off tilted platforms — [[Playtest v0.0.17]].
25. **A fighter "went into super speed"** — seen once at a round start (phone, 2026-09-07); a different one at the left wall (341 px/s, vel 0) — sheet §3 wants a clock time — [[bot-soak-2026-09-08]].
26. **A death in the tail second after `round_end` still counts a stock** — open, low — 18 seen on v0.1.0/v0.1.1, none on v0.1.4 — [[bot-soak-2026-09-08]].
28. **A round has no clock: two fighters that never meet play for ever** — design call; bots no longer stall (v0.1.5 routes and hunt), people still can — a round timer, a shrinking arena, or pull the fighters together — [[bot-soak-2026-09-08]].
29. **More than four players** — idea (user, 2026-09-08) — `range(1, 5)` in `serve_game.py`, four HUD panels, four spawn ledges — [[arena-tower]].
31. **Down and jump in the same frame jump instead of dropping through** — open — S + W together, a twin-stick flick past the down rim; fix in `player.gd` (the drop check) or `touch_controls.gd` (down first) — [[v0.1.5 - Bot Routes]].
32. **A bot added right after `tbbot clear` never gets a seat** — open — a leaving seat is held 8 s and `--autojoin` never asks again; retry, or `tbbot add` waits — [[v0.1.5 - Bot Routes]].

## How to work here
- **Rules:** `CLAUDE.md` (rule 7 plain words; rule 8 trim; scene edits allowed since v0.1.3, load check after; GDScript ships via `./bump_build.sh`). One approved phase at a time; report bugs outside it, don't fix them. Every human-validation ask becomes a section with its own verdict in [[Playtest — Master Validation Suite v0.1]].
- **Verify:** `godot --headless --path . --script tools/check_scripts.gd -- --no-net` (scripts and scenes), then `./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json` (bump first; detached; wait for `25/25`; it restarts the PC service per scenario: leave the service alone, and clear any bots first).
- **Serve:** `systemctl --user restart towerbrawl` after a `serve_game.py` change. Laptop: [[laptop-server]]. Deck: `tbdash`.

## Architecture now
- `serve_game.py`: authoritative lobby/match state (slots, stocks, scores, rounds, 5-crown match end), relay for the rest. A reader thread per socket, a `ClientConn` writer thread with a bounded queue; `sync_pos` via the `MovementBatcher`, one `sync_bundle` per client every 50 ms. Client token gates slot reclaim; 8 s rejoin grace mid-match; deaths deduped per `DEATH_DEDUPE_S` 0.6 s (under the client's 1.2 s respawn). Round gaps `NEXT_ROUND_DELAY = 2.6`, `REPLAY_ROUND_DELAY = 6.5`, `MATCH_END_DELAY = 7.0`. No round timer (backlog 28). Harness gate (`_harness_tick`). Tagged log lines; `status.json` once a second; `client_stats.jsonl`.
- `scripts/global.gd`: the only network code on the client. JSON for events, binary for movement: `sync_pos` 11 B `[type, sender, tick u16, x*10 s16, y*10 s16, aim 0.1° u16, flags]` (bits: facing, dash, shield, bear, egg, on-ground, duck), relayed inside `sync_bundle`, `spawn_projectile` 9 B; mirrored in `serve_game.py BIN_TYPES` and `tools/chaos_bots.py`. Signals to `arena.gd` / `character_select.gd`; auto-rejoin, scene correction, combat state kept over reloads.
- `scripts/arena.gd` + `arena_layouts.gd` (v0.1.3): the tower built at load from the table (walls layer 1, one-way ledges layer 6); camera `_camera_target`, markers `_draw_markers`, spawn ledges `_platform_tops`, ceiling-hole respawn `_spawn_spot`.
- `scripts/player.gd`: local sim + 20 Hz send with idle suppression; puppets render from a 16-sample ring 100 ms behind the sender. `_physics_process` order: shared timers, puppet branch, local egg branch, local controls (duck with `DUCK_GRACE_S`, drop-through, look); seams `arena_w` / `arena_h`; `MAX_FALL_SPEED` 600; respawn 1.2 s after a relayed death. Deaths reported by whoever saw the hit.
- `scripts/history_ring.gd` the tape (360 frames), `scripts/replay_player.gd` the VHS replay (211 frames around the closing kill), `scripts/font_warmup.gd` the glyph warm-up, `scripts/touch_controls.gd` the phone controller (two layouts), `scripts/bot_brain.gd` the personas (`wanderer chaser sniper turtle rusher griefer`). `web/shell.html` the page.
- `tools/`: `watch_server.py` the deck (`tbdash`), `stats_table.py` rows and summaries from `client_stats.jsonl`, `tbbot.py` headless bots (logs in `.bots/`), `chaos_bots.py` 25 scenarios, `webshot.py` web screenshots over CDP, `duck_probe.gd` the duck check.

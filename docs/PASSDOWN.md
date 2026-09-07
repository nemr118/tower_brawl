---
tags: [handoff]
---
# PASSDOWN — Tower Brawl (read this first in a new session)

Godot 4.7 web game (4-player LAN brawler), Python WebSocket relay; `docs/` is the Obsidian vault. Kickoff reads: `CLAUDE.md`, this file, the newest page in `Patch Notes/`, [[Commands]]. History: [[Changelog]]. Deep dives: `docs/reference/`. Closed: [[closed]].

## Now (2026-09-07)
- **Tagged `v0.0.41`** on `master`, tree clean. **Harness 24/24 with `--restart-each`, no Minor**, report `harness_report_v0.0.41.json`. **The family plays on the laptop** ([[laptop-server]]): `tools/deploy_laptop.sh <ip>` pushes a build, `tools/pull_laptop_logs.sh <ip>` pulls the night's data.
- **Next: tag `v0.1.0` = v0.0.41 with a new number, no code change (decided 2026-09-07).** Runbook: [[release-v0.1.0]]. Gate: sheet section 6 on v0.0.41, then `release/v0.1.0`, `./bump_build.sh minor`, suite 24/24, tag, ff-merge, deploy to the laptop. **v0.1.1** = cut 1 (the phone main thread) or the Android export + PCK loader; decide at the tag (runbook §5). Bundle feels late? `RELAY_BUNDLE_MS = 0`.
- **Waiting on a human: one sheet, [[Playtest — Master Validation Suite]]** (v0.0.41). No console: clock times only (match log 0.1); `tools/stats_table.py --match N` prints the rows. Sections: 1 phone frames, 2 ranger quiver (backlog 1, 6), 3 PC reload keys (backlog 13), 4 shift feel with the anchored floor (backlog 9, 24), 5 bundle feel, 6 v0.1.0 sign-off. Stays in `docs/` until every verdict is ticked.
- **Ideas, not scheduled:** replay skip key, virtual stick, touch buttons, spawn shield, death animations, zoomed replay, sound; later a headless Godot sim server replaces the relay, native apps + PCK loader, Dead Cells style 3D fighters, a quarter-turn walls layout. Detail: [[PASSDOWN-2026-09-05]].
- **v0.0.41 "Drawn Replay Icons":** the replay overlay's ◄◄ ► ■ marks were font glyphs the web build's font does not have (boxes in a browser); `replay_player.gd` `_draw_icon` draws them as outlined shapes. Deck `--controls`: `a` opens a bot menu (1 to 6 = a persona). See [[v0.0.41 - Drawn Replay Icons]].
- **v0.0.40 "LAN Server Kit":** the laptop server tools ([[laptop-server]]): `tbbot.py` (headless bots, backlog 19 closed), `tbdash --controls`, `deploy_laptop.sh`, `pull_laptop_logs.sh`; `serve_game.py` writes join / name / lock / kill / leave records to `client_stats.jsonl`; `stats_table.py --summary` (K/D, classes, weapons, devices) and `--events`. See [[v0.0.40 - LAN Server Kit]].

## Open backlog
`N. **Title** — state — next action — where the detail lives`. Numbers are never reused; closed items are in [[closed]].
3. **Second tab spectating stalls the game tab** — open, mitigated — use a second device — [[PASSDOWN-2026-09-05]].
4. **`server.log` / `debug.log` never rotate** — open — add rotation inside the optimisation plan — [[PASSDOWN-2026-09-05]].
5. **`player_configs` still carries a default class per slot** — open, harmless — clean up when `global.gd` is touched.
9. **An outer ledge carries a fighter out of the top of the screen mid-shift** — open (only the ledges swing past the edge since v0.0.39) — arena configurations: outer ledges inside 165 px of the pivot, or option B (wrap a fighter above the top edge to the bottom) — [[v0.0.31 - Top Edge Probe]].
11. **Arena voids are a mechanic, not a bug** — user decision (v0.0.11) — nothing to do (`bot_brain.gd` routes through the seams).
12. **One-off `fleet.client-silent`** — seen once (v0.0.27) — if it shows again keep `.harness_logs/godot2.log`.
13. **PC keyboard dead after a reload in the replay gap** — waiting on a human — run sheet section 3, read `keys= focus=` — [[Playtest — Master Validation Suite]], [[v0.0.28 - Rejoin in the Replay Gap]].
14. **Stall report from the playtest** — open, vague — ask for exact steps at the next playtest — [[Playtest v0.0.26]].
16. **The stomp-egg has no author over the network** — design call — a `player_hit` event from the observer, relayed like `player_died` — [[v0.0.29 - Egg-Form Puppet]].
17. **Seam hiding** — design call — a fighter is drawn on one side of the seam only; draw a second copy near the edge — [[Playtest v0.0.17]].
18. **Archer kit revisit (behind backlog 1, 6, 15)** — design call — slow regen, steal arrows, arrows in the join snapshot, ammo on other screens — [[v0.0.30 - Ranger Rejoin Quiver]].
20. **The W jump lock** — waiting on a `🪤 [JumpTrap]` line from a real game — [[v0.0.18 - Playtest Fixes: Bubble Spawn, Arrows, Bots, HUD]].
21. **Slope traction and air shield feel** — design call — fighters slide off tilted platforms; an air shield kills sideways speed — [[Playtest v0.0.17]].
24. **Turning ledges sweep the anchored slab corners mid-turn** — open, accepted for v0.1.0 — arena configurations: soft turning pieces (`SHIFT_SOFT_PLATFORMS`) or outer ledges inward; sheet 4.1 asks if it hurt anyone — [[v0.0.39 - Anchored Ground]].

## How to work here
- **Rules:** `CLAUDE.md` (rule 7 plain words; rule 8 trim step; no `.tscn` edits; GDScript ships via `./bump_build.sh --title "..."`). One approved phase at a time; report bugs outside it, don't fix them. Every human-validation ask goes into [[Playtest — Master Validation Suite]] as a section with its own verdict.
- **Verify:** `godot --headless --path . --script tools/check_scripts.gd -- --no-net`, then `./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json` (bump first; detached; wait for `24/24 scenarios passed`).
- **Serve:** `systemctl --user restart towerbrawl` after any `serve_game.py` change. Family nights: [[laptop-server]]. Play: `https://192.168.4.21:8443/play`. Deck: `tbdash`. The rest: [[Commands]].

## Architecture now
- `serve_game.py`: authoritative lobby/match state (slots, stocks, scores, rounds, 5-crown match end), relay for the rest. A reader thread per socket, a `ClientConn` writer thread with a bounded queue (movement dropped first, stalled peers dropped); `sync_pos` goes through the `MovementBatcher`, one `sync_bundle` per client every 50 ms (v0.0.36). Client token gates slot reclaim; 8 s rejoin grace mid-match, a held seat counts as present at `new_round`; observer deaths deduped per 1.5 s. Round gaps `NEXT_ROUND_DELAY = 2.6`, `REPLAY_ROUND_DELAY = 6.5`, `MATCH_END_DELAY = 7.0`. Harness gate (`_harness_tick`). Tagged log lines; `status.json` once a second; `client_stats.jsonl` (cards, match / round / join / lock / kill / leave records).
- `scripts/global.gd`: the only network code on the client. JSON for events, binary for movement: `sync_pos` 11 B `[type, sender, tick u16, x*10 s16, y*10 s16, aim 0.1° u16, flags]` (bits: facing, dash, shield, bear, egg, on-ground), relayed inside `sync_bundle` (v0.0.36), `spawn_projectile` 9 B; mirrored in `serve_game.py BIN_TYPES` and `tools/chaos_bots.py`. Signals out to `arena.gd` / `character_select.gd`; auto-rejoin, scene correction, combat state kept over reloads.
- `scripts/player.gd`: local sim + 20 Hz send with idle suppression; puppets render from a 16-sample ring 100 ms behind the sender (`_render_snapshots`). `_physics_process` order: shared timers, puppet branch (early return), local egg branch, local controls. `restore_combat_state` on a rejoin. Deaths reported by whoever saw the hit.
- `scripts/history_ring.gd` the tape (360 frames) and `scripts/replay_player.gd` the VHS replay (211 frames around the closing kill), driven by `arena.gd`. `scripts/harness_ticker.gd` the join-locked panel; `scripts/bot_brain.gd` the personas (`wanderer chaser sniper turtle rusher griefer`). `web/shell.html` the page (phone helpers, canvas focus self-heal).
- `tools/watch_server.py` + `tools/deck_input.py`: the deck (`tbdash`; `--controls` = the laptop's SERVER panel). `tools/stats_table.py`: rows and match summaries from `client_stats.jsonl`. `tools/tbbot.py`: headless bots. `tools/chaos_bots.py`: protocol oracle, 24 scenarios, fleet runner, the gates.

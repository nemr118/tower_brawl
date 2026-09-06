---
tags: [handoff]
---
# PASSDOWN — Tower Brawl (read this first in a new session)

Godot 4.7 web game (4-player LAN brawler), custom WebSocket relay in Python. `docs/` is the Obsidian vault. Kickoff reads: `CLAUDE.md`, this file, the newest page in `Patch Notes/`, [[Commands]]. History: [[Changelog]]. Deep dives: `docs/reference/`. Closed: [[closed]].

## Now (2026-09-05)
- **Tagged `v0.0.36`** on `master`, working tree clean at handoff. **Harness 24/24 with `--restart-each`, no Minor**, report `harness_report_v0.0.36.json`.
- **Next: optimisation Step C, cut 1 (the phone), or `v0.1.0`.** Cuts 2 (v0.0.35) and 3 (v0.0.36) are done; the phone main thread is the last cut on [[optimisation_step_b_profiles]] and needs a human first: read the S25 Ultra over USB (master sheet section 1, `proc=` / `phys_cpu=`) before cutting a script; section 5 judges the bundle's feel. Not worth a build: `status_loop`, the 40 log lines, JSON to binary. Bundle feels late on Wi-Fi? `RELAY_BUNDLE_MS = 0` in `serve_game.py`, no client build.
- **Waiting on a human: one sheet, [[Playtest — Master Validation Suite]]** (v0.0.36). Sections: 1 phone frame numbers over USB (S25 Ultra, Pixel, iPad), 2 ranger quiver (backlog 1, 6), 3 PC reload keyboard probe (backlog 13), 4 free-fall feel (backlog 23), 5 puppet feel with the bundles. Stays in `docs/` until every verdict is ticked.
- **v0.1.0 ideas, not scheduled:** replay skip key, virtual stick, touch buttons, spread air spawns, spawn shield, death animations, zoomed replay, montage, sound on the flash, replay on demand. Detail: [[PASSDOWN-2026-09-05]].
- **v0.0.36 "Relay Packet Coalescing" (optimisation Step C, build 3):** `serve_game.py` holds each `sync_pos` up to 50 ms (`RELAY_BUNDLE_MS`); a `MovementBatcher` thread sends ONE `sync_bundle` (type 3, `[3, n, n x 10 B]`) per client, never with the recipient's own entries. `global.gd` `_emit_sync_entry` unpacks both types; `chaos_bots.py` flattens bundles, new `bundle` scenario (24th). Fleet: packets into a client 38 → 17 /s (-55 %), bytes -9 %, jitter unchanged, `extrap` 1.2 → 5 %. See [[v0.0.36 - Relay Packet Coalescing]], design [[optimisation_step_c_bundle]].
- **v0.0.35 "Tape Card on Change" (optimisation Step C, build 2):** `arena.gd` no longer sends the `history_status` card on every kill stamp; the stamp marks it dirty and `_record_tape_frame` sends it at most once per `TAPE_CARD_MIN_S` (10 s); freeze and replay start / skip / end send at once. Fleet, 4 brains, 90 s: cards per screen 48.8 → 14.0, card bytes 217 → 67 B/s (-69 %). See [[v0.0.35 - Tape Card on Change]].

## Open backlog
`N. **Title** — state — next action — where the detail lives`. Numbers are never reused; closed items are in [[closed]].
3. **Second tab spectating stalls the game tab** — open, mitigated — spectate from a second device or profile — [[PASSDOWN-2026-09-05]].
4. **`server.log` / `debug.log` never rotate** — open — add rotation inside the optimisation plan — [[PASSDOWN-2026-09-05]].
5. **`player_configs` still carries a default class per slot** — open, harmless — clean up when `global.gd` is next touched.
11. **Arena voids are a mechanic, not a bug** — user decision (v0.0.11) — nothing to do (`bot_brain.gd` routes through the seams).
12. **One-off `fleet.client-silent`** — seen once (v0.0.27 run 1) — if it shows again keep `.harness_logs/godot2.log` — `harness_report_v0.0.27_run1.json`.
13. **PC keyboard dead after a reload in the replay gap** — waiting on a human — run section 3 of the master sheet and read `keys= focus=` — [[Playtest — Master Validation Suite]], [[v0.0.28 - Rejoin in the Replay Gap]].
14. **Stall report from the playtest** — open, vague — ask for exact steps at the next playtest, do not guess a fix — [[Playtest v0.0.26]].
16. **The stomp-egg has no author over the network** — design call — a `player_hit` event from the observer, relayed like `player_died`; the victim's client runs `take_hit` on itself — [[v0.0.29 - Egg-Form Puppet]].
17. **Seam hiding** — design call — a fighter is drawn on one side of the seam only; draw a second copy near the edge — [[Playtest v0.0.17]].
18. **Archer kit revisit (the proper fix behind backlog 1, 6, 15)** — design call — slow regen, steal enemy arrows, arrows in the join snapshot, ammo count on other screens, the two-arrow frame — [[v0.0.30 - Ranger Rejoin Quiver]].
19. **Fill-with-bots button** — design call — the server would have to start headless bot processes.
20. **The W jump lock** — waiting on a `🪤 [JumpTrap]` line from a real game — then fix — [[v0.0.18 - Playtest Fixes: Bubble Spawn, Arrows, Bots, HUD]].
21. **Slope traction and air shield feel** — design call — fighters slide off tilted platforms; an air shield kills sideways speed — [[Playtest v0.0.17]].
22. **Hiding on top of the flipped ground** — design call — upside down, the old floor sits at the top edge — [[Playtest v0.0.17]].

## How to work here
- **Rules:** `CLAUDE.md` (plain words, rule 7; wrap up with the trim step, rule 8; no `.tscn` edits; GDScript ships via `./bump_build.sh --title "..."`). One approved phase at a time; report bugs outside it, don't fix them. Every human-validation ask goes into [[Playtest — Master Validation Suite]] as a section with its own verdict.
- **Verify:** `godot --headless --path . --script tools/check_scripts.gd -- --no-net`, then `./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json` (bump first; run detached, wait for `24/24 scenarios passed`).
- **Serve:** `systemctl --user restart towerbrawl` after any `serve_game.py` change. Play at `https://192.168.4.21:8443/play`. Live view: `tbdash`. The rest: [[Commands]].

## Architecture now
- `serve_game.py`: authoritative lobby/match state (slots, alive, stocks, scores, rounds, 5-crown match end), relay for the rest. One reader thread per socket, one `ClientConn` writer thread with a bounded queue (movement dropped first, stalled peers dropped after ~5 s); `sync_pos` goes through the `MovementBatcher`, one `sync_bundle` per client every 50 ms (v0.0.36). Client token gates slot reclaim; 8 s rejoin grace mid-match, a held seat counts as present at `new_round`; observer-authoritative deaths deduped per 1.5 s. Round gaps `NEXT_ROUND_DELAY = 2.6`, `REPLAY_ROUND_DELAY = 6.5`, `MATCH_END_DELAY = 7.0`. Harness gate (`_harness_tick`). Tagged log lines; `status.json` once a second (`status_loop`).
- `scripts/global.gd`: the only network code on the client. JSON for events, binary for movement: `sync_pos` 11 B `[type, sender, tick u16, x*10 s16, y*10 s16, aim 0.1° u16, flags]` (bits: facing, dash, shield, bear, egg, feet-on-the-ground), relayed inside `sync_bundle` since v0.0.36, `spawn_projectile` 9 B; mirrored in `serve_game.py BIN_TYPES` and `tools/chaos_bots.py`. Signals out to `arena.gd` / `character_select.gd`. Auto-rejoin, scene correction, combat state persisted for reloads.
- `scripts/player.gd`: local sim + 20 Hz send with idle suppression; puppets render from a 16-sample ring 100 ms behind the sender (`_render_snapshots`). `_physics_process` order: shared timers, puppet branch (early return), local egg branch, local controls. `restore_combat_state` on a rejoin. Deaths reported by whoever saw the hit.
- `scripts/history_ring.gd` the tape (360 frames) and `scripts/replay_player.gd` the VHS replay (211 frames around the closing kill), both driven by `arena.gd`. `scripts/harness_ticker.gd` the join-locked panel. `scripts/bot_brain.gd` the personas (`wanderer chaser sniper turtle rusher griefer`). `web/shell.html` the page with the phone helpers and the canvas focus self-heal.
- `tools/watch_server.py` + `tools/deck_input.py`: the deck (`tbdash`), reads `status.json` and `harness_state.json` only. `tools/chaos_bots.py`: protocol oracle, 24 scenarios, fuzz, fault injection, soak, `GodotClient` fleet runner, puppet / tape / replay gates.

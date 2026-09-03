---
tags: [handoff]
---
# PASSDOWN — Tower Brawl (read this first in a new session)

Godot 4.7 web game (4-player LAN brawler), custom WebSocket relay in Python, browser + phone clients. Repo `~/Work/tower_brawl`, this folder is symlinked into the Obsidian vault as `Tower Brawl`.

## Current status (2026-09-02)
- **Commit tagged `v0.0.8`** on `master`. Working tree clean at handoff.
- **Harness 17/17** (`tools/chaos_bots.py --restart-each`), report `harness_report_v0.0.8.json`. Fleet of 2 headless Godot clients: 0 script errors.
- **Phase 3a done and playtested on phone + PC:** 20 Hz movement with idle suppression, u16 tick in every movement sample, bounded per-client send queues + stall detection in `serve_game.py`.
- Phases 0, 0.5, 1, 2, 3a complete. Full history: [[Changelog]] and `Patch Notes/`.

## How to work here
- **Rules:** `CLAUDE.md` in the repo root (no `.tscn` edits; every GDScript change ships via `./bump_build.sh --title "..."`, which compile-checks with autoloads live, bumps `v0.0.x`, exports, cache-busts the pck, generates the patch-notes page; patch notes on every bump). The user approves one phase at a time; report bugs found outside the phase, don't fix them unasked.
- **Verify:** `godot --headless --path . --script tools/check_scripts.gd -- --no-net` (`--check-only` is useless here) then `./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json`. `--scenario X` for one; `--list` for all 17; `--soak 30` for leaks; `--scenario play --latency-ms 120 --loss 0.05` for fault injection.
- **Serve/play:** `systemctl --user restart towerbrawl` after any `serve_game.py` change (client-only changes need no restart: the server re-reads the version from `global.gd`). Everyone opens `https://192.168.4.21:8443/play` (redirects to the current build; PC on plain http is not a secure context in Chromium). Logs: `server.log` (never rotated, contains days of history: filter by the last "Game version" banner line), `.harness_logs/godot*.log`.
- **Headless real client:** `godot --headless --path . -- --autojoin --name=X --class=N` (NetStats line every 5 s in its stdout).
- **Docs live in `docs/`** (= the vault). Commands and gotchas: [[obsidian_notes]].

## Architecture in one screen
- `serve_game.py`: authoritative lobby/match state (slots, playing/waiting, alive, stocks, scores, rounds, 5-crown match end), relay for everything else. One reader thread per socket + one `ClientConn` writer thread with a bounded queue (movement dropped first when backed up; stalled peers dropped after ~5 s of a non-shrinking kernel backlog). TCP keepalive instead of app-level timeouts (hidden tabs keep their seat). Frame cap 4 KB, relay cap 1 KB. Sender stamped server-side. Client token gates slot reclaim; 8 s rejoin grace mid-match; 1.5 s forfeit grace on explicit leave; observer-authoritative deaths deduped per 1.5 s.
- `scripts/global.gd`: the only network code on the client. JSON for events, **binary for movement**: `sync_pos` 11 B `[type, sender, tick u16, x*10 s16, y*10 s16, aim 0.1° u16, flags]`, `spawn_projectile` 9 B. Layout mirrored in `serve_game.py BIN_TYPES` and `tools/chaos_bots.py`. Signals out to `arena.gd` / `character_select.gd` (both connect from a table and disconnect in `_exit_tree`). Auto-rejoin after a reconnect, scene correction to the server state, combat state (ammo, tick) persisted for reloads.
- `scripts/player.gd`: local sim + 20 Hz send with idle suppression; remote puppets lerp to the last sample (**Phase 3b replaces this**); deaths reported by whoever saw the hit.
- `tools/chaos_bots.py`: protocol oracle + 17 scenarios + fuzz + fault injection + soak + `GodotClient` fleet runner.

## Open backlog / edge cases
1. **Ranger reload mid-match** loses the stuck arrows on the ground (projectiles are not in any snapshot) → 0 ammo, no pickups until the next round. Simple fallback: restore ≥1 arrow on a mid-match rejoin; proper fix with the class-kit revisit (arrows in the join snapshot, or slow regen). See [[Playtest v0.0.8]].
2. **Frame-0 input read with id 0**: one fleet run logged `InputMap action "p0_left" doesn't exist` (a fighter with id 0 read input for one frame in the lobby→arena window). Not reproduced in 5 runs; guards added in `player.gd`, `arena.gd`, `character_select.gd`. If it recurs, capture `.harness_logs/godot2.log` with `--verbose`.
3. Spectating from a second tab of the same browser shares Chromium's renderer main thread with the game tab (input stalls during heavy work in the other tab). Mitigated (inputs released on focus loss); use a second device/profile to spectate.
4. `server.log` / `debug.log` never rotate (untracked; multi-day files). Consider rotation.
5. Godot client `player_configs` still carries a default class per slot; harmless.

## Immediate next milestone: AI bot brains (between 3a and 3b)
Design agreed with the user (see the session summary in this file's history):
- `scripts/bot_brain.gd`, a node attached to the **local** fighter when the client starts with `--autojoin --ai=<persona>`. Perceives by reading the scene tree (`players` group with dash/shield state, `projectiles` group, platforms, powerup). Acts by pressing the same input actions a human presses (`Input.action_press/release` on `p<N>_left/right/up/down/jump/dash/attack/special`), so `player.gd` stays untouched.
- Personas: `wanderer` (baseline motion), `chaser` (close distance, jump when blocked, dash to engage/escape), `sniper` (keep range, lead shots with target velocity), `turtle` (shield on inbound projectile), `rusher` (rogue dash-slash), `griefer` (deliberate edge cases: wrap seam, dash through projectiles, spam shield, stand on the powerup, toggle bear form). Human-likeness knobs: reaction delay 100–250 ms, gaussian aim error, difficulty scalar, seed.
- Harness: `--godot N --ai <persona>` on the fleet scenario; assertions unchanged (no script errors, everyone fought, rounds ended). Add an artificial latency option on the Godot send path (bots on the server machine see 0 ms).
- Later, bot-fill for real matches: a bot manager in `serve_game.py` spawning `godot --headless -- --autojoin --ai=chaser --name=Bot` on request, capped so humans always get a seat, bots yield on a full server; a `bot: true` flag in `player_joined` for the roster.
- Why before 3b: the puppet-jitter metric is only meaningful under human-like acceleration and reversals.

## Remaining roadmap to v0.1.0
- **Phase 3b:** snapshot interpolation on remote puppets (≈100 ms render delay, short extrapolation using tick timing), replacing the exponential lerp; a **puppet-jitter telemetry metric** in the NetStats line (per-frame position jumps on remote fighters) so `lag` scenarios get a quality pass/fail. Harness `--latency-ms/--jitter-ms/--loss` already exist.
- **Phase 3c:** 5-second ring buffer of rendered state (players, projectiles, platform rotation) at physics rate on every client; kill-frame stamping from `player_died` / `round_end`; server-sent round-end duration so client and server agree on the replay window.
- **v0.1.0:** the VHS round-winning replay: rewind visuals + grain shader + rewind sound, playback with 0.5× slow-mo starting 2 s before the final kill. Tag v0.1.0 only when the replay, the netcode bugs and the optimisation plan are all done.

## Post-v0.1.0 (high level)
Mobile fullscreen API bridge; unified input mapping + settings menu; combat depth (head-stomp kill, status effects, projectile/character model reworks); scaling beyond 4 players.

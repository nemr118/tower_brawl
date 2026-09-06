---
tags: [handoff, commands]
---
# Commands (the hot list; deep dives in `reference/`)

## Editor and server
```bash
godot --editor project.godot &                    # open the Godot editor
./venv/bin/python serve_game.py                   # the WebSocket backend + HTTP file server, by hand
systemctl --user restart towerbrawl               # the service; needed after any serve_game.py change
systemctl --user status towerbrawl
```
Play: `https://192.168.4.21:8443/play` (redirects to the current build; PC on plain http is not a secure context).

## Build, bump and cache-bust (every GDScript change)
```bash
./bump_build.sh --title "Short Title"   # compile-check with autoloads live, bump v0.0.x, export, version the pck, make the patch page
./bump_build.sh minor                   # v0.0.x -> v0.1.0 (only after replay, netcode bugs and optimisations)
./bump_build.sh none                    # re-export the current version (does NOT bust caches)
./bump_build.sh --clean                 # also delete older index_v*.pck copies (20 MB each)
godot --headless --path . --script tools/check_scripts.gd -- --no-net   # the compile check alone
```
`GAME_VERSION` lives in `scripts/global.gd` only; the script mirrors it into `serve_game.py`, the server re-reads it on every join.

## The harness (`tools/chaos_bots.py`)
```bash
./venv/bin/python tools/chaos_bots.py --list                   # the 24 scenarios
setsid nohup ./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json > <scratch>/harness.log 2>&1 &   # the full gate, one report per build, detached
grep -c "scenarios passed" <scratch>/harness.log               # wait for "24/24 scenarios passed"
./venv/bin/python tools/chaos_bots.py --scenario smoke --trace /tmp/trace.jsonl   # one scenario, packet capture
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 4 --ai chaser,sniper,turtle,rusher --duration 90 --latency-ms 120 --jitter-ms 40   # the fleet gate; --jitter-ms 150 = heavy; --loss 0.05 = gaps
./venv/bin/python tools/chaos_bots.py --soak 30                # loop the suite (RSS, fds)
```
Other scenarios: `fuzz`, `slow_reader`, `lag`, `bundle` (v0.0.36: 20 `sync_bundle`/s, relay delay), `tape`, `replay`, `reload_in_gap`, `ranger_rejoin`. Knobs: `--seed`, `--die-rate`, `--ai-difficulty 0.3`, `--no-state`. Levels: `PASS`, `FAIL`, `MINOR` (passed, but the server logged an `ERROR` or a client a `WARNING:`). Client logs: `.harness_logs/godot<N>.log`.

## Headless Godot as a real client
```bash
godot --headless --path . -- --autojoin --name=Headless --class=2 --reclaim=2   # --reclaim = ask that seat back (a reload)
godot --headless --path . -- --autojoin --name=Bot --ai=sniper --ai-seed=7 --ai-difficulty=0.7 --latency-ms=120
```
Personas: `wanderer`, `chaser`, `sniper`, `turtle`, `rusher`, `griefer` (each picks its class).

Console lines (headless stdout = browser console):
- `📈 [NetStats]` every 5 s: bytes and packets in / out per type (since v0.0.36 `in:` lists `sync_bundle=` frames and `sync_pos=` entries), `puppets= jitter=<mean>/<p95>px/s snaps wraps stall extrap dips=`, then `fps draw=59.8 phys=60.0 worst=21ms hitches=0 proc=0.6ms phys_cpu=0.4ms` (pictures a second, physics ticks a second, slowest frame, frames over 50 ms, then the slowest `_process` frame and `_physics_process` tick of each second in ms, 5 s mean; skip the first line after a scene load), then `| keys=N focus=1` (key presses since the last line; `focus=0` = the canvas lost the page focus, the keyboard does not reach the game).
- `🏹 [Quiver] rejoin slot=2 round=2 saved_round=2 arrows=0->1 charges=3 kunai=4 bear=0 tick=612` once per rejoin (save = `localStorage` key `towerbrawl_combat` in a browser, `user://towerbrawl_combat.sav` headless).
- `🧗 [TopEdge]` one a second while a local fighter above `y = -20` touches something (backlog 9, should be silent). `🧭 [Spawn]` per round, `🪤 [JumpTrap]` on an ignored floor jump, `🧠 [Bot ...]` every 5 s for a brain (`shift=` = wraps during a turn), `📼 [Tape]` / `📼 [Replay]` (see [[tape]] and [[replay]]).

## Phone console over USB (Arch + Chromium + ADB)
```bash
adb devices          # phone must say "device"; first time tap Allow on the phone. "no permissions": pacman -S android-udev, replug, adb kill-server
```
Then Chromium `chrome://inspect/#devices`, tick Discover USB devices, open the play URL in Chrome on the phone, click inspect under the tab, Console, filter `NetStats`. Steps: [[Playtest — Master Validation Suite]] section 1.

## The deck and the logs
```bash
tbdash                                            # = ./venv/bin/python tools/watch_server.py; --plain --once --no-mouse --zoom 5
grep "\[GATE\]\|\[TAPE\]\|\[NET\]" server.log | tail   # tags: JOIN LEAVE CONN NAME LOCK MATCH ROUND KILL NET STATS GATE TAPE
```
`server.log` never rotates: filter by the last "Game version" line. `[STATS 10s]` ends with `bundles=20.0/s x2.9`. Packet dumps go to `debug.log` only. Deck keys: [[deck]].

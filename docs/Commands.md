---
tags: [handoff, commands]
---
# Commands (the hot list; deep dives in `reference/`)

## Editor and server
```bash
godot --editor project.godot &                    # open the project in the Godot editor
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
`GAME_VERSION` lives in `scripts/global.gd` only; the script mirrors it into `serve_game.py`, the server re-reads it on every join. A client-only build needs no server restart.

## The harness (`tools/chaos_bots.py`)
```bash
./venv/bin/python tools/chaos_bots.py --list                   # the 23 scenarios
./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json   # the full gate, one report per build
setsid nohup ./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json > <scratch>/harness.log 2>&1 &
grep -c "scenarios passed" <scratch>/harness.log               # wait for "23/23 scenarios passed"
./venv/bin/python tools/chaos_bots.py --scenario smoke --trace /tmp/trace.jsonl   # one scenario, packet capture
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 4 --ai chaser,sniper,turtle,rusher --duration 90 --latency-ms 120 --jitter-ms 40   # standard fleet gate
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 4 --ai chaser,sniper,turtle,rusher --duration 90 --latency-ms 120 --jitter-ms 150  # heavy gate
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 2 --ai chaser,sniper --loss 0.2   # 2 brains + 2 protocol bots, gaps
./venv/bin/python tools/chaos_bots.py --scenario play --latency-ms 120 --jitter-ms 40 --loss 0.05   # fault knobs
./venv/bin/python tools/chaos_bots.py --soak 30                # loop the suite, watch RSS / threads / fds
```
Other scenarios: `fuzz`, `slow_reader`, `stop_pinging`, `lag`, `tape` (~24 s), `replay` (~30 s), `reload_in_gap` (~50 s), `ranger_rejoin` (~40 s). Knobs: `--seed`, `--die-rate`, `--ai-difficulty 0.3`, `--no-state`. Levels: `PASS`, `FAIL`, `MINOR` (passed, but the server logged an `ERROR` or a client a `WARNING:`). Finding names are stable (`dup.event`, `oracle.stock-mismatch`, `timeout.round-end`, ...). Client logs: `.harness_logs/godot<N>.log`.

## Headless Godot as a real client
```bash
godot --headless --path . -- --autojoin --name=Headless --class=2
godot --headless --path . -- --autojoin --name=Headless --reclaim=2          # ask for seat 2 back at once (a page reload)
godot --headless --path . -- --autojoin --name=Bot --ai=sniper --ai-seed=7 --ai-difficulty=0.7 --latency-ms=120
```
Personas: `wanderer`, `chaser`, `sniper`, `turtle`, `rusher`, `griefer` (each picks its class unless `--class` is given).

Console lines (headless stdout = browser console):
- `📈 [NetStats]` every 5 s: bytes and packets in / out per type, `puppets= jitter=<mean>/<p95>px/s snaps wraps stall extrap dips=`, then `fps draw=59.8 phys=60.0 worst=21ms hitches=0` (pictures a second, physics ticks a second, slowest frame, frames over 50 ms), then `| keys=N focus=1` (key presses since the last line; `focus=0` = the canvas lost the page focus, the keyboard does not reach the game).
- `🏹 [Quiver] rejoin slot=2 round=2 saved_round=2 arrows=0->1 charges=3 kunai=4 bear=0 tick=612` once per rejoin (save = `localStorage` key `towerbrawl_combat` in a browser, `user://towerbrawl_combat.sav` headless).
- `🧭 [Spawn]` per round, `🪤 [JumpTrap]` on an ignored floor jump, `🧠 [Bot ...]` every 5 s for a brain, `📼 [Tape]` / `📼 [Replay]` (see [[tape]] and [[replay]]).

## The deck and the logs
```bash
tbdash                                            # = ./venv/bin/python tools/watch_server.py; --plain --once --no-mouse --zoom 5
grep "\[GATE\]\|\[TAPE\]\|\[NET\]" server.log | tail   # tags: JOIN LEAVE CONN NAME LOCK MATCH ROUND KILL NET STATS GATE TAPE
python3 -c "import json; print(json.load(open('status.json'))['harness'])"   # the harness gate as the server sees it
```
`server.log` is never rotated: filter by the last "Game version" banner line. Packet dumps go to `debug.log` only. Deck keys and panels: [[deck]].

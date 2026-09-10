---
tags: [handoff, commands]
---
# Commands (the hot list; deep dives: `reference/`)

## Editor and server
```bash
godot --editor project.godot &                    # open the Godot editor
./venv/bin/python serve_game.py                   # the backend + file server, by hand
systemctl --user restart towerbrawl               # the service; needed after any serve_game.py change
```
Play: `https://192.168.4.21:8443/play` (http is not a secure context).

## The laptop server (family nights, [[laptop-server]])
```bash
tools/deploy_laptop.sh <laptop ip>                # push build + source, restart there (TB_SUDO_PASS=... skips the prompt)
tools/pull_laptop_logs.sh <laptop ip>             # pull client_stats.jsonl + server.log into playtest_logs/<date>_<ip>/
ssh nemr@<laptop ip>                              # find it: ip neigh | grep -i 08:60:6e. On it: tbdash, tbbot add [persona], tbbot clear, tblog
```

## Build, bump and cache-bust (every GDScript change)
```bash
./bump_build.sh --title "Short Title"   # check, bump v0.0.x, export, version the pck, patch page
./bump_build.sh minor --title "Release" # the next minor (v0.1.x -> v0.2.0); the runbook: [[release-v0.1.0]]
./bump_build.sh none                    # re-export the current version, no cache bust
godot --headless --path . --script tools/check_scripts.gd -- --no-net   # the check: scripts compile, scenes load (run after a .tscn edit)
```
`GAME_VERSION`: `scripts/global.gd`, mirrored into `serve_game.py`.

## The harness (`tools/chaos_bots.py`)
```bash
./venv/bin/python tools/chaos_bots.py --list                   # the 25 scenarios
setsid nohup ./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json > <scratch>/harness.log 2>&1 &   # the full gate, detached; wait for "25/25 scenarios passed"
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 4 --ai chaser,sniper,turtle,rusher --duration 90   # the fleet gate; --latency-ms 120
```
Knobs: `--seed`, `--die-rate`, `--ai-difficulty 0.3`, `--no-state`. `MINOR` = passed with a server `ERROR` or a client `WARNING:`. Logs: `.harness_logs/godot<N>.log`.

The tower: `scripts/arena_layouts.gd`, the numbers in [[arena-tower]]; the shift is off (`ARENA_SHIFT_ENABLED`).

## Headless Godot as a real client
```bash
godot --headless --path . -- --autojoin --name=Bot --ai=sniper --ai-seed=7 --reclaim=2   # or: tbbot add sniper; --reclaim = that seat back
tools/webbot.sh --ai chaser --minutes 5   # a real WEB client (Chromium headless, a brain); console -> .bots/web<N>.log
```
Personas: `wanderer`, `chaser`, `sniper`, `turtle`, `rusher`, `griefer`.
```bash
./venv/bin/python tools/webshot.py --seq sticks --layout twin --out /tmp/shot   # web screenshots over CDP (idle|sticks|moves|duck|keys)
godot --headless --path . --script tools/duck_probe.gd -- --no-net   # the duck must hold 40 frames on a floor
godot --headless --path . --fixed-fps 60 --script tools/nav_probe.gd -- --no-net   # bot routes: N/N trips; --only=N; --drop-test
./venv/bin/python tools/soak_report.py --dir playtest_logs/<f> --from 23:08   # a bot soak; STALL = a round over 300 s
```

Console lines (headless stdout = the browser console):
- `📈 [NetStats]` every 5 s: packets and bytes per type, `puppets= jitter=<mean>/<p95>px/s snaps wraps stall extrap dips=`, `fps draw= phys= worst= hitches= proc= phys_cpu=`, `| keys=N focus=1` (`focus=0`: the canvas lost focus); = the `client_stats` card.
- `🎮 [Layout] twin saved=true` once per scene load (the phone layout).
- `🏹 [Quiver] rejoin slot= round= arrows= charges= kunai= bear=` once per rejoin (`localStorage` `towerbrawl_combat`).
- `🔤 [FontWarm] pairs= ms=` per scene load. `🩹 [SelfRespawn] slot= round= waited_ms=` when my death got no echo for 1 s. `📼 [Replay] start_ms= tick_ms= first_ms=` the replay's start cost.
- `🧭 [BotNav] P hunt on` (no kill for 20 s) / `stuck 4 s on <ledge> ... detour` (v0.1.5). `🏃 [Speed]` sideways over 300 px/s outside a dash (backlog 25). `🧭 [Spawn]` per round, `🪤 [JumpTrap]` on an ignored floor jump, `🧠 [Bot ...]` every 5 s, `📼 [Tape]` / `📼 [Replay]` ([[tape]]).

## The deck, the cards and the logs
```bash
tbdash                                            # = tools/watch_server.py (a: bot menu, i: info); --no-controls --plain --once
./venv/bin/python tools/stats_table.py --list     # the matches in client_stats.jsonl
./venv/bin/python tools/stats_table.py --match 3  # one row per device; --by-round --devices
./venv/bin/python tools/stats_table.py --summary --last 3        # seats, classes, kills, K/D, weapons, devices; --events
./venv/bin/python tools/stats_table.py --from 20:41 --to 20:52   # a clock window; --file playtest_logs/<f>/client_stats.jsonl
grep "\[GATE\]\|\[TAPE\]\|\[NET\]" server.log | tail   # tags: JOIN LEAVE CONN NAME LOCK MATCH ROUND KILL NET STATS GATE TAPE
```
`server.log` never rotates on the PC (the laptop's does). `client_stats.jsonl` rotates at 10 MB. Keys: [[deck]].

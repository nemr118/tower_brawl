---
tags: [handoff, commands]
---
# Commands (the hot list; deep dives in `reference/`)

## Editor and server
```bash
godot --editor project.godot &                    # open the Godot editor
./venv/bin/python serve_game.py                   # the WebSocket backend + HTTP file server, by hand
systemctl --user restart towerbrawl               # the service; needed after any serve_game.py change
```
Play: `https://192.168.4.21:8443/play` (redirects to the current build; PC on plain http is not a secure context).

## The laptop server (family nights, [[laptop-server]])
```bash
tools/deploy_laptop.sh <laptop ip>                # push the build + source, restart the game there (TB_SUDO_PASS=... skips the password prompt)
tools/pull_laptop_logs.sh <laptop ip>             # pull the night's client_stats.jsonl + server.log into playtest_logs/<date>_<ip>/
ssh nemr@<laptop ip>                              # find it: ip neigh | grep -i 08:60:6e. On it: tbdash, tbbot add [persona], tbbot clear, tblog
```

## Build, bump and cache-bust (every GDScript change)
```bash
./bump_build.sh --title "Short Title"   # compile-check with autoloads live, bump v0.0.x, export, version the pck, make the patch page
./bump_build.sh minor --title "Release" # the next minor (v0.1.x -> v0.2.0); the runbook: [[release-v0.1.0]]
./bump_build.sh none                    # re-export the current version (no cache bust)
./bump_build.sh --clean                 # also delete older index_v*.pck
godot --headless --path . --script tools/check_scripts.gd -- --no-net   # the compile check
```
`GAME_VERSION` lives in `scripts/global.gd`; the script mirrors it into `serve_game.py`, which re-reads it on every join.

## The harness (`tools/chaos_bots.py`)
```bash
./venv/bin/python tools/chaos_bots.py --list                   # the 24 scenarios (fuzz, lag, bundle, tape, replay, fleet ...)
setsid nohup ./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json > <scratch>/harness.log 2>&1 &   # the full gate, detached; wait for "24/24 scenarios passed"
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 4 --ai chaser,sniper,turtle,rusher --duration 90 --latency-ms 120 --jitter-ms 40   # the fleet gate; 150 = heavy; --loss 0.05
```
Knobs: `--seed`, `--die-rate`, `--ai-difficulty 0.3`, `--no-state`. Levels: `PASS`, `FAIL`, `MINOR` (passed, but the server logged an `ERROR` or a client a `WARNING:`). Client logs: `.harness_logs/godot<N>.log`.

## Headless Godot as a real client
```bash
godot --headless --path . -- --autojoin --name=Headless --class=2 --reclaim=2   # --reclaim = that seat back (a reload)
godot --headless --path . -- --autojoin --name=Bot --ai=sniper --ai-seed=7 --ai-difficulty=0.7 --latency-ms=120   # or: tools/tbbot.py add sniper
```
Personas: `wanderer`, `chaser`, `sniper`, `turtle`, `rusher`, `griefer`.

Console lines (headless stdout = the browser console):
- `📈 [NetStats]` every 5 s: packets and bytes in / out per type, `puppets= jitter=<mean>/<p95>px/s snaps wraps stall extrap dips=`, `fps draw=59.8 phys=60.0 worst=21ms hitches=0 proc=0.6ms phys_cpu=0.4ms` (frames a second, physics ticks, slowest frame, frames over 50 ms, slowest script frame and tick; skip the first line after a scene load), `| keys=N focus=1` (`focus=0` = the canvas lost the page focus). The same numbers go to the server as the `client_stats` card.
- `🏹 [Quiver] rejoin slot=2 round=2 saved_round=2 arrows=0->1 charges=3 kunai=4 bear=0 tick=612` once per rejoin (save = `localStorage` key `towerbrawl_combat`; headless `user://towerbrawl_combat.sav`).
- `🧗 [TopEdge]` while a local fighter above `y = -20` touches something (backlog 9). `🧭 [Spawn]` per round, `🪤 [JumpTrap]` on an ignored floor jump, `🧠 [Bot ...]` every 5 s for a brain, `📼 [Tape]` / `📼 [Replay]` ([[tape]], [[replay]]).

## The deck, the client cards and the logs
```bash
tbdash                                            # = ./venv/bin/python tools/watch_server.py; SERVER panel on by default (a bot menu, i info); --no-controls --plain --once
./venv/bin/python tools/stats_table.py --list     # the matches in client_stats.jsonl (every client's NetStats card, every 5 s)
./venv/bin/python tools/stats_table.py --match 3  # one row per device (fps, proc, rtt, pkt/s, jitter, keys, focus); --by-round --devices
./venv/bin/python tools/stats_table.py --summary --last 3        # seats, classes, kills, K/D, weapons, devices per match; --events lists every marker
./venv/bin/python tools/stats_table.py --from 20:41 --to 20:52   # a clock window; --file playtest_logs/<f>/client_stats.jsonl reads a pulled night
grep "\[GATE\]\|\[TAPE\]\|\[NET\]" server.log | tail   # tags: JOIN LEAVE CONN NAME LOCK MATCH ROUND KILL NET STATS GATE TAPE
```
`server.log` never rotates: filter by the last "Game version" line. `client_stats.jsonl` (cards + join / lock / kill / leave / match records) rotates at 10 MB. Deck keys: [[deck]].

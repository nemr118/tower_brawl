---
tags: [handoff, commands]
---
# Commands (the hot list; deep dives: `reference/`)

## The new game (`bench/`, [[first-playable-plan]])
```bash
godot --headless --path bench res://server/game_server.tscn -- --bots 7  # the game server, wss 8091; --arena mix|keep|bridges|bench, --bot-level easy|normal|hard, --soak, --no-tls, --goal N, --walls-s N, --port, --out, --spots 2,3, --admin-port 8092
godot --path bench -- --server=wss://192.168.4.21:8091 --name=Dad  # the game in a window
tools/v2_build.sh --title "Short Title"   # check, bump v0.2.0-pP.N, export build/web/v2/, patch page; --phase 5 = p5.1; `none` re-exports
godot --headless --path bench --script res://tools/check_scripts.gd  # the check: scripts, scenes
godot --headless --path bench --script res://tools/input_probe.gd  # 31 sim rules, offline
godot --headless --path bench --script res://tools/arena_probe.gd -- --png=/tmp/maps --rounds=200   # the arena rules, routes, bot rounds; --layout=N --quick --list; --write-routes after a map change
godot --headless --path bench --script res://tools/bot_probe.gd -- --rounds=200 --level=easy,normal,hard   # the bots; --catch, --reach, --kid, --deaths=<jsonl> --png=DIR
godot --headless --path bench --script res://tools/play_probe.gd -- --server=ws://127.0.0.1:8091 --name=Me --start --bots=7 --move --watch=300   # a headless person; --lag=60 --jitter=30, --predict, --arena=N, --bot-level=N, --shooter/--catcher
./venv/bin/python tools/v2_synth.py --url ws://127.0.0.1:8091 --n 7 --seconds 300 --start --bots 0  # 7 fake players
./venv/bin/python tools/v2_shot.py --out /tmp/v2shot [--phone [--ios]] [--watch 20] [--look-tap] [--extra "look=t1"]  # Chromium pictures
./venv/bin/python tools/v2_soak_report.py --file bench_results/<date>/v2_server.jsonl --map   # a soak's checks
./venv/bin/python tools/v2_host_check.py   # the host port's checks
./venv/bin/python tools/v2_pull_check.py   # a phone's pull-back shot (its header)
tools/deploy_rog.sh   # the ROG travel server; its panel: tools/v2_dash.py
```
Play: `https://192.168.4.21:8443/v2/` (`?name=Ava&join`, `?info`, `?arena=1`, `?bench` = the old benchmark page; test knobs `look=t3`, `lag=60&jitter=30`, `slow=25`). Host page: `<PC>:8088/data/perspective/client/TowerBrawlServer` (`tower_brawl_ignition/deploy_host.sh`). Lines: `[NET] [JOIN] [LEAVE] [LOBBY] [ROUND] [KILL] [MATCH] [HOST]`, `📊 [Server Ns]` every 5 s (`late seat:inputs/late`), `🎮 [Look]` on the page; `bench_results/<date>/v2_server.jsonl` (round lines). The laptop: `tools/towerbrawl-v2.service`.

## The old game: editor and server
```bash
./venv/bin/python serve_game.py   # the relay + file server, by hand
systemctl --user restart towerbrawl   # the service; after any serve_game.py change
```
Play: `https://192.168.4.21:8443/play` (http is not a secure context).

## The laptop server (family nights, [[laptop-server]])
```bash
tools/deploy_laptop.sh <laptop ip>   # push both games, restart both services (TB_SUDO_PASS=... skips the prompt)
tools/pull_laptop_logs.sh <laptop ip>   # client_stats.jsonl + server.log -> playtest_logs/<date>_<ip>/
ssh nemr@<laptop ip>   # find it: ip neigh | grep -i 08:60:6e. On it: tbdash, tbbot add [persona], tbbot clear, tblog
```

## Build and bump (the old game, every GDScript change)
```bash
./bump_build.sh --title "Short Title"   # check, bump v0.0.x, export, version the pck, patch page; `minor` = the next minor ([[release-v0.1.0]]); `none` re-exports
godot --headless --path . --script tools/check_scripts.gd -- --no-net   # the check: scripts compile, scenes load
```

## The harness (`tools/chaos_bots.py`, the old game)
```bash
./venv/bin/python tools/chaos_bots.py --list   # the 25 scenarios
setsid nohup ./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json > <scratch>/harness.log 2>&1 &   # the full gate; wait for 25/25
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 4 --duration 90   # the fleet gate; --latency-ms 120
```
Knobs: `--seed`, `--die-rate`, `--ai-difficulty 0.3`, `--no-state`; `MINOR` = a pass with `ERROR`/`WARNING:`; `.harness_logs/`.

## Headless clients (the old game)
```bash
godot --headless --path . -- --autojoin --name=Bot --ai=sniper   # or: tbbot add sniper
./venv/bin/python tools/soak_report.py --dir playtest_logs/<f> --from 23:08   # an old bot soak
```
Console lines: `📈 [NetStats]`, `🎮 [Layout]`, `🏹 [Quiver]`, `📼 [Replay]` ([[tape]]), `🧭 [BotNav]`, `🏃 [Speed]` (25), `🪤 [JumpTrap]` (20).

## The deck and the logs (the old game)
```bash
tbdash   # = tools/watch_server.py (a: bot menu, i: info); --no-controls --plain --once
./venv/bin/python tools/stats_table.py --list   # client_stats.jsonl's matches; --match 3, --by-round, --summary --last 3, --from/--to
grep "\[GATE\]\|\[TAPE\]\|\[NET\]" server.log | tail   # tags: JOIN LEAVE CONN NAME LOCK MATCH ROUND KILL NET STATS GATE TAPE
```
`server.log`, `debug.log`: `.1` at 50 MB; `client_stats.jsonl` at 10 MB. Keys: [[deck]].

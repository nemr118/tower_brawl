---
tags: [handoff, commands]
---
# Commands (the hot list; deep dives: `reference/`)

## The new game (`bench/`, [[first-playable-plan]])
```bash
godot --headless --path bench res://server/game_server.tscn -- --bots 7   # the game server, wss 8091; --no-tls, --power-arrows, --goal N, --walls-s N (0 none), --port, --out, --spots 2,3 (test)
godot --path bench -- --server=wss://192.168.4.21:8091 --name=Dad  # the game in a window (keyboard + mouse)
tools/v2_build.sh --title "Short Title"   # check, bump v0.2.0-pP.N (sim/proto.gd), export build/web/v2/, stamp the pck, patch page; --phase 3 = p3.1; `none` = re-export
godot --headless --path bench --script res://tools/check_scripts.gd  # the check (scripts + scenes)
godot --headless --path bench --script res://tools/input_probe.gd  # 29 sim rules, offline
godot --headless --path bench --script res://tools/play_probe.gd -- --server=ws://127.0.0.1:8091 --name=Me --start --bots=7 --move --watch=300   # a headless person; --lag=60 --jitter=30, --predict (corrections), --shooter / --catcher[=old] (server --spots 2,3 --bots 0)
./venv/bin/python tools/v2_synth.py --url ws://127.0.0.1:8091 --n 7 --seconds 300 --start --bots 0   # 7 fake players
./venv/bin/python tools/v2_shot.py --out /tmp/v2shot [--phone [--ios]] [--watch 20] [--look-tap] [--extra "slow=25"]  # Chromium pictures
```
Play: `https://192.168.4.21:8443/v2/` (`?name=Ava&join`, `?info`, `?bench` = the old benchmark page; test knobs `look=t3`, `lag=60&jitter=30`, `slow=25`). The LOOK button: LOW/NORMAL/HIGH. Lines: `[NET] [JOIN] [LEAVE] [LOBBY] [ROUND] [KILL] [MATCH]`, `📊 [Server Ns]` every 5 s (`late seat:inputs/late`), `🎮 [Look]` on the page; `bench_results/<date>/v2_server.jsonl`. The laptop: `tools/towerbrawl-v2.service`.

## The old game: editor and server
```bash
./venv/bin/python serve_game.py   # the backend + file server, by hand
systemctl --user restart towerbrawl   # the service; after any serve_game.py change
```
Play: `https://192.168.4.21:8443/play` (http is not a secure context).

## The laptop server (family nights, [[laptop-server]])
```bash
tools/deploy_laptop.sh <laptop ip>   # push both games, restart both services (TB_SUDO_PASS=... skips the prompt)
tools/pull_laptop_logs.sh <laptop ip>   # client_stats.jsonl + server.log into playtest_logs/<date>_<ip>/
ssh nemr@<laptop ip>   # find it: ip neigh | grep -i 08:60:6e. On it: tbdash, tbbot add [persona], tbbot clear, tblog
```

## Build, bump and cache-bust (the old game, every GDScript change)
```bash
./bump_build.sh --title "Short Title"   # check, bump v0.0.x, export, version the pck, patch page; `minor` = the next minor ([[release-v0.1.0]]); `none` = re-export
godot --headless --path . --script tools/check_scripts.gd -- --no-net   # the check: scripts compile, scenes load (run after a .tscn edit)
```

## The harness (`tools/chaos_bots.py`, the old game)
```bash
./venv/bin/python tools/chaos_bots.py --list   # the 25 scenarios
setsid nohup ./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json > <scratch>/harness.log 2>&1 &   # the full gate, detached; wait for "25/25 scenarios passed"
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 4 --ai chaser,sniper,turtle,rusher --duration 90   # the fleet gate; --latency-ms 120
```
Knobs: `--seed`, `--die-rate`, `--ai-difficulty 0.3`, `--no-state`. `MINOR` = passed with a server `ERROR` or a client `WARNING:`. Logs: `.harness_logs/godot<N>.log`. The tower: [[arena-tower]].

## Headless Godot as a real client (the old game)
```bash
godot --headless --path . -- --autojoin --name=Bot --ai=sniper --ai-seed=7 --reclaim=2   # or: tbbot add sniper. Personas: wanderer chaser sniper turtle rusher griefer
tools/webbot.sh --ai chaser --minutes 5   # a real WEB client (Chromium headless, a brain); console -> .bots/web<N>.log
godot --headless --path . --script tools/duck_probe.gd -- --no-net   # the duck; nav_probe.gd (--fixed-fps 60; --drop-test), join_full_probe.gd (--live)
./venv/bin/python tools/soak_report.py --dir playtest_logs/<f> --from 23:08   # a bot soak; STALL = a round over 300 s
```
Console lines: `📈 [NetStats]` (= the `client_stats` card), `🎮 [Layout]`, `🏹 [Quiver]`, `📼 [Replay]` ([[tape]]), `🧭 [BotNav]`, `🏃 [Speed]` (25), `🪤 [JumpTrap]` (20); `tools/webshot.py` takes the old page's pictures.

## The deck, the cards and the logs (the old game)
```bash
tbdash   # = tools/watch_server.py (a: bot menu, i: info); --no-controls --plain --once
./venv/bin/python tools/stats_table.py --list   # the matches in client_stats.jsonl; --match 3, --by-round, --devices, --summary --last 3, --events, --from HH:MM --to HH:MM, --file <jsonl>
grep "\[GATE\]\|\[TAPE\]\|\[NET\]" server.log | tail   # tags: JOIN LEAVE CONN NAME LOCK MATCH ROUND KILL NET STATS GATE TAPE
```
`server.log`, `debug.log`: `.1` at 50 MB; `client_stats.jsonl` at 10 MB. Keys: [[deck]].

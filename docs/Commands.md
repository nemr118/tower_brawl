---
tags: [handoff, commands]
---
# Commands (the hot list; deep dives: `reference/`)

## The new game (`bench/`, [[first-playable-plan]])
```bash
godot --headless --path bench res://server/game_server.tscn -- --bots 7  # wss 8091; --arena mix|keep|bridges|3, --bot-level easy|normal|hard, --soak, --no-tls, --goal N, --walls-s N, --port, --out, --spots 2,3, --admin-port 8092, --no-powerups, --season auto|off|halloween|harvest, --mode ffa|teams, --silly-every N; test knobs --silly N, --pu-gallery, --hw-gallery, --boiler-demo, --pet-always, --start-power N
godot --path bench -- --server=wss://192.168.4.21:8091
tools/v2_build.sh --title "Short Title"   # check, bump, export, patch page; --phase 5 = p5.1; `none` re-exports
godot --headless --path bench --script res://tools/check_scripts.gd
godot --headless --path bench --script res://tools/input_probe.gd  # the rules; also review_probe.gd, teams_probe.gd, motion_probe.gd, harvest_probe.gd, sfx_probe.gd, pit_probe.gd, kit_probe.gd, power_probe.gd -- --matches=6 --arena=3, balance_probe.gd -- --rounds=300 (who wins; --old)
godot --headless --path bench --script res://tools/arena_probe.gd -- --png=/tmp/maps --rounds=200   # --layout=N --quick --list; --write-routes after a map change
godot --headless --path bench --script res://tools/bot_probe.gd -- --rounds=200 --level=easy,normal,hard   # --catch, --reach, --kid, --deaths=<f>
godot --headless --path bench --script res://tools/play_probe.gd -- --server=ws://127.0.0.1:8091 --name=Me --start --bots=7 --move --watch=300   # a person; --lag=60 --jitter=30, --predict, --warps --stall=150, --arena=N
./venv/bin/python tools/v2_synth.py --url ws://127.0.0.1:8091 --n 7 --start --bots 0  # 7 fakes; v2_chaos.py --spawn (a soak)
./venv/bin/python tools/v2_shot.py --out /tmp/v2shot [--phone [--ios]] [--extra "nocam"] [--burst 7] [--until "[Winner]@3,15"] [--no-join] [--host-start 8092]  # pictures (--help); v2_motion_clip.py --script lobby (a film of the menus)
./venv/bin/python tools/v2_soak_report.py --file <v2_server.jsonl> --map
./venv/bin/python tools/v2_host_check.py   # host port; v2_pull_check.py
tools/deploy_rog.sh
tools/pull_rog_logs.sh; ./venv/bin/python tools/v2_night_report.py --file <jsonl>
```
Play: `https://192.168.4.21:8443/v2/` (`?name=Ava&join`, `?info`, `?arena=1`, `?tv` THE BIG SCREEN, `?bench` the old benchmark; test knobs `look=t3`, `lag=60&jitter=30`, `slow=25`, `bolt_s=5`, `nocam`, `polish_off=a,b`, `stick=old`, `controls=buttons`, `res=1`, `cream`, `phew`, `taunt`, `nohowto`, `sound=1`, `music=1`, `menu`, `slowmo=4`, `sfxlog`). A sound: `python3 tools/make_sfx.py --only NAME`; a song's take: `python3 tools/comfy/make_music.py --pick match=2`. Host page: `<PC>:8088/data/perspective/client/TowerBrawlServer` (`tower_brawl_ignition/deploy_host.sh`). Lines: `[NET] [JOIN] [LEAVE] [LOBBY] [ROUND] [KILL] [MATCH] [HOST] [POWER]`, `📊 [Server Ns]` every 5 s (`late seat:inputs/late`), `🎮 [Look]` on the page; `bench_results/<date>/v2_server.jsonl`. The laptop: `tools/towerbrawl-v2.service`.

## The old game: editor and server
```bash
./venv/bin/python serve_game.py   # the relay + files, by hand
systemctl --user restart towerbrawl   # after any serve_game.py change
```
Play: `https://192.168.4.21:8443/play`.

## The laptop server (family nights, [[laptop-server]])
```bash
tools/deploy_laptop.sh <laptop ip>   # both games, both services (TB_SUDO_PASS=... skips the prompt)
tools/pull_laptop_logs.sh <laptop ip>   # -> playtest_logs/<date>_<ip>/
ssh nemr@<laptop ip>   # find it: ip neigh | grep -i 08:60:6e. On it: tbdash, tbbot add, tbbot clear, tblog
```

## Build and bump (the old game, every GDScript change)
```bash
./bump_build.sh --title "Short Title"   # check, bump v0.0.x, export, patch page; `minor` ([[release-v0.1.0]]); `none`
godot --headless --path . --script tools/check_scripts.gd -- --no-net   # the check
```

## The harness (`tools/chaos_bots.py`, the old game)
```bash
./venv/bin/python tools/chaos_bots.py --list
setsid nohup ./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_<ver>.json > <scratch>/harness.log 2>&1 &   # the gate: 25/25
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 4 --duration 90   # --latency-ms 120
```
Knobs: `--seed`, `--die-rate`, `--ai-difficulty 0.3`; `.harness_logs/`.

## Headless clients (the old game)
```bash
godot --headless --path . -- --autojoin --ai=sniper
./venv/bin/python tools/soak_report.py --dir playtest_logs/<f>   # a soak
```
Console lines: `📈 [NetStats]`, `🎮 [Layout]`, `🏹 [Quiver]`, `📼 [Replay]` ([[tape]]), `🧭 [BotNav]`, `🏃 [Speed]`, `🪤 [JumpTrap]`.

## The deck and logs (old game)
```bash
tbdash   # tools/watch_server.py; --plain --once
./venv/bin/python tools/stats_table.py --list   # --match 3, --by-round, --summary --last 3
grep "\[GATE\]\|\[TAPE\]\|\[NET\]" server.log | tail   # tags: JOIN LEAVE MATCH ROUND KILL
```
`server.log`, `debug.log`: `.1` at 50 MB. [[deck]].

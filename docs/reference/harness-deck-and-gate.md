---
tags: [reference]
---
# The harness on the deck, and the harness gate

Built in v0.0.22 (state file, MINOR level, bot cards) and v0.0.23 (the gate). Read this page when working on `tools/chaos_bots.py` reporting, `bot_status` cards or the join lock. Commands: [[Commands]].

## The state file
While `tools/chaos_bots.py` runs it writes `harness_state.json` in the repo root (gitignored): the run state, the suite checklist, the running scenario with its step, findings and warnings, and the bot cards of the Godot clients in a fleet run. A heartbeat thread (`StatePublisher`) refreshes it once a second. `--no-state` turns it off.

## Result levels
`PASS`, `FAIL`, and `MINOR`: the scenario passed but something complained (`ctx.warn(name, detail)` in the harness). The two warnings today are `server.error-logged` (the server wrote an `ERROR` line or a traceback during the scenario) and `fleet.script-warning` (a Godot client printed a `WARNING:` line). The report table has a `warn` column and a `WARNINGS` block; the JSON report carries `warnings` and `minor` per scenario.

## Bot cards
Bots tell the server who they are: `"bot": "<persona>"` in `request_join` (`"protocol"` for a harness bot, `"headless"` for a plain headless client), and a brain sends a `bot_status` card every 5 s. The server keeps the last card per seat in `status.json` (`seats[].bot`) and never relays it. The card shape is the same in `status.json` and in `harness_state.json` (`bots[]`):
```json
{"schema": 1, "kind": "brain", "seat": 2, "persona": "sniper", "seed": 421, "difficulty": 0.7, "uptime_s": 45,
 "state": null, "target": null, "goal": [320, 200],
 "actions": {"decisions": 412, "moves": 300, "jumps": 40, "dashes": 12, "attacks": 38, "specials": 6, "evades": 7},
 "nav": {"wraps": 3, "drops": 1, "seams": 2, "land_avg_s": 0.42, "max_loop": 1},
 "aim": {"err_mean_deg": 0.0, "err_max_deg": 0.1, "frames": 900},
 "combat": {"kills": null, "deaths": null, "shots": null, "hits": null, "accuracy": null, "air_time_pct": null, "damage_dealt": null},
 "learning": {"episode": null, "reward": null, "weights": {}, "deltas": {}}}
```
`state`, `target`, `combat` and `learning` are empty slots for future bot brains (a state like `seeking`, `retreating`, `camping`; the seat it hunts; accuracy and air time; learning weights and their deltas). The deck draws them as soon as a brain fills them.

## The harness gate
The server reads the same `harness_state.json` once a second (`_harness_tick` in `status_loop`, also at startup). While `state` is `running` or `restarting`, `written_at` is under 5 s old and the harness `pid` is alive, every seat is for bots only. A person who presses JOIN gets a `join_locked` packet and stays a spectator; a person already seated is moved back to spectator through `_release_seat` and gets `join_locked` with `demoted: true` (`[LEAVE] P1 was moved to spectator by the harness gate` in `server.log`, `[GATE]` lines when the gate closes and opens). Bots pass because they say `"bot"` in `request_join`.

The server-only packet `harness_status` (`active, state, scenario, done, total, passed, failed, minor`) is sent on change and to new sockets while locked; `status.json` has the same dict under `harness`. The screen shows a small amber ticker (`scripts/harness_ticker.gd`, listens to `Global.net_harness_status`): `TESTS RUNNING - JOIN IS LOCKED / Scenario: reclaim / Tests done: 5 / 19` in the JOIN MATCH spot of the lobby, or one line under the arena top bar; JOIN MATCH, LOCK IN and JOIN NEXT MATCH hide while locked. The deck header says `SEATS LOCKED (harness)`. `--no-state` turns the file off, so it also leaves the gate open.
```bash
python3 -c "import json; print(json.load(open('status.json'))['harness'])"   # {'active': True, 'state': 'running', 'scenario': 'smoke', 'done': 0, 'total': 23, ...}
grep "\[GATE\]" server.log | tail                                           # when the gate closed and opened
```

## The gates inside the fleet scenarios
`fleet --ai ...` parses every brain's `🧠 [Bot` line (`fleet.bot-idle`, `fleet.bot-fall-loop`, `fleet.bot-missing`, `fleet.no-kills`, `fleet.no-round-end` at 150 s+) and the `puppets=` field (`puppet_gate` → `fleet.puppet-jitter`: mean ≤ 45 px/s at `--jitter-ms` ≤ 60, ≤ 100 above; `fleet.puppet-snaps`: teleports ≤ deaths seen + 5, seam wraps excluded; also on the `lag` scenario's Godot observer). `tape_gate` → `fleet.tape-missing` / `fleet.tape-fps`; `replay_gate` → `fleet.replay-missing / -skipped / -late / -frames-dropped / -duration`. The harness fails on any `dips=` count (v0.0.17) and on any duplicate broadcast, except the ranger brain's same-frame double shot where `Bot.double_shot_ok` is set (v0.0.30).

Related: [[deck]], [[tape]], [[replay]].

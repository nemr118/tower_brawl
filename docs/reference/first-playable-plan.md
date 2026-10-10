---
tags: [reference, plan]
status: built 2026-10-10 as v0.2.0-p1.1 ([[v0.2.0-p1.1 - First Playable]]); on the laptop since 2026-10-10 (tick 0.36 ms mean with 8 sockets); the play night waits
---
# The first playable (P1): the new game the kids can play

**Built 2026-10-10** as [[v0.2.0-p1.1 - First Playable]]: section 3 steps 1 to 8 are done on the PC (the page has the proofs); the laptop tick proof (3.7) passed after the deploy on 2026-10-10: 0.36 ms mean, 3.18 ms max with 8 sockets (the mark: under 4 ms). The sheet: [[Playtest v0.2.0-p1.1]].

**The decision (the user, 2026-10-10):** "I'd really like to get this game off the ground and playable with my kids. They aren't really interested in the benchmarking. The game looks great from the benchmark on my phone. Can we just proceed and tweak optimizations as we go? The graphics tweaks are a great lever to pull, but we don't even know exactly how the game is played. If we see performance issues in the future, we can revisit tweaking lighting or having settings so devices that struggle can tone down areas that impact their performance." So the benchmark stops here (the verdict: [[bench-8p-results]]) and we build. The entry: [[Design Decisions v0.2]] D18. The long plan it shortens: [[v0.2-transformation-plan]].

## 1. What the kids get
On their phones and the PC keyboard: 2 to 8 players, with bots in the empty seats. Each one is an archer in their own colour, in the bench arena, with the T2 look (torch lights, particles, one fog layer). Run, jump, wall jump, ledge grab, dodge (a dodge catches an arrow), shoot, pick arrows up, stomp. One life a round; the last one standing scores; first to the goal wins the match and the crown; then back to the lobby. It runs on the laptop beside the old game: `https://192.168.4.29:8443/v2`.

## 2. What we start from (the bench, on branch `beta`)
- `bench/sim/sim.gd` (850 lines): the simulation. TowerFall's numbers x4.5, every move, arrows that fly, stick and get picked up, the catch, the stomp, one-hit deaths, the bot brain. Plain objects, no scene nodes, so a client can run it too (prediction, later).
- `bench/server/bench_server.gd`: wss with our cert, 60 ticks a second, a snapshot every second tick, inputs read 60 times a second, a network thread, a line a second about its cost.
- `bench/client/`: draws the match at 60 fps with the look; the 28-frame archer sheet in 8 colours; interpolation 50 ms behind the server.
- `bench/sim/level.gd`: the 1920 x 1080 arena with wrap on all edges.
- `tools/bench_synth.py` (fake players), `bench_report.py`, `bench_export.sh`, `bench_shot.py`.
- From the brawler: `scripts/touch_controls.gd` (twin sticks) and the keyboard bindings.

**What is missing.** The server ignores the buttons a client sends (it counts them); the bot brain moves every fighter. No seats or names. No rounds, scores, winner or lobby. No HUD. No phone controls on the new client. No service on the laptop.

## 3. The build: one build, then a play night
1. **Buttons move a fighter.** `sim.gd` gets `apply_input(f, buttons, aim)`: left and right set `move_dir`; jump held or tapped (the sim has `want_jump` and `hold_jump`); down drops through a ledge; the dodge takes its 8 ways from the stick; shoot is hold to aim, let go to fire (TowerFall's way, D5 A, a placeholder until the kids judge it). The brain runs only in a seat without a person. The server keeps the last inputs per seat and uses the one for its tick; a late packet still carries the 3 before (the packet already has `u8 buttons, u16 aim` x4).
2. **Seats and the lobby.** `hello(name, version)` gets a seat, or spectator when 8 are taken. A lobby screen: your name, JOIN, the seat list, START (anyone, with 2 or more seated), a 3 s countdown. A wrong version is told so. A seat is held 8 s after a drop, as today.
3. **Rounds.** One life a round (D2 A, a placeholder). The round ends 1.5 s after one fighter is left, or at once with none (a draw). Points to win by player count: TowerFall's 5, 4, 3 for 2, 3, 4 players; 3 for 5 to 8. The crown. The match end holds 7 s, then the lobby. No miasma yet: a round where two fighters never meet ends as a draw at 60 s (backlog 28's rule).
4. **Arrows.** Everyone starts with 3 plain arrows and gets arrows back by picking them up (the sim does this). The power arrows (fire, bomb, poison, smoke) are off by default; `--power-arrows` turns the sim's mix on for everyone (the bots fire them today). Chests come later (G10).
5. **The client.** The bench world is the game view at the T2 look (`look=` stays as a test knob). A HUD for 8: name, arrows, points, the crown. Your own fighter is drawn from the newest snapshot, the others 50 ms behind, to cut the lag until prediction comes (P2). The lobby and the round screens. The brawler's twin sticks, ported: the left stick moves (up jumps, down drops), the right stick aims and fires when let go, a DODGE button. Keyboard: WASD, space, shift to dodge, the mouse aims, hold the button to aim and let go to fire.
6. **Build and serve.** `tools/v2_build.sh`: the check, the export to `build/web/v2/` with a stamped pck (the cache rule), the version string in `bench/sim/proto.gd`, a patch page. The Python server already serves `build/web`, so `/v2/index.html` just works. `tools/deploy_laptop.sh` also copies `bench/` and installs `towerbrawl-v2.service` (headless Godot, port 8091, the cert pair). The old game is untouched (D11 A).
7. **Proofs before the night.** A headless client joins, holds right for 60 ticks and jumps: its fighter moved and rose 153 px (±3). 7 fake players and 1 headless person: a round ends, a point counts, a match ends, the lobby comes back. Headless Chromium pictures: the lobby, a round, the HUD. The tick on the laptop with 8 seats: under 4 ms.
8. **The play night sheet** (one short sheet, the rule): the controls make sense to the kids · a shot goes where I aimed · a dodge I timed caught the arrow · the lag: playable, or not · rounds: too long, too short, or right · 8 on one screen: I find myself in a second. Verdict: keep building, or fix first.

The project stays in `bench/` for now (the tools and the docs point there). It moves to the root at v0.2.0, when the relay and the brawler go (G7).

## 4. After the first night
- **P2 "The feel":** prediction and reconciliation for your own fighter (the sim is already separate from the drawing), the client clock that stays ahead, the controls tuned from the sheet, and a quality setting: high = T3, normal = T2, low = T1 (the iPhone starts on low), with the automatic step-down before Android halves to 30.
- Then the plan's phases as written: the super arena (G5), server bots (G6), the release v0.2.0 (G7), the look (G8), sound (G9), treasure and how characters differ (G10).

## 5. What the benchmark gave the game (the rules we carry)
- Draw at 1920 x 1080 and scale up.
- Particles are the first cost: few emitters that each do more, pooled, with a budget per effect. Without them the S25 Ultra's frame work halved.
- Lights are cheap on the Androids up to T3's 10 to 18. The iPhone holds T1; it starts without effects.
- The server has room: 2.4 ms a tick on the laptop with 8, 0.3 ms on the PC.
- A quality setting, and a step-down before a phone halves to 30 fps.

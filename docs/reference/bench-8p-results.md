# 8-player benchmark: results

**Run B, 2026-09-11.** The plan and the tools: [[bench-8p-plan]]. The question: can the server and the phones carry an 8-person match with the look we want, or must we dial back?

**The setup.** The bench server ran on the PC (Core Ultra 9 285K) with 8 fighters, 7 fake players and 1 phone at a time, over wss on the home Wi-Fi. Each phone climbed the tiers by itself, 20 seconds a step, drawn at 1920 x 1080 and at its full screen size. Raw data: `bench_results/2026-09-11/` (gitignored). Tables: `./venv/bin/python tools/bench_report.py --date 2026-09-11`.

## The devices

| Name in the data | What it is (from the browser) | Drawn at "full screen" |
|---|---|---|
| S25 | Galaxy S25 Ultra, Adreno 830 | 2560 x 1440 |
| pixel | Pixel 10 family (Tensor G5, PowerVR DXT-48-1536) | 1920 x 1080 |
| iphone | an iPhone with a small screen (Safari says 320 x 693 points), iOS 26.5 | 1386 x 779 |
| ipad | a 13-inch iPad, iPadOS 26.5 | 2752 x 1548 |

## The tiers

| Tier | What it adds |
|---|---|
| T0 plain | sprites and tiles, no lights |
| T1 lights | normal-map lights (torches) |
| T2 effects | particles, flames, light shafts, 1 fog layer |
| T3 shaders | outline shader, post shader (grade, vignette), 2 fog layers |
| T4 live 3D | 16 live 3D archers |
| T5 stress | double everything: 16 fighters, 2x arrows and fire, about 30 lights |
| T6 max | 3 fog layers, rain, lightning, 16 spirit lights, bloom, heat and shock distortion |
| T7 limit | T6, then more each level |

## Frames a second, drawn at 1920 x 1080

"Held 60" means 58 fps or more, 99% of frames under 25 ms, and no hitches.

| Tier | S25 Ultra | Pixel 10 | iPhone | iPad (capped, see below) |
|---|---|---|---|---|
| T0 plain | **60** | **60** | **60** | 30 |
| T1 lights | **60** | **60** | **60** | 30 |
| T2 effects | **60** | 60 (p99 26.5 ms) | 44 | 30 |
| T3 shaders | **59** | 57 | 43 | 30 |
| T4 live 3D | **59** | 56 | 44 | 30 |
| T5 stress | 53 | 39 | 41 | 27 |
| T6 max | 44 | 39 | 36 | 25 |
| T7, level 1 | 50 | 35 | 30 | 19 |
| T3 with CPU particles | 60 (p99 33 ms) | 58 | 38 | 30 |

At full screen size, the S25 Ultra (2560 x 1440) held 60 through T3, then got 58 at T4, 36 at T5 and 29 at T6. The iPhone got the same numbers at full size as at 1080.

## What it means

1. **The server needs no dial-back.** At 8 fighters a tick took 0.34 ms on average (worst p99 3.8 ms, while phones joined) and 2.5% CPU, over 35 minutes. The stress run on the PC (32 fighters, 31 clients) took 1.16 ms. The laptop is slower per core, perhaps 3 to 4 times, which still leaves plenty of room. Run D checks that.
2. **The network is fine, but the Pixel's Wi-Fi needs a longer buffer.** Every phone got its 30 snapshots a second. Round trip p95: S25 18 to 89 ms, iPhone 26 to 51, Pixel 38 to 126. The gap between snapshots (p99, at 60 fps) was about 50 ms on the S25 and the iPhone, which is normal: 33 ms plus one frame. On the Pixel it was 67 to 105 ms. The planned 50 ms draw delay suits the first two, and the Pixel would need about 100. So the game should set each player's delay from their own measured gaps.
3. **Lit sprites cost nothing.** Every phone held 60 at T1. The base of the Dead Cells-inspired look (normal-mapped sprites, torch lights) is safe.
4. **The effects step (T2) is where the phones split.** Both Androids kept about 60, but the iPhone fell to 44 and stayed there through T4. Its script time stayed low (6.5 ms), and fewer pixels did not help, so its graphics chip is choking on something T2 turns on: the particles, the fog layer or the light shafts. This run cannot tell which. CPU particles made it worse (38).
5. **The max look (T6) is over budget on every phone.** The best was 44 fps (S25 Ultra at 1080). T5 and T6 both double the lights on screen (26 to 33, against 13 to 15 at T3). In Godot's Compatibility renderer each 2D light draws what it touches again, so lights are the first suspect. But T5 and T6 change several things at once, so that is not proven.
6. **Draw at 1920 x 1080 and scale up.** For pixel art it looks the same, and it gives the S25 Ultra back about a third of its frame time at the heavy tiers.
7. **Live 3D archers are cheap.** T4 cost 0 to 1 fps against T3 on every phone. This feeds D14 (bake to sprites or draw live).

**The short answer.** Keep the server plan as it is. For the look, aim at about T3 (lights, particles, 2 fog layers, outline and post shaders, 3D archers allowed) drawn at 1080. The Androids hold that, with little room to spare, and the real game adds prediction and a HUD. The iPhone needs a lighter effects setting. The max look needs cheaper lights (for example, glow drawn in the fog shader instead of PointLight2D nodes), or it stays a "high" setting for strong phones.

## Problems with this run

- **The iPad was capped at 30 fps** in every tier, even T0 with 4 ms of script time. That is Low Power Mode (the battery was low). Its numbers only show that it held a steady 30 through T4 at 1080. Run it again, charged, with Low Power Mode off.
- **The Pixel's window changed size in both runs:** it shrank to 2243 x 760 at T3 in run 1, and turned portrait at T2 in run 2. Its "full screen" T6 and T7 were then drawn at 1351 x 759 and 1080 x 607, so their passes don't count. Its 1080 rows were still drawn at 1920 x 1080 and are used (run 2, the complete one). The report now marks rows where the window changed.
- **The pass rule was wrong** and failed even a steady 60 (p95 16.7 ms or less, and script time 8 ms or less). The report now judges old cards by the fair rule, and the page uses it too (re-exported 2026-09-11).
- **The limit test stopped at level 1 on every phone**, partly because of that rule. It told us nothing that T6 didn't.
- **Script time (`proc`) reads higher than the frame time** on the web (S25 at T2: 18.7 ms at 60 fps). Use it only to compare tiers.
- **Not done yet:** run C (10 minutes of heat on the weakest phone). Run D is below.

## Proposed next steps

1. The iPad again, charged, with Low Power Mode off (7 minutes).
2. **A split test.** Ladders that turn on one thing at a time, for T2 on the iPhone (particles only, fog only, shafts only) and for lights on the Androids (8, 16, 24, 32 lights). About an hour to build, 5 minutes a phone. It shows exactly what to cut or make cheaper.
3. Run C on the iPhone at T1 or T2 (10 minutes).
4. ~~Run D~~: done, see below.

## Run D: the server on the laptop (2026-09-11)

The bench server ran on the laptop (i7-3630QM, 4 cores from 2012), and the fake players connected from the PC. The family game kept running beside it: the relay, its 4 bots and the dashboard. The server files are a copy in `~/tower_brawl_bench` on the laptop, with raw data in `results/` there. The running game was not touched.

A tick has 16.7 ms.

| Stage | Tick average | Slowest 1% of ticks (typical / worst second) | CPU (of one core) | When someone joins | What the players got |
|---|---|---|---|---|---|
| 8 fighters, 7 players, 5 min | 2.78 ms | 4.5 / 7.9 ms | 20% | one tick of 71 ms | round trip p95 11 ms or less, snapshot gaps p99 37 ms, no stalls |
| The same, locked to one core, 3 min | 2.74 ms | 4.4 / 6.7 ms | 20% | one tick of 41 ms | the same |
| 32 fighters, 31 players, 3 min | 8.86 ms | 12.5 / 19.9 ms | 57% | one tick of 96 ms | round trip p95 11 ms or less, snapshot gaps p99 39 ms, no stalls |

**What it means**

1. **8 players fits, with room: 2.8 ms of 16.7.** Here the laptop is about 8 times slower than the PC, although a plain timing loop said 3.8. The simulation leans on memory, and the laptop has old DDR3.
2. **The real game will cost more** (rounds, pickups, rewinding shots for lag). At 2 to 3 times the stand-in, a tick takes 6 to 8 ms. That still fits, but with less room, so measure the tick cost while G1 to G4 are built.
3. **32 players is the ceiling.** The average fits, but the worst seconds go over 16.7 ms.
4. **A join stalls the match for everyone** (41 to 96 ms), because the TLS handshake runs inside a tick. (Fixed in the bench server on 2026-09-13 by a network thread: see the end of this page.) On the PC it was 12 to 15 ms, too small to notice. Fix this before real play, either by doing handshakes on another thread, or by letting a TLS proxy (Caddy or nginx) take wss and pass plain ws to the server over localhost.
5. **Locking the server to one core changed little:** the same average, and the worst second went from 7.9 to 6.7 ms.

**Using more cores.** A tick split into its parts (PC, stand-in simulation):

| Part of a tick | 8 fighters | 32 fighters |
|---|---|---|
| movement and collisions | 53% | 49% |
| arrows | 14% | 19% |
| bot brains | 12% | 18% |
| arrow bumps and pickups | 13% | 10% |
| snapshot writing | 5% | 3% |

Movement and arrows must run in order (who hits what first), so the simulation stays on one core. Only the bot brains could move to other threads, which saves 12 to 18%. The other cores are still useful for:
- TLS and sending (the proxy, or a network thread)
- running more matches at once
- the page server

If a tick ever needs to be much faster, the mover could be written in C++ (GDExtension). But the web client must run the same code for prediction, so only do that if the numbers force it.

**Dedicating the laptop to one match server** (not measured yet, because it needs sudo and stopping the family game):
- Stop the old game's relay, 4 bots and dashboards once v0.2 replaces them. They use about 0.8 of a core.
- Set the CPU governor to `performance`, so it doesn't slow down between busy moments.
- In the match server's systemd unit, set `CPUAffinity=3 7` (one core and its twin) and `Nice=-10`, and keep everything else off that core.

## The network thread (2026-09-13)

The bench server now does all the network work on a second thread: accepting players, the TLS and websocket handshakes, reading, answering pings, and sending. The simulation keeps its own thread, and the two share data only for a moment. `--net-thread 1` is the default, and `0` puts everything back on one thread. `--net-sleep-ms 4` (the default) is how long the network thread rests between socket checks.

Each test compared the thread off and on with 7 or 31 fake players, 80 to 120 s a test.

**Laptop, 8 players** (times in ms):

| Setting | Average tick | Slowest 1% | Worst tick | Worst tick at a join | Network thread | CPU | Ping p95 |
|---|---|---|---|---|---|---|---|
| thread off | 2.79 | 4.09 | 7.4 | **83.9** | none | 21% | 9 |
| on, checks every 1 ms | 2.46 | 3.40 | 7.3 | 4.6 | 113 ms a second | 31% | 4 |
| on, checks every 4 ms | 2.39 | 3.43 | 6.5 | 4.5 | 55 ms a second | 22% | 7 |
| on, every 4 ms, locked to cores 2 and 3 | 2.37 | 3.19 | 5.9 | 4.7 | 55 ms a second | 22% | 7 |

**Laptop, 32 players:**

| Setting | Average tick | Slowest 1% | Worst tick | Worst tick at a join | Network thread | CPU | Ping p95 |
|---|---|---|---|---|---|---|---|
| thread off | 9.14 | 12.49 | 17.6 | **82.7** | none | 59% | 12 |
| on, checks every 1 ms | 9.30 | 12.35 | 19.2 | 12.4 | 225 ms a second | 80% | 4 |
| on, checks every 4 ms | 9.17 | 12.42 | 20.5 | 18.2 | 135 ms a second | 70% | 7 |
| on, every 4 ms, locked to cores 2 and 3 | 9.50 | 12.30 | 15.9 | 12.4 | 132 ms a second | 71% | 7 |

**PC:** the worst tick at a join went from 11.9 to 0.3 ms with 8 players, and from 15.4 to 1.4 ms with 32. The average tick went from 0.31 to 0.28 ms, and from 1.14 to 0.94 ms.

**What it means**

1. **The join freeze is gone.** On the laptop with 8 players, the worst tick at a join fell from 84 ms to under 5.
2. **8 players got 15% cheaper** (2.79 to 2.39 ms a tick), for the same CPU, once the thread rests 4 ms between checks. Checking every 1 ms doubled the thread's CPU and made ticks no faster, so 4 ms is the default.
3. **32 players got no faster on average.** The simulation is 85% of the tick and still runs on one core, and both threads share the laptop's slow memory. The thread still removes the freeze.
4. **Locking the server to two separate cores trims the worst ticks** (32 players: from 20.5 to 15.9 ms, back under 16.7). Do this in the real server's systemd unit (`CPUAffinity`). The bench doesn't need it.
5. **Pings get answered sooner:** p95 7 ms, against 9 with the thread off.

**How to repeat:** `python3 tools/bench_ab.py <out_dir> local|laptop <port> name:fighters:cap:clients:seconds:net_thread[:sleep_ms[:cores]] ...`, then `python3 tools/bench_ab_summary.py <out_dir>`. The tick split per part comes from `godot --headless --path bench --script res://tools/sim_prof.gd`. For the laptop, copy `bench/project.godot`, `bench/server/` and `bench/sim/` to `~/tower_brawl_bench` first.

## A second S25 Ultra run (2026-09-13)

The S25 Ultra ran the ladder again; it is named "daughter" in the data (`bench_results/2026-09-13/`). It was the same phone and the same drawing code, and the server still used the old single thread.

| Tier, drawn at 1080 | First run (09-11) | Second run (09-13) |
|---|---|---|
| T1 lights | 60 | 60 |
| T2 effects | 60 | 60 |
| T3 shaders | 59 | 58 |
| T4 live 3D | 59 | 56 |
| T5 stress | 53 | 46 |
| T6 max | 44 | 32 |
| T3 with CPU particles | 60 | 30 |

At full size (2560 x 1440) it dropped to exactly 30 fps from T2 on, where the first run held 60 through T3. Frames of exactly 33.3 ms mean the phone fell to half its refresh rate. Android does that when frames keep missing, and more easily when the phone is warm or saving power. The network also hiccuped: a 150 ms round trip at the start, and 21 stalls during T6 at 1080.

**What it means:** the same phone gave very different numbers two days apart. A warm or power-saving phone loses the top tiers first, while T1 to T3 at 1080 held up. So run C (10 minutes of heat) matters more than we thought. The game also needs a quality setting that steps down by itself when frames keep missing.

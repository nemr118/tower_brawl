---
tags: [reference, plan, test]
status: done 2026-10-10 (G0 closed by the user; the verdict is in bench-8p-results)
---
# The 8-player benchmark (phase G0)

**The question** (the user, 2026-09-10): what can the server and the phones carry in an 8-person match? Find out before the new game is built, so we know early whether anything must be dialled back. The vision: [[v0.2-transformation-plan]]. The server design it tests: [[sim-server-design]].

## 1. What we measure, and the pass marks
**The server** (the laptop, the family-night machine):

| Measure | Pass | Why |
|---|---|---|
| work per tick, p99, at 8 fighters and 24 arrows | 4 ms or less | a tick has 16.7 ms; the real game adds rounds, chests and bot brains |
| the same at double load (16 fighters, 64 arrows) | 8 ms or less | headroom |
| CPU of the server process at 8 | 25% of one core or less | the laptop also serves files and writes logs |
| memory over 10 minutes | flat | no leak |
| bytes sent to 8 clients | about 100 KB/s | checks the design estimate |

**The network** (each phone and each synthetic client, on the family Wi-Fi):

| Measure | Pass |
|---|---|
| round trip, median / p95 | 20 / 40 ms or less |
| gap between two snapshots, p99 (they are 33 ms apart) | 50 ms or less |
| stalls over 150 ms in 10 minutes | none |

**The phones** (one at a time):

| Measure | Pass |
|---|---|
| frames a second, and frame time p99 | 58 fps or more, p99 25 ms or less, no hitches (holds 60 fps). Changed 2026-09-11: the first rule, p95 16.7 ms or less, failed even a steady 60, because frame times wobble around 16.7 ms |
| frame time p99 | 25 ms or less |
| hitches over 50 ms, after the first 5 s | none |
| script time a frame (`proc`) | shown, not judged. On the web it reads higher than the frame time, so it is only good for comparing tiers |
| heat: 10 one-minute steps of the same tier | held 60 in every minute. Changed 2026-09-13: the first rule, the last minute at 90% of the first or better, passed run C while only 1 minute in 10 held 60 |

**Today's baseline** (the first phone match, v0.1.0, 640 x 360, 4 fighters): the S25 Ultra and the Pixel held 60 drawn fps, worst script frame 6.5 to 8 ms in play, round trip 19 and 25 ms ([[v0.1.1 - Phone Controller]]).

## 2. How: four small programs
Throwaway code on a branch `bench/8p`, in a `bench/` folder. The family's build and the laptop's brawler are not touched; the laptop runs the bench server on a spare port only during a test. It already runs headless Godot for `tbbot`.

1. **`bench/bench_server.gd`: the server.** Headless Godot on the laptop; wss on port 8091 with the existing cert. It runs a **stand-in simulation** at 60 ticks a second: 8 fighters on a whole-pixel mover in a 1920 x 1080 box level (ledges, walls, wrap on all edges), doing the same kind of work per tick as TowerFall's `Player.cs` and `Arrow.cs` (move a pixel at a time, check solids, check arrows against bodies), with TowerFall's numbers x4.5. Arrows are fired, stick and are picked up; empty seats get simple bot inputs. It sends a snapshot 30 times a second (fighters + arrows, about 400 bytes) and reads inputs 60 times a second. Every second it logs: tick time (mean, p99, max), send time, bytes per client, CPU and memory (`/proc/self/stat`, `/proc/self/status`), each client's round trip. `--fighters 16 --arrows 64` is the headroom run.
2. **`tools/bench_synth.py`: 7 synthetic clients** in one Python process on the PC, using the websocket library the harness already uses. They send inputs, read snapshots, and measure their own round trip and snapshot gaps. They fill the other seats, so the server has 8 real sockets. (7 headless Godot clients would do the same, but load the PC.)
3. **`bench/bench_client.tscn`: the phone page.** Its own web export (`build/bench/`), served at `https://<laptop>:8443/bench`. It joins the bench server as the 8th player, draws the match it receives, and climbs a **ladder of tiers** by itself, 20 s each (the first 3 s of each not counted):

| Tier | What it draws (a 1920 x 1080 arena) |
|---|---|
| T0 | background, tiles, 8 animated 90 px sprites, 24 arrows, the HUD for 8 |
| T1 | T0 + normal maps on fighters and tiles, 4 lights |
| T2 | T1 + 8 more small lights (torches, glowing arrows), particles (dust, trails), 3 parallax layers |
| T3 | T2 + fighter shaders (outline, banded light), screen shake, hit flashes |
| T4 | T3 with live 3D fighters (the prototype's 1 200-triangle archer, toon + outline) instead of sprites |
| T5 | stress: T3 with 16 fighters, 64 arrows, 16 lights |

   Every tier runs twice: **at the phone's full screen resolution**, and **drawn at 1920 x 1080 then scaled up**. An S25 Ultra screen (3120 x 1440) has 2.2 times the pixels of 1080p, so this is often the biggest knob of all.

   The sprites are stand-ins: generated 128 x 128 frames and normal maps of the real size (the cost is the same whatever they show). T4 loads `archer_lp1200.glb` from an untracked folder; it is not committed, because this repo is public.

   Every second the page records: frame time p50 / p95 / p99 / max (from its own frame times), `proc`, `phys_cpu`, draw calls and objects (Godot's `Performance` monitors), texture memory, round trip, snapshot gaps. Once: model, OS, browser, screen size, pixel ratio, canvas size, refresh rate, CPU cores, and the GPU name where the browser allows it. It sends one `bench` card per tier to the bench server, which writes `bench_results/<date>/cards.jsonl`. No cable, no console: the same idea as today's `client_stats` cards.
4. **`tools/bench_report.py`: the report.** Reads the server's lines and the cards. Prints a table per device (tier x resolution: p95, p99, hitches, `proc`, draw calls, pass / fail), the server table, and the highest tier each phone passes.

## 3. The runs
| Run | Who | How long |
|---|---|---|
| A. Everything on the PC: server, synthetic clients, a headless Chromium page (script numbers only: its drawing is software, not real) | Claude | first, to shake out the code |
| B. Server on the laptop, 7 synthetic clients, one phone at a time: S25 Ultra, Pixel, an iPhone, the iPad, the other Android | you: open the page, tap START, lay the phone down | about 4 minutes a phone |
| C. The weakest phone from B, at its best passing tier | you | 10 minutes (heat) |
| D. Server headroom: 16 fighters, 64 arrows, 15 synthetic clients | Claude | 10 minutes |
| E. Optional, on a family night: every real device on the bench page at once | everyone | 5 minutes (a busy Wi-Fi) |

## 4. What each answer changes
- **A phone fails T1:** phones get a "low" setting without normal-map lighting, or the light is baked into the sprites.
- **Passes at 1080p but not at full resolution:** the game draws at 1920 x 1080 and scales up (likely anyway).
- **Passes T4:** live 3D fighters stay possible (D14 B). **Fails T4:** bake sprites (D14 A).
- **Fails T0 even at 1080p:** the real knobs are a smaller canvas (for example 1600 x 900: bigger fighters on screen, a smaller arena) or fewer players.
- **Server over 4 ms:** profile the mover before building G1. **Wi-Fi p95 over 40 ms, or stalls:** 20 snapshots a second, or plan WebRTC.
- **Fails the 10-minute heat check:** a 30 fps option for that phone.

The results go in `docs/reference/bench-8p-results.md` (the tables and a verdict), linked from PASSDOWN.

## 5. Cost
One build of spike code, about 1 000 lines. The stand-in mover and arrow loop are an early sketch of G1 and G2 and stay as a reference. About 20 minutes of your time with the phones. No `bump_build.sh`: the family build does not change, and the bench page has its own pck name, renamed on every run to beat the browser cache.

## 6. Built (2026-09-10, branch `bench/8p`, not committed)
**What is in it.** `bench/` is its own Godot project, so the game's `Global` never starts:
- `sim/sim.gd`: the stand-in simulation, TowerFall's decompiled numbers x4.5 (each constant names its `Player.cs` / `Arrow.cs` source). Bots run, jump, wall jump, drop through ledges, dodge, catch, stomp, shoot, fetch arrows. The power-up arrows: **fire** sets the ground burning for 4 s, **bomb** explodes 0.25 s after it sticks (radius 158 px, TowerFall's 35 px x4.5), **miasma** leaves a poison cloud for 5 s. `sim/level.gd`: a 1920 x 1080 arena on a 30 px grid with wrap on all edges. `sim/proto.gd`: the packets.
- `server/bench_server.gd`: headless, wss with our cert, 60 ticks, 30 snapshots a second, a `📊 [BenchServer]` line a second.
- `client/`: `bench_client.gd` (the ladder, the cards, the START screen), `net.gd` (decode, a 50 ms render clock, interpolation), `world.gd` (the arena and the tiers), `fx.gd` + `fx_factory.gd` (all effects, pooled), `fighter3d.gd` (T4).
- `shaders/`: 2-step cel light + outline + hit flash for fighters, pixel particles snapped to a 3 px grid (added and mixed), post (grade, vignette, colour split on blasts), fog bands, light shafts, miasma clouds.
- `tools/gen_assets.gd` draws all the art as PNGs in `assets/` (our own pixel art: hooded archers in 8 colours with normal maps, stone and plank tiles, a moonlit castle, effect textures). `bench/untracked/` holds the 3D prototype's archer for T4 (git-ignored).
- `tools/bench_synth.py`, `bench_report.py`, `bench_export.sh`, `bench_shot.py` (headless Chromium pictures).

**The effects by tier.** T2 adds everything that moves: jump and landing dust, wall-jump dust, dodge rings and afterimages in the player's colour, arrow trails per kind (fire flames + a light, bomb fuse sparks, miasma drips), burning ground (flames, embers, a glow, a flickering light, a scorch mark), explosions (flash, two shock rings, fire, sparks, smoke, debris, a light burst, a scorch mark, shake), miasma bursts and clouds (boiling pixel cloud, bubbles, a purple light), catches (a star and a ring), pickups, deaths (a burst in the player's colour and a rising soul), spawns (a beam), torches, drifting embers and dust motes, fog, light shafts, parallax. T3 adds the fighter shader, the post shader and screen shake.

**How to run it (PC as the server; the laptop works the same way).**
```bash
tools/bench_export.sh                                   # the page -> build/web/bench/ (served by the game's server on :8443)
godot --headless --path bench res://server/bench_server.tscn -- --fighters 8          # wss :8091; --fighters 16 --arrow-cap 64 = run D
./venv/bin/python tools/bench_synth.py --url wss://192.168.4.21:8091 --n 7 --seconds 1800   # the 7 other seats
./venv/bin/python tools/bench_report.py                 # the tables, today's bench_results/
```
- **A phone:** open `https://192.168.4.21:8443/bench/index.html?name=S25`, tap START, lay it down (13 steps, about 5 minutes). If it cannot connect, open `https://192.168.4.21:8091` once, accept the certificate, and reload.
- **Start the bench server first.** The page on 8443 comes from the game server, but the cards go to the bench server on 8091. Since 2026-09-11 the page shows a red WAITING line and START stays off until the bench server answers. It keeps trying, so start the server and wait. If the server drops mid-run, the corner says NO SERVER, and the last screen says how many cards were not saved.
- **iPhone and iPad:** turn Low Power Mode off and charge to at least 50%. Low Power Mode caps Safari at 30 fps, and every tier would fail.
- **Heat (run C):** `…/bench/index.html?name=S25-heat&tiers=3,3,3,3,3,3,3,3,3,3&res=1080&no-cpu&seconds=60` (10 one-minute steps of T3 at 1080). Hold the phone sideways, unplugged, battery saver or Low Power Mode off, and note the charge before and after. For a step run 3 or more times, the report prints a trend line.
- **Just look:** `…/bench/index.html?tier=3` (no ladder; `&nopost` without the post shader), or on the PC `godot --path bench -- --tier=3 --server=wss://127.0.0.1:8091`.

**Checked on the PC.**
- `sim_probe.gd`: a tick costs 0.15 ms (p99 0.27) at 8 fighters and 0.35 ms (p99 0.57) at 16. In 60 s the bots made 318 shots, 59 explosions, 45 fires, 55 miasma clouds, 153 deaths, 44 catches, 173 pickups. Snapshots average 303 bytes.
- ws and wss with 7 synthetic clients: 30 snapshots a second each, gap p99 34 ms, no stall.
- Run A, a headless client through all 13 steps: no script error, 14 cards stored (headless Godot draws nothing: script numbers only).
- Run D on the PC (Core Ultra 9 285K): 16 fighters, 64 arrows, 15 wss clients, 55 s: steady tick 0.56 ms mean, p99 worst 1.9 ms, CPU 3.9%, memory flat, 220 KB/s out, every client under 8 ms round trip and without stalls. **Pass.**
- The page in headless Chromium against the Godot TLS server: every tier draws (pictures in the session's scratch folder).

**Found on the way.**
- **A TLS handshake runs inside a tick:** 15 clients joining in the same second made one 15.7 ms tick. The real server should do handshakes between ticks. The report shows joins on their own line.
- **The round trip includes up to ~8 ms waiting for the server's next poll** (it polls 120 times a second).
- **T4 uses a toon `StandardMaterial3D`** with the prototype's texture and outline, because its `hero.gdshader` draws noise outside the prototype (it picks its texture from the prototype's vertex colours).
- Godot 4.7 writes no `mainPack` key in the page: `bench_export.sh` adds one, like `bump_build.sh`.

**Next:** runs B, C and D are done: [[bench-8p-results]]. Run C (2026-09-13) ran the S25 Ultra at T3, the look we aim for, not the weakest phone. Still to do: the split test, then run C again at the setting it picks.

## 7. The max build (2026-09-11, same branch)
**Added at the user's request:** smoke arrows, more archer animations, the fog and effects "dialled all the way up", and a test that finds the limit.
- **Smoke arrows** (`A_SMOKE`): a grey cloud 230 px wide for 8 s. No damage, but a bot cannot target a fighter inside it from more than 150 px, and the cloud thickens the fog.
- **The archer sheet is 28 frames** (2 rows of 16, 2048 x 256): idle 2, run 6, jump, fall, aim, **hit 2**, **air dash**, **roll 4** (a ball turned 90° a frame), **wall slide**, **wall jump**, **ledge hang**, **ledge pull-up**, **death 5** (hit, thrown, falling, impact, lying), spawn crouch. `gen_assets.gd` draws them from poses (hips, lean, feet, cape, arms).
- **The simulation gives them something to show:** `F_HURT` (a blast within 1 to 1.8 radii, or a hard side bump, knocks a fighter back for 0.3 s), `F_LEDGE` (a falling fighter pressing into a wall top hangs, then hops up), a ground dodge rolls and an air dodge dashes, and a dead body flies with the hit, falls and bounces for 1.5 s. New events `E_HURT`, `E_LEDGE`, `E_SMOKE`; new flags 32 (rolling / pulling up), 64 (wall jump), 128 (in smoke).
- **Dynamic fog** (`shaders/fog_dynamic.gdshader`, T2 and up): two drifting noise layers, cut into pixel cells and 7 density steps. Up to 32 fighters, arrows and blast rings push and swirl it and clear a pocket around fighters; up to 32 lights light it in their colour; smoke clouds thicken it. T2 has 1 layer (behind the fighters), T3 2 (one in front), T6 3.
- **T6 max:** particles x2.5 (drawn at 60%), 3 fog layers, rain with splashes, lightning (a bolt, a flash of the whole scene, a light at the strike, shake), 16 spirit lights with real lights, bloom, shock ripples that bend the picture around blasts, heat shimmer over fires.
- **T7 limit:** 10 levels of 5 s each (1.5 s to settle, then measured). Every level turns the dial: particles 64% to 100% of x2.5, fog layers 3 to 5, spirit lights 11 to 38, fighters 8 to 32 (copies of the match). The first level that misses 60 fps ends it; the card lists every level and `limit_level`.
- **The ladder is 17 steps** (T0 to T7 at full resolution and at 1080p, plus T3 with CPU particles): about 7 minutes a phone. Look without the ladder: `…/bench/index.html?tier=6`, or `?tier=7&level=10`.

**Checked on the PC.**
- `sim_probe.gd`: 0.19 ms a tick at 8 fighters, 0.77 ms at 32. In 60 s: 54 smoke clouds, 43 staggers, 45 wall jumps, 6 ledge grabs, 86 deaths.
- A headless client through all 17 steps, including the 4-level limit test: no script error.
- **Server stress, 32 fighters, 128 arrows, 31 wss clients, 50 s:** steady tick 1.16 ms mean, p99 worst 5.4 ms, CPU 7.7%, memory flat, 776 KB/s out, every client under 5 ms round trip, no stall. **Pass.**
- Pictures of T3, T6 and T7 level 10 from headless Chromium: T6 is the intended look; T7 level 10 buries the arena in fog and colour split, which is the ceiling it is meant to find, not a look to ship.

**Found on the way.**
- **Ledge grabs are rare** (6 a minute): the arena has few wall tops at head height, and bots only hang when they happen to press into one. A real arena should place grab-able wall tops on purpose.
- **A parse error in a script started with `--script` never quits Godot** (it looks like a hang). Run `godot --headless --path bench --check-only --script res://<file>` first.

**First phone try (2026-09-11): nothing saved.** The phones ran the ladder while no bench server was running. The page drew an empty arena (no fighters, arrows or effects, because those come from the server) and quietly dropped every card. The numbers on the phone screens are too kind and are not used. Fixed: the page now waits for the server (see the steps above). Run B again.

## 8. The split test (2026-09-14, same branch)
**The questions** (the user, 2026-09-13): (1) what in T2 slows the iPhone: particles, fog or light shafts; (2) how many lights the Androids carry: 8, 16, 24 or 32; (3) what in T3 costs the most on the S25 Ultra: fog layers, lights, particles or the post shader. Run C showed T3 at 1080 has no room to spare.

**60 fps is a ceiling.** A phone never draws faster than its screen, so a step with room to spare and a step that only just makes it both read 16.7 ms frames. So every card now also carries:
- `slow_share`: the share of the step spent on frames over 25 ms (the time Android drew at 30). Measured, not estimated.
- `work_p50` / `work_p95` (ms): the page's own frame code, timed around every `requestAnimationFrame` callback (Godot's frame loop goes through it).
- `gpu_p50` / `gpu_p95` (ms): how long the graphics chip takes to finish a frame, on 1 frame in 15: a WebGL2 fence placed after the frame, checked until it is done (given up after 100 ms: `gpu_lost`). Compare it only between steps on the same phone. If a phone has no fence, `timing_err` says so, and we judge by fps, p99 and `slow_share`. `notime` in the link turns the timer off.

**The ladders.** One link each, all drawn at 1080, no CPU-particle step. Each runs forward and then back, so every step runs once early and once late, and a slow warm-up hits all steps alike. The first 3 s of each step are not counted. The step names are in `world.gd` `VARIANTS`.

| Link | Who | Steps | Step length | Time |
|---|---|---|---|---|
| `split=t2` | iPhone | `t1` (normal maps, 4 lights), `t1.particles` (all emitters, and the flashes, rings, afterimages and scorch marks that come with them), `t1.fog` (1 layer, fed T2's light list, while only T1's 4 lights draw), `t1.fogplain` (the same layer without its loops over fighters, lights and smoke), `t1.shafts`, `t1.lights` (8 torches and the short lights of blasts, fire arrows, fire and poison), `t2` | 30 s | 7 min |
| `split=lights` | S25 Ultra, Pixel | `l4`, `l8`, `l16`, `l24`, `l32`: T1 (no fog) with that many torch-sized lights, the 8 torches first, then a 6 x 4 grid | 30 s | 5 min |
| `split=t3` | S25 Ultra | `t3`, `t3-fog1` (1 fog layer), `t3-fog` (none), `t3-lights` (no light draws, but the fog still gets them, so this is the cost of the lights alone), `t3-particles`, `t3-post` | 60 s | 12 min |

The fighter shader, the shake and the hit flashes stay on in every T3 step. A light that is "not drawn" is hidden (`visible = false`) and stays `enabled`, so the fog still finds it. `steps=t3,t3-fog` runs your own list; `look=t3-fog` shows one step without a ladder.

**How we pick** (decided before the run):
- **Q1:** a part is the cost if the iPhone falls under 58 fps with it alone. If no part does, but T2 does, it is the sum, and `gpu_p95` shows the biggest share.
- **Q2:** the limit is the highest count that held 60 in both passes with `gpu_p95` at 13 ms or less (about a fifth of the frame free).
- **Q3:** run C again uses T3 minus the part that saved the most GPU time. If that step did not hold 60 in both its minutes, cut the second part too. Without GPU numbers: by `slow_share`, then p99.

**What changed.** `world.gd`: a step is a tier plus a dictionary of parts (`parts_for_tier`, `set_variant`, `apply_parts`), 24 grid lights, `lights_drawn()`, and the fog's loops can be turned off. `fx.gd`: events always run (rings, shake and colour split feed the fog and the post shader); the drawing checks `enabled`. `bench_client.gd`: `SPLITS`, the timer (`TIMING_JS`), and on each card `variant`, `split`, `pass_i`, `parts`, `slow_share`, and what the nodes really had on (`lights_drawn`, `fog_layers_on`, `fog_lights_fed`, `emitters_drawn`, `post_on`). `bench_report.py`: a split table per run (both passes, the change against `t1`, `l4` or `t3`, and a "switches" column that checks what was on against what was asked). `bench_shot.py`: `--looks` and `--ladder`.

**How to run.** The bench server and 7 fake players as in section 6, then:
- iPhone: `https://192.168.4.21:8443/bench/index.html?name=iphone-split&split=t2` (Low Power Mode off, 50% charge or more)
- S25 Ultra, cool: `…/bench/index.html?name=S25-split&split=t3`; rest 15 minutes; then `…?name=S25-lights&split=lights`
- Pixel: `…/bench/index.html?name=pixel-lights&split=lights`
- The report: `./venv/bin/python tools/bench_report.py` (the split table follows each run's rows).

**Checked on the PC (2026-09-14).**
- `--check-only` on `world.gd`, `fx.gd` and `bench_client.gd`: no parse error.
- A bench server with `--port 8092 --out <scratch>`, 7 fake players, and a headless Godot client through each ladder in 4 s steps: `t2` 14 cards, `lights` 10, `t3` 12, and the switch check says `ok` on every step. The server: 0.28 ms a tick, 2.6% CPU. (Headless Godot has no web timer, so its cards say `timing: off`.)
- The old ladder (T0 to T7, with T4's 3D archers, the limit test and CPU particles) still runs to the end with no script error.
- The switch check says WRONG for each field changed by hand on a card: lights drawn, fog lights, fog layers, post, emitters.
- Headless Chromium ran `split=t3`. It draws in software at about 7 fps, so it reached 5 of 12 steps in 100 s. The timer works: 10 GPU samples, none given up. There `t3-lights` cut the GPU time from 765 to 145 ms, which proves the hidden lights really stop drawing (the size means nothing for a phone).
- A picture of each of the 16 steps: every part shows or goes as asked. `t3-lights` is darker, but the fog still glows around the torches; `t3-fog` loses only the fog; `lights 32` lights the ledges all over the arena.
- `https://192.168.4.21:8443/bench/index.html` serves the new pck (`index_20260914155606.pck`).

**Found on the way.**
- The timer checks the fence from the page's own thread, again and again, until the chip is done (1 frame in 15). That costs the page a little time, the same on every step.
- Events now run at every tier, so T0 and T1 now also track rings and shake (a few numbers a frame). Nothing more is drawn.

**Stopped (2026-10-10).** The S25 Ultra ran `split=t3` ([[bench-8p-results]], "The split test, part 1"). The iPhone and lights ladders were not run: the user chose to build the game now and tune the look later ([[Design Decisions v0.2]] D18, [[first-playable-plan]]). The page and the ladders stay for later.

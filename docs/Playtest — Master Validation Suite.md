---
tags: [playtest]
build: v0.0.40
backlog: 1, 6, 13, 9 and 24 (the shift feel), optimisation Step C (build 1 and build 3), v0.1.0 release sign-off
result: not played yet
---
# Playtest — Master Validation Suite

**Result: not played yet. Tick the boxes, paste the console lines into the tables, tick one verdict per section.**

One sheet for everything a person still has to check. It replaces the three old sheets (Backlog 1 ranger quiver, Backlog 13 PC reload probe, v0.0.32 free-fall shift), which were deleted in v0.0.34. Each section stands alone and has its own verdict, so you can do one section per evening. Section 1 reads the phone's own frame numbers (since v0.0.37 they reach the server on their own, no cable). Section 5 (v0.0.36) checks that the puppets still feel right now that the server sends movement in bundles. Section 4 (rewritten 2026-09-07) checks the arena shift with the floor anchored and the rest turning above it. Section 6 (added 2026-09-07) is the release sign-off for v0.1.0: one whole match, a spectator, and a look at everything on screen. v0.1.0 is v0.0.40 with a new number, so a pass here on v0.0.40 counts for the release ([[release-v0.1.0]]).

**No console needed anywhere (v0.0.37).** Every device, phone or PC or tablet, sends its NetStats numbers to the server every 5 s; the server stamps every match and round. You write clock times (the PC clock, HH:MM), nothing else. Afterwards `./venv/bin/python tools/stats_table.py --list` shows the matches and `--match N` (or `--from HH:MM --to HH:MM`) prints one row per device, all devices at once. A console is only where the tagged lines (`Quiver`, `Spawn`, `TopEdge`) print, and only the PC needs it.

## 0. Setup (once per evening)

| Field | Your answer |
|---|---|
| Date and time (so the `server.log` lines can be found) | |
| Build shown in the lobby (must be v0.0.40, the release candidate) | |
| PC: operating system, browser and version (`chrome://version`) | |
| Phones and tablets in the game (model, browser) | |
| Number of players, bots in the game (yes / no, how many) | |

- The server is the laptop at a family evening ([[laptop-server]]; the play link is on its screen) or the PC's service at home (`https://192.168.4.21:8443/play`). If a console says VERSION MISMATCH, reload hard. Everything the night records is pulled afterwards with `tools/pull_laptop_logs.sh <laptop ip>`.
- PC console: F12, tab Console, then type the filter word the section names (`NetStats`, `Quiver`, `Spawn`, `TopEdge`).
- Numbers: no console. Write clock times in the match log below and next to the tick boxes; the tables are pulled from the server afterwards (`tools/stats_table.py`, [[Commands]]).
- A bot as the second fighter: `godot --headless --path . -- --autojoin --ai=chaser --name=Bot1`.
- Server lines on the side: `tail -f server.log | grep -E "JOIN|LEAVE|ROUND"`. Live numbers per seat: `tbdash` (the Screen column, v0.0.37).

### 0.1 Match log (the only numbers you write by hand are clock times)

| # | Start (HH:MM) | End (HH:MM) | Devices in it (fighters, spectator) | What you did, what you noticed |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |
| 4 | | | | |
| 5 | | | | |

The server stamps every match and round itself, so these times only need to be close: they say which match is which. For a moment inside a match (a shift, a replay, a reload, a screen rotation) write the clock time next to the tick box; to the minute is enough, 10 s in a situation gives two cards.

---

## 1. Mobile frame telemetry (optimisation Step C, build 1; the v0.1.1 baseline)

**Why.** On the dev PC the game uses about 1 ms of a 16.7 ms frame ([[optimisation_step_b_profiles]]). A phone is the platform that matters and has never been measured. Since v0.0.34 every `📈 [NetStats]` line ends its `fps` part with two new numbers:

```
fps draw=59.8 phys=60.0 worst=21ms hitches=0 proc=0.6ms phys_cpu=0.4ms | keys=0 focus=1
```

| Field | Meaning |
|---|---|
| `draw=` | pictures drawn a second (a 120 Hz phone can read up to 120) |
| `phys=` | physics ticks a second (should stay near 60) |
| `worst=` | the slowest drawn frame in the last 5 s, in ms |
| `hitches=` | frames slower than 50 ms in the last 5 s |
| `proc=` | ms the scripts spent in `_process` (drawing the puppets, the HUD, the VHS overlay) in the slowest frame of each second, averaged over the 5 s |
| `phys_cpu=` | ms the scripts spent in `_physics_process` (the fighter sim, the tape frame, the packets) in the slowest tick of each second, averaged over the 5 s |

Both come from Godot's `TIME_PROCESS` / `TIME_PHYSICS_PROCESS` monitors, which the engine refreshes once a second with the worst frame of that second. So they are "worst script frame per second" numbers, not the typical frame. The first line after the arena loads carries the load spike (a PC prints `proc=28ms` there with `worst=132ms`); skip that line and read the ones after it.

**How to read it.** The frame budget is 1000 divided by the screen rate: 16.7 ms at 60 Hz, 8.3 ms at 120 Hz. Add `proc=` and `phys_cpu=` from a line taken mid-fight. If that sum is under a third of the budget and `draw=` still sits far below the screen rate, the time goes outside our scripts (the browser, WebGL, the renderer), and cutting script work will not help. If `proc=` is the big one, the draw-side scripts are the first cut. If `phys_cpu=` is the big one, the sim is.

Since v0.0.37 every device sends these numbers to the server on its own (the `client_stats` card, every 5 s). The console below is optional: use it only to watch the lines live.

### 1.1 Optional: watch the S25 Ultra console live from the Arch PC (Chromium + ADB)

Developer Options and USB debugging are already on. `adb` is installed on the PC (package `android-tools`).

1. Plug the phone into the PC with a USB data cable. Unlock the phone. If it asks about the USB mode, "Charging only" is fine.
2. On the PC: `adb devices`. The first time, the phone shows **Allow USB debugging?** with the PC's key. Tick **Always allow from this computer**, tap **Allow**. Run `adb devices` again. The line must end in `device`. If it says `unauthorized`, look at the phone again. If it says `no permissions`, install `android-udev` (`sudo pacman -S android-udev`), replug the cable, then `adb kill-server` and `adb devices` again.
3. On the PC, in Chromium, open `chrome://inspect/#devices`. Tick **Discover USB devices**. The phone appears under **Remote Target** within a few seconds, with its model name.
4. On the phone, in Chrome, open `https://192.168.4.21:8443/play`. Accept the certificate warning if it shows. The tab now appears under the phone in the Chromium page.
5. Click **inspect** under that tab. A DevTools window opens on the PC. Open the **Console** tab, tick **Preserve log**, and type `NetStats` in the filter box. One line lands every 5 s.
6. Play. Keep the phone unlocked and the screen on. To copy lines: select them, or right-click in the console and **Save as...**.
7. When done, close the DevTools window first, then unplug. `adb kill-server` is optional.

Snags: if the phone does not appear in step 3, run `adb devices` again (Chromium uses its own ADB and the two can fight; `adb kill-server` then retry). A DevTools window open on the PC costs the phone a little; note it in the table if `draw=` changes when you close it.

- [ ] (optional) `adb devices` shows the phone as `device`
- [ ] The phone and its tab show under Remote Target
- [ ] The DevTools console shows `📈 [NetStats]` lines with `proc=` and `phys_cpu=`
- [ ] The version line in the phone console says v0.0.34 or later

### 1.2 Device fields

| Field                                           | S25 Ultra                        | Pixel | iPad       |
| ----------------------------------------------- | -------------------------------- | ----- | ---------- |
| Model and OS version                            | SM-S938U, One Ui 8.5, Android 16 | N/A   | No console |
| Browser and version                             |                                  | N/A   | No console |
| Screen refresh rate set (60 / 120 Hz, adaptive) |                                  | N/A   | No console |
| Battery saver on?                               |                                  | N/A   | No console |
| Wi-Fi band (2.4 / 5 GHz)                        |                                  | N/A   | No console |
| Console path used (USB DevTools / none)         | USB DevTools                     | N/A   | No console |

Model, OS, screen rate and browser come with the card (`./venv/bin/python tools/stats_table.py --devices`); fill battery saver and the Wi-Fi band by hand. "No console" is fine everywhere: the numbers arrive anyway.

### 1.3 Frame numbers per device

Sit in each situation for at least 10 s (two cards) and write the clock time. The rows come afterwards from `./venv/bin/python tools/stats_table.py --from HH:MM --to HH:MM`, one per device, every device at once (draw, phys, worst, hitches, proc, phys_cpu, rtt, puppets).

| Situation | Clock (HH:MM, 10 s or more) | Devices in it | Feel on the phone (smooth / stutters / slow) |
|---|---|---|---|
| Lobby, idle | | | |
| Round in play, 2 fighters | | | |
| Round in play, 4 fighters | | | |
| During an arena shift | | | |
| During the replay (`◄◄ REW`) | | | |
| Right after a page reload (rejoin) | | | |
| Spectating (not joined) | | | |
| PC, for comparison (4 fighters) | | | |

### 1.4 Edge cases
- [ ] Phone screen rotated during a round: clock time before and after the turn: 
- [ ] Battery saver on (S25 Ultra): clock time with it on: 
- [ ] (only if 1.1 was used) the DevTools window closed: clock time, so `draw=` can be compared: 
- [ ] A visible hitch during play (not at the arena load): clock time and what was happening: 

### 1.5 Verdict (section 1)
- [ ] **`proc=` + `phys_cpu=` is under a third of the phone's budget and `draw=` holds the screen rate:** the scripts are not the phone's problem. v0.1.1 skips cut 1 and looks at the export settings or the native app instead ([[release-v0.1.0]]).
- [ ] **`proc=` is the big number:** the draw-side scripts cost. Next cut: `_render_snapshots`, the `VhsOverlay` redraw and the HUD in `player.gd` / `arena.gd`.
- [ ] **`phys_cpu=` is the big number:** the sim costs. Next cut: `_record_tape_frame` and the local branch of `player.gd` `_physics_process`.
- [ ] **Both small, `draw=` low anyway:** the browser or the GPU. Next: the export settings (canvas size, the compatibility renderer), not the scripts.

---

## 2. Ranger reload and quiver recovery (backlog 1 and 6)

**Why.** Before v0.0.30 a ranger who reloaded the page mid-match came back with the arrows it had left, and its stuck arrows on the ground were gone, so a ranger with 0 arrows was disarmed until the next round. Since v0.0.30 `player.gd` `restore_combat_state` ignores a save from another round, and in the same round a ranger never comes back with less than 1 arrow. The harness scenario `ranger_rejoin` checks this headless. The browser keeps the save in `localStorage` under the key `towerbrawl_combat`, and that path has never been watched by a person.

Every rejoin prints one line (filter `Quiver`):

```
🏹 [Quiver] rejoin slot=2 round=2 saved_round=2 arrows=0->1 charges=3 kunai=4 bear=0 tick=612
```

| Field | Meaning |
|---|---|
| `slot` | your seat number |
| `round` | the round the game is in when the fighter is built again |
| `saved_round` | the round the save was written in |
| `arrows=A->B` | A = what the save said, B = what you got |
| `charges`, `kunai`, `bear` | the mage charges, the rogue kunai, the druid bear form after the restore |

Rule: `saved_round == round` → B is A, but never less than 1 for a ranger. `saved_round != round` → B is the fresh 3, the save is ignored.

Play the **ranger** on the PC with a second fighter in.

### 2.1 Scenario A: empty quiver, reload in the same round (the bug)
1. Shoot all three arrows at the far wall. The quiver row shows three grey dots.
2. Pick nothing up. Press F5.
3. The page comes back in the arena, same seat (`server.log`: `(rejoined mid-match)`), same round.

- [ ] Back in the arena, same seat, as the ranger
- [ ] The round number in the banner is the round you left
- [ ] The quiver row shows **1 yellow dot** (not 0)
- [ ] You can shoot one arrow and pick it up again where it sticks
- [ ] The stuck arrows from before the reload are gone (expected; this fix does not bring them back)

### 2.2 Scenario B: arrows left, reload in the same round (the control)
1. Shoot exactly one arrow. Two yellow dots stay.
2. Press F5. Come back in the same round.

- [ ] The quiver row shows **2 yellow dots** (the save is kept as it was, no free arrow)

### 2.3 Scenario C: reload inside the replay gap, land in the next round
1. Shoot all three arrows, then let the round end on a kill. The replay starts (`◄◄ REW`).
2. Press F5 while the replay plays. The page comes back inside the 6.5 s gap.
3. Wait for the next round.

- [ ] The next round starts at the normal time
- [ ] The quiver row shows **3 yellow dots** at the round start
- [ ] If a `🏹 [Quiver]` line printed, `saved_round` is the old round and `arrows` ends in `->3`. No line at all is also fine (the fighter was built at the round start, where everyone gets a fresh quiver)

### 2.4 Scenario D: away past the round start (the hidden phone)
1. Shoot all three arrows, let the round end on a kill, then close the tab.
2. Count to 7 (past `new_round` at 6.5 s, inside the 8 s seat grace). Open the play page again.

- [ ] Back in the same seat, in the running round
- [ ] The quiver row shows **3 yellow dots** (the save named the old round, so it was ignored)

### 2.5 Console lines (paste the whole line)

| Scenario | `round` | `saved_round` | `arrows` | `charges` | `kunai` | `bear` | whole line |
|---|---|---|---|---|---|---|---|
| A | | | | | | | |
| B | | | | | | | |
| C | | | | | | | |
| D | | | | | | | |

`localStorage` check, in the console after scenario A (before the reload): `localStorage.getItem('towerbrawl_combat')` → paste the value: 

### 2.6 Edge cases (tick what you tried)
- [ ] **Two reloads in a row** in the same round with 0 arrows: the second reload also gives 1
- [ ] **Reload with 1 arrow left**: still 1, not 2
- [ ] **Mage**: shoot two fireballs, reload in the same round → `charges=1` in the line and 1 charge on screen
- [ ] **Rogue**: throw two kunai, reload → `kunai=2`
- [ ] **Druid in bear form**: reload → `bear=1` and the fighter is still a bear
- [ ] **Knight**: reload → the line prints with `arrows=3->3` and nothing changes
- [ ] **A different class after the match**: join the next match as a mage after playing ranger; no `🏹 [Quiver]` line (a fresh join is not a rejoin)
- [ ] **Other screens**: on the phone, the reloaded ranger's first arrow after the rejoin flies and can hit

Notes:

### 2.7 Verdict (section 2)
- [ ] **A gives 1 arrow, B keeps 2, C and D give 3:** the fix works in the browser. Close backlog 1 and 6. The class-kit revisit (backlog 18) stays a design call.
- [ ] **A still gives 0:** the browser save was not read. Paste the `🏹 [Quiver]` line (or say there was none) and the `localStorage` value. Next: `arena.gd` `_start_round` (`Global.rejoined_mid_match`) and `global.gd` `load_combat_state`.
- [ ] **C or D gives less than 3:** the round guard did not fire. Paste the line. Next: where `Global.current_round` is set on a rejoin (`global.gd` snapshot handling, `new_round`).
- [ ] **Something else:** write it down with the console lines.

---

## 3. PC reload movement lockout probe (backlog 13)

**Why.** On 2026-09-04 the PC reloaded its page while the replay was playing. It got its seat back, the next round started on time, but the fighter could aim with the mouse and could not walk. A second reload did not help. The server and lobby parts were fixed in [[v0.0.28 - Rejoin in the Replay Gap]]. The walking part is still open because it never happens headless (scenario `reload_in_gap` walks fine). The suspect is the browser keyboard.

In the browser the game only hears keys while the game canvas has the page focus. Every `📈 [NetStats]` line ends with `keys=N` (key presses the game heard since the last line, one line every 5 s) and `focus=1` or `focus=0` (does the canvas have the page focus now). Both numbers are also in the card the game sends to the server every 5 s (v0.0.37), so a clock time next to each try is enough when the console is closed: `./venv/bin/python tools/stats_table.py --from HH:MM --to HH:MM` prints `keys` (the sum) and `focus` (0 if it was lost at all) per device.

| What you see while holding a key | What it means | Where to look next |
|---|---|---|
| `focus=0` | the reload lost the page focus; the self-heal in `web/shell.html` did not catch it | `focus_canvas()` in `global.gd`, the focus code in `web/shell.html` |
| `focus=1 keys=0` | the canvas has the focus but the game never sees the key events | the InputMap copy in `global.gd` `assign_id` (`p1_*` actions copied to `p<n>_*`) |
| `focus=1 keys>0` and still no walking | the keys arrive, the fighter state is the problem | `player.gd` local branch; take the `🧭 [Spawn]` line and the whole NetStats line |
| `keys>0` and walking works | the bug is gone or needs another trigger | try the edge cases in 3.4 |

| Field | Your answer |
|---|---|
| Keyboard: laptop, USB, Bluetooth | |
| Class the PC played | |

Every reload in section 2 is also a reload for this probe: after each rejoin hold `D` for 5 s and read one NetStats line.

### 3.1 Scenario A: reload during the replay (the original bug)
1. Play a round until it ends on a kill. As soon as the replay starts (`◄◄ REW`), press F5 on the PC.
2. The page lands in the arena in the same seat (`server.log`: `[JOIN] P<n> took seat <n> ... (rejoined mid-match)`).
3. Wait for the next round. Do not click anywhere. Do not press any key yet.
4. When the round starts, hold `D` for 5 s, then hold `A` for 5 s. Move the mouse in a circle. Count 2 NetStats lines.

- [ ] Back in the arena, same seat, same class
- [ ] The next round started at the normal time (6.5 s after the kill)
- [ ] The fighter aims with the mouse
- [ ] The fighter walks with A and D
- [ ] The fighter jumps with W or Space
- [ ] The fighter attacks with the mouse button

Server line for the rejoin (`grep JOIN server.log`): 

`🧭 [Spawn]` line after the reload (filter `Spawn`): 

### 3.2 Scenario B: reload in the middle of a round
1. While a round runs and your fighter is alive, press F5.
2. No click, no key until the arena is back. Then hold `D` 5 s, `A` 5 s, move the mouse.

- [ ] Back in the arena, same seat
- [ ] Aims
- [ ] Walks

### 3.3 Scenario C: the control (a normal join, no reload)
1. Open the page fresh, JOIN, pick a class, LOCK IN, play one round. Hold `D` 5 s and `A` 5 s. Take one NetStats line.

- [ ] Walks (this must work; if it does not, the build is broken, stop here)

### 3.4 Edge cases (only if A or B failed)
Do each one right after a failed reload, in this order, and note whether walking came back. Take one NetStats line after each.

| # | Do this | Walking came back? | `keys=` | `focus=` |
|---|---|---|---|---|
| 3.4.1 | Click once anywhere on the game picture | [ ] yes [ ] no | | |
| 3.4.2 | Press Tab, then click the game picture again | [ ] yes [ ] no | | |
| 3.4.3 | Switch to another window (Alt+Tab) and back | [ ] yes [ ] no | | |
| 3.4.4 | Press F5 a second time and wait for the arena | [ ] yes [ ] no | | |
| 3.4.5 | Reload from the address bar (click the URL, Enter) instead of F5 | [ ] yes [ ] no | | |
| 3.4.6 | Reload with the mouse button held down while the page comes back | [ ] yes [ ] no | | |
| 3.4.7 | Reload with `D` held down while the page comes back | [ ] yes [ ] no | | |

### 3.5 Keys and focus table (all reloads, sections 2 and 3)

| Line | walked? | aimed? | `keys=` | `focus=` | `rtt` ms | `draw=` | `phys=` | `worst=` | `hitches=` | `puppets=` |
|---|---|---|---|---|---|---|---|---|---|---|
| 3.1 A, holding D | | | | | | | | | | |
| 3.1 A, holding A | | | | | | | | | | |
| 3.2 B, holding D | | | | | | | | | | |
| 3.2 B, holding A | | | | | | | | | | |
| 3.3 C, control | | | | | | | | | | |
| 2.1 A (ranger) | | | | | | | | | | |
| 2.2 B (ranger) | | | | | | | | | | |
| 2.3 C (ranger) | | | | | | | | | | |
| 2.4 D (ranger) | | | | | | | | | | |

Notes:

### 3.6 Verdict (section 3)
- [ ] `focus=0` while the keys did nothing: **the page focus is the cause.** Next: the focus self-heal must run later or again (`focus_canvas()` after `assign_id`, `web/shell.html`).
- [ ] `focus=1 keys=0` while holding a key: **the key events are lost in the game.** Next: the InputMap copy in `global.gd` `assign_id`.
- [ ] `focus=1 keys>0` and no walking: **the fighter state.** Next: `player.gd`, with the `🧭 [Spawn]` line and the NetStats line.
- [ ] Walking worked every time: **not reproduced.** Close backlog 13 or keep the probe for the next family evening.

---

## 4. Arena shift with the ground anchored (backlog 9 open, 24 new, the feel)

**Why.** Since v0.0.39 the two ground slabs do not turn with the stage. They are moved out of the spinning group when the arena loads, so the floor is always the floor; everything else (the four ledges, the tower, the apex) still turns as a group around the middle of the screen, with the platforms solid (v0.0.38). What that buys: the flipped floor at the top edge (backlog 22) is gone, and a fighter knocked off a turning ledge lands on the floor instead of falling out of the bottom. What it costs: the outer ledges still swing about 30 px past the top edge mid-turn (backlog 9, the ride, now on the ledges only), and the turning ledges sweep through the corners of the anchored slabs mid-turn, so a fighter standing at the outer end of a slab can be shoved or clipped for a moment (backlog 24, known and accepted for the playtest). This section checks how the new shift feels and how often the two known costs show up in a real game.

Two players at least, four is best. Filter `TopEdge` on the PC console for the tagged line; every shift also gets a clock time in the match log.

### 4.1 Standing on the floor when the shift starts
- [ ] Stand in the middle of `GroundLeft` or `GroundRight`. Let another player grab the power-up. The floor does not move; the rest of the stage turns above you.
- [ ] Stand at the OUTER end of a slab (near the screen edge). A turning ledge sweeps through that corner mid-turn. Were you shoved, clipped, stuck or killed by it (write which, and the clock time)?
- [ ] After the turn the ledges, tower and apex are upside down above the same floor. Does the new layout read as fair (something to stand on, no dead spots)?
Notes:

### 4.2 Standing on a ledge or the tower when the shift starts
- [ ] Stand on `LedgeLeft` or `LedgeRight` (the outer ledges). You ride the ledge; near the middle of the turn you pass above the top of the screen for up to a second. How did that feel (fine / confusing / unfair)?
- [ ] Stand on `LedgeHighLeft`, the tower or the apex. You ride it; it stays on screen.
- [ ] Come back into view on the new layout, still standing, when the stage locks.
Notes:

### 4.3 In the air or falling when the shift starts
- [ ] Jump just before the banner `** ARENA SHIFT! **`: you land on the floor or on a turning platform; everything is solid.
- [ ] Fall through the centre gap during the turn: you wrap to the top and land somewhere. Did you land on a ledge passing near the top edge, mostly out of view (write it, clock time)?
Notes:

### 4.4 A round start during the turn
- [ ] Have the last fighter of a round die while the stage turns (the next round comes 2.6 s after the last kill).
- [ ] The new round starts with everyone on solid platforms at the spawn; the `🧭 [Spawn]` line on the PC console lists a floor spot at `y = 302`.
Notes:

### 4.5 Other screens
- [ ] Watch another player through a turn on your screen. They see the same on theirs (ask them). The floor is still at the bottom on every screen.
Notes:

### 4.6 Telemetry

| When | `🧗 [TopEdge]` line (full) or "none" | Clock (HH:MM) |
|---|---|---|
| Whole session | | |

Clock times of a shift and of the moment the stage locked again; the numbers (draw, worst, hitches, proc, keys, focus, every device) come from `./venv/bin/python tools/stats_table.py --from HH:MM --to HH:MM` afterwards:

| When | Clock (HH:MM) | Devices in it | Felt like |
|---|---|---|---|
| During a shift | | | |
| Right after the stage locked | | | |

### 4.7 Verdict (section 4)
- [ ] **The anchored floor feels right; the ledge ride and the slab-corner sweep are nits:** ship v0.1.0 with it. Backlog 9 and 24 stay open for the arena configurations.
- [ ] **The slab-corner sweep hurt someone (write how):** fix backlog 24 before v0.1.0 (soft turning pieces, or move the outer ledges inward); play this section again.
- [ ] **The ledge ride out of the top is unfair (write why):** do option B or move the outer ledges inward before v0.1.0; play this section again.
- [ ] **Something else felt wrong during the turn (write what):** open a backlog item with the clock time.
Notes:

---

## 5. Movement bundles: do the puppets still feel right? (optimisation Step C, build 3)

**Why.** Until v0.0.35 the server sent every fighter's movement packet on its own: with 3 other fighters that was about 40 packets a second into every screen, and on the wire each one carries 40 to 50 B of headers around 11 B of game data ([[optimisation_step_b_profiles]], Profile 3). Since v0.0.36 the server holds the samples for up to 50 ms and sends them as ONE `sync_bundle` frame per screen, about 20 a second. The harness (`bundle` and `fleet` scenarios) says the puppets move as smoothly as before on the PC, with 25 ms more delay on average, hidden inside the 100 ms the puppets already render behind. Only a person can say whether it feels the same on a phone over Wi-Fi. Detail: [[v0.0.36 - Relay Packet Coalescing]].

### 5.1 Setup
- [ ] Build in the lobby is v0.0.40 or later (an older build is refused with VERSION MISMATCH).
- [ ] At least three fighters: you on the PC, you on a phone, and one bot (`godot --headless --path . -- --autojoin --ai=chaser --name=Bot1`). Four is better (add `--ai=rusher --name=Bot2`).
- [ ] No console needed: write the clock time of the rounds in the match log (section 0.1).

### 5.2 Play two rounds and watch the other fighters
- [ ] The bot and the other screen's fighter glide; no stutter, no rubber-banding, no sliding after a stop.
- [ ] A dash, a jump and a landing on the other screen look like they did before v0.0.36 (nobody sinks into the floor after landing).
- [ ] The phone's fighter, watched from the PC: same as above.
- [ ] Arrows, firebolts and kunai still appear where the shooter is (those packets are not bundled).
- [ ] Anything that felt late or wrong, in your words:

### 5.3 The numbers
Nothing to paste. Write the match in the match log; afterwards `./venv/bin/python tools/stats_table.py --match N` prints one row per device. With 3 other fighters `IN pkt/s` should be about 20 to 25 (it was about 40) and `bundles/5s` about 100; `jitter`, `snaps`, `stall%` and `extrap%` as before. The server side is the `[STATS 10s]` line in `server.log`, ending in `bundles=20.0/s x2.9` (bundles a second, mean entries).

| Match # (from 0.1) | Fighters | Devices that felt late, if any |
|---|---|---|
| | | |

### 5.4 Verdict (section 5)
- [ ] **The puppets feel the same and `IN` is about half of 40 pkt/s:** the bundle stays. Step C cut 3 is closed.
- [ ] **The puppets feel later or stutter (write where):** turn the bundle off without a client rebuild: `RELAY_BUNDLE_MS = 0` in `serve_game.py`, `systemctl --user restart towerbrawl`, play again; if the feel returns, the 50 ms window is too long for Wi-Fi, try 25.
- [ ] **`IN pkt/s` is still about 40 and `bundles/5s` is 0:** the server is not bundling; check the `[STATS]` line for `bundles=` and that the service restarted after the build.
Notes:

---

## 6. v0.1.0 release sign-off (one match, a spectator, everything on screen)

**Why.** v0.1.0 is the first minor version: v0.0.40 with a new number and no code change ([[release-v0.1.0]]). Sections 1 to 5 each look at one feature. This section looks at the whole game the way a player does: one full match from lobby to the crown, with a spectator watching, on the devices you have. The harness cannot judge this, a person can. There is no sound in this build (sound is on the v0.1.0 ideas list, unscheduled), so this is a visual check only.

### 6.1 Setup
- [ ] Section 0 filled. Build in the lobby is v0.0.40 (the release candidate).
- [ ] Fighters: you on the PC, you on the S25 Ultra, at least one bot (`godot --headless --path . -- --autojoin --ai=chaser --name=Bot1`). A fourth fighter (iPad, Pixel or `--ai=rusher --name=Bot2`) is better.
- [ ] Spectator: a device that is NOT one of the fighters opens `https://192.168.4.21:8443/play` and does not press join (a second device or a second browser profile, never a second tab in the game PC's browser, backlog 3).
- [ ] No console needed for the numbers. Write the match in the match log (section 0.1). PC console (F12) only for the tagged lines.

### 6.2 Match stability (play one whole match to 5 crowns)
- [ ] The lobby shows every fighter with the right name and class before the first round.
- [ ] Every round starts within about 3 s of the last kill (the replay rounds within about 7 s); nobody is stuck in a gap.
- [ ] No fighter froze, rubber-banded or fell through the floor. If one did, write the device and the round.
- [ ] One deliberate reload on the S25 Ultra mid-match: the seat comes back with the same name, class and stocks within the 8 s grace. Clock time of the reload: 
- [ ] The match ends on the fifth crown, the winner screen shows the right name, and the lobby is back with everyone in it.
- [ ] `server.log` on the side: `grep -E "ROUND|MATCH|KILL" server.log | tail -30` shows one `ROUND` per round and one `MATCH` end; no `ERROR` line during the match: `grep -c ERROR server.log` before and after.

### 6.3 Spectator connectivity
- [ ] The spectator device sees the lobby, then the arena, without pressing anything.
- [ ] It follows the fight: fighters move, arrows fly, kills show, the replay plays, the next round starts. Note anything it shows late or not at all.
- [ ] It survives the match end and shows the winner and the lobby after.
- [ ] Spectator joins mid-match (reload it during round 3): it lands in the running round, not in a blank arena.
- [ ] The game tab on the PC did NOT stall while the spectator was connected (backlog 3 was a second tab on the same browser; a second device must be clean).

### 6.4 Visual coherence (what is on screen matches what happened)
- [ ] Name tags stay on the right fighter, readable, on every device including the phones.
- [ ] The HUD (stocks, crowns, round number) agrees on every screen after each round.
- [ ] The tape card (kill stamps) updates within about 10 s of a kill and at once at the replay (cut 2 in action).
- [ ] The replay shows the closing kill from the right angle, with the right fighters, and skips or ends cleanly.
- [ ] The arena shift looks the same on the phone and the PC (no half-drawn frames, no fighter left behind); the floor stays put and the rest turns above it (section 4).
- [ ] Puppets on the phone glide like on the PC (this repeats the section 5 feel with a full match; tick the section 5 verdict from the same evening).
- [ ] Anything that looked wrong, in your words (device, round, what):

### 6.5 The numbers
Nothing to paste. The match log (section 0.1) has the clock times; `./venv/bin/python tools/stats_table.py --match N` prints one row per device and `--by-round` one table per round. The S25 Ultra row is also the v0.1.1 baseline (cut 1, the phone main thread); section 1 asks for the same numbers per situation.

### 6.6 Verdict (section 6)
- [ ] **Ship v0.1.0:** the match ran to the crown, the spectator followed it, nothing on screen was wrong or was only a nit written above. Run the release runbook, [[release-v0.1.0]] step 2.
- [ ] **Ship with the bundle off:** the match was clean but the puppets felt late on the phone: `RELAY_BUNDLE_MS = 0` in `serve_game.py`, restart the service, tick the second box of section 5.4 and say so on the patch page.
- [ ] **Do not ship (write why):** a freeze, a lost seat, a spectator that stalled the game, or a wrong winner. Open a backlog item with the round and the `server.log` lines; fix it in a v0.0.x build, replay this section.
Notes:

---

Related: [[release-v0.1.0]] (section 6), [[PASSDOWN]] (backlog 1, 6, 9, 13, 24; Step C), [[optimisation_step_b_profiles]], [[v0.0.34 - Mobile Frame Telemetry]], [[v0.0.36 - Relay Packet Coalescing]], [[v0.0.30 - Ranger Rejoin Quiver]], [[v0.0.28 - Rejoin in the Replay Gap]], [[v0.0.32 - Free-Fall Arena Shift]], [[v0.0.33 - Shift Tumble Kept]], [[Commands]] (the console lines and the USB console).

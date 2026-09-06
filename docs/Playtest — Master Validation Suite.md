---
tags: [playtest]
build: v0.0.36
backlog: 1, 6, 13, 23 (the feel), optimisation Step C (build 1 and build 3)
result: not played yet
---
# Playtest — Master Validation Suite

**Result: not played yet. Tick the boxes, paste the console lines into the tables, tick one verdict per section.**

One sheet for everything a person still has to check. It replaces the three old sheets (Backlog 1 ranger quiver, Backlog 13 PC reload probe, v0.0.32 free-fall shift), which were deleted in v0.0.34. Each section stands alone and has its own verdict, so you can do one section per evening. Section 1 reads the phone's own frame numbers over a USB cable. Section 5 (v0.0.36) checks that the puppets still feel right now that the server sends movement in bundles.

## 0. Setup (once per evening)

| Field | Your answer |
|---|---|
| Date and time (so the `server.log` lines can be found) | |
| Build shown in the lobby (must be v0.0.36 or later for section 5, v0.0.34 for the rest) | |
| PC: operating system, browser and version (`chrome://version`) | |
| Phones and tablets in the game (model, browser) | |
| Number of players, bots in the game (yes / no, how many) | |

- The server runs as the service (`systemctl --user status towerbrawl`). Play at `https://192.168.4.21:8443/play`. If a console says VERSION MISMATCH, reload hard.
- PC console: F12, tab Console, then type the filter word the section names (`NetStats`, `Quiver`, `Spawn`, `TopEdge`).
- Phone console: section 1 says how to open it over USB. A phone without a cable has no console; write "no console" in those fields.
- A bot as the second fighter: `godot --headless --path . -- --autojoin --ai=chaser --name=Bot1`.
- Server lines on the side: `tail -f server.log | grep -E "JOIN|LEAVE|ROUND"`.

---

## 1. Mobile frame telemetry and S25 Ultra USB inspection (optimisation Step C, build 1)

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

### 1.1 Open the S25 Ultra console from the Arch PC (Chromium + ADB)

Developer Options and USB debugging are already on. `adb` is installed on the PC (package `android-tools`).

1. Plug the phone into the PC with a USB data cable. Unlock the phone. If it asks about the USB mode, "Charging only" is fine.
2. On the PC: `adb devices`. The first time, the phone shows **Allow USB debugging?** with the PC's key. Tick **Always allow from this computer**, tap **Allow**. Run `adb devices` again. The line must end in `device`. If it says `unauthorized`, look at the phone again. If it says `no permissions`, install `android-udev` (`sudo pacman -S android-udev`), replug the cable, then `adb kill-server` and `adb devices` again.
3. On the PC, in Chromium, open `chrome://inspect/#devices`. Tick **Discover USB devices**. The phone appears under **Remote Target** within a few seconds, with its model name.
4. On the phone, in Chrome, open `https://192.168.4.21:8443/play`. Accept the certificate warning if it shows. The tab now appears under the phone in the Chromium page.
5. Click **inspect** under that tab. A DevTools window opens on the PC. Open the **Console** tab, tick **Preserve log**, and type `NetStats` in the filter box. One line lands every 5 s.
6. Play. Keep the phone unlocked and the screen on. To copy lines: select them, or right-click in the console and **Save as...**.
7. When done, close the DevTools window first, then unplug. `adb kill-server` is optional.

Snags: if the phone does not appear in step 3, run `adb devices` again (Chromium uses its own ADB and the two can fight; `adb kill-server` then retry). A DevTools window open on the PC costs the phone a little; note it in the table if `draw=` changes when you close it.

- [ ] `adb devices` shows the phone as `device`
- [ ] The phone and its tab show under Remote Target
- [ ] The DevTools console shows `📈 [NetStats]` lines with `proc=` and `phys_cpu=`
- [ ] The version line in the phone console says v0.0.34 or later

### 1.2 Device fields

| Field | S25 Ultra | Pixel | iPad |
|---|---|---|---|
| Model and OS version | | | |
| Browser and version | | | |
| Screen refresh rate set (60 / 120 Hz, adaptive) | | | |
| Battery saver on? | | | |
| Wi-Fi band (2.4 / 5 GHz) | | | |
| Console path used (USB DevTools / none) | | | |

The Pixel follows the same steps as 1.1 (USB debugging on, `adb devices`, `chrome://inspect`). The iPad has no Chromium USB path: with a Mac at hand use Safari's **Develop** menu (Web Inspector over the cable); without one, fill only the feel column and write "no console".

### 1.3 Frame numbers per device

Copy one `📈 [NetStats]` line per situation. Sit in each situation for at least 10 s so the line covers it.

**S25 Ultra** (USB DevTools)

| Situation | `draw=` | `phys=` | `worst=` | `hitches=` | `proc=` | `phys_cpu=` | `rtt` ms | `puppets=` |
|---|---|---|---|---|---|---|---|---|
| Lobby, idle | | | | | | | | |
| Round in play, 2 fighters | | | | | | | | |
| Round in play, 4 fighters | | | | | | | | |
| During an arena shift | | | | | | | | |
| During the replay (`◄◄ REW`) | | | | | | | | |
| Right after a page reload (rejoin) | | | | | | | | |
| Spectating (not joined) | | | | | | | | |

**Pixel** (USB DevTools)

| Situation | `draw=` | `phys=` | `worst=` | `hitches=` | `proc=` | `phys_cpu=` | `rtt` ms | `puppets=` |
|---|---|---|---|---|---|---|---|---|
| Lobby, idle | | | | | | | | |
| Round in play, 2 fighters | | | | | | | | |
| Round in play, 4 fighters | | | | | | | | |
| During an arena shift | | | | | | | | |
| During the replay | | | | | | | | |
| Right after a page reload | | | | | | | | |

**iPad** (Safari Web Inspector, or feel only)

| Situation | `draw=` | `phys=` | `worst=` | `hitches=` | `proc=` | `phys_cpu=` | Feel (smooth / stutters / slow) |
|---|---|---|---|---|---|---|---|
| Lobby, idle | | | | | | | |
| Round in play, 2 fighters | | | | | | | |
| Round in play, 4 fighters | | | | | | | |
| During an arena shift | | | | | | | |
| During the replay | | | | | | | |

**PC, for comparison** (one line, 4 fighters)

| `draw=` | `phys=` | `worst=` | `hitches=` | `proc=` | `phys_cpu=` |
|---|---|---|---|---|---|
| | | | | | |

### 1.4 Edge cases
- [ ] Phone screen rotated during a round: `draw=` before and after the turn: 
- [ ] Battery saver on (S25 Ultra): `draw=` and `proc=` with it on: 
- [ ] The phone in the game and the DevTools window closed: `draw=` changes? 
- [ ] `hitches=` above 0 during play (not at the arena load): paste the whole line: 

### 1.5 Verdict (section 1)
- [ ] **`proc=` + `phys_cpu=` is under a third of the phone's budget and `draw=` holds the screen rate:** the scripts are not the phone's problem. Step C moves on to cut 2 (`history_status` on change) and cut 3 (packet count).
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

In the browser the game only hears keys while the game canvas has the page focus. Every `📈 [NetStats]` line ends with `keys=N` (key presses the game heard since the last line, one line every 5 s) and `focus=1` or `focus=0` (does the canvas have the page focus now).

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

## 4. Free-fall arena shift and tumble feel (backlog 23, the feel)

**Why.** Since v0.0.32 the platforms are not solid while the arena shift turns the stage (2.5 s). A fighter standing on a platform when the shift starts falls through the turning stage, drops out of the bottom, comes back in at the top, three or four times, and lands on the new layout when it locks. Before, that fighter rode a platform out of the top of the screen (backlog 9). The harness proves the ride is gone (0 `🧗 [TopEdge]` lines on the heavy fleet) and, since v0.0.33, no longer counts the tumble as a fall loop. What it cannot judge is how the free fall and the tumble feel in a real game, on a phone and on a PC.

Two players at least, four is best. Filter `TopEdge` on the PC console.

### 4.1 Standing on a ledge when the shift starts
- [ ] Stand on `LedgeLeft` or `LedgeRight` (the outer ledges). Let another player grab the power-up.
- [ ] You fall as soon as the banner `** ARENA SHIFT! **` shows.
- [ ] You never leave the top of the screen.
- [ ] You fall out of the bottom and come back in at the top, three or four times, then land on the new layout when the stage locks.
Notes:

### 4.2 Standing on the ground slab when the shift starts
- [ ] Stand on `GroundLeft` or `GroundRight`. Let another player grab the power-up.
- [ ] You fall through the slab as it starts to turn.
- [ ] You never leave the top of the screen.
Notes:

### 4.3 Standing on the centre tower when the shift starts
- [ ] Stand on the centre tower. Let another player grab the power-up.
- [ ] You fall through the tower (it is soft too), then land when the stage locks.
Notes:

### 4.4 Grabbing the power-up yourself
- [ ] Grab the power-up while standing on a platform. You fall right away, same as the others.
Notes:

### 4.5 Jumping and dashing during the turn
- [ ] During the turn, jump and dash across the screen. Nothing catches you mid-air; you pass through the turning platforms.
- [ ] You can still be hit and can still hit others during the turn.
Notes:

### 4.6 A round start during the turn
- [ ] Have the last fighter of a round die while the stage turns (the next round comes 2.6 s after the last kill).
- [ ] The new round starts with everyone on solid platforms. Nobody falls through the floor at the spawn.
Notes:

### 4.7 Other screens
- [ ] Watch another player fall through the turning stage on your screen. They fall the same way on their own screen (ask them).
Notes:

### 4.8 Edge cases
- [ ] Shield up when the shift starts: you still fall.
- [ ] Egg form (druid stomp) when the shift starts: you still fall.
- [ ] Two shifts in a row (a new power-up right after the stage locks): the second shift also drops you, and the platforms are solid in between.
Notes:

### 4.9 Telemetry

| When | `🧗 [TopEdge]` line (full) or "none" |
|---|---|
| Whole session | |

`📈 [NetStats]` lines during and right after a shift (PC, and the phone from section 1 if the cable is in):

| Device | When | `draw=` | `phys=` | `worst=` | `hitches=` | `proc=` | `phys_cpu=` | `keys=` | `focus=` |
|---|---|---|---|---|---|---|---|---|---|
| PC | During a shift | | | | | | | | |
| PC | Right after the stage locked | | | | | | | | |
| Phone | During a shift | | | | | | | | |
| Phone | Right after the stage locked | | | | | | | | |

### 4.10 Verdict (section 4)
- [ ] The free fall and the tumble through the bottom feel fair. Keep it as it is; backlog 23 stays closed.
- [ ] The fall through the platforms is fine but the tumble through the bottom is too much (write why). Reopen backlog 23 as a feel change, for example a slower fall during the turn.
- [ ] The free fall feels bad (write why). Reopen backlog 9 and look at option B (wrap at the top during a turn).
- [ ] A `🧗 [TopEdge]` line showed during a shift. Reopen backlog 9 with the line pasted above.
Notes:

---

## 5. Movement bundles: do the puppets still feel right? (optimisation Step C, build 3)

**Why.** Until v0.0.35 the server sent every fighter's movement packet on its own: with 3 other fighters that was about 40 packets a second into every screen, and on the wire each one carries 40 to 50 B of headers around 11 B of game data ([[optimisation_step_b_profiles]], Profile 3). Since v0.0.36 the server holds the samples for up to 50 ms and sends them as ONE `sync_bundle` frame per screen, about 20 a second. The harness (`bundle` and `fleet` scenarios) says the puppets move as smoothly as before on the PC, with 25 ms more delay on average, hidden inside the 100 ms the puppets already render behind. Only a person can say whether it feels the same on a phone over Wi-Fi. Detail: [[v0.0.36 - Relay Packet Coalescing]].

### 5.1 Setup
- [ ] Build in the lobby is v0.0.36 or later (an older build is refused with VERSION MISMATCH).
- [ ] At least three fighters: you on the PC, you on a phone, and one bot (`godot --headless --path . -- --autojoin --ai=chaser --name=Bot1`). Four is better (add `--ai=rusher --name=Bot2`).
- [ ] PC console open (F12, Console, filter `NetStats`). Phone console over USB if you can (section 1 says how); otherwise write "no console".

### 5.2 Play two rounds and watch the other fighters
- [ ] The bot and the other screen's fighter glide; no stutter, no rubber-banding, no sliding after a stop.
- [ ] A dash, a jump and a landing on the other screen look like they did before v0.0.36 (nobody sinks into the floor after landing).
- [ ] The phone's fighter, watched from the PC: same as above.
- [ ] Arrows, firebolts and kunai still appear where the shooter is (those packets are not bundled).
- [ ] Anything that felt late or wrong, in your words:

### 5.3 The numbers
Paste one `📈 [NetStats]` line per device from the middle of a round. Read `IN … pkt/s`, then in the `in:` list `sync_bundle=N(…B)` and `sync_pos=M(…B)`, then the `puppets=` part. With 3 other fighters `IN` should be about 20 to 25 pkt/s (it was about 40), `sync_bundle` about 100 per 5 s line, `sync_pos` about 200.

| Device | Fighters in the game | `IN` pkt/s | `sync_bundle=` | `sync_pos=` | `jitter=` (mean/p95) | `snaps=` | `stall=` | `extrap=` | `dips=` | `keys=` | `focus=` |
|---|---|---|---|---|---|---|---|---|---|---|---|
| PC | | | | | | | | | | | |
| Phone (model) | | | | | | | | | | | |
| Second phone / tablet | | | | | | | | | | | |

Server side, one `[STATS 10s]` line from `server.log` (it now ends with `bundles=20.0/s x2.9` = bundles a second and mean entries per bundle):

| `OUT` pkt/s | `bundles=` | `in:` `sync_pos=` |
|---|---|---|
| | | |

### 5.4 Verdict (section 5)
- [ ] **The puppets feel the same and `IN` is about half of 40 pkt/s:** the bundle stays. Step C cut 3 is closed.
- [ ] **The puppets feel later or stutter (write where):** turn the bundle off without a client rebuild: `RELAY_BUNDLE_MS = 0` in `serve_game.py`, `systemctl --user restart towerbrawl`, play again; if the feel returns, the 50 ms window is too long for Wi-Fi, try 25.
- [ ] **`IN` is still about 40 pkt/s and there is no `sync_bundle=` in the `in:` list:** the server is not bundling; check the `[STATS]` line for `bundles=` and that the service restarted after the build.
Notes:

---

Related: [[PASSDOWN]] (backlog 1, 6, 13, 23; Step C), [[optimisation_step_b_profiles]], [[v0.0.34 - Mobile Frame Telemetry]], [[v0.0.36 - Relay Packet Coalescing]], [[v0.0.30 - Ranger Rejoin Quiver]], [[v0.0.28 - Rejoin in the Replay Gap]], [[v0.0.32 - Free-Fall Arena Shift]], [[v0.0.33 - Shift Tumble Kept]], [[Commands]] (the console lines and the USB console).

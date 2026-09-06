---
tags: [playtest]
build: v0.0.27
result: played 2026-09-04, the replay numbers stay, two new bugs in the replay gap
---
# Playtest v0.0.26 — the VHS replay on phone and PC

**Result: played on 2026-09-04 on build v0.0.27. The 6.5 s gap, the slow-motion window and the caption all stay as they are. Two new bugs, both when a screen reloads or wakes up inside the replay gap (backlog 13 in [[PASSDOWN]]; the server and lobby parts fixed in [[v0.0.28 - Rejoin in the Replay Gap]], the PC keyboard part carries a `keys= focus=` probe), and one vague stall report (backlog 14). The phone fps numbers are still missing (no console on the S25 Ultra).**54

This is our test sheet for the replay. We play the game on a phone and on a PC at the same time. After every round that ends on a kill, every screen plays the tape back. We look at each thing on the list. If it works, we tick the box like this: `[x]`. If it does not work, we leave it `[ ]` and write what we saw in the notes.

**How to start**
- Open `https://192.168.4.21:8443/play` on the phone and on the PC.
- If the browser console says VERSION MISMATCH, reload the page hard.
- Need more players? Start a bot: `godot --headless --path . -- --autojoin --ai=chaser --name=Bot1` (and `--ai=sniper --name=Bot2` for a second one).
- On the PC, run `tbdash` in a terminal. The `Tape` column shows `▶ R3` while a screen plays and `■ R3 ✓ ▶5.1s` after.
- Words we use: the **tape** is the last six seconds of the fight as your screen drew it. The **replay** plays that tape back. The **ghosts** are the fighters in the replay. The **kill** is the moment the round was won.

**What the replay does today (the numbers we are testing)**
- The server waits **6.5 s** between a round won on a kill and the next round (7.0 s after a won match, 2.6 s after a draw).
- The replay starts about **1 s** after the round ends and takes about **5 s**: rewind (0.4 s), play at full speed (2 s), **slow motion for 1 s before the kill and 1 s after, at half speed** (2 s), the fall (0.5 s), fade to black (0.2 s).
- A white flash marks the kill. A red ring sits on the victim in slow motion. The caption at the bottom says who killed whom and with what, for example `Godot2 killed Andrew · Firebolt`.

---

## 0. What we tested on

| Question                                           | Phone            | PC                         |
| -------------------------------------------------- | ---------------- | -------------------------- |
| Which device? (Android Chrome, iPhone, iPad, PC …) | S25 Ultra, Chrom | Omarchy/Hyprland, Chromium |
| How does it connect? (home Wi-Fi or cell data)     | Wi-Fi            |                            |
| Screen size (for example 1080 x 2400)              |                  |                            |
| Which class did you play?                          |                  |                            |

Notes:
-Wife and daughter played for about an hour and a half. Daughter on IPad using chrome, Wife on Google Pixel with chrome. They didn't do a focused playtest, just wanted to play and give feedback. Here are their notes:
	-The kill cam at the end is very cool, need a button to skip it and start the next round though. If any active player presses attack during the kill cam, it stops and kicks off the next round.
	-It's difficult to aim beyond just shooting straight ahead with virtual controls. The joystick needs to have variable speed instead of just full running every direction change.Need a deadzone, if the center stick, only rotate aim and don't move. Anything else you think could help optimize the feel for the virtual gamepad?
	-Virtual D-pad, there isn't a reason to stick the + structure for the moves and abilities. Just make them circles that are easier to input and in ergonomic places. It's hard currently to hit the correct button.
	-The air spawns seem to spawn people very close together. If both players died, they almost always spawned in the air right next to eachother. Need to check if someone else is dropping in or just check player positions in general and try to spawn dropping in players further away from other players.
	-The rounds go too fast. Balancing will probably help with that and level design and everything else, the game isn't real flushed out yet. One suggestion is to give everyone a charge of shield from the beginning. Each life you spawn with a shield that protects you, but doesn't reflect attacks or anything, If you get hit, your shield pops. The shield would last until you take a hit. Also have a power-up idea to regenerate your shield, either once or every 5 seconds for 15 seconds.
	-My wife went to another windows for a bit and on my daughter screen the game just wouldn't do anything. Figure out how to handle stalls better that don't impact gameplay and don't punish the stalled player too much.

---

## 1. The gap between rounds (6.5 s)

- [x] **Not too long.** Nobody presses keys or taps the screen waiting for the next round to start.
- [x] **Not too short.** The replay finishes (fade to black) before the new round starts. Nobody gets cut off in the middle of the slow motion.
- [x] **Match end.** After the last round of a match (7 s), the replay feels fine and the winner screen still shows up.
- [x] **Draw or forfeit.** When a round ends without a kill (both fall, or someone leaves), there is no replay and the next round comes fast (2.6 s).

Notes (too long, too short, or just right, and on which screen):
-Everything feels fine with the replay, just want to add a way to skip it and kick off the action. It's a nice way to punctuate a round end. Before, everything just kinda ran into eachother.

---

## 2. The slow-motion window

- [x] **You can see the kill.** In slow motion you can tell who hit whom and with what.
- [ ] **The shot is in the window.** For an arrow or a firebolt, the shot leaves the shooter *inside* the slow motion, not before it. (A firebolt flies longer than half a second. If the shot starts before the slow motion, write it down.)
- [x] **The flash.** The white flash lands on the hit, not before or after it.
- [x] **The ring.** The red ring sits on the fighter who died, not on the killer.
- [x] **The fall.** After the slow motion you see the body fall, then the fade.

Notes (which weapon, what was hard to see):
-We don't have death animations yet, once the hit happens, the character disappears. We do need death animations though

---

## 3. Reading the replay on a phone

Only the phone does this part. The PC is easy to read.

- [x] **Caption.** You can read `NAME killed NAME · WEAPON` at the bottom without leaning in.
- [x] **Labels.** You can read `◄◄ REW`, `► PLAY`, `► SLOW`, `■ STOP`, the counter (`-2.5s` to `+1.0s`) and the blinking `REPLAY`.
- [x] **Ghosts.** The scanlines, the rolling bar and the shake do not hide the ghosts. You can still see the name tags over them.
- [x] **Flash.** The white flash is not painful on the phone (try one round with the room dark).
- [x] **Notch.** The caption and the labels are not under the camera hole.

Notes (phone model, what was too small):
-Replay worked great on the phone. Only thing I can think of would be a possible future feature. Start the replay full screen and zoom in on the projectile or attack as it approaches the target. Mark that as a feature idea.

---

## 4. The paused world

While the tape plays, the live fighters are hidden and frozen. Watch for anything left over.

- [x] **Keys do nothing.** Press move, jump, attack during the replay. Nothing moves, nothing shoots, no sound of a hit.
- [x] **Clean new round.** When the new round starts everyone is in a bubble on a platform spot. Nobody is where they died, nobody is off screen.
- [x] **No leftovers.** No stuck arrow, no firebolt, no power-up hangs over from the old round on top of the ghosts or into the new round.
- [x] **Top bar.** The crowns, lives and names in the top bar do not change or flicker during the replay. The crown for the round shows up once.
- [x] **Spectator screen.** A spectator (a fifth screen, or a phone that pressed nothing) plays the replay too, from its own tape.
- [x] **Platforms.** The platforms in the replay sit at the angle they had at the kill, then jump back to the live angle for the new round without a wobble.

Notes:
-No issues with the paused state

---

## 5. Odd cases

Try these on purpose. Tick the box if the game handles it well.

- [ ] **Hidden tab.** On the phone, switch to another app for two seconds during a round, then come back. The next replay on that phone is skipped (console says `skipped=not-frozen`) or plays clean. It never plays a broken or empty tape.
- [x] **Kill while turning.** Win a round while the arena is spinning. The replay shows the platforms turning like they did.
- [x] **Kill on the seam.** Win a round with a fighter half off the left or right edge. The ghost is drawn on the right side.
- [x] **Two kills in one second.** A double kill or a kill right after another. The replay shows the last one (the closing kill) and the caption names the right people.
- [ ] **Reload during the replay.** Reload the page on the PC while a replay plays. You come back into the lobby or the arena without an error, and the next replay works.
- [x] **Late joiner.** Someone joins as a spectator in the middle of a round. Their first replay is skipped or short, never broken.

Notes:
-Reload during replay - I got the final kill, replay started, I refreshed, I spawned back to the next round round and aim works. I'm unable to move though. Refreshed again and still unable to move.
-Hidden tab - On replay - Phone changed apps during replay and came back ~2-3 seconds. PC went back to lobby after replay. Phone loaded into old arena at the point the final kill was. Phone unable to move or do anything had to refresh. If not during the kill cam, phone can tab over to another app then come back, in the middle of a round when the phone does this, it gets a round start message, then syncs up to the live positions.

---

## 6. Numbers to read afterwards

Open the browser console on each screen (on the phone, connect it to the PC or take a screenshot of the console). Copy the lines here.

- **Frame rate.** Every 5 s the `📈 [NetStats]` line ends with `fps draw=59.8 phys=60.0 worst=21ms hitches=0` (new in v0.0.27). `draw` is how many pictures a second the screen drew, `phys` is how many physics ticks, `worst` is the slowest single frame, `hitches` counts frames over 50 ms. Good on a PC: `draw` near 60, `worst` under 40 ms. Write the phone's numbers down during a replay and during a normal round.
- **Replay lines.** One `📼 [Replay]` line per playback: `frames=211 drawn=211 dur_ms=5050 late_ms=987 cut=0 skipped=-`. `drawn` well under `frames` means the screen was too slow to draw every tape frame. `cut=1` means the new round started before the fade. `skipped=` names why a replay did not play.
- **Server.** `grep "\[TAPE\].*replay" server.log | tail` lists every replay the server heard about, with how long it took and how late it started.
- **Deck.** On `tbdash`, click the round-end column: the line under the axis says `replay played on N screens`, how long, and how late.


I'll just dump the log from PC here. Unable to get to console from S25 Ultra

📈 [NetStats 5s] P2 Arena | IN   4.6 pkt/s   0.07 KB/s (avg  15 B) | OUT  17.8 pkt/s   0.22 KB/s (avg  13 B) | in: sync_pos=18(198B), pong=5(145B) | out: sync_pos=84(924B), ping=5(225B) | total in 33.7 KB out 52.7 KB over 613s | rtt 4 ms | puppets=1 jitter=0.0/0.0px/s snaps=0 wraps=0 stall=0.0% extrap=73.0% dips=0 pn=300 | fps draw=240.0 phys=60.0 worst=4ms hitches=0
index.js:452 📼 [Tape] round=3 frozen=0 closing=0 killer=2 victim=1 weapon=Arrow seq=5738 before=360 after=0 span_ms=5981 fps=60.0 stamps=2 frames=360
index.js:452 📈 [NetStats 5s] P2 Arena | IN   5.6 pkt/s   0.09 KB/s (avg  17 B) | OUT  21.2 pkt/s   0.33 KB/s (avg  16 B) | in: sync_pos=22(242B), pong=5(145B), player_died=1(80B) | out: sync_pos=98(1078B), ping=5(225B), spawn_projectile=1(9B), player_died=1(72B), history_status=1(327B) | total in 34.2 KB out 54.4 KB over 618s | rtt 4 ms | puppets=1 jitter=1.5/0.9px/s snaps=0 wraps=0 stall=0.0% extrap=63.7% dips=0 pn=226 | fps draw=239.8 phys=60.0 worst=5ms hitches=0
index.js:452 📼 [Tape] round=3 frozen=0 closing=0 killer=2 victim=1 weapon=Arrow seq=6008 before=360 after=0 span_ms=5981 fps=60.0 stamps=3 frames=360
index.js:452 📼 [Tape] round=3 frozen=1 closing=1 killer=2 victim=1 weapon=Arrow seq=6008 before=300 after=60 span_ms=5981 fps=60.0 stamps=3 frames=360
index.js:452 📈 [NetStats 5s] P2 Arena | IN   5.2 pkt/s   0.11 KB/s (avg  22 B) | OUT  16.6 pkt/s   0.43 KB/s (avg  27 B) | in: sync_pos=19(209B), pong=5(145B), player_died=1(80B), round_end=1(127B) | out: sync_pos=73(803B), ping=5(225B), history_status=3(1091B), spawn_projectile=1(9B), player_died=1(72B) | total in 34.7 KB out 56.5 KB over 623s | rtt 4 ms | puppets=1 jitter=0.5/2.2px/s snaps=0 wraps=0 stall=0.0% extrap=58.8% dips=0 pn=165 | fps draw=239.8 phys=60.0 worst=6ms hitches=0
index.js:452 📼 [Replay] round=3 killer=2 victim=1 weapon=Arrow from=5858 to=6068 frames=211 drawn=211 dur_ms=5047 late_ms=996 cut=0 skipped=-
index.js:452 🧭 [Spawn] round 4 flips=3 roster=[1, 2] spots=[(110.0, 116.0), (530.0, 116.0)]
index.js:452 📈 [NetStats 5s] P2 Arena | IN   2.6 pkt/s   0.05 KB/s (avg  20 B) | OUT   5.2 pkt/s   0.19 KB/s (avg  37 B) | in: sync_pos=7(77B), pong=5(145B), new_round=1(33B) | out: sync_pos=19(209B), ping=5(225B), history_status=1(482B), activate_powerup=1(53B) | total in 35.0 KB out 57.5 KB over 628s | rtt 4 ms | puppets=1 jitter=6.6/7.2px/s snaps=0 wraps=0 stall=0.0% extrap=41.9% dips=0 pn=43 | fps draw=240.0 phys=60.0 worst=5ms hitches=0
index.js:452 📈 [NetStats 5s] P2 Arena | IN   5.6 pkt/s   0.08 KB/s (avg  14 B) | OUT   5.4 pkt/s   0.09 KB/s (avg  17 B) | in: sync_pos=23(253B), pong=5(145B) | out: sync_pos=22(242B), ping=5(225B) | total in 35.4 KB out 57.9 KB over 633s | rtt 4 ms | puppets=1 jitter=0.0/0.0px/s snaps=0 wraps=0 stall=0.0% extrap=69.0% dips=0 pn=300 | fps draw=240.0 phys=60.0 worst=4ms hitches=0
index.js:452 📈 [NetStats 5s] P2 Arena | IN   4.6 pkt/s   0.07 KB/s (avg  15 B) | OUT   4.6 pkt/s   0.08 KB/s (avg  18 B) | in: sync_pos=18(198B), pong=5(145B) | out: sync_pos=18(198B), ping=5(225B) | total in 35.7 KB out 58.3 KB over 638s | rtt 4 ms | puppets=1 jitter=0.0/0.0px/s snaps=0 wraps=0 stall=0.0% extrap=74.7% dips=0 pn=300 | fps draw=239.8 phys=60.0 worst=5ms hitches=0
index.js:452 📈 [NetStats 5s] P2 Arena | IN   4.8 pkt/s   0.08 KB/s (avg  17 B) | OUT   4.6 pkt/s   0.08 KB/s (avg  18 B) | in: sync_pos=18(198B), pong=5(145B), spawn_powerup=1(54B) | out: sync_pos=18(198B), ping=5(225B) | total in 36.1 KB out 58.8 KB over 643s | rtt 4 ms | puppets=1 jitter=0.0/0.0px/s snaps=0 wraps=0 stall=0.0% extrap=73.7% dips=0 pn=300 | fps draw=240.0 phys=60.0 worst=4ms hitches=0
index.js:452 📈 [NetStats 5s] P2 Arena | IN   4.6 pkt/s   0.07 KB/s (avg  15 B) | OUT   4.6 pkt/s   0.08 KB/s (avg  18 B) | in: sync_pos=18(198B), pong=5(145B) | out: sync_pos=18(198B), ping=5(225B) | total in 36.4 KB out 59.2 KB over 648s | rtt 4 ms | puppets=1 jitter=0.0/0.0px/s snaps=0 wraps=0 stall=0.0% extrap=75.0% dips=0 pn=300 | fps draw=239.8 phys=60.0 worst=6ms hitches=0
index.js:452 📈 [NetStats 5s] P2 Arena | IN   4.6 pkt/s   0.07 KB/s (avg  15 B) | OUT   4.6 pkt/s   0.08 KB/s (avg  18 B) | in: sync_pos=18(198B), pong=5(145B) | out: sync_pos=18(198B), ping=5(225B) | total in 36.8 KB out 59.6 KB over 653s | rtt 4 ms | puppets=1 jitter=0.0/0.0px/s snaps=0 wraps=0 stall=0.0% extrap=74.7% dips=0 pn=300 | fps draw=239.8 phys=60.0 worst=7ms hitches=0
index.js:452 📈 [NetStats 5s] P2 Arena | IN   4.6 pkt/s   0.07 KB/s (avg  15 B) | OUT   4.6 pkt/s   0.08 KB/s (avg  18 B) | in: sync_pos=18(198B), pong=5(145B) | out: sync_pos=18(198B), ping=5(225B) | total in 37.1 KB out 60.0 KB over 658s | rtt 4 ms | puppets=1 jitter=0.0/0.0px/s snaps=0 wraps=0 stall=0.0% extrap=75.3% dips=0 pn=300 | fps draw=240.0 phys=60.0 worst=4ms hitches=0
index.js:452 📈 [NetStats 5s] P2 Arena | IN   4.6 pkt/s   0.07 KB/s (avg  15 B) | OUT   4.6 pkt/s   0.08 KB/s (avg  18 B) | in: sync_pos=18(198B), pong=5(145B) | out: sync_pos=18(198B), ping=5(225B) | total in 37.4 KB out 60.4 KB over 663s | rtt 4 ms | puppets=1 jitter=0.0/0.0px/s snaps=0 wraps=0 stall=0.0% extrap=75.3% dips=0 pn=300 | fps draw=240.0 phys=60.0 worst=5ms hitches=0
index.js:452 📈 [NetStats 5s] P2 Arena | IN   5.0 pkt/s   0.07 KB/s (avg  15 B) | OUT   4.8 pkt/s   0.08 KB/s (avg  18 B) | in: sync_pos=20(220B), pong=5(145B) | out: sync_pos=19(209B), ping=5(225B) | total in 37.8 KB out 60.8 KB over 668s | rtt 4 ms | puppets=1 jitter=0.0/0.0px/s snaps=0 wraps=0 stall=0.0% extrap=74.3% dips=0 pn=300 | fps draw=240.0 phys=60.0 worst=4ms hitches=0

| Screen | NetStats fps during a round | fps during a replay | worst / hitches | Replay line (`drawn`, `late_ms`, `cut`) |
| ------ | --------------------------- | ------------------- | --------------- | --------------------------------------- |
| PC     |                             |                     |                 |                                         |
| Phone  |                             |                     |                 |                                         |
| iPad   | N/A                         | N/A                 | N/A             | N/A                                     |

---

## 7. What we found

**What felt good:**
-Overall, gameplay feels solid, network is good, Wife and daughter both playing from wi-fi for an hour and a half is a testement to that. Replay looks great. 

**Bugs and weird things** (write the device and what happened):
-I think I documented all the bugs throughout the playtest. Check there.

**Verdict**
- [x] The 6.5 s gap stays as it is. If not, the new number: ___ s.
- [x] The slow-motion window (1 s before, 1 s after, half speed) stays. If not: ___ s before, ___ s after, speed ___.
- [x] The phone can read the caption and the labels. If not, what to make bigger: ___
- [x] Ready for the bug builds (backlog 10 egg puppet, backlog 1 and 6 ranger arrows, backlog 9 stuck at the top). If a replay fix comes first, it ships as the next build.

---
Earlier sheets: [[Playtest v0.0.17]] · [[Playtest v0.0.8]] · [[Playtest v0.0.5]] · Builds: [[v0.0.26 - Play the Tape]] · Start here: [[PASSDOWN]]

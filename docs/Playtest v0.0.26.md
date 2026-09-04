---
tags: [playtest]
build: v0.0.27
result: not played yet
---
# Playtest v0.0.26 — the VHS replay on phone and PC

**Result: not played yet. Play on build v0.0.27 or newer (it has the fps numbers in the console).**

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

| Question                                           | Phone | PC |
| -------------------------------------------------- | ----- | -- |
| Which device? (Android Chrome, iPhone, iPad, PC …) |       |    |
| How does it connect? (home Wi-Fi or cell data)     |       |    |
| Screen size (for example 1080 x 2400)              |       |    |
| Which class did you play?                          |       |    |

Notes:
-

---

## 1. The gap between rounds (6.5 s)

- [ ] **Not too long.** Nobody presses keys or taps the screen waiting for the next round to start.
- [ ] **Not too short.** The replay finishes (fade to black) before the new round starts. Nobody gets cut off in the middle of the slow motion.
- [ ] **Match end.** After the last round of a match (7 s), the replay feels fine and the winner screen still shows up.
- [ ] **Draw or forfeit.** When a round ends without a kill (both fall, or someone leaves), there is no replay and the next round comes fast (2.6 s).

Notes (too long, too short, or just right, and on which screen):
-

---

## 2. The slow-motion window

- [ ] **You can see the kill.** In slow motion you can tell who hit whom and with what.
- [ ] **The shot is in the window.** For an arrow or a firebolt, the shot leaves the shooter *inside* the slow motion, not before it. (A firebolt flies longer than half a second. If the shot starts before the slow motion, write it down.)
- [ ] **The flash.** The white flash lands on the hit, not before or after it.
- [ ] **The ring.** The red ring sits on the fighter who died, not on the killer.
- [ ] **The fall.** After the slow motion you see the body fall, then the fade.

Notes (which weapon, what was hard to see):
-

---

## 3. Reading the replay on a phone

Only the phone does this part. The PC is easy to read.

- [ ] **Caption.** You can read `NAME killed NAME · WEAPON` at the bottom without leaning in.
- [ ] **Labels.** You can read `◄◄ REW`, `► PLAY`, `► SLOW`, `■ STOP`, the counter (`-2.5s` to `+1.0s`) and the blinking `REPLAY`.
- [ ] **Ghosts.** The scanlines, the rolling bar and the shake do not hide the ghosts. You can still see the name tags over them.
- [ ] **Flash.** The white flash is not painful on the phone (try one round with the room dark).
- [ ] **Notch.** The caption and the labels are not under the camera hole.

Notes (phone model, what was too small):
-

---

## 4. The paused world

While the tape plays, the live fighters are hidden and frozen. Watch for anything left over.

- [ ] **Keys do nothing.** Press move, jump, attack during the replay. Nothing moves, nothing shoots, no sound of a hit.
- [ ] **Clean new round.** When the new round starts everyone is in a bubble on a platform spot. Nobody is where they died, nobody is off screen.
- [ ] **No leftovers.** No stuck arrow, no firebolt, no power-up hangs over from the old round on top of the ghosts or into the new round.
- [ ] **Top bar.** The crowns, lives and names in the top bar do not change or flicker during the replay. The crown for the round shows up once.
- [ ] **Spectator screen.** A spectator (a fifth screen, or a phone that pressed nothing) plays the replay too, from its own tape.
- [ ] **Platforms.** The platforms in the replay sit at the angle they had at the kill, then jump back to the live angle for the new round without a wobble.

Notes:
-

---

## 5. Odd cases

Try these on purpose. Tick the box if the game handles it well.

- [ ] **Hidden tab.** On the phone, switch to another app for two seconds during a round, then come back. The next replay on that phone is skipped (console says `skipped=not-frozen`) or plays clean. It never plays a broken or empty tape.
- [ ] **Kill while turning.** Win a round while the arena is spinning. The replay shows the platforms turning like they did.
- [ ] **Kill on the seam.** Win a round with a fighter half off the left or right edge. The ghost is drawn on the right side.
- [ ] **Two kills in one second.** A double kill or a kill right after another. The replay shows the last one (the closing kill) and the caption names the right people.
- [ ] **Reload during the replay.** Reload the page on the PC while a replay plays. You come back into the lobby or the arena without an error, and the next replay works.
- [ ] **Late joiner.** Someone joins as a spectator in the middle of a round. Their first replay is skipped or short, never broken.

Notes:
-

---

## 6. Numbers to read afterwards

Open the browser console on each screen (on the phone, connect it to the PC or take a screenshot of the console). Copy the lines here.

- **Frame rate.** Every 5 s the `📈 [NetStats]` line ends with `fps draw=59.8 phys=60.0 worst=21ms hitches=0` (new in v0.0.27). `draw` is how many pictures a second the screen drew, `phys` is how many physics ticks, `worst` is the slowest single frame, `hitches` counts frames over 50 ms. Good on a PC: `draw` near 60, `worst` under 40 ms. Write the phone's numbers down during a replay and during a normal round.
- **Replay lines.** One `📼 [Replay]` line per playback: `frames=211 drawn=211 dur_ms=5050 late_ms=987 cut=0 skipped=-`. `drawn` well under `frames` means the screen was too slow to draw every tape frame. `cut=1` means the new round started before the fade. `skipped=` names why a replay did not play.
- **Server.** `grep "\[TAPE\].*replay" server.log | tail` lists every replay the server heard about, with how long it took and how late it started.
- **Deck.** On `tbdash`, click the round-end column: the line under the axis says `replay played on N screens`, how long, and how late.

| Screen | NetStats fps during a round | fps during a replay | worst / hitches | Replay line (`drawn`, `late_ms`, `cut`) |
| ------ | --------------------------- | ------------------- | --------------- | --------------------------------------- |
| PC     |                             |                     |                 |                                         |
| Phone  |                             |                     |                 |                                         |
| iPad   |                             |                     |                 |                                         |

---

## 7. What we found

**What felt good:**
-

**Bugs and weird things** (write the device and what happened):
-

**Verdict**
- [ ] The 6.5 s gap stays as it is. If not, the new number: ___ s.
- [ ] The slow-motion window (1 s before, 1 s after, half speed) stays. If not: ___ s before, ___ s after, speed ___.
- [ ] The phone can read the caption and the labels. If not, what to make bigger: ___
- [ ] Ready for the bug builds (backlog 10 egg puppet, backlog 1 and 6 ranger arrows, backlog 9 stuck at the top). If a replay fix comes first, it ships as the next build.

---
Earlier sheets: [[Playtest v0.0.17]] · [[Playtest v0.0.8]] · [[Playtest v0.0.5]] · Builds: [[v0.0.26 - Play the Tape]] · Start here: [[PASSDOWN]]

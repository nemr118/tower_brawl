---
tags: [playtest]
build: v0.0.17
result: done, fixes first (v0.0.18+)
---
# Playtest v0.0.17 — real people on phone and PC

**Result: done on 2026-09-03. Movement and phone helpers pass. Not ready for Phase 3c yet: fix builds first, starting with v0.0.18.**

This is our test sheet. We play the game on a phone and on a PC at the same time. We look at each thing on the list. If it works, we tick the box like this: `[x]`. If it does not work, we leave it `[ ]` and write what we saw in the notes.

**How to start**
- Open `https://192.168.4.21:8443/play` on the phone and on the PC.
- If the browser console says VERSION MISMATCH, reload the page hard.
- Need more players? Start a bot: `godot --headless --path . -- --autojoin --ai=chaser --name=Bot1` (and `--ai=sniper --name=Bot2` for a second one).
- Words we use: the **puppet** is the other player's fighter as drawn on *your* screen. The other player moves it. Your screen only copies it.

---

## 0. What we tested on

| Question                                           | Phone                           | PC              |
| -------------------------------------------------- | ------------------------------- | --------------- |
| Which device? (Android Chrome, iPhone, iPad, PC …) | Android Chrome                  | Chromium        |
| How does it connect? (home Wi-Fi or cell data)     | Wi-Fi                           | Wired to router |
| Screen size (for example 1080 x 2400)              | Unsure, it's a Galaxy S25 Ultra | 3440x1440       |
| Which class did you play?                          | Multiple                        | Multiple        |

Notes:
- Played many rounds with my son and daught and some with bots and my son. I played on my PC running Omarchy/Chromium, My son on my phone, Galaxy S25 Ultra with chrome, Daughter on an IPad Pro, I think the browser was safari, but it could have been chrome.

---

## 1. Phone screen and turning (new in v0.0.16)

Only the phone does this part. A PC never shows these signs.

- [x] **Tap sheet.** The dark sheet that says "Tap to play full screen" pops up right away on the phone.
- [x] **Fill and turn.** Tap the sheet. The game fills the whole screen and the phone turns sideways. (Android does both. An iPad fills the screen but does not turn. An iPhone does neither. That is expected, not a bug.)
- [x] **Upright sign.** Hold the phone upright. The "Please turn your phone sideways" sign shows up. Turn the phone sideways again and the game comes right back.
- [x] **Corner button.** Leave full screen. The little corner button (⛶) shows up. Tap it and the game fills the screen again.
- [x] **Notch check.** The camera hole does not cover up any player buttons, health, or scores.

Notes (what kind of phone, what happened):
- Galaxy S25 Ultra
	- When full screen and turning sidesway on Galaxy, the game stays landscape (Which is fine)
	- When game isn't full screen and turns sideways, the message is displayed
- Linux/Chromium
	- Overlay for full screen comes up. When you click, it changes the game to full screen
- IPad/Safari or it might have been chrome
	- Everything worked perfectly

---

## 2. Jumps and landing on platforms (fixed in v0.0.17)

Watch the other player's puppet while they jump.

- [x] **Small hop.** Hop onto a platform and stand still. The puppet lands flat on top. It does not dip into the floor or fall through it.
- [x] **Fast stop.** Run on a platform, then stop. The puppet stops right away. It does not slide forward.
- [x] **Top of the screen.** Jump or dash off the very top edge. The puppet stays up high. It does not flash near the bottom floor.

Notes:
- Omarchy/Linux 
	- When on platforms, I occasionally couldn't jump with w. It was like I was attached to the platform. I could walk back and forth, but not jump. Once I walked off the platform or dashed, I was able to jump. It wasn't every time, but it happened occasionally.add

---

## 3. Moving and screen edges (Phase 3b)

- [x] **Walking and running.** The puppet moves smoothly. No shaking, no jitter.
- [x] **Screen edge.** Walk or dash off the left or right edge. The puppet pops to the other side in one clean step. It does not streak all the way across.
- [x] **Teleports.** A mage blink, or a player coming back after dying, snaps to the new spot in one step. No sliding.

Notes:
- All devices
	- Walking/aiming/jumping all feels smooth. If I try to use controls while watching another players screen, it's playable, but there is a noticeable about of lag. It's not terrible and functional, but it's definately noticable.
	- Screen edge
		- The character is always on one side or other, never split. It leads to what feels like invisable area's where the character is displayed clearly. It's almost invisable. My daughter loved to exploit this by infinitely falls through the most edge case she could get while spamming rangled attacks across the arena.
	- Teleports
		- There's a minor amount of slide, it's not terrible though

---

## 4. Attacks and hits

- [x] **Hits land on the body.** Swing, slash, stomp or shoot at a moving puppet. The hit lands where the puppet is drawn, not in empty space behind it.
- [x] **Shield and dash stay on.** When a puppet dashes or holds up a shield, the picture stays stuck to its body while it moves.

Notes:
- All devices
	- Hits land close to where the puppet is drawn. It's not exact, and it's hard to measure. It is noticable though.
	- Shields and dash look good while moving
		- One annoying thing is shielding while in air causes all directional jump momentum to stop and fall straight downward.

---

## 5. Watch list (open questions 9 and 10 in PASSDOWN)

These are things we are not sure about yet. Tick the box if it looks fine. If it looks wrong, write what you saw.

- [x] **Stuck at the top.** Nobody gets stuck or pinned floating near the top of the screen around the middle of the arena.
- [ ] **Druid egg.** When a druid turns into an egg, the egg moves and falls normally on the other screen.

Notes:
- All devices
	- Unable to verify egg. If a player hit's the phoenix, they are killed and the druid stays a phoenix. I believe this is the same knight shield logic. The hit isn't registered on the druid and the phoenix just stays a build until the duration ends. Unable to enter egg form.

---

## 6. Server and console health

- [x] **Server line.** The server log (`server.log`) prints `players=N spectators=M sockets=N+M` with the right numbers.
- [x] **Browser console.** No red error text on the phone or the PC. Lines that start with `[shell]` are normal notes. They are fine.

Notes:
- Server log looks good. One thing to modify is the number of bots. as an example players=4(2 bots). That would be nice to know, if there's no adverse effects. Also similar logic for spectators and total sockets.

---

## 7. What we found

**What felt good:**
- Overall, the game was playable and felt decent if you were only looking at your screen. There is very little data per sec according to the logs. I'd be ok with increasing data or polling or modifying the netcode to increase the real position.

**Bugs and weird things** (write the device and what happened):
- We don't have many angled surfaces in the arena, but I noticed during arena rotations that it felt like you slipped off angled platforms too easily. Would be nice to have "traction" or something that made that more predictable if you jump to an angled surface. Slower sliding depending on the angle.
- We played with bots for a bit. The bots seems fine for a first pass. They weren't incredibly hard or easy for my kids. We had issues with bots not locking in after a match had concluded or a match was disrupted in some way. Ideally, the bots at chamption select lock in once all players have locked in. I had to restart the bots multiple times. 
	- It would also be nice to have a button in game to fill the server with random persona bots. 
- I had one instance of typing up patch notes on the PC while I was in a match with my son and desyncing from the match. I don't remember the details exactly but it did happen once. 
- Archer arrows have conditions where they can be completely consumed, leaving the player with no ammo and no way to reclaim. One condition is killing another player, the arrow is consumed. Ideally, the arrow falls to the ground.
- Arrows stuck in platforms when the arena rotates are stuck in the same position, leading to some being unobtainable, or just floating in space. Need to figure out the best way to handle this. 
- Archer arrow stock is indicated for the client only. Everyone else see's the Archer as always having full ammo, even when they are empty.
- When the arena is upside down, players can spawn on top of the floor, out of view, which is annoying. It's also easy to get up there and hide with almost nothing but a few pixels indicating you are there. 
- Balance note, Archer seems at a major disadvantage compared to other classes ranged abilities. Other classes get spammable ranged attacks that don't consume ammo and don't have to reclaim spent rounds. 
- Visual note, unable to tell the difference between arrows you can pick up and your enemies arrows. Either need to be able to steal your foes arrows or clearly indicate when players arrows are whose.
- Visual note, with multiple people playing the same character it's very hard to keep track of your character.
- Visual note, it would be great to see a hovering P1, P2, P3, P4 or player names over their character in the match. 
- Crown counter isn't visable or doesn't function. Just shows the crown icon and no indication of the standings
- Unable to change player names. My daughter originally played on my phone and I set her name to "Tav", when she joined on the IPad, she also selected "Tav". Both characters had the same name, and were playing the same class at time leading to extremely confusing sequences
- In the log, when players kill each other, verify player names are also captured.
- 

**Verdict**
- [ ] Ready for Phase 3c: **not yet**
- If no, which fixes come first (they ship as v0.0.18 and up):
  - **v0.0.18 (shipped):** bubble spawn (random spot in the upper middle air, shield bubble, pops after 5 s / on the ground / on any attack), arrows that kill fly on and stick, stuck arrows turn with the platforms, bots lock in again after a match, crown number and first letter of names show in the top bar, R key crown wipe removed, `🪤 [JumpTrap]` console line for the W jump bug. See [[v0.0.18 - Playtest Fixes: Bubble Spawn, Arrows, Bots, HUD]].
  - **v0.0.19 (proposed, "Who is who"):** name tags over fighters, no two players with the same name, change your name in the lobby.
  - **Later:** seam hiding, archer kit and ammo sync, fill-with-bots button, bot count in the log line, slope traction, air shield feel, hiding on top of the flipped ground. The full list lives in [[PASSDOWN]].

---
Earlier sheets: [[Playtest v0.0.8]] · [[Playtest v0.0.5]] · Builds: [[v0.0.16 - Mobile fullscreen and landscape lock support]], [[v0.0.17 - Hotfix: prevent puppet floor clipping on jump landing]] · Start here: [[PASSDOWN]]

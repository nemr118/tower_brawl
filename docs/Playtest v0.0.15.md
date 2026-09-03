---
tags: [playtest]
build: v0.0.15 / v0.0.16 / v0.0.17
result: not done yet
---
# Playtest v0.0.15 / v0.0.16 / v0.0.17 — real people on phone and PC

**Result: (fill in when done: pass / fail)**

This is our test sheet. We play the game on a phone and on a PC at the same time. We look at each thing on the list. If it works, we tick the box like this: `[x]`. If it does not work, we leave it `[ ]` and write what we saw in the notes.

**How to start**
- Open `https://192.168.4.21:8443/play` on both the phone and the PC.
- If the browser console says VERSION MISMATCH, reload the page hard.
- Need more players? Start a bot: `godot --headless --path . -- --autojoin --ai=chaser --name=Bot1` (and `--ai=sniper --name=Bot2` for a second one).
- Words we use: the **puppet** is the other player's fighter as drawn on *your* screen. The other player moves it; your screen only copies it.

---

## 1. What we tested on

| Question                                                             | Phone | PC  |
| -------------------------------------------------------------------- | ----- | --- |
| Which device? (Android Chrome, iPhone Safari, iPad, PC Chromium ...) |       |     |
| How does it connect? (home Wi-Fi or cell data)                       |       |     |
| Screen size (for example 1080 x 2400)                                |       |     |
| Which class did you play?                                            |       |     |

Notes:
- 

---

## 2. Phone screen and turning (v0.0.16)

Only the phone does this part. A PC never shows these signs.

- [ ] **Tap sheet.** The dark sheet that says "Tap to play full screen" showed up right away when the page opened, even while the game was still loading.
- [ ] **Fill the screen and turn.** One tap made the game fill the whole screen. The phone turned sideways by itself. (Android should do both. An iPad fills the screen but does not turn. An iPhone does neither. That is expected, not a bug.)
- [ ] **Upright sign.** Hold the phone upright. The "Please turn your phone sideways" sign pops up. Turn the phone sideways again and the game comes right back.
- [ ] **Leave and come back.** Swipe to leave full screen. The little button in the top right corner appears. Tap it and the game fills the screen again.
- [ ] **Camera notch and edges.** The game picture goes cleanly under the camera hole. No buttons and no score text are cut off at the edges.

Notes (what kind of phone, what happened):
- 

---

## 3. Puppet movement and smoothness (v0.0.15, Phase 3b)

Watch the other player's puppet on your screen while they move.

- [ ] **Walking and running.** The puppet moves smoothly. No shaking, no jitter, no little jumps back and forth.
- [ ] **Screen edge wrap.** When a player walks or dashes off the left or right edge, the puppet pops to the other side in one step. It does not glide or streak all the way across the arena. Try it while dashing too.
- [ ] **Quick stops.** When a moving player stops, the puppet stops cleanly. It does not slide forward or bounce back.
- [ ] **Landing (v0.0.17 hotfix).** Hop onto a platform and stand still. The puppet lands on top of the platform and stays there. It does not sink into the platform and pop back up.
- [ ] **Jumping and falling.** Jumps look smooth. Falling through the gap at the bottom looks clean and the puppet does not get stuck falling in a loop.
- [ ] **Small delay.** The puppet is drawn a tenth of a second late on purpose. Stand next to each other and jump at the same time. The other jump starts a little late, but always by the same tiny amount, never more, never less.
- [ ] **Stand still, then go.** Stand still for 3 seconds, then sprint. The puppet starts moving right away (within about a blink). It does not wait and then jump ahead.

Notes:
- 

---

## 4. Fighting and hits

- [ ] **Hits land where the body is.** Swing a sword, slash, stomp or shoot an arrow at a moving puppet. The hit lands where the puppet is drawn. You never hit a "ghost" behind it, and you never miss a body you clearly touched.
- [ ] **Dash and shield stay glued on.** When a puppet dashes or holds up a shield, the dash and shield pictures stay on the body. A puppet in the middle of a dash cannot be killed. A knight with the shield up blocks the hit.
- [ ] **Blink and respawn snap.** When a mage blinks, or when someone comes back after dying, the puppet snaps to the new spot in one step. It does not slide across the room.
- [ ] **Druid shapes.** When a druid turns into the egg or the bear, the drawn puppet changes shape at the right moment, not early.

Notes:
- 

---

## 5. Connection and server

- [ ] **Weak signal.** Use cell data, or walk the phone away from the router until the `rtt` number in the console NetStats line goes above about 150 ms. The puppet may keep running straight for a split second and then freeze. It must never glide across an edge or jump around when the packets catch up. Write down `jitter=` and `extrap=` from that phone's NetStats line here: 
- [ ] **Leave and rejoin.** Close the phone tab in the middle of a match and open it again. The other puppets come back clean. Your own fighter does not shake on the PC after you return.
- [ ] **Server log line.** Look at the server terminal (`server.log`). The `[STATS]` line shows the right numbers: `players=N spectators=M sockets=N+M`.
- [ ] **Browser console.** No red errors on the phone or the PC. Lines that start with `[shell]` are just notes about what the phone could not do. They are fine. The NetStats line shows up every 5 seconds with `puppets=` filled in.

Notes:
- 

---

## 6. What we found

**What felt good:**
- 

**Bugs and weird things** (write the device and what happened):
- 

**Verdict**
- [ ] Ready for Phase 3c: **yes / no**
- If no, which fixes come first (they ship as v0.0.17 and up):
  - 

---
Earlier sheets: [[Playtest v0.0.8]] · [[Playtest v0.0.5]] · Builds: [[v0.0.15 - Harness Quality Gate & Spectator Count]], [[v0.0.16 - Mobile fullscreen and landscape lock support]] · Start here: [[PASSDOWN]]

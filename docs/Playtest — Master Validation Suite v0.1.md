---
tags: [playtest]
build: v0.1.4 (sections 1 to 4 on v0.1.1 or later, section 5 on v0.1.2 or later, sections 6 and 7 on v0.1.4 or later: the v0.1.3 duck flickered)
backlog: 25 (the speed burst), the kill cam circle (fixed in v0.1.1), the phone controller revamp, 27 (the respawn death, server fix), cut 1 (the first replay hitch and the lobby frames, v0.1.2), the tower arena and the pacing (v0.1.3), the twin sticks and the duck fix (v0.1.4)
result: open (started 2026-09-08)
---
# Playtest — Master Validation Suite v0.1

**Result: open.** The second master sheet. The first one ([[Playtest — Master Validation Suite]], archived) signed off v0.1.0 on 2026-09-07. This one starts with the two phones' first match that same night (23:32 to 23:36 on the laptop, S25 Ultra against a Pixel): three things came out of it, and v0.1.1 answers them. Each section has its own verdict, so one section per evening is fine.

**No console, no cable.** Every phone sends its numbers to the server every 5 s. You write clock times (the PC clock, HH:MM) and tick boxes. Afterwards, from the PC: `tools/pull_laptop_logs.sh <laptop ip>`, then `./venv/bin/python tools/stats_table.py --file playtest_logs/<folder>/client_stats.jsonl --list` and `--match N`. The phones cannot be told apart by model (Chrome hides it): the S25 Ultra is the 3123 x 1443 screen, the Pixel is 2406 x 1080, and the names and addresses do the rest.

## 0. Setup (once per evening)

| Field | Your answer |
|---|---|
| Date and time | |
| Build shown in the lobby (must be v0.1.1 or later) | |
| Phones in the game (who is on which) | |
| Server (the laptop, or the PC's service) | |

### 0.1 Match log

| # | Start (HH:MM) | End (HH:MM) | Who, on what | What you noticed |
|---|---|---|---|---|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

---

## 1. The phone controller (v0.1.1)

What changed. The four buttons are round now and sit on an arc under the right thumb: ATK (the big one, where the thumb rests), JUMP next to it toward the bottom, SPEC above, DASH at the far end. A touch goes to the nearest button, so the gap between two buttons is no longer "jump wins". The stick has a small inner ring: with the thumb inside the ring the fighter aims (the yellow line) and does not walk; past the ring it walks and aims the same way. The aim goes all the way round, not in eight steps, and it stays where the thumb left it when you lift off.

### 1.1 Buttons (both phones, one round each at least)
- [ ] Press ATK ten times in a row, fast. Count the jumps you did not mean to do: 
- [ ] Press JUMP ten times in a row. Count the attacks you did not mean to do: 
- [ ] Can you reach SPEC and DASH without moving your grip on the phone? (yes / a stretch / no): 
- [ ] Slide the thumb from ATK onto JUMP without lifting. Did the jump fire? (yes / no): 
- [ ] Is any button too close to the bottom edge for the phone's swipe bar? (write which): 

### 1.2 The stick and the aim
- [ ] Stand still, tilt the stick a little (inside the yellow ring) and turn it all the way round. Does the aim line follow smoothly, with no snapping to eight directions? (yes / no): 
- [ ] Inside the ring, does the fighter stay put? (yes / it creeps): 
- [ ] Push past the ring. Does the fighter walk where the stick points and does the aim stay with it? (yes / no): 
- [ ] Aim up-right, lift the thumb, then press ATK. Did the shot go up-right? (yes / it went sideways): 
- [ ] Rogue only: count your deaths to your own kunai over one match (the first night was 9 of 14): 

### 1.3 Feel
| Question | S25 Ultra | Pixel |
|---|---|---|
| Buttons: hit what you meant (always / mostly / often not) | | |
| Stick: the ring size (too small / right / too big) | | |
| Stick: the travel (too short / right / too long) | | |
| Anything you miss from the old layout | | |

### 1.4 Verdict (section 1)
- [ ] **Pass:** the wrong-button count in 1.1 is 0 or 1 out of ten on both phones, and 1.2 is all yes. The layout stays.
- [ ] **Buttons pass, aim short:** aiming backward while running forward is the one thing missing. Next: a right-hand aim stick as a toggle (twin-stick), flick to throw.
- [ ] **Buttons still miss:** write which pair in the notes. Next: move or grow that pair (the numbers live in `scripts/touch_controls.gd` `BUTTONS`).
- [ ] **The ring is wrong:** too small (walks when you meant to aim) or too big (aims when you meant to walk). Next: `AIM_RING` in `scripts/touch_controls.gd` (0.40 now).
Notes:

---

## 2. The kill cam circle (fixed in v0.1.1)

The bug. When the winner's own kunai came back and killed them inside the second after the round ended, the replay drew its red circle on the winner and the server line said "no closing kill" (rounds 2 and 7 on 2026-09-07). Now the replay and the card always name the kill that ended the round.

- [ ] Win a round, then die on purpose right after (jump off, or catch your own kunai). Watch the replay: the red circle is on the fighter you knocked out, not on you. Clock time: 
- [ ] Win a round cleanly. The circle is on the fighter you knocked out. Clock time: 
- [ ] Afterwards, from the PC: `grep "froze the round" playtest_logs/<folder>/server.log` shows no "no closing kill" for those rounds.

### 2.1 Verdict (section 2)
- [ ] **Pass:** both boxes right, no "no closing kill" line for a round with a kill. Close it.
- [ ] **Fail:** write the clock time and which fighter was circled. The code: `report_stamp()` in `scripts/history_ring.gd`.

---

## 3. The speed burst (backlog 25)

What was seen. "At the start of one round my character seemed to go into super speed for a second or two, then it was normal" (S25 Ultra, 2026-09-07). Run speed is 220 px/s and a dash is 550 for 0.14 s, so the code has no way to do this for that long. v0.1.1 adds a probe: whenever the fighter really moves faster than 300 px/s sideways outside a dash, the phone prints one `🏃 [Speed]` line a second to its own console. A phone has no console, so the line also has to be read another way: for now, the clock time and the round number are what we need, and a Rogue on the S25 Ultra is the setup that saw it.

- [ ] It happened again. Clock time (HH:MM) and round number: 
- [ ] What were you doing the second before (standing in the start bubble, walking, dashing, just landed): 
- [ ] Was the DASH button under your thumb at the time? (yes / no / not sure): 
- [ ] Which way did the fighter go, and did it stop on its own or when you let go of the stick: 
- [ ] It did not happen in the whole evening (how many rounds): 

The night soak of 2026-09-08 (four bots, 190 rounds) printed 520 Speed lines, all short slides on tilted pieces, none longer than half a second. So a bot does not do it; the touch layer or the phone is still the suspect.

### 3.1 Verdict (section 3)
- [ ] **Seen again with a clock time:** next build sends the `🏃 [Speed]` line to the server like the NetStats card, so it can be read from the PC.
- [ ] **Not seen in two evenings:** close backlog 25 as fixed by the new button hit test (the dash-chain theory: the old drag handler re-pressed DASH whenever a thumb wobbled on its edge).
Notes:

---

## 4. The respawn death (backlog 27, server fix of 2026-09-08)

The bug. When a fighter died, came back 1.2 s later and was killed again right away (the first attack pops the spawn bubble), the server threw the second death away as a repeat of the first. The fighter stayed dead on its own screen and alive on the server, so the round could never end. Four bots hit it once in the night and the round ran 13 h. The server's repeat window is now 0.6 s (was 1.5 s), and a harness test does exactly this. This section is the human version: the way a real thumb does it.

- [ ] For one whole round, the moment you come back after a death, mash ATK and run at the other fighter. Try to die again as fast as you can. How many times did you die within a second or two of coming back: 
- [ ] Did the lives number on the HUD go down every time you died? (yes / no, write the clock time): 
- [ ] Did anyone stay dead on their screen while the round kept going? (no / yes, clock time and who): 
- [ ] Afterwards, from the PC: `grep "\[KILL\]" playtest_logs/<folder>/server.log` shows one line per death that counted, with the lives going down one at a time, and `grep "\[ROUND\]" playtest_logs/<folder>/server.log` shows every round ending.

### 4.1 Verdict (section 4)
- [ ] **Pass:** every quick second death took a life and no one stayed dead. Close it; backlog 27 stays closed.
- [ ] **Fail:** write the clock time and who. v0.1.2 adds the client's own safety net: a fighter whose death got no answer for one second comes back by itself (`🩹 [SelfRespawn]` in the console). If someone still stayed dead on v0.1.2, backlog 28 (a round clock) moves up.
Notes:

---

## 5. Cut 1: the first replay and the lobby (v0.1.2)

What was seen. On the first night the first replay of the match stuttered on both phones (an 89 ms frame on the S25 Ultra, 52 ms on the Pixel), and the S25's lobby froze for a moment when the other phone joined and when both locked in (two frames over 50 ms). Later replays and the fight itself were smooth.

What changed. The lobby's icons were 1024 px pictures drawn at 30 px, loaded fresh on every join, lock and reveal; they are 256 px now and loaded once. The letters the replay overlay and the "knocked out" banner use are drawn once, off-screen, when the arena loads, so the first time they show on screen costs nothing. The replay's ghost fighters are built when the arena loads, not when the first replay starts. Every replay now reports three numbers to the server: `start_ms`, `tick_ms` (how long the replay took to start, script side) and `first_ms` (the slowest of its first three drawn frames).

- [ ] Play one full match on both phones. Clock time of the match start (HH:MM): 
- [ ] The first replay of the match: did it start with a visible stutter? (no / yes, on which phone): 
- [ ] In the lobby, when the other phone joined and when both locked in: did the screen freeze for a moment? (no / yes, when): 
- [ ] Afterwards, from the PC: `tools/pull_laptop_logs.sh <laptop ip>`, then `grep '"kind":"replay"' playtest_logs/<folder>/client_stats.jsonl`: one line per replay per phone. Write the round 1 numbers: S25 `first_ms` / `tick_ms`:  · Pixel `first_ms` / `tick_ms`: 
- [ ] `./venv/bin/python tools/stats_table.py --file playtest_logs/<folder>/client_stats.jsonl --match N --by-round`: round 1 `hitches` on both phones (was 2 and 1):  · the lobby cards' `proc` around the join and the locks (`--from HH:MM --to HH:MM`; was 21 to 22 ms): 

### 5.1 Verdict (section 5)
- [ ] **Pass:** round 1 has no hitch on either phone (`hitches=0`, every `first_ms` under 34, two frames), and the lobby cards at the join and the locks stay under 12 ms `proc`. Cut 1 is done.
- [ ] **The replay still stutters:** write `first_ms` and `tick_ms`. A big `tick_ms` is the script side (the freeze and the tape card); a big `first_ms` with a small `tick_ms` is the draw side (next suspect: the ghost fighters' first draw, then a shader).
- [ ] **The lobby still freezes:** write which moment (join / lock / reveal) and the `proc`. Next: the label text (`scripts/font_warmup.gd` pairs) or the roster rebuild in `scripts/character_select.gd`.
Notes:

---

## 6. The tower (v0.1.3)

What changed. The arena is a tower now: one screen wide, three screens tall, with hard walls just outside the screen. A hole in the middle of the floor drops you out of the bottom and in through the ceiling; a hole in the ceiling does the reverse (a jump plus an upward dash from the top ledges). Two passages through the side walls, one in the upper part (just under the two long ledges near the top) and one in the lower part: out of one wall, in at the other. The ledges are one-way: jump up through them, and press down plus jump to drop through. The camera follows you up and down. Hold down for 1.5 s to look below you, hold the aim straight up for 1.5 s to look above (on the phone: the stick straight down, or straight up inside the aim ring). Down on the floor ducks: the hitbox is the bottom half, so a shot at head height passes over. A fighter above or below your screen shows as a small bubble with its class icon at the top or bottom edge, at its real left-right spot. The arena shift is gone. Everything is slower: run 220 to 170, the dash cooldown 0.65 to 1.2 s, attacks about a third slower, specials about twice the wait, shots about 15 percent slower. The design page: `docs/reference/arena-tower.md`. Note (v0.1.4): the v0.1.3 duck went on and off every frame, so 6.2's look-down and 6.3's duck need v0.1.4 or later ([[v0.1.4 - Twin Sticks]]).

### 6.1 Moving around (both phones, one match at least)
- [ ] Climb from the floor to the top ledges using only jumps. Did every row feel reachable? (yes / write the row that was not): 
- [ ] Drop through a ledge with down + jump. Did it work first time? (yes / no): 
- [ ] Walk off the floor into the middle hole. Did you come back in through the ceiling and land on the ledge under it? (yes / no, write where you landed): 
- [ ] Find a side passage and go through it. Did you come out of the other wall at the same height? (yes / no): 
- [ ] Did anything ever get stuck in a wall, a floor corner or a ledge? (no / yes, clock time and where): 

### 6.2 The camera, the look and the markers
- [ ] Does the view follow you smoothly, with no jump when you land? (yes / it snaps): 
- [ ] Hold down for 1.5 s. Does the view slide down, and back when you let go? (yes / no): 
- [ ] Aim straight up and hold. Does the view slide up? (yes / no / it fires by accident while I play, write when): 
- [ ] When the other phone is above or below you, is the marker at the right left-right spot? (yes / no): 
- [ ] Could you find the other fighter within a few seconds every time? (yes / no, write how long it took): 

### 6.3 Duck and the pace
- [ ] Duck under an arrow or a kunai on purpose. Did it pass over you? (yes / no): 
- [ ] The dash and the teleport: could you find a moment to use them? (yes, easier / same as before / worse): 
- [ ] The fight: does it feel like a brawl still, but with time to think? (yes / too slow / still a hairball): 
- [ ] Kills by accident (own kunai, walked into a shot) over one match, both phones: 

### 6.4 Verdict (section 6)
- [ ] **Pass:** every row reachable, the holes and passages work, nothing stuck, the camera and the markers are fine, the pace feels right. The tower stays; next: themes, moving platforms, traps (build 2).
- [ ] **The pace is off:** write which numbers felt wrong (run, dash, attacks, specials, shots). Next: the table in `docs/reference/arena-tower.md` section 7, one build.
- [ ] **The map is off:** write the row, hole or passage. Next: `scripts/arena_layouts.gd`, one build.
- [ ] **Look fires by accident:** write when. Next: `LOOK_HOLD_S` and `LOOK_UP_COS` in `scripts/player.gd`.
Notes:

---

## 7. Twin sticks (v0.1.4)

What changed. The phone has a second layout. Tap the small SWAP button under the top bar (top left) to switch; the choice is remembered on that phone. Twin sticks: the LEFT circle walks where you point. Push past its rim: a dash that way. Tilt it above 45 degrees (the gold arc): a jump; bring it back under the arc to jump again. Straight down (the blue arc): duck, and after 1.5 s the view slides down. Straight down and past the rim: drop through the ledge you stand on. The RIGHT circle aims (the gold line stays where you left it). Push past its rim: one shot that way; pull back inside and push again for the next. Hold it straight up 1.5 s: the view slides up. SPEC is the round button in the bottom right corner. The arc layout (section 1) is unchanged.

### 7.1 The swap (both phones)
- [ ] Tap SWAP. Did the layout change at once, with nothing stuck (no fighter walking on its own)? (yes / no): 
- [ ] Reload the page. Is the layout still the one you picked? (yes / no): 
- [ ] Did SWAP ever fire by accident while playing? (no / yes, write when): 

### 7.2 The left stick
- [ ] Walk left and right inside the circle. Does the fighter go where the stick points, and stop when you come back to the middle? (yes / it creeps / it stops late): 
- [ ] Push past the rim ten times. Count the dashes: 
- [ ] Walk at full tilt for ten seconds without meaning to dash. Count the dashes you did not want: 
- [ ] Tilt up-right to jump while running, ten times. Count the misses: 
- [ ] Wobble the stick near 45 degrees. Did it double-jump? (no / yes): 
- [ ] Straight down: does the fighter duck and, after 1.5 s, does the view slide down? (yes / no): 
- [ ] Straight down past the rim on a ledge: did you drop through? (yes / no / it jumped): 
- [ ] Do you miss the straight-down dash in the air? (no / yes): 

### 7.3 The right stick
- [ ] Turn the aim all the way round. Smooth? (yes / no): 
- [ ] Walk left while aiming right. Did the fighter face right and walk backward? (yes / no): 
- [ ] Push past the rim ten times. Count the shots: 
- [ ] Hold the thumb past the rim. Does it keep firing? (no, one shot / yes): 
- [ ] Hold straight up. Does the view slide up after 1.5 s? Did it ever slide by accident while you were shooting upward? (yes and no / write what happened): 
- [ ] Rogue only: deaths to your own kunai over one match: 

### 7.4 SPEC and the thumbs
- [ ] Can you reach SPEC without moving your grip? (yes / a stretch / no): 
- [ ] Did a thumb ever land on the wrong thing (SPEC instead of the aim, SWAP instead of the stick, the aim circle instead of the move circle)? (no / write which): 
- [ ] Do the circles appear where your thumbs land, or do you have to look? (they follow / I look): 

### 7.5 Feel
| Question | S25 Ultra | Pixel |
|---|---|---|
| Left circle size (too small / right / too big) | | |
| Right circle size (too small / right / too big) | | |
| The rims (too easy to cross / right / too far) | | |
| The jump angle (too low / right / too high) | | |
| Which layout you keep (arc / twin) and why | | |

### 7.6 Verdict (section 7)
- [ ] **Pass:** 7.1 all yes, the counts in 7.2 and 7.3 are 9 or 10 out of ten with 0 or 1 unwanted, no double jump. Both layouts stay; each phone keeps its choice.
- [ ] **The rims are wrong:** too easy (unwanted dashes or shots) or too far. Next: `RIM_PAD` (10) and `RIM_REARM` (0.85) in `scripts/touch_controls.gd`.
- [ ] **The jump angle is wrong:** misses or double jumps. Next: `JUMP_DEG` (45) and `JUMP_REARM_DEG` (35).
- [ ] **A circle is wrong:** too small or too big. Next: `MOVE_RADIUS` (80), `AIM_RADIUS` (70).
- [ ] **The thumbs miss:** write what in the notes. Next: move SPEC or SWAP (`SPECIAL_TWIN`, `SWAP_CENTER`), or a bigger dead zone (`NOISE_RADIUS`).
Notes:

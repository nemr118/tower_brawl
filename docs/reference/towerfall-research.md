---
tags: [reference, design, research]
status: research 2026-09-10 (for the v0.2 pivot)
---
# TowerFall Ascension: how it works (research for v0.2)

On 2026-09-10 the user asked to move Tower Brawl closer to TowerFall Ascension, the game that started this project. This page is what TowerFall does, with its real numbers. The plan that uses it: [[v0.2-transformation-plan]]. The choices: [[Design Decisions v0.2]].

## 0. Where the facts come from
- **The user's own Steam copy**, decompiled with the user's permission: `/mnt/storage/SteamLibrary/steamapps/common/TowerFall/TowerFall.exe` (a .NET/XNA build), turned into C# with `ilspycmd` 10.1.1 into `~/Work/towerfall_research/decompiled/` (637 files). The levels are XML files in `Content/Levels/`. Main files read: `Player.cs`, `Arrow.cs`, `BoltArrow.cs`, `RoundLogic.cs`, `LastManStandingRoundLogic.cs`, `HeadhuntersRoundLogic.cs`, `Miasma.cs`, `MatchSettings.cs`, `Session.cs`, `TreasureSpawner.cs`, `MatchVariants.cs`, `ReplayRecorder.cs`.
- **The rule for this repo (it is public):** no TowerFall code, art, sound or level layouts go in here. Rules and numbers are written in our own words, as a guide to tune by feel. The decompiled source stays in `~/Work/towerfall_research/`, outside any repo.
- **The web:** the TowerFall wiki, Game Developer articles, Wikipedia, Maddy Thorson's physics article, the 8-Player Edition page. Links at the end.

**Units.** TowerFall runs at 60 frames a second on a 320 x 240 screen with 10 px tiles. Its numbers are pixels per frame (px/f). The "ours" column uses **1 TowerFall pixel = 2 of our pixels**: px/f x 120 = our px/s, px/f² x 7 200 = our px/s², frames / 60 = seconds. Our 640 x 360 screen is then 32 x 18 tiles of 20 px (TowerFall: 32 x 24).

> **Update, same day (plan draft 2):** the game moves to 90 px fighters on a 1920 x 1080 screen, so the scale becomes 1 TowerFall pixel = 4.5 of ours. The x2 columns below are from draft 1; the x4.5 table is in [[v0.2-transformation-plan]] section 3.

## 1. The game in one paragraph
Two to four archers on one screen. Every hit kills. Each archer starts a round with 3 arrows and picks them up again after they stick. A dodge moves you fast and catches an arrow flying at you. Jumping on a head kills. The screen wraps on all four edges. The last one alive gets a point; with 4 players, 3 points win. Chests appear in the first seconds with arrows and powerups. After 25 s a purple wall (the miasma) closes in from both sides, so no round lasts much more than 50 s. When a round ends, a short replay shows the kill.

## 2. Moving
| Thing | TowerFall | Ours (x2) | Tower Brawl today |
|---|---|---|---|
| Run top speed | 1.5 px/f | 180 px/s | `SPEED` 170 |
| Run acceleration, ground / air | 0.15 / 0.1 | 1 080 / 720 px/s² | `ACCEL` 1 500 |
| Slowing down, ground / air (no input, or aiming on the ground) | 0.2 / 0.14 | 1 440 / 1 008 px/s² | `FRICTION` 1 300 |
| Aiming on the ground | top speed 0: you stand still | — | you run and shoot |
| Gravity | 0.3 px/f² | 2 160 px/s² | 1 150 (1 600 falling) |
| Gravity while jump is held, going up or just past the top | 0.15 | 1 080 px/s² | — |
| Jump speed | 3.2 px/f | 384 px/s | 430 |
| Jump height, held / tapped | 34 / 17 px | 68 / 34 px | 80, one height |
| Extra sideways speed when jumping while running | 0.5 | 60 px/s | — |
| Top fall speed / holding down (fast fall) | 2.8 / 3.5 | 336 / 420 px/s | `MAX_FALL_SPEED` 600 |
| Coyote time / jump buffer | 6 f / 6 f | 0.1 s / 0.1 s | 0.12 s / 0.12 s |
| Wall slide top speed | starts 0.5, grows 0.01 a frame to 1.6 | 60 to 192 px/s | — |
| Wall jump | up 3.2, away 2.0, pushed away for 12 f | 384 up, 240 away, 0.2 s | — |
| Ledge grab | falling beside a wall top, looks 10 px up; hop 2.2 | 20 px, 264 px/s | — |
| Jump pad | 4.3 px/f | 516 px/s | — |
| Body box / ducking box | 8 x 14 / 8 x 6 | 16 x 28 / 16 x 12 | 14 x 24 / 14 x 12 |
| One-way ledges | jump up through them; rising through one pops you up 2 px a frame | | one-way ledges, down + jump drops |

## 3. The dodge and the catch
- Press dodge: a burst in one of 8 directions (the stick, or the way you face) at 5.5 px/f (660 px/s). The speed shrinks x0.85 every frame, so the dodge covers about 35 px (70 ours). It lasts 20 f (0.33 s), plus up to 5 f while the button stays held.
- Cooldown: 25 f (0.42 s) after the dodge ends. While it cools, running speeds up only 0.8 as fast. (Today: `DASH_COOLDOWN` 1.2 s, 77 px.)
- Dodge on the ground while holding down: a slide, x1.4 speed, with the ducking box.
- **During a dodge an arrow cannot hurt you.** A 12 x 16 box (24 x 32 ours) catches it instead. A catch freezes you for 10 f (a flash), and the arrow goes into your quiver; if the quiver is full, it drops at your feet. With a shield on, you cannot catch.
- A second dodge press ends the dodge at once and keeps the speed ("dodge cancel"; fast enough = a "hyper"). A jump during a dodge keeps up to 1.8 px/f sideways (2.8 out of a slide), or becomes a wall jump.
- A dodge does not protect from a stomp. A dodge cancels aiming.

## 4. Arrows
- **Quiver:** 3 at the start of a round, 6 at most. Over 12 arrows in the level, the oldest start to fade away.
- **Shooting:** press shoot to start aiming, let go to fire. Aim is 8 directions; the "Free Aiming" option gives 360. Shooting with an empty quiver just clicks.
- **Aim help when firing:** if an enemy is within 36 px (72) and within 65° of the aim, with no wall between, the arrow goes straight at them.
- **Flight:** 4 px/f (480 px/s; today 560). Straight for 25 f (0.42 s, 100 px = 200 ours), then gravity 0.2 (1 440 px/s²), sideways drag 0.03 (216 px/s²), top fall 5.5 (660 px/s).
- **Every arrow bends a little** toward an enemy within 70 px (140), within 40° of its heading, in clear sight: 2° a frame (120°/s).
- It cannot hit its own shooter until it is 20 px (40) away.
- **Hits a wall:** sticks. For 15 f (0.25 s) nobody can take it. Then **anyone** can pick it up, own or enemy, by touching a 22 x 30 box (44 x 60) around the body. (Today only the shooter can.)
- **Two flying arrows meeting head-on** both bounce off and fall, harmless.
- **Hits a fighter:** it stays in the body and the fighter dies. The corpse keeps its quiver (an option drops it). Dying while aiming drops the drawn arrow.
- **Stealing:** walk into someone sideways with an empty quiver while they have arrows: you take one.

## 5. Kills
- Every hit kills: an arrow, a stomp, an explosion, lava, being crushed, the miasma.
- **Stomp:** land on someone whose top is at least 10 px (20) lower while you fall: they die, you bounce up as if you jumped. From the side: both are pushed apart.
- **Shield** (a powerup): takes one hit of any kind and breaks; an arrow bounces off it.

## 6. The screen and the wrap
- One 320 x 240 screen. All 141 Versus level files have `WrapMode="Both"`: out the left, in at the right; out the bottom, in at the top. Arrows wrap too, and the aim help and the bend see across the edge.
- Fighters and arrows near an edge are drawn on both sides (`DoWrapRender`), so there is no hiding spot at the seam (our backlog 17).
- Level files mark player spawn spots (4 in the levels checked), team spawn spots, chest spots (851 in the 141 files, about 6 a level) and big chest spots (134).
- A tower is a set of 10 to 13 levels with one look, one treasure list and one signature arrow (section 9). Levels add parts: cracked walls and ledges, switch blocks, jump pads, ice, hot coals, spike balls, lanterns, darkness.

## 7. Rounds and matches
- **Last Man Standing** (the main mode): the one left alive gets 1 point; if nobody is left, nobody scores. Points to win at the standard length: **5 with 2 players, 4 with 3, 3 with 4**. "Quick" halves it, "Epic" doubles it. (Today: 5 crowns at any count.)
- **Headhunters:** +1 per kill, -1 per self-kill; 5 / 8 / 10 to win; a round still ends when one is left.
- **Team Deathmatch:** 2v2 (also 3v1 and 2v1), 5 points. Stomps don't hurt a teammate, arrows do. Bumping a teammate evens out your arrows.
- **Round end:** once it is decided, the game waits 90 f (1.5 s) before scoring. A late death in that time can still make it a draw. (Our backlog 26 is the same moment.)
- **Replay:** the last 210 frames (about 3.3 s). Start skips it. (Our replay keeps 211 frames.)
- The leader wears a crown.
- **Autobalance** (on unless turned off): the crown holder starts with one arrow fewer (never under 2). A player 2 points behind the leader (Last Man Standing with 3 or more players; otherwise 3 points) starts with a shield.

## 8. The miasma (the round clock)
- **25 s** (1 500 f) after the round starts, purple walls grow in from the left and right edges. Each wall's width is a share of half the screen (160 px, 320 ours).
- In 9 s each wall reaches 33% of the way to the middle. It turns deadly 2 s after it appears.
- Then both pull back to 15% over 3 s, then close all the way (105%) over 11 s: anyone still alive dies. Then they pull back over 4 s.
- A kill that leaves one fighter alive makes the walls melt away at once.
- So a round lasts at most about 50 s. The "Sudden Death" option starts the walls after 1 s; "No Time Limit" turns them off.
- For comparison: our humans' rounds, median 46 s, longest 99 s; our bots once played one round for 10 hours ([[bot-soak-2026-09-08]]).

## 9. Treasure
- **When:** each chest appears at a random time 10 f to (players x 60) f after the round starts (up to 4 s with 4 players).
- **How many:** the chest spots are tried in order, each with a chance. With 4 players: 90%, 90%, 60%, 80%, 20%, 10%. With 3: 90, 90, 80, 20, 10. With 2: 90, 90, 20, 10.
- **Big chest:** a 3% chance a round of one big chest with 3 things instead.
- **Opening:** touch it. A bomb chest is a trap.
- **What's inside:** 60% of the time 2 special arrows of the tower's type. Otherwise a pick from the tower's list, by weight: each arrow type 1, shield / wings / speed boots 0.5, looking glass 0.25, each orb 0.15, bomb 0.1, chaos orb 0.001.

| Tower | Signature arrows | Also in its chests |
|---|---|---|
| Sacred Ground | plain (+2 arrows) | shield, wings, time / dark / lava orb |
| Twilight Spire | plain | shield, wings, boots, glass, all orbs, bomb |
| Backfire | bomb | shield, glass, orbs, bomb |
| Flight | bomb | wings x4, boots, shield, glass, orbs, bomb |
| Mirage | laser | wings, shield, glass, orbs, bomb |
| Thornwood | bramble | wings, shield, glass, orbs, bomb |
| Frostfang Keep | drill | shield, glass, boots, orbs, bomb |
| Kings Court | bomb, bramble | shield, boots, glass, orbs, bomb |
| Sunken City | bolt | shield, glass, orbs, bomb |
| Moonstone | bomb, laser | shield, glass, orbs, bomb |
| TowerForge | super bomb | shield, wings, glass, orbs, bomb |
| Ascension | feather | shield, wings, boots, glass, orbs, bomb |
| Dark World: Amaranth, Dreadwood, Darkfang, Cataclysm | plain; bomb + bramble; trigger; prism | the same kinds |

## 10. Powerups and special arrows
| Name | What it does |
|---|---|
| Shield | takes one hit, then breaks. No catching while you wear it. (Option: it grows back 4 s after breaking.) |
| Wings | press jump in the air to flap (1.4 px/f up); hold to glide (top fall 0.8). Lost to fire or death. |
| Speed boots | top run speed and run acceleration x1.4. |
| Looking glass | nearly invisible (20% seen), quiver hidden. |
| Time orb | everything at half speed for 5 to 6 s. |
| Dark orb | the level goes dark for 10 to 15 s. |
| Lava orb | lava rises from the edges. |
| Space orb | the whole level scrolls and wraps. |
| Chaos orb | all orbs at once (very rare). |
| Bomb arrows (2) | explode a moment after they are fired. |
| Super bomb arrows (2) | a big cross-shaped blast. |
| Laser arrows (2) | 5 px/f, no gravity, bounce off walls 8 times (the code; the wiki says 7). |
| Bramble arrows (2) | deadly thorns grow along the surface they hit. |
| Drill arrows (2) | bore through one wall. |
| **Bolt arrows (2)** | **the nearest thing to a guided arrow.** They seek on their own: a target within 80 px (160), within 30°, 1° a frame. About to hit a wall, they look further (160 px, 48°) and turn up to 90° to go round it. |
| Feather arrows (2) | 6 px/f, no gravity, bend 3° a frame. |
| Trigger arrows (2) | explode when you press the second shoot button. |
| Prism arrows (2) | trap a fighter in a crystal that shatters after a moment. |
| Toy arrows (option) | harmless. |

## 11. Options ("variants")
TowerFall's options change the rules for a night. **Every arrow and archer option can be set per player**, so the game already has a tested list of perks and handicaps. The ones that matter here:
- Arrows: No arrows, Single arrow, Max arrows (6), **Regenerating arrows** (an empty quiver gets one arrow after 90 f, 1.5 s), Secret arrows (quivers hidden), start with a special arrow type, No seeking, Super seeking (bend x2), Anti-gravity arrows.
- Archers: Start with shields, Regenerating shields, Start with wings, Start with speed boots, Start invisible, **Double jumping**, Exploding corpses, Return as ghosts, Corpses drop arrows, Encumbrance (every 2 arrows carried: top speed -0.25), Small quivers (max 3), No quivers (max 1), No dodging, **Super dodging** (x1.8), Clumsy archers (drop an arrow on each dodge), **Free aiming** (360).
- Curses: Cursed bows (shooting empty kills you), Cursed dodges (a dodge without a catch or a stomp kills you).
- Rules: No autobalance, No friendly fire, **No time limit**, **Sudden death**, Team revive, Gunn style (the frame freezes on every death).
- Treasure: No treasure, Max treasure, Always big treasure, Bottomless chests, Bomb chests, Symmetrical treasure, Treasure draft (pick a treasure at the round start).

## 12. What the designer learned
- **One weapon.** The bow was built first and was so much fun that every other weapon was cut. The arrow rules barely changed from the first prototype.
- **Characters only look different.** "All of the characters are only cosmetically different." Different abilities "diluted" the balance. Players still pick a favourite for its look, its attitude and its victory tune.
- **Layers you find by playing.** The dodge is for moving; then you find it catches arrows; then that you can cancel it; then the mind games. Friends teach each other; nothing needs a move list.
- **Four people in one room, one screen,** everyone always visible. No online play.
- Effects and particles were added so people watching can follow the action.
- Plain rules are the standard; the options are for silly nights ("you can ruin the game").
- **Physics without an engine.** Everything is a box on whole pixels. "Actors" (fighters, arrows, chests) move one pixel at a time and stop at "solids"; the leftover part of a pixel is kept for the next frame. A moving solid carries what rides on it and pushes what it hits; an actor crushed between two solids dies. The result is the same every time.
- **8-Player Edition** (2016, Windows, an official mod): Versus only; free-for-all up to 6, teams up to 8; every level redrawn wider.

## Sources
- TowerFall wiki: [Versus](https://towerfall.wiki.gg/wiki/Versus), [Variants](https://towerfall.wiki.gg/wiki/Variants), [Powerups](https://towerfall.wiki.gg/wiki/Powerups), [Competitive Strategies](https://towerfall.wiki.gg/wiki/Competitive_Strategies), [Ascension](https://towerfall.wiki.gg/wiki/Ascension)
- Game Developer: [The magic of TowerFall: depth, simplicity, community](https://www.gamedeveloper.com/design/the-magic-of-i-towerfall-i-depth-simplicity-community), [On TowerFall Ascension's approach to characters](https://www.gamedeveloper.com/design/on-towerfall-ascension-s-approach-to-characters), [Road to the IGF: TowerFall Ascension](https://www.gamedeveloper.com/design/road-to-the-igf-matt-thorson-s-i-towerfall-ascension-i-)
- [TowerFall on Wikipedia](https://en.wikipedia.org/wiki/TowerFall)
- [Celeste & TowerFall Physics](https://www.maddymakesgames.com/articles/celeste_and_towerfall_physics/index.html) (Maddy Thorson)
- [TowerFall 8-Player](https://maddymakesgamesinc.itch.io/towerfall-8-player) (itch.io); [Engadget on the 8-player update](https://www.engadget.com/2016-08-30-towerfall-ups-the-mayhem-with-eight-person-local-multiplayer.html)

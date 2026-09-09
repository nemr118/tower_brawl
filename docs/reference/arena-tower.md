---
tags: [reference, design]
status: approved 2026-09-08, built in v0.1.3 (build 1)
---
# The tower arena (design page, build 1)

The user's picture, 2026-09-08: hard outer walls with details, a hole in the floor and one in the ceiling, side passages, an inside much taller than it is wide, a camera that follows you up and down, duck and look, slower and more tactical fighting, no arena shift. This page turns that into numbers and a build list. Later themes, moving platforms and traps go in a second table, not a second scene. The old arena is described in [[v0.0.39 - Anchored Ground]]; it goes away with this build.

## 1. The tower in numbers

| Thing | Number | Why |
|---|---|---|
| Play width | 640 px, x 0 to 640 | one screen; the camera never moves sideways |
| Play height | 1 080 px, y 0 to 1 080 | three screens (user: 3) |
| Walls | 48 px thick, outside the play box (x -48..0, 640..688; y -48..0, 1 080..1 128) | the inner face is the screen edge; wall bumps stick inward and are ledges |
| Ceiling hole | x 256 to 384 at y 0 | 128 px, the middle |
| Floor hole | x 256 to 384 at y 1 080 | same span, so the bottom hole comes out at the top hole |
| Upper side passage | y 380 to 428, both walls | 48 px tall, a fighter is 24 px |
| Lower side passage | y 800 to 848, both walls | same |
| Ledges | 12 px thick, one-way (jump through from below, down + jump drops through) | a tower needs a way up |
| Floor | y 1 080, solid, 256 px each side of the hole | |
| Wall bumps | 90 x 16 px, solid on top, a wall below | the walls "conform to provide ledges" |
| Row spacing | 70 px | a jump reaches 80 px (430 squared over 2 x 1 150) |

Movement packets carry x and y as tenths of a pixel in a signed 16-bit field: 3 276 px each way. 1 128 fits.

### 1.1 The map (1 column = 16 px, 1 row = 30 px; `#` wall, `=` ledge, `.` open, `o` hole, `>` passage, `S` spawn)

```
       x:0                                 640
        #########   ooooooooo    ##########    y 0
        #.......................................#
        #.......................................#   90  ledge 130..270, ledge 370..510
        #........========.......========........#
        #.......................................#  160  wall bumps 0..90, 550..640
        #######.................................#######
        #.......................................#  230  ledge 250..390
        #...............=========...............#
        #...S.................................S.#  300  ledge 60..200 (spawn), ledge 440..580 (spawn)
        #...========.....................========#
        >.......................................>  380..428 upper passage; ledge 260..380
        >...............========................>
        #.......................................#  450  ledge 130..270, ledge 370..510
        #........========.......========........#
        #.......................................#  520  wall bumps 0..90, 550..640
        #######.................................#######
        #.......................................#  590  ledge 250..390
        #...............=========...............#
        #.......................................#  660  ledge 40..180, ledge 460..600
        #..========.....................========#
        #.......................................#  730  ledge 260..380
        #...............========................#
        >.......................................>  800..848 lower passage; ledge 130..270, 370..510
        >........========.......========........>
        #.......................................#  870  wall bumps 0..90, 550..640
        #######.................................#######
        #.......................................#  940  ledge 250..390
        #...............=========...............#
        #...S.................................S.#  1010 ledge 60..200 (spawn), ledge 440..580 (spawn)
        #...========.....................========#
        ################   ooooooooo   ##########  y 1080 floor, hole 256..384
```

Every row is reachable from the row under it with one jump. The passages sit where no ledge touches the wall, so you enter one by jumping from the centre piece toward the wall: geometry, not a straight run. The ceiling hole needs a jump and an upward dash from the y 90 ledges (a jump alone reaches y about 10; the hole starts counting at y -16). The floor hole is a drop.

### 1.2 The layout table
A new script, `scripts/arena_layouts.gd`, holds the pieces as data: `{name, kind, x, y, w, h}` with `kind` one of `wall`, `floor`, `ledge`, `bump`. `arena.gd` builds a `StaticBody2D` with a `CollisionShape2D` and a drawn rectangle for each at load, into `$Platforms` (the node keeps its name so the tape, the replay and the bot brain keep their field). Ledges get `one_way_collision = true`. The spawn spots are the ledges marked `spawn`. A second layout later is a second table with a name; the server can pick one per match then.

## 2. The wrap through the holes
The rule keeps its shape, only the numbers change, because the walls, the floor and the ceiling stop a fighter everywhere else:
- `player.gd` `_check_screen_wrap`: x past -12 comes back at 650 and the reverse (only possible inside a passage); y past 1 096 comes back at -10 (the floor hole); y under -16 with upward speed comes back at 1 090 (the ceiling hole, the speed kept).
- `_unwrapped_delta` / `_wrap_into_arena` (the puppet ring): the y seam goes from 386 to 1 106, the half seam from 193 to 553.
- Projectiles: the same y seam through the holes; the x wrap they have today only fires inside a passage now.
- `bot_brain.gd` `ARENA_H` 360 to 1 080, `SEAM_Y` 376 to 1 096; the bot's platform map reads the built pieces.
- `tools/chaos_bots.py` `ARENA_H` 360 to 1 080 (the protocol bots' random spots).
- A mid-round respawn drops in through the ceiling hole: the air bubble starts at x 300 to 340 (`SPAWN_MIN_X` / `SPAWN_MAX_X`), y -10, and floats down as today (45 px/s, 5 s at most), so a fighter comes back in the top third. Round starts use the four spawn ledges.
- New: a top fall speed, `MAX_FALL_SPEED` 600 px/s in `player.gd`. Without it a three-screen drop reaches 1 860 px/s, 93 px per packet, over the 80 px puppet teleport threshold (`Global.TELEPORT_PX`).

## 3. The camera
- A `Camera2D` in `arena.tscn` (`Cam`), moved by `arena.gd` each drawn frame to my fighter (a spectator: the middle of all living fighters). Limits x 0 to 640 (no sideways scroll), y 0 to 1 080. Position smoothing on, 8 per second.
- Look down: hold down (S, or the stick straight down inside the aim ring) on the floor for 1.5 s: the view eases to 200 px below the fighter. Look up: aim within 30 degrees of straight up for 1.5 s (mouse, or the stick straight up inside the ring): 200 px above. Let go: eases back in 0.3 s.
- Dead: the camera stays where the fighter died until the respawn.
- The replay: the camera goes to the closing kill's victim (the red circle) for the whole replay; the VHS overlay is drawn on the HUD layer (screen space) instead of the world, so it does not scroll.
- Stays on screen because it is already on `$HUD` (a `CanvasLayer`): the top bar, the banner, the leave button, the ticker. Moves to `$HUD` in code: the pause overlay, the join button. The background `ColorRect` moves to a `Sky` `CanvasLayer` under everything (layer -1) so it does not scroll either. The touch controls are their own `CanvasLayer` already.

## 4. Duck
- On the floor, down held over 0.5 and no sideways input: the fighter ducks. It does not walk while ducked. Down + jump on a one-way ledge drops through it.
- The hitbox (14 x 24 at (0, -4)) becomes 14 x 12 at (0, 2): the bottom half. A shot at standing height passes over. Stomps and melee still hit.
- The duck goes out in `sync_pos` as flag bit 0x40 (`FLAG_DUCK`), so every screen shrinks the puppet's hitbox too: hits are reported by whoever sees them, so the shape has to match everywhere. The tape records it; the replay draws it. Bit 0x80 stays free.

## 5. Off-screen markers
The camera only scrolls up and down, so a fighter you cannot see is above or below you and its x is its real x. A `Markers` `CanvasLayer` draws, each frame, a 22 px bubble with the class icon (`ICON_TEX`, 256 px) at (their x, 14) for a fighter above the view and (their x, 346) for one below, in the seat's colour. Their own screen never shows one for themselves. Dead fighters and the spectator's view: none.

## 6. The arena shift goes away
`const ARENA_SHIFT_ENABLED = false` in `arena.gd`: the host's 15 s powerup timer is not started. The relay in `serve_game.py`, `Global.arena_flips`, the tape's `rot` and `flips`, the replay's platform turn and the bots' `shift_wraps` all stay and all read zero. Backlog 9 and 24 close as "does not apply any more" (the pieces that swung past the top edge are gone).

## 7. The pacing table (current, proposed)

| What | File | Now | Proposed | Why |
|---|---|---|---|---|
| Run speed `SPEED` | player.gd | 220 | 170 | the hairball |
| `ACCEL` / `FRICTION` | player.gd | 1 900 / 1 500 | 1 500 / 1 300 | same feel at the new speed |
| Jump `JUMP_VELOCITY` | player.gd | -430 | -430 | the map is built on an 80 px jump |
| `GRAVITY` / `FALL_GRAVITY` | player.gd | 1 150 / 1 600 | same | |
| `MAX_FALL_SPEED` | player.gd | none | 600 | new, section 2 |
| Dash `DASH_SPEED` x `DASH_DURATION` | player.gd | 550 x 0.14 = 77 px | 480 x 0.16 = 77 px | same reach, easier to see |
| `DASH_COOLDOWN` | player.gd | 0.65 | 1.2 | a choice, not a reflex |
| Ranger arrow cooldown | player.gd | 0.32 | 0.45 | |
| Knight sword cooldown | player.gd | 0.38 | 0.5 | |
| Mage bolt cooldown | player.gd | 0.35 | 0.5 | |
| Druid thorn / bear swipe | player.gd | 0.35 / 0.5 | 0.5 / 0.6 | |
| Rogue kunai cooldown | player.gd | 0.22 | 0.35 | |
| Ranger recoil shot special | player.gd | 0.8 | 1.5 | |
| Knight shield special / shield time | player.gd | 0.75 / 0.38 | 1.2 / 0.45 | |
| Mage blink special (95 px) | player.gd | 1.0 | 2.0 | the teleport was "hard to find a time for" |
| Druid bear / air shield special | player.gd | 1.0 | 1.5 | |
| Rogue shadow dash special | player.gd | 1.1 | 2.0 | |
| Mage charge recharge | player.gd | 1.4 s | 1.8 s | |
| Rogue kunai recharge | player.gd | 0.9 s | 1.2 s | |
| Arrow speed | arrow.gd | 650 | 560 | |
| Firebolt speed / life | firebolt.gd | 520 / 1.8 s | 460 / 2.2 s | a taller room |
| Kunai speed / life | kunai.gd | 720 / 1.2 s | 600 / 1.5 s | |
| Thorn speed | thorn.gd | 550 | 480 | |
| Respawn after a death / spawn shield | arena.gd, player.gd | 1.2 s / 1.0 s | same | |

The bot brain copies `SPEED`, `JUMP_H` and the projectile speeds; the build reads them from the player and projectile scripts instead of keeping copies. The harness scenario `respawn_death` times the 1.2 s respawn, unchanged.

## 8. The build list (one build, v0.1.3)
1. `arena.tscn`: delete the eight platform bodies and their five shapes; add `Cam` (Camera2D), `Sky` (CanvasLayer -1, the background moves under it), `Markers` (CanvasLayer). `player.tscn` untouched.
2. `tools/check_scripts.gd`: also load and instantiate every scene under `res://scenes`, so a broken scene fails the bump. `CLAUDE.md` rule 1 rewritten: scene edits allowed, the load check after every one, binary files never.
3. `scripts/arena_layouts.gd` (the table), `arena.gd` builds it, the spawn picker reads the spawn ledges, the powerup timer gated off.
4. `player.gd`: the seams, the fall cap, duck, the flag bit, the pacing numbers; `global.gd`: `FLAG_DUCK`; the projectile scripts: the seam and the speeds.
5. The camera and the look rules, the markers, the overlay on the HUD layer, the replay camera.
6. `bot_brain.gd`: the map and the seams, constants read from the player; `tools/chaos_bots.py`: `ARENA_H`.
7. Harness 25/25, a sheet section 6 (the tower: the map, the passages, duck, look, markers, the pace), deploy to the laptop.

Not in build 1: themes, moving platforms, traps, more than four players (an idea, backlog 29), a second layout.

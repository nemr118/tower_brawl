---
tags: [playtest]
build: v0.0.32
backlog: 9
result: not played yet
---
# Playtest v0.0.32 — Free-Fall Arena Shift

**Result: not played yet. Fill in the boxes below, then paste the console lines into the tables.**

This sheet is for one change only. Since v0.0.32 the platforms are not solid while the arena shift turns the stage (2.5 s). A fighter standing on a platform when the shift starts falls through the turning stage and lands on the new layout when it locks. Before, that fighter rode the platform out of the top of the screen for about a second (backlog 9, [[v0.0.31 - Top Edge Probe]]).

The harness proves the ride is gone (zero `🧗 [TopEdge]` lines on the heavy fleet run). What it cannot judge is how the free fall feels in a real game, on a phone and on a PC. That is what this sheet is for.

## Setup
- Build: `v0.0.32`. Check the version line in the browser console at load.
- Play at `https://192.168.4.21:8443/play`. Two players at least, four is best.
- Open the browser console on the PC (F12). Phones cannot show it; write "phone, no console" in the console fields.

| Field | Your answer |
|---|---|
| Date | |
| Devices (PC browser, phone model and browser) | |
| Number of players | |
| Bots in the game (yes / no, how many) | |

## Scenarios
Tick each box once you have seen it. Write what happened in the notes line.

### 1. Standing on a ledge when the shift starts
- [ ] Stand on `LedgeLeft` or `LedgeRight` (the outer ledges). Let another player grab the power-up.
- [ ] You fall as soon as the banner `** ARENA SHIFT! **` shows.
- [ ] You never leave the top of the screen.
- [ ] You fall out of the bottom and come back in at the top, three or four times, then land on the new layout when the stage locks. (The harness measured 0.65 s per screen of fall, so this tumble is expected. Backlog 23 asks whether it feels right.)
Notes:

### 2. Standing on the ground slab when the shift starts
- [ ] Stand on `GroundLeft` or `GroundRight`. Let another player grab the power-up.
- [ ] You fall through the slab as it starts to turn.
- [ ] You never leave the top of the screen.
Notes:

### 3. Standing on the centre tower when the shift starts
- [ ] Stand on the centre tower. Let another player grab the power-up.
- [ ] You fall through the tower (it is soft too), then land when the stage locks.
Notes:

### 4. Grabbing the power-up yourself
- [ ] Grab the power-up while standing on a platform.
- [ ] You fall right away, same as the others.
Notes:

### 5. Jumping and dashing during the turn
- [ ] During the turn, jump and dash across the screen.
- [ ] Nothing catches you mid-air; you pass through the turning platforms.
- [ ] You can still be hit and can still hit others during the turn.
Notes:

### 6. A round start during the turn
- [ ] Have the last fighter of a round die while the stage is turning (the next round comes 2.6 s after the last kill).
- [ ] The new round starts with everyone standing on solid platforms. Nobody falls through the floor at the spawn.
Notes:

### 7. Other screens
- [ ] Watch another player fall through the turning stage on your screen. They fall the same way on their own screen (ask them).
Notes:

## Edge cases
- [ ] Shield up when the shift starts: you still fall.
- [ ] Egg form (druid stomp) when the shift starts: you still fall.
- [ ] Two shifts in a row (a new power-up right after the stage locks): the second shift also drops you, and the platforms are solid in between.
Notes:

## Telemetry
Paste the lines from the PC console. A `🧗 [TopEdge]` line during a shift means the fix did not hold; paste it in full.

| When | `🧗 [TopEdge]` line (full) or "none" |
|---|---|
| Whole session | |

`📈 [NetStats]` lines during and right after a shift (the `fps` part and `keys= focus=`):

| When | `fps draw= phys= worst= hitches=` | `keys=` | `focus=` |
|---|---|---|---|
| During a shift | | | |
| Right after the stage locked | | | |

## Verdict
- [ ] The free fall and the tumble through the bottom feel fair. Keep option A as it is; make the harness gate ignore wraps during a turn (backlog 23).
- [ ] The fall through the platforms is fine but the tumble through the bottom is too much (write why). Backlog 23: change the feel, for example a slower fall during the turn.
- [ ] The free fall feels bad (write why in the notes). Reopen backlog 9 and look at option B (wrap at the top during a turn).
- [ ] A `🧗 [TopEdge]` line showed during a shift. Reopen backlog 9 with the line pasted above.
Notes:

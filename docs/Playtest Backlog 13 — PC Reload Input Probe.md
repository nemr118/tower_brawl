---
tags: [playtest]
build: v0.0.29
backlog: 13
result: not played yet
---
# Playtest Backlog 13 — PC Reload Input Probe

**Result: not played yet. Fill in the boxes below, then paste the console lines into the tables.**

This sheet is for one bug only. On 2026-09-04 the PC reloaded its page while the replay was playing. It got its seat back in the same second, round 3 started on time, but the fighter could aim with the mouse and could not walk. A second reload did not help. The server and lobby parts of backlog 13 were fixed in [[v0.0.28 - Rejoin in the Replay Gap]]. The walking part is still open because it did not happen headless (the harness scenario `reload_in_gap` walks fine after a reload). So the suspect is the browser keyboard.

**Why this test works.** In the browser the game only hears keys while the game canvas has the page focus. Since v0.0.28 every `📈 [NetStats]` line in the browser console ends with two numbers: `keys=N` (key presses the game heard since the last line, one line every 5 s) and `focus=1` or `focus=0` (does the canvas have the page focus right now). Read together they tell us where the keys get lost:

| What you see while holding a key | What it means | Where to look next |
|---|---|---|
| `focus=0` | the page focus was lost by the reload; the self-heal in `web/shell.html` did not catch it | `focus_canvas()` in `global.gd`, the focus code in `web/shell.html` |
| `focus=1 keys=0` | the canvas has the focus but the game never sees the key events | the InputMap copy in `global.gd` `assign_id` (`p1_*` actions copied to `p<n>_*`) |
| `focus=1 keys>0` and still no walking | the keys arrive, the fighter state is the problem after all | `player.gd` local branch; take the `🧭 [Spawn]` line and the whole NetStats line |
| `keys>0` and walking works | the bug is gone or needs another trigger | try the edge cases in section 4 |

---

## 0. What we tested on

| Question | Answer |
|---|---|
| PC operating system and browser (with version, `chrome://version`) | |
| Keyboard: laptop, USB, Bluetooth | |
| Build shown in the lobby (must be v0.0.29 or later) | |
| Second fighter: phone, second PC, or a bot (`godot --headless --path . -- --autojoin --ai=chaser --name=Bot1`) | |
| Class the PC played | |
| Date and time (so the `server.log` lines can be found) | |

**How to start**
- Start the server (`./venv/bin/python serve_game.py`) and open `https://192.168.4.21:8443/play` on the PC. If the console says VERSION MISMATCH, reload hard.
- Open the browser console (F12, tab Console) and type `NetStats` in the filter box. One line lands every 5 s.
- Get a second fighter in (phone or bot). Join, lock in, play until a round ends on a kill. The replay plays for about 5 s, the next round starts 6.5 s after the kill.
- Keep `server.log` open in a terminal on the side: `tail -f server.log | grep -E "JOIN|LEAVE|ROUND"`.

---

## 1. Scenario A: reload during the replay (the original bug)

Steps:
1. Play a round until it ends on a kill. As soon as the replay starts (the `◄◄ REW` label), press F5 on the PC.
2. The page reloads and should land in the arena in the same seat (`server.log`: `[JOIN] P<n> took seat <n> ... (rejoined mid-match)`).
3. Wait for the next round to start. Do not click anywhere. Do not press any key yet.
4. When the round starts, hold `D` for 5 seconds, then hold `A` for 5 seconds. Move the mouse in a circle. Count 2 NetStats lines.
5. Write down what happened and paste the two lines.

- [ ] The page came back in the arena, in the same seat, same class
- [ ] The next round started at the normal time (6.5 s after the kill)
- [ ] The fighter aims with the mouse
- [ ] The fighter walks with A and D
- [ ] The fighter jumps with W or Space
- [ ] The fighter attacks with the mouse button

Console lines (paste the whole line, or at least the part after `fps`):

| Line | `keys=` | `focus=` | walking? (yes/no) | aiming? (yes/no) |
|---|---|---|---|---|
| NetStats line 1 (while holding D) | | | | |
| NetStats line 2 (while holding A) | | | | |

Server line for the rejoin (`grep JOIN server.log`): 

`🧭 [Spawn]` line after the reload (filter `Spawn` in the console): 

Notes:
- 

## 2. Scenario B: reload in the middle of a round (the second reload of the playtest)

Steps:
1. While a round is running and your fighter is alive, press F5.
2. Same as before: no click, no key until the arena is back. Then hold `D` 5 s, `A` 5 s, move the mouse.

- [ ] Back in the arena, same seat
- [ ] Aims
- [ ] Walks

| Line | `keys=` | `focus=` | walking? | aiming? |
|---|---|---|---|---|
| NetStats line 1 | | | | |
| NetStats line 2 | | | | |

Notes:
- 

## 3. Scenario C: the control (a normal join, no reload)

Steps:
1. Open the page fresh, click JOIN, pick a class, click LOCK IN, play one round.
2. During the round hold `D` 5 s and `A` 5 s. Take one NetStats line.

- [ ] Walks (this must work; if it does not, the build is broken, stop here)

| Line | `keys=` | `focus=` |
|---|---|---|
| NetStats line | | |

## 4. Edge cases (only if scenario A or B failed)

Do each one right after a failed reload, in this order, and note whether walking came back. Take one NetStats line after each.

| # | Do this | Walking came back? | `keys=` | `focus=` |
|---|---|---|---|---|
| 4.1 | Click once anywhere on the game picture | [ ] yes [ ] no | | |
| 4.2 | Press Tab, then click the game picture again | [ ] yes [ ] no | | |
| 4.3 | Switch to another window (Alt+Tab) and back | [ ] yes [ ] no | | |
| 4.4 | Press F5 a second time and wait for the arena | [ ] yes [ ] no | | |
| 4.5 | Reload from the address bar (click the URL, press Enter) instead of F5 | [ ] yes [ ] no | | |
| 4.6 | Reload with the mouse button held down while the page comes back | [ ] yes [ ] no | | |
| 4.7 | Reload with `D` held down while the page comes back | [ ] yes [ ] no | | |

Notes:
- 

## 5. Other numbers from the same lines

Copy from the same NetStats lines, so we can see if the machine was struggling at the time.

| Line | `rtt` ms | `fps draw=` | `phys=` | `worst=` ms | `hitches=` | `puppets=` |
|---|---|---|---|---|---|---|
| Scenario A line 1 | | | | | | |
| Scenario A line 2 | | | | | | |
| Scenario B line 1 | | | | | | |
| Scenario C line | | | | | | |

## 6. The verdict

Tick one, using the table at the top:

- [ ] `focus=0` while the keys did nothing: **the page focus is the cause.** Next: the focus self-heal must run later or again (`focus_canvas()` after `assign_id`, `web/shell.html`).
- [ ] `focus=1 keys=0` while holding a key: **the key events are lost in the game.** Next: the InputMap copy in `global.gd` `assign_id`.
- [ ] `focus=1 keys>0` and no walking: **the fighter state.** Next: `player.gd`, with the `🧭 [Spawn]` line and the NetStats line from this sheet.
- [ ] Walking worked every time: **not reproduced on v0.0.29.** Close backlog 13 or keep the probe and wait for the next family evening.

Related: [[PASSDOWN]] (backlog 13), [[v0.0.28 - Rejoin in the Replay Gap]], [[Playtest v0.0.26]] (where the bug was found), [[obsidian_notes]] section 6 (the NetStats fields).

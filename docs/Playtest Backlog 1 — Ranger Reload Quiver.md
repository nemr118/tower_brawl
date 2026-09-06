---
tags: [playtest]
build: v0.0.30
backlog: 1 and 6
result: not played yet
---
# Playtest Backlog 1 — Ranger Reload Quiver

**Result: not played yet. Fill in the boxes below, then paste the console lines into the tables.**

This sheet is for one fix only. Before v0.0.30 a ranger who reloaded the page mid-match came back with the arrows it had left in the quiver, and its stuck arrows on the ground were gone (the new page never saw them). A ranger with 0 arrows was disarmed until the next round. Since v0.0.30 `player.gd` `restore_combat_state` does two things: (1) a save from another round is ignored, so a rejoin after the next round started keeps the fresh quiver; (2) in the same round, a ranger never comes back with less than 1 arrow.

The harness scenario `ranger_rejoin` checks this headless (23/23). Headless clients keep the save in a file. The browser keeps it in `localStorage` under the key `towerbrawl_combat`, and that path has never been watched by a person. That is what this sheet is for.

**Why this test works.** Every rejoin prints one line in the browser console:

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

---

## 0. What we tested on

| Question | Answer |
|---|---|
| PC operating system and browser (with version, `chrome://version`) | |
| Build shown in the lobby (must be v0.0.30 or later) | |
| Second fighter: phone, second PC, or a bot (`godot --headless --path . -- --autojoin --ai=chaser --name=Bot1`) | |
| Date and time (so the `server.log` lines can be found) | |

**How to start**
- Start the server (`./venv/bin/python serve_game.py`) and open `https://192.168.4.21:8443/play` on the PC. If the console says VERSION MISMATCH, reload hard.
- Open the browser console (F12, tab Console) and type `Quiver` in the filter box. One line lands on every rejoin. Switch the filter to `NetStats` for the keys and focus table at the end.
- Pick the **ranger** on the PC. Get a second fighter in. Join, lock in, start.
- Keep `server.log` open on the side: `tail -f server.log | grep -E "JOIN|LEAVE|ROUND"`.

---

## 1. Scenario A: empty quiver, reload in the same round (the bug)

Steps:
1. In a round, shoot all three arrows at the far wall. The quiver row under the fighter shows three grey dots.
2. Do not pick anything up. Press F5.
3. The page comes back in the arena, same seat (`server.log`: `(rejoined mid-match)`), same round.
4. Look at the quiver row and the console line.

- [ ] The page came back in the arena, in the same seat, as the ranger
- [ ] The round number in the banner is the same round you left
- [ ] The quiver row shows **1 yellow dot** (not 0)
- [ ] You can shoot one arrow, and pick it up again from where it sticks
- [ ] The stuck arrows from before the reload are gone (expected, this fix does not bring them back)

Console line (paste the whole line):

| Scenario | `round` | `saved_round` | `arrows` | `charges` | `kunai` | `bear` |
|---|---|---|---|---|---|---|
| A | | | | | | |

Notes:

---

## 2. Scenario B: arrows left, reload in the same round (the control)

Steps:
1. In a round, shoot exactly one arrow. Two yellow dots stay.
2. Press F5. Come back in the same round.

- [ ] The quiver row shows **2 yellow dots** (the save is kept as it was, no free arrow)
- [ ] Console line pasted below

| Scenario | `round` | `saved_round` | `arrows` | `charges` | `kunai` | `bear` |
|---|---|---|---|---|---|---|
| B | | | | | | |

---

## 3. Scenario C: reload inside the replay gap, land in the next round

Steps:
1. Shoot all three arrows, then let the round end on a kill (yours or the other fighter's). The replay starts (`◄◄ REW`).
2. Press F5 while the replay plays. The page comes back inside the 6.5 s gap.
3. Wait for the next round to start.

- [ ] The next round starts at the normal time
- [ ] The quiver row shows **3 yellow dots** at the round start
- [ ] Console: if a `🏹 [Quiver]` line printed, `saved_round` is the old round and `arrows` ends in `->3`. It is also fine if no line printed (the fighter was built at the round start, where everyone gets a fresh quiver).

| Scenario | `round` | `saved_round` | `arrows` | `charges` | `kunai` | `bear` |
|---|---|---|---|---|---|---|
| C | | | | | | |

---

## 4. Scenario D: away past the round start (the hidden phone)

Steps:
1. Shoot all three arrows, let the round end on a kill, then close the tab.
2. Count to 7 (past `new_round` at 6.5 s, inside the 8 s seat grace). Open `https://192.168.4.21:8443/play` again.

- [ ] Back in the same seat, in the running round
- [ ] The quiver row shows **3 yellow dots** (the save named the old round, so it was ignored)

| Scenario | `round` | `saved_round` | `arrows` | `charges` | `kunai` | `bear` |
|---|---|---|---|---|---|---|
| D | | | | | | |

---

## 5. Edge cases (tick what you tried)

- [ ] **Two reloads in a row** in the same round with 0 arrows: the second reload also gives 1 (the first rejoin writes `arrows=1` back to the save on its next movement tick)
- [ ] **Reload with 1 arrow left**: still 1, not 2
- [ ] **Mage**: shoot two fireballs, reload in the same round → `charges=1` in the line and 1 charge on screen
- [ ] **Rogue**: throw two kunai, reload → `kunai=2`
- [ ] **Druid in bear form**: reload → the line says `bear=1` and the fighter is still a bear
- [ ] **Knight**: reload → the line prints with `arrows=3->3` and nothing changes
- [ ] **A different class after the match**: join the next match as a mage after playing ranger; no `🏹 [Quiver]` line (a fresh join is not a rejoin)
- [ ] **Other screens**: on the phone or the second PC, the reloaded ranger's first arrow after the rejoin flies and can hit

Notes:

---

## 6. Keys and focus after each reload (backlog 13 rides along)

Every reload here is also the reload of the open PC keyboard probe. After each rejoin hold `D` for 5 s and read one `📈 [NetStats]` line. If walking ever fails, also fill in [[Playtest Backlog 13 — PC Reload Input Probe]].

| Scenario | walked with A/D? | `keys=` | `focus=` | whole line |
|---|---|---|---|---|
| A | | | | |
| B | | | | |
| C | | | | |
| D | | | | |

---

## 7. The verdict

Tick one:

- [ ] **A gives 1 arrow, B keeps 2, C and D give 3:** the fix works in the browser. Close backlog 1 and 6 (the fallback). The class-kit revisit (arrows in the join snapshot, or slow regen) stays on the later list, item 3.
- [ ] **A still gives 0:** the browser save was not read. Paste the `🏹 [Quiver]` line (or say there was none) and the `localStorage.getItem('towerbrawl_combat')` value from the console. Next: `arena.gd` `_start_round` line ~499 (`Global.rejoined_mid_match`) and `global.gd` `load_combat_state`.
- [ ] **C or D gives less than 3:** the round guard did not fire. Paste the line: `round` and `saved_round` say what the client believed. Next: when `Global.current_round` is set on a rejoin (`global.gd` snapshot handling, `new_round`).
- [ ] **Something else:** write it down with the console lines.

Related: [[PASSDOWN]] (backlog 1, 6, 15), [[v0.0.30 - Ranger Rejoin Quiver]], [[Playtest v0.0.8]] (where the bug was found), [[Commands]] (the console lines).

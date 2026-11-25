---
tags: [reference, design, classes]
date: 2026-11-24
---
# Classes: a scope (a study, nothing built)

The user, 2026-11-24: "Can you scope out adding additional classes? What can we do to make everything unique and balanced? Archer ammo is a concern. I love the pick up ammo mechanic, if we add a melee character, how does that impact ammo recovery? Look at the best ways to add classes for this game, maintaining balance and fun".

This page answers that with numbers from October's nights and from bot matches, and proposes a way in. It builds on D3 in [[Design Decisions v0.2]] ("classes stay, one set of mechanics; the details stay open ... bot fleets to test the balance later"). The bot fleet exists now. Nothing in the game changed for this study: three knobs in `sim/sim.gd` (`start_quiver`, `melee_no_pickup`, `melee_one_hit`) and two probes (`bench/tools/ammo_probe.gd`, `bench/tools/kit_probe.gd`).

## The short answer
1. **Ammo is not scarce today.** A person shoots about 1.5 arrows a round and starts with 3. A round ends before a quiver does. So the quiver's size is a weak lever, and the pick-up mechanic you love decides few rounds.
2. **A melee fighter barely hurts the arrow supply. It hurts the balance.** With one melee fighter in four, an archer's quiver is empty 3% of its time (1% without). But the only melee fighter the game has, the costume, wins 49% of 4-fighter rounds where 25% is fair. Its two-hit toughness is the reason, not its swing.
3. **The best way in: kits.** Every class keeps the archer's rules (one hit, the dodge-catch, fetching arrows) and gets **one perk and one cost**, each priced by the bot fleet before a person plays it. No new button. Classes then differ in what they can do, not in how much they hurt.
4. **A melee class works if it stays in the arrow game:** out at the first hit like everyone, and it throws the arrows it picks up. Bots price that at about fair (+5 points with four, +2 with eight).
5. **Not for Thursday.** It is three or four sessions of work, and the art is the biggest part. This build's TURKEY TROT round is a free first taste of everyone-is-melee.

## 1. What the numbers say

### The arrow game today (people, October)
From the server's own numbers by name (`v2_stats.json`, 24 and 25 October, 1 157 person-rounds):

| | People | Bots (NORMAL) |
|---|---|---|
| Arrows shot a round | 1.4 to 1.6 | 1.8 to 2.4 |
| Arrows caught a round (the dodge-catch) | 0.01 to 0.03 | 0.3 to 0.9 |
| Arrows shot for one arrow knockout | 4.3 to 4.8 | 2.7 to 3.0 |
| Arrow knockouts to stomp knockouts | 382 to 202 (about 2 to 1) | 227 to 83 |

Two things stand out. People use half their quiver in a round. And people almost never catch an arrow: once in 50 rounds. TowerFall's best trick is not part of how the family plays yet.

### How much the quiver matters (bots, `ammo_probe.gd`, 300 rounds a line, no power-ups)
| Each archer starts with | A round lasts | The quiver is empty | Arrows fetched a round |
|---|---|---|---|
| 2 (4 archers) | 8.0 s | 9% of the time | 0.4 |
| **3 (today)** | 7.3 s | **1%** | 0.3 |
| 4 | 7.9 s | 0% | 0.3 |
| 5 | 7.2 s | 0% | 0.2 |
| 3 (8 archers) | 10.9 s | 2% | 0.4 |
| 3 (2 archers) | 4.7 s | 1% | 0.2 |

An archer fetches an arrow once in three rounds. Giving one fighter 1, 2 or 5 arrows moves its wins by 3 points or less (below). A quiver that never empties is worth nothing (+0.5).

**So if the pick-up mechanic should matter more, a class is not the first tool. These are:**
- everyone starts with 2 arrows (empty 9% of the time: fetching becomes a real choice, at no cost in art or code);
- kits that spend arrows fast (a two-arrow volley) or that are good at getting them back (below);
- anything that makes rounds longer.

### What a melee fighter does to the arrows (`ammo_probe.gd`)
The melee fighter here is the costume (THE BIG TURKEY, GHOSTFACE): no bow, a short swing with a lunge. It brings no arrows to the round.

| The match | An archer's quiver is empty | Arrows lying around | Arrows caught a round | Each melee wins | Each archer wins |
|---|---|---|---|---|---|
| 4 archers | 1% | 1.0 | 0.31 | | 25% |
| 3 archers, 1 melee that pockets arrows | 3% | 0.7 | 0.22 | **49%** | 17% |
| 3 archers, 1 melee that leaves arrows | 3% | 0.9 | 0.21 | 47% | 17% |
| 2 archers, 2 melee (pockets) | 5% | 0.5 | 0.08 | 38% | 12% |
| 2 archers, 2 melee (leaves) | 3% | 0.7 | 0.06 | 36% | 14% |
| 8 archers | 2% | 1.9 | 0.33 | | 12% |
| 6 archers, 2 melee (pockets) | 3% | 1.3 | 0.23 | 26% | 8% |
| 4 archers, 4 melee (pockets) | 4% | 0.8 | 0.12 | 20% | 5% |

What it means for ammo recovery:
- **Fewer arrows enter the round.** Each melee fighter is three arrows that never come. With half the fighters melee, half as many arrows lie around.
- **A melee fighter ends a round holding 0.6 arrows:** about 0.3 it walked over and 0.3 it caught with its dodge. If it cannot pocket the ones it walks over, the archers get those back (0.9 lie around, not 0.7).
- **Both effects are small** because rounds are short: the archers' empty time goes from 1% to 3 to 5%.
- **The catch gets rarer:** with two melee in four, a third as many arrows are caught. Fewer arrows fly, so there is less to catch.
- **The balance is the real problem:** the costume wins about double its share at every size.

### What a perk is worth (`kit_probe.gd`: one fighter has the kit, the rest are plain archers; 600 rounds a line; power-ups on)
| The kit | Wins with 4 (fair 25%) | Wins with 8 (fair 12.5%) |
|---|---|---|
| Plain (the control) | 25.7% | 9.3% |
| Starts with a SHIELD | **37.8%** (+12.8) | **24.0%** (+11.5) |
| Starts with 1 arrow | 19.8% (-5.2) | 11.0% |
| Starts with 2 arrows | 22.3% (-2.7) | 10.8% |
| Starts with 5 arrows | 22.2% | 11.8% |
| A quiver that never empties | 25.5% | 13.0% |
| Big arrows | 28.2% (+3.2) | 12.2% |
| Wings (flies all round) | 33.7% (+8.7) | 16.2% (+3.7) |
| Runs 1.6 times as fast | **43.5%** (+18.5) | **24.2%** (+11.7) |
| 2 arrows and a SHIELD | 39.3% (+14.3) | 19.0% (+6.5) |
| Melee: the costume as it is (two hits) | **48.7%** (+23.7) | **34.3%** (+21.8) |
| Melee, out at the first hit | 30.3% (+5.3) | 14.2% (+1.7) |
| Melee, first hit, with a SHIELD | 49.5% (+24.5) | 31.7% (+19.2) |
| Melee, first hit, 1.6 times as fast | 41.8% (+16.8) | 29.2% (+16.7) |

One standard error is 1.8 points with 4 and 1.4 with 8. The control with 8 came out 3 points low, so read that column as "about".

**What the price list teaches:**
- **A second life and speed are the expensive things.** A SHIELD at the start is +12 points. So is running fast. The costume's knock-down is +24.
- **Arrows are cheap.** Fewer arrows is not a real cost, and more arrows is not a real perk. "2 arrows and a SHIELD" is still +14 with four.
- **A plain melee fighter is not weak.** Out at the first hit, with no arrows at all, a melee bot still wins a little over its share. Bots chase perfectly; people will do worse. But it is close enough to tune.
- Bots are not people. The costume won only 4 knockouts in 18 turns for October's people before its lunge. The list shows what is far off, not the last percent.

## 2. Principles (what keeps classes unique, balanced and fun here)
1. **One hit ends you, so classes differ in what they can DO.** Not in damage, and not in health: a second life is the most expensive thing on the list.
2. **Everybody stays in the arrow game.** Every class can dodge-catch and fetch arrows. A class with no bow still needs a use for an arrow it holds, or it becomes a hole the arrows fall into.
3. **One perk, one cost, both with a price.** A kit ships when the fleet puts it within 5 points of fair with 4 and with 8 fighters. Then the night's log checks people: each person's win share in a kit beside their own share as a plain archer.
4. **No new button.** Kids play on phones with two thumbs. A kit rides on what is there: the pull and let-go, DODGE, jump, a stomp.
5. **Costs that leave the moves alone.** The bots walk a route map built from what the archer's body can do (`sim/routes.json`). A kit that runs slower or jumps differently needs its own map and its own proof. A slower bow, a longer dodge cooldown or a smaller quiver cost nothing there.
6. **Readable at 5 mm.** On a phone a fighter is 5 mm tall. A class must show in its outline (a helmet, a shield, wings) while the seat's colour stays the player.
7. **The bots must play every kit.** A kit the bots cannot play cannot be priced, and cannot fill an empty seat.
8. **Kits are also the kindest handicap.** A SHIELD kit for the youngest is the catch-up help, chosen instead of handed out.

## 3. A melee class that lives with the arrows
Three ways, and the one to pick:
- **A. The costume as a class.** No. It is double its fair share, takes arrows out of play, and makes the catch rare.
- **B. A melee fighter that kicks arrows** (it cannot hold one; an arrow it walks over skids a few steps). Keeps the supply whole, but the class stands outside the arrow game.
- **C. THE BRAWLER: it throws what it holds (recommended).** No bow. A quick pull and let-go swings, with the costume's lunge. A long pull throws a held arrow by hand: slower than a bow shot and falling sooner, so short range. It starts with 1 arrow, holds 2 at most, and is out at the first hit. Its dodge still catches.

Why C: it keeps the user's rule from D0 ("keep classes, but they need ammo"). The Brawler wants every arrow that lands near it, so archers and Brawlers fight over the same arrows on the floor, which is the mechanic you love. It brings an arrow to the round instead of none. And it needs no aim for its main move, so it is the easy class for the youngest (the October kids let go inside the ring on 20 to 37% of their shots).

Its price to start from: melee at the first hit with no arrows is +5 with four and +2 with eight. The thrown arrow adds a little. Tune with the lunge (9.5 px a tick now), the swing's reach and its cooldown; never with a second life.

## 4. A first roster
Four kits, one for each kind of thing a fighter can be good at. Each perk has a measured stand-in; each cost is one that leaves the moves alone.

| Kit | Shoots | Perk | Cost | Starts from |
|---|---|---|---|---|
| **ARCHER** | the bow, 3 arrows | none: the game as it is | none | 25% |
| **KNIGHT** (defence) | the bow | starts each round with a SHIELD | a slow bow (the pull takes longer to arm), and 2 arrows | SHIELD is +12.8; 2 arrows takes back 3; the slow bow must take back the rest |
| **SCOUT** (movement) | the bow | a second jump in the air | 2 arrows, a quiver of 3 at most | wings all round is +8.7; one air jump is a part of that |
| **BRAWLER** (melee) | a swing; throws held arrows | the lunge; no aim needed | no bow, 1 arrow, short reach | +5.3 |

Two more for later, both about fetching:
- **RETRIEVER:** its dodge-catch reaches twice as far and it fetches arrows from twice as far; it starts with 1 arrow. The class for someone who loves the pick-up game.
- **TRICKSTER:** the first arrow it shoots each round comes back to its hand after it sticks. Starts with 2.

And one for the youngest: the KNIGHT with no cost, as a lobby switch a grown-up sets (the catch-up SHIELD, by choice).

Left out on purpose: a mage whose bolts vanish (ammo you cannot fetch breaks principle 2), anything with a cooldown button (principle 4), anything with health (principle 1).

## 5. What it costs to build
| Part | What | Size |
|---|---|---|
| The rules | A kit number per fighter in `sim/sim.gd`, one table of each kit's numbers (`sim/kits.gd`), the kit in the fighter's state so the page's copy predicts it | small |
| The KNIGHT | A SHIELD at the start exists. New: a pull that arms later for this kit | small |
| The BRAWLER | The swing and lunge exist (the costume's knife). New: out at the first hit, the hand throw, holding 2 | medium |
| The SCOUT | New: the air jump in the moves, in the page's prediction, and a second route map for the bots | medium to large |
| The bots | The melee chase exists. New: a Brawler that goes for arrows; a Scout that uses its jump | medium |
| The lobby and the HUD | A kit picker on your own card, a small emblem on every card, a HOW TO PLAY card a kit | medium |
| The art | The fighters are drawn by code from a pose table (`bench/tools/gen_assets.gd`: a hood, a cape, a bow). A kit is a new head, a new prop and its poses, in 8 colours: about a session a kit. A sheet is 2 MB of texture, so a kit's sheet loads when a seat picks it | large |
| Sound | A swing, a throw | small |
| The proofs | `kit_probe.gd` as the gate, the rule probes, a soak, then a night | medium |

In order:
1. **Kits v1:** the table, the KNIGHT, the picker, the emblems. The smallest step that puts a choice in the lobby. One session.
2. **The BRAWLER** as a class, with its art. One or two sessions.
3. **The SCOUT**, with its route map. Two sessions.
4. **A night with the family, then tune** from the log (the round's line would name each seat's kit).

## 6. Questions that are the user's
1. **Should ammo matter more for everyone?** Starting with 2 arrows makes a quiver run dry 9% of the time and costs nothing to try: one number (`START_QUIVER`). It is the cheapest test of "do we like fetching more".
2. **The Brawler: thrower (C) or kicker (B)?**
3. **Can two players pick the same class?** Yes is simpler, and kinder to kids who all want the Brawler.
4. **Names and looks:** knights and scouts of the castle, or silly ones by the season (a turkey Brawler in November)?
5. **Teams and classes together?** A KNIGHT beside a small kid is the best pair this game could offer. Teams come first (this build).

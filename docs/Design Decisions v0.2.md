---
tags: [design, decisions]
---
# Design Decisions v0.2

One entry per decision, written when the user makes it: the decision, the options not picked and why, open questions. Research: [[towerfall-research]], [[dead-cells-research]], [[sim-server-design]]. The plan: [[v0.2-transformation-plan]] (draft 2).

## Decided

### D0. Closer to TowerFall Ascension — decided 2026-09-10 (the user)
- **Decision:** v0.2.0 moves toward TowerFall Ascension, the game that inspired Tower Brawl and brought the kids in. Keep classes, but they need ammo and all the features that make TowerFall feel like TowerFall. Keep the 360 degree aim. Maybe a guided arrow powerup. Improve on the TowerFall formula; less brawler.
- **Not picked:** working through the brawler decision list as it was (29 was first, with 8 seats, rotating seats or two rooms).

### D0b. The vision: TowerFall play, Dead Cells look, 8 players, a simulation server — decided 2026-09-10 (the user, second message)
- **Decision, in the user's words:** "I love the TowerFall gameplay, but I'd like to lean towards the Dead Cells style art. I think we build a super arena for 8 people, inspired by TowerFall. Clever ledges, balance, physics of TowerFall. Keep a Dead Cells style art style. Higher res (90px) characters, so still pixelly, but not quite as much as TowerFall. Keep classes, but align the mechanics. I'd also like to switch to a simulation based server instead of the relay."
- **This settles:** D1 (a super arena for 8, TowerFall-inspired; its size is D13), D3 in principle (classes stay, one set of mechanics; the details stay open), D6 (a simulation server), D8 (8 players), tower build 2 (replaced by the super arena), the art direction (Dead Cells style, 90 px fighters; the route is D14).
- **Not picked (draft 1's recommendations):** 640 x 360 single screens at 2x TowerFall scale; "you die on your own screen" on the relay; 4 players then 6.

### D0c. Benchmark TowerFall, differ on purpose — decided 2026-09-10 (the user, third message)
- **Decision, in the user's words:** "I want towerfall gameplay, but with a more modern art style like dead cells. It doesn't have to the same pixel by pixel either, we want to be unique. If we base combat numbers like jump height, arrow speed, etc, we should be benchmarking towerfall and we have the whole decompiled code to take a peek at. Where I want to deviate from towerfall is player size, arena size, art, variant in characters." Keep the arrow ammo and fetching spent ammo. Characters must not be carbon copies of each other; how they differ is open (loadouts, classes, even Diablo 2 style loot).
- **What it means:** every combat number starts from TowerFall's value in the decompiled code, scaled to our size. A tuning table keeps "TowerFall's number → ours → why" for each one. The art is modern and our own, with Dead Cells as the inspiration, not a pixel-exact copy. D3 is reopened as "how characters differ".
- **First step:** the 8-player benchmark of the server and the phones ([[bench-8p-plan]]).

**How the old list folds in:**

| Old item | Where it goes |
|---|---|
| 16 the stomp-egg has no author | the egg goes (D4); the server decides every hit (D6) |
| 17 seam hiding | fighters and arrows drawn on both sides of an edge (G2) |
| 18 the archer kit | the whole arrow game: anyone picks up, steals, catches (G3) |
| 21 the air shield feel | goes with the specials (D4) |
| 28 a round clock | the miasma (D2, G4) |
| 29 more than four players | decided: 8 (D0b) |
| Tower build 2 | decided: the super arena (D0b, G5) |
| A v0.2.0 tag | D12, D17 |
| Watching 3, 13, 20, 25, 26 | end with the relay and `move_and_slide`, unless they come back |
| Ideas | skip key: G4. Sound: G9. Stats views: a death-spot map in G6, awards later. Sim server: decided. The `ws_client_thread` read: dropped (the relay retires). |

## Open (one at a time)

### D2. Lives and the round clock
- **A. One life a round, and the miasma** (recommended): Last Man Standing, the miasma at 25 s with TowerFall's timings, the 1.5 s wait at the round end, the crown, autobalance on.
- **B. Keep 3 stocks and the respawn, add the miasma.** Longer rounds, less tension per shot.
- **C. Keep stocks, add a plain timer.** Simplest; least like TowerFall.
- **Open:** points to win with 5 to 8 players (TowerFall: 5 / 4 / 3 for 2 / 3 / 4; 3 is the natural guess for more). Headhunters as a second mode later?

### D3. How characters differ (reopened by D0c; open for ideas)
Every character keeps TowerFall's movement, the one-hit kill, the dodge catch, and ammo you fire and fetch again. One fact shapes every option: **with one-hit kills, "more damage" means nothing.** So characters differ in what they can *do*: ammo types and quiver size, getting around (double jump, a long dodge, wings), defence (a shield charge), reach (a melee swing), senses (seeing hidden quivers), tricks (steals, traps).
- **A. Classes with one perk and one cost** (draft 1). Easy to learn and to balance.

| Class | Ammo | Perk | Cost |
|---|---|---|---|
| Ranger | arrows | starts with 4; arrows bend twice as much | none: the plain archer |
| Knight | throwing axes | starts every round with a shield | top speed -15% |
| Mage | crystal bolts | a long dodge (x1.6) | dodge cooldown x1.5 |
| Rogue | kunai | a side bump steals even when your quiver isn't empty; quiver hidden | starts with 2 |
| Druid | thorn darts | double jump | quiver max 4 |

- **B. A loadout:** pick a ranged weapon (bow, crossbow, throwing axes, kunai: each its own ammo to fetch), a melee weapon (a short swing, maybe one that knocks arrows away), and one or two equipment slots (shield charm, wing boots, a bigger quiver, a grapple). Chosen in the lobby. Many combinations.
- **C. Loot during the match** (Diablo 2 style): chests and kills drop gear with rarities (common, magic, rare) and random bonus lines ("+1 quiver", "dodge cooldown -10%", "arrows bend more"), kept for the round or the match. Every match plays differently; balance comes from rarity and caps, not from classes.
- **D. A mix:** the class sets your look and one signature item, a small loadout on top, and chests drop loot during the match.
- **Not decided.** The benchmark comes first. This deserves its own session, and bot fleets to test the balance later.

### D4. Defence
- **A. The TowerFall dodge replaces the dash and all specials** (recommended): 8 ways, catches arrows, can be cancelled, 0.42 s cooldown. The knight shield, blink, bear, air shield, egg, shadow dash, recoil shot and spawn bubble all go.
- **B. The dodge plus a class special on a long cooldown.** More to learn and balance; more brawler.

### D5. Shooting
- **A. Hold to aim, let go to fire** (recommended). On the ground you stand still while aiming. 360 aim with aim help (162 px, 65°) and the small bend (315 px, 40°). Twin sticks: the right stick aims while held and fires when let go.
- **B. Fire on press with a cooldown** (today).
- **Open:** how strong the aim help should be for the kids; an option to turn it off.

### D7. The guided arrow
- **A. Steered by the player** (recommended). After the shot, keep holding shoot and the aim steers it (about 180° a second, no gravity while steered) for up to 1.5 s; you can move but not shoot while steering. Two per chest. Our own addition, not in TowerFall.
- **B. TowerFall's bolt:** it seeks on its own and turns up to 90° to miss a wall. No new control.
- **C. Both:** bolts in chests, steering as a class perk.
- With the simulation server both are easy: the server flies it from the owner's inputs.

### D9. Sound
- **A. In v0.3.0 with the look** (recommended, G9). A lot of TowerFall's feel is sound. Our own or free sounds only.
- **B. Earlier,** as placeholder sounds in v0.2.0.

### D10. The physics
- **A. Our own whole-pixel mover** (recommended): actors and solids like TowerFall, for fighters, arrows and chests. The same result on the server and the client makes prediction and reconciliation clean. *Risk:* new collision code; `archer_probe.gd` covers it.
- **B. Godot's `move_and_slide`,** tuned. Its floor flicker (behind backlog 20 and 25) would show up as prediction corrections.

### D11. The brawler while we build
- **A. It stays on the relay, untouched, and is what the laptop runs until v0.2.0** (recommended). The new server runs on its own port beside it.
- **B. Freeze it now,** and pause family nights until the new game is playable.

### D12. What must be true before the v0.2.0 tag (draft)
- A family night on the laptop in the new game: the sheet verdict is "ship".
- The harness on the simulation server: every scenario passes, no Minor.
- A 3-hour 8-bot soak on the laptop: no stall, no round over 55 s.
- The relay and the brawler removed.
- The runbook of [[release-v0.1.0]], updated.

### D13. The arena's size
- **A. One 1920 x 1080 screen, TowerFall's numbers x4.5, fighters shown at their full 90 px on a 1080 px screen** (recommended). Everyone always visible; wrap on all edges. *Risk:* 8 in free-for-all is more than TowerFall allowed (6); spike G0c measures it.
- **B. A bigger arena (for example 2400 x 1350) scaled down to fit.** More room; fighters show about 72 px tall on a 1080 px screen, and the down-scale smears the pixel art.
- **C. Bigger than the screen, with a camera that zooms out to keep everyone in view.** Room for anything; the wrap gets awkward with a moving camera, and fighters shrink when the group spreads out.

### D14. How the fighters get into the game
- **A. Bake sprites, like Dead Cells** (recommended): the prototype renders every clip frame at 90 px with no anti-aliasing into colour, normal-map and player-colour mask sheets, and the arms and weapon as a layer at 24 aim angles. Cheapest for phones; a bake after every change; aim pictures in 15° steps.
- **B. Draw the 3D models live** (the prototype's session-4 plan). Exact aim, no bake; unmeasured cost for 8 fighters on phones; 2D and 3D lights to keep in step.
- **The look (D0c):** modern and our own, not pixel-exact; either route can draw hard or soft edges.
- **The gate:** the benchmark's tier T4 ([[bench-8p-plan]]) measures live 3D on the phones. A, unless B holds 60 fps on the weakest phone.

### D15. The netcode model
- **A. The server simulates, clients predict their own fighter, inputs land on their tick, our own packets** (recommended, [[sim-server-design]]).
- **B. Rollback for everyone.** Too heavy for 8 fighters on phones in a web build; needs bit-identical results on every device.
- **C. netfox.** A faster start, but built on Godot's high-level multiplayer API, so the harness bots, the deck and the stats would all be redone.

### D16. What the Python server keeps
- **A. Only the web files** (recommended); the Godot server owns the lobby, seats, rounds, logs and status.
- **B. The lobby,** with a Godot process per match behind it. Two sockets or a proxy; rules in two languages.

### D17. The milestones
- **A. v0.2.0 "The Sim"** = the new game on the new server with flat placeholder art; **v0.3.0 "The Look"** = Dead Cells art, effects and sound; **v0.4.0** = treasure, the guided arrow, class perks (recommended). The family plays the new game early, and the art gets the time it needs.
- **B. One big v0.2.0** with everything. Nothing new to play for a long time.
- **C. Art first, then the server.** The art would be judged on a game about to change underneath it.

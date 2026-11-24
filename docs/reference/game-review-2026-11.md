---
tags: [reference, review, ideas]
status: review 2026-11-23 (the two October nights' logs, today's build, the code; the ROG was off, so there are no newer logs)
---
# Game review and the Thanksgiving plan (2026-11-23)

Why: the user: "Do a review of the game. It's almost Thanksgiving and I want to do an update for the Holiday. Look at ways to makes some fun thanksgiving themed power-ups and maps. Review the game overall, look for way to improve it". Thanksgiving is Thursday 2026-11-26.

What this stands on: the server's logs of the two October nights (448 rounds, 59 matches; `playtest_logs/2026-10-26_rog/`), pictures of today's build as a phone sees it, the code, and a helper's bug hunt through the server and the rules. Older idea pages: [[holiday-ideas]], [[dynamic-ideas]], [[mobile-controls]].

## The short version
1. **The game holds up.** The server never crashed in two nights. Rounds are quick at every size. Small groups work.
2. **Inside a match it is still Halloween.** The lobby went back to the castle on 3 November, but candies, TRICK OR TREAT, PUMPKIN HEAD and GHOSTFACE still drop on every arena, and two of the four arenas are spooky.
3. **A Thanksgiving set fits**, and most of it can reuse rules that already work, with new pictures. The new parts: a turkey to chase, a pie in the face, a barn.
4. **The numbers point at three fixes:** the catch-up power-ups mostly miss (40% taken), the friendly things come late, and first-time players get almost no help.
5. **Three builds have never been judged on real phones** (p4.15, p4.16, p4.17). Thanksgiving would be their first real test. A 15-minute family check before Thursday is worth more than any new feature.

## What the October nights say
| Measure | 24 October (p2.1 to p4.8) | 25 October (p4.9 to p4.14) |
|---|---|---|
| Rounds, matches | 191, 28 | 257, 31 |
| People at once, at most | 4 | 4 |
| Fighters in a round, most often | 4 (125 rounds: four people, no bots) | 3 (112 rounds), then 2 (82), then 4 (62) |
| A round lasts (median) | 12.5 s | 11.2 s |
| A match | 6 rounds | 8 rounds, 2.2 minutes, then 20 s in the lobby |
| Round time a person spends out | 33% | 17% (ghosts came that day) |
| Draws | 6 | 9 |
| Server errors | 0 | 18, all one known log line (GHOSTFACE) |

- **Pacing is fine at every size.** 2 fighters: a median 8.0 s. 3 fighters: 14.5 s. 4 fighters: 12.7 s. 8 fighters: 11.6 s. The big arenas do not feel empty in the numbers.
- **The family plays with few bots.** On 25 October every round but one had 2 to 4 fighters. The server starts with 7 bots each time, so someone taps them away every time.
- **Bots are a fair match.** On 25 October people won 75% of the rounds they were in; by seat count alone it would be 82% (24 October: 79% and 84%).
- **Who wins:** on 24 October four people played, mostly without bots. One won 38% of their rounds, one 20%, two won 15% each. A fair share is about 25%.
- **The catch-up power-ups mostly miss.** 111 BIG orbs came "for someone behind". 44 were taken (40%), 18 of those by bots. Nothing on the screen tells a player that an orb is for them.
- **The black cat:** petted 17 times in the night. It shows up 6 to 12 s into a round; by 9 s a third of rounds are over.
- **A BIG orb looks the same to everyone:** bigger, with a gold ring. The server already sends who it is for (`for_seat`); the page never uses it.
- **Candies:** 56 opened: about 21 treats, 17 tricks, 18 GHOSTFACE. GHOSTFACE's knife got 4 of the night's 505 deaths.
- **Names:** 5 of the night's 10 player names were "Player 1" to "Player 5". Kids skip the name box.
- **Deaths (25 October):** arrow 279, stomp 111, blast 46, a furnace 17, poison 14, the walls 14, lightning 10, a ghost cat 6, fire 4, the knife 4.
- **Phones:** iPhones ran 15 to 30 fps. p4.16 has the fix, not yet seen on a real iPhone.

## Thanksgiving: the Harvest Feast
The theme: the harvest, the feast, turkeys, autumn leaves. (No costumes of peoples: the repo is public.) Halloween's rules for a holiday still hold ([[holiday-ideas]]): rare and special, always a way out, easy to read at 90 px, the bots can use it, the same rules on the phone. The logs add one: **it must show up in a round's first 5 seconds**, or half the rounds never see it.

### A. The season switch (the base for every holiday)
- The server knows the season: AUTO by its date (Halloween 1 October to 2 November, the Harvest 3 to 30 November, else none), or a pick on the host page and in the lobby (AUTO, OFF, HALLOWEEN, HARVEST). Kids can have Halloween in June.
- The server sends it, so every phone matches. Today each phone reads its own date for the lobby, and the candies are always Halloween's.
- The season picks the skins below, the lobby's dress, the loading picture and the winner's backdrop. Cost: medium.

### B. New pictures on rules that already work (cheap and safe)
The rules stay the same, so the bots and the phone's prediction need nothing new.

| Today | In the Harvest season |
|---|---|
| A candy: TRICK OR TREAT | A covered dish: WHAT'S FOR DINNER? Lift the lid: a treat (a power-up) or a trick |
| Trick: PUMPKIN HEAD (a hopping pumpkin, no shots, 3 s) | TURKEY TIME: you are a hopping, gobbling turkey, no shots, 3 s |
| Trick: BACKWARDS (3 s) | TOO MUCH PIE: you are dizzy, left is right, 3 s |
| Trick: TINY (6 s, the look only) | PEA-SIZED: the same, as small as a pea |
| PUMPKIN BOMBS (seeds that pop) | POPCORN ARROWS: a corn cob that bursts into popping kernels |
| Bats sweep THE HAUNTED HOUSE; BAT SWARM | A gust of leaves sweeps THE HARVEST BARN; CROWS circle you |
| The black cat (pet it: a SHIELD) | The turkey (below) |
| GHOSTFACE | THE BIG TURKEY (below) |

Cost: medium for the whole table (new drawing code, new names, four new badges).

### C. Three new things
- **Catch the turkey.** A turkey runs onto the floor 2 to 4 s into most rounds on the barn (a quarter of rounds elsewhere). It runs away from whoever is near and hops off ledges. Touch it: it gobbles, drops a power-up for you and leaves in a puff of feathers. Arrows only make it jump. Bots chase it a little. Why: a chase is the funniest thing a turkey can do, and it gives a player who is behind something to do besides hide. Cost: medium (the cat's code plus running away).
- **PIE.** An arrow kind: every arrow is a pie. It bursts like a small bomb, and everyone near the splat is covered in cream for 3 s: they cannot see the others (the smoke rule), and their own screen gets a big cream splat. Why: a pie in Dad's face. Cost: medium (the bomb and smoke rules joined, one new picture layer). The bots lose sight the way smoke makes them.
- **THE BIG TURKEY** (the costume, from a dish about 1 time in 3, GHOSTFACE's rules): no bow this round; let go of shoot to peck. A hit knocks you down 2 s in a burst of feathers; a hit while you are down ends you. Drawn big and round: a brown body, a fan tail in orange, red and gold, a red wattle, your colour as a scarf. Cost: medium (drawing code only; the rules are GHOSTFACE's). GHOSTFACE's knife got only 4 kills in 18 turns, so both costumes should get a short lunge with the swing: see "the game overall".

### D. Maps
- **THE HARVEST BARN** (new): a barn cut open, like the haunted house. Hay bales to stand on, a loft, ladders as ledges, lanterns for torches, a pumpkin patch and corn outside, a low orange sun. Leaves fall all round; a gust of leaves sweeps through now and then (the bats' rule: it hides you and drops arrows). The turkey lives here. Cost: large (a text map, its probes, the bots' routes, the look).
- **THE BIG TABLE** (new, the stretch): you are tiny on the Thanksgiving table. Plates and pie tins are platforms, candlesticks are pillars, forks and spoons are ledges, the roast on its platter is the middle block, a gravy boat on one side. Cost: large. The most "wow" of the set, and the one to drop first if time runs short.
- **Autumn on THE KEEP and THE BRIDGES** while the season is on: falling leaves, pumpkins and hay by the walls. Cost: small. THE HAUNTED HOUSE and THE BOILER ROOM stay in the picker; in the Harvest season MIX leaves them out.

### E. The look around the match (ComfyUI, on the user's go)
A harvest loading picture; a harvest dress for the lobby (autumn colours, HARVEST FEAST on the ribbon, a pumpkin pie as the O of TOWER); the winner's screen at a feast hall; arena cards for the new maps; badges for the dish, the tricks, PIE, POPCORN and the turkey. About 60 pictures, about 10 minutes of the card. Cost: medium to wire in.

### F. Awards
GOBBLE GOBBLE (caught the turkey most), PIE FACE (creamed most), STUFFED (opened most dishes), LEFTOVERS (picked up most arrows), and a line on every award card: "thankful for ...". Cost: small.

### What fits before Thursday
Two and a half days. In this order, so the night has a full set even if the last parts slip:
1. The season switch, the dish and its tricks, popcorn, the autumn dress, the harvest lobby and loading pictures.
2. Catch the turkey.
3. THE HARVEST BARN.
4. PIE and THE BIG TURKEY.
5. THE BIG TABLE, the awards.
Each look is shown BEFORE/AFTER first. The deploy needs the ROG switched on and a go.

## The game overall: what to improve
Ranked by what the logs and pictures show, not by size.

1. **Catch-up help that cannot miss.** Small.
   - A person 2 or more points behind the leader starts the round with a SHIELD (TowerFall's own autobalance rule).
   - A BIG orb that lands for you gets an arrow on your own screen and the words FOR YOU.
   - Why: 60% of BIG orbs were never taken, and two players won 15% of their rounds where 25% is fair.
2. **A HOW TO PLAY card for first-timers.** Small. Three big pictures the first time a phone joins (run and jump; pull back and let go to shoot; DODGE catches arrows), and a "?" button in the lobby. Why: kids let go inside the ring on 20 to 37% of their shots in October, and a holiday brings new players.
3. **Friendly things come early.** Small. The cat at 2 to 5 s, not 6 to 12 s. The turkey starts that way.
4. **THE BIG SCREEN.** Medium. A page for a TV (`?tv`, on the ROG's own screen or HDMI): the match full screen with big names and points, no lobby panel over it; between matches the line-up, the awards, and a QR code to join. Why: on a phone a fighter is about 5 mm tall, at most 4 people played at once, and a holiday room has more watchers than players.
5. **Tap your name.** Small to medium. The join screen shows the names the server has seen as big buttons, and "someone new". Why: half the players never typed one; the night's numbers and awards then belong to a person, and a season board becomes possible.
6. **The costumes hit harder.** Small. A short lunge with the knife (and the peck), so turning into a character is a treat, not a loss. Why: 4 kills in 18 turns.
7. **Sound.** Medium to large. The game has none. Start with one device in the room (the big screen): a countdown, FIGHT, hits, the turkey's gobble, the winner's tune. Phones stay silent unless switched on. The biggest gap in how the game feels, and the one that needs the most care (8 phones in one room).
8. **Teams and pairs.** Medium. A kid with a grandparent; the last team standing scores. From [[dynamic-ideas]]; still the best way to let the youngest win.
9. **Bots follow the group.** Small. The server remembers the lobby's settings over a restart, or BOTS becomes "fill to 4 fighters". Why: 7 bots every start, and the family plays with 0 or 1.
10. **Two fighters start opposite each other.** Small. Known since p1 (spawns are shuffled). Why now: 87 of 448 rounds had just 2 fighters.
11. **Fewer words on a phone.** Small. With 8 fighters the picture is busy: a word over every orb, chips under every card, tips. Words only on your own things, pictures for the rest.

**Leave alone:** the round length, the walls at 25 s, the bots' level, ghosts, the server's network code. The numbers say they work.

## Bugs the code hunt found (a helper, 2026-11-23)
It read the server, the rules and the page in full, ran its own probes on a test server, and checked the October logs. I checked the main ones again in the logs. Most harmful first.

1. **A dropped phone loses its seat after 8 s** (`game_server.gd` `HOLD_TICKS`). The fighter plays on as a bot; the person comes back to the lobby view, must tap JOIN, gets the lowest free seat (maybe another colour) and 0 points. On 25 October: 33 drops, 17 came back in time (3 to 8 s), 16 lost the seat. Fix: hold a seat 60 s during a match, and let the page take its seat back by itself.
2. **After a phone freezes for 2 s or more, its clock can run far ahead and never come back** (`net.gd`: one false long ping). Seen in a probe: after a 3 s freeze the page ran 176 ticks ahead and drew its own fighter 100 to 540 px off until a reload. Fix: cap the ping the clock uses at 300 ms, and clamp the server's margin byte.
3. **A freed seat's fighter stays in the round and can win it.** The banner then says " WINS THE ROUND" with no name, and the point goes to an empty seat. 6 times in the two nights. Fix: take that fighter out of the round, or keep the name and points to the round's end.
4. **The round's winner can still be killed in the 1.5 s before the point** (an arrow in the air, a blast, poison). The banner says X WINS over X's body, and the point counts. 10 of 248 rounds on 25 October, one of them a match point. A rule to pick: the winner is safe once the round is called, or nobody scores.
5. **The server never notices a silent phone.** A frozen page keeps its seat with its last buttons held down, round after round; and a phone that returns on a new socket gets a second seat. Fix: no packet for 3 s counts as a drop; a known token takes its old seat over.
6. **After a server restart, an open page plays without prediction** until it is reloaded (`predict.gd` keeps the old server's tick). Fix: reset it when the socket opens.
7. **A thumb already on the glass when the sticks appear is ignored until lifted** (kids rest their thumbs through 3-2-1). And a cancelled touch fires an armed shot. Fix: take an unknown touch as a new one.
8. **SKIP works from the replay's first frame, with one tap, for everyone**, and sits where right thumbs play. 10 of 31 matches were skipped, 4 within 2 s. Fix: SKIP wakes up 2 s in, away from the JUMP corner.
9. **The winner's screen gets what the replay leaves of 12 s:** 6.2 s after a 1-kill replay, 3.6 s after 3 kills, 0.8 s after 6. The awards and p4.17's painted screen live in that rest. Fix: the server adds the replay's length (it knows the winner's kills) to a fixed 8 s.
10. **Four lists in the page only grow** (`net.gd`, `predict.gd`): about 1.3 MB an hour. Fix: cap them.
11. **After 5 s without a connection every lobby says "ONE MORE STEP: open https://.../v2ws"**, which is wrong advice after a Wi-Fi blip. Fix: only when the socket never opened.
12. **A socket that closes while the send path is blocked keeps its seat "on"** (rare; a host kick clears it).

**Looked solid:** no stuck phase; join, leave, kick, start, stop at every phase edge; a 9th phone (FULL, then JOIN when a seat frees); power-up state between rounds and matches; the server's memory over 8 hours (flat within 3 MB).

## Housekeeping
- **p4.15, p4.16 and p4.17 have no night on record.** The wall moves, the BUTTONS layout, the iPhone speed-up and the new winner's screen are unjudged. Before Thursday: 15 minutes with two or three phones, one of them an iPhone. Watch for the white screen, the frame rate, and a stutter when the winner's screen comes up.
- **The ROG was off on 2026-11-23** (no answer on Tailscale, the wire or Wi-Fi). It has to be on for a deploy, and its logs since 26 October are still on it.
- **The GHOSTFACE log line** (`game_server.gd` `_log_powers`): 18 script errors in one night, each losing that tick's power lines. A two-line fix, still waiting for a go.
- **The open sheet** ([[Playtest v0.2.0-p4.14]]) has no verdict; the home laptop runs p2.1; the release v0.2.0 (G7) is not cut.
- **The README** still describes the old game (4 hero classes). The repo is public: it should show the new one (8 seats, phones, the arenas).

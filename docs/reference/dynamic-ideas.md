---
tags: [reference, ideas]
---
# Fresh matches: ideas and holiday themes (research 2026-10-24)

What other party games do to keep rounds fresh, and what fits our family. Tonight's build (lightning orbs, power-ups, catch-up items, the Halloween arena) is not repeated. TowerFall's rules: [[towerfall-research]].

Two limits: the phone predicts your own fighter (`predict.gd`), so whatever moves you (wind, low gravity, moving floors) must run the same there. The bots walk by a route map (`routes.json`) made for normal jumps.

## The five best next ideas for us
**1. Ghosts: keep playing after you are out.** You come back as a see-through ghost that flies through walls. Shoot = a BOO dash that shoves a living player. An arrow pops a ghost for 3 s.
- Why: with 8 players and one life, most people watch most of a round, and the kids often go first. Now they still play.
- Takes: medium. A ghost state in `sim.gd`, ghosts in the snapshot, a faint sprite, bot ghosts that drift to the nearest player.
- Risk: 7 ghosts on the last 2 is too much: a small shove, a cooldown. TowerFall's "Return as ghosts" (a ghost's touch kills) and Bomberman R's revenge cart (a kill puts you back in) can be fun rules later.

**2. Teams, with team revive.** A TEAMS button: OFF, 2 TEAMS or PAIRS (4 teams of 2). The last team standing scores. Teammates can't hurt each other. Stand by a fallen teammate for 2 s to bring them back (TowerFall has "Team revive").
- Why: each kid teams up with a parent or grandparent and wins too. Going out is not the end.
- Takes: medium. A team per seat, the round-end rule, team-coloured rings and arrows, bots that skip teammates.
- Risk: kids must see their side at a glance: big team colours.

**3. An arena event in some rounds.** After about 5 s, with a 2 s warning sign: LIGHTS OUT (only torches, arrows and rings glow), RISING LAVA, CRUMBLING LEDGES or a WIND gust. Like TowerFall's dark and lava orbs, Overcooked's kitchen on two trucks that drift apart, Gang Beasts' lifts that go wild near a round's end.
- Why: every round gets its own story.
- Takes: lights out is small (the look only). Lava and crumbling ledges are large (the map changes; bots must know). Wind needs `predict.gd`.
- Risk: the dark must stay cheap on the LOW look. Add EVENTS: ON/OFF (Smash Ultimate added a hazards switch).

**4. FUN RULES in the lobby.** One rule a match, 6 to 8 choices plus SURPRISE: ENDLESS ARROWS, BIG ARROWS, BOUNCY ARROWS, SHIELDS FOR ALL, SLOW-MO, SUDDEN DEATH (walls from the start), GHOSTS. TowerFall's Variants menu has dozens; Smash has Special Smash (big, tiny, fast, invisible).
- Why: lots of variety, almost no new art. Kids love choosing.
- Takes: small each (most are one number in `sim.gd`).
- Risk: too many choices confuse: big icons, few words. No jump changes until the bots get new routes.

**5. An announcer and a HONK button.** A voice calls the moments: "3, 2, 1, FIGHT!", "Last two!", "Grandma wins!" Every phone gets a HONK: a silly noise and a bubble over your fighter (like Duck Game's quack button).
- Why: laughs without typing. The 11-year-old hears what happened, no reading.
- Takes: medium. The game has no sound yet (G9). The browser's own speech voice can say typed names.
- Risk: 8 phones in one room are loud: the announcer speaks from one device (the TV or the host). Honks get a cooldown.

## More ideas
**Arena events:** a lift or sliding bridge; spike balls on a chain; jump pads and switch blocks; an earthquake that splits the arena for 5 s.
**Match modes:** HEADHUNTERS (a kill = a point, a self-kill = -1); KING OF THE HILL (stand in a glowing zone that moves); BIG CAT (one huge player with a shield; whoever kills them becomes it); CROWN (stomp the leader to take it); BOMB TAG (pass the bomb by touch before it pops); a new arena every round.
**Match modifiers** (more FUN RULES): one arrow; exploding bodies; double jump; moon jump (needs bot routes); an orb every 5 s.
**Comeback help:**
- TowerFall's autobalance: the leader starts with 1 arrow fewer (never under 2); 2 points behind = start with a shield.
- A HELPER per player: a parent gives the youngest a starting shield (TowerFall's options can be set per player).
- Last-round pick: at match point, the player in last place picks the final round's fun rule (Mario Party's Last Five Turns).
- Mario Kart's blue shell is the warning: a late hit you can't escape feels unfair. Give openings, not free wins (Riot, Bugnet).
- For tonight's build: catch-up items by points behind, not place (with 8, many tie at 0); one big item on the field at a time; each one escapable (a meow before the cat, a dodge beats it); the lightning warning big on the LOW look.

**Fun and social:** 4 emote buttons (laugh, cry, heart, cat); a dance when you hold down; a victory tune each; "On fire!" after 3 kills; awards after the deathcam (most stomps, best catch, sneakiest ghost).
**Cosmetics:** hats picked in the lobby (cat ears, crown, wizard; bots get random ones); arrow trails (stars, hearts); confetti when you fall; a new hat every 10 matches. Keep the body colour: at 90 px it says who is who.

## Holiday themes
**Halloween** (Oct 1 - Nov 1):
- Pumpkin bombs: the bomb arrow as a jack-o'-lantern that bursts into seeds.
- Bats: a swarm sweeps across as moving cover; the flying power-up gets bat wings.
- Candy: each kill drops one; 3 candies = 1 more arrow.
- Trick-or-treat orb: a power-up, or a harmless trick (a hopping pumpkin for 3 s).
- The black cat, more ways: a cat-ears hat; a cat that walks the floor and shields whoever pets it; ghosts as cats.
- Costumes: pumpkin head, witch hat, sheet ghost, vampire cape.

**Thanksgiving** (Nov 2-30): falling leaves (the rain effect) and hay on THE KEEP; a turkey runs about, stomp it for a power-up; pilgrim hats.
**Christmas and winter** (Dec 1-30): snowy BRIDGES with icy ledges; Santa's sleigh drops the orbs instead of the lightning; snowball arrows that freeze you 2 s; Santa hats, antlers.
**New Year** (Dec 31 - Jan 2): fireworks in the sky; firework bomb arrows; a countdown voice before the last round; party hats.
**Valentine's Day** (Feb 7-14): pink lanterns, hearts instead of dust; Cupid arrows pull two players together 3 s (no kill); PAIRS with heart badges.
**Easter** (the week up to Easter Sunday, which moves): a sunny KEEP with flowers; an egg hunt round (first to 3 eggs); bunny ears, a double-jump power-up.
**Fourth of July** (Jul 1-5): fireworks over THE BRIDGES; firecracker arrows (a string of pops); a Roman candle = 3 small arrows in a fan; star capes.

**What the big games change:** the same maps dressed up (Overwatch's makeovers, Rocket League's spooky Farmstead, Fortnite's darker, foggier island); a mode for a week or two (Rocket League's pumpkin cube, Fall Guys' Halloween-only round); an old item back (Fortnite's Pumpkin Launcher); skins. Back every year.
**How they switch on:** by date. Terraria reads the computer's date (Halloween Oct 10 - Nov 1, Christmas Dec 15-31). Fortnitemares 2026 started Oct 1 for a month; Brawlhalloween 2026 runs Oct 7 - Nov 4. TF2 maps can ask "is it Halloween?".
**Recommend both:** a THEME button in the lobby: AUTO (the default), OFF, or any holiday. AUTO uses the server's date (the ROG or the laptop), so all 8 phones match; the server sends `theme` with the lobby state. Kids can have Halloween in June. Mostly the look and reskins (pumpkin = bomb arrow), so bots and balance stay the same; new holiday rules (snowballs, Cupid, eggs) are FUN RULES.

## Sources
- TowerFall wiki: [Variants](https://towerfall.wiki.gg/wiki/Variants)
- Smash: [hazards switch](https://www.eventhubs.com/news/2018/jun/14/super-smash-bros-ultimate-adds-option-toggle-stage-hazards-and-first-time-series-history), [Special Smash](https://ssbwiki.com/Mini)
- [Blue shell](https://en.wikipedia.org/wiki/Blue_shell), [Mario Kart items](https://nintendoworldreport.com/feature/16008), [Last Five Turns](https://www.mariowiki.com/Last_5_Turns)
- Comebacks: [Riot](https://www.leagueoflegends.com/en-gb/news/dev/quick-gameplay-thoughts-2-25-comeback-mechanics/), [Bugnet](https://bugnet.io/blog/how-to-design-a-comeback-mechanic)
- [Bomberman R](https://www.pushsquare.com/reviews/ps4/super_bomberman_r), [Duck Game quack](https://siliconera.com/?p=490614), [Overcooked](https://en.wikipedia.org/wiki/Overcooked), [Gang Beasts lifts](https://gangbeasts.wiki.gg/wiki/Elevators)
- [Overwatch](https://egmnow.com/overwatchs-halloween-terror-event-returns-today/), [Rocket League](https://earlygame.com/rocket-league/haunted-hallows-event-halloween-details), [Fortnitemares 2026](https://beebom.com/fortnite-update-42-30-patch-notes-fortnitemares-2026/), [Fall Guys](https://en.wikipedia.org/wiki/Fall_Guys), [Brawlhalloween](https://brawlhalla.wiki.gg/wiki/Brawlhalloween)
- [TF2 holiday check](https://developer.valvesoftware.com/wiki/Tf_logic_on_holiday), Terraria [Halloween](https://terraria.wiki.gg/wiki/Halloween), [Christmas](https://terraria.wiki.gg/wiki/Christmas)

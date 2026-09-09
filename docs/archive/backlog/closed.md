---
tags: [archive, backlog]
---
# Closed backlog items

Appended at close time: the number, the closing version, one line on the fix, the page that holds the story. Numbers are never reused, so patch pages and sheets that name "backlog 15" still resolve here. The open list is in [[PASSDOWN]].

## Backlog
27. **A second death 1.2 to 1.5 s after the first was dropped as a duplicate (dead on its screen, alive on the server, the round ran 13 h)** — closed on **v0.1.1** (server only, 2026-09-08): `serve_game.py` `DEATH_DEDUPE_S` 1.5 -> 0.6, under the 1.2 s respawn; harness scenario `respawn_death` — [[v0.1.1 - Phone Controller]].
19. **Fill-with-bots button** — closed in **v0.0.40** as a tool, not a server feature: `tools/tbbot.py` (`tbbot add [persona]`, `remove`, `clear`, `list`) starts real headless Godot clients on the server machine, max 4; the deck's `--controls` panel has the buttons — [[v0.0.40 - LAN Server Kit]], [[laptop-server]].
22. **Hiding on top of the flipped ground** — closed in **v0.0.39** (the ground slabs are anchored and never turn, so the old floor never sits at the top edge) — [[v0.0.39 - Anchored Ground]].
1. **Ranger reload mid-match loses the stuck arrows** — fallback shipped in **v0.0.30**: `player.gd` `restore_combat_state` ignores a save from another round and gives a same-round ranger at least 1 arrow; headless proof `ranger_rejoin`, browser proof [[Playtest Backlog 1 — Ranger Reload Quiver]]; the proper fix is open backlog 18 — [[v0.0.30 - Ranger Rejoin Quiver]], [[Playtest v0.0.8]].
2. **`p0_left` InputMap error** — fixed in **v0.0.11**: the three P1-bind copies in `global.gd` require `my_player_id >= 2` (id 0 = spectator); was the intermittent red on the default fleet scenario.
6. **Ranger arrow economy (the reload half)** — shipped with item 1 in **v0.0.30**; the in-round economy (three arrows per life, pickups only from own stuck arrows, the sniper persona plays mage for this reason) is a design call = open backlog 18.
7. **No screen wrap while shielding or in egg form** — fixed in **v0.0.11**: `_check_screen_wrap()` in both early-return branches of `player.gd`; found by the griefer persona.
8. **Turtle can chain 4 bottom wraps** — fixed in **v0.0.13**: no air shield over an empty column, as the griefer.
9. **A fighter rides the arena shift out of the top of the screen** — fixed in **v0.0.32** (option A, soft platforms), **reopened in v0.0.38** (the free fall felt terrible; `SHIFT_SOFT_PLATFORMS = false`); the live line is in [[PASSDOWN]] — [[v0.0.32 - Free-Fall Arena Shift]], [[v0.0.38 - Solid Shift Restored]].
23. **The shift tumble trips `fleet.bot-fall-loop`** — closed in **v0.0.33** (keep the tumble): `bot_brain.gd` `_track_wraps` counts a bottom wrap while `arena.is_arena_rotating` as `shift_wraps` (`shift=` on the `🧠 [Bot]` line), never as a fall loop; the gate threshold stays at 4; heavy fleet seed 13 passes — [[v0.0.33 - Shift Tumble Kept]].
10. **Egg form runs on puppets** — fixed in **v0.0.29**: the `if is_egg:` branch in `player.gd` `_physics_process` sits below the `if not is_local_player` check; the puppet's egg flag comes from the sender's `sync_pos` (bit 16) through `_apply_state`; what is left of the egg over the network is open backlog 16 — [[v0.0.29 - Egg-Form Puppet]].
15. **A wanderer brain sends the same `spawn_projectile` twice within 20 ms** — explained in **v0.0.30**: `player.gd` reads `attack` and `special` in the same physics frame and a ranger's attack and special both fire an arrow from `global_position + aim_dir * 18` along `aim_direction`, so the two 9 B packets are identical; a legit double shot, counted by `Bot.double_shot_ok` where a ranger brain plays; whether one frame should fire two overlapping arrows is open backlog 18 — [[v0.0.30 - Ranger Rejoin Quiver]].

## The old "later list" (Phase 3b step 5, [[Playtest v0.0.17]])
Items 2, 3, 4, 6, 7, 8 and 9 of that list are now open backlog 17 to 22. Closed:
- Later-list 1 **Who is who** — shipped in **v0.0.19**: name tags, no duplicate names, CHANGE NAME button, platform start spots; arrows in the shooter's colour and the quiver count on other screens went to open backlog 18 — [[v0.0.19 - Who is who]].
- Later-list 5 **Bot count in the `[STATS]` line** — shipped in **v0.0.22**: `"bot"` in `request_join`, `players=4 (2 bots)` — [[v0.0.22 - Observability, Harness Telemetry and Bot Arena]].

## Playtest summaries that used to sit in PASSDOWN
- Family playtest of 2026-09-03 (PC Chromium, Galaxy S25 Ultra Chrome, iPad Pro): phone screen helpers pass; puppet movement, seams, teleports and landing pass; hits land close to the drawn body. Fixed in v0.0.18: bubble spawn, lost arrows, floating arrows, bots not re-locking, hidden crown number, R key wipe, plus a jump trap. Full notes: [[Playtest v0.0.17]].
- Replay playtest of 2026-09-04: the 6.5 s gap, the slow-motion window and the caption all stay; phone fps numbers still missing (no console on the S25 Ultra); found backlog 13 and 14 and the *family* feature asks in [[PASSDOWN]]. Full notes: [[Playtest v0.0.26]].
- The full PASSDOWN as it stood at v0.0.30, with every build bullet: [[PASSDOWN-2026-09-05]].
- **9** — closed in v0.1.3 — does not apply any more: the arena shift is off and the pieces that swung past the top edge are gone (the tower, [[arena-tower]]) — [[v0.0.31 - Top Edge Probe]].
- **24** — closed in v0.1.3 — does not apply any more: nothing turns, so nothing sweeps the floor corners (the tower) — [[v0.0.39 - Anchored Ground]].

# Kick-off prompt (Tower Brawl)

Copy this into a fresh session after /clear, or type: "Read kickoff.md and do what it says".

---

Tower Brawl, branch beta. Read, in this order: CLAUDE.md, docs/PASSDOWN.md, the newest page in docs/Patch Notes/ (v0.2.0-p4.18 - Harvest Feast), docs/Commands.md. Then docs/reference/game-review-2026-11.md (the review of 2026-11-23: what the October logs say, the Thanksgiving plan, the 12 bugs a helper found).

Where things stand (2026-11-24): v0.2.0-p4.18 "Harvest Feast" is built and committed on beta, but NOT on the ROG yet (the ROG was switched off on 2026-11-23; it still holds p4.17). The user wants it on the ROG by Thursday morning 2026-11-26 (Thanksgiving). p4.18 is the Thanksgiving update the user picked from the review: the seasons (the server's, AUTO by date, a SEASON button in the lobby), a turkey to catch, covered dishes with new tricks, PIE (cream on your screen), THE BIG TURKEY costume, two new arenas (THE HARVEST BARN, layout 5; THE BIG TABLE, layout 6), autumn on the castle arenas, ComfyUI harvest pictures, a SHIELD for a player 2 points behind and FOR YOU on BIG orbs, HOW TO PLAY, WHO ARE YOU? (tap your name), THE BIG SCREEN (the page's ?tv, for a TV). The user saw a first-look sheet and the BEFORE/AFTER sheets of 2026-11-24.

Next:
1. When the user says go and the ROG is on (never while anyone plays): check the ROG's CPU cap, then tools/deploy_rog.sh, then check the host port says v0.2.0-p4.18 and the page loads index_v0.2.0-p4.18.pck. The ROG needs qrencode for THE BIG SCREEN's code (its links page already uses it).
2. Ask for a 15-minute family check on real phones before the gathering (one iPhone): the white screen, the frame rate on the two new arenas, a stutter at the winner's screen. p4.15, p4.16 and p4.17 have no night on record either.
3. The 12 bugs in the review page wait for the user's yes or no (the worst: a dropped phone loses its seat after 8 s; the winner's screen gets only what the replay leaves of 12 s). One rule is the user's to pick: is a round's winner safe once the round is called, or does a late hit mean nobody scores?
4. After the night: tools/pull_rog_logs.sh and tools/v2_night_report.py (it knows the season and the new arenas), then the sheet lines in the patch pages of p4.16 to p4.18 (the open sheet is docs/Playtest v0.2.0-p4.14.md).
Ideas waiting (the review's list): sound, teams and pairs, phones as pads for THE BIG SCREEN, two fighters starting opposite each other, bots that follow the group's size, a winter season (docs/reference/holiday-ideas.md).

How this build was made, for the next season: the season's names are in sim/proto.gd (HARVEST_*), its rules in sim/sim.gd (season), its pictures in client/harvest_view.gd; a new arena is a text map in sim/level.gd plus a view file hooked in client/world.gd _apply_theme, then arena_probe --write-routes (5 minutes). Two helpers built the arenas in their own copies under ~/.cache/tower-brawl-work/ and handed back paste-ready pieces. ComfyUI: tools/comfy/run_harvest.py, then make_assets.py harvest (the README has the steps).

Rules: ask before every deploy and never while anyone plays; show any look change to the user as BEFORE/AFTER first; ask before any GPU run (the AMD card can freeze the PC; tools/comfy/batch.sh waits for the card and its lock); one approved phase at a time: report bugs, do not fix them without a go; plain words (the user teaches an 11-year-old); commit on beta at each checked step and push beta alone; never commit cloudflared; stop a test server by its PID (pkill -f with its arguments kills your own shell).

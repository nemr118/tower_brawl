# Kick-off prompt (Tower Brawl)

Copy this into a fresh session after /clear, or type: "Read kickoff.md and do what it says".

---

Tower Brawl, branch beta. Read, in this order: CLAUDE.md, docs/PASSDOWN.md, the newest page in docs/Patch Notes/ (v0.2.0-p4.20 - Team Turkey), docs/Commands.md. Then docs/reference/classes-scope.md (the classes study: numbers and a proposal, nothing built) if the talk turns to classes.

Where things stand (2026-11-25): v0.2.0-p4.20 "Team Turkey" is built and committed on beta, but NOT on the ROG (the ROG was switched off; it still holds p4.17). The user wants it on the ROG by Thursday morning 2026-11-26 (Thanksgiving). Three builds wait in one: p4.18 "Harvest Feast" (the seasons, the turkey, dishes, PIE, THE BIG TURKEY, two arenas), p4.19 "Second Helpings" (the review's 12 bugs, the winner is safe with a PHEW, sound, the new loading page, SETTINGS, name cards, sticks, bots named GRAVY and STUFFING, a GOBBLE button, balance) and p4.20 (TEAMS: TEAM TURKEY against TEAM PIE with no friendly fire; a silly round every third round; music made by ACE-Step, off until picked; a match's MENU; TONIGHT'S CHAMPIONS; a +1 to the winner's card; the page's own watchdog for a dead link; route maps built at the server's start; bots keep their seats; clean names). The user saw the BEFORE/AFTER sheets of p4.19 and the "what is new" sheet of p4.20. None of p4.15 to p4.20 has run on a real phone.

Next:
1. When the user says go and the ROG is on (never while anyone plays): check the ROG's CPU cap, then tools/deploy_rog.sh, then check the host port says v0.2.0-p4.20 and the page loads index_v0.2.0-p4.20.pck. The ROG needs qrencode for THE BIG SCREEN's code.
2. Ask what the user HEARD: the 37 sounds (to retune one: a number in tools/make_sfx.py, python3 tools/make_sfx.py --only NAME, a build) and the 3 songs (the six takes are in ~/.cache/tower-brawl-comfy/music/; python3 tools/comfy/make_music.py --pick match=2 swaps a take, then godot --headless --path bench --import and a build). Music is off until someone turns it on in SETTINGS.
3. Ask for a 15-minute family check on real phones (one iPhone) and the TV: the loading screen and TAP TO PLAY, TEAMS (do the flags read at a phone's size), a silly round, a phone locked for 20 s coming back to its seat, the white screen, the frame rate.
4. To watch: among bots THE BIG TURKEY's wearer wins 45% of 8-fighter rounds (the lever is MASK_DOWN and MASK_GRACE in bench/sim/sim.gd, not its lunge). The user was offered "everyone starts with 2 arrows" as a cheap test of the pick-up game (START_QUIVER in sim.gd); no answer yet.
5. After the night: tools/pull_rog_logs.sh and tools/v2_night_report.py, then the sheet lines in the patch pages of p4.16 to p4.20.
Classes: docs/reference/classes-scope.md proposes kits (one perk, one cost, no new button), a first roster (KNIGHT, SCOUT, BRAWLER) and stages; the user has not picked. The README still shows the old game.

How this round was made: helpers work in their own copies under ~/.cache/tower-brawl-work/ and commit there; each is merged with "git diff --binary BASE..HEAD -- bench tools | git apply --3way". Twice a server error (API 529) cut helpers off near their ends: their commits were merged and their last proofs run by hand; check a helper's copy for uncommitted work and for processes it left running. Give every server of a multi-server tool its own block of ports (a clash looks like "the page never joined"). Do not rebuild the page while a page test runs.

Rules: ask before every deploy and never while anyone plays; show any look change to the user as BEFORE/AFTER first; ask before any GPU run (the AMD card can freeze the PC; the music batch was one go for one batch); one approved phase at a time: report bugs, do not fix them without a go; plain words (the user teaches an 11-year-old); commit on beta at each checked step and push beta alone; never commit cloudflared; stop a test server by its PID, and check a PID is a number above 1 and is yours before any kill; sound never reaches the speakers in a test (Chromium with --mute-audio).

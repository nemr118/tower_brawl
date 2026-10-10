# Kick-off prompt (written 2026-10-10, for the P1 build)

Paste the text below into a fresh session after `/clear`. If copy and paste fails, type this instead: **Read kickoff.md and do what it says.**

---

Continue Tower Brawl in ~/Work/tower_brawl. Run `git status -sb` first; the branch is beta. The laptop runs the old game v0.1.7; leave it alone.

Read, in this order: (1) CLAUDE.md, (2) docs/PASSDOWN.md, (3) docs/Patch Notes/v0.1.7 - Bug Sweep.md, (4) docs/Commands.md.
Then docs/reference/first-playable-plan.md (all of it) and docs/Design Decisions v0.2.md (D18 and the open list), and skim bench/sim/sim.gd, bench/server/bench_server.gd, bench/client/net.gd and scripts/touch_controls.gd.

Task: build P1, the first playable, in the order of the plan's section 3: (1) real buttons into the sim (apply_input; the bot brain only in empty seats), (2) seats and the lobby, (3) one-life rounds and points, (4) plain arrows, power arrows behind --power-arrows, (5) the client: the T2 look, the HUD for 8, the twin sticks and the keyboard, (6) tools/v2_build.sh and /v2, (7) the proofs of section 3.7, run headless on the PC, (8) the short sheet for the play night. Show me the PC proofs before anything goes to the laptop. Don't deploy to the laptop without asking.

Rules: plain words (rule 7). Git by rule 9 (commit on beta at each checked step, push, no other branches). The repo is public: no TowerFall code, art or levels, only numbers and rules in our own words. One phase: P1 only; report anything else, don't fix it. End with the rule 8 wrap.

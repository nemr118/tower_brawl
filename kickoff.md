# Kick-off prompt (written 2026-10-10, after the P1 build)

Paste the text below into a fresh session after `/clear`. If copy and paste fails, type this instead: **Read kickoff.md and do what it says.**

---

Continue Tower Brawl in ~/Work/tower_brawl. Run `git status -sb` first; the branch is beta. The laptop runs the old game v0.1.7; the new game is NOT on it yet.

Read, in this order: (1) CLAUDE.md, (2) docs/PASSDOWN.md, (3) docs/Patch Notes/v0.2.0-p1.1 - First Playable.md, (4) docs/Commands.md.

Where we are: P1, the first playable of the new game (bench/), is built as v0.2.0-p1.1 and committed on beta; the PC proofs passed (the page's Checked table). Two things wait on me: the laptop deploy and the play night.

Task, in this order: (1) when I say "deploy": `TB_SUDO_PASS=... tools/deploy_laptop.sh 192.168.4.29` (it sends both games and installs towerbrawl-v2.service beside the old one); then check both services are active, join https://192.168.4.29:8443/v2/ with a headless person (play_probe.gd against wss://192.168.4.29:8091) and read the laptop's tick with 8 seats from its report line (the plan's mark: under 4 ms); write the number into the page. (2) After the play night, read docs/Playtest v0.2.0-p1.1.md with me and fix what failed (one phase, report the rest). (3) Then P2 "The feel" (docs/reference/first-playable-plan.md section 4): prediction and reconciliation for your own fighter, the client clock, the controls tuned from the sheet, the quality setting. Don't start P2 before the sheet has a verdict unless I say so.

Rules: plain words (rule 7). Git by rule 9 (commit on beta at each checked step, push, no other branches). The repo is public: no TowerFall code, art or levels, only numbers and rules in our own words. One phase at a time; report anything else, don't fix it. End with the rule 8 wrap.

# Kick-off prompt (written 2026-10-10, after the laptop deploy of P1)

Paste the text below into a fresh session after `/clear`. If copy and paste fails, type this instead: **Read kickoff.md and do what it says.**

---

Continue Tower Brawl in ~/Work/tower_brawl. Run `git status -sb` first; the branch is beta. The laptop (192.168.4.29) runs both games: the old game v0.1.7 at /play and the new game v0.2.0-p1.1 at /v2/ (towerbrawl-v2.service, deployed 2026-10-10; the tick with 8 sockets 0.36 ms mean).

Read, in this order: (1) CLAUDE.md, (2) docs/PASSDOWN.md, (3) docs/Patch Notes/v0.2.0-p1.1 - First Playable.md, (4) docs/Commands.md.

Where we are: P1, the first playable of the new game (bench/), is built, deployed and proven on the laptop (the page's Checked table). What waits on me: the play night and its sheet, docs/Playtest v0.2.0-p1.1.md.

Task, in this order: (1) After the play night, read docs/Playtest v0.2.0-p1.1.md with me. If a line failed, read the laptop's side first: `journalctl -u towerbrawl-v2` over ssh and `~/tower_brawl/bench_results/<date>/v2_server.jsonl`. Fix what failed as one phase; report the rest. Backlog 35 (a match goes on with fewer than 2 fighters) and "bots shoot from the first tick of FIGHT" are open notes: fix them only if I pick them for that phase. A new build: `tools/v2_build.sh --title "..."`; the deploy asks me first (`TB_SUDO_PASS=... tools/deploy_laptop.sh 192.168.4.29`). (2) Then P2 "The feel" (docs/reference/first-playable-plan.md section 4): prediction and reconciliation for your own fighter, the client clock, the controls tuned from the sheet, the quality setting. Don't start P2 before the sheet has a verdict unless I say so.

Rules: plain words (rule 7). Git by rule 9 (commit on beta at each checked step, push, no other branches). The repo is public: no TowerFall code, art or levels, only numbers and rules in our own words. One phase at a time; report anything else, don't fix it. End with the rule 8 wrap.

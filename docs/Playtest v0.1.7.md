---
tags: [playtest]
build: v0.1.7
result: open (started 2026-09-10)
---
# Playtest v0.1.7

**Result: open.** One line per thing only a person can judge: tick it, write yes or no. The proofs Claude ran on the PC are in [[v0.1.7 - Bug Sweep]]. The old master sheet (sections 1 to 9) is in `archive/playtests/`.

## First: the soak reading, then the deploy
- [ ] The morning after 2026-09-10, on the PC: `tools/pull_laptop_logs.sh 192.168.4.29`, then `./venv/bin/python tools/soak_report.py --dir playtest_logs/<folder> --from 18:16`. The last line says "no stall" (yes / no): 
- [ ] Only after that: `TB_SUDO_PASS=... tools/deploy_laptop.sh 192.168.4.29`. `tbdash` on the laptop shows v0.1.7 (yes / no): 

## On the laptop, v0.1.7
- [ ] Each phone shows the certificate warning once more; accept it and the game loads. S25 Ultra (yes / no):  · Pixel (yes / no): 
- [ ] PC keyboard, standing on a ledge: S and W pressed together drop through (yes / no): 
- [ ] Twin sticks, standing on a ledge: a flick past the down rim drops through. S25 Ultra (yes / no):  · Pixel (yes / no): 
- [ ] All four seats taken, a fifth device presses JOIN: it shows ALL SEATS TAKEN, then the button comes back. In a match (yes / no):  · In the lobby (yes / no): 
- [ ] On one phone, a name with an apostrophe (O'Brien): join, reload the page. The name is still there (yes / no): 

## Verdict
- [ ] **Pass**, or the line that failed and a clock time (HH:MM): 

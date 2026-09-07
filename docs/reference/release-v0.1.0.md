---
tags: [reference, release]
release: v0.1.0
decided: 2026-09-07
---
# Release v0.1.0 — criteria and runbook

**What ships.** v0.1.0 is v0.0.38 with a new version number and nothing else. It carries optimisation Step C cuts 2 (tape card on change, [[v0.0.35 - Tape Card on Change]]) and 3 (relay `sync_bundle`, [[v0.0.36 - Relay Packet Coalescing]]) the client stats cards ([[v0.0.37 - Client Stats Reporting]]) and the solid shift again ([[v0.0.38 - Solid Shift Restored]], backlog 9 reopened by decision). Cut 1 (the phone main thread) is NOT in it: it moves to v0.1.1 as the first post-release optimisation. Decided 2026-09-07.

**How it is verified.** One playtest on the v0.0.38 build, section 6 of [[Playtest — Master Validation Suite]], is the final human check of v0.1.0. The same evening's S25 Ultra rows from `tools/stats_table.py` (section 1) become the baseline for v0.1.1. Because v0.1.0 has no code change over v0.0.38, a pass on v0.0.38 counts for v0.1.0. If any code changes between the playtest and the tag, the playtest no longer counts and section 6 is played again.

## 1. Before the tag (all must be true)
- [ ] `git status --short` prints nothing on `master`; `git describe --tags` says `v0.0.38`.
- [ ] Master sheet section 6 verdict ticked **ship**. Section 5 verdict ticked **the bundle stays** (or the bundle is off, see 4.3, and the patch page says so).
- [ ] Sections 1 to 4 played or written off: a verdict ticked, or "not played, moved to v0.1.x" written under the verdict, so the sheet can be archived at the tag.
- [ ] The full suite on the v0.1.0 build: `24/24 scenarios passed`, no Minor, report `docs/harness_report_v0.1.0.json`. (Step 2 below; the suite runs after the bump because the server checks the version on every join.)
- [ ] The only code diff between v0.0.38 and v0.1.0 is `GAME_VERSION` in `scripts/global.gd`, its mirror in `serve_game.py`, and the exported `build/web/` files. Check: `git diff v0.0.38 --stat -- scripts serve_game.py tools`.
- [ ] Patch page `docs/Patch Notes/v0.1.0 - Release.md` filled (summary, what is in, what moved to v0.1.1, harness line, playtest verdict), Changelog link present.

## 2. Branch, bump, gate
```bash
cd ~/Work/tower_brawl
git status --short                                   # nothing
git checkout -b release/v0.1.0
./bump_build.sh minor --title "Release"              # v0.0.38 -> v0.1.0: compile check, export, index_v0.1.0.pck, patch page
systemctl --user restart towerbrawl                  # the service re-reads the version; old builds now get VERSION MISMATCH
setsid nohup ./venv/bin/python tools/chaos_bots.py --restart-each --json docs/harness_report_v0.1.0.json > /tmp/harness_v0.1.0.log 2>&1 &
grep "scenarios passed" /tmp/harness_v0.1.0.log      # wait for "24/24 scenarios passed", then check the report for MINOR
```
Known flake to expect: `fleet.bot-fall-loop` on the rusher brain (seed 42) is a brain finding, not a netcode one. If it is the only failure, rerun `--scenario fleet` once; a clean rerun is a pass, and the patch page says so.

Then fill the patch page, do the PASSDOWN trim step (`CLAUDE.md` rule 8), and archive the master sheet to `docs/archive/playtests/` if every verdict is ticked.

## 3. Tag, merge, push
```bash
git add -A
git commit -m "v0.1.0: release (optimisation Step C cuts 2 and 3; cut 1 -> v0.1.1)"
git tag -a v0.1.0 -m "Tower Brawl v0.1.0: relay bundles, tape card on change, replay, rejoin"
git checkout master
git merge --ff-only release/v0.1.0
git push origin master v0.1.0
git branch -d release/v0.1.0                         # the branch has done its job; the tag is the record
```
Verify after the push: `git describe --tags` says `v0.1.0`, the lobby at `https://192.168.4.21:8443/play` shows v0.1.0 on the PC and on one phone (hard reload if VERSION MISMATCH), `tbdash` shows the service up, and `grep "Game version" server.log | tail -1` says v0.1.0.

## 4. Rollback
### 4.1 Before the merge (branch only)
```bash
git checkout -- . && git clean -fd build/web         # drop the uncommitted bump and the new index_v0.1.0.* files
git checkout master                                  # master still says v0.0.38; its build/web is tracked, so the served files come back
git branch -D release/v0.1.0
git tag -d v0.1.0 2>/dev/null
systemctl --user restart towerbrawl
```
### 4.2 After the push (the tag is public)
Do not delete a pushed tag. Revert forward:
```bash
git revert --no-edit <release commit>                # restores GAME_VERSION v0.0.38 and the v0.0.38 build files (tracked)
systemctl --user restart towerbrawl                  # the service re-reads the version on every join
```
Phones that cached v0.1.0 get VERSION MISMATCH once and reload to v0.0.38 (`/play` always redirects to the current build). Then bump a new patch build (`./bump_build.sh --title "..."`) with the fix; the version after a revert continues upward, numbers are never reused.
### 4.3 Turn a cut off without a client build
- **Cut 3, the bundle feels late:** `RELAY_BUNDLE_MS = 0` in `serve_game.py`, `systemctl --user restart towerbrawl`. Every `sync_pos` is relayed at once, exactly like v0.0.35. Try 25 before 0.
- **Cut 2, the tape card looks stale:** no server switch; `TAPE_CARD_MIN_S` lives in `arena.gd`, so that is a client build. Only worth it if section 6 names the card.

## 5. After v0.1.0
- **v0.1.1, two candidates (decide at the tag):** Step C cut 1, the phone main thread, from the S25 Ultra `proc` / `phys_cpu` rows of `tools/stats_table.py` for the playtest matches ([[optimisation_step_b_profiles]]); or the Android export plus a PCK loader (the app downloads `index_<version>.pck` from the server and loads it with `ProjectSettings.load_resource_pack()`, the browser's cache-bust without the browser). If the native app is next, cut 1 waits until the native build is measured on the same phone.
- **Later, a direction not a plan:** the Python relay is to be replaced by a headless Godot simulation server (one authoritative sim, clients send inputs). Relay-only numbers (packets in, `sync_bundle` counts) stop mattering then; the phone's own frame numbers still do. Nothing in v0.1.x depends on this.
- Ideas list (unscheduled) stays in [[PASSDOWN]].

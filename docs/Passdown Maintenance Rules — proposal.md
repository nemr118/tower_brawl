---
tags: [handoff, proposal]
status: enacted 2026-09-05 (P1 to P7; P8 deferred, the size gate in bump_build.sh is a later code change)
---
# Passdown Maintenance Rules — proposal (enacted 2026-09-05, P8 deferred)

**Why.** Every kickoff reads five documents. Measured on 2026-09-05 at v0.0.30:

| File | Bytes | About tokens | What a kickoff actually needs from it |
|---|---|---|---|
| `CLAUDE.md` | 4 375 | 1 100 | all of it |
| `docs/PASSDOWN.md` | 46 258 | 11 500 | the tag, the harness line, the next step, the open backlog: about 6 000 bytes |
| of which the "Current status" section | 26 414 | 6 600 | the first bullet and the newest build bullet |
| `docs/Changelog.md` | 10 985 | 2 700 | the top two lines |
| `docs/obsidian_notes.md` | 24 323 | 6 100 | the build, harness, headless and deck commands: about 4 000 bytes |
| newest patch note | about 4 500 | 1 100 | all of it |
| **Kickoff set today** | **about 90 000** | **about 22 500** | **about 16 000 bytes would do** |

The waste is history that already lives somewhere else: every build bullet in PASSDOWN repeats its patch page, the "Architecture in one screen" carries a "since v0.0.x" trail per feature, the backlog keeps struck-through items, `obsidian_notes` holds deep dives on shipped features next to the six commands a session needs.

## The rules (P1 to P8)

**P1. PASSDOWN carries the frontier only.** Sections, in this order, with a size cap of about 8 000 bytes for the whole file:
1. `## Now` (one screen): the tag, the harness line, the working-tree state, the next step in one sentence, anything a human must do (open sheets), the last **two** build bullets, each at most four lines and ending in the wikilink to its patch page.
2. `## Open backlog`: open items only, one to three lines each, in the format of P5.
3. `## How to work here`: the rules pointer, the three verify commands, the serve command, the docs pointer. No history.
4. `## Architecture now`: the current shape, one line per file, no "since vX" or "was" phrases. History belongs to the patch pages.
Nothing else. The "later list", the playtest summaries and the roadmap prose move out (P3).

**P2. Build history lives in the patch pages, nowhere else.** A build bullet stays in PASSDOWN for two builds, then it is deleted (not archived: the patch page is the archive, the Changelog is the index). The Changelog stays complete, but a kickoff reads only `head -12 docs/Changelog.md`.

**P3. The archive folder.** `docs/archive/` with four subfolders. Obsidian resolves wikilinks by file name across folders, so moved pages keep their links.
- `docs/archive/backlog/closed.md`: every closed or explained backlog item, appended at close time with its number, the closing version and the wikilink. Numbers are never reused, so patch pages and sheets that name "backlog 15" still resolve.
- `docs/archive/playtests/`: a playtest sheet moves here once its verdict has been acted on (a build shipped or the item was closed). A sheet with an unticked verdict block stays in `docs/`.
- `docs/archive/passdown/PASSDOWN-<date>.md`: a copy of the old PASSDOWN taken once, when P1 is enacted, so nothing written there is lost. After that, no snapshots: git has them.
- `docs/archive/reports/`: `harness_report_*.json` older than the last three builds. The patch page link `../harness_report_vX.json` breaks for the moved ones; the patch page keeps the numbers in its own harness line, so that is acceptable. Alternative: leave the reports in place and add `docs/harness_report_*` to what a session never reads (they are never read anyway; they cost repo bytes, not tokens). Recommended: leave them, do nothing.

**P4. Split `obsidian_notes.md`.** Into `docs/Commands.md` (hot: build and bump, the harness lines, the headless client line and its console fields, the deck, serve and logs; target 5 000 bytes, no prose) and `docs/reference/` (the per-feature deep dives: the tape, the replay, the harness gate, the deck keys, the critical learnings; one page each, read only when the session works on that feature). `obsidian_notes.md` becomes a two-line pointer or is deleted.

**P5. Backlog item format.** One line each, three at most: `N. **Title** — state (open / waiting on a human / design call) — the next concrete action — the wikilink that holds the detail`. The finding story (log lines, timestamps, the theory) goes into the patch page of the build that found it, or the sheet, not into the backlog line.

**P6. The kickoff read list.** `CLAUDE.md`, `docs/PASSDOWN.md`, the newest patch page, `docs/Commands.md`. About 20 000 bytes, about 5 000 tokens. The Changelog and the reference pages are read on demand. The kickoff prompt template in rule 8 changes to name these four.

**P7. The wrap protocol grows a trim step (rule 8, before the summary).** At every shipped build: (a) add the new build bullet, delete the third-newest; (b) move closed backlog items to `archive/backlog/closed.md`; (c) move acted-on sheets to `archive/playtests/`; (d) check `wc -c docs/PASSDOWN.md docs/Commands.md` and say the two numbers in the wrap; over the cap (8 000 and 5 000) the wrap trims before it ends.

**P8. Size gate in the build script (optional, small).** `bump_build.sh` prints the two byte counts of P7(d) and warns above the caps. It never blocks a build.

## Enacting it: one docs-only commit, after approval

1. `git mv docs/PASSDOWN.md docs/archive/passdown/PASSDOWN-2026-09-05.md`, then write the new `docs/PASSDOWN.md` by P1: the `## Now` block from the current first bullet (tag, harness, next = backlog 9, the two open sheets), build bullets v0.0.30 and v0.0.29 cut to four lines each, the open backlog items 3, 4, 5, 9, 11, 12, 13, 14, 16 in P5 form plus the later list items that are still design calls (2, 4, 6, 7, 8, 9 of that list) folded into the same numbered backlog with new numbers 17 and up, `## How to work here` from the current section minus the history, `## Architecture now` rewritten without the version trail.
2. `docs/archive/backlog/closed.md`: items 1, 2, 6, 7, 8, 10, 15 and later-list 1 and 5, with their closing versions.
3. `git mv` the four filled sheets (`Playtest v0.0.5`, `v0.0.8`, `v0.0.17`, `v0.0.26`) to `docs/archive/playtests/`. The two backlog sheets (1 and 13) stay until their verdicts are ticked.
4. `docs/Commands.md` from `obsidian_notes` sections 2, 3 and 4, 5, 6, 7 (commands only); `docs/reference/` pages from sections 7 to 10 and the learnings; delete `obsidian_notes.md` or leave a pointer.
5. `CLAUDE.md` rule 6 and rule 8: name the four kickoff files and the trim step.
6. Run the wrap check (`git status`, sizes) and tag nothing: docs only.

Estimated result: a kickoff read of about 20 000 bytes instead of 90 000, and a PASSDOWN a human can read in two minutes.

Related: [[PASSDOWN]], [[Changelog]], [[Commands]], [[closed]], [[PASSDOWN-2026-09-05]].

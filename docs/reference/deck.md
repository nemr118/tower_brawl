---
tags: [reference]
---
# The operations deck (`tbdash`)

`tools/watch_server.py` + `tools/deck_input.py`. Built in v0.0.21 (dashboard), v0.0.22 (deck), v0.0.24 (keys and mouse), v0.0.25 (tape column), v0.0.26 (replay marks). Read this page when working on the deck or reading it during a playtest. Commands: [[Commands]].

```bash
tbdash                                               # alias in ~/.bashrc for the line below, works from any folder
./venv/bin/python tools/watch_server.py              # live view, keys and mouse, q or Ctrl+C to stop
./venv/bin/python tools/watch_server.py --plain      # plain text, no colours, no keys
./venv/bin/python tools/watch_server.py --once       # one colour picture, then exit (--once --plain for text)
./venv/bin/python tools/watch_server.py --no-mouse   # keyboard only (a terminal that eats the mouse codes)
./venv/bin/python tools/watch_server.py --zoom 5     # start at 5 s per strip column
python3 tools/deck_input.py                          # self-test of the key and mouse parser
```

**Keys:** `←` `→` pan the fight strip, `+` `-` zoom (0.5, 1, 2, 5, 10, 30 s per column), `Home` match start, `End` or `f` back to live, click a column to read what happened in that second, `Esc` clears it, `1`-`9` and `0` hide or show a log tag (`KILL ROUND MATCH JOIN LEAVE NAME LOCK CONN NET`, `0` = `TAPE`), `PgUp` `PgDn` scroll the log, `p` pause, `s` save `deck_snapshot_<HH-MM-SS>.txt` in the repo root (gitignored), `q` quit. **Mouse:** wheel pans, Ctrl+wheel or Shift+wheel zooms around the pointer, wheel over the events panel scrolls it. Works in `foot` and `ghostty`; inside `tmux` the mouse needs `set -g mouse on`. Raw stdin thread, xterm SGR mouse reporting `ESC[?1000h` / `ESC[?1006h`.

**Inputs.** The server writes `status.json` once a second (temp file + rename; match state, one row per seat with kills, deaths and ping, the bot cards, the kill timeline with round end times, `ended_at`, `winner` and `names`, traffic rates, the last 40 tagged log lines). The harness writes `harness_state.json` while it runs. The deck only reads those two files; it never talks to the server. A red bar means `status.json` is missing or older than 3 s, so the server is probably down (`systemctl --user status towerbrawl`). A yellow bar means the harness is restarting the server between scenarios.

**Panels** (a panel with nothing to show is not drawn):
- `HEADER`: state, round, flips, players (with the bot count), spectators, uptime; `SEATS LOCKED (harness)` while the gate is closed.
- `HARNESS`: only while a harness run is alive. Scenario name and place in the suite, a progress bar, `ETA` from the newest `docs/harness_report_*.json`, what the scenario tests, the last step, the checklist (✔ PASS, ✖ FAIL, ▲ Minor, ● running, ○ waiting; `SLOW` in yellow when a scenario runs past twice its last time), findings and warnings. A finished run stays as one line for ten minutes.
- `ALERT`: a red line at the very top for 10 s when an `ERROR` line, a `[NET]` stall or a harness-gate demotion lands.
- `SEATS`: name (🤖 for a bot), class, state, lives, crowns, `K/D`, `Ping`, `Trend` (the ping over the last 60 s, on terminals 120 columns or wider), `Health` (`good`, `laggy` over 150 ms, `slow` when the send queue backs up, `quiet` after 3 s of silence, `stalled` after 5 s, `held`, `empty`), `Tape` (only when a screen sent a card: `● 5.0s ·2` = recording, 5 s on the tape, 2 kills stamped this round; `■ R3 ✓` = frozen for round 3 with the closing kill; `▶ R3` = playing the replay, `■ R3 ✓ ▶5.1s` = played, `■ R3 ✓ ✗` = skipped), link, packets in, queue and drops, seconds since the last packet.
- `FIGHT`: from the first second of a match. One column is 1 s (zoom 0.5 to 30 s). `kills/1s` row = exact count per column. One lane per fighter, label `P2 Godot4 ♛4 42/24` (crowns, kills/deaths) in the seat colour (P1 blue, P2 red, P3 green, P4 yellow). A kill is the weapon glyph in the victim's colour (`➶` arrow, `✦` firebolt, `✧` kunai, `❋` thorns, `⚔` melee, `▼` stomp), a death is `✕` in the killer's colour, `◈` both, a digit when two or more events share a column. Every second round has a grey band. `┃` round start, `┫` round end, `♛` on the winner's lane one column after the closing kill, `║` match end, `round` row `R2 21s ♛ P2`, `time` axis in `m:ss`, `▶ live` on the right while following (`▶ end` for a finished match). Pan away and the title says `view 0:00-3:49 (End = live)`. Click a column: the line under the axis reads `1:00  Godot2 (P4) killed Andrew (P1) with Firebolt · round 1 ended, P4 Godot2 won · tape frozen on 2 screens (P1 P4), 300 frames before the kill / 60 after · replay played on 2 screens (P3 P4), 5.1 s, started 1.0 s after the kill`. Stays after the match ends (`last match, P2 won`) until the next one starts.
- `BOT ARENA`: whenever a bot is seated, brains and plain clients alike. `Kind` (`brain`, `headless`, `protocol`), persona, difficulty, state (`no card yet` before a brain's first card), `K/D` from the seat counts, actions, wraps, fall loop, aim error, `Age` of the card, uptime; accuracy, air time and learning appear once a brain sends them. A column that is `-` everywhere is left out.
- `TRAFFIC`: IN and OUT lines plus two 60 s `KB/s` curves. `EVENTS`: the tagged log lines fill the rest, filtered with `1`-`9`. When the screen is short the events panel folds first, then traffic; the panels above are never cut (about 35 lines with a live harness and 4 brains).

**Code shape:** `Deck` holds the view (zoom, pan, selection, filters, alerts, 60 s of ping and traffic), `build_strip` makes the fight strip (`tape_inspect` adds the tape state of a round-end column), `tape_text` fills the `Tape` seat column, `render_rich` / `render_plain` draw it with a height budget.

**`--controls` (the laptop screen, v0.0.40):** a SERVER panel above the header with the play links and buttons **+ bot**, **- bot**, **clear bots**, **wifi help** (keys `a`, `r`, `x`, `w`; `tools/tbbot.py` does the work). `a` or **+ bot** opens the bot menu (v0.0.41): `1` to `6` or a click on a chip adds that persona, `a` adds the next in the list, Esc closes; while it is open the digits go to the menu, not the event filter. `i` or **info** opens the about panel: the game in a line, the version, the GitHub link, what `docs/` is.

**Server log tags:** every `server.log` line starts with `[JOIN] [LEAVE] [CONN] [NAME] [LOCK] [MATCH] [ROUND] [KILL] [NET] [STATS] [GATE] [TAPE]`. `[STATS]` reads `players=4 (2 bots) spectators=M sockets=N+M`. The packet dumps (`[MSG]`, `[SEND]`) are debug level and go to `debug.log` only. Colours show only on a real terminal; the files stay plain (`HH:MM:SS | LEVEL | message`).

Related: [[harness-deck-and-gate]], [[tape]], [[replay]].

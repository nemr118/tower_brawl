# Tower Brawl - Project Notes & Dev Server Guide

## 🗺️ Project Architecture
Tower Brawl is a 4-player local network Godot 4 web game that runs entirely in the browser using HTML5/WebGL.
- **Backend:** A custom Python server (`serve_game.py`) running a custom WebSocket implementation (`websockets` library). It acts as the authoritative state machine for the lobby, player slots, and match transitions.
- **Frontend/Client:** Godot 4. The `global.gd` singleton acts as the network root, parsing all incoming WebSocket packets and delegating state updates (like locking in or syncing player coordinates) to the UI via Godot signals.
- **Godot High-Level Multiplayer:** We explicitly do **NOT** use `ENetMultiplayerPeer` or Godot's built-in Multiplayer API. The netcode is entirely custom JSON over WebSockets.

---

## 🔗 Relevant Links
- **Local PC Testing (HTTP):** `http://192.168.4.21:8000`
- **Mobile Device Testing (HTTPS):** `https://192.168.4.21:8443` *(Requires HTTPS for `SharedArrayBuffer` support on mobile browsers).*
- **Public Tunnel (If active):** `https://towerbrawl-server.loca.lt`

> [!WARNING] Mobile Caching
> Mobile browsers (especially iOS Safari) are notoriously aggressive at caching. If you push an update and the phone doesn't see it, you must increment the `.pck` version (e.g. `index_v9.pck`).

---

## 💻 Relevant Terminal Commands

### 1. Launching the Godot Editor
To open the project visually in the Godot Engine Editor from the terminal:
```bash
# From inside the tower_brawl directory:
godot --editor project.godot &
```
*(The `&` runs it in the background so you can keep using your terminal).*

### 2. Starting the Python Server
```bash
# Start the authoritative WebSocket backend and HTTP file server
./venv/bin/python serve_game.py
```
*(If you have set up a systemd service for it, you can use `systemctl --user restart towerbrawl` instead).*

### 3. + 4. Build, Version-Bump and Cache-Bust in one step
When you modify GDScript, run:
```bash
./bump_build.sh            # patch bump (v0.0.4 -> v0.0.5), compile-check, export, version the pck
./bump_build.sh minor      # v0.0.5 -> v0.1.0
./bump_build.sh none       # re-export the current version (does NOT bust caches)
./bump_build.sh --clean    # also delete older index_v*.pck copies (20 MB each)
```
It prints the versioned URL to open, e.g. `https://192.168.4.21:8443/index_v0.0.5.html`. The plain `/index.html` is patched to load the same pck, so the root URL works too as long as the HTML itself is not cached.

The version string lives in ONE place, `const GAME_VERSION` in `scripts/global.gd`. The script mirrors it into `serve_game.py`, and the running server re-reads it from `global.gd` on every join, so a rebuild does not need a server restart (a change to `serve_game.py` itself still does: `systemctl --user restart towerbrawl`).

Versioning scheme: `v0.0.x` while building; `v0.1.0` is the target once the VHS replay, the network/state bugs and the optimizations are done.

### 5. The Test Harness (formerly the Chaos Bots)
`tools/chaos_bots.py` is a protocol test harness: every bot behaves like the Godot client (join, name, lock in, 30 Hz `sync_pos` while alive, silence while dead, 1 s pings) and keeps a model of what the server state should be. Every packet is checked against a per-type schema, the model (oracle) and a duplicate-broadcast detector. Named scenarios end with a report and a non-zero exit code on any finding.
```bash
./venv/bin/python tools/chaos_bots.py --list                  # scenarios (23 since v0.0.30)
./venv/bin/python tools/chaos_bots.py                         # run them all
./venv/bin/python tools/chaos_bots.py --restart-each          # restart the server before each one (isolates scenarios)
./venv/bin/python tools/chaos_bots.py --scenario smoke --trace /tmp/trace.jsonl   # packet capture with model snapshots
./venv/bin/python tools/chaos_bots.py --scenario play --bots 3 --duration 60 --die-rate 0   # bandwidth baseline
./venv/bin/python tools/chaos_bots.py --json docs/harness_report_<version>.json    # keep a report per build
```
Finding names are stable (`dup.event`, `oracle.stock-mismatch`, `timeout.round-end`, `scenario.reclaim.slot-mismatch`, ...) so reports can be diffed between builds. `--seed` fixes bot behaviour; `--die-rate` sets per-second mortality (0 = immortal). Reports for each build live in `docs/harness_report_*.json`.

Step 2 scenarios (added after Phase 1):
```bash
./venv/bin/python tools/chaos_bots.py --scenario fleet --godot 2 --duration 60   # real headless Godot clients + bots; fails on any SCRIPT ERROR (logs in .harness_logs/)
./venv/bin/python tools/chaos_bots.py --scenario fuzz          # bad JSON, wrong types, binary opcode, 3000-packet burst, 512 KB payload, lying length header
./venv/bin/python tools/chaos_bots.py --scenario slow_reader   # a client stops reading: head-of-line blocking check
./venv/bin/python tools/chaos_bots.py --scenario stop_pinging  # a silent client must be dropped and announced
./venv/bin/python tools/chaos_bots.py --scenario lag           # 150 +/- 50 ms and 10% loss on one player
./venv/bin/python tools/chaos_bots.py --scenario play --latency-ms 120 --jitter-ms 40 --loss 0.05   # fault knobs for Phase 3 interpolation work
./venv/bin/python tools/chaos_bots.py --soak 30                # loop the suite on one server, watch RSS / threads / fds for growth
./venv/bin/python tools/chaos_bots.py --scenario ranger_rejoin  # v0.0.30: a headless ranger reloads mid-match with an empty quiver saved (about 40 s)
```

### 6. Headless Godot as a real client (bandwidth measurements)
```bash
godot --headless --path . -- --autojoin --name=Headless --class=2
godot --headless --path . -- --autojoin --name=Headless --reclaim=2   # ask for seat 2 back at once, like a browser after a page reload (v0.0.28)
```
Joins, names itself, locks in, and once the match starts runs `player.gd` for real, sending `sync_pos` at the true rate. Every 5 s it prints a `📈 [NetStats]` line (bytes/packets in and out, per packet type, the puppet jitter numbers, and since v0.0.27 the frame rate: `fps draw=59.8 phys=60.0 worst=21ms hitches=0` = pictures drawn a second, physics ticks a second, the slowest single frame, frames over 50 ms). The same line appears in the browser console of any real client, so a phone playtest shows where the frames drop. Since v0.0.28 the line ends with `keys=<key presses since the last line> focus=<1 if the game canvas has the page focus>`: in a browser the keyboard only reaches the game while the canvas has the focus, so `focus=0` explains a fighter that aims with the mouse but does not walk. Since v0.0.30 a rejoin prints one `🏹 [Quiver] rejoin slot=2 round=2 saved_round=2 arrows=0->1 charges=3 kunai=4 bear=0 tick=612` line: the ammo restored from the save (`localStorage` key `towerbrawl_combat` in a browser, `user://towerbrawl_combat.sav` headless); a save from another round is ignored, a same-round ranger keeps at least 1 arrow. The server logs a `[STATS]` line every 10 s in `server.log`.

### 7. The live operations deck (v0.0.21, grown in v0.0.22, keys and mouse since v0.0.24, tape column since v0.0.25)
```bash
tbdash                                               # alias in ~/.bashrc for the line below, works from any folder
./venv/bin/python tools/watch_server.py              # live view, keys and mouse, q or Ctrl+C to stop
./venv/bin/python tools/watch_server.py --plain      # plain text, no colours, no keys
./venv/bin/python tools/watch_server.py --once       # one colour picture, then exit (--once --plain for text)
./venv/bin/python tools/watch_server.py --no-mouse   # keyboard only (a terminal that eats the mouse codes)
./venv/bin/python tools/watch_server.py --zoom 5     # start at 5 s per strip column
python3 tools/deck_input.py                          # self-test of the key and mouse parser
```
Keys: `←` `→` pan the fight strip, `+` `-` zoom (0.5, 1, 2, 5, 10, 30 s per column), `Home` match start, `End` or `f` back to live, click a column to read what happened in that second, `Esc` clears it, `1`-`9` and `0` hide or show a log tag (`KILL ROUND MATCH JOIN LEAVE NAME LOCK CONN NET`, `0` = `TAPE`), `PgUp` `PgDn` scroll the log, `p` pause, `s` save `deck_snapshot_<HH-MM-SS>.txt` in the repo root, `q` quit. Mouse: wheel pans, Ctrl+wheel or Shift+wheel zooms around the pointer, wheel over the events panel scrolls it. Works in `foot` and `ghostty`; inside `tmux` the mouse needs `set -g mouse on`.
The server writes `status.json` once a second (match state, one row per seat with kills, deaths and ping, the bot cards, the kill timeline with round end times, `ended_at`, `winner` and `names` since v0.0.24, traffic rates, the last 40 tagged log lines). The harness writes `harness_state.json` while it runs. The deck only reads those two files; it never talks to the server. A red bar means `status.json` is missing or older than 3 s, so the server is probably down (`systemctl --user status towerbrawl`). A yellow bar means the harness is restarting the server between scenarios.

The picture is a stack of panels. A panel with nothing to show is not drawn:
- `HEADER`: state, round, flips, players (with the bot count), spectators, uptime.
- `HARNESS`: only while a harness run is alive. Scenario name and place in the suite, a progress bar, `ETA` from the newest `docs/harness_report_*.json`, what the scenario tests, the last step, the checklist (✔ PASS, ✖ FAIL, ▲ Minor, ● running, ○ waiting; `SLOW` in yellow when a scenario runs past twice its last time), findings and warnings. A finished run stays as one line for ten minutes.
- `ALERT`: a red line at the very top for 10 s when an `ERROR` line, a `[NET]` stall or a harness-gate demotion lands.
- `SEATS`: name (🤖 for a bot), class, state, lives, crowns, `K/D`, `Ping`, `Trend` (the ping over the last 60 s, lowest to highest, on terminals 120 columns or wider), `Health` (`good`, `laggy` over 150 ms, `slow` when the send queue backs up, `quiet` after 3 s of silence, `stalled` after 5 s, `held`, `empty`), `Tape` (v0.0.25, only when a screen sent a card: `● 5.0s ·2` = recording, 5 s on the tape, 2 kills stamped this round; `■ R3 ✓` = frozen for round 3 with the closing kill; see section 9), link, packets in, queue and drops, seconds since the last packet.
- `FIGHT`: from the first second of a match. One column is 1 s (zoom 0.5 to 30 s). `kills/1s` row = exact count per column. One lane per fighter, label `P2 Godot4 ♛4 42/24` (crowns, kills/deaths) in the seat colour (P1 blue, P2 red, P3 green, P4 yellow). A kill is the weapon glyph in the victim's colour (`➶` arrow, `✦` firebolt, `✧` kunai, `❋` thorns, `⚔` melee, `▼` stomp), a death is `✕` in the killer's colour, `◈` both, a digit when two or more events share a column. Every second round has a grey band. `┃` round start, `┫` round end, `♛` on the winner's lane one column after the closing kill, `║` match end, `round` row `R2 21s ♛ P2`, `time` axis in `m:ss`, `▶ live` on the right while following (`▶ end` for a finished match). Pan away and the title says `view 0:00-3:49 (End = live)`. Click a column: the line under the axis reads `1:00  Godot2 (P4) killed Andrew (P1) with Firebolt · round 1 ended, P4 Godot2 won · tape frozen on 2 screens (P1 P4), 300 frames before the kill / 60 after`. Stays after the match ends (`last match, P2 won`) until the next one starts.
- `BOT ARENA`: whenever a bot is seated, brains and plain clients alike. `Kind` (`brain`, `headless`, `protocol`), persona, difficulty, state (`no card yet` before a brain's first card), `K/D` from the seat counts, actions, wraps, fall loop, aim error, `Age` of the card, uptime; accuracy, air time and learning appear once a brain sends them. A column that is `-` everywhere is left out.
- `TRAFFIC`: IN and OUT lines plus two 60 s `KB/s` curves. `EVENTS`: the tagged log lines fill the rest, filtered with `1`-`9`. When the screen is short the events panel folds first, then traffic; the panels above are never cut (about 35 lines with a live harness and 4 brains).

Every `server.log` line starts with a tag since v0.0.21: `[JOIN] [LEAVE] [CONN] [NAME] [LOCK] [MATCH] [ROUND] [KILL] [NET] [STATS]`, plus `[GATE]` (v0.0.23) and `[TAPE]` (v0.0.25). The packet dumps (`[MSG]`, `[SEND]`) are debug level and go to `debug.log` only. Colours show only on a real terminal; the files stay plain.

### 8. The harness on the deck (v0.0.22)
While `tools/chaos_bots.py` runs it writes `harness_state.json` in the repo root (gitignored): the run state, the suite checklist, the running scenario with its step, findings and warnings, and the bot cards of the Godot clients in a fleet run. A heartbeat thread refreshes it once a second. `--no-state` turns it off.

Results have three levels now. `PASS`, `FAIL`, and `MINOR`: the scenario passed but something complained (`ctx.warn(name, detail)` in the harness). The two warnings today are `server.error-logged` (the server wrote an `ERROR` line or a traceback during the scenario) and `fleet.script-warning` (a Godot client printed a `WARNING:` line). The report table has a `warn` column and a `WARNINGS` block; the JSON report carries `warnings` and `minor` per scenario.

Bots tell the server who they are: `"bot": "<persona>"` in `request_join` (`"protocol"` for a harness bot), and a brain sends a `bot_status` card every 5 s. The server keeps the last card per seat in `status.json` (`seats[].bot`) and never relays it. The card shape is the same in `status.json` and in `harness_state.json` (`bots[]`):
```json
{"schema": 1, "kind": "brain", "seat": 2, "persona": "sniper", "seed": 421, "difficulty": 0.7, "uptime_s": 45,
 "state": null, "target": null, "goal": [320, 200],
 "actions": {"decisions": 412, "moves": 300, "jumps": 40, "dashes": 12, "attacks": 38, "specials": 6, "evades": 7},
 "nav": {"wraps": 3, "drops": 1, "seams": 2, "land_avg_s": 0.42, "max_loop": 1},
 "aim": {"err_mean_deg": 0.0, "err_max_deg": 0.1, "frames": 900},
 "combat": {"kills": null, "deaths": null, "shots": null, "hits": null, "accuracy": null, "air_time_pct": null, "damage_dealt": null},
 "learning": {"episode": null, "reward": null, "weights": {}, "deltas": {}}}
```
`state`, `target`, `combat` and `learning` are empty slots for future bot brains (a state like `seeking`, `retreating`, `camping`; the seat it hunts; accuracy and air time; learning weights and their deltas). The deck draws them as soon as a brain fills them.

**The harness gate (v0.0.23).** The server reads the same `harness_state.json` once a second. While `state` is `running` or `restarting`, `written_at` is under 5 s old and the harness `pid` is alive, every seat is for bots only. A person who presses JOIN gets a `join_locked` packet and stays a spectator; a person already seated is moved back to spectator (`[LEAVE] P1 was moved to spectator by the harness gate` in `server.log`, `[GATE]` lines when the gate closes and opens). Bots pass because they say `"bot"` in `request_join` (`"protocol"`, `"headless"`, or a persona). The screen shows a small amber ticker: `TESTS RUNNING - JOIN IS LOCKED / Scenario: reclaim / Tests done: 5 / 19` (lobby, in the JOIN MATCH spot) or one line under the arena top bar. The deck header says `SEATS LOCKED (harness)`. `--no-state` turns the file off, so it also leaves the gate open. Check the gate from the shell:
```bash
python3 -c "import json; print(json.load(open('status.json'))['harness'])"   # {'active': True, 'state': 'running', 'scenario': 'smoke', 'done': 0, 'total': 19, ...}
grep "\[GATE\]" server.log | tail                                           # when the gate closed and opened
```

### 9. The tape: history ring and kill stamps (Phase 3c, v0.0.25)
Every screen keeps a tape of the last six seconds of the fight, as that screen drew it (`scripts/history_ring.gd`, driven by `arena.gd`). One frame per physics tick (60 a second), 360 slots made once and reused: 5 s before a kill plus a 1 s tail after it. A frame holds the spin (`rot`, `flips`), every fighter (`[x, y, aim_x, aim_y, flags]`, the `sync_pos` flag bits plus `FLAG_BUBBLE` 64 and `FLAG_DEAD` 128), every projectile (`[weapon_id, x, y, rot, stuck, shooter]`) and the power-up. When the server's `player_died` arrives (it carries `weapon` since v0.0.25) the newest frame is stamped: `{seq, round, killer, victim, weapon, closing, fighters}`. On `round_end` the newest stamp becomes the closing kill, the tape records 60 more frames and freezes; `new_round` clears it. Since v0.0.26 the frozen tape is played back: section 10.

How to see it:
```bash
grep "📼 \[Tape\]" .harness_logs/godot1.log | tail -3     # one line per stamp and per freeze on a headless client
#   📼 [Tape] round=1 frozen=1 closing=1 killer=3 victim=4 weapon=Firebolt seq=695 before=300 after=60 span_ms=5989 fps=59.9 stamps=9 frames=360
grep "\[TAPE\]" server.log | tail                          # [TAPE] P3's screen froze the round 1 tape: P3 killed P4 with 'Firebolt', 300 frames before, 60 after
python3 -c "import json; [print(s['id'], s['tape']) for s in json.load(open('status.json'))['seats']]"   # the history_status card per seat
./venv/bin/python tools/chaos_bots.py --scenario tape      # the Phase 3c scenario (about 24 s)
```
The browser console prints the same `📼 [Tape]` line. The card (`history_status`, client to server, never relayed, kept as `seats[].tape` in `status.json`): `frames, span_ms, fps, recording, frozen, round, stamps, closing_seq, last {seq, round, killer, victim, weapon, closing, before, after, fighters}, replay` (the replay card, v0.0.26, section 10). On the deck: the `Tape` column in SEATS, the inspect line of a round-end column, and the `[TAPE]` events on key `0`. Good numbers: `before=300 after=60 fps=59.9`. The harness fails a tape under 280 frames before the closing kill, under 30 after, or outside 50 to 70 fps (`tape` scenario, and `tape_gate` on `fleet` and `lag`).

### 10. The replay: playing the tape back (v0.0.26)
When a round ends on a kill, the server puts `"replay": true` in `round_end` and waits `REPLAY_ROUND_DELAY = 6.5` s before `new_round` (a draw or a forfeit win keeps `NEXT_ROUND_DELAY = 2.6`; a won match waits `MATCH_END_DELAY = 7.0`, was 6.0). The rule in `_check_round_end`: a winner, and a death in `last_death` within `REPLAY_KILL_WINDOW = 1.5` s. Every screen (players and spectators alike) plays its own frozen tape with `scripts/replay_player.gd`, started by `arena.gd` the moment the tape freezes (about 1.0 s after `round_end`):
- **What plays:** 211 frames around the closing kill `K`: `◄◄ REW` from K+60 back to K-150 at 10x (0.4 s), `► PLAY` K-150 to K-30 at 1x (2.0 s), `► SLOW` K-30 to K+30 at 0.5x with a white flash on K (2.0 s), `► PLAY` K+30 to K+60, the fall (0.5 s), `■ STOP` with a fade to black (0.2 s). 5.1 s in all; `new_round` at 6.5 s cuts anything still running.
- **How:** the live fighters and projectiles are paused (`process_mode = DISABLED`, hidden); ghosts are real `player.tscn` and projectile scenes with `is_ghost = true` (no physics, no collision, not in the `players` / `projectiles` groups) moved to the frame's spots; the platforms turn to the frame's `rot`; a VHS overlay draws scanlines, a rolling tracking bar, a small shake, the label, a counter from the kill (`-2.5s` to `+1.0s`), `REPLAY` with a blinking dot, and the caption `Godot2 killed Andrew · Firebolt`. The banner hides while it plays. Nothing is put back by hand: the next round respawns everyone.
- **Skipped when:** the tape is not frozen 1.5 s after `round_end` (`not-frozen`: a hidden tab whose ticks stalled), nothing was recorded (`empty-tape`), or there is no closing stamp (`no-closing-stamp`).
- **A drop inside the gap (v0.0.28):** a screen that reloads or loses its socket inside the 6.5 s keeps its seat for the 8 s grace, and the next round starts with that seat counted as present (`[ROUND] round 3 starting with [1, 2] (seat held for [2], back within the grace or out)`). Back in time: same seat, `(rejoined mid-match)`, the arena loads at the real round. Never back: the round ends as a forfeit when the grace runs out. A client whose reconnect lands in LOBBY (the match ended meanwhile, or the server restarted) goes back to the lobby scene. Scenario: `./venv/bin/python tools/chaos_bots.py --scenario reload_in_gap` (about 50 s, restarts the server once in its last act).

How to see it:
```bash
grep "📼 \[Replay\]" .harness_logs/godot1.log | tail -3   # one line per replay, played, cut or skipped
#   📼 [Replay] round=1 killer=4 victim=3 weapon=Firebolt from=869 to=1079 frames=211 drawn=211 dur_ms=5050 late_ms=987 cut=0 skipped=-
grep "\[TAPE\].*replay" server.log | tail                 # [TAPE] P3's screen played the round 1 replay: 211 frames in 5.0 s, started 1.0 s after the round end
python3 -c "import json; [print(s['id'], (s['tape'] or {}).get('replay')) for s in json.load(open('status.json'))['seats']]"
./venv/bin/python tools/chaos_bots.py --scenario replay    # the v0.0.26 scenario (about 30 s)
```
The card: `history_status.replay = {playing, played, round, frames, drawn, dur_ms, late_ms, cut, skipped}`, sent once when the replay starts and once when it ends or is skipped. On the deck the `Tape` column reads `▶ R3` while playing, `■ R3 ✓ ▶5.1s` after, `■ R3 ✓ ✗` when skipped; the inspect line of a round-end column adds `· replay played on 2 screens (P3 P4), 5.1 s, started 1.0 s after the kill`. Good numbers: `frames=211 drawn=211 dur_ms≈5050 late_ms≈1000 cut=0`. The harness `replay` scenario wants `round_end.replay == true`, `new_round` 6.0 to 8.0 s after `round_end`, 200+ frames, 90 %+ drawn, 4 500 to 6 000 ms, started within 1 500 ms, not cut, not skipped, and a played card in `status.json`; `replay_gate` on `fleet` and `lag` wants every frozen tape with a closing kill (but the last) played back on time.

---

## 📝 Patch Notes
Live in the `Patch Notes/` folder, one page per version, indexed newest-first in [[Changelog]]. `./bump_build.sh --title "Short Title"` creates the page from `patch_note_template.md` and inserts the Changelog link; fill in the page before or right after the bump (CLAUDE.md rule 5).

---

## 🧠 Critical Learnings & Bug Fixes

### The "Ghost Player" ID Collision Bug
**The Bug:** The Godot client caches the player's ID in `localStorage` so they can seamlessly rejoin if their browser crashes. However, if the server restarted, it would assign that slot (e.g., Player 1) to a bot. When the user refreshed, their client saw `localStorage == 1`, saw Player 1 in the lobby, and falsely assumed *it* was Player 1, permanently hiding the "Join Match" button.
**The Fix:** We introduced a strict `Global.is_spectator` boolean. The client now strictly ignores its `localStorage` ID and acts as a spectator until the server explicitly responds to a `request_join` packet with an `assign_id` payload.

### The Scene Transition Void
**The Bug:** Bots would force the match to start on the server, but the server never told the spectator clients that the match had started. The bots would fight in the void while the user was stuck looking at the character select screen.
**The Fix:** The Python server now broadcasts a explicit `{"type": "scene_transition"}` packet the moment the lobby locks in. The Godot client intercepts this packet and forces a hard transition to `res://scenes/arena.tscn`, instantly pulling players and spectators out of the lobby and into the Arena.

### The GDScript Silent Fail
**The Pitfall:** If you introduce a syntax error in a GDScript file, `godot --headless --export-release` still succeeds and ships the broken script.
**The Trap:** `godot --headless --check-only scripts/x.gd` does NOT work here. Without `--script` it launches the whole game (a stale process was found hung for over an hour). With `--script` it runs before autoloads are registered, so every script that mentions `Global` fails with `Identifier not found: Global` even when it is correct.
**The Fix:** `bump_build.sh` runs `tools/check_scripts.gd`, a SceneTree script that loads every `.gd` file after autoloads exist and exits non-zero on any parse or compile error. Run it alone with:
```bash
godot --headless --path . --script tools/check_scripts.gd -- --no-net
```

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
./venv/bin/python tools/chaos_bots.py --list                  # scenarios
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
```

### 6. Headless Godot as a real client (bandwidth measurements)
```bash
godot --headless --path . -- --autojoin --name=Headless --class=2
```
Joins, names itself, locks in, and once the match starts runs `player.gd` for real, sending `sync_pos` at the true rate. Every 5 s it prints a `📈 [NetStats]` line (bytes/packets in and out, per packet type). The same line appears in the browser console of any real client. The server logs a `[STATS]` line every 10 s in `server.log`.

### 7. The live server dashboard (v0.0.21)
```bash
./venv/bin/python tools/watch_server.py              # live view, redraws every second, Ctrl+C to stop
./venv/bin/python tools/watch_server.py --plain      # plain text, no colours
./venv/bin/python tools/watch_server.py --once       # one picture, then exit (handy in a script)
```
The server writes `status.json` once a second (match state, one row per seat, traffic rates, the last 40 tagged log lines). The dashboard only reads that file; it never talks to the server. A red bar means the file is missing or older than 3 s, so the server is probably down (`systemctl --user status towerbrawl`). Every `server.log` line starts with a tag since v0.0.21: `[JOIN] [LEAVE] [CONN] [NAME] [LOCK] [MATCH] [ROUND] [KILL] [NET] [STATS]`. The packet dumps (`[MSG]`, `[SEND]`) are debug level and go to `debug.log` only. Colours show only on a real terminal; the files stay plain.

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

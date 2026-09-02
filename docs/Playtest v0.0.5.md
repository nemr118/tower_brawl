---
tags: [playtest]
build: v0.0.5
---
# Playtest v0.0.5 — browser & mobile

Goal: prove in real browsers what the headless suite cannot, in ~15 minutes. Needs one PC (Chrome/Firefox, DevTools console open) and one or two phones on the LAN. Server: `systemctl --user status towerbrawl` should be active; build served from `build/web`.

**URLs:** PC `http://192.168.4.21:8000/index_v0.0.5.html` · phones `https://192.168.4.21:8443/index_v0.0.5.html` (accept the self-signed cert once).
**Watch on the PC:** the browser console prints a `📈 [NetStats 5s]` line every 5 s. **Watch on the server:** `tail -f ~/Work/tower_brawl/server.log`.

| # | Check | Do | Expect | If broken you will see |
|---|---|---|---|---|
| 1 | **Binary frames in the browser** (the one thing headless could not prove) | PC + 1 phone join, start a match, run around | Both fighters move on both screens. Console: `out: sync_pos=150(1350B)` per 5 s (9 B each) and `in: sync_pos=…` with `avg 9 B`. Server `[STATS]` line shows `avg 10 B`. | Opponent frozen at spawn; `<bad-binary>` in the NetStats line; `invalid binary packet` warnings in server.log |
| 2 | **RTT on Wi-Fi** | Read `rtt N ms` at the end of the phone's NetStats line (phone console via `chrome://inspect`, or just the PC's line) | A number (first real latency data for Phase 3; 5–40 ms on LAN is normal) | `rtt -1 ms` = no pong reaching the client |
| 3 | **Version-mismatch banner** | On the PC: `sed -i 's/"v0.0.5"/"v0.0.6"/' scripts/global.gd` (no rebuild; the server re-reads it). On a phone press JOIN MATCH. Then revert: `sed -i 's/"v0.0.6"/"v0.0.5"/' scripts/global.gd` | Red "UPDATE REQUIRED … reload the page" label at the top of the lobby, JOIN button greyed. After the revert, reload → join works | Nothing happens on JOIN (only a console line) |
| 4 | **Thorns on remote screens** | One player picks **Druid**, presses attack a few times | The *other* screen shows green thorns flying from the druid | Thorns only on the druid's own screen (was the pre-v0.0.5 behaviour) |
| 5 | **Spectator view, no ghost fighters** | Third device (or a second tab) opens the URL and does **not** join; the two players start | Spectator sees the arena with exactly 2 fighters and a "SPECTATING…" banner. Press JOIN NEXT MATCH → "YOU'RE IN THE QUEUE…" banner; when the round ends everyone returns to the lobby | 4 fighters (two idle ghosts at spawn) on the spectator's screen |
| 6 | **5-crown match end** | 2 players; one stands still, the other kills them 3× per round, 5 rounds (~3–4 min) | Banner "WINS THE MATCH! Returning to lobby…", lobby after ~6 s, scores reset to 0. Server log: `WINS THE MATCH (5 crowns)` then `MATCH OVER -> LOBBY (match won)` | Another round starts after the 5th win, or the banner is replaced by "ROUND 6" |
| 7 | **Page reload mid-lobby (hot reclaim)** | In the lobby, reload one phone's page | That player keeps its slot; the *other* screens never show it leaving | Roster flickers "left" on the other screens; a new slot number |
| 8 | **Everyone leaves mid-match (idle reset)** | During a match, all players press LEAVE MATCH / close tabs; then one rejoins | Server log: `Last player left mid-match -> LOBBY (idle reset)`; the rejoiner lands in a clean lobby | Rejoiner is sent straight into an empty arena |

**Send back:** 2–3 NetStats lines from the PC console, the last 30 lines of `server.log`, phone models + browsers, and a note per row (✅ / ❌ + what you saw). Anything ❌ becomes a harness scenario before Phase 3a starts.

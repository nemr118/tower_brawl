---
tags: [playtest]
build: v0.0.5
---
# Playtest v0.0.5 — browser & mobile

Goal: prove in real browsers what the headless suite cannot, in ~15 minutes. Needs one PC (Chrome/Firefox, DevTools console open) and one or two phones on the LAN. Server: `systemctl --user status towerbrawl` should be active; build served from `build/web`.

**URL (everyone):** `https://192.168.4.21:8443/play` redirects to the current versioned page (accept the self-signed cert once). On the PC use HTTPS too, or `http://localhost:8000/play`; plain `http://192.168.x.x` is not a secure context in Chromium.
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

---

## Results (2026-09-02, PC Chromium + Android phone + spectator tab)

**Verified:** binary frames in the browser (NetStats 10 B/pkt, 0.30 KB/s, RTT 2–4 ms), thorns replicated, 5-crown match end, lobby reload, spectator view.

| # | Observation | Root cause (from server.log + code) | Fix (v0.0.6) |
|---|---|---|---|
| 1 | No touch controls on the phone (aim via touch worked, no movement/attacks) | `touch_controls.gd` showed itself only on the `web_android` / `web_ios` feature tags, which this phone did not report | Visible when Global's user-agent check, the feature tags **or** `DisplayServer.is_touchscreen_available()` say so, and revealed on the first screen touch regardless |
| 1 | "Mobile disconnected, PC stayed in the match, could not rejoin" | The log shows the opposite: **P4 = the PC** was dropped ("P4 LEFT remaining=[1]") a minute into every match. The PC tab was in the background (spectator tab, typing) so Chromium paused the engine loop, no pings for 10 s, the server cut it, the match ended and the phone went to the lobby via `return_to_lobby`. The PC reconnected as a spectator with a stale `my_player_id` and nothing ever moved it out of the arena | Liveness is TCP keepalive now (a hidden tab keeps its seat; a dead peer is detected in ~25 s). On reconnect the client asks for its seat back with its token and the scene is corrected to the server's state |
| 1 | Death desync: PC killed the phone, phone never died, puppet stuck dead on the PC | Only the victim's own client could report a death; the phone's simulation did not see the hit. One kill in the whole session ("Thorns") confirms it. Melee kills never counted at all for the same reason | Observer-authoritative deaths: whichever client sees the hit reports it, the server accepts the first report per death and ignores repeats for 1.5 s |
| 1 | PC always slot 4, phone slot 1 | `reclaim_id` from localStorage was honoured unconditionally, forever | A client token; a saved slot is honoured only with the token that held it (reload, rejoin grace, or left < 2 min ago), otherwise lowest free slot 1→2→3→4 |
| 4 | Phone dropped after ~10 s of typing | Same 10 s server timeout while the keyboard/background throttled the engine | TCP keepalive, see above |
| 5 | PC input stuck 3–7 s, always at spectator reconnects | The spectator tab shares Chromium's renderer main thread with the game tab; its reconnect stalls the game tab and the key-up is lost. Spectator churn came from the same 10 s timeout | Keepalive removes the churn; the client releases every player action on focus loss so a stall can no longer leave a key held. Spectating from a second **device** or browser profile avoids the shared main thread entirely |
| 5 | Arena flip wrong for a reconnecting spectator | Platform rotation was never in the join snapshot | Server counts `activate_powerup`; `arena_flips` in every snapshot; the arena applies it on load |
| 7 | Name missing on the other client | The lobby confirms the saved name (and sends `set_name`) **before** JOIN, while the client is still a spectator, and the server ignored it | Server keeps a pending name per socket and applies it on join; the client also repeats `set_name` on `assign_id` |
| 7 | Mid-match reload = instant win for the other player | Disconnect removed the fighter at once | 8 s rejoin grace: the seat, name and class are held; a reload comes back into the same fight |
| 8 | Both leave within 0.5 s → accidental forfeit win | First leave ended the round immediately | 1.5 s forfeit grace after an explicit leave; if nobody is left the match idle-resets with no winner |
| 3 | Version banner | Test command ran from the wrong directory; server logic unchanged and covered by the `version_mismatch` scenario | — |

Harness coverage added for every server-side fix: `silent_client`, `reload_mid_match`, `simultaneous_leave`, `observer_death`, and a stranger-reclaim check inside `reclaim`. Report: `harness_report_v0.0.6.json`.

### Second pass on the phone (v0.0.6)
| # | Observation | Root cause | Fix (v0.0.7) |
|---|---|---|---|
| 9 | Touch controls appear and move the fighter, but dragging the joystick fires arrows | Godot emulates a mouse click from every touch, and the input map binds mouse button 1 to attack (button 2 to special); every joystick touch was a left click | Touch devices strip the mouse-button bindings from all player actions (on reveal of the touch controls and on slot assignment); the touch controller also marks the screen touch/drag events it handles as consumed |
| 10 | Reload mid-match respawns with a full quiver | Ammo is client-side and the reloaded page started from class defaults; stocks were also reset to 3 locally | `assign_id` carries `rejoined=true` when a socket resumes its own seat in a running match; the client persists arrows / charges / kunai / bear form whenever they change and restores them on a rejoin; stocks now always come from the server (snapshots, `player_died`, `new_round`) |

Harness: `reload_mid_match` asserts the `rejoined` flag; every fresh lobby join asserts it is absent.

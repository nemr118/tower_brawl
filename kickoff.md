# Kick-off prompt (Tower Brawl)

Copy this into a fresh session after /clear, or type: "Read kickoff.md and do what it says".

---

Tower Brawl, branch beta. Read, in this order: CLAUDE.md, docs/PASSDOWN.md, the newest page in docs/Patch Notes/ (v0.2.0-p4.14 - Spooky Platforms, then p4.13 - The Boiler Room), docs/Commands.md.

Where things stand (2026-10-25 evening): the ROG laptop is the travel server at the family gathering (Wi-Fi 192.168.1.244, phones open https://192.168.1.244:8443/v2/, Tailscale 100.78.118.1) running v0.2.0-p4.14: THE BOILER ROOM, candies from bodies and the sky, GHOSTFACE, the new lobby and winner screen, ComfyUI pictures (loading, power-ups, awards), the look polish (client/polish.gd switches), iPhones full screen from the Home Screen (serve_game.py /v2ws). The host page (Ignition, desktop gateway) has a QR code under PLAY ON PHONES. The home laptop still runs p2.1.

Next:
1. After the night: tools/pull_rog_logs.sh, then tools/v2_night_report.py on the night's v2_server.jsonl; ask the user how it went (the iPhones on the Home Screen, GHOSTFACE's rate, the boiler room, candies).
2. The sheet is ready: docs/Playtest v0.2.0-p4.14.md (made 2026-10-25 afternoon from the p4.12 to p4.14 lines; it takes over p1.1's sheet, now archived). Ask the user to fill it in, then act on its verdict.
3. Then (ask first): the newest build on the home laptop and a 3-hour --soak; the release v0.2.0 (G7).
Ideas waiting: a castle loading picture for after Halloween (tools/comfy/, ask before any GPU run), the arenas a step brighter for lit rooms, the in-match banners in the lobby's font, the ROG app's links page that does not open as a window.

Rules: ask before every deploy and never while anyone plays; show any look change to the user as BEFORE/AFTER first; ask before any GPU run (the AMD card can freeze the PC); build from a clean git-archive copy when helpers edit the tree; plain words (the user teaches an 11-year-old); commit on beta at each checked step and push beta alone; never commit cloudflared.

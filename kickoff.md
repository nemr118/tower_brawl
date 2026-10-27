# Kick-off prompt (Tower Brawl)

Copy this into a fresh session after /clear, or type: "Read kickoff.md and do what it says".

---

Tower Brawl, branch beta. Read, in this order: CLAUDE.md, docs/PASSDOWN.md, the newest page in docs/Patch Notes/ (v0.2.0-p4.17 - Victory Lap), docs/Commands.md. Then docs/reference/mobile-controls.md (the phone controls research and the gathering night's logs).

Where things stand (2026-10-26 night): v0.2.0-p4.17 "Victory Lap" is built and committed on beta, but NOT on the ROG yet. The ROG still runs p4.16 "Crisp Phones" (deployed 2026-10-26 18:04). p4.17 is the look for the next play night, made with ComfyUI. The user saw the BEFORE/AFTER pictures and said "yes" to all five pieces: the round banners in the lobby title's style with a painted ribbon (client/hud_banner.gd), the winner's screen's painted backdrop (spooky in October) and the winner's painted hooded archer (client/winner_view.gd), award badges on the lobby cards, and pictures on the lobby's buttons. Each piece has a polish switch (banners2, winner_backdrop, winner_portrait, award_badges, ui_icons). The ComfyUI steps are in tools/comfy/README.md (run_winner.py, run_ui.py, make_assets.py). The ROG (the travel server) is at home (Tailscale 100.78.118.1, wired 192.168.4.37, Wi-Fi 192.168.4.126; phones https://192.168.4.126:8443/v2/). The home laptop runs p2.1.

Next:
1. Ask the user for the go to put p4.17 on the ROG (never while anyone plays): check the ROG's CPU cap, then tools/deploy_rog.sh, then check the host port says v0.2.0-p4.17 and the page loads index_v0.2.0-p4.17.pck.
2. After a night on p4.17 (ask the user how it went): tools/pull_rog_logs.sh and tools/v2_night_report.py: the phones' fps by res and look, memory (mem_mb, tex_mb: flat means no white screen; the winner's pictures add about 7 MB), controls (BUTTONS or CLASSIC), aim_taps, late_pct and eased. Then the sheet lines in p4.16's and p4.17's patch pages (the open sheet is docs/Playtest v0.2.0-p4.14.md, its verdict open).
3. Then (ask first): the home laptop on the newest build with a 3-hour --soak; the release v0.2.0 (G7).
Reported, not fixed: a candy that makes someone GHOSTFACE breaks the server's [POWER] log line (game_server.gd _log_powers: the trick names list has no fourth name).
Ideas waiting: a quick shot when a kid lets go inside the ring (Brawl Stars' tap shot, the server picks the aim); a layout editor (sizes, left-handed); a practice room; the arenas a step brighter for lit rooms; the ROG app's links page that does not open as a window.
Pictures: tools/v2_shot.py --burst 7 (every frame after START) and --until "[Winner]@3,15" (the winner's screen, then the lobby); use --extra nocam for the winner's screen (the test browser plays the replay too slowly to reach it).

Rules: ask before every deploy and never while anyone plays; show any look change to the user as BEFORE/AFTER first; ask before any GPU run (the AMD card can freeze the PC; tools/comfy/batch.sh waits for the card and its lock); build from a clean git-archive copy when helpers edit the tree; plain words (the user teaches an 11-year-old); commit on beta at each checked step and push beta alone; never commit cloudflared; stop a test server by its PID (pkill -f with its arguments kills your own shell).

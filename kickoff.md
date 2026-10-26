# Kick-off prompt (Tower Brawl)

Copy this into a fresh session after /clear, or type: "Read kickoff.md and do what it says".

---

Tower Brawl, branch beta. Read, in this order: CLAUDE.md, docs/PASSDOWN.md, the newest page in docs/Patch Notes/ (v0.2.0-p4.16 - Crisp Phones), docs/Commands.md. Then docs/reference/mobile-controls.md (the phone controls research and the gathering night's logs).

Where things stand (2026-10-26 evening): v0.2.0-p4.16 "Crisp Phones" is built and committed, NOT deployed. It carries the user's picks after the night's logs: iPhone speed (no HIGH on iOS, the arena drawn at 0.75 there), the small control fixes (DODGE taps kept, the let-go wobble, page guards, a dodge buffer, jump buffer 6), the bow only on a pull, the BUTTONS layout (the lobby's CONTROLS), the warping fix (the others glide and ease when snapshots are late), and the ComfyUI art (the arena picker, the trick badges, a castle sky, the loading picture by season). The logs said: iPhones ran 15 to 30 fps (HIGH 16, LOW 60 on one), Wi-Fi stalls froze the others now and then, kids let go inside the ring on 20 to 37% of their touches. The ROG (the travel server) runs p4.14 and is online at home (Tailscale 100.78.118.1, wired 192.168.4.37); its Wi-Fi power save is already off. The home laptop runs p2.1.

Next:
1. Ask the user: p4.16 on the ROG (tools/deploy_rog.sh from a clean git-archive copy of the commit; never while anyone plays).
2. After a night on p4.16: tools/pull_rog_logs.sh and tools/v2_night_report.py: the phones' fps by res (0.75 on iPhones) and look, memory (mem_mb, tex_mb: flat means the white screen is gone), controls (BUTTONS or CLASSIC), aim_taps, late_pct and eased (Wi-Fi stalls). Then the sheet: p4.16's "For the next sheet" lines (the open sheet is docs/Playtest v0.2.0-p4.14.md, its verdict open).
3. Then (ask first): the home laptop on the newest build with a 3-hour --soak; the release v0.2.0 (G7).
Reported, not fixed: a candy that makes someone GHOSTFACE breaks the server's [POWER] log line (game_server.gd _log_powers: the trick names list has no fourth name; the journal counts them by the error).
Ideas waiting: a quick shot when a kid lets go inside the ring (Brawl Stars' tap shot, the server picks the aim); a layout editor (sizes, left-handed); a practice room; the arenas a step brighter for lit rooms; the in-match banners in the lobby's font; the ROG app's links page that does not open as a window.

Rules: ask before every deploy and never while anyone plays; show any look change to the user as BEFORE/AFTER first; ask before any GPU run (the AMD card can freeze the PC; tools/comfy/batch.sh waits for the card and its lock); build from a clean git-archive copy when helpers edit the tree; plain words (the user teaches an 11-year-old); commit on beta at each checked step and push beta alone; never commit cloudflared.

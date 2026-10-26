# Kick-off prompt (Tower Brawl)

Copy this into a fresh session after /clear, or type: "Read kickoff.md and do what it says".

---

Tower Brawl, branch beta. Read, in this order: CLAUDE.md, docs/PASSDOWN.md, the newest page in docs/Patch Notes/ (v0.2.0-p4.15 - Climb Out), docs/Commands.md.

Where things stand (2026-10-25 night): v0.2.0-p4.15 "Climb Out" is built on the PC and committed, NOT deployed. It answers the second gathering night. The user said it went well; the worst was the movement on the phone stick (wall climbs, ledge grabs, dashes; THE HAUNTED HOUSE's bottom-left pit), and iPhones went white every 2-3 matches. p4.15: TowerFall's easier wall moves (sim.gd tf_moves), the stick's pump and swing jumps (?stick=old gives the old stick), the white-screen leaks fixed (the replay's font sheets; the GL numbers patched by tools/v2_build.sh; the page reloads itself if it loses its drawing), and the phone report carries the stick's numbers and the page's memory. tools/pit_probe.gd: a kid model gets out of the pit 97% of tries (was 30%). The ROG (the travel server) still runs p4.14 and was offline at 21:31 (Tailscale 100.78.118.1; wired 192.168.4.37 at home). The home laptop runs p2.1.

Next:
1. Ask the user: p4.15 on the ROG (tools/deploy_rog.sh from a clean git-archive copy; never while anyone plays), and how the new moves feel on their phone.
2. When the ROG is online: tools/pull_rog_logs.sh, then tools/v2_night_report.py on bench_results/2026-10-25/v2_server.jsonl (and 2026-10-24's): the iPhones' sessions around the white screens, GHOSTFACE's rate, the boiler room, candies.
3. After a night on p4.15: the open sheet (docs/Playtest v0.2.0-p4.14.md; p4.15's "For the next sheet" lines go in when the user wants a sheet) and the phones' new numbers (stick: jumps, rim and button dodges; mem_mb and tex_mb should stay flat).
4. Then (ask first): the newest build on the home laptop and a 3-hour --soak; the release v0.2.0 (G7).
Reported, not fixed: a candy that makes someone GHOSTFACE breaks the server's [POWER] log line (game_server.gd _log_powers: the trick names list has no fourth name; a SCRIPT ERROR; the game itself is fine).
Ideas waiting: (Claude's) a JUMP button if the pump and swing still feel hard; a castle loading picture for after Halloween (tools/comfy/, ask before any GPU run); the arenas a step brighter for lit rooms; the in-match banners in the lobby's font; the ROG app's links page that does not open as a window.

Rules: ask before every deploy and never while anyone plays; show any look change to the user as BEFORE/AFTER first; ask before any GPU run (the AMD card can freeze the PC); build from a clean git-archive copy when helpers edit the tree; plain words (the user teaches an 11-year-old); commit on beta at each checked step and push beta alone; never commit cloudflared.

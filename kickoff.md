# Kick-off prompt (Tower Brawl)

Copy this into a fresh session after /clear, or type: "Read kickoff.md and do what it says".

---

Tower Brawl, branch beta. Read, in this order: CLAUDE.md, docs/PASSDOWN.md, the newest page in docs/Patch Notes/ (v0.2.0-p4.15 - Climb Out), docs/Commands.md. Then docs/reference/mobile-controls.md (the phone controls research).

Where things stand (2026-10-26): v0.2.0-p4.15 "Climb Out" is built and committed, NOT deployed (TowerFall's easier wall moves, the stick's pump and swing, the iPhone white-screen leaks fixed). On beta since, NOT built yet: the warping fix (the user: "sometimes characters would warp"): client/net.gd glides the other fighters on at their last speed when snapshots are late (6 ticks at most) and eases out the catch-up over 0.1 s; play_probe --warps with net.gd's --stall=MS knob showed 150 ms stalls every 3 s give 11.6 warps a minute before, 0 after (250 ms: 24.7, 0). The phone report now also carries late_pct, eased, eased_px. The ROG (the travel server) still runs p4.14 and has been offline since the gathering (Tailscale 100.78.118.1; wired 192.168.4.37 at home). The home laptop runs p2.1. The user: "Let's wait for the logs, then we'll make the next decisions."

Next:
1. When the user says the ROG is online: tools/pull_rog_logs.sh, then tools/v2_night_report.py on bench_results/2026-10-25/v2_server.jsonl and 2026-10-24's. Look for: each phone's frame rate (a slow phone feels mushy), the devices (tablets?), pings and late inputs over time (the warping: stalls every few seconds?), reconnects and page errors around the iPhones' white screens, shots let go inside the ring (resting right thumbs), GHOSTFACE's rate, the boiler room, candies.
2. On the ROG (no sudo needed to read): its Wi-Fi power save (iw dev <wifi> get power_save; nmcli -f 802-11-wireless.powersave connection show <conn>). On means the server's own Wi-Fi stalls every phone: offer to turn it off in rog_server.sh's one password box, or a cable at gatherings.
3. Report in plain words, then the user decides the three calls in docs/reference/mobile-controls.md: (1) measure + small fixes (the DODGE button's 2-tick latch, the let-go wobble, the page's long-press and pull-to-refresh guards, a dodge buffer, the jump buffer 6); (2) the bow comes up only once the thumb pulls; (3) a BUTTONS layout (JUMP and DODGE buttons, a following stick) as a lobby choice beside CLASSIC.
4. Then build p4.16 (it must carry the warping fix and the ComfyUI art on beta: the arena picker, the trick badges, the castle backdrop, the loading picture by season; all picked by the user 2026-10-26) and deploy on the user's go; later the home laptop with a 3-hour --soak, and the release v0.2.0 (G7).
Reported, not fixed: a candy that makes someone GHOSTFACE breaks the server's [POWER] log line (game_server.gd _log_powers: the trick names list has no fourth name).
Ideas waiting: the arenas a step brighter for lit rooms; the in-match banners in the lobby's font; the ROG app's links page that does not open as a window.

Rules: ask before every deploy and never while anyone plays; show any look change to the user as BEFORE/AFTER first; ask before any GPU run (the AMD card can freeze the PC); build from a clean git-archive copy when helpers edit the tree; plain words (the user teaches an 11-year-old); commit on beta at each checked step and push beta alone; never commit cloudflared.

#!/usr/bin/env bash
# The ROG laptop as a travel server (2026-10-24, a family gathering): push beta's
# new game (bench/, build/web/v2/, tools/) to the ROG over Tailscale and restart its
# new-game job with the host port (127.0.0.1:8092). The old game is not touched.
#   tools/deploy_rog.sh [host]        (default: the ROG's Tailscale address 100.78.118.1)
# The ROG has no sudo for us, so both games run as the user's own jobs (systemd-run
# --user, linger on): they stop when the ROG restarts; run this again to start the
# new game, and see the setup note below for the pages.
# One-time setup (done 2026-10-24): ~/tower_brawl on the ROG is a copy of the home
# laptop's (no logs, no venv), ~/tower_brawl/bin/godot is this PC's /usr/bin/godot
# (4.7.2; every library it needs is on the ROG), and the pages and the old game run as
#   systemd-run --user --unit=towerbrawl -p WorkingDirectory=$T -p Restart=always /usr/bin/python3 $T/serve_game.py
# Phones need the ROG's firewall open on the Wi-Fi it is on (the user runs, ON THE ROG):
#   sudo ufw allow from <wifi network>/24 to any port 8443,8444,8091 proto tcp
# The host page (Ignition on this PC) reaches the host port through the tunnel unit
# tb-host-tunnel (this PC's 127.0.0.1:18092 -> the ROG's 127.0.0.1:8092).
set -euo pipefail
cd "$(dirname "$0")/.."
HOST="${1:-100.78.118.1}"
R="ssh -i $HOME/.ssh/claude_rog_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes"
D="nemr@$HOST:tower_brawl"
rsync -az -e "$R" --exclude __pycache__ tools/ "$D/tools/"
rsync -az -e "$R" --delete --exclude untracked --exclude .godot/exported --exclude .godot/editor bench/ "$D/bench/"
rsync -az -e "$R" --delete build/web/v2/ "$D/build/web/v2/"
$R "nemr@$HOST" 'bash -s' <<'REMOTE'
set -e
T=/home/nemr/tower_brawl
systemctl --user stop towerbrawl-v2 2>/dev/null || true
systemctl --user reset-failed towerbrawl-v2 2>/dev/null || true
systemd-run --user --unit=towerbrawl-v2 --description="Tower Brawl v2 game server (wss 8091, host port 8092)" -p WorkingDirectory=$T -p Restart=always -p RestartSec=3 $T/bin/godot --headless --path $T/bench res://server/game_server.tscn -- --port 8091 --cert $T/cert.pem --key $T/key.pem --out $T/bench_results --quiet --admin-port 8092
sleep 5
echo "pages + old game: $(systemctl --user is-active towerbrawl)  new game: $(systemctl --user is-active towerbrawl-v2)"
curl -s --max-time 3 http://127.0.0.1:8092/state | python3 -c 'import json,sys; d=json.load(sys.stdin); print("host port:", d["version"], d["phase_name"], "bots", d["bots_wanted"], d["bot_level_name"], "| phones: https://%s:8443/v2/" % (d["lan"][0] if d["lan"] else "?"))'
REMOTE

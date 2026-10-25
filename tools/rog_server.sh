#!/usr/bin/env bash
# Tower Brawl on the ROG laptop, from Super+Space ("Tower Brawl Server", the user's ask
# 2026-10-25): start what is not running (the pages and the old game; the new game with
# its host port 8092, the same jobs tools/deploy_rog.sh starts), wait for the game to
# answer, write the links page (tools/rog_links.py: the links phones open, with QR codes),
# then open the host page (Ignition on the PC, through the tunnel) and the links page, and
# show the phone link in a notification. Safe to run again: a running game is left alone.
#   tools/rog_server.sh [--no-open]   (--no-open: start and write the page, open nothing)
T=/home/nemr/tower_brawl
DASH="http://100.69.199.3:8088/data/perspective/client/TowerBrawlServer"
OUT=$HOME/.cache/tower-brawl
mkdir -p "$OUT"
OPEN=1
[ "${1:-}" = "--no-open" ] && OPEN=0
started=""
if ! systemctl --user is-active -q towerbrawl; then
  systemctl --user reset-failed towerbrawl 2>/dev/null
  systemd-run --user --unit=towerbrawl --description="Tower Brawl pages + old game (https 8443)" \
    -p WorkingDirectory=$T -p Restart=always -p RestartSec=3 /usr/bin/python3 $T/serve_game.py
  started="$started the pages,"
fi
if ! systemctl --user is-active -q towerbrawl-v2; then
  systemctl --user reset-failed towerbrawl-v2 2>/dev/null
  systemd-run --user --unit=towerbrawl-v2 --description="Tower Brawl v2 game server (wss 8091, host port 8092)" \
    -p WorkingDirectory=$T -p Restart=always -p RestartSec=3 $T/bin/godot --headless --path $T/bench \
    res://server/game_server.tscn -- --port 8091 --cert $T/cert.pem --key $T/key.pem --out $T/bench_results --quiet --admin-port 8092
  started="$started the game,"
fi
for i in $(seq 1 40); do
  curl -s --max-time 1 http://127.0.0.1:8092/state > /dev/null && break
  sleep 0.5
done
python3 $T/tools/rog_links.py --out "$OUT/links.html" --dash "$DASH"
IP=$(ip -4 -o addr show scope global | awk '$2 !~ /^(lo|tailscale|docker|br-|veth|virbr)/ {split($4, a, "/"); print a[1]; exit}')
MSG="Phones: https://${IP:-?}:8443/v2/"
[ -n "$started" ] && MSG="Started${started%,}. $MSG" || MSG="Already running. $MSG"
if [ $OPEN = 1 ]; then
  notify-send -a "Tower Brawl" "Tower Brawl" "$MSG" 2>/dev/null
  setsid omarchy-launch-webapp "$DASH" > /dev/null 2>&1 &
  setsid omarchy-launch-webapp "file://$OUT/links.html" > /dev/null 2>&1 &
fi
echo "$MSG"

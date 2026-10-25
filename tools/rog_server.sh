#!/usr/bin/env bash
# Tower Brawl on the ROG laptop, from Super+Space ("Tower Brawl Server", the user's ask
# 2026-10-25): start what is not running (the pages and the old game; the new game with
# its host port 8092, the same jobs tools/deploy_rog.sh starts), wait for the game to
# answer, write the links page (tools/rog_links.py: the links phones open, with QR codes),
# then open the host page (Ignition on the PC, through the tunnel) and the links page, and
# show the phone link in a notification. Safe to run again: a running game is left alone.
# It also opens the firewall to the networks the laptop is on (the user, 2026-10-25: at
# home the ROG let in only the gathering's network): the game's ports (8091 the game,
# 8443 the pages, 8444 the old game) for each network not let in yet, after one password
# box (pkexec: the desktop's own dialog); nothing to do: no box.
#   tools/rog_server.sh [--no-open]   (--no-open: start and write the page, open nothing,
#                                      and only report the firewall)
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
# The firewall: which of this laptop's networks are not let in to the game's ports yet.
PORTS="8091,8443,8444"
NETS=$(python3 -c '
import ipaddress, subprocess
out = subprocess.run(["ip", "-4", "-o", "addr", "show", "scope", "global"], capture_output=True, text=True).stdout
for line in out.splitlines():
    p = line.split()
    if len(p) >= 4 and not p[1].startswith(("lo", "tailscale", "docker", "br-", "veth", "virbr")):
        print(ipaddress.ip_interface(p[3]).network)' | sort -u)
CLOSED=""
if systemctl is-active -q ufw 2>/dev/null; then
  for net in $NETS; do
    grep -q "allow tcp $PORTS 0.0.0.0/0 any $net in" /etc/ufw/user.rules 2>/dev/null || CLOSED="$CLOSED $net"
  done
fi
FW=""
if [ -n "$CLOSED" ]; then
  if [ $OPEN = 1 ]; then
    CMD=""
    for net in $CLOSED; do
      CMD="$CMD ufw allow proto tcp from $net to any port $PORTS comment 'Tower Brawl';"
    done
    if pkexec /bin/sh -c "$CMD" > /dev/null 2>&1; then
      FW=" Firewall opened to:$CLOSED."
    else
      FW=" FIREWALL STILL CLOSED to$CLOSED: phones there cannot join. Run Tower Brawl Server again to type the password."
    fi
  else
    FW=" (the firewall is closed to$CLOSED)"
  fi
fi
for i in $(seq 1 40); do
  curl -s --max-time 1 http://127.0.0.1:8092/state > /dev/null && break
  sleep 0.5
done
python3 $T/tools/rog_links.py --out "$OUT/links.html" --dash "$DASH"
IP=$(ip -4 -o addr show scope global | awk '$2 !~ /^(lo|tailscale|docker|br-|veth|virbr)/ {split($4, a, "/"); print a[1]; exit}')
MSG="Phones: https://${IP:-?}:8443/v2/"
[ -n "$started" ] && MSG="Started${started%,}. $MSG" || MSG="Already running. $MSG"
MSG="$MSG$FW"
if [ $OPEN = 1 ]; then
  notify-send -a "Tower Brawl" "Tower Brawl" "$MSG" 2>/dev/null
  setsid omarchy-launch-webapp "$DASH" > /dev/null 2>&1 &
  setsid omarchy-launch-webapp "file://$OUT/links.html" > /dev/null 2>&1 &
fi
echo "$MSG"

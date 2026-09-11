#!/usr/bin/env bash
# Push the current build to the server laptop and restart the game there.
# Use:  tools/deploy_laptop.sh <laptop ip>            (asks the laptop's sudo password)
#       TB_SUDO_PASS=... tools/deploy_laptop.sh <ip>  (no prompt)
# The laptop screen shows its IP in the TOWER BRAWL SERVER box.
set -e
cd "$(dirname "$0")/.."
HOST="${1:?give the laptop IP, for example: tools/deploy_laptop.sh 192.168.4.29}"
VER=$(grep -o 'GAME_VERSION: String = "[^"]*"' scripts/global.gd | cut -d'"' -f2)
DEST="nemr@$HOST:~/tower_brawl"

echo "Sending $VER to $HOST ..."
rsync -a serve_game.py cert.pem key.pem "$DEST/"
rsync -a project.godot scripts scenes assets web .godot "$DEST/"   # the bots run the game source
rsync -a --exclude __pycache__ tools/ "$DEST/tools/"
rsync -a --exclude 'index_v*' build/web/ "$DEST/build/web/"
rsync -a build/web/index_"$VER".* "$DEST/build/web/"

# v0.1.7: serve_game.py rolls its own logs (one .1 each), so the old logrotate file goes.
RESTART="rm -f /etc/logrotate.d/towerbrawl && systemctl restart towerbrawl"
if [ -n "${TB_SUDO_PASS:-}" ]; then
  # non-interactive (a script or an agent): the laptop's sudo password from the environment
  ssh "nemr@$HOST" "echo '$TB_SUDO_PASS' | sudo -S sh -c '$RESTART' && sleep 2 && systemctl is-active towerbrawl"
else
  ssh -t "nemr@$HOST" "sudo sh -c '$RESTART' && sleep 2 && systemctl is-active towerbrawl"
fi
echo "Done. Play: https://$HOST:8443/play"

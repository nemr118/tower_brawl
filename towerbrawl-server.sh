#!/bin/bash
# Dedicated Background Server & Tunnel Manager for TowerBrawl

cd /home/nemr/Work/tower_brawl
python3 serve_game.py &
PYTHON_PID=$!

trap "kill $PYTHON_PID; exit 0" SIGINT SIGTERM EXIT

while true; do
    echo "Starting localtunnel on towerbrawl-server.loca.lt..."
    npx localtunnel --port 8000 --subdomain towerbrawl-server
    sleep 3
done

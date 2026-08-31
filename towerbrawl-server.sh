#!/bin/bash
# TowerBrawl Dedicated Server wrapper

cd /home/nemr/Work/tower_brawl

# Start Python server
python3 serve_game.py &
PYTHON_PID=$!

sleep 1
echo "Starting cloudflare tunnel..."
./cloudflared tunnel --url http://localhost:8000

# Cleanup trap
trap "kill $PYTHON_PID; exit 0" SIGINT SIGTERM EXIT
wait $PYTHON_PID

#!/usr/bin/env bash
# TowerBrawl Family Game Launcher
# Run this to build + serve + open the game in your browser.

cd "$(dirname "$0")"

# Kill any old server
pkill -f "python3.*serve_game.py" 2>/dev/null
sleep 0.5

# Rebuild (fast, ~3s)
echo "Building..."
./deploy.sh >/dev/null 2>&1

# Start server in background
python3 serve_game.py &
SERVER_PID=$!
sleep 1.5

# Get local IP
LOCAL_IP=$(python3 -c "import socket; s=socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.connect(('8.8.8.8',80)); print(s.getsockname()[0]); s.close()" 2>/dev/null || echo "192.168.4.21")

echo ""
echo "==========================================="
echo "  Game is live!"
echo "  Your browser  -> http://localhost:8000"
echo "  Family phones -> https://$LOCAL_IP:8443"
echo "==========================================="
echo ""

# Open your browser automatically
xdg-open "http://localhost:8000" 2>/dev/null &

# Keep terminal open showing server logs
wait $SERVER_PID

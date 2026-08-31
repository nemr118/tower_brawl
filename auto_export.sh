#!/usr/bin/env bash
cd "$(dirname "$0")"

# 1. Export Web Build quietly
./deploy.sh >/dev/null 2>&1

# 2. Ensure Python Server is running
if ! pgrep -f "python3 serve_game.py" > /dev/null; then
    python3 serve_game.py &
fi

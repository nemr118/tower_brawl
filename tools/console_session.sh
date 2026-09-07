#!/usr/bin/env bash
# What runs inside the terminal on the server laptop's screen (via cage + foot).
# Help box, then the deck. q in the deck lands in a shell; leaving the shell restarts this.
export TB_CONSOLE=1
cd "$(dirname "$0")/.." || exit 1
while true; do
    tools/console.sh
    echo "  the deck opens in 5 s (press q in the deck for a shell) ..."
    sleep 5
    ./venv/bin/python tools/watch_server.py --controls
    tools/console.sh
    echo "  You are in a shell. Type exit to go back to the deck."
    bash -i
done

#!/bin/bash
while true; do
    systemctl --user stop towerbrawl.service
    sleep 3
    systemctl --user start towerbrawl.service
    sleep 3
    URL=$(journalctl --user -u towerbrawl.service -n 5 | grep "your url is:" | tail -n 1)
    if [[ "$URL" == *"https://towerbrawl-server.loca.lt"* ]]; then
        echo "Claimed!"
        break
    else
        echo "Got $URL, retrying..."
        sleep 10
    fi
done

#!/usr/bin/env bash
# Pull the playtest data off the server laptop into playtest_logs/<date>_<ip>/ on this PC.
# Use:  tools/pull_laptop_logs.sh <laptop ip>
# What comes over: client_stats.jsonl (+ .1) = every device's NetStats card, every
# join / name / class pick / kill / leave, every match and round marker;
# server.log; status.json (the last picture); .bots/*.log (the laptop's bots).
# Then:  ./venv/bin/python tools/stats_table.py --file playtest_logs/<folder>/client_stats.jsonl --list
#        ./venv/bin/python tools/stats_table.py --file playtest_logs/<folder>/client_stats.jsonl --summary
set -e
cd "$(dirname "$0")/.."
HOST="${1:?give the laptop IP, for example: tools/pull_laptop_logs.sh 192.168.4.29}"
OUT="playtest_logs/$(date +%Y-%m-%d)_${HOST//./-}"
mkdir -p "$OUT"
rsync -a --ignore-missing-args \
  "nemr@$HOST:~/tower_brawl/client_stats.jsonl" "nemr@$HOST:~/tower_brawl/client_stats.jsonl.1" \
  "nemr@$HOST:~/tower_brawl/server.log" "nemr@$HOST:~/tower_brawl/status.json" "$OUT/"
rsync -a --ignore-missing-args "nemr@$HOST:~/tower_brawl/.bots/" "$OUT/bots/" 2>/dev/null || true
echo "Pulled into $OUT:"
ls -la "$OUT" | tail -n +2
echo
./venv/bin/python tools/stats_table.py --file "$OUT/client_stats.jsonl" --list || true

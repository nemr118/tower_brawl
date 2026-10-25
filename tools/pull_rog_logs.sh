#!/usr/bin/env bash
# Pull the ROG's (the travel server's) game logs into playtest_logs/<today>_rog/: its whole
# bench_results/ (one v2_server.jsonl per server start date: the server's 5 s lines, the
# rounds and matches, the phones' reports since p4.7; v2_stats.json) and the new game's journal.
#   tools/pull_rog_logs.sh [hours of journal, default 36] [host, default the ROG's Tailscale address]
# Then: ./venv/bin/python tools/v2_night_report.py --file playtest_logs/<today>_rog/bench_results/<date>/v2_server.jsonl
set -euo pipefail
cd "$(dirname "$0")/.."
HOURS="${1:-36}"
HOST="${2:-100.78.118.1}"
R="ssh -i $HOME/.ssh/claude_rog_ed25519 -o IdentitiesOnly=yes -o BatchMode=yes"
OUT="playtest_logs/$(date +%F)_rog"
mkdir -p "$OUT"
rsync -az -e "$R" "nemr@$HOST:tower_brawl/bench_results/" "$OUT/bench_results/"
$R "nemr@$HOST" "journalctl --user -u towerbrawl-v2 --since '-${HOURS}h' --no-pager -o short-iso" > "$OUT/journal_v2.txt" || true
echo "pulled into $OUT:"
find "$OUT" -type f -printf "  %p  %s bytes\n" | sort

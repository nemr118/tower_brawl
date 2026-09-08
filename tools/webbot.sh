#!/usr/bin/env bash
# ==============================================================================
# A real WEB client on the PC (v0.1.2). Chromium headless loads the web build
# and plays with a bot brain, so the browser code path (wasm, WebGL, the font
# atlas, the .pck in memory) can be measured without a phone. The page's console
# (📈 [NetStats], 📼 [Tape] / [Replay], 🔤 [FontWarm] ...) goes to .bots/web<N>.log.
# Draws run on SwiftShader (software GL): draw numbers are slow, the script
# numbers (proc, the replay's start_ms) are the web build's real ones.
#
#   tools/webbot.sh [--url https://192.168.4.21:8443/index.html] [--ai chaser] [--name Web1]
#                   [--class N] [--minutes 4] [--n 1] [--arg --no-warm]
# The URL passes the headless flags as ?arg=... (web/shell.html hands them to
# the game; scripts/global.gd parses them like a headless client's).
# ==============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
URL="https://127.0.0.1:8443/index.html"; AI="chaser"; NAME=""; CLASS=""; MIN=4; N=1; EXTRA=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift ;;
    --ai) AI="$2"; shift ;;
    --name) NAME="$2"; shift ;;
    --class) CLASS="$2"; shift ;;
    --minutes) MIN="$2"; shift ;;
    --n) N="$2"; shift ;;
    --arg) EXTRA="$EXTRA&arg=$2"; shift ;;   # any other game flag, e.g. --arg --no-warm
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
NAME=${NAME:-Web$N}
mkdir -p .bots
LOG=".bots/web$N.log"
PROFILE="$(mktemp -d /tmp/tb-webbot-XXXX)"
Q="?arg=--autojoin&arg=--name=$NAME&arg=--ai=$AI"
[[ -n "$CLASS" ]] && Q="$Q&arg=--class=$CLASS"
Q="$Q$EXTRA"
echo "webbot $NAME -> $URL$Q (log $LOG, $MIN min)"
# The console lines come out of Chromium's stderr as: [...:INFO:CONSOLE:452] "text", source: ...
timeout "${MIN}m" chromium --headless=new --no-first-run --no-default-browser-check \
  --ignore-certificate-errors --user-data-dir="$PROFILE" --window-size=1280,720 \
  --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader \
  --autoplay-policy=no-user-gesture-required --enable-logging=stderr --v=0 \
  "$URL$Q" 2>&1 | grep --line-buffered -o 'CONSOLE:[0-9]*\] ".*", source' | sed -u 's/^CONSOLE:[0-9]*\] "//; s/", source$//' > "$LOG" || true
rm -rf "$PROFILE"
echo "webbot $NAME done: $(grep -c 'NetStats' "$LOG") NetStats lines, $(grep -c '\[Replay\]' "$LOG") Replay lines in $LOG"

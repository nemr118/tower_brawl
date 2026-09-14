#!/usr/bin/env bash
# Exports the benchmark page (bench/, branch bench/8p) to build/web/bench/ with a
# new pck name every time, so a phone never runs a cached old copy. The game's
# own server serves it at https://<host>:8443/bench/index.html.
#   tools/bench_export.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web/bench
godot --headless --path bench --import --quit-after 900 > /dev/null 2>&1 || true
godot --headless --path bench --export-release "Web" ../build/web/bench/index.html 2>&1 | grep -v '^Godot Engine' | tail -5
stamp=$(date +%Y%m%d%H%M%S)
cd build/web/bench
rm -f index_*.pck
mv index.pck "index_$stamp.pck"
# Godot 4.7 writes no mainPack key: add one after "executable" (as bump_build.sh does)
sed -i "s/\"executable\":\"index\"/\"executable\":\"index\",\"mainPack\":\"index_$stamp.pck\"/" index.html
sed -i "s/\"index\.pck\"/\"index_$stamp.pck\"/g" index.html
grep -o "\"mainPack\":\"[^\"]*\"" index.html || { echo "mainPack injection failed" >&2; exit 1; }
du -sh .

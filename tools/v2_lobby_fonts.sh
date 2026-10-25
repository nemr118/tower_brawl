#!/usr/bin/env bash
# The lobby's two fonts (2026-10-25): Noto Sans Condensed Black (the logo, the
# titles, the buttons) and Noto Sans Condensed Bold (names, tags, small lines),
# cut down to the letters the game uses (basic Latin, Latin-1, quotes, dashes,
# the dot and the arrows), so each is a few dozen KB instead of 640 KB.
# Noto Sans is under the SIL Open Font License 1.1 (bench/assets/fonts/OFL.txt).
# Needs the system's Noto fonts (Arch: noto-fonts) and pyftsubset (python-fonttools).
#   tools/v2_lobby_fonts.sh [OUT_DIR]   (default: bench/assets/fonts)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
OUT=${1:-bench/assets/fonts}
SRC=/usr/share/fonts/noto
U="U+0020-007E,U+00A0-00FF,U+2013-2014,U+2018-201F,U+2022,U+2026,U+2190-2193"
mkdir -p "$OUT"
for pair in "NotoSans-CondensedBlack:lobby_display" "NotoSans-CondensedBold:lobby_body"; do
  src="$SRC/${pair%%:*}.ttf"
  dst="$OUT/${pair##*:}.ttf"
  pyftsubset "$src" --unicodes="$U" --layout-features='kern,liga' --no-hinting --output-file="$dst"
  echo "$dst: $(stat -c %s "$dst") bytes"
done

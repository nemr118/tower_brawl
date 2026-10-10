#!/usr/bin/env bash
# ==============================================================================
# The new game's build (P1): check, bump, export, stamp the pck, patch page.
#
#   tools/v2_build.sh --title "Short Title"   bump the build number (v0.2.0-p1.N -> N+1),
#                                             check, export, name the pck, make the patch page
#   tools/v2_build.sh none                    re-export the CURRENT version (no bump, no page)
#
# The version lives in bench/sim/proto.gd (const VERSION := "v0.2.0-p1.N"), the
# one source: the server turns away a client with another version, and the pck is
# named after it, so a phone never runs a cached old copy (CLAUDE.md rule 2).
# The page lands in build/web/v2/ and the Python server (serve_game.py) serves it
# at https://<host>:8443/v2/ with no change: it already serves build/web.
# ==============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PROTO="bench/sim/proto.gd"
OUT="build/web/v2"
PRESET="Web v2"
NOTES_DIR="docs/Patch Notes"

BUMP="patch"; TITLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    none) BUMP="none" ;;
    --title) TITLE="$2"; shift ;;
    --title=*) TITLE="${1#--title=}" ;;
    -h|--help) sed -n '3,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

current=$(grep -oE 'const VERSION := "v[^"]+"' "$PROTO" | grep -oE 'v[0-9][^"]*')
[[ -n "$current" ]] || { echo "could not read VERSION from $PROTO" >&2; exit 1; }
if [[ "$BUMP" == "none" ]]; then
  NEW="$current"
else
  base="${current%.*}"; n="${current##*.}"
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "VERSION $current does not end in a build number" >&2; exit 1; }
  NEW="$base.$((n + 1))"
fi

echo "== [1/4] Check (every bench script compiles, every scene loads) =="
if ! out=$(godot --headless --path bench --script res://tools/check_scripts.gd 2>&1); then
  echo "$out" | grep -v '^Godot Engine' | grep -v 'leaked\|_free_rids\|cleanup (core' >&2
  echo "✗ Check FAILED. Version NOT bumped, nothing exported." >&2
  exit 1
fi
echo "$out" | grep 'check_scripts' || true

echo "== [2/4] Version $current -> $NEW =="
if [[ "$BUMP" != "none" ]]; then
  sed -i -E "s/(const VERSION := \")v[^\"]+\"/\1$NEW\"/" "$PROTO"
  grep -q "\"$NEW\"" "$PROTO" || { echo "✗ failed to write $NEW into $PROTO" >&2; exit 1; }
  existing=$(ls "$NOTES_DIR"/"$NEW - "*.md 2>/dev/null | head -1 || true)
  if [[ -z "$existing" ]]; then
    [[ -n "$TITLE" ]] || { TITLE="Untitled"; echo "⚠  no --title given: creating '$NEW - Untitled.md' (rename it and fix the Changelog link)" >&2; }
    prev_page=$(ls "$NOTES_DIR"/v*.md 2>/dev/null | sed 's#.*/##; s#\.md$##' | sort -V | tail -1)
    page="$NOTES_DIR/$NEW - $TITLE.md"
    title_esc=$(printf '%s' "$TITLE" | sed 's/[&/\]/\\&/g')
    prev_esc=$(printf '%s' "${prev_page:-Changelog}" | sed 's/[&/\]/\\&/g')
    sed -e "s/{VERSION}/$NEW/g" -e "s/{DATE}/$(date +%F)/g" -e "s/{TITLE}/$title_esc/g" \
        -e "s/{PHASE}/tbd/g" -e "s/{HARNESS}/the P1 proofs (no relay harness: the new server)/g" -e "s/{PREVIOUS}/$prev_esc/g" \
        docs/patch_note_template.md > "$page"
    sed -i "/<!-- bump_build.sh inserts new versions directly below this line -->/a - [[$NEW - $TITLE]] — $(date +%F) · tbd · P1 proofs tbd" docs/Changelog.md
    [[ -n "$prev_page" ]] && sed -i "s/^Previous: \(.*\) · Next: — /Previous: \1 · Next: [[$NEW - $title_esc]] /" "$NOTES_DIR/$prev_page.md"
    echo "📝 patch-notes page created: $page (fill in summary / changes / checked / metrics)"
  fi
fi

echo "== [3/4] Export preset '$PRESET' -> $OUT =="
mkdir -p "$OUT"
godot --headless --path bench --import --quit-after 900 > /dev/null 2>&1 || true
before=$(stat -c %y "$OUT/index.pck" 2>/dev/null || echo none)
set +e
godot --headless --path bench --export-release "$PRESET" "../$OUT/index.html" 2>&1 | grep -v '^Godot Engine' | grep -v 'leaked\|_free_rids\|cleanup (core' | tail -5
set -e
after=$(stat -c %y "$OUT/index.pck" 2>/dev/null || echo none)
[[ "$after" != "$before" && "$after" != none ]] \
  || { echo "✗ export did not write a new $OUT/index.pck" >&2; exit 1; }
grep -q 'id="fs-gate"' "$OUT/index.html" \
  || { echo "✗ $OUT/index.html has no phone helpers: check html/custom_html_shell in bench/export_presets.cfg (bench/web/shell.html links to web/shell.html)" >&2; exit 1; }

echo "== [4/4] Name the pck: index_$NEW.pck =="
rm -f "$OUT"/index_*.pck
mv "$OUT/index.pck" "$OUT/index_$NEW.pck"
# Godot 4.7 writes no mainPack key: add one after "executable" (as bump_build.sh does)
sed -i "s/\"executable\":\"index\"/\"executable\":\"index\",\"mainPack\":\"index_$NEW.pck\"/" "$OUT/index.html"
sed -i "s/\"index\.pck\"/\"index_$NEW.pck\"/g" "$OUT/index.html"
[[ "$(grep -c mainPack "$OUT/index.html")" == "1" ]] || { echo "✗ mainPack injection failed in $OUT/index.html" >&2; exit 1; }

ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
ip=${ip:-127.0.0.1}
cat <<MSG

✅ Build $NEW ready  ($OUT is $(du -sh "$OUT" | cut -f1))
   Phones and the PC  ->  https://$ip:8443/v2/   (the page; the Python service serves it)
   The game server    ->  godot --headless --path bench res://server/game_server.tscn   (wss on 8091, --no-tls for ws)
   A window on the PC ->  godot --path bench -- --server=wss://$ip:8091 --name=Dad
   Both sides must run $NEW: the server turns away any other version.
MSG

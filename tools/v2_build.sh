#!/usr/bin/env bash
# ==============================================================================
# The new game's build (P1): check, bump, export, stamp the pck, patch page.
#
#   tools/v2_build.sh --title "Short Title"   bump the build number (v0.2.0-p1.N -> N+1),
#                                             check, export, name the pck, make the patch page
#   tools/v2_build.sh --phase 2 --title "..." the first build of a phase: v0.2.0-p2.1
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

BUMP="patch"; TITLE=""; PHASE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    none) BUMP="none" ;;
    --title) TITLE="$2"; shift ;;
    --title=*) TITLE="${1#--title=}" ;;
    --phase) PHASE="$2"; shift ;;
    --phase=*) PHASE="${1#--phase=}" ;;
    -h|--help) sed -n '3,15p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

current=$(grep -oE 'const VERSION := "v[^"]+"' "$PROTO" | grep -oE 'v[0-9][^"]*')
[[ -n "$current" ]] || { echo "could not read VERSION from $PROTO" >&2; exit 1; }
if [[ "$BUMP" == "none" ]]; then
  NEW="$current"
elif [[ -n "$PHASE" ]]; then
  [[ "$PHASE" =~ ^[0-9]+$ ]] || { echo "--phase takes a number" >&2; exit 2; }
  NEW="${current%-p*}-p$PHASE.1"
  [[ "$NEW" != "$current" ]] || { echo "already at $NEW: drop --phase to bump the build number" >&2; exit 2; }
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

PH=$(printf '%s' "$NEW" | sed -E 's/.*-p([0-9]+)\..*/\1/')
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
        -e "s/{PHASE}/tbd/g" -e "s/{HARNESS}/the P$PH proofs (no relay harness: the new server)/g" -e "s/{PREVIOUS}/$prev_esc/g" \
        docs/patch_note_template.md > "$page"
    sed -i "/<!-- bump_build.sh inserts new versions directly below this line -->/a - [[$NEW - $TITLE]] — $(date +%F) · tbd · P$PH proofs tbd" docs/Changelog.md
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
# The GL number fix (the iPhone white screen, after p4.14). The web export's GL layer
# (emscripten, in index.js) gives every GL object a number from ONE counter that
# never goes back, and fills each table with empty slots up to that number. The game
# makes and frees about 200 GL objects a frame (buffers and vertex arrays for the
# shapes it draws), so the tables grew by megabytes a minute and never shrank, until
# an iPhone's page ran out of memory. The new getNewId hands out the lowest free number of that table (as a GL
# driver on a PC does), so a table is only as long as what is alive in it.
GETID_OLD='getNewId:table=>{var ret=GL.counter++;for(var i=table.length;i<ret;i++){table[i]=null}return ret}'
GETID_NEW='getNewId:table=>{var n=table.length,s=table.tbNext|0,i;if(s<1||s>n)s=1;for(i=s;i<n&&table[i]!=null;i++);if(i>=n){for(i=1;i<s&&table[i]!=null;i++);if(i>=s)i=n<1?1:n}for(var j=table.length;j<i;j++)table[j]=null;if(i>=table.length)table[i]=null;table.tbNext=i+1;if(i>=GL.counter)GL.counter=i+1;return i}'
python3 - "$OUT/index.js" "$GETID_OLD" "$GETID_NEW" <<'PY' \
  || { echo "✗ $OUT/index.js: emscripten's getNewId is not the one we patch (a new Godot?): see the GL number fix in tools/v2_build.sh" >&2; exit 1; }
import sys
path, old, new = sys.argv[1:]
text = open(path).read()
if text.count(old) != 1:
    sys.exit(1)
open(path, "w").write(text.replace(old, new))
PY
# p4.13: the Home Screen icon and manifest (an iPhone added to the Home Screen opens the game full screen)
cp bench/web/pwa/manifest.json bench/web/pwa/icon-180.png bench/web/pwa/icon-512.png "$OUT/"
cp bench/web/page/splash_castle.png "$OUT/"   # 2026-10-26: the loading picture outside the Halloween season (bench/web/shell.html)

ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
ip=${ip:-127.0.0.1}
cat <<MSG

✅ Build $NEW ready  ($OUT is $(du -sh "$OUT" | cut -f1))
   Phones and the PC  ->  https://$ip:8443/v2/   (the page; the Python service serves it)
   The game server    ->  godot --headless --path bench res://server/game_server.tscn   (wss on 8091, --no-tls for ws)
   A window on the PC ->  godot --path bench -- --server=wss://$ip:8091 --name=Dad
   Both sides must run $NEW: the server turns away any other version.
MSG

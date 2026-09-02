#!/usr/bin/env bash
# ==============================================================================
# Tower Brawl - compile-check, bump version, export web build, bust the cache.
#
#   ./bump_build.sh            patch bump  (v0.0.4 -> v0.0.5), check, export, version the pck
#   ./bump_build.sh minor      minor bump  (v0.0.5 -> v0.1.0)
#   ./bump_build.sh major      major bump
#   ./bump_build.sh none       re-export the CURRENT version (does NOT bust browser caches)
#   ./bump_build.sh --clean    also delete older index_v*.pck / .html copies (20 MB each)
#   ./bump_build.sh --title "Short Title"   name the patch-notes page for this version
#
# Why: Godot web exports are cached in the browser's IndexedDB keyed by the .pck
# file name. A new file name is the only reliable way to make phones load new
# code. The version string lives in scripts/global.gd (single source of truth);
# this script mirrors it into serve_game.py, names the pck after it, and patches
# the "mainPack" entry in the HTML loader config.
# ==============================================================================
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

GLOBAL_GD="scripts/global.gd"
SERVER_PY="serve_game.py"
BUILD_DIR="build/web"
EXPORT_PRESET="Web"

BUMP="patch"; CLEAN=0; TITLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    patch|minor|major|none) BUMP="$1" ;;
    --clean) CLEAN=1 ;;
    --title) TITLE="$2"; shift ;;
    --title=*) TITLE="${1#--title=}" ;;
    -h|--help) sed -n '3,16p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

current=$(grep -oE 'const GAME_VERSION: String = "v[0-9]+\.[0-9]+\.[0-9]+"' "$GLOBAL_GD" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
[[ -n "$current" ]] || { echo "could not read GAME_VERSION from $GLOBAL_GD" >&2; exit 1; }
IFS=. read -r MA MI PA <<< "$current"
case "$BUMP" in
  major) MA=$((MA+1)); MI=0; PA=0 ;;
  minor) MI=$((MI+1)); PA=0 ;;
  patch) PA=$((PA+1)) ;;
  none) ;;
esac
NEW="v$MA.$MI.$PA"

echo "== [1/4] Compile check (all scripts, autoloads live) =="
# --check-only cannot see autoloads (every script using Global "fails"), so we
# run a SceneTree script that loads everything after autoloads are registered.
if ! out=$(godot --headless --path . --script tools/check_scripts.gd -- --no-net 2>&1); then
  echo "$out" | grep -v '^Godot Engine' >&2
  echo "✗ Compile check FAILED. Version NOT bumped, nothing exported." >&2
  exit 1
fi
echo "$out" | grep 'check_scripts' || true

echo "== [2/4] Version v$current -> $NEW =="
if [[ "$BUMP" != "none" ]]; then
  sed -i -E "s/(const GAME_VERSION: String = \")v[0-9.]+\"/\1$NEW\"/" "$GLOBAL_GD"
  sed -i -E "s/^(GAME_VERSION = \")v[0-9.]+\"/\1$NEW\"/" "$SERVER_PY"
  grep -q "\"$NEW\"" "$GLOBAL_GD" && grep -q "\"$NEW\"" "$SERVER_PY" \
    || { echo "✗ failed to write $NEW into $GLOBAL_GD / $SERVER_PY" >&2; exit 1; }
fi

# Patch-notes page (docs/Patch Notes/<version> - <title>.md) + Changelog link. CLAUDE.md rule 5.
NOTES_DIR="docs/Patch Notes"
if [[ "$BUMP" != "none" ]]; then
  existing=$(ls "$NOTES_DIR"/"$NEW - "*.md 2>/dev/null | head -1 || true)
  if [[ -z "$existing" ]]; then
    [[ -n "$TITLE" ]] || { TITLE="Untitled"; echo "⚠  no --title given: creating '$NEW - Untitled.md' (rename it and fix the Changelog link)" >&2; }
    prev_page=$(ls "$NOTES_DIR"/v*.md 2>/dev/null | sed 's#.*/##; s#\.md$##' | sort -V | tail -1)
    page="$NOTES_DIR/$NEW - $TITLE.md"
    sed -e "s/{VERSION}/$NEW/g" -e "s/{DATE}/$(date +%F)/g" -e "s/{TITLE}/$TITLE/g" \
        -e "s/{PHASE}/tbd/g" -e "s/{HARNESS}/tbd/g" -e "s/{PREVIOUS}/${prev_page:-Changelog}/g" \
        docs/patch_note_template.md > "$page"
    sed -i "/<!-- bump_build.sh inserts new versions directly below this line -->/a - [[$NEW - $TITLE]] — $(date +%F) · tbd · harness tbd" docs/Changelog.md
    [[ -n "$prev_page" ]] && sed -i "s/^Previous: \(.*\) · Next: — /Previous: \1 · Next: [[$NEW - $TITLE]] /" "$NOTES_DIR/$prev_page.md"
    echo "📝 patch-notes page created: $page (fill in summary / changes / metrics / harness)"
  fi
fi

echo "== [3/4] Export preset '$EXPORT_PRESET' -> $BUILD_DIR =="
mkdir -p "$BUILD_DIR"
before=$(stat -c %y "$BUILD_DIR/index.pck" 2>/dev/null || echo none)
set +e
godot --headless --path . --export-release "$EXPORT_PRESET" "$BUILD_DIR/index.html" 2>&1 | grep -v '^Godot Engine'
set -e
after=$(stat -c %y "$BUILD_DIR/index.pck" 2>/dev/null || echo none)
[[ "$after" != "$before" && "$after" != none ]] \
  || { echo "✗ export did not write a new $BUILD_DIR/index.pck" >&2; exit 1; }

echo "== [4/4] Cache-bust: index_$NEW.pck =="
cp "$BUILD_DIR/index.pck"  "$BUILD_DIR/index_$NEW.pck"
cp "$BUILD_DIR/index.html" "$BUILD_DIR/index_$NEW.html"
# Patch both the versioned copy and the plain index.html, so the root URL also
# loads the new pck (the HTML itself is served with Cache-Control: no-store).
for html in "$BUILD_DIR/index_$NEW.html" "$BUILD_DIR/index.html"; do
  sed -i "s/\"executable\":\"index\"/\"executable\":\"index\",\"mainPack\":\"index_$NEW.pck\"/" "$html"
  sed -i "s/\"index\.pck\"/\"index_$NEW.pck\"/g" "$html"
  [[ "$(grep -c mainPack "$html")" == "1" ]] \
    || { echo "✗ mainPack injection failed in $html" >&2; exit 1; }
done

if [[ $CLEAN -eq 1 ]]; then
  echo "-- cleaning older versioned builds --"
  find "$BUILD_DIR" -maxdepth 1 -name 'index_v*' ! -name "index_$NEW.*" -print -delete
fi

ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
ip=${ip:-127.0.0.1}
size=$(du -sh "$BUILD_DIR" | cut -f1)
cat <<MSG

✅ Build $NEW ready  ($BUILD_DIR is $size)
   PC       ->  http://$ip:8000/index_$NEW.html
   Phones   ->  https://$ip:8443/index_$NEW.html
   (plain /index.html now also points at index_$NEW.pck)
   Server: serve_game.py re-reads the version from $GLOBAL_GD on every join,
           so no restart is needed unless serve_game.py itself changed.
MSG

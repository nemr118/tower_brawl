#!/usr/bin/env bash
# One ComfyUI batch on this PC's card, as a good neighbour (2026-10-26). It waits until no
# other card job runs (the user units in TB_WAIT_UNITS gone, the card under TB_VRAM_FREE_MIB in
# use), takes the PC's shared card lock (/tmp/sr6_pc_gpu.lock, the SR6 jobs' lock), starts
# ComfyUI the safe way (vam_restyle's tools/comfy.sh: a 0.50 cap, a watchdog on the whole
# card), runs the job scripts one after another, and stops ComfyUI. The log is
# $TB_COMFY_OUT/batch.log; its last line is "BATCH DONE" or "BATCH FAILED: why".
#   TB_WAIT_UNITS="other.service" tools/comfy/batch.sh run_cards.py run_splash.py ...
# Start it as a user service so it outlives the shell:
#   systemd-run --user --unit=tb-comfy --collect env TB_WAIT_UNITS=... bash tools/comfy/batch.sh ...
set -u
cd "$(dirname "$0")"
OUT="${TB_COMFY_OUT:-$HOME/.cache/tower-brawl-comfy}"
mkdir -p "$OUT"
LOG="$OUT/batch.log"
FREE_MIB="${TB_VRAM_FREE_MIB:-3200}"
WAIT_S="${TB_WAIT_S:-14400}"
VR="$HOME/Work/vam_restyle"
F=$(ls /sys/class/drm/card*/device/mem_info_vram_used | head -1)
say() { echo "$(date +%T) $*" | tee -a "$LOG"; }
vram_mib() { echo $(( $(cat "$F") / 1048576 )); }
busy() {
  for u in ${TB_WAIT_UNITS:-}; do
    systemctl --user is-active --quiet "$u" && { echo "$u is running"; return 0; }
  done
  [ "$(vram_mib)" -ge "$FREE_MIB" ] && { echo "the card has $(vram_mib) MiB in use"; return 0; }
  return 1
}
fail() { say "BATCH FAILED: $*"; exit 1; }

say "batch: $*"
deadline=$(( $(date +%s) + WAIT_S ))
while why=$(busy); do
  [ "$(date +%s)" -ge "$deadline" ] && fail "still busy after ${WAIT_S} s ($why)"
  [ "${last_why:-}" != "$why" ] && say "waiting: $why"
  last_why=$why
  sleep 20
done
exec 9>/tmp/sr6_pc_gpu.lock
say "taking the card lock"
flock -w 3600 9 || fail "the card lock stayed taken for an hour"
why=$(busy) && fail "busy again after the lock ($why)"
say "the card: $(vram_mib) MiB in use; starting ComfyUI"
stop_comfy() { (cd "$VR" && tools/comfy.sh stop >> "$LOG" 2>&1); say "ComfyUI stopped"; }
trap stop_comfy EXIT
(cd "$VR" && systemd-run --user --scope -q -p MemoryMax=30G env VR_COMFY_ROOT="$HOME/ComfyUI" \
  VR_COMFY_PY="$HOME/ComfyUI/venv-py312/bin/python" VR_VRAM_FRACTION=0.50 VR_FP8=1 VR_COMFY_EXTRA="" \
  tools/comfy.sh start) >> "$LOG" 2>&1 || fail "ComfyUI did not start"
for s in "$@"; do
  say "== $s"
  python3 -u "$s" >> "$LOG" 2>&1 || fail "$s stopped with an error"
  (cd "$VR" && tools/comfy.sh status) | grep -q running || fail "ComfyUI is gone (the watchdog?): see $HOME/.cache/vam_restyle or the log"
done
say "BATCH DONE"

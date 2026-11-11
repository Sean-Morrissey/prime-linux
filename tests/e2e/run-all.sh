#!/usr/bin/env bash
# prime-e2e — run every layer of the desktop test suite and print one verdict.
#
#   bash run-all.sh              all layers
#   bash run-all.sh --fast       skip journeys (no windows opened, ~20 s)
#   bash run-all.sh --layer 2    one layer
#
# Layers, cheapest first:
#   1 structural  the desktop is assembled correctly (services, config, bar json,
#                 menus resolve, doctor green) — fails fast, never opens a window
#   2 contracts   invariants that have broken before: notifications must carry
#                 actions, contrast computed from the real CSS, text scale must
#                 reach every surface, shipped tree clean, no portability leaks
#   3 journeys    act like a person: open the typing box, open menus, load the
#                 board, minimise and restore, and assert latency budgets
#
# Layers 1 and 2 are read-only. Layer 3 opens and closes its own windows and
# cleans up after itself even when it fails.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FAST=0; ONLY=""; ALLOW_LIVE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --fast) FAST=1; shift ;;
    --layer) ONLY="${2:-}"; shift 2 ;;
    --allow-live) ALLOW_LIVE=1; shift ;;   # journeys open windows — only on a machine nobody is using
    *) shift ;;
  esac
done

# Journeys open and close real windows, menus and a browser. On the machine
# somebody is working on, that is rude even when it cleans up. Refuse unless the
# caller says the session is disposable (a VM) or explicitly allows it.
if [ "$FAST" = 0 ] && [ "$ALLOW_LIVE" = 0 ] && [ "${PRIME_E2E_VM:-0}" != "1" ]; then
  echo "refusing to run journeys on the live desktop."
  echo "  run inside the test VM (PRIME_E2E_VM=1) or pass --allow-live when the screen is yours."
  echo "  the read-only layers still run: bash run-all.sh --fast"
  FAST=1
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && [ -d "$XDG_RUNTIME_DIR/hypr" ]; then
  HYPRLAND_INSTANCE_SIGNATURE="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"
  export HYPRLAND_INSTANCE_SIGNATURE
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$HERE/results/$STAMP"
mkdir -p "$OUT"

declare -a NAMES=("structural" "contracts" "journeys")
declare -a CODES=()
declare -a TIMES=()

run_layer() {
  local n="$1" script="$2"
  [ -n "$ONLY" ] && [ "$ONLY" != "$n" ] && return
  if [ ! -f "$script" ]; then
    printf 'SKIP %-12s %s not built yet\n' "$n" "$(basename "$script")"
    return
  fi
  printf '\n\033[1m── %s ────────────────────────────────────────────────\033[0m\n' "$n"
  local t0 t1
  t0=$(date +%s%N)
  bash "$script" 2>&1 | tee "$OUT/$n.log"
  local rc=${PIPESTATUS[0]}
  t1=$(date +%s%N)
  CODES+=("$rc")
  TIMES+=("$(( (t1 - t0) / 1000000 ))")
}

run_layer structural "$HERE/structural.sh"
run_layer contracts  "$HERE/contracts.sh"
[ "$FAST" = 1 ] || run_layer journeys "$HERE/journeys.sh"

echo
echo "══════════════════════════ PRIME E2E ══════════════════════════"
FAILED=0
for i in "${!CODES[@]}"; do
  if [ "${CODES[$i]}" -eq 0 ]; then s="PASS"; else s="FAIL"; FAILED=1; fi
  printf '%-5s %-12s %6s ms\n' "$s" "${NAMES[$i]}" "${TIMES[$i]}"
done
if [ -d "$HERE/results/$STAMP" ]; then
  echo "results: $OUT"
fi
echo "═══════════════════════════════════════════════════════════════"

# A run that never executed a layer is not a pass.
if [ "${#CODES[@]}" -eq 0 ]; then
  echo "VERDICT: NOTHING RAN (exit 2)"
  exit 2
fi
[ "$FAILED" -eq 0 ] && echo "VERDICT: PASS" || echo "VERDICT: FAIL"
exit "$FAILED"

#!/usr/bin/env bash
# Run the Prime e2e suite inside the test VM and bring the results back.
#
#   bash run-suite.sh          structural + contracts + journeys (opens windows
#                              inside the VM, never on the host)
#   bash run-suite.sh --fast   read-only layers only
#
# The VM has no host window: Hyprland is started on tty1 using virtio-vga-gl +
# egl-headless + VNC connector, so journeys drive a real compositor with real
# windows — just not one anybody is looking at on the host screen.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VM_DIR="${PRIME_VM_DIR:-$HOME/VMs/prime}"
[ -f "$SCRIPT_DIR/id_ed25519" ] && VM_DIR="$SCRIPT_DIR"
cd "$VM_DIR"

FAST="${1:-}"
LOG="$VM_DIR/vm-suite.log"
SSH=(ssh -F /dev/null -o ServerAliveInterval=15 -o ServerAliveCountMax=4 -i "$VM_DIR/id_ed25519" -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes sean@127.0.0.1)

say() { printf '%s %s\n' "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }

say "checking the VM is reachable"
"${SSH[@]}" 'echo ok' >/dev/null || { say "VM not reachable — start it with start-vm.sh"; exit 1; }

say "ensuring a Hyprland session exists on Virtual-1 (headless)"
set +e
"${SSH[@]}" 'bash -s' <<'REMOTE' >>"$LOG" 2>&1
set -u
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
systemctl --user set-environment PATH="$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin" 2>/dev/null || true

# Clean stale hypr socket dirs; if hyprlock ever locked the session or Hyprland
# has non-zero CapEff (which breaks bwrap/glycin-svg), restart prime-vm-hypr cleanly.
for d in "$XDG_RUNTIME_DIR"/hypr/*; do
  [ -d "$d" ] || continue
  sig="$(basename "$d")"
  hpid="$(pgrep -x Hyprland | head -1)"
  cap_eff="$(awk '/^CapEff:/{print $2}' "/proc/${hpid:-0}/status" 2>/dev/null || echo "")"
  if HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors -j >/dev/null 2>&1 \
     && ! pgrep -x hyprlock >/dev/null \
     && [ "$cap_eff" = "0000000000000000" ]; then
    echo "Hyprland already running cleanly ($sig)"
    pkill -x hypridle 2>/dev/null || true
    S="prime""-screensaver"; pkill -f "$S" 2>/dev/null || true
    HYPRLAND_INSTANCE_SIGNATURE="$sig" ~/.local/share/prime-linux/layer/bin/prime-hypr dispatch dpms on 2>/dev/null || true
    exit 0
  else
    rm -rf "$d"
  fi
done

# Release tty1 DRM master from sddm / getty and start Hyprland on seat0 tty1
# Do NOT pass --config hyprland.conf: Hyprland 0.57+ treats --config as a Lua
# file; default startup reads ~/.config/hypr/hyprland.lua which loads legacy conf.
# Drop ambient/bounding capabilities so bwrap (glycin-svg in GTK3) never fails.
sudo systemctl stop sddm.service getty@tty1.service prime-vm-hypr.service 2>/dev/null || true
sudo systemctl reset-failed prime-vm-hypr.service 2>/dev/null || true
rm -rf "$XDG_RUNTIME_DIR"/hypr/*
sudo systemd-run --unit=prime-vm-hypr --uid=sean --gid=sean \
  -p PAMName=login -p TTYPath=/dev/tty1 -p StandardInput=tty \
  -p CapabilityBoundingSet= -p AmbientCapabilities= \
  -E XDG_RUNTIME_DIR=/run/user/1000 \
  -E DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus \
  -E PATH=/home/sean/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/bin \
  -E XDG_SESSION_TYPE=wayland \
  -E XDG_SESSION_CLASS=user \
  -E XDG_SEAT=seat0 \
  -E XDG_VTNR=1 \
  -E AQ_NO_MODIFIERS=1 \
  /usr/bin/Hyprland >/tmp/hyprland-launch.log 2>&1

for i in $(seq 1 20); do
  sig="$(ls -t "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)"
  if [ -n "$sig" ] && HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl monitors -j >/dev/null 2>&1; then
    echo "Hyprland up ($sig)"
    pkill -x hypridle 2>/dev/null || true
    for j in $(seq 1 15); do
      systemctl --user is-active prime-bar@top.service >/dev/null 2>&1 && break
      sleep 0.5
    done
    pkill -x hypridle 2>/dev/null || true
    S="prime""-screensaver"; pkill -f "$S" 2>/dev/null || true
    # Close first-run Welcome window if present so the test desktop starts empty
    for a in $(HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class=="org.primelinux.Welcome") | .address'); do
      HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl dispatch "hl.dsp.window.close({ window = \"address:$a\" })" >/dev/null 2>&1 || true
    done
    HYPRLAND_INSTANCE_SIGNATURE="$sig" ~/.local/share/prime-linux/layer/bin/prime-hypr dispatch dpms on 2>/dev/null || true
    sleep 1
    exit 0
  fi
  sleep 1
done
echo "Hyprland did not come up:"
sudo journalctl -u prime-vm-hypr -n 40 --no-pager
exit 1
REMOTE
HYPR_RC=$?
set -e
if [ "$HYPR_RC" -ne 0 ]; then
  if [ "$FAST" = "--fast" ]; then
    say "Hyprland unavailable in guest — continuing with --fast (contracts/structural)"
  else
    say "Hyprland unavailable in guest — cannot run journeys"; exit 1
  fi
fi

SUITE_CMD='export PRIME_E2E_VM=1 XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$XDG_RUNTIME_DIR"/hypr 2>/dev/null | head -1)
cd ~/prime-linux/tests/e2e && bash run-all.sh '"$FAST"''

say "running the suite inside the VM"
set +e
"${SSH[@]}" "$SUITE_CMD" 2>&1 | tee -a "$LOG"
RC=${PIPESTATUS[0]}
set -e

say "fetching results"
mkdir -p "$VM_DIR/vm-results"
"${SSH[@]}" 'tar -C /home/sean/prime-linux/tests/e2e/results -cf - .' 2>>"$LOG" \
  | tar -C "$VM_DIR/vm-results" -xf - 2>>"$LOG" || true

say "suite exit $RC — results in $VM_DIR/vm-results"
exit "$RC"

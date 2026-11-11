#!/usr/bin/env bash
# Start the throwaway Prime test VM. Nothing here touches the host desktop.
#
#   bash start-vm.sh          boot headless (VirGL egl-headless + VNC 127.0.0.1:5901 + ssh 127.0.0.1:2222)
#   bash start-vm.sh --gui    same VM with a GTK window, when you want to watch it
#
# The disk is an overlay on the pristine Arch cloud image, so `rm disk.qcow2` and
# re-running gives a clean machine in seconds.
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VM_DIR="${PRIME_VM_DIR:-$HOME/VMs/prime}"
[ -f "$SCRIPT_DIR/arch-cloud.qcow2" ] && VM_DIR="$SCRIPT_DIR"
cd "$VM_DIR"

GUI=0; [ "${1:-}" = "--gui" ] && GUI=1

[ -f arch-cloud.qcow2 ] || { echo "arch-cloud.qcow2 missing in $VM_DIR — download it first"; exit 1; }
[ -f seed.iso ] || bash "$SCRIPT_DIR/build-seed.sh"

if [ ! -f disk.qcow2 ]; then
  qemu-img create -f qcow2 -F qcow2 -b arch-cloud.qcow2 disk.qcow2 40G >/dev/null
  echo "created disk.qcow2 (40G overlay)"
fi

# resize the filesystem on first boot so the overlay's extra space is usable
if [ ! -f .resized ]; then
  qemu-img resize disk.qcow2 40G >/dev/null 2>&1 || true
  touch .resized
fi

ACCEL="-enable-kvm -cpu host"
[ -r /dev/kvm ] || ACCEL="-cpu max"      # TCG fallback: slow but works

# Hyprland 0.57+ (Aquamarine DRM backend) requires BOTH:
#   1. A DRM render node (/dev/dri/renderD128) capable of GBM buffer allocation
#      -> provided by `-vga none -device virtio-vga-gl` + `-display egl-headless`
#   2. A connected display output (Virtual-1)
#      -> attached by `-vnc 127.0.0.1:5901` without opening any window on the host
RENDER_NODE="/dev/dri/renderD128"
EGL_OPTS="egl-headless"
[ -r "$RENDER_NODE" ] && EGL_OPTS="egl-headless,rendernode=$RENDER_NODE"

if [ "$GUI" = 1 ]; then
  VIDEO="-vga none -device virtio-vga-gl -display gtk,gl=on"
else
  VIDEO="-vga none -device virtio-vga-gl -display $EGL_OPTS -vnc 127.0.0.1:5901"
fi

qemu-system-x86_64 \
  $ACCEL -machine q35 -smp 4 -m 8192 \
  -drive file=disk.qcow2,if=virtio,cache=writeback \
  -drive file=seed.iso,media=cdrom,readonly=on \
  -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22 \
  -device virtio-net-pci,netdev=n0 \
  $VIDEO \
  -device virtio-keyboard-pci -device virtio-mouse-pci \
  -device qemu-xhci -device usb-tablet \
  -serial file:serial.log \
  -pidfile vm.pid -daemonize

echo "vm started (pid $(cat vm.pid)); ssh -i $VM_DIR/id_ed25519 -p 2222 sean@127.0.0.1"

#!/usr/bin/env bash
# Boot the CI-built Prime Linux in a VM.
#
# The point of this: nobody should need podman, the bluebuild CLI or sudo on their own
# machine to see the real thing. CI builds the image and the disk; this fetches the
# disk and boots it. Nothing here touches the host beyond writing a qcow2 into .vm/.
#
#   tools/vm-boot.sh fetch [run-id]   download the newest qcow2 (default: latest good run)
#   tools/vm-boot.sh boot             start it (KVM, UEFI, virtio, host :2222 -> guest :22)
#   tools/vm-boot.sh status           what is on disk, what is running
#   tools/vm-boot.sh rm               delete the VM disk (start clean next time)
#
# Inside the VM: log in as prime / prime, then
#   prime-setup          answer the questions
#   prime status         the supervisor
#   prime-autoupdate status
# The update timer fires 15 minutes after boot, so leaving it running is a real test
# of the unattended cycle against the real bootc backend.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VM_DIR="$ROOT/.vm"
DISK="$VM_DIR/prime-linux.qcow2"
VARS="$VM_DIR/OVMF_VARS.fd"
WORKFLOW="build-disk.yml"
ARTIFACT="prime-linux-qcow2"

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_bad=$'\033[31m'; c_dim=$'\033[2m'; c_b=$'\033[1m'
say() { printf '%s\n' "$*"; }
ok()  { printf '  %s✓%s %s\n' "$c_ok" "$c_reset" "$*"; }
bad() { printf '  %s✗%s %s\n' "$c_bad" "$c_reset" "$*"; }
dim() { printf '%s%s%s\n' "$c_dim" "$*" "$c_reset"; }

# UEFI firmware: an image-based Fedora boots UEFI; SeaBIOS is not enough.
find_ovmf() {
  local code="" vars=""
  for c in /usr/share/edk2/x64/OVMF_CODE.4m.fd \
           /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd \
           /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
           /usr/share/OVMF/OVMF_CODE.fd \
           /usr/share/edk2/ovmf/OVMF_CODE.fd; do
    [ -r "$c" ] && { code="$c"; break; }
  done
  for v in /usr/share/edk2/x64/OVMF_VARS.4m.fd \
           /usr/share/edk2-ovmf/x64/OVMF_VARS.fd \
           /usr/share/OVMF/OVMF_VARS.fd \
           /usr/share/edk2/ovmf/OVMF_VARS.fd; do
    [ -r "$v" ] && { vars="$v"; break; }
  done
  [ -n "$code" ] && [ -n "$vars" ] || return 1
  printf '%s\n%s\n' "$code" "$vars"
}

cmd_fetch() {
  mkdir -p "$VM_DIR"
  local run="${1:-}"
  if [ -z "$run" ]; then
    run="$(gh run list --workflow="$WORKFLOW" --status success --limit 1 \
             --json databaseId -q '.[0].databaseId' 2>/dev/null || true)"
  fi
  if [ -z "$run" ] || [ "$run" = "null" ]; then
    bad "no successful '$WORKFLOW' run to download from"
    dim "    start one:  gh workflow run $WORKFLOW --ref main -f platform=amd64"
    dim "    then:       tools/vm-boot.sh fetch"
    return 1
  fi
  say "  downloading $ARTIFACT from run $run ..."
  rm -rf "$VM_DIR/download" && mkdir -p "$VM_DIR/download"
  if ! gh run download "$run" -n "$ARTIFACT" -D "$VM_DIR/download"; then
    bad "could not download the artifact"
    dim "    see what it produced:  gh run view $run"
    return 1
  fi
  local found
  found="$(find "$VM_DIR/download" -name '*.qcow2' -type f | head -1)"
  [ -n "$found" ] || { bad "the artifact had no .qcow2 in it"; return 1; }
  mv "$found" "$DISK"
  rm -rf "$VM_DIR/download"
  ok "disk: $DISK ($(du -h "$DISK" | cut -f1))"
  ok "from run $run"
}

cmd_boot() {
  [ -s "$DISK" ] || { bad "no disk yet — run: tools/vm-boot.sh fetch"; return 1; }
  command -v qemu-system-x86_64 >/dev/null 2>&1 || { bad "QEMU is not installed"; return 1; }
  local fw; fw="$(find_ovmf)" || { bad "no UEFI firmware found (install edk2-ovmf)"; return 1; }
  local code vars_in
  code="$(printf '%s' "$fw" | head -1)"; vars_in="$(printf '%s' "$fw" | tail -1)"
  [ -s "$VARS" ] || cp "$vars_in" "$VARS"
  local accel="tcg"; [ -w /dev/kvm ] && accel="kvm"

  # The disk is UEFI-only, so firmware is passed as two pflash drives: the code
  # read-only, and a writable copy of the variables (a shared read-only vars file
  # makes the guest forget its boot entries between runs).
  #
  # Defaults are deliberately the boring ones that work everywhere: plain virtio-vga
  # with no GL, no audio. A first boot that errors out on a display backend teaches
  # nobody anything. PRIME_VM_GL=1 and PRIME_VM_AUDIO=1 opt into the nicer ones.
  local -a args=(
    -name "Prime Linux"
    -accel "$accel"
    -machine q35
    -m "${PRIME_VM_MEM:-4096}" -smp "${PRIME_VM_CPUS:-4}"
    -drive "if=pflash,format=raw,readonly=on,file=$code"
    -drive "if=pflash,format=raw,file=$VARS"
    -drive "file=$DISK,if=virtio,format=qcow2"
    -device qemu-xhci -device usb-tablet
    -netdev user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22
    -device virtio-net-pci,netdev=n0
  )
  if [ "${PRIME_VM_GL:-0}" = "1" ]; then
    args+=(-device virtio-vga-gl -display gtk,gl=on,show-cursor=on)
  else
    args+=(-device virtio-vga -display gtk,show-cursor=on)
  fi
  if [ "${PRIME_VM_AUDIO:-0}" = "1" ]; then
    args+=(-device intel-hda -device hda-duplex -audiodev pipewire,id=snd0)
  fi

  say "${c_b}Prime Linux${c_reset} ${c_dim}(accel: $accel)${c_reset}"
  dim "  login: prime / prime      ssh from the host: ssh -p 2222 prime@localhost"
  dim "  in the guest: prime-setup, then leave it running — the update timer fires at 15 min"
  say
  exec qemu-system-x86_64 "${args[@]}"
}

cmd_status() {
  say "${c_b}Prime VM${c_reset}"
  if [ -s "$DISK" ]; then ok "disk present: $DISK ($(du -h "$DISK" | cut -f1))"
  else dim "  no disk yet (tools/vm-boot.sh fetch)"; fi
  local running
  running="$(pgrep -af 'qemu-system-x86_64.*Prime Linux' | head -3)"
  if [ -n "$running" ]; then ok "running:"; printf '    %s\n' "$running"; else dim "  not running"; fi
  say "  newest disk runs:"
  gh run list --workflow="$WORKFLOW" --limit 3 2>/dev/null | sed 's/^/    /' || true
}

cmd_rm() { rm -f "$DISK" "$VARS"; ok "removed the VM disk (the next boot starts fresh)"; }

case "${1:-}" in
  fetch)  shift || true; cmd_fetch "${1:-}" ;;
  boot)   cmd_boot ;;
  status) cmd_status ;;
  rm)     cmd_rm ;;
  -h|--help|"") sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//' ;;
  *)      say "unknown command: $1 (try: fetch | boot | status | rm)"; exit 2 ;;
esac

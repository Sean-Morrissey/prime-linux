#!/usr/bin/env bash
# Prime supervisor — real btrfs backend for Arch-family machines (CachyOS, Arch,
# EndeavourOS, Manjaro). This is the one that touches a real computer.
#
# It refuses to do anything unless PRIME_ALLOW_REAL_SYSTEM_CHANGES=yes, because the
# first thing a supervisor must not do is surprise its owner. Read-only verbs
# (status, updates, listing rollback points) are always allowed.
#
# Model: rollback points are read-only btrfs snapshots of the root subvolume,
# stored on a *separate* subvolume so they survive the thing they protect against.
# A snapshot of /@ living inside /@ is not a backup, it is a keepsake.
#
#   PRIME_SNAPSHOT_ROOT   where snapshots live (must NOT be inside / usually)
#   PRIME_ROOT_SUBVOL     the root subvolume path as seen from the top level
#
# Status today: read-only verbs implemented and safe. Snapshot/restore are
# implemented but UNPROVEN — they have never been run on a real machine, and they
# require the snapshot subvolume to be set up first (see docs/ARCHITECTURE.md §9).
# Honest default: refuse.

real_guard() {
  if [ "${PRIME_ALLOW_REAL_SYSTEM_CHANGES:-no}" != "yes" ]; then
    bad "this backend is not allowed to change this machine"
    dim  "  it needs PRIME_ALLOW_REAL_SYSTEM_CHANGES=yes, set by a human, on purpose"
    dim  "  read-only commands (status, updates, rollbacks) still work"
    exit 3
  fi
}

require_root() {
  [ "$(id -u)" = "0" ] || { bad "this needs root (snapshots live outside your home)"; exit 4; }
}

# ---------------------------------------------------------------- backend API
backend_status() {
  local fs; fs="$(findmnt -no FSTYPE / 2>/dev/null)"
  say "  machine:  $(uname -sr)"
  say "  root fs:  $fs ${c_dim}($(findmnt -no SOURCE / 2>/dev/null))${c_reset}"
  if [ "$fs" != "btrfs" ]; then
    bad "root is not btrfs — snapshots are not available on this machine"
    dim "  (rollback would need a different backend; the supervisor still runs checks)"
  else
    ok "root is btrfs — snapshot-based rollback is possible"
  fi
  say "  bootloader: $(real_bootloader)"
  say "  snapshots:  $(backend_snapshot_count)"
}

real_bootloader() {
  if [ -e /boot/limine.conf ] || [ -e /boot/efi/limine.conf ]; then echo "limine"
  elif [ -d /boot/grub ] || [ -d /boot/grub2 ]; then echo "grub"
  elif [ -d /boot/loader/entries ]; then echo "systemd-boot"
  else echo "unknown"; fi
}

backend_update_count() {
  command -v checkupdates >/dev/null 2>&1 || { echo 0; return; }
  checkupdates 2>/dev/null | wc -l | tr -d ' '
}

backend_updates() {
  command -v checkupdates >/dev/null 2>&1 || { dim "  (checkupdates unavailable)"; return; }
  local out; out="$(checkupdates 2>/dev/null)"
  if [ -z "$out" ]; then dim "  (nothing pending)"; return; fi
  local n; n="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
  say "  $n package(s) ready to install"
  printf '%s\n' "$out" | head -15 | sed 's/^/    /'
  [ "$n" -gt 15 ] && dim "    ... and $((n-15)) more"
}

backend_snapshot() { # backend_snapshot <label>
  real_guard; require_root
  local label="${1:-manual}"
  local root="${PRIME_SNAPSHOT_ROOT:-}"
  [ -n "$root" ] || { bad "PRIME_SNAPSHOT_ROOT is not set"; return 1; }
  case "$root" in /@*|/) bad "refusing: snapshot root '$root' lives inside the subvolume it protects"; return 1 ;; esac
  local subvol="${PRIME_ROOT_SUBVOL:-@}" id
  id="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "$root/$id" 2>/dev/null
  btrfs subvolume snapshot -r "$root/../$subvol" "$root/$id/$subvol" >/dev/null 2>&1 || {
    bad "btrfs snapshot failed"; return 1; }
  printf '%s\n' "$label" > "$root/$id/label"
  printf '%s\n' "$id"
}

backend_snapshot_count() {
  local root="${PRIME_SNAPSHOT_ROOT:-}"
  [ -n "$root" ] && [ -d "$root" ] || { echo 0; return; }
  find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

backend_snapshots() {
  local root="${PRIME_SNAPSHOT_ROOT:-}"
  [ -n "$root" ] && [ -d "$root" ] || { dim "  (no snapshot location configured)"; return; }
  local found=0
  for d in $(find "$root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r); do
    found=1
    printf '  %s  %-12s\n' "$(basename "$d")" "$(cat "$d/label" 2>/dev/null)"
  done
  [ "$found" = "1" ] || dim "  (no rollback points yet)"
}

backend_apply_updates() {
  real_guard; require_root
  # pacman is synchronous here: no image rebuild, no reboot to take effect
  pacman -Syu --noconfirm
}

backend_restore() { # backend_restore <id>  — the dangerous one
  real_guard; require_root
  bad "restore is not wired up yet on purpose"
  dim "  restoring means swapping the root subvolume and rebooting; getting it wrong"
  dim "  costs the machine. It needs the snapshot subvolume set up and one supervised"
  dim "  rehearsal on a throwaway VM before it is allowed anywhere near a daily driver."
  return 1
}

backend_health() {
  # reuse the same probe the interview uses; no model call, no network needed
  local probe="$SELF_DIR/../../files/system/usr/libexec/prime/hw-probe.sh"
  if [ -r "$probe" ]; then
    bash "$probe" 2>/dev/null | python3 -c '
import json,sys
try: d=json.load(sys.stdin)
except Exception: sys.exit(0)
for c in d.get("checks", []):
    print(f"{c[\"id\"]}\t{1 if c.get(\"ok\") else 0}\t{c.get(\"label\",\"\")}")' 2>/dev/null
  else
    printf 'probe\t0\thardware probe not found\n'
  fi
  # the checks that matter after an update and that a hardware probe cannot see
  if systemctl --user is-active graphical-session.target >/dev/null 2>&1; then
    printf 'session\t1\tDesktop session started cleanly\n'
  else
    printf 'session\t0\tDesktop session is not running\n'
  fi
}

backend_health_snapshot() {
  printf '{"ts":"%s","kernel":"%s","pending":%s}\n' \
    "$(date -u +%FT%TZ)" "$(uname -r)" "$(backend_update_count)"
}

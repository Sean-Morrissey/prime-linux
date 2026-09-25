#!/usr/bin/env bash
# Prime supervisor — sandbox backend.
#
# A fake machine inside a directory. Same commands, same control flow, zero risk:
# no root, no btrfs, no pacman, nothing outside PRIME_STATE_DIR is ever touched.
# This is how the supervisor's logic is developed and proven, including the part
# that matters most — what happens when an update leaves the machine broken.
#
# World layout (all under $PRIME_STATE_DIR/sandbox):
#   pending              number of updates waiting
#   installed            number of packages installed
#   health_broken        if present, the machine boots but is unhealthy
#   fail_next_update     if present, the next update silently breaks the machine
#   snapshots/<id>/      pending, installed, label, created
#
# Not part of the supervisor interface: nothing here is called by anything except
# prime itself, through the same verb names the real backends implement.

SANDBOX_W="${PRIME_STATE_DIR:-$HOME/.local/state/prime}/sandbox"

sb_init() { # seed the fake machine if it does not exist yet
  [ -d "$SANDBOX_W" ] && return 0
  mkdir -p "$SANDBOX_W/snapshots"
  echo 228 > "$SANDBOX_W/pending"
  echo 1840 > "$SANDBOX_W/installed"
}

sb_pending() { sb_init; cat "$SANDBOX_W/pending" 2>/dev/null || echo 0; }

# ---------------------------------------------------------------- backend API
backend_status() {
  sb_init
  say "  machine:  $(uname -s) (sandbox) ${c_dim}— nothing here is real${c_reset}"
  say "  storage:  301 GB free of 752 GB"
  say "  snapshots: $(backend_snapshot_count)"
  if [ -e "$SANDBOX_W/health_broken" ]; then
    bad "last known state: unhealthy"
  else
    ok "last known state: healthy"
  fi
}

backend_update_count() { sb_pending; }

backend_updates() {
  sb_init
  local n; n="$(sb_pending)"
  [ "$n" = "0" ] && { dim "  (nothing pending)"; return 0; }
  say "  $n package(s) ready to install"
  say "  ${c_dim}e.g. linux 7.2.4 · mesa 25.3 · firefox 148.0${c_reset}"
}

backend_snapshot() { # backend_snapshot <label> -> prints id
  sb_init
  local label="${1:-manual}"
  local id; id="$(date -u +%Y%m%dT%H%M%SZ)"
  # two snapshots inside the same second must not collide
  while [ -d "$SANDBOX_W/snapshots/$id" ]; do id="$id-$(printf '%02d' $((RANDOM % 90 + 10)))"; done
  mkdir -p "$SANDBOX_W/snapshots/$id"
  cp "$SANDBOX_W/pending"   "$SANDBOX_W/snapshots/$id/pending"
  cp "$SANDBOX_W/installed" "$SANDBOX_W/snapshots/$id/installed"
  printf '%s\n' "$label" > "$SANDBOX_W/snapshots/$id/label"
  date -u +%FT%TZ > "$SANDBOX_W/snapshots/$id/created"
  [ -e "$SANDBOX_W/health_broken" ] && touch "$SANDBOX_W/snapshots/$id/was_broken"
  printf '%s\n' "$id"
}

backend_snapshot_count() {
  sb_init
  find "$SANDBOX_W/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

backend_snapshots() {
  sb_init
  local found=0
  for d in $(find "$SANDBOX_W/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r); do
    found=1
    printf '  %s  %-12s %s\n' "$(basename "$d")" "$(cat "$d/label" 2>/dev/null)" "$(cat "$d/created" 2>/dev/null)"
  done
  [ "$found" = "1" ] || dim "  (no rollback points yet)"
}

backend_apply_updates() {
  sb_init
  # an update that fails before it changes anything — the other failure mode
  if [ -e "$SANDBOX_W/fail_next_apply" ]; then
    rm -f "$SANDBOX_W/fail_next_apply"
    return 1
  fi
  local n; n="$(sb_pending)"
  if [ "$n" != "0" ]; then
    echo $(( $(cat "$SANDBOX_W/installed") + n )) > "$SANDBOX_W/installed"
    echo 0 > "$SANDBOX_W/pending"
  fi
  if [ -e "$SANDBOX_W/fail_next_update" ]; then
    rm -f "$SANDBOX_W/fail_next_update"
    touch "$SANDBOX_W/health_broken"   # the update "succeeded" and broke the machine
  fi
  touch "$SANDBOX_W/reboot_pending"    # an image update needs a restart to take effect
  return 0
}

backend_restore_last_good() { # the newest rollback point — used by post-boot recovery
  sb_init
  local d
  d="$(find "$SANDBOX_W/snapshots" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | tail -1)"
  [ -n "$d" ] || return 1
  backend_restore "$(basename "$d")"
}

# The sandbox has no real image digest, so it models one with two plain files:
# image_id is what is "booted" now, offer_id is what an update would install.
# They exist so the digest-based policy (skip a known-bad image, remember what
# broke) can be exercised here exactly as it is on bootc.
backend_current_digest() { sb_init; cat "$SANDBOX_W/image_id" 2>/dev/null || echo "sandbox-image-0"; }
backend_pending_digest() { # digest of the update being offered, empty if none
  sb_init
  [ "$(sb_pending)" != "0" ] || { echo ""; return 0; }
  cat "$SANDBOX_W/offer_id" 2>/dev/null || echo "sandbox-offer"
}

backend_pending_reboot() { # 1 = an update is installed but needs a restart
  sb_init
  [ -e "$SANDBOX_W/reboot_pending" ] && echo 1 || echo 0
}

backend_reboot() { # in the sandbox a restart just records that it happened
  sb_init
  date -u +%FT%TZ > "$SANDBOX_W/last_reboot"
  rm -f "$SANDBOX_W/reboot_pending"
  return 0
}

backend_restore() { # backend_restore <id>
  sb_init
  local id="$1"
  local d="$SANDBOX_W/snapshots/$id"
  [ -d "$d" ] || return 1
  cp "$d/pending"   "$SANDBOX_W/pending"
  cp "$d/installed" "$SANDBOX_W/installed"
  rm -f "$SANDBOX_W/health_broken"
  return 0
}

backend_health_boot() { # boot-critical only — what the boot-time verifier may roll back on
  sb_init
  printf 'cpu\t1\tProcessor: AMD Ryzen 5 7500X3D (sandbox)\n'
  printf 'memory\t1\tMemory: 24.4 GB available\n'
  printf 'storage\t1\tStorage: 301 GB free of 752 GB\n'
  if [ -e "$SANDBOX_W/health_broken" ]; then
    printf 'services\t0\tA system service failed to start after the update\n'
  else
    printf 'services\t1\tServices: nothing failed\n'
  fi
}

backend_health() { # everything: boot-critical + the desktop-is-usable checks
  backend_health_boot
  if [ -e "$SANDBOX_W/health_broken" ]; then
    printf 'display\t1\tDisplay: 1920x1080 x2\n'
    printf 'network\t1\tNetwork: wired connection active\n'
    printf 'session\t0\tDesktop session failed to start after the update\n'
    printf 'audio\t0\tAudio: no output device found\n'
  elif [ -e "$SANDBOX_W/comfort_broken" ]; then
    printf 'display\t1\tDisplay: 1920x1080 x2\n'
    printf 'network\t0\tNetwork: no connection (laptop not associated yet)\n'
    printf 'session\t0\tDesktop session did not start (login screen)\n'
    printf 'audio\t0\tAudio: no sound server running\n'
  else
    printf 'display\t1\tDisplay: 1920x1080 x2\n'
    printf 'network\t1\tNetwork: wired connection active\n'
    printf 'session\t1\tDesktop session started cleanly\n'
    printf 'audio\t1\tAudio: output and microphone working\n'
  fi
}

backend_health_snapshot() {
  sb_init
  printf '{"ts":"%s","pending":%s,"installed":%s,"broken":%s}\n' \
    "$(date -u +%FT%TZ)" "$(sb_pending)" "$(cat "$SANDBOX_W/installed" 2>/dev/null || echo 0)" \
    "$([ -e "$SANDBOX_W/health_broken" ] && echo true || echo false)"
}

# ---------------------------------------------------- sandbox-only conveniences
sb_break_next_update() { sb_init; touch "$SANDBOX_W/fail_next_update"; }
sb_fail_next_apply()   { sb_init; touch "$SANDBOX_W/fail_next_apply"; }
sb_set_pending()       { sb_init; echo "$1" > "$SANDBOX_W/pending"; }
sb_set_facts()         { sb_init; printf '%s\n' "$1" > "$SANDBOX_W/facts.json"; }
sb_rebooted()          { sb_init; [ -e "$SANDBOX_W/last_reboot" ] && echo 1 || echo 0; }
sb_pending_now()       { sb_pending; }
sb_set_offer_id()      { sb_init; printf '%s\n' "$1" > "$SANDBOX_W/offer_id"; }
sb_set_image_id()      { sb_init; printf '%s\n' "$1" > "$SANDBOX_W/image_id"; }
sb_comfort_broken()    { sb_init; touch "$SANDBOX_W/comfort_broken"; }

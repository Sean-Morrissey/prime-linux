#!/usr/bin/env bash
# Prime supervisor — backend for the shipped distro (image-based, bootc).
#
# On an atomic image there is nothing to snapshot before an update: the running
# system is one immutable image, an update downloads the *next* image alongside it,
# and the old one stays on disk. So the rollback point is not something Prime has to
# create — it already exists. That is the whole reason the product is built this way:
# the safety net is a property of the base, not a promise from the agent.
#
# Verbs here are the same ones the sandbox backend implements (see
# backend-sandbox.sh), so the policy engine in ./prime-autoupdate does not know or
# care which of them it is talking to.
#
# Two guards, both deliberate:
#   * everything refuses to run if this is not a bootc system (no bootc, no update)
#   * anything that changes the machine needs PRIME_ALLOW_REAL_SYSTEM_CHANGES=yes,
#     which only the installed systemd units set. Running a helper by hand cannot
#     quietly upgrade someone's computer.

need_bootc() {
  command -v bootc >/dev/null 2>&1 || {
    bad "this machine is not image-based (no 'bootc') — use the btrfs backend"
    return 1
  }
}

need_consent() {
  [ "${PRIME_ALLOW_REAL_SYSTEM_CHANGES:-no}" = "yes" ] || {
    bad "refusing to change a real machine without PRIME_ALLOW_REAL_SYSTEM_CHANGES=yes"
    return 1
  }
}

bt_json() { # one value out of `bootc status --json`, empty on any failure
  bootc status --json 2>/dev/null | python3 -c "
import json,sys
try: s=json.load(sys.stdin).get('status',{})
except Exception: print(''); raise SystemExit
path='$1'.split('.')
cur=s
for p in path:
    if isinstance(cur,dict) and p in cur: cur=cur[p]
    else: print(''); raise SystemExit
print(cur if cur is not None else '')" 2>/dev/null
}

bt_booted_image()  { bt_json booted.image.image; }
bt_booted_digest() { bt_json booted.image.imageDigest; }
bt_staged_digest() { bt_json staged.image.imageDigest; }
bt_rollback_digest() { bt_json rollback.image.imageDigest; }

# ---------------------------------------------------------------- backend API
backend_status() {
  need_bootc || return 1
  local img dig free
  img="$(bt_booted_image)"; dig="$(bt_booted_digest)"
  free="$(df -BG --output=avail / 2>/dev/null | tail -1 | tr -d ' G')"
  say "  system:   Prime Linux (image-based, bootc) — read-only root"
  say "  image:    ${img:-unknown} ${dig:+(${dig:0:12})}"
  say "  storage:  ${free:-?} GB free on /"
  if [ "$(backend_pending_reboot)" = "1" ]; then
    warn "an update is installed and waiting for a restart"
  else
    ok "running the newest installed version"
  fi
  if [ -n "$(bt_rollback_digest)" ]; then
    ok "previous version still on disk — the undo button exists"
  else
    dim "  (no previous version yet — the first update will create one)"
  fi
}

backend_update_count() {
  need_bootc || { echo 0; return 1; }
  local out
  out="$(bootc upgrade --check 2>&1 | tail -5)"
  if printf '%s' "$out" | grep -qiE 'update available|queued for next boot|new image'; then
    echo 1
  else
    echo 0
  fi
}

backend_updates() {
  need_bootc || return 1
  local out
  out="$(bootc upgrade --check 2>&1 | tail -5)"
  if printf '%s' "$out" | grep -qiE 'update available|queued for next boot|new image'; then
    say "  1 image update available"
    printf '%s\n' "$out" | sed 's/^/    /'
  else
    dim "  (nothing pending)"
  fi
}

# On an atomic system the rollback point already exists: it is the image you are
# running. Prime records its identity instead of creating anything.
backend_snapshot() { # -> prints the current deployment id
  need_bootc || return 1
  local dig; dig="$(bt_booted_digest)"
  printf '%s\n' "${dig:-booted}"
}

backend_snapshot_count() {
  need_bootc >/dev/null 2>&1 || { echo 0; return 0; }
  [ -n "$(bt_rollback_digest)" ] && echo 1 || echo 0
}

backend_snapshots() {
  need_bootc || return 1
  local b s r
  b="$(bt_booted_digest)"; s="$(bt_staged_digest)"; r="$(bt_rollback_digest)"
  [ -n "$b" ] && printf '  %s  %-10s %s\n' "${b:0:12}" "booted" "the version running now"
  [ -n "$s" ] && printf '  %s  %-10s %s\n' "${s:0:12}" "staged" "installed, applies on restart"
  [ -n "$r" ] && printf '  %s  %-10s %s\n' "${r:0:12}" "rollback" "go back to this"
  [ -n "$b$s$r" ] || dim "  (no deployments reported)"
}

backend_apply_updates() {
  need_bootc || return 1
  need_consent || return 1
  # downloads and stages the next image; nothing about the running system changes
  bootc upgrade 2>&1 | sed 's/^/    /'
  local rc=${PIPESTATUS[0]}
  [ "$rc" -eq 0 ] || return 1
  return 0
}

backend_pending_reboot() {
  need_bootc >/dev/null 2>&1 || { echo 0; return 0; }
  local s b
  s="$(bt_staged_digest)"; b="$(bt_booted_digest)"
  if [ -n "$s" ] && [ "$s" != "$b" ]; then echo 1; else echo 0; fi
}

backend_reboot() {
  need_consent || return 1
  systemctl reboot
}

backend_restore() { # <id> — bootc rolls back one deployment, which is the one that matters
  need_bootc || return 1
  need_consent || return 1
  bootc rollback 2>&1 | sed 's/^/    /'
  return ${PIPESTATUS[0]}
}

backend_restore_last_good() { backend_restore last; }

# digests for the "skip a known-bad image" policy (see prime-autoupdate cmd_cycle)
backend_current_digest() { need_bootc >/dev/null 2>&1 || { echo ""; return 0; }; bt_booted_digest; }
backend_pending_digest() { need_bootc >/dev/null 2>&1 || { echo ""; return 0; }; bt_staged_digest; }

# ---------------------------------------------------------------- health
# Two tiers, on purpose (P0-3). `backend_health_boot` is the *boot-time verifier*:
# it must only assert things that are guaranteed true at boot — failed units,
# storage, and the root filesystem. Network (a Wi-Fi laptop that has not associated
# yet), a screen (a lid-closed laptop) and a session (the login screen) are all
# legitimately absent right after boot, so they would produce false failures and
# trigger a rollback-reboot loop. Those live in `backend_health`, which `prime
# health` runs once someone is actually using the machine.
hd_free_gb() { df -BG --output=avail / 2>/dev/null | tail -1 | tr -d ' G'; }

backend_health_boot() {
  # storage
  local free; free="$(hd_free_gb)"
  if [ "${free:-0}" -lt 2 ]; then printf 'storage\t0\tStorage: only %s GB free\n' "${free:-?}"
  else printf 'storage\t1\tStorage: %s GB free\n' "$free"; fi

  # failed units — the single best "did this update break something" signal
  local failed_units=0
  command -v systemctl >/dev/null 2>&1 && \
    failed_units="$(systemctl --failed --no-legend 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${failed_units:-0}" -gt 0 ]; then
    printf 'services\t0\tServices: %s failed unit(s)\n' "$failed_units"
  else
    printf 'services\t1\tServices: nothing failed\n'
  fi

  # root filesystem mounted and readable
  if [ -r /etc/os-release ] && [ -d /usr ]; then
    printf 'rootfs\t1\tRoot filesystem readable\n'
  else
    printf 'rootfs\t0\tRoot filesystem not readable\n'
  fi
}

backend_health() { # everything: boot-critical plus the desktop-is-usable checks
  backend_health_boot

  # network
  if ip route show default 2>/dev/null | grep -q .; then
    printf 'network\t1\tNetwork: connected\n'
  else
    printf 'network\t0\tNetwork: no connection\n'
  fi

  # display hardware present and something plugged into it
  local connected=0
  for st in /sys/class/drm/card*-*/status; do
    [ -r "$st" ] || continue
    [ "$(cat "$st" 2>/dev/null)" = "connected" ] && connected=1
  done
  if [ "$connected" = "1" ]; then printf 'display\t1\tDisplay: screen detected\n'
  else printf 'display\t0\tDisplay: no screen detected\n'; fi

  # a graphical session actually exists
  local gfx=0
  if command -v loginctl >/dev/null 2>&1; then
    for s in $(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}'); do
      local ty; ty="$(loginctl show-session "$s" -p Type --value 2>/dev/null)"
      case "$ty" in wayland|x11) gfx=1 ;; esac
    done
  fi
  if [ "$gfx" = "1" ]; then printf 'session\t1\tDesktop session started cleanly\n'
  else printf 'session\t0\tDesktop session did not start\n'; fi

  # audio stack alive for at least one user
  local audio=0
  if [ -d /sys/class/sound ]; then
    command -v pgrep >/dev/null 2>&1 && pgrep -x pipewire >/dev/null 2>&1 && audio=1
    [ "$audio" = "0" ] && pgrep -x pulseaudio >/dev/null 2>&1 && audio=1
  fi
  if [ "$audio" = "1" ]; then printf 'audio\t1\tAudio: sound server running\n'
  else printf 'audio\t0\tAudio: no sound server running\n'; fi
}

backend_health_snapshot() {
  printf '{"ts":"%s","free_gb":%s,"failed_units":%s,"image":"%s"}\n' \
    "$(date -u +%FT%TZ)" "${free_gb:-$(hd_free_gb)}" "${failed_units:-0}" "$(bt_booted_digest)"
}

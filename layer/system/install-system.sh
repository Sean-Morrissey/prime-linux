#!/usr/bin/env bash
# install-system.sh — put Prime Linux's system pieces in place (run as root).
#
#   install-system.sh install [--user NAME] [--policy auto|ask|security|off]
#                             [--no-enable] [--no-security]
#   install-system.sh uninstall      remove everything this installed
#   install-system.sh main-user --user NAME   make NAME the computer's main account
#   install-system.sh forget-user --user NAME NAME no longer uses Prime (prime-uninstall)
#   install-system.sh status         what is installed, and is it current
#   install-system.sh needs-update   exit 1 if the installed copies are older than this
#                                    checkout (no root needed; prime-update uses it)
#   --root DIR                       install under DIR instead of / (tests; no systemctl)
#
# Safe to re-run. Everything that runs as root is COPIED here, root-owned, from
# the layer — nothing root runs ever lives in a home folder, so no account can
# change what the nightly updater or the pacman hook execute.
#
# What it installs:
#   /usr/local/lib/prime-linux/prime-system-update       the updater (and prime-security)
#   /etc/systemd/system/prime-system-update.{service,timer}
#   /etc/prime/updates.conf                              settings (kept if it exists)
#   /etc/pacman.d/hooks/zz-prime-desktop-backup.hook     + /usr/share/libalpm/scripts/prime-desktop-backup-all
#   /etc/sysctl.d/90-prime-security.conf + firewall      (prime-security apply)
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LAYER="$(readlink -f "$HERE/..")"
ROOT=""; USER_NAME=""; POLICY=""; ENABLE=1; SECURITY=1
cmd="${1:-}"; shift 2>/dev/null || true
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2%/}"; shift ;;
    --user) USER_NAME="$2"; shift ;;
    --policy) POLICY="$2"; shift ;;
    --no-enable) ENABLE=0 ;;
    --no-security) SECURITY=0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac; shift
done
case "$POLICY" in ""|auto|ask|security|off) ;; automatic) POLICY=auto ;; *) echo "policy must be auto, ask, security or off" >&2; exit 2 ;; esac

LIB=/usr/local/lib/prime-linux
# source (relative to layer/) → destination, mode
FILES=(
  "system/updates/prime-system-update|$LIB/prime-system-update|755"
  "bin/prime-security|$LIB/prime-security|755"
  "system/security/90-prime-security.conf|$LIB/90-prime-security.conf|644"
  "system/updates/prime-system-update.service|/etc/systemd/system/prime-system-update.service|644"
  "system/updates/prime-system-update.timer|/etc/systemd/system/prime-system-update.timer|644"
  "system/libalpm/prime-desktop-backup-all|/usr/share/libalpm/scripts/prime-desktop-backup-all|755"
  "system/zz-prime-desktop-backup.hook|/etc/pacman.d/hooks/zz-prime-desktop-backup.hook|644"
)
MANIFEST="$ROOT/var/lib/prime-linux/system-files"
live() { [ -z "$ROOT" ] && [ -d /run/systemd/system ]; }
say() { printf '    %s\n' "$*"; }
need_root() { [ "$(id -u)" = 0 ] || [ -n "$ROOT" ] || { echo "run this as root (sudo)" >&2; exit 4; }; }

stale_files() { # prints destinations whose installed copy differs from the layer
  local f src dst
  for f in "${FILES[@]}"; do
    IFS='|' read -r src dst _ <<<"$f"
    cmp -s "$LAYER/$src" "$ROOT$dst" || echo "$dst"
  done
}

install_all() {
  need_root
  local f src dst mode changed=0
  mkdir -p "$(dirname "$MANIFEST")"
  : > "$MANIFEST.new"
  for f in "${FILES[@]}"; do
    IFS='|' read -r src dst mode <<<"$f"
    if ! cmp -s "$LAYER/$src" "$ROOT$dst"; then
      install -D -o 0 -g 0 -m "$mode" "$LAYER/$src" "$ROOT$dst" 2>/dev/null \
        || install -D -m "$mode" "$LAYER/$src" "$ROOT$dst" || { echo "could not install $dst" >&2; return 1; }
      changed=1
    fi
    echo "$dst" >> "$MANIFEST.new"
  done
  mv -f "$MANIFEST.new" "$MANIFEST"
  say "updater, nightly service and pacman hook in place"

  # settings: created once, then they belong to the person
  local conf="$ROOT/etc/prime/updates.conf"
  if [ ! -e "$conf" ]; then install -D -m 644 "$LAYER/system/updates/updates.conf" "$conf"; say "settings: $conf (new)"
  else say "settings: $conf (kept)"; fi
  local sets=()
  [ -n "$POLICY" ] && sets+=("POLICY=$POLICY")
  # the computer's main account is the first one that installed Prime: a second
  # account installing later must not take over (whose AUR updates get checked)
  if [ -n "$USER_NAME" ] && [[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && ! grep -qE '^MAIN_USER=.' "$conf"; then
    sets+=("MAIN_USER=$USER_NAME")
  fi
  [ ${#sets[@]} -gt 0 ] && sed_set "$conf" "${sets[@]}"     # values validated above
  mkdir -p "$ROOT/var/lib/prime-linux/updates"; chmod 755 "$ROOT/var/lib/prime-linux" "$ROOT/var/lib/prime-linux/updates"
  # which accounts use Prime: home folders are private, so this list (readable by
  # everyone, written only here) is how one account knows another still needs the
  # shared pieces. Installs from before the list existed: the main account counts.
  local main_; main_="$(sed -n 's/^MAIN_USER=//p' "$conf" | tail -1)"
  [ -n "$main_" ] && remember_user "$main_"
  [ -n "$USER_NAME" ] && [[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && remember_user "$USER_NAME"
  [ -e "$ROOT/var/lib/prime-linux/updates/installed-at" ] || date +%s > "$ROOT/var/lib/prime-linux/updates/installed-at"

  local policy; policy="$(sed -n 's/^POLICY=//p' "$conf" | tail -1)"
  if live; then
    systemctl daemon-reload
    if [ "$ENABLE" = 1 ] && [ "${policy:-auto}" != off ]; then
      systemctl enable --now prime-system-update.timer >/dev/null 2>&1 && say "automatic updates: on (${policy:-auto})"
    else
      systemctl disable --now prime-system-update.timer >/dev/null 2>&1; say "automatic updates: off"
    fi
  else
    say "automatic updates: ${policy:-auto} (service is enabled at first boot)"
    [ "$ENABLE" = 1 ] && [ "${policy:-auto}" != off ] && mkdir -p "$ROOT/etc/systemd/system/timers.target.wants" \
      && ln -sfn /etc/systemd/system/prime-system-update.timer "$ROOT/etc/systemd/system/timers.target.wants/prime-system-update.timer"
  fi
  if [ "$SECURITY" = 1 ]; then
    PRIME_SEC_ROOT="$ROOT" PRIME_TEST_ALLOW_NONROOT="$([ -n "$ROOT" ] && echo 1 || echo 0)" "$ROOT$LIB/prime-security" apply | sed 's/^  /    /' | tail -n +2
  fi
  return 0
}

USERS_FILE="$ROOT/var/lib/prime-linux/users"
remember_user() { # remember_user NAME — once, kept sorted
  mkdir -p "$(dirname "$USERS_FILE")"
  { cat "$USERS_FILE" 2>/dev/null; echo "$1"; } | grep -E '^[a-z_][a-z0-9_-]{0,31}$' | sort -u > "$USERS_FILE.new"
  chmod 644 "$USERS_FILE.new"; mv -f "$USERS_FILE.new" "$USERS_FILE"
}

sed_set() { # fallback when the updater can't run here: same validation, plain edit
  local conf="$1" kv; shift
  for kv in "$@"; do
    if grep -q "^${kv%%=*}=" "$conf"; then sed -i "s|^${kv%%=*}=.*|$kv|" "$conf"; else echo "$kv" >> "$conf"; fi
  done
}

uninstall_all() {
  need_root
  if live; then systemctl disable --now prime-system-update.timer >/dev/null 2>&1; fi
  local f
  if [ -r "$MANIFEST" ]; then while read -r f; do [ -n "$f" ] && rm -f "$ROOT$f"; done < "$MANIFEST"
  else for f in "${FILES[@]}"; do IFS='|' read -r _ f _ <<<"$f"; rm -f "$ROOT$f"; done; fi
  rm -f "$ROOT/etc/sysctl.d/90-prime-security.conf" "$ROOT/etc/systemd/system/timers.target.wants/prime-system-update.timer"
  rm -rf "$ROOT/etc/prime/updates.conf" "$ROOT/var/lib/prime-linux"
  rmdir "$ROOT$LIB" "$ROOT/etc/prime" 2>/dev/null
  live && systemctl daemon-reload
  say "Prime's system pieces removed (the firewall stays on — it is CachyOS's default too)"
}

case "$cmd" in
  install)      install_all ;;
  forget-user)  # an account left Prime (prime-uninstall): prints how many still use it
    need_root
    [[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "forget-user needs --user NAME" >&2; exit 2; }
    if [ -f "$USERS_FILE" ]; then grep -vx "$USER_NAME" "$USERS_FILE" > "$USERS_FILE.new"; chmod 644 "$USERS_FILE.new"; mv -f "$USERS_FILE.new" "$USERS_FILE"; fi
    n="$(grep -c . "$USERS_FILE" 2>/dev/null)"; echo "${n:-0}"
    exit 0 ;;
  main-user)    # hand the "main account" role on (prime-uninstall, when its owner leaves)
    need_root
    [[ "$USER_NAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { echo "main-user needs --user NAME" >&2; exit 2; }
    [ -f "$ROOT/etc/prime/updates.conf" ] && sed_set "$ROOT/etc/prime/updates.conf" "MAIN_USER=$USER_NAME"
    exit 0 ;;
  uninstall)    uninstall_all ;;
  needs-update) s="$(stale_files)"; [ -z "$s" ] && exit 0; printf '%s\n' "$s"; exit 1 ;;
  status)
    s="$(stale_files)"
    if [ -z "$s" ]; then echo "Prime system pieces: installed and current"
    else echo "Prime system pieces: missing or older than this copy:"; printf '  %s\n' $s; fi
    live && echo "nightly timer: $(systemctl is-enabled prime-system-update.timer 2>/dev/null)" ;;
  *) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

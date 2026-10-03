#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"   # never the real home or session (tests/sandbox.sh)
# Sandbox tests for Prime's real updater (layer/system/updates/prime-system-update),
# its installer (layer/system/install-system.sh), the update-policy CLI and the
# pacman backup hook. Nothing here needs root or touches this machine: every
# command that could change a system (pacman, snapper, systemctl, flatpak,
# runuser…) is a fake on PATH — and the updater itself refuses to run in test
# mode if any of them would resolve to the real one.
#
# Run: bash tests/check-system-update.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYER="$(cd "$HERE/../layer" && pwd)"
ENGINE="$LAYER/system/updates/prime-system-update"
T="$(mktemp -d "${TMPDIR:-/tmp}/prime-sysupd-test.XXXXXX")"
trap 'rm -rf "$T"' EXIT
pass=0; fail=0
c_ok=$'\033[32m'; c_bad=$'\033[31m'; c_b=$'\033[1m'; c_r=$'\033[0m'
section() { printf '\n%s%s%s\n' "$c_b" "$*" "$c_r"; }
good() { printf '  %s✓%s %s\n' "$c_ok" "$c_r" "$*"; pass=$((pass+1)); }
nope() { printf '  %s✗%s %s\n' "$c_bad" "$c_r" "$*"; fail=$((fail+1)); }
check() { if [ "$2" = "$3" ]; then good "$1"; else nope "$1 (expected '$2', got '$3')"; fi; }
has()   { if grep -q -- "$2" "$3" 2>/dev/null; then good "$1"; else nope "$1 (no '$2' in $(basename "$3"))"; fi; }
hasnt() { if grep -q -- "$2" "$3" 2>/dev/null; then nope "$1 (found '$2')"; else good "$1"; fi; }

# ── fake commands ────────────────────────────────────────────────────────────
FB="$T/fakebin"; mkdir -p "$FB"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$FAKE/calls"\n%s\n' "$1" "${2:-exit 0}" > "$FB/$1"; chmod +x "$FB/$1"; }
cat > "$FB/pacman" <<'EOF'
#!/usr/bin/env bash
echo "pacman $*" >> "$FAKE/calls"
case "$1" in
  -Sy|-Syy) [ -e "$FAKE/fail_sync" ] && { echo "error: failed retrieving file 'core.db'"; exit 1; }; exit 0 ;;
  -Qu)  cat "$FAKE/pending" 2>/dev/null; exit 0 ;;
  -Suw) [ -e "$FAKE/fail_download" ] && { echo "error: failed retrieving file 'x.pkg.tar.zst' : Operation too slow"; exit 1; }; exit 0 ;;
  -Su)
    if [ -e "$FAKE/fail_install" ]; then
      [ -e "$FAKE/partial" ] && { echo half >> "$FAKE/installed"; rm -f "$FAKE/fail_install"; }
      echo "error: failed to commit transaction"; exit 1
    fi
    ts="$(date '+%Y-%m-%dT%H:%M:%S%z')"
    while read -r p v; do echo "[$ts] [ALPM] upgraded $p ($v -> 2)" >> "$FAKE/pacman.log"; done < "$FAKE/pending"
    : > "$FAKE/pending"; echo upgraded >> "$FAKE/installed"; exit 0 ;;
  -S)   exit 0 ;;
  -Q)   cat "$FAKE/installed"; exit 0 ;;
  -Qq)  grep -qx "$2" "$FAKE/pkgs" 2>/dev/null; exit ;;
  -Qqg) exit 1 ;;
  -Dk)  exit 0 ;;
esac
exit 0
EOF
chmod +x "$FB/pacman"
fake snapper 'echo 42'
fake systemctl '[ "${1:-}" = --failed ] && { cat "$FAKE/failed" 2>/dev/null; exit 0; }; exit 1'
fake runuser 'shift 3; exec "$@"'
fake paru 'cat "$FAKE/aur" 2>/dev/null'
for c in flatpak systemd-run systemd-inhibit mkinitcpio limine-mkinitcpio dracut cachyos-rate-mirrors reflector; do fake "$c"; done

NOW=1790000000
world() { # world <name> — a fresh fake computer, updates waiting
  W="$T/$1"; FAKE="$W/fake"; mkdir -p "$FAKE" "$W/state" "$W/home" "$W/boot" "$W/modules/7.0-cachyos"
  printf 'archlinux-keyring 1\nlinux-cachyos 7.0\nfirefox 140\n' > "$FAKE/pending"
  printf 'base 1\n' > "$FAKE/installed"; printf 'snap-pac\n' > "$FAKE/pkgs"; : > "$FAKE/pacman.log"
  echo linux-cachyos > "$W/modules/7.0-cachyos/pkgbase"
  echo k > "$W/boot/vmlinuz-linux-cachyos"; echo i > "$W/boot/initramfs-linux-cachyos.img"
  cp "$LAYER/system/updates/updates.conf" "$W/updates.conf"
  echo $((NOW - 3 * 86400)) > "$W/state/installed-at"
  facts "away_minutes=60" "gaming=-" "power=ac" "metered=no" "free_gb=50" "boot_free_mb=-" "pkg_busy=-" \
        "root_fs=btrfs" "snapper_root=yes" "bootloader=limine" "repo_updates=3" "flatpak_updates=0" \
        "aur_updates=0" "security_updates=0" "sessions=-"
  HOUR=4
}
facts() { printf '%s\n' "$@" > "$W/facts"; }
fact()  { echo "$1" >> "$W/facts"; }        # later lines win
eng() { # eng <args…>  → output in $W/out, exit code in $rc
  env HOME="$W/home" PRIME_TEST_ALLOW_NONROOT=1 PRIME_ALLOW_REAL_SYSTEM_CHANGES="${ALLOW:-yes}" PATH="$FB:$PATH" FAKE="$FAKE" \
    PRIME_UPDATES_CONF="$W/updates.conf" PRIME_UPDATES_STATE="$W/state" PRIME_FACTS_FILE="$W/facts" \
    PRIME_PACMAN_LOCK="$W/db.lck" PRIME_PACMAN_LOG="$FAKE/pacman.log" PRIME_BOOT_DIR="$W/boot" PRIME_MODULES_DIR="$W/modules" \
    PRIME_NOW_EPOCH="$NOW" PRIME_NOW_HOUR="$HOUR" "$ENGINE" "$@" > "$W/out" 2>&1
  rc=$?
}
installed() { cat "$FAKE/calls" 2>/dev/null | grep -c 'pacman -Su --needed' || true; }
status_of() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$W/state/last-run.json" 2>/dev/null; }

section "1. idle maths (the old supervisor mixed microseconds and seconds)"
src="$(sed -n '/^idle_minutes_from()/,/^}/p' "$ENGINE")"; eval "$src"
check "10 minutes idle reads as 10" 10 "$(idle_minutes_from 1000.5 $(( (1000500000 - 600000000) )))"
check "idle-since in the future reads as 0" 0 "$(idle_minutes_from 100 200000000)"
check "2 hours idle on a machine up 30 days" 120 "$(idle_minutes_from 2592000 $(( (2592000 - 7200) * 1000000 )))"

section "2. update hours, nobody at the computer → installs, snapshot first, keyring first"
world night; eng cycle
check "cycle exits cleanly" 0 "$rc"
check "packages installed once" 1 "$(installed)"
order="$(grep -oE 'pacman -Sy |pacman -S --needed|pacman -Suw|snapper|pacman -Su --needed' "$FAKE/calls" | tr '\n' ',' )"
check "order: sync, keyring, download, snapshot, install" "pacman -Sy ,pacman -S --needed,pacman -Suw,snapper,pacman -Su --needed," "$order"
has "keyring packages updated on their own first" "pacman -S --needed .*archlinux-keyring" "$FAKE/calls"
check "result recorded" ok "$(status_of)"
has "restart advised (new kernel)" '"restart": "yes"' "$W/state/last-run.json"
has "snapshot number recorded" '"snapshot": "42"' "$W/state/last-run.json"
has "pop-up held for quiet hours (4am)" "held for quiet hours" "$W/state/history.log"
eng cycle
check "second run the same night does nothing (once a day)" 1 "$(installed)"

section "3. update hours but someone is using the computer → waits"
world busy; fact away_minutes=2; eng cycle
check "nothing installed" 0 "$(installed)"
has "says why" "someone is using the computer" "$W/out"

section "4. outside update hours, not overdue → waits"
world day; HOUR=14; echo $((NOW - 3600)) > "$W/state/installed-at"; eng cycle
check "nothing installed" 0 "$(installed)"

section "5. computer is off every night → catches up when overdue and nobody is using it"
world offnights; HOUR=14; eng cycle
check "installed (3 days overdue, away)" 1 "$(installed)"
world offnights2; HOUR=14; fact away_minutes=0; eng cycle
check "…but not while someone is working" 0 "$(installed)"

section "6. never during a game, on low battery, on a metered connection"
world game; fact "gaming=gamescope fullscreen"; eng cycle
check "game running: nothing installed" 0 "$(installed)"; has "says so" "game or fullscreen" "$W/out"
world batt; fact "power=battery 30"; eng cycle
check "battery 30%: nothing installed" 0 "$(installed)"; has "says so" "on battery at 30%" "$W/out"
world batt2; fact "power=battery 80"; eng cycle
check "battery 80%: installs" 1 "$(installed)"
world metered; fact metered=yes; eng cycle
check "metered: nothing installed" 0 "$(installed)"

section "7. policies"
world off; sed -i 's/^POLICY=.*/POLICY=off/' "$W/updates.conf"; eng cycle
check "off: nothing at all" 0 "$(installed)"; hasnt "off: doesn't even check" "pacman" "$FAKE/calls"
world ask; sed -i 's/^POLICY=.*/POLICY=ask/' "$W/updates.conf"; HOUR=14; eng cycle
check "ask: nothing installed" 0 "$(installed)"
has "ask: offers Install now" "Install now" "$W/state/notifications.test"
world sec0; sed -i 's/^POLICY=.*/POLICY=security/' "$W/updates.conf"; echo $((NOW - 86400)) > "$W/state/last-success"; echo 0 > "$W/state/last-attempt"; eng cycle
check "security, no security fix waiting: waits" 0 "$(installed)"
world sec2; sed -i 's/^POLICY=.*/POLICY=security/' "$W/updates.conf"; fact security_updates=2; eng cycle
check "security, 2 security fixes waiting: full update" 1 "$(installed)"
world sec-old; sed -i 's/^POLICY=.*/POLICY=security/' "$W/updates.conf"; echo $((NOW - 40 * 86400)) > "$W/state/last-success"; eng cycle
check "security, 40 days since the last update: full update anyway" 1 "$(installed)"

section "8. a download fails → nothing installed, no snapshot, mirrors refreshed, retried later"
world dl; touch "$FAKE/fail_download"; eng cycle
check "nothing installed" 0 "$(installed)"
hasnt "no snapshot taken for nothing" "snapper" "$FAKE/calls"
has "faster mirrors picked" "cachyos-rate-mirrors" "$FAKE/calls"
check "result: skipped (machine untouched)" skipped "$(status_of)"
check "not counted as a failure" "" "$(cat "$W/state/failcount" 2>/dev/null)"

section "9. install fails before changing anything → failure counted; stops after FAIL_LIMIT"
world inst; touch "$FAKE/fail_install"; eng cycle
check "result: failed" failed "$(status_of)"; check "failure count 1" 1 "$(cat "$W/state/failcount")"
has "plain words: nothing was changed" "Nothing was changed" "$W/state/last-run.json"
echo 0 > "$W/state/last-attempt"; eng cycle; check "failure count 2" 2 "$(cat "$W/state/failcount")"
echo 0 > "$W/state/last-attempt"; : > "$FAKE/calls"; eng cycle
has "third night: stops and waits for a person" "waiting for a person" "$W/out"
hasnt "…without touching pacman" "pacman" "$FAKE/calls"

section "10. install stops part-way → finishes it (never left half-updated)"
world partial; touch "$FAKE/fail_install" "$FAKE/partial"; eng cycle
check "retried and finished" ok "$(status_of)"
check "install attempted twice" 2 "$(installed)"

section "11. after the update: missing startup image is rebuilt"
world initrd; sed -i 's/^-Su)/-Su)/' "$FB/pacman"; rm "$W/boot/initramfs-linux-cachyos.img"; eng cycle
has "mkinitcpio -P run" "mkinitcpio -P" "$FAKE/calls"
check "machine reported fine after the repair" ok "$(status_of)"

section "12. a service that broke with the update is noticed"
world units; cat > "$FB/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >> "$FAKE/calls"
[ "${1:-}" = --failed ] && { grep -q upgraded "$FAKE/installed" && echo "bluetooth.service loaded failed failed"; exit 0; }
exit 1
EOF
eng cycle
check "result: attention" attention "$(status_of)"
has "names the service" "bluetooth.service" "$W/state/last-run.json"
has "tried restarting it" "systemctl restart bluetooth.service" "$FAKE/calls"
fake systemctl '[ "${1:-}" = --failed ] && { cat "$FAKE/failed" 2>/dev/null; exit 0; }; exit 1'

section "13. manual run (prime-update) and safety refusals"
world manual; HOUR=14; fact away_minutes=0; touch "$W/db.lck"; eng apply --manual
check "manual run installs even while you work" 1 "$(installed)"
has "removed a lock left by a crash" "leftover lock" "$W/out"
has "machine-readable result for prime-update" "RESULT ok" "$W/out"
world guard; ALLOW=no eng cycle
check "without the consent flag: refuses (exit 3)" 3 "$rc"
hasnt "…and runs no pacman" "pacman" "$FAKE/calls" 2>/dev/null
world lowdisk; fact free_gb=2; eng apply --manual
check "2 GB free: refuses" 2 "$rc"; hasnt "…before touching pacman" "pacman -Sy" "$FAKE/calls"
world esp; fact boot_free_mb=60; eng apply --manual
check "boot partition nearly full: refuses" 2 "$rc"
world realcmd; env HOME="$W/home" PRIME_TEST_ALLOW_NONROOT=1 PRIME_ALLOW_REAL_SYSTEM_CHANGES=yes PRIME_UPDATES_STATE="$W/state" \
  PRIME_UPDATES_CONF="$W/updates.conf" "$ENGINE" cycle >/dev/null 2>&1; rc=$?
if command -v pacman >/dev/null; then check "test mode with the real pacman on PATH: refuses (exit 99)" 99 "$rc"; fi

section "14. settings are validated (they are read by a root service)"
world set; eng set POLICY=ask WINDOW_START=1; check "valid settings saved" 0 "$rc"
has "POLICY=ask written" "^POLICY=ask" "$W/updates.conf"
eng set 'POLICY=auto;rm -rf /'; check "injection refused" 2 "$rc"
eng set WINDOW_START=25; check "hour 25 refused" 2 "$rc"
eng set EVIL=1; check "unknown key refused" 2 "$rc"
echo 'POLICY=$(touch '"$W"'/pwned)' >> "$W/updates.conf"; eng status
check "config is parsed, never executed" no "$([ -e "$W/pwned" ] && echo yes || echo no)"

section "15. prime-update-policy (used by the welcome flow and the assistant)"
world pol
pol() { env PRIME_TEST_ALLOW_NONROOT=1 PRIME_UPDATES_CONF="$W/updates.conf" PRIME_UPDATES_STATE="$W/state" \
        PRIME_UPDATES_ENGINE="$ENGINE" PATH="$FB:$PATH" FAKE="$FAKE" "$LAYER/bin/prime-update-policy" "$@" 2>/dev/null; }
check "get: default is automatic" automatic "$(pol get)"
pol set ask >/dev/null; check "set ask → exit 0" 0 "$?"; check "get: ask" ask "$(pol get)"
pol set off >/dev/null; check "get: off" off "$(pol get)"
pol set security >/dev/null; check "get: security" security "$(pol get)"
pol set automatic >/dev/null; check "set automatic → get automatic" automatic "$(pol get)"
pol set sometimes >/dev/null; check "nonsense value → exit 2" 2 "$?"

section "16. install-system.sh into a scratch root"
R="$T/root"; bash "$LAYER/system/install-system.sh" install --root "$R" --user alex --policy ask > "$T/inst.out" 2>&1
check "install exits 0" 0 "$?"
for f in usr/local/lib/prime-linux/prime-system-update usr/local/lib/prime-linux/prime-security \
         etc/systemd/system/prime-system-update.service etc/systemd/system/prime-system-update.timer \
         etc/pacman.d/hooks/zz-prime-desktop-backup.hook usr/share/libalpm/scripts/prime-desktop-backup-all \
         etc/prime/updates.conf etc/sysctl.d/90-prime-security.conf; do
  [ -e "$R/$f" ] && good "/$f" || nope "/$f missing"
done
has "policy set from the installer" "^POLICY=ask" "$R/etc/prime/updates.conf"
has "AUR user set" "^MAIN_USER=alex" "$R/etc/prime/updates.conf"
check "timer enabled for first boot" yes "$([ -L "$R/etc/systemd/system/timers.target.wants/prime-system-update.timer" ] && echo yes || echo no)"
has "service carries the consent flag" "PRIME_ALLOW_REAL_SYSTEM_CHANGES=yes" "$R/etc/systemd/system/prime-system-update.service"
has "service runs the root-owned copy, not a home folder" "ExecStart=/usr/local/lib/prime-linux/" "$R/etc/systemd/system/prime-system-update.service"
bash "$LAYER/system/install-system.sh" needs-update --root "$R" >/dev/null; check "needs-update: current" 0 "$?"
sed -i 's/^POLICY=.*/POLICY=off/' "$R/etc/prime/updates.conf"
bash "$LAYER/system/install-system.sh" install --root "$R" >/dev/null 2>&1
has "re-install keeps the person's settings" "^POLICY=off" "$R/etc/prime/updates.conf"
echo '# changed' >> "$R/usr/local/lib/prime-linux/prime-system-update"
bash "$LAYER/system/install-system.sh" needs-update --root "$R" >/dev/null; check "needs-update: notices a stale copy" 1 "$?"
bash "$LAYER/system/install-system.sh" uninstall --root "$R" >/dev/null 2>&1
check "uninstall leaves no files" 0 "$(find "$R" -type f | wc -l)"

section "17. pacman backup hook: runs nothing from home folders, archives are private"
H="$T/hookhome"; mkdir -p "$H/.local/share/prime-linux/layer/bin" "$H/.config/prime" "$H/.config/hypr"
echo secret > "$H/.config/prime/ai.key"; echo x > "$H/.config/hypr/hyprland.conf"
printf '#!/bin/sh\ntouch %s/USER-CODE-RAN\n' "$T" > "$H/.local/share/prime-linux/layer/bin/prime-desktop-backup"
chmod +x "$H/.local/share/prime-linux/layer/bin/prime-desktop-backup"
printf '#!/bin/sh\necho "alex:x:%s:%s::%s:/bin/bash"\n' "$(id -u)" "$(id -g)" "$H" > "$FB/getent"; chmod +x "$FB/getent"
env PATH="$FB:$PATH" FAKE="$T" bash "$LAYER/system/libalpm/prime-desktop-backup-all"; check "hook exits 0" 0 "$?"
arc="$(ls "$H"/.config-backups/desktop/*_before-update.tar.gz 2>/dev/null | head -1)"
[ -n "$arc" ] && good "settings archived (restore menu format)" || nope "no archive written"
check "user's own script was NOT run" no "$([ -e "$T/USER-CODE-RAN" ] && echo yes || echo no)"
check "archive readable only by its owner" 600 "$(stat -c %a "$arc" 2>/dev/null)"
check "backup folder private" 700 "$(stat -c %a "$H/.config-backups/desktop" 2>/dev/null)"
check "API key not in the archive" 0 "$(tar -tzf "$arc" 2>/dev/null | grep -c ai.key)"
has "ran as the user through runuser" "runuser -u alex" "$T/calls"

section "18. prime-security"
SH="$T/sechome"; mkdir -p "$SH/.config/prime" "$SH/.config-backups"; chmod 755 "$SH/.config/prime" "$SH/.config-backups"
chmod 700 "$SH"; echo k > "$SH/.config/prime/ai.key"; chmod 644 "$SH/.config/prime/ai.key"
U="$T/ufw"; mkdir -p "$U"; echo ENABLED=yes > "$U/ufw.conf"
printf '%s\n' '### tuple ### allow any 22 0.0.0.0/0 any 0.0.0.0/0 in' \
  '### tuple ### allow udp 5353 0.0.0.0/0 any 192.168.0.0/16 in comment=50' > "$U/user.rules"
# the firewall is on (ufw enabled), SSH is off: no answer may come from this machine's own systemd
SB="$T/secbin"; mkdir -p "$SB"
printf '#!/bin/sh\ncase "$*" in *is-enabled*ufw.service*) exit 0 ;; esac\nexit 1\n' > "$SB/systemctl"; chmod +x "$SB/systemctl"
sec() { env HOME="$SH" PRIME_UFW_DIR="$U" PATH="$SB:$PATH" "$LAYER/bin/prime-security" "$@" 2>/dev/null; }
sec status --tsv > "$T/sec.tsv"
has "private files flagged" "Other accounts on this computer can read" "$T/sec.tsv"
has "port open to every network flagged" "Open to every network.*22/any" "$T/sec.tsv"
has "LAN-only rule counted as home network" "1 rule(s) let devices on your home network" "$T/sec.tsv"
sec fix-permissions >/dev/null
check "ai.key now 600" 600 "$(stat -c %a "$SH/.config/prime/ai.key")"
check "~/.config/prime now private" 700 "$(stat -c %a "$SH/.config/prime")"
sec status --tsv > "$T/sec2.tsv"; hasnt "no longer flagged" "Other accounts on this computer can read" "$T/sec2.tsv"
env PRIME_SEC_ROOT="$T/secroot" PRIME_TEST_ALLOW_NONROOT=1 "$LAYER/bin/prime-security" apply >/dev/null 2>&1
has "apply installs the network protections file" "send_redirects = 0" "$T/secroot/etc/sysctl.d/90-prime-security.conf"
hasnt "hardening never disables user namespaces (Flatpak/Steam need them)" "^kernel.unprivileged_userns_clone" "$T/secroot/etc/sysctl.d/90-prime-security.conf"

printf '\n%s%d passed, %d failed%s\n' "$c_b" "$pass" "$fail" "$c_r"
[ "$fail" -eq 0 ]

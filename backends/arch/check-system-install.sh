#!/usr/bin/env bash
# Checks for Prime's system pieces inside a fresh install (run as the new user,
# with passwordless sudo — by test-system-in-container.sh, or by hand in a VM).
#   FULL=1  also runs a real update through prime-update's system step (slow)
set -u
P="$HOME/.local/share/prime-linux"; L="$P/layer"; E=/usr/local/lib/prime-linux/prime-system-update; fail=0
ck() { if eval "$2" >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

ck "updater installed, root-owned, not writable by users" "[ -x $E ] && [ \"\$(stat -c %U:%a $E)\" = root:755 ]"
ck "nightly service + timer installed"            "[ -f /etc/systemd/system/prime-system-update.service ] && [ -f /etc/systemd/system/prime-system-update.timer ]"
ck "timer enabled"                                "[ -L /etc/systemd/system/timers.target.wants/prime-system-update.timer ]"
ck "service runs only root-owned code"            "grep -q '^ExecStart=/usr/local/lib/prime-linux/' /etc/systemd/system/prime-system-update.service"
ck "settings file present and readable"           "grep -q '^POLICY=' /etc/prime/updates.conf"
ck "AUR user recorded"                            "grep -q \"^MAIN_USER=\$(id -un)\" /etc/prime/updates.conf"
ck "backup hook script is the root-owned copy"    "[ \"\$(stat -c %U /usr/share/libalpm/scripts/prime-desktop-backup-all)\" = root ] && ! grep -q 'layer/bin/prime-desktop-backup\"' /usr/share/libalpm/scripts/prime-desktop-backup-all"
ck "network protections installed"                "grep -q send_redirects /etc/sysctl.d/90-prime-security.conf"
ck "system pieces current"                        "bash $L/system/install-system.sh needs-update"
ck "status works without root"                    "$E status | grep -q 'setting:'"
ck "status --json is valid JSON"                  "$E status --json | jq -e .policy"
ck "snapshot report works without root"           "$E snapshots --tsv | grep -qE '^(ok|warn|bad)'"
ck "undo explains in plain words"                 "$E undo | grep -qi 'files'"
ck "policy CLI: get"                              "[ \"\$($L/bin/prime-update-policy get)\" = automatic ]"
ck "policy CLI: set ask, then get"                "$L/bin/prime-update-policy set ask && [ \"\$($L/bin/prime-update-policy get)\" = ask ]"
ck "policy CLI: set automatic again"              "$L/bin/prime-update-policy set automatic && [ \"\$($L/bin/prime-update-policy get)\" = automatic ]"
ck "a stray run refuses to change the system"     "! $E cycle; [ \$? -ne 0 ]; sudo $E cycle; [ \$? = 3 ]"
ck "status line for the menu"                     "$L/bin/prime-updates-settings --status-line | grep -q '^Last update'"
ck "security report runs"                         "$L/bin/prime-security status | grep -q 'Security check'"
ck "security apply is safe to run (and re-run)"   "sudo $L/bin/prime-security apply && sudo $L/bin/prime-security apply"
ck "fix-permissions makes ~/.config/prime private" "$L/bin/prime-security fix-permissions && [ \"\$(stat -c %a ~/.config/prime)\" = 700 ]"
ck "doctor runs to the end"                       "$L/bin/prime-doctor | grep -qE 'healthy|need you'"
ck "pacman hook saves settings as the user"       "sudo pacman -S --noconfirm jq && ls ~/.config-backups/desktop/*_before-update.tar.gz"
ck "…into a private archive"                      "[ \"\$(stat -c %a \"\$(ls -1t ~/.config-backups/desktop/*_before-update.tar.gz | head -1)\")\" = 600 ]"
if [ "${FULL:-0}" = 1 ]; then
  ck "a real update through the updater succeeds" "timeout 1800 sudo env PRIME_ALLOW_REAL_SYSTEM_CHANGES=yes $E apply --manual | tee /tmp/apply.out | grep -Eq '^RESULT (ok|attention)'"
  ck "…and records the result"                    "jq -e '.status' /var/lib/prime-linux/updates/last-run.json"
  ck "…and says it in plain words in the menu"    "$L/bin/prime-updates-settings --status-line | grep -q 'today'"
fi
ck "uninstall removes the system pieces"          "sudo bash $L/system/install-system.sh uninstall && [ ! -e $E ] && [ ! -e /etc/systemd/system/prime-system-update.timer ]"
ck "…and reinstall works"                         "sudo bash $L/system/install-system.sh install --user \$(id -un) && [ -x $E ]"
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail

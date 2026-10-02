#!/usr/bin/env bash
# tests/check-ssh.sh — remote login (SSH) is never switched on by Prime, and an
# SSH that is on, open to every network and taking passwords is reported as a
# problem (the login health check shows it) and narrowed to the home network
# by `prime-security apply` (which the installer runs). No root: systemctl,
# ufw and pacman are fakes on PATH.
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
REPO="$PWD"; L="$REPO/layer"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; pass=$((pass+1)); else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

FB="$T/bin"; mkdir -p "$FB"
# systemctl: sshd is on when $T/sshd-on exists; ufw is enabled when $T/ufw-on exists
cat > "$FB/systemctl" <<EOF
#!/usr/bin/env bash
echo "systemctl \$*" >> "$T/calls"
case "\$*" in
  *firewalld*) exit 1 ;;
  *is-enabled*sshd*|*is-active*sshd*) [ -e "$T/sshd-on" ] ;;
  *is-enabled*ufw*) [ -e "$T/ufw-on" ] ;;
  *disable*sshd*) rm -f "$T/sshd-on" ;;
  *enable*sshd*) touch "$T/sshd-on" ;;
  *) exit 0 ;;
esac
EOF
# ufw: "allow from NET … port 22" appends a LAN tuple; "delete allow 22…" drops the open ones
cat > "$FB/ufw" <<EOF
#!/usr/bin/env bash
echo "ufw \$*" >> "$T/calls"
R="$T/ufw/user.rules"
case "\$*" in
  "allow from "*" port 22 "*) net="\$3"; echo "### tuple ### allow tcp 22 0.0.0.0/0 any \$net in" >> "\$R" ;;
  "--force delete allow 22"|"--force delete allow 22/tcp"|"--force delete allow OpenSSH")
     grep -vE '^### tuple ### allow (any|tcp) 22 [^ ]+ any (0\.0\.0\.0/0|::/0) ' "\$R" > "\$R.n"; mv "\$R.n" "\$R" ;;
esac
exit 0
EOF
printf '#!/usr/bin/env bash\necho "pacman $*" >> "%s/calls"\nexit 0\n' "$T" > "$FB/pacman"
chmod +x "$FB"/*
mkdir -p "$T/ufw" "$T/ssh/sshd_config.d" "$T/home"
echo ENABLED=yes > "$T/ufw/ufw.conf"
SEC=(env PATH="$FB:$PATH" HOME="$T/home" PRIME_UFW_DIR="$T/ufw" PRIME_SSHD_CONFIG="$T/ssh/sshd_config" "$L/bin/prime-security")
status() { "${SEC[@]}" status --tsv 2>/dev/null; }
reset() { rm -f "$T/sshd-on" "$T/ufw-on" "$T/calls"; : > "$T/ufw/user.rules"; rm -f "$T/ssh/sshd_config.d/"*
          printf 'Include /etc/ssh/sshd_config.d/*.conf\n#PasswordAuthentication yes\nKbdInteractiveAuthentication no\n' \
              | sed "s|/etc/ssh|$T/ssh|" > "$T/ssh/sshd_config"; }

echo "== Prime never switches remote login on"
ck "the packages list has no SSH server"        "! grep -qE '^\s*openssh\b' os/arch/packages.txt"
ck "install.sh never enables or starts sshd"    "! grep -nE 'sshd|openssh' install.sh boot.sh"
ck "the system installer never enables sshd"    "! grep -nE 'enable[^#]*sshd' layer/system/install-system.sh layer/bin/prime-update"
ck "only 'prime-security ssh on' enables it"    "[ \"\$(grep -rlE 'systemctl enable[^#]*sshd' layer | sort | tr '\n' ' ')\" = 'layer/bin/prime-security ' ]"

echo "== the owner's machine: SSH on, open to every network, passwords on"
reset; touch "$T/sshd-on" "$T/ufw-on"
echo '### tuple ### allow tcp 22 0.0.0.0/0 any 0.0.0.0/0 in' > "$T/ufw/user.rules"
ck "reported as a problem (bad)"                "status | grep -qP '^bad\tRemote login \(SSH\) is on, open to every network, and accepts passwords'"
ck "the login check passes problems on"         "grep -qF '[ \"\$lvl\" = bad ] && row bad' $L/bin/prime-doctor"
ck "an OpenSSH app rule counts too"             "printf '### tuple ### allow tcp 22 0.0.0.0/0 any 0.0.0.0/0 OpenSSH - in\n' > $T/ufw/user.rules && status | grep -qP '^bad\tRemote login'"
echo '### tuple ### allow tcp 22 0.0.0.0/0 any 0.0.0.0/0 in' > "$T/ufw/user.rules"
env PATH="$FB:$PATH" HOME="$T/home" PRIME_UFW_DIR="$T/ufw" PRIME_SSHD_CONFIG="$T/ssh/sshd_config" \
    PRIME_TEST_ALLOW_NONROOT=1 PRIME_SEC_ROOT="" "$L/bin/prime-security" apply > "$T/apply.out" 2>&1
ck "apply removes the rule for every network"   "! grep -qE 'allow tcp 22 [^ ]+ any 0\.0\.0\.0/0 ' $T/ufw/user.rules"
ck "…and keeps SSH reachable from home"         "grep -q 'allow tcp 22 0.0.0.0/0 any 192.168.0.0/16 in' $T/ufw/user.rules"
ck "…and says so"                               "grep -q 'now your home network only' $T/apply.out"
ck "…and warns about passwords"                 "grep -q 'accepts passwords' $T/apply.out"
ck "…but never turns SSH off by itself"         "[ -e $T/sshd-on ]"
ck "after apply: a warning, not a problem"      "status | grep -qP '^warn\tRemote login \(SSH\) is on and accepts passwords \(your home network only\)'"

echo "== no firewall at all"
reset; touch "$T/sshd-on"
ck "SSH with no firewall is open to everyone"   "status | grep -qP '^bad\tRemote login \(SSH\) is on, open to every network'"

echo "== reading sshd's settings like sshd does (first value wins, Include first)"
reset; touch "$T/sshd-on" "$T/ufw-on"
echo 'PasswordAuthentication no' > "$T/ssh/sshd_config.d/10-keys.conf"
echo 'PasswordAuthentication yes' >> "$T/ssh/sshd_config"
ck "drop-in 'no' beats a later 'yes'"           "status | grep -qP '^warn\tRemote login \(SSH\) is on \(your home network only, keys only\)'"
reset; touch "$T/sshd-on" "$T/ufw-on"
echo 'PasswordAuthentication yes' > "$T/ssh/sshd_config.d/10-pw.conf"
echo 'PasswordAuthentication no' >> "$T/ssh/sshd_config"
ck "drop-in 'yes' beats a later 'no'"           "status | grep -qP 'accepts passwords'"
reset; touch "$T/sshd-on" "$T/ufw-on"
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication yes\n' > "$T/ssh/sshd_config.d/10.conf"
ck "keyboard-interactive counts as passwords"   "status | grep -qP 'accepts passwords'"
reset; touch "$T/sshd-on" "$T/ufw-on"
printf 'Match User alex\n    PasswordAuthentication no\n' >> "$T/ssh/sshd_config"
ck "a Match block doesn't count for everyone"   "status | grep -qP 'accepts passwords'"

echo "== off is off"
reset; touch "$T/ufw-on"
ck "SSH off is reported as fine"                "status | grep -qP '^ok\tRemote login \(SSH\) is off'"

echo
[ $fail = 0 ] && echo "ALL PASSED ($pass)" || echo "$fail FAILED"
exit $fail

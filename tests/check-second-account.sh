#!/usr/bin/env bash
# tests/check-second-account.sh <before|installed|left> — run as root inside the
# install container (tests/install-in-container.sh): alex installed Prime first,
# then sam installs on the same computer, then sam uninstalls with --packages.
set -u
STEP="${1:?before|installed|left}"; fail=0
ck() { if eval "$2" >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
SNAP=/root/alex-before.sha
alex_files() { find /home/alex/.config/hypr /home/alex/.config/prime /home/alex/.local/share/prime-linux/layer -type f \
                 ! -path '*/__pycache__/*' -print0 2>/dev/null | sort -z | xargs -0 sha256sum; }
case "$STEP" in
  before)
    alex_files > "$SNAP" ;;
  installed)
    ck "sam has their own desktop config"         "grep -q prime-linux /home/sam/.config/hypr/hyprland.conf"
    ck "sam has their own copy of Prime"          "[ -x /home/sam/.local/share/prime-linux/layer/bin/prime-menu ] && [ \$(stat -c %U /home/sam/.local/share/prime-linux) = sam ]"
    ck "alex is still the computer's main account" "grep -qx MAIN_USER=alex /etc/prime/updates.conf"
    ck "nothing of alex's was touched"            "alex_files | cmp -s - $SNAP"
    ck "sam's add-ons list is sam's own"          "[ \$(stat -c %U /home/sam/.config/prime/addons) = sam ]" ;;
  left)
    ck "sam's Prime is gone"                      "[ ! -d /home/sam/.local/share/prime-linux ]"
    ck "nightly updates stay (alex uses them)"    "[ -x /usr/local/lib/prime-linux/prime-system-update ] && [ -f /etc/systemd/system/prime-system-update.timer ]"
    ck "the backup hook stays"                    "[ -f /etc/pacman.d/hooks/zz-prime-desktop-backup.hook ]"
    ck "Prime stays on the login screen"          "[ -f /usr/share/wayland-sessions/prime.desktop ]"
    ck "--packages left alex's desktop installed" "pacman -Qq hyprland waybar rofi >/dev/null"
    ck "alex is still the main account"           "grep -qx MAIN_USER=alex /etc/prime/updates.conf"
    ck "nothing of alex's was touched"            "alex_files | cmp -s - $SNAP" ;;
esac
[ "$STEP" = before ] && exit 0
echo; [ $fail = 0 ] && echo "ALL PASSED ($STEP)" || echo "$fail FAILED ($STEP)"; exit $fail

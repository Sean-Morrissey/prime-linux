#!/usr/bin/env bash
# Runs prime-uninstall and checks the account is back to how it was before
# Prime (install-in-container.sh runs this after check-install.sh).
# Expects the test's "before" state: a kitty.conf and an nm-applet autostart
# entry containing "before-prime",
# no hyprland.conf, and the gsettings snapshot in /tmp/gsettings-before.
set -u
fail=0
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

"$HOME/.local/share/prime-linux/layer/bin/prime-uninstall" --yes
echo
ck "Prime's copy is gone"                    "[ ! -e ~/.local/share/prime-linux ]"
ck "your old kitty.conf is back"             "grep -q before-prime ~/.config/kitty/kitty.conf"
ck "files Prime created are gone"            "[ ! -e ~/.config/hypr/hyprland.conf ] && [ ! -e ~/.config/hypr/keyboard.conf ] && [ ! -e ~/.config/hypr/monitors.conf ] && [ ! -e ~/.config/hypr/hardware.conf ]"
ck "no Prime services or commands left"      "! ls -d ~/.config/systemd/user/prime-* ~/.config/systemd/user/swaync.service.d ~/.local/bin/prime-* 2>/dev/null | grep -q ."
ck "no Prime app-list entries left"          "! ls ~/.local/share/applications/prime-* 2>/dev/null | grep -q ."
ck "your own nm-applet autostart is back"    "grep -q 'before-prime' ~/.config/autostart/nm-applet.desktop && ! grep -q 'hidden by Prime' ~/.config/autostart/nm-applet.desktop"
ck "GTK theme/icons/fonts restored"          "for k in gtk-theme icon-theme font-name; do [ \"\$(gsettings get org.gnome.desktop.interface \$k)\" = \"\$(grep \"^\$k \" /tmp/gsettings-before | cut -d' ' -f2-)\" ] || exit 1; done"
ck "Prime settings kept in backups"          "ls -d ~/.config-backups/prime-settings-*"
ck "update hook removed"                     "[ ! -e /etc/pacman.d/hooks/zz-prime-desktop-backup.hook ]"
ck "Prime is off the login screen"           "[ ! -e /usr/share/wayland-sessions/prime.desktop ]"
ck "login screen Prime enabled is off again" "[ ! -L /etc/systemd/system/display-manager.service ]"
ck "install record cleared"                  "[ ! -e ~/.local/state/prime/install.manifest ]"
echo; [ $fail = 0 ] && echo "UNINSTALL: ALL PASSED" || echo "UNINSTALL: $fail FAILED"; exit $fail

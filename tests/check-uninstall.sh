#!/usr/bin/env bash
# This test installs and removes Prime for real, so it runs only on a throwaway machine
# (the containers of tests/install-in-container.sh and packs-in-container.sh, or CI) —
# never on someone's own account. (Run there, it once put back a months-old desktop.)
if [ ! -f /.dockerenv ] && [ ! -f /run/.containerenv ] && [ "${GITHUB_ACTIONS:-}" != true ] \
        && [ "${PRIME_TEST_THROWAWAY:-}" != 1 ]; then
    echo "  SKIP  installs and removes Prime for real: runs in tests/install-in-container.sh or on CI"
    exit 0
fi
# Runs prime-uninstall and checks the account is back to how it was before
# Prime (install-in-container.sh runs this after check-install.sh).
# Expects the test's "before" state: a kitty.conf and an nm-applet autostart
# entry containing "before-prime",
# no hyprland.conf, and the gsettings snapshot in /tmp/gsettings-before.
set -u
fail=0
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }

# the person's own edits since installing, which removing Prime must not destroy
echo "# my own line, added after installing" >> ~/.config/hypr/hyprland.conf
echo "# my own screen rule" >> ~/.config/hypr/hardware.conf
echo "# my own terminal tweak" >> ~/.config/kitty/kitty.conf
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
ck "your edits to files it removed are saved" "grep -q 'my own line' ~/.config-backups/prime-uninstall-*/.config/hypr/hyprland.conf && grep -q 'my own screen rule' ~/.config-backups/prime-uninstall-*/.config/hypr/hardware.conf"
ck "…and to files it put back"               "grep -q 'my own terminal tweak' ~/.config-backups/prime-uninstall-*/.config/kitty/kitty.conf"
ck "update hook removed"                     "[ ! -e /etc/pacman.d/hooks/zz-prime-desktop-backup.hook ]"
ck "Prime is off the login screen"           "[ ! -e /usr/share/wayland-sessions/prime.desktop ]"
ck "login screen Prime enabled is off again" "[ ! -L /etc/systemd/system/display-manager.service ]"
ck "install record cleared"                  "[ ! -e ~/.local/state/prime/install.manifest ]"
echo; [ $fail = 0 ] && echo "UNINSTALL: ALL PASSED" || echo "UNINSTALL: $fail FAILED"; exit $fail

# shellcheck shell=bash
# tests/sandbox.sh — sourced first by every tests/check-*.sh.
#
# The tests run Prime's installer, uninstaller, theme and settings tools. Run on a
# developer's own computer without this, they changed that person's real desktop
# (it happened: an uninstall test put back a months-old config). So, before any
# test line runs:
#   * HOME and XDG_RUNTIME_DIR are throwaway folders (the real ones are never named),
#   * the live session is out of reach: no session D-Bus, no Hyprland socket, no
#     Wayland socket, GSettings in memory,
#   * commands that act on the whole computer or on running programs (sudo, pkill,
#     loginctl, nmcli…) are stand-ins that do nothing.
# Tests that need fakes of their own still put them first on PATH, as before.
#
# On CI (a throwaway machine) only the folders are swapped: the runner's sudo and
# services are what the install tests exercise there.
[ "${PRIME_TEST_SANDBOX:-}" = 1 ] && return 0
export PRIME_TEST_SANDBOX=1
_sb="$(mktemp -d "${TMPDIR:-/tmp}/prime-test.XXXXXX")"
mkdir -p "$_sb/home/.local/share/applications" "$_sb/run" "$_sb/shims"
# the leak scan (check-portable) reads the owner's private name patterns: point at them, read-only
if [ -f "$HOME/.config/prime/author-patterns.json" ]; then
    export PRIME_AUTHOR_PATTERNS="${PRIME_AUTHOR_PATTERNS:-$HOME/.config/prime/author-patterns.json}"
fi
chmod 700 "$_sb/run"
# the GUI self-tests want some installed apps to list: copies, never links
cp "$HOME"/.local/share/applications/*.desktop "$_sb/home/.local/share/applications/" 2>/dev/null || true
export HOME="$_sb/home" XDG_RUNTIME_DIR="$_sb/run" GSETTINGS_BACKEND=memory
unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
unset DBUS_SESSION_BUS_ADDRESS HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY
if [ "${GITHUB_ACTIONS:-}" != true ]; then
    for _c in sudo pkill killall loginctl nmcli bluetoothctl powerprofilesctl brightnessctl \
              timedatectl hyprctl hyprpm swaync-client notify-send; do
        printf '#!/bin/sh\n# test sandbox: %s does nothing here\nexit 1\n' "$_c" > "$_sb/shims/$_c"
        chmod +x "$_sb/shims/$_c"
    done
    export PATH="$_sb/shims:$PATH"
fi
trap 'rm -rf "$_sb"' EXIT
unset _c

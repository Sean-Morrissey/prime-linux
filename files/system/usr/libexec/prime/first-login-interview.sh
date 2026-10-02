#!/usr/bin/env bash
# Open the first-run interview in a terminal, exactly once.
#
# The distro's promise is "tell Prime who you are and it sets the machine up for you",
# so this has to be the first thing that happens after someone logs in — not a menu
# item they have to find. It runs on the first graphical login, checks whether the
# interview has already been completed, and if not, opens a terminal running it.
#
# It is deliberately easy to escape: 'skip' through the questions, or run this once
# with --decline to stop it appearing again. A setup wizard you cannot get rid of is
# the reason people hate setup wizards.

set -u

IDENTITY="$HOME/.config/prime/identity.yaml"
DECLINED="$HOME/.config/prime/.interview-declined"

if [ "${1:-}" = "--decline" ]; then
  mkdir -p "$(dirname "$DECLINED")" && touch "$DECLINED"
  echo "the interview will not appear again (run 'prime-setup' whenever you want it)"
  exit 0
fi

# already done, or already refused
[ -e "$IDENTITY" ] && exit 0
[ -e "$DECLINED" ] && exit 0

# A terminal, whatever this desktop calls one. If none of these exist we exit quietly
# rather than throwing an error box at somebody on their first login.
SETUP="/usr/libexec/prime/prime-setup"
HOLD='echo; printf "  press Enter to close this window... "; read -r _'

run_terminal() {
  case "$1" in
    konsole)         exec konsole --hold -e bash -c "$SETUP; $HOLD" ;;
    gnome-terminal)  exec gnome-terminal -- bash -c "$SETUP; $HOLD" ;;
    kgx)             exec kgx -- bash -c "$SETUP; $HOLD" ;;
    kitty)           exec kitty bash -c "$SETUP; $HOLD" ;;
    foot)            exec foot bash -c "$SETUP; $HOLD" ;;
    alacritty)       exec alacritty -e bash -c "$SETUP; $HOLD" ;;
    wezterm)         exec wezterm start -- bash -c "$SETUP; $HOLD" ;;
    xterm)           exec xterm -hold -e bash -c "$SETUP; $HOLD" ;;
  esac
}

for t in konsole gnome-terminal kgx kitty foot alacritty wezterm xterm; do
  if command -v "$t" >/dev/null 2>&1; then
    run_terminal "$t"
    exit 0
  fi
done

# No terminal found: say so in the session log rather than failing silently.
logger -t prime "no terminal emulator found for the first-run interview" 2>/dev/null || true
exit 0

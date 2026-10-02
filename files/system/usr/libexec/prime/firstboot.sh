#!/usr/bin/env bash
# Prime Linux first-boot wizard.
# Runs ONCE per install, as root. It must never contain or fetch API keys:
# each user connects their own account on their own machine.
set -euo pipefail

MARKER=/var/lib/prime/firstboot.done
[ -e "$MARKER" ] && exit 0

install -d -m 0755 /var/lib/prime
install -d -m 0755 /etc/skel/College

# Student scaffolding every new account inherits (via /etc/skel).
for d in Autumn-2026 dashboard notes assignments; do
  install -d -m 0755 "/etc/skel/College/$d"
done

# Plain-language welcome for someone who has never used Linux.
if [ -d /home ] && ! [ -e /etc/skel/.config/prime/WELCOME.txt ]; then
  install -d -m 0755 /etc/skel/.config/prime
  cat > /etc/skel/.config/prime/WELCOME.txt <<'EOF'
Prime Linux — you're set up.

Two sessions are available from the login screen:
  1. "Desktop" (KDE Plasma) — the normal point-and-click desktop. Start here.
  2. "Prime" (Hyprland)   — the keyboard-driven power mode.

Your machine updates itself as a whole image. If an update ever misbehaves,
reboot, and pick the previous entry from the boot menu — you are back in
seconds, nothing is lost.

Next step: run "prime setup" to connect the assistant to your own AI account.
EOF
fi

date -u +%FT%TZ > "$MARKER"

# Tell whoever is logged in that setup is waiting.
runuser -u "$(logname 2>/dev/null || echo root)" -- \
  notify-send -i dialog-information "Prime Linux" \
  "Welcome. Run 'prime setup' to connect your assistant." 2>/dev/null || true

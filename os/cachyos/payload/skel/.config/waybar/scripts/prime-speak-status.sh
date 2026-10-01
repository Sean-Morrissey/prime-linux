#!/usr/bin/env bash
# Waybar module: is Prime going to read this reply out loud?
#    muted -> 󰖁  (flag file present)
#    on    -> 󰕾  (service running, no flag)
#    warn  -> 󰕾  (flag absent but the service is dead)
# One stat + one pgrep per second; never asks the agent anything.
set -u

FLAG="${HOME}/.hermes/prime-speak.muted"

if [ -f "$FLAG" ]; then
  printf '{"text":"󰖁","class":"muted","tooltip":"Voice OFF — Prime stays silent\\n\\nClick: turn spoken replies back on"}\n'
  exit 0
fi

if pgrep -f 'scripts/prime-speak\.py' >/dev/null 2>&1; then
  printf '{"text":"󰕾","class":"on","tooltip":"Voice ON — Prime reads replies aloud\\n\\nClick: silence it"}\n'
else
  printf '{"text":"󰕾","class":"warn","tooltip":"Voice ON but prime-speak.service is NOT running\\n\\nLeft-click: toggle flag · Right-click: restart the service"}\n'
fi

#!/usr/bin/env bash
# Prime push-to-talk — legacy entry point.
#
# Super+R is now hold-to-talk: Hyprland runs prime-ptt-down.sh on press and
# prime-ptt-up.sh on release. This script is kept so older references (and a
# manual `bash prime-ptt.sh` from a terminal) still start listening, but it is
# no longer bound to a key.
set -u
exec bash "$(dirname "$0")/prime-ptt-down.sh"

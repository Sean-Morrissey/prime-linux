#!/usr/bin/env bash
REAL_HOME="$HOME"
. "$(dirname "${BASH_SOURCE[0]}")/sandbox.sh"   # never the real home or session (tests/sandbox.sh)
# tests/check-sandbox.sh — every test runs away from the real home and the live session.
fail=0
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
ck "HOME is a throwaway folder"                       "[ \"\$HOME\" != '$REAL_HOME' ] && case \"\$HOME\" in \"\${TMPDIR:-/tmp}\"/prime-test.*) true ;; *) false ;; esac"
ck "the runtime folder is a throwaway too"            "[ \"\$XDG_RUNTIME_DIR\" = \"\$(dirname \"\$HOME\")/run\" ]"
ck "no session bus, Hyprland or Wayland socket"       "[ -z \"\${DBUS_SESSION_BUS_ADDRESS:-}\${HYPRLAND_INSTANCE_SIGNATURE:-}\${WAYLAND_DISPLAY:-}\" ]"
ck "systemctl --user can't reach the real session"    "! systemctl --user is-system-running"
if [ "${GITHUB_ACTIONS:-}" != true ]; then
    ck "sudo and pkill do nothing"                    "! sudo true && ! pkill -0 bash"
fi
ck "every check-*.sh loads the sandbox or runs only on a throwaway machine" "! grep -LE 'tests/sandbox.sh|throwaway machine' $(dirname "$0")/check-*.sh | grep -q ."
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail

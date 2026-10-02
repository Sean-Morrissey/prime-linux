#!/usr/bin/env bash
# tests/check-update-private.sh — "Update everything" on a friend's machine
# installed from the PRIVATE repo, without a GitHub login: it must not hang
# waiting for a username nobody can type (it runs in a window), and must say
# how to sign in. git is a fake on PATH that answers like GitHub does.
# No display variables: run from a desktop session the updater would otherwise
# open its window (and reload Hyprland) on the real screen.
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fail=0
ck() { if ( eval "$2" ) >/dev/null 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; fail=$((fail+1)); fi; }
mkdir -p "$T/bin" "$T/home"
REAL_GIT="$(command -v git)"
cat > "$T/bin/git" <<FAKE
#!/usr/bin/env bash
for a in "\$@"; do
  if [ "\$a" = pull ] || [ "\$a" = fetch ]; then
    # real git would prompt on the terminal here unless told not to
    [ "\${GIT_TERMINAL_PROMPT:-1}" = 0 ] || { sleep 90; exit 1; }
    echo "fatal: could not read Username for 'https://github.com': terminal prompts disabled" >&2; exit 128
  fi
done
exec "$REAL_GIT" "\$@"
FAKE
chmod +x "$T/bin/git"
start=$(date +%s)
env -u GIT_TERMINAL_PROMPT -u GIT_ASKPASS -u WAYLAND_DISPLAY -u DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE HOME="$T/home" PATH="$T/bin:$PATH" PRIME_NO_LIVE=1 PRIME_NO_GSETTINGS=1 \
    timeout 120 bash layer/bin/prime-update --prime > "$T/out" 2>&1 </dev/null
took=$(( $(date +%s) - start ))
ck "doesn't wait for a username (finished in ${took}s)" "[ $took -lt 60 ]"
ck "says GitHub didn't let it in"                      "grep -q \"GitHub didn't let this computer in\" $T/out"
ck "says how to sign in (gh auth login)"               "grep -q 'gh auth login' $T/out"
[ $fail = 0 ] || sed 's/^/      | /' "$T/out" | tail -20
echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail

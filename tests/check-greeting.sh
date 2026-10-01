#!/usr/bin/env bash
# tests/check-greeting.sh — the terminal greeting spells P.R.I.M.E
# (Please Relax I'll Manage Everything). No install needed: throwaway HOMEs only.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; L="$REPO/layer"; fail=0
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ck() { if eval "$2" >"$T/out" 2>&1; then echo "  PASS  $1"; else echo "  FAIL  $1"; sed 's/^/          /' "$T/out" | tail -6; fail=$((fail+1)); fi; }
LOGO="$L/branding/terminal/prime-logo.txt"; PLAIN="$L/branding/terminal/prime-logo.plain.txt"
MIG="$(grep -l 'spells P.R.I.M.E' "$L"/migrations/*.sh)"

echo "== the logo"
ck "the generator reproduces both files exactly" \
   "cp -r $L/branding $T/b && python3 $T/b/src/make-terminal-logo.py >/dev/null && cmp $T/b/terminal/prime-logo.txt $LOGO && cmp $T/b/terminal/prime-logo.plain.txt $PLAIN"
ck "at most 16 lines and 40 columns"        "[ \$(wc -l < $PLAIN) -le 16 ] && [ \$(awk '{ if (length > m) m = length } END { print m }' $PLAIN) -le 40 ]"
ck "the words read across, in order"         "[ \"\$(grep -oE '[a-z'\\'']+\$' $PLAIN | paste -sd' ')\" = \"lease elax 'll anage verything\" ]"
ck "one gradient colour per letter, in order" "[ \"\$(grep -oE '38;2;[0-9;]+m' $LOGO | uniq | paste -sd' ')\" = '38;2;96;165;250m 38;2;115;158;250m 38;2;134;152;251m 38;2;154;145;251m 38;2;192;132;252m' ]"
ck "the plain copy has no colour codes"       "! grep -q \$'\\x1b' $PLAIN"
ck "the old meaning is gone everywhere"        "! grep -rIiE 'persistent · resident|memory engine' $REPO --exclude-dir=.git --exclude=check-greeting.sh"

echo "== fastfetch"
CONF="$L/seed/fastfetch/config.jsonc"
ck "Prime's config parses and shows the logo"  "python3 -c \"import json,re,sys; d=json.loads(re.sub(r'(?m)^\\s*//.*\$','',open('$CONF').read())); l=d['logo']; assert l['source'].endswith('prime/prime-logo.txt') and l['height']==15 and l['padding']['top']>0\""
ck "it is marked as Prime's (uninstall removes it)" "grep -q prime-linux $CONF"
ck "the theme refresh puts the logo in place" \
   "HOME=$T/h1 PRIME_NO_GSETTINGS=1 bash $L/bin/prime-theme --apply >/dev/null 2>&1; cmp $T/h1/.config/prime/prime-logo.txt $LOGO && cmp $T/h1/.config/prime/prime-logo.plain.txt $PLAIN"

echo "== a new terminal shows it (any shell, never twice)"
G="$T/g"; mkdir -p "$G/bin" "$G/home"
printf '#!/bin/sh\necho GREETING\n' > "$G/bin/fastfetch"
for s in bash zsh fish; do printf '#!/bin/sh\necho SHELL-RAN\n' > "$G/bin/$s"; done
printf '#!/bin/sh\necho "$PATH"\n' > "$G/bin/pathsh"
chmod +x "$G/bin"/*
term() { env -u KITTY_WINDOW_ID HOME="$G/home" PATH="$G/bin:$PATH" SHELL="$G/bin/$1" "${@:2}" /bin/bash $L/bin/prime-terminal-shell; }
ck "bash with no greeting of its own: greeting, then the shell" "[ \"\$(term bash | paste -sd' ')\" = 'GREETING SHELL-RAN' ]"
ck "zsh too"                                   "[ \"\$(term zsh | paste -sd' ')\" = 'GREETING SHELL-RAN' ]"
ck "a shell that already greets: only once"    "echo fastfetch > $G/home/.bashrc && [ \"\$(term bash | paste -sd' ')\" = 'SHELL-RAN' ]; rm -f $G/home/.bashrc"
ck "a commented-out greeting doesn't count"    "echo '# fastfetch' > $G/home/.bashrc && term bash | grep -q GREETING; rm -f $G/home/.bashrc"
ck "fish with CachyOS-style greeting: once"    "mkdir -p $G/home/.config/fish && printf 'function fish_greeting\n  fastfetch\nend\n' > $G/home/.config/fish/config.fish && [ \"\$(term fish | paste -sd' ')\" = 'SHELL-RAN' ]"
ck "PRIME_NO_GREETING=1 switches it off"       "[ \"\$(term bash env PRIME_NO_GREETING=1 | paste -sd' ')\" = 'SHELL-RAN' ]"
ck "Prime's commands are on PATH in it"         "term pathsh env PRIME_NO_GREETING=1 | grep -q \"^$G/home/.local/bin:\""
ck "the theme makes kitty start it"            "HOME=$T/h1 PRIME_NO_GSETTINGS=1 bash $L/bin/prime-theme --apply >/dev/null 2>&1; grep -qx \"shell *\\\"$L/bin/prime-terminal-shell\\\"\" $T/h1/.config/prime/theme/kitty.conf"

echo "== upgrading an existing install ($(basename "$MIG"))"
run_mig() { HOME="$1" PRIME_LAYER="$L" bash -eu "$MIG"; }
ck "no fastfetch config yet: Prime's is added" "mkdir -p $T/h2 && run_mig $T/h2 && cmp $T/h2/.config/fastfetch/config.jsonc $CONF && [ -s $T/h2/.config/prime/prime-logo.txt ]"
ck "the earlier hand-made greeting: backed up, replaced" \
   "mkdir -p $T/h3/.config/fastfetch && echo '{\"logo\":{\"source\":\"~/.config/prime/prime-logo.txt\"}}' > $T/h3/.config/fastfetch/config.jsonc && run_mig $T/h3 && cmp $T/h3/.config/fastfetch/config.jsonc $CONF && ls $T/h3/.config-backups/*/fastfetch/config.jsonc"
ck "someone's own fastfetch config: left alone" \
   "mkdir -p $T/h4/.config/fastfetch && echo '{\"logo\":\"arch\"}' > $T/h4/.config/fastfetch/config.jsonc && run_mig $T/h4 && grep -q arch $T/h4/.config/fastfetch/config.jsonc"
ck "running it twice changes nothing"          "run_mig $T/h3 && cmp $T/h3/.config/fastfetch/config.jsonc $CONF && [ \$(ls -d $T/h3/.config-backups/* | wc -l) = 1 ]"
ck "a fresh install seeds it (only if absent)" "grep -q 'create \"\$HOME/.config/fastfetch/config.jsonc\"' $REPO/install.sh"
ck "About says what Prime means"              "PRIME_PANEL=1 bash $L/bin/prime-about | grep -q \"P.R.I.M.E — Please Relax I'll Manage Everything\""

echo; [ $fail = 0 ] && echo "ALL PASSED" || echo "$fail FAILED"; exit $fail

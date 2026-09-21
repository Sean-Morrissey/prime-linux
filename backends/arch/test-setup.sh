#!/usr/bin/env bash
# Proves the first-run interview: scripted answers in, a valid identity file, course
# folders and an honest record of where the person disagreed with the suggestion.
# Nothing here touches a real home directory — it all lands under a temp dir.
#
# Run: ./test-setup.sh

set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP="$SELF_DIR/prime-setup"
ROOT="${TMPDIR:-/tmp}/prime-setup-test.$$"
pass=0; fail=0

c_reset=$'\033[0m'; c_ok=$'\033[32m'; c_bad=$'\033[31m'; c_b=$'\033[1m'; c_dim=$'\033[2m'
head() { printf '\n%s%s%s\n' "$c_b" "$*" "$c_reset"; }
good() { printf '  %s✓%s %s\n' "$c_ok" "$c_reset" "$*"; pass=$((pass+1)); }
nope() { printf '  %s✗%s %s\n' "$c_bad" "$c_reset" "$*"; fail=$((fail+1)); }
has() { # has <file> <pattern> <description>
  if grep -qE "$2" "$1" 2>/dev/null; then good "$3"; else nope "$3 (no /$2/ in $(basename "$1"))"; fi
}
hasnt() {
  if grep -qE "$2" "$1" 2>/dev/null; then nope "$3 (found /$2/)"; else good "$3"; fi
}

mkdir -p "$ROOT"
CFG="$ROOT/config"; COLLEGE="$ROOT/college"
# The answers fixture lives in testdata/ so a person can reproduce any of this by
# hand: ./prime-setup --answers testdata/setup-answers.txt
ANSWERS="$SELF_DIR/testdata/setup-answers.txt"
[ -r "$ANSWERS" ] || { echo "missing fixture: $ANSWERS" >&2; exit 1; }

head "1. a scripted interview produces a valid identity file"
PRIME_SETUP_QUIET=1 "$SETUP" --answers "$ANSWERS" --config-dir "$CFG" --college-dir "$COLLEGE" >"$ROOT/out.txt" 2>&1
rc=$?
[ "$rc" = "0" ] && good "exits cleanly" || { nope "exit code $rc"; sed 's/^/    /' "$ROOT/out.txt" | tail -8; }
[ -s "$CFG/identity.yaml" ] && good "wrote identity.yaml" || nope "no identity.yaml"
python3 -c "
import yaml,sys
d=yaml.safe_load(open('$CFG/identity.yaml'))
assert d['name']=='Alex', d['name']
assert d['pronouns']=='they/them', d['pronouns']       # took the suggestion
assert d['term']=='Autumn-2026'
assert len(d['courses'])==2, d['courses']
assert d['courses'][0]['code']=='MATH-1099', d['courses'][0]
assert d['courses'][0]['name']=='Bridge to College Math', d['courses'][0]
assert d['preferences']['session']=='prime'
assert d['preferences']['accessibility']['text_scale']=='huge'   # overrode the suggestion
assert d['preferences']['autonomy']=='suggest', d['preferences']['autonomy']
assert d['preferences']['voice'] is False        # booleans stay booleans in the schema
assert d['agent']['connected']=='later'
assert d['agent']['monthly_cap_usd']==10
assert 'worked examples' in d['freeform']
print('parsed ok')
" >"$ROOT/yaml.log" 2>&1
if grep -q "parsed ok" "$ROOT/yaml.log"; then good "parses as YAML and every answer is where it belongs"
else nope "YAML check failed"; sed 's/^/    /' "$ROOT/yaml.log" | tail -5; fi

head "2. timestamps are quoted (an unquoted YAML date is a datetime, not a string)"
has "$CFG/identity.yaml" '^created: "' "created is quoted"
has "$CFG/identity.yaml" '^updated: "' "updated is quoted"

head "3. answers never contain a credential"
hasnt "$CFG/identity.yaml" 'sk-|api[_-]?key|token|password' "no key material in the identity file"
hasnt "$CFG/identity.yaml" 'anthropic|openai|deepseek|google' "no provider names either"

head "4. course folders exist and are named after the courses"
[ -d "$COLLEGE/Autumn-2026/MATH-1099" ] && good "MATH-1099 folder created" || nope "MATH-1099 folder missing"
[ -d "$COLLEGE/Autumn-2026/ENGL-0155" ] && good "ENGL-0155 folder created" || nope "ENGL-0155 folder missing"
[ -s "$COLLEGE/Autumn-2026/MATH-1099/README.md" ] && good "each course has a README to work in" || nope "README missing"

head "5. what got remembered is where they disagreed"
has "$CFG/answers.log" '"outcome":"chose their own"' "recorded an override as a strong signal"
has "$CFG/answers.log" '"outcome":"took the suggestion"' "recorded an accepted default as a weak one"
overrides=$(grep -c '"outcome":"chose their own"' "$CFG/answers.log" 2>/dev/null)
overrides=${overrides:-0}
[ "$overrides" -ge 2 ] && good "$overrides overrides captured for the pattern learner" \
  || nope "expected at least 2 overrides, saw $overrides"

head "6. re-running one beat does not throw the rest away"
"$SETUP" --answers <(printf 'Spring-2027\n') --beats 2 --config-dir "$CFG" --college-dir "$COLLEGE" >/dev/null 2>&1
python3 -c "
import yaml
d=yaml.safe_load(open('$CFG/identity.yaml'))
assert d['name']=='Alex', 'name was lost'
assert d['preferences']['accessibility']['text_scale']=='huge', 'preferences were lost'
assert d['created'], 'created timestamp was lost'
print('ok')" >"$ROOT/re.log" 2>&1
grep -q ok "$ROOT/re.log" && good "one beat re-run, everything else intact" || { nope "re-run damaged the file"; sed 's/^/    /' "$ROOT/re.log" | tail -4; }

head "7. a blank interview still produces a working machine"
printf '\n\n\n\n\n\n\n\n\n\n\n\n\n\n\nEND\n' > "$ROOT/blank.txt"
"$SETUP" --answers "$ROOT/blank.txt" --config-dir "$ROOT/blankcfg" --college-dir "$ROOT/blankcol" >/dev/null 2>&1
python3 -c "
import yaml
d=yaml.safe_load(open('$ROOT/blankcfg/identity.yaml'))
assert d['name'], 'a name is required even if it is just the username'
assert d['preferences']['theme']=='dark'
assert d['courses']==[]
print('ok')" >"$ROOT/blank.log" 2>&1
grep -q ok "$ROOT/blank.log" && good "answered nothing, still got a usable machine" \
  || { nope "blank run did not produce a usable file"; sed 's/^/    /' "$ROOT/blank.log" | tail -4; }

printf '\n%s%d passed, %d failed%s   %s(work dir: %s)%s\n' \
  "$c_b" "$pass" "$fail" "$c_reset" "$c_dim" "$ROOT" "$c_reset"
rm -rf "$ROOT"
[ "$fail" -eq 0 ]

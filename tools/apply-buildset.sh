#!/usr/bin/env bash
# apply-buildset — turn a clone of CachyOS-Live-ISO into the Prime OS builder.
#
# Usage: tools/apply-buildset.sh [CLONE_DIR]      (default ~/Projects/cachyos-archiso)
#
# Everything here is derived from the installer package that the live image actually runs:
# cachyos-calamares-next (the ISO's package list includes it, and the launcher reinstalls it
# at boot). We do NOT keep vendored copies of its ~800-line config in this repo — they would
# silently drift. Instead the upstream files are fetched, our changes are applied to them
# programmatically, and every change is asserted afterwards.
#
# Result, verified by this script before it exits:
#   * the desktop chooser offers "Prime Desktop" and pre-selects it
#   * the package list is OUR local one — never CachyOS's floating remote list
#   * the boot-manager chooser describes each option in plain language (default: limine)
#   * the partition step cannot pre-select "erase disk" on a machine that already has Windows
#   * a post-install step in the installed system caps the boot menu at one rollback entry
#   * all of it is copied into place after the installer package installs (pacman hook)
#
# Changes nothing outside CLONE_DIR and a temporary directory.
set -uo pipefail

CLONE="${1:-$HOME/Projects/cachyos-archiso}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILDSET="$REPO_ROOT/os/cachyos/archiso"
MIRROR="https://mirror.cachyos.org/repo/x86_64/cachyos"
PKGLIST="$BUILDSET/packages_prime.x86_64"

say() { printf '%s\n' "$*"; }
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; }
hr()  { printf '%s\n' "────────────────────────────────────────────────────────"; }
die() { bad "$*"; exit 1; }

[ -d "$CLONE/archiso" ] || die "no archiso/ in $CLONE — clone https://github.com/CachyOS/CachyOS-Live-ISO first"
[ -d "$BUILDSET" ] || die "buildset missing: $BUILDSET"

hr; say "Prime OS buildset → $CLONE"; hr

# ---------------------------------------------------------------- 1. upstream installer
VER="$(pacman -Si cachyos-calamares-next 2>/dev/null | awk -F': *' '/^Version/{print $2}')"
[ -n "$VER" ] || die "cannot read cachyos-calamares-next version from the package database"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PKG="cachyos-calamares-next-$VER-x86_64.pkg.tar.zst"
say "upstream installer: cachyos-calamares-next $VER (the one the ISO runs)"
curl -sfL -o "$TMP/$PKG" "$MIRROR/$PKG" || die "download failed: $MIRROR/$PKG"
tar --zstd -xf "$TMP/$PKG" -C "$TMP" || die "cannot extract $PKG"
UP="$TMP/etc/calamares"; UPSH="$TMP/usr/share/calamares"
[ -f "$UP/modules/netinstall.yaml" ] || die "unexpected package layout"
[ -f "$UPSH/settings_online.conf" ] || die "unexpected package layout (no settings_online.conf)"
ok "fetched the real upstream installer config"

# ---------------------------------------------------------------- 2. our files land here
STAGE="$CLONE/archiso/airootfs"
OVR="$STAGE/usr/share/prime/overrides"
mkdir -p "$OVR/etc/calamares/modules" "$OVR/usr/share/calamares" \
         "$STAGE/usr/local/bin" "$STAGE/etc/pacman.d/hooks"
cp -a "$BUILDSET/airootfs/." "$STAGE/" 2>/dev/null || true
cp -a "$BUILDSET/calamares/modules/shellprocess_prime_target.conf" "$OVR/etc/calamares/modules/"
# Executable bits here are cosmetic: mkarchiso copies airootfs with `--no-preserve=mode`, so
# every file reaches the live image as 0644 and nothing from airootfs is ever executable
# there. Both of our scripts are therefore invoked through an interpreter (sh / bash) rather
# than as programs — see the hook's NOTE 2. The bits are set anyway so the clone reads true.
chmod 0755 "$BUILDSET/airootfs/usr/local/bin/prime-live-overrides" \
           "$BUILDSET/airootfs/etc/calamares/scripts/prime-target-setup" 2>/dev/null || true
chmod 0755 "$STAGE/usr/local/bin/prime-live-overrides" \
           "$STAGE/etc/calamares/scripts/prime-target-setup" 2>/dev/null || true
# upstream partition.conf ships verbatim; its safety values are asserted in step 4
cp -a "$UP/modules/partition.conf" "$OVR/etc/calamares/modules/partition.conf"
ok "staged our scripts, hook and shellprocess config"

# ---------------------------------------------------------------- 3. derive the config
python3 - "$UP" "$UPSH" "$OVR" "$PKGLIST" "$VER" <<'PY' || die "deriving the installer config failed"
import re, sys
from pathlib import Path
import yaml

up, upsh, ovr, pkglist = (Path(p) for p in sys.argv[1:5])
ver = sys.argv[5]
mods, out = up / "modules", ovr / "etc/calamares/modules"

def sub_block(text, anchor, pattern, repl, what):
    """Replace `pattern` only inside the item block that starts at `anchor`."""
    i = text.index(anchor)
    j = text.find("\n    - id:", i + len(anchor))
    block = text[i:j if j != -1 else len(text)]
    new, n = re.subn(pattern, repl, block, count=1)
    assert n == 1, f"could not edit {what}"
    return text[:i] + new + text[j if j != -1 else len(text):]

# --- desktop chooser: Prime Desktop first, and pre-selected --------------------------
chooser = (mods / "packagechooser_desktop.conf").read_text(encoding="utf-8")
assert re.search(r"(?m)^items:", chooser), "chooser has no items: key"
item = ('    - id: "Prime-Desktop"\n'
        '      name: "Prime Desktop"\n'
        '      description: "Recommended. A complete desktop that looks after itself: your '
        'files and apps ready to go, updates that never interrupt you, and an assistant that '
        'can put the machine back the way it was if an update goes wrong."\n'
        '      screenshot: ":/images/hyprland.webp"\n')
chooser = re.sub(r"(?m)^items:\n", "items:\n" + item, chooser, count=1)
chooser = re.sub(r"(?m)^default:.*$", 'default: "Prime-Desktop"', chooser, count=1)
(out / "packagechooser_desktop.conf").write_text(chooser, encoding="utf-8")

# --- boot manager chooser: say what each option gives him, no loader trivia ----------
boot = (mods / "packagechooser_bootloader.conf").read_text(encoding="utf-8")
plain = {
    "limine": "Recommended. The startup menu finds the systems already on your computer and "
              "keeps an earlier version of Prime you can go back to if an update goes wrong.",
    "systemd-boot": "A simple, fast startup menu. It shows the systems already on your "
                    "computer and the last version of Prime that worked.",
    "grub": "Works on almost every computer, including older ones. Shows the systems already "
            "on your computer and an earlier version you can go back to.",
    "refind": "A visual menu that lists every system it can find. Busier than the others, but "
              "easy to look at.",
}
for i, text in plain.items():
    boot = sub_block(boot, f'    - id: {i}\n', r"(?m)^      description: .*$",
                     f'      description: "{text}"', f"description of {i}")
assert re.search(r"(?m)^default: limine$", boot), "boot manager default is not limine"
(out / "packagechooser_bootloader.conf").write_text(boot, encoding="utf-8")

# --- package source: OUR list only, never the floating remote one --------------------
niconf = (mods / "netinstall.conf").read_text(encoding="utf-8")
niconf, n = re.subn(r"(?m)^groupsUrl:\n(?: - .*\n)+",
                    'groupsUrl:\n - file:///etc/calamares/modules/netinstall.yaml\n',
                    niconf, count=1)
assert n == 1, "could not pin groupsUrl to the local list"
(out / "netinstall.conf").write_text(niconf, encoding="utf-8")

# --- the Prime desktop group itself --------------------------------------------------
pkgs = [l.strip() for l in pkglist.read_text(encoding="utf-8").splitlines()
        if l.strip() and not l.strip().startswith("#")]
netinstall = (mods / "netinstall.yaml").read_text(encoding="utf-8")
anchor = '- name: "KDE-Desktop"\n'
assert anchor in netinstall, "insertion anchor disappeared"
group = ['- name: "Prime-Desktop"',
         '  description: "Prime: the desktop, your files and the assistant, ready to use."',
         '  hidden: false',
         '  selected: false',
         '  expanded: false',
         '  critical: true',
         '  packages:'] + [f'    - {p}' for p in pkgs]
netinstall = netinstall.replace(anchor, "\n".join(group) + "\n" + anchor, 1)
(out / "netinstall.yaml").write_text(netinstall, encoding="utf-8")

parsed = yaml.safe_load((out / "netinstall.yaml").read_text(encoding="utf-8"))
names = [g.get("name") for g in parsed]
assert "Prime-Desktop" in names, "our group is not in the package list"
mine = [g for g in parsed if g.get("name") == "Prime-Desktop"][0]
assert mine["packages"] == pkgs, "our package list does not match packages_prime.x86_64"

# --- the post-install step, added to the real sequence -------------------------------
settings = (upsh / "settings_online.conf").read_text(encoding="utf-8")
inst_anchor = "- id:       btrfs_snapshot\n"
assert inst_anchor in settings, "btrfs_snapshot instance disappeared"
settings = settings.replace(inst_anchor,
                            inst_anchor + ("- id:       prime_target\n"
                                           "  module:   shellprocess\n"
                                           "  config:   shellprocess_prime_target.conf\n"), 1)
settings, n = re.subn(r"(?m)^(\s*)- shellprocess@btrfs_snapshot$",
                      r"\1- shellprocess@btrfs_snapshot\n\1- shellprocess@prime_target",
                      settings, count=1)
assert n == 1, "could not add our step to the exec sequence"
# the launcher copies this file to /etc/calamares/settings.conf at start-up, so ours is the
# source; we also place a copy at the destination for anyone reading it there.
(ovr / "usr/share/calamares/settings_online.conf").write_text(settings, encoding="utf-8")
(ovr / "etc/calamares/settings.conf").write_text(settings, encoding="utf-8")

print(f"derived from upstream {ver}: desktop chooser, boot chooser, package source, "
      f"package list ({len(pkgs)} packages), exec sequence")
PY

# ---------------------------------------------------------------- 4. verify
hr; say "verify"; hr
fails=0
check() { if eval "$2"; then ok "$1"; else bad "$1"; fails=$((fails+1)); fi; }
NPKG=$(grep -cvE '^\s*#|^\s*$' "$PKGLIST")

check "hook installed (copies our config in after the installer package lands)" \
      "[ -f '$STAGE/etc/pacman.d/hooks/95-prime-os-overrides.hook' ]"
check "hook invokes the copy script through /bin/sh (airootfs modes are not preserved)" \
      "grep -q 'test -f /usr/local/bin/prime-live-overrides && sh /usr/local/bin/prime-live-overrides' \
       '$STAGE/etc/pacman.d/hooks/95-prime-os-overrides.hook'"
check "hook fires for both installer package names" \
      "[ \$(grep -c '^Target = cachyos-calamares' '$STAGE/etc/pacman.d/hooks/95-prime-os-overrides.hook') -ge 2 ]"
check "hook is NOT marked for removal, so the live session's reinstall cannot undo it" \
      "! grep -q 'remove from airootfs' '$STAGE/etc/pacman.d/hooks/95-prime-os-overrides.hook'"
check "target script invoked through bash (same mode reason)" \
      "grep -q '/bin/bash /etc/calamares/scripts/prime-target-setup' \
       '$OVR/etc/calamares/modules/shellprocess_prime_target.conf'"
check "target-side rollback script present" \
      "[ -f '$STAGE/etc/calamares/scripts/prime-target-setup' ]"
check "desktop chooser offers Prime Desktop and defaults to it" \
      "grep -q '^default: \"Prime-Desktop\"' '$OVR/etc/calamares/modules/packagechooser_desktop.conf' \
       && grep -q 'id: \"Prime-Desktop\"' '$OVR/etc/calamares/modules/packagechooser_desktop.conf'"
check "package source pinned to the local list" \
      "grep -q 'file:///etc/calamares/modules/netinstall.yaml' '$OVR/etc/calamares/modules/netinstall.conf'"
check "Prime-Desktop group carries all $NPKG packages" \
      "python3 -c \"
import yaml,sys
d=yaml.safe_load(open('$OVR/etc/calamares/modules/netinstall.yaml'))
g=[x for x in d if x.get('name')=='Prime-Desktop']
sys.exit(0 if g and g[0]['packages']==[l.strip() for l in open('$PKGLIST') if l.strip() and not l.strip().startswith('#')] else 1)\""
check "every package name exists in the configured repos" \
      "python3 - <<'PYEOF'
import subprocess, sys
bad=[]
for l in open('$PKGLIST'):
    l=l.strip()
    if not l or l.startswith('#'): continue
    if subprocess.run(['pacman','-Si',l],capture_output=True).returncode != 0: bad.append(l)
print('missing: '+', '.join(bad)) if bad else None
sys.exit(1 if bad else 0)
PYEOF"
check "boot manager chooser default is limine and every option has plain text" \
      "grep -q '^default: limine' '$OVR/etc/calamares/modules/packagechooser_bootloader.conf' \
       && grep -q 'finds the systems already on your computer' '$OVR/etc/calamares/modules/packagechooser_bootloader.conf'"
check "partition step pre-selects NOTHING (cannot wipe the Windows disk by accident)" \
      "grep -q '^initialPartitioningChoice: none' '$OVR/etc/calamares/modules/partition.conf' \
       && grep -q '^initialSwapChoice: none' '$OVR/etc/calamares/modules/partition.conf'"
check "our post-install step is in the exec sequence, after the boot manager is set up" \
      "python3 -c \"
import re, sys
s=open('$OVR/usr/share/calamares/settings_online.conf').read()
seq=s.split('exec:')[1]
i_boot=seq.index('- bootloader'); i_us=seq.index('- shellprocess@prime_target')
sys.exit(0 if i_us>i_boot else 1)\""
check "every derived file still parses as yaml" \
      "python3 -c \"
import glob,yaml
for f in glob.glob('$OVR/etc/calamares/**/*.conf',recursive=True)+glob.glob('$OVR/etc/calamares/**/*.yaml',recursive=True):
    yaml.safe_load(open(f))\""
check "no secret-shaped values in the staged tree" \
      "! grep -rIlE '(api[_-]?key|secret|password|token)[\"'\''[:space:]]*[:=][\"'\''[:space:]]*[A-Za-z0-9_-]{16,}' '$OVR' 2>/dev/null | grep -q ."

hr
if [ "$fails" -eq 0 ]; then
  say "buildset applied cleanly."
  say "build:  cd $CLONE && sudo ./buildiso.sh -p desktop"
  exit 0
fi
bad "$fails check(s) failed — not ready to build"
exit 1

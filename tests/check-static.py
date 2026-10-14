#!/usr/bin/env python3
"""Static checks on the Prime layer — no install, no container, no display needed.

They hold the desktop to its standard: no terminal in the user path, no jargon
in anything a person reads, one text-size setting (no hardcoded font sizes),
every bar item named in words and reachable from the keyboard, and every
script and data file at least parses.

  python3 tests/check-static.py        (tests/check-static.sh runs it, plus the GUI self-tests)
"""
from __future__ import annotations

import glob
import json
import os
import re
import subprocess
import sys

REPO = os.path.realpath(os.path.join(os.path.dirname(__file__), ".."))
LAYER = os.path.join(REPO, "layer")
fails = 0


def ck(name: str, problems: list):
    global fails
    if problems:
        fails += 1
        print(f"  FAIL  {name}")
        for p in problems[:12]:
            print(f"          {p}")
        if len(problems) > 12:
            print(f"          … and {len(problems) - 12} more")
    else:
        print(f"  PASS  {name}")


def rel(p: str) -> str:
    return os.path.relpath(p, REPO)


def jsonc(path: str):
    return json.loads(re.sub(r"(?m)^\s*//.*$", "", open(path).read()))


BIN = sorted(glob.glob(f"{LAYER}/bin/*") + glob.glob(f"{LAYER}/addons/*/bin/*"))
SCRIPTS = [p for p in BIN if os.path.isfile(p)]
SHELL = [p for p in SCRIPTS if open(p, errors="replace").readline().rstrip().endswith(("bash", "sh"))]
PY = [p for p in SCRIPTS if "python" in open(p, errors="replace").readline()]
MENUS = [f"{LAYER}/default/menu.json"] + glob.glob(f"{LAYER}/addons/*/menu.json")
ELEMENTS = [f"{LAYER}/default/elements.json"] + glob.glob(f"{LAYER}/addons/*/elements.json")
DESKTOP = sorted(glob.glob(f"{LAYER}/applications/*.desktop") + glob.glob(f"{LAYER}/addons/*/*.desktop"))
HYPR = sorted(glob.glob(f"{LAYER}/default/hypr/*.conf") + glob.glob(f"{LAYER}/addons/*/hypr.conf"))
BARS = [f"{LAYER}/default/waybar/config.jsonc", f"{LAYER}/default/waybar/sidebar.jsonc"]

# ── everything parses ──────────────────────────────────────────────────────────
ck("every script is executable", [rel(p) for p in SCRIPTS if not os.access(p, os.X_OK)])
ck("shell scripts parse (bash -n)",
   [f"{rel(p)}: {r.stderr.strip()}" for p in SHELL
    if (r := subprocess.run(["bash", "-n", p], capture_output=True, text=True)).returncode])
bad_py = []
for p in PY:
    try:
        compile(open(p).read(), p, "exec")
    except SyntaxError as e:
        bad_py.append(f"{rel(p)}: {e}")
ck("python scripts parse", bad_py)
bad_json = []
for p in MENUS + ELEMENTS + glob.glob(f"{LAYER}/addons/*/waybar-*.json") + [f"{LAYER}/default/swaync/config.json"]:
    try:
        json.load(open(p))
    except ValueError as e:
        bad_json.append(f"{rel(p)}: {e}")
for p in BARS:
    try:
        jsonc(p)
    except ValueError as e:
        bad_json.append(f"{rel(p)}: {e}")
ck("menus, right-click menus and bars are valid JSON", bad_json)
ck("no compiled-python caches in the layer",
   [rel(p) for p in glob.glob(f"{LAYER}/**/__pycache__", recursive=True)
    if subprocess.run(["git", "-C", REPO, "ls-files", "--error-unmatch", p],
                      capture_output=True).returncode == 0])

# ── one text size: no hardcoded font sizes ─────────────────────────────────────
px = []
for p in glob.glob(f"{LAYER}/**/*.css", recursive=True) + SCRIPTS:
    for n, line in enumerate(open(p, errors="replace"), 1):
        if re.search(r"font-size:\s*[0-9.]+(px|pt)\b", line):
            px.append(f"{rel(p)}:{n}: {line.strip()}")
ck("stylesheets size text in rem (follows Theme → Text size), never px/pt", px)
rasi = []
for p in glob.glob(f"{LAYER}/default/rofi/*.rasi"):
    for n, line in enumerate(open(p), 1):
        if re.search(r"^\s*font:\s*\"[^\"]*\d", line):
            rasi.append(f"{rel(p)}:{n}: {line.strip()}")
    if "theme/fonts.rasi" not in open(p).read():
        rasi.append(f"{rel(p)}: doesn't import the generated fonts.rasi")
ck("menus take every font from the generated fonts.rasi", rasi)
lit = []
for p in HYPR + [f"{LAYER}/default/kitty/kitty.conf"]:
    for n, line in enumerate(open(p), 1):
        if re.match(r"^\s*(font_size|bar_text_size)\s*=?\s*[0-9]", line):
            lit.append(f"{rel(p)}:{n}: {line.strip()}")
ck("lock screen, title bars and terminal take their size from the theme", lit)
for m in re.finditer(r"theme-str '([^']*)'", "".join(open(p).read() for p in SHELL)):
    if re.search(r"font:\s*\"[^\"]*\d", m.group(1)):
        lit.append(m.group(1))
ck("no inline rofi font sizes in scripts", [x for x in lit if "theme-str" in x or "font:" in x])

# ── no terminal in the user path ───────────────────────────────────────────────
TERMINAL = re.compile(r"\b(prime-float|kitty|btop|htop|nmtui|alacritty|foot|xterm)\b")
# deliberate, labelled ways to open a terminal (power users): allowed
ALLOWED = re.compile(r"Open a terminal|^Terminal$")
term = []
for p in MENUS:
    for s in json.load(open(p))["sections"]:
        for it in s.get("items", []):
            if it.get("kind") == "term":
                term.append(f"{rel(p)}: {it['id']} still uses kind \"term\" — use \"panel\" or \"run\"")
            if TERMINAL.search(it.get("cmd", "")) and not ALLOWED.search(it.get("label", "")):
                term.append(f"{rel(p)}: {it['id']} → {it['cmd']}")
        term += [f"{rel(p)}: {s['id']} pins a terminal ({x})" for x in s.get("pins", []) if TERMINAL.search(x)]
for p in ELEMENTS:
    for eid, e in json.load(open(p)).get("elements", {}).items():
        for it in e.get("items", []):
            if TERMINAL.search(it.get("cmd", "")) and not ALLOWED.search(it.get("label", "")):
                term.append(f"{rel(p)}: {eid} “{it['label'].strip()}” → {it['cmd']}")
for p in BARS:
    for mod, spec in jsonc(p).items():
        if isinstance(spec, dict):
            for k, v in spec.items():
                if k.startswith("on-") and isinstance(v, str) and TERMINAL.search(v):
                    term.append(f"{rel(p)}: {mod} {k} → {v}")
for p in DESKTOP:
    for line in open(p):
        if line.startswith("Exec=") and TERMINAL.search(line):
            term.append(f"{rel(p)}: {line.strip()}")
        if line.strip() == "Terminal=true":
            term.append(f"{rel(p)}: Terminal=true")
for p in HYPR:
    for n, line in enumerate(open(p), 1):
        m = re.match(r"^bind[a-z]*\s*=\s*([^,]*),\s*([^,]*),\s*([^,]*),\s*(.*)$", line)
        if m and TERMINAL.search(m.group(4)) and not ALLOWED.search(m.group(3).strip()) \
                and "$terminal" not in m.group(4):
            term.append(f"{rel(p)}:{n}: {line.strip()}")
for p in SCRIPTS:
    src = open(p, errors="replace").read()
    if os.path.basename(p) == "prime-float":
        continue
    for n, line in enumerate(src.splitlines(), 1):
        if re.search(r"(\[\"kitty\"|exec kitty|\bkitty -e|\bkitty --class|prime-float\b)", line) \
                and not line.lstrip().startswith("#") and "prime-allow-terminal" not in line:
            term.append(f"{rel(p)}:{n}: {line.strip()}")
ck("nothing in the menu, bar, right-click menus, app list or keys opens a terminal", term)

# ── no jargon in anything a person reads ───────────────────────────────────────
JARGON = re.compile(r"\b(bootc|ostree|systemd|systemctl|journalctl|polkit|pkexec|toolchains?|pacman|AUR|"
                    r"hyprpm|hyprctl|hyprland|waybar|swaync|rofi|btop|nmtui|blueman|snapper|flatpak|"
                    r"gsettings|dbus|daemon|hermes|sudo|stdout|stderr|regex|json|jq|registry|cpu|gpu|ram|ip address)\b", re.I)
seen = []                                      # (where, text) a person reads


def visible(where, text):
    if isinstance(text, str) and text.strip():
        seen.append((where, text))


for p in MENUS:
    for s in json.load(open(p))["sections"]:
        visible(f"{rel(p)}:{s['id']}", s.get("label"))
        for it in s.get("items", []):
            visible(f"{rel(p)}:{it['id']}", it.get("label"))
            visible(f"{rel(p)}:{it['id']}", it.get("hint"))
for p in ELEMENTS:
    d = json.load(open(p))
    for it in d.get("generic_items", []) + d.get("utility_items", []):
        visible(rel(p), it.get("label"))
    for eid, e in d.get("elements", {}).items():
        visible(f"{rel(p)}:{eid}", e.get("label"))
        for it in e.get("items", []):
            visible(f"{rel(p)}:{eid}", it.get("label"))
for p in BARS + glob.glob(f"{LAYER}/addons/*/waybar-*.json"):
    d = jsonc(p) if p.endswith("c") else json.load(open(p)).get("modules", {})
    for mod, spec in d.items():
        if isinstance(spec, dict):
            for k, v in spec.items():
                if k.startswith("tooltip-format"):
                    visible(f"{rel(p)}:{mod}", re.sub(r"\{[^}]*\}", "", v))
for p in DESKTOP:
    for line in open(p):
        if re.match(r"^(Name|GenericName|Comment)=", line):
            visible(rel(p), line.split("=", 1)[1])
for p in HYPR:
    for line in open(p):
        m = re.match(r"^bind[a-z]*d[a-z]*\s*=\s*[^,]*,[^,]*,([^,]*),", line)
        if m:
            visible(rel(p), m.group(1))
for p in glob.glob(f"{LAYER}/default/hypr/hyprlock.conf"):
    for line in open(p):
        m = re.match(r"^\s*(text|placeholder_text|fail_text)\s*=\s*(.*)$", line)
        if m and not m.group(2).startswith("cmd["):
            visible(rel(p), m.group(2))
for p in glob.glob(f"{LAYER}/default/rofi/*.rasi"):
    for line in open(p):
        m = re.match(r'^\s*placeholder:\s*"(.*)";', line)
        if m:
            visible(rel(p), m.group(1))
# strings scripts show: notifications, Prime-window lines, picker prompts and hints, window text
SHOWN = re.compile(r"""(?:notify-send(?:\s+-[a-zA-Z]\s+\S+)*|\bnotify|\bsay\s+\w+|\b(?:ok|fixd|bad|good|warn|note|step|row)
                       |ROFI_HINT=|-p|--title|--subtitle|-mesg|set_text\(|label=|set_placeholder_text\(|
                       print\(f?)\s*\(?\s*(["'])(.*?)(?<!\\)\1""", re.X)
PROTO = re.compile(r"""@(?:ok|fix|bad|step|note|summary|text|row|action)\s+(.*?)(?:["']|\\t|$)""")
for p in SCRIPTS:
    for n, line in enumerate(open(p, errors="replace"), 1):
        s = line.strip()
        if s.startswith("#") or s.startswith('"""'):
            continue
        hits = [m.group(2) for m in SHOWN.finditer(line)]
        if hits and re.search(r"\bnotify", line):          # notify "Title" "Body": every quoted part shows
            hits = re.findall(r'"((?:[^"\\]|\\.)*)"', line)
        for text in hits:
            if text.startswith(("-", "$", "~/", "/")) or "|" in text:
                continue                         # an argument or a command, not a sentence
            visible(f"{rel(p)}:{n}", re.sub(r"\$\{?[A-Za-z_][^ }]*\}?|\{[^}]*\}", "", text))
        for m in PROTO.finditer(line):
            visible(f"{rel(p)}:{n}", re.sub(r"\$\{?[A-Za-z_][^ }]*\}?|\{[^}]*\}", "", m.group(1)))
ck(f"no jargon in what people read ({len(seen)} strings: menus, bar, keys, app list, lock screen, windows)",
   [f"{w}: “{t.strip()}”" for w, t in seen if JARGON.search(t)])

# ── the bar: named in words, reachable from the keyboard ───────────────────────
top = jsonc(BARS[0])
mods = []
for _m in top["modules-left"] + top["modules-center"] + top["modules-right"]:
    # a group is a container: its members are the bar items
    mods += top.get(_m, {}).get("modules", []) if _m.startswith("group/") else [_m]
no_tip = [m for m in mods if isinstance(top.get(m), dict) and top[m].get("tooltip") is False]
ck("every top-bar item has a tooltip", no_tip)
elements = json.load(open(ELEMENTS[0]))["elements"]


def element_id(module):
    if module.startswith("custom/media"):
        return "bar.media"
    return "bar." + module.split("/")[-1].split("#")[-1]


ck("every bar item has a right-click menu (and so a keyboard entry, Super+Alt+B)",
   [m for m in mods + jsonc(BARS[1])["modules-left"] if element_id(m) not in elements])
binds = "".join(open(p).read() for p in HYPR)
ck("the bar has a keyboard shortcut (Super+Alt+B)", [] if re.search(r"SUPER ALT, B, .*prime-bar --keys", binds) else ["missing"])
ck("every shortcut is described (Super+/ lists it)",
   [l.strip() for p in HYPR for l in open(p) if re.match(r"^bind[a-z]*\s*=", l) and not re.match(r"^bind[a-z]*d[a-z]*\s*=", l)])

# ── state never in colour alone ────────────────────────────────────────────────
col = []
pl = open(f"{LAYER}/default/hypr/plugins.conf").read()
for m in re.finditer(r"^\s*hyprbars-button\s*=\s*([^,]+),\s*([^,]+),\s*([^,]*),", pl, re.M):
    if not m.group(3).strip():
        col.append(f"title-bar button {m.group(1).strip()} has no symbol")
# a title-bar button's settings are split on commas: a colour written with commas
# (rgba(255, 255, 255, 0.1)) breaks the line into pieces and Hyprland reports an error
for m in re.finditer(r"^\s*hyprbars-button\s*=\s*(.*)$", pl, re.M):
    first = m.group(1).split(",")[0].strip()
    if "(" in first and ")" not in first:
        col.append(f"title-bar button colour has commas: {first}… — write it as rgba(rrggbbaa)")
lock = open(f"{LAYER}/default/hypr/hyprlock.conf").read()
if "prime-lock-status" not in lock:
    col.append("lock screen doesn't say Caps Lock in words")
if "fail_text" not in lock:
    col.append("lock screen doesn't say a wrong password in words")
audio = open(f"{LAYER}/bin/prime-audio-pill").read()
if 'text="Muted"' not in audio:
    col.append("muted sound is shown only by colour")
ck("states are said in words or symbols, not colour alone", col)

# ── Prime on every surface ─────────────────────────────────────────────────────
brand = []
if not re.search(r"text\s*=\s*Prime\b", lock):
    brand.append("lock screen doesn't say Prime")
panel = open(f"{LAYER}/bin/prime-panel").read()
if "— Prime" not in panel or "mark_path()" not in panel:
    brand.append("Prime windows don't carry the Prime name and emblem")
if "Start" not in json.dumps(top.get("image#logo", {})) or "mark" not in json.dumps(top.get("image#logo", {})):
    brand.append("the bar logo isn't the Prime emblem opening Start")
ck("Prime on the lock screen, the bar and every Prime window", brand)

# ── a fresh install comes up as Prime (payload + ISO buildset) ─────────────────
PAY = os.path.join(REPO, "os/cachyos/payload")
wire = []
skel = open(f"{PAY}/skel/.config/hypr/hyprland.conf").read()
if "layer/default/hypr/prime.conf" not in skel:
    wire.append("the seeded hyprland.conf doesn't load the Prime layer")
if "exec-once = /usr/local/bin/prime-first-login" not in skel:
    wire.append("the seeded hyprland.conf doesn't run the first-login step")
for gone in ("waybar", "rofi", "prime"):
    if os.path.exists(f"{PAY}/skel/.config/{gone}"):
        wire.append(f"skel/.config/{gone} would shadow the layer's own")
if open(f"{LAYER}/system/wayland-sessions/prime.desktop").read() != \
        open(f"{PAY}/system/usr/share/wayland-sessions/prime.desktop").read():
    wire.append("the two copies of the Prime login session differ")
if "Name=Prime\n" not in open(f"{LAYER}/system/wayland-sessions/prime.desktop").read():
    wire.append("the login session isn't called Prime")
fl = f"{PAY}/system/usr/local/bin/prime-first-login"
if not os.access(fl, os.X_OK) or subprocess.run(["bash", "-n", fl]).returncode:
    wire.append("prime-first-login is not an executable, parsing script")
ts = os.path.join(REPO, "os/cachyos/archiso/airootfs/etc/calamares/scripts/prime-target-setup")
tsrc = open(ts).read()
if subprocess.run(["bash", "-n", ts]).returncode or "expand-payload.py" not in tsrc or "--root /" in tsrc:
    wire.append("prime-target-setup must seed each account (skel only, never --root /)")
pk = lambda f: {l.strip() for l in open(f) if l.strip() and not l.lstrip().startswith("#")}
missing = pk(os.path.join(REPO, "os/arch/packages.txt")) - pk(os.path.join(REPO, "os/cachyos/archiso/packages_prime.x86_64"))
if missing:
    wire.append(f"the ISO package list lacks what the layer needs: {' '.join(sorted(missing))}")
tok = json.load(open(f"{PAY}/TOKENS.json"))["tokens"]
body = "".join(open(os.path.join(d, f), errors="replace").read()
               for d, _, fs in os.walk(PAY) for f in fs if f != "TOKENS.json")
stale = [t for t in tok if t not in body] + [t for t in set(re.findall(r"@[A-Z][A-Z0-9_]*@", body))
                                             if t not in tok and t not in json.load(open(f"{PAY}/TOKENS.json")).get("foreign", {})]
if stale:
    wire.append(f"TOKENS.json is out of step with the payload: {stale}")
ck("a fresh install comes up as Prime (seeded config, login session, first login, packages)", wire)

print()
print("ALL PASSED" if fails == 0 else f"{fails} FAILED")
sys.exit(1 if fails else 0)

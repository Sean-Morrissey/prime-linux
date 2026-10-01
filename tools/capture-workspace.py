#!/usr/bin/env python3
"""capture-workspace — turn the working Prime desktop into a blank-ready payload.

Owner ask (2026-09-27): *"take all of what i have, package it as prime os ... blank and
ready for him not any of my info"*. Design and inventory: docs/WORKSPACE-CAPTURE.md.

Three rules, enforced here rather than trusted:

  1. **Allow-list only.** A file is captured because it is named in SYSTEM / SKEL /
     REVIEW below — never because it happened to match a wildcard over a home dir.
  2. **Template before writing.** Every personal or machine-specific value becomes an
     `@TOKEN@` placeholders are substituted on the target machine at first boot.
  3. **Scan and fail.** After writing, the payload is re-read and scanned for the raw
     strings it must not contain. Any hit in the shipped payload is a hard failure
     (exit 2) — the report says which file and which rule, with the match masked.

Usage:
  tools/capture-workspace.py                      # write payload, print report
  tools/capture-workspace.py --out DIR            # different payload root
  tools/capture-workspace.py --check DIR          # re-scan an existing payload
  tools/capture-workspace.py --list              # show the allow-list and exit

Exit: 0 clean · 1 nothing captured / usage error · 2 leaks found in the shipped payload.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
TOKEN = re.compile(r"@[A-Z0-9_]+@")

# ----------------------------------------------------------------- allow-lists
# Paths rooted at / — land in the image via a `system/` tree.
SYSTEM = [
    "/usr/local/bin/prime-pc",
    "/etc/prime-pc/prime-pc.conf",
    "/etc/snapper/configs/root",
]

# Paths under $HOME — land in a new user's home via a `skel/` tree.
SKEL = [
    "~/.config/hypr/hyprland.conf",
    "~/.config/hypr/hypridle.conf",
    "~/.config/hypr/hyprlock.conf",
    "~/.config/hypr/hyprpaper.conf",
    "~/.config/hypr/scripts/**",
    "~/.config/waybar/**",
    "~/.config/rofi/prime-*.rasi",
    "~/.config/prime/**",
    "~/.config/systemd/user/prime-*.service",
    "~/.config/systemd/user/prime-*.timer",
    "~/.hermes/scripts/prime-*.sh",
    "~/.hermes/scripts/prime-*.py",
    "~/.hermes/scripts/ledger-*.sh",
    "~/.hermes/scripts/ledger-*.py",
    "~/.hermes/scripts/cal.py",
    "~/.hermes/skins/**",
    "~/.hermes/plugins/**",
    "~/.hermes/agent-hooks/**",
    # secrets are blanked in place by blank_secrets(); the file still needs a manual
    # pass (see REVIEW below), which is why it is flagged in the report.
    "~/.hermes/config.yaml",
]

# Captured, templated, and written to a SEPARATE tree that does not ship.
# Skills are Sean's own procedures: they name him, his printer, his courses. They are
# worth keeping as the starting point for a curated starter set, but nothing in here
# is shippable until a human has read it.
REVIEW = [
    "~/.hermes/skills/**",
    "~/.hermes/SOUL.md",
    "~/.hermes/ledger.md",
]

# Never captured, whatever the allow-list says.
EXCLUDE_SUBSTR = (".bak", ".pre-", ".old")  # editor/backup noise, incl. timestamped .bak-<date>

# ----------------------------------------------------------------- templating
# Order matters: most specific pattern first, or a later rule eats its prefix.
RULES: list[tuple[str, str, str]] = [
    ("email", r"smorrissey1@student\.cscc\.edu", "@EMAIL@"),
    ("github-handle", r"(?i)\bsean[-\s]?morrissey\b", "@GHOWNER@"),
    ("ghcr-path", r"(?i)ghcr\.io/sean-morrissey", "ghcr.io/@GHOWNER@"),
    ("home-path", r"/home/sean\b", "@HOME@"),
    ("username-var", r"\bSEAN_HOME\b", "PRIME_USER_HOME"),
    ("gpu-env", r"HSA_OVERRIDE_GFX_VERSION=\S+", "@GPU_ENV@"),
    ("audio-sink", r"alsa_output\.[A-Za-z0-9._]+", "@AUDIO_SINK@"),
    # whole modeline first, so no geometry from this machine survives
    ("monitor-modeline", r"(?m)^(?P<pre>\s*(?:monitor|Monitor)\s*=\s*)(?:HDMI|DP|eDP|DVI|VGA)[^\n]*$", r"\g<pre>@MONITORS@"),
    # his wallpaper collection does not ship (third-party art); every reference becomes a hook
    ("wallpaper", r"~?@HOME@/\.config/hypr/wallpapers/[^\"'\s]+", "@WALLPAPER@"),
    ("study-dir", r"/College\b", "@STUDY_DIR@"),
    ("study-platform", r"(?i)\bALEKS\b", "@STUDY_PLATFORM@"),
    ("lan-ip", r"\b192\.168\.\d{1,3}\.\d{1,3}\b", "@LAN_IP@"),
    ("first-name", r"\bSean\b", "@USER@"),
    ("first-name-lower", r"\bsean\b", "@USER@"),
]

# Secret-ish keys whose VALUES are blanked in config-like files. A blanked value is only
# a leak when it *is* a literal: `token = ptt.session_token(port)` and
# `SECRET_PATTERNS = [` are code, and blanking them would break the file.
SECRET_KEY = re.compile(
    r"""(?im)^(\s*[\w.-]*(?:api[_-]?key|token|secret|password|passwd|credential)[\w.-]*\s*:\s*)"""
    r"""("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|\$\{[^}]*\}|@[A-Z0-9_]+@|\[\]|\{\}|[^\s#].*?)?(\s*(?:#.*)?)$"""
)
PLACEHOLDER_VALUE = re.compile(r"^\s*(?:''|\"\"|\$\{|@[A-Z0-9_]+@|\[\]|\{\})\s*$")

# ----------------------------------------------------------------- leak scan
# If any of these survive in the shipped payload, the capture is wrong. Read the file
# first, then quote it to Sean only when it is his own file — matches are masked.
LEAKS: list[tuple[str, str]] = [
    ("user-name", r"(?i)\bsean\b"),
    ("surname", r"(?i)morrissey"),
    ("email", r"(?i)student\.cscc\.edu"),
    ("home-path", r"/home/(?!@)\w"),
    ("real-monitor", r"\b(?:HDMI|DP|eDP|DVI|VGA)-[A-Z0-9]+-?\d*\b"),
    ("real-audio-sink", r"alsa_output\.pci-"),
    ("lan-ip", r"\b192\.168\.\d"),
    ("gpu-tuning", r"(?:HSA_OVERRIDE_GFX_VERSION|amdgpu\.ppfeaturemask)=\S"),
    ("api-key-value", r"\bsk-[A-Za-z0-9]{16,}"),
    ("secret-value", r"""(?im)^\s*[\w.-]*(?:api[_-]?key|token|secret|password|passwd|credential)[\w.-]*\s*[:=]\s*("[^"\n]{8,}"|'[^'\n]{8,}'|[A-Za-z0-9_\-\./+]{16,})(?:\s*(?:#.*)?)$"""),
    ("private-key", r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    ("school-path", r"/College\b|cscc\.edu"),
    ("printer", r"(?i)\b(?:elegoo|centauri|orca[- ]?slicer)\b"),
]

BINARY_SUFFIX = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".ico", ".woff", ".woff2", ".ttf", ".otf", ".mp3", ".ogg", ".pem", ".key"}


def mask(match: str) -> str:
    m = match.strip()
    if len(m) <= 6:
        return m[0] + "…" if m else ""
    return f"{m[:3]}…{m[-2:]} ({len(m)} chars)"


def is_text(path: Path) -> bool:
    if path.suffix.lower() in BINARY_SUFFIX:
        return False
    try:
        chunk = path.open("rb").read(8192)
    except OSError:
        return False
    return b"\x00" not in chunk


def excluded(path: Path) -> bool:
    parts = path.parts
    if "__pycache__" in parts or ".git" in parts:
        return True
    name = path.name
    if name.endswith(".pyc"):
        return True
    return any(s in name for s in EXCLUDE_SUBSTR)


def expand(pattern: str) -> list[Path]:
    base = pattern.replace("~", str(HOME), 1).replace("@HOME@", str(HOME))
    out: list[Path] = []
    if any(ch in base for ch in "*?[") or base.endswith("**"):
        import glob

        out = [Path(p) for p in glob.glob(base, recursive=True)]
    else:
        p = Path(base)
        if p.exists():
            out = [p]
    return [p for p in out if p.is_file() and not excluded(p)]


def blank_secrets(text: str) -> tuple[str, int]:
    """Drop the VALUE of any secret-ish key, keeping the key and its comment. A value that
    is itself a placeholder (`${ENV_VAR}`, `@TOKEN@`, `''`) is left alone — that is the
    shape the shipped file is supposed to have."""
    hits = 0

    def repl(m: re.Match[str]) -> str:
        nonlocal hits
        key, val, tail = m.group(1), (m.group(2) or ""), (m.group(3) or "")
        if val and not (PLACEHOLDER_VALUE.match(val) or "@" in val or "${" in val or "$" in val):
            hits += 1
            return f"{key}{tail}"
        return m.group(0)

    return SECRET_KEY.sub(repl, text), hits


def template(text: str, extra: list[tuple[str, str, str]] | None = None) -> tuple[str, list[str]]:
    rules = list(RULES)
    if extra:
        at = next((i for i, r in enumerate(rules) if r[0] == "study-dir"), len(rules))
        rules[at:at] = extra
    fired: list[str] = []
    for name, pat, rep in rules:
        text, n = re.subn(pat, rep, text)
        if n:
            fired.append(f"{name}×{n}")
    return text, fired


MONITOR_NAME = re.compile(r"\b(?:HDMI|DP|eDP|DVI|VGA)-[A-Z0-9]+-?\d*\b")


def monitor_rules(raws: list[str]) -> tuple[list[tuple[str, str, str]], dict[str, str]]:
    """Every real connector name in the layer becomes a stable token, so the script that
    drives a second screen survives a different port on the target machine."""
    names = sorted({m.group(0) for raw in raws for m in MONITOR_NAME.finditer(raw)})
    mapping = {n: f"@MONITOR_{i}@" for i, n in enumerate(names, 1)}
    rules = [(f"monitor-name{i}", re.escape(n), t) for i, (n, t) in enumerate(mapping.items(), 1)]
    return rules, mapping


def read_any(path: Path) -> tuple[str, str]:
    """Read a file; fall back to passwordless sudo for root-only config (/etc/snapper)."""
    try:
        return path.read_text(encoding="utf-8", errors="replace"), "direct"
    except PermissionError:
        import subprocess

        proc = subprocess.run(["sudo", "-n", "cat", str(path)], capture_output=True, text=True)
        if proc.returncode == 0:
            return proc.stdout, "sudo"
        raise


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def quote_yaml_tokens(text: str) -> str:
    """`@TOKEN@` is not valid YAML anywhere in a scalar (`found character '@'`), including
    mid-value (`bash @HOME@/x.sh`). Quote the whole scalar — and fold any YAML
    continuation lines into it first, or the wrapped value swallows only its first line and
    the rest of the scalar becomes a syntax error."""
    lines = text.splitlines()
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        m = re.match(r"""^(\s*(?:-\s+)?[\w.\-\[\]"']*\s*:\s*)(.+?)(\s+#.*)?$""", line)
        if not m:
            # bare list item: `      - @HOME@`
            m = re.match(r"^(\s*-\s+)(.+?)(\s+#.*)?$", line)
        if m and "@" in m.group(2) and not m.group(2).lstrip().startswith(("\"", "'")):
            indent = len(m.group(1)) - len(m.group(1).lstrip())
            val = m.group(2).strip()
            j = i + 1
            while j < len(lines):
                nxt = lines[j]
                if not nxt.strip() or nxt.lstrip().startswith("#"):
                    break
                nindent = len(nxt) - len(nxt.lstrip())
                if nindent <= indent or re.match(r"^\s*(?:-\s+)?[\w.\-]+\s*:", nxt):
                    break
                val += " " + nxt.strip()  # YAML already treats this as one folded scalar
                j += 1
            quoted = val.replace('"', '\\"')
            out.append(f'{m.group(1)}"{quoted}"{m.group(3) or ""}')
            i = j
            continue
        out.append(line)
        i += 1
    return "\n".join(out) + ("\n" if text.endswith("\n") else "")


def token_namespace() -> set[str]:
    """The exact token namespace this tool creates. Anything else that looks like @X@ in a
    captured file belongs to the file's own tooling (wpctl's `@DEFAULT_AUDIO_SINK@`, a
    Makefile's `@VAR@`) and must survive untouched."""
    return {rep for _, _, rep in RULES if re.fullmatch(r"@[A-Z0-9_]+@", rep)}


def scan_tokens(root: Path) -> tuple[dict[str, int], dict[str, int]]:
    mine: dict[str, int] = {}
    foreign: dict[str, int] = {}
    namespace = token_namespace()
    for path in sorted(root.rglob("*")):
        if not path.is_file() or not is_text(path):
            continue
        for tok in TOKEN.findall(path.read_text(encoding="utf-8", errors="replace")):
            bucket = mine if (tok in namespace or re.fullmatch(r"@MONITOR_\d+@", tok) or tok == "@MONITORS@") else foreign
            bucket[tok] = bucket.get(tok, 0) + 1
    return mine, foreign


def token_manifest(mine: dict[str, int], foreign: dict[str, int]) -> dict:
    return {
        "note": "Tokens this payload contains. Only these are substituted by tools/expand-payload.py; "
                "anything under 'foreign' belongs to tools inside those files (wpctl, make) and is left alone.",
        "tokens": dict(sorted(mine.items())),
        "foreign": dict(sorted(foreign.items())),
    }


def strip_jsonc(text: str) -> str:
    """waybar's config files are JSONC: `//` comments and trailing commas are legal there
    and are not a defect to report. `://` is protected so URLs survive."""
    text = re.sub(r"(?<!:)//[^\n]*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return text


def check_syntax(path: Path) -> str | None:
    """A payload that no longer parses is worse than one with a token in it: the machine
    installs, then the thing does not start. Returns an error string, or None if it parses."""
    suffix = path.suffix.lower()
    text = path.read_text(encoding="utf-8", errors="replace")
    if suffix == ".json":
        try:
            json.loads(text)
            return None
        except json.JSONDecodeError as exc:
            try:
                json.loads(strip_jsonc(text))  # waybar ships JSONC
                return None
            except json.JSONDecodeError:
                return f"json: {exc}"
    if suffix in (".yaml", ".yml"):
        try:
            import yaml
        except ImportError:
            return None
        try:
            yaml.safe_load(text)
            return None
        except Exception as exc:  # noqa: BLE001 — any parse failure is a failure
            return f"yaml: {str(exc).splitlines()[0][:110]}"
    if suffix == ".py":
        try:
            compile(text, str(path), "exec")
            return None
        except SyntaxError as exc:
            return f"python: line {exc.lineno}: {exc.msg}"
    if suffix == ".sh":
        proc = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
        if proc.returncode == 0:
            return None
        first = (proc.stderr.strip().splitlines() or [""])[0]
        return f"bash: {first[:110]}"
    return None


def dest_for(src: Path, group: str, out: Path, review_out: Path) -> Path:
    if group == "system":
        rel = Path(*src.parts[1:])  # strip leading /
        return out / "system" / rel
    rel = src.relative_to(HOME)
    if group == "skel":
        return out / "skel" / rel
    return review_out / "skel" / rel


def capture(out: Path, want_report: bool, do_review: bool) -> tuple[dict, int]:
    review_out = out.parent / "payload-review"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)

    files: list[dict] = []
    manual: list[dict] = []
    syntax_errors: list[dict] = []
    detected: dict[str, list[str]] = {"monitors": [], "audio_sinks": [], "gpu_env": []}
    groups = [("system", SYSTEM), ("skel", SKEL)]
    if do_review:
        groups.append(("review", REVIEW))

    # pre-pass: read every allow-listed file first, so connector names can be tokenized
    # with one consistent map instead of per-file guessing.
    sources: list[tuple[str, Path, str, str]] = []
    for group, patterns in groups:
        for pat in patterns:
            for src in sorted(set(expand(pat))):
                try:
                    raw, how = read_any(src)
                except (OSError, PermissionError) as exc:
                    print(f"  ! unreadable: {src} ({exc})", file=sys.stderr)
                    continue
                sources.append((group, src, raw, how))

    m_rules, m_map = monitor_rules([raw for _, _, raw, _ in sources])

    for group, src, raw, how in sources:
        text = raw
        secret_hits = 0
        # Only data files get their secret values dropped: a `key: value` line inside a
        # .py source file is a dict entry, and blanking it produces invalid Python.
        if src.suffix.lower() not in {".py", ".sh", ".bash"}:
            text, secret_hits = blank_secrets(text)
        templated, fired = template(text, m_rules)
        if src.suffix.lower() in (".yaml", ".yml"):
            templated = quote_yaml_tokens(templated)

        # hardware the target machine must detect for itself — recorded in the
        # REPORT only, never written into the payload.
        for line in re.findall(r"(?m)^\s*monitor\s*=\s*([^,\n]+).*$", raw):
            if re.match(r"(HDMI|DP|eDP|DVI|VGA)", line):
                detected["monitors"].append(line)
        detected["audio_sinks"] += re.findall(r"alsa_output\.[A-Za-z0-9._]+", raw)
        detected["gpu_env"] += re.findall(r"HSA_OVERRIDE_GFX_VERSION=\S+", raw)

        dst = dest_for(src, group, out, review_out)
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(templated, encoding="utf-8")
        if src.stat().st_mode & 0o111:
            dst.chmod(0o755)

        entry = {
            "group": group,
            "source": str(src).replace(str(HOME), "~"),
            "dest": str(dst.relative_to(out.parent)),
            "bytes": dst.stat().st_size,
            "sha256": sha256(dst),
            "tokens": fired,
            "secrets_blanked": secret_hits,
            "read_via": how,
        }
        files.append(entry)

        err = check_syntax(dst)
        if err:
            syntax_errors.append({"file": entry["dest"], "group": group, "error": err})

        # Anything where a token landed inside executable logic needs a human:
        # substituting a placeholder into code is a port, not a rename.
        if any(t.startswith(("first-name", "username-var", "home-path", "wallpaper", "monitor-name")) for t in fired):
            manual.append({"file": entry["dest"], "why": ",".join(fired)})

    mine, foreign = scan_tokens(out)
    (out / "TOKENS.json").write_text(json.dumps(token_manifest(mine, foreign), indent=2) + "\n", encoding="utf-8")

    report = {
        "captured_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "payload": str(out),
        "files": files,
        "needs_manual_pass": manual,
        "syntax_errors": syntax_errors,
        "tokens": mine,
        "foreign_tokens": foreign,
        "detected_on_source_machine": {k: sorted(set(v)) for k, v in detected.items() if v},
        "monitor_tokens": m_map,
        "counts": {
            "files": len(files),
            "templated": sum(1 for f in files if f["tokens"]),
            "secrets_blanked": sum(f["secrets_blanked"] for f in files),
            "manual_pass": len(manual),
            "syntax_errors": len([e for e in syntax_errors if e["group"] != "review"]),
            "bytes": sum(f["bytes"] for f in files),
        },
    }
    if want_report:
        (out.parent / "capture-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report, 0


def scan(root: Path, shipped_only: bool = True) -> list[dict]:
    hits: list[dict] = []
    if not root.exists():
        return hits
    for path in sorted(root.rglob("*")):
        if not path.is_file() or not is_text(path):
            continue
        try:
            lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        for lineno, line in enumerate(lines, 1):
            for name, pat in LEAKS:
                for m in re.finditer(pat, line):
                    hits.append(
                        {
                            "file": str(path),
                            "line": lineno,
                            "rule": name,
                            "masked": mask(m.group(0)),
                        }
                    )
    return hits


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="capture the Prime workspace as a blank-ready payload")
    ap.add_argument("--out", default="os/cachyos/payload", help="payload root (default: os/cachyos/payload)")
    ap.add_argument("--check", metavar="DIR", help="re-scan an existing payload instead of capturing")
    ap.add_argument("--review", action="store_true", help="also capture the review-only tree (skills, ledger)")
    ap.add_argument("--list", action="store_true", help="print the allow-list and exit")
    args = ap.parse_args(argv)

    if args.list:
        for name, pats in (("system", SYSTEM), ("skel", SKEL), ("review (never ships)", REVIEW)):
            print(f"{name}:")
            for p in pats:
                print(f"  {p}")
        return 0

    if args.check:
        root = Path(args.check)
        hits = scan(root)
        print(f"scan {root}: {len(hits)} leak(s)")
        for h in hits[:60]:
            print(f"  {h['file']}:{h['line']} [{h['rule']}] {h['masked']}")
        return 2 if hits else 0

    out = Path(args.out).expanduser().resolve()
    report, _ = capture(out, want_report=True, do_review=args.review)

    print(f"payload  {out}")
    print(f"  files            {report['counts']['files']}")
    print(f"  bytes            {report['counts']['bytes'] / 1024:.1f} KB")
    print(f"  templated        {report['counts']['templated']}")
    print(f"  secrets blanked  {report['counts']['secrets_blanked']}")
    if report["tokens"]:
        print(f"  tokens           {', '.join(f'{k}×{v}' for k, v in report['tokens'].items())}")
    if report["foreign_tokens"]:
        print(f"  left untouched   {', '.join(report['foreign_tokens'])} (tool syntax, not ours — e.g. wpctl)")
    if report["detected_on_source_machine"]:
        print("  detected here (NOT shipped; target machine detects its own):")
        for k, v in report["detected_on_source_machine"].items():
            print(f"    {k}: {', '.join(v)}")
    if report["needs_manual_pass"]:
        print(f"  needs a human pass ({len(report['needs_manual_pass'])} files where a token landed in code):")
        for m in report["needs_manual_pass"][:15]:
            print(f"    {m['file']}  [{m['why']}]")

    print("leak scan:")
    hits = scan(out)
    if not hits:
        print("  clean — no personal or machine-specific string survived in the payload")
    else:
        print(f"  {len(hits)} hit(s) — NOT shippable until fixed")
        for h in hits[:40]:
            print(f"    {h['file']}:{h['line']} [{h['rule']}] {h['masked']}")

    shipped_syntax = [e for e in report["syntax_errors"] if e["group"] != "review"]
    if shipped_syntax:
        print(f"syntax check: {len(shipped_syntax)} file(s) no longer parse — NOT shippable:")
        for e in shipped_syntax[:20]:
            print(f"    {e['file']}  [{e['error']}]")
    else:
        print("syntax check: every captured file that has a parser still parses")

    review_root = out.parent / "payload-review"
    if args.review and review_root.exists():
        rhits = scan(review_root)
        print(f"review tree (does not ship): {review_root} — {len(rhits)} leak(s), expected until curated")

    print(f"report   {out.parent / 'capture-report.json'}")
    return 2 if (hits or shipped_syntax) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

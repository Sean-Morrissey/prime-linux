#!/usr/bin/env python3
"""expand-payload — fill a captured payload's @TOKENS@ on the machine that is installing.

Pairs with tools/capture-workspace.py. The capture writes `@HOME@`, `@MONITOR_1@`,
`@AUDIO_SINK@` … instead of one machine's values; this decides what they mean *here* and
writes the real files. Run at first boot, after the interview has a username, or by hand:

  tools/expand-payload.py --home /home/alex --root / --dry-run
  tools/expand-payload.py --home /home/alex --root / --user alex --study-dir /home/alex/College

Design rules:
  * Nothing is invented silently: every token that cannot be resolved here is listed and the
    run fails, so a half-configured desktop never looks like a finished one.
  * Hardware is detected, not assumed (hyprctl / pactl / lspci when present), and anything
    given on the command line wins over detection.
  * Writing into a real root needs --root explicitly. `--dry-run` prints what it would do.

Exit: 0 every token resolved · 1 usage/IO error · 2 unresolved tokens (nothing written).
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

TOKEN = re.compile(r"@[A-Z0-9_]+@")
COMMON_PLATFORMS = "ALEKS|Canvas|Blackboard|Moodle|MyLab|Cengage|Pearson"


def sh(cmd: list[str]) -> str:
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return ""
    return proc.stdout if proc.returncode == 0 else ""


def detect_monitors() -> list[str]:
    out = sh(["hyprctl", "monitors", "-j"])
    if out:
        try:
            return [m["name"] for m in json.loads(out) if m.get("name")]
        except (json.JSONDecodeError, KeyError, TypeError):
            pass
    return [line.split()[0] for line in sh(["wlr-randr"]).splitlines() if line and not line[0].isspace()]


def detect_audio_sink() -> str:
    for line in sh(["pactl", "list", "short", "sinks"]).splitlines():
        parts = line.split()
        if len(parts) > 1 and "monitor" not in parts[1]:
            return parts[1]
    return ""


def detect_gpu_env() -> str:
    """ROCm's gfx target for cards the runtime does not know yet — only when the card is AMD."""
    lspci = sh(["lspci"])
    if not re.search(r"\b(AMD|ATI)\b.*(VGA|Display|3D)", lspci, re.I):
        return ""
    return "HSA_OVERRIDE_GFX_VERSION=12.0.0"  # Navi 44 (RX 9060 XT) baseline; override on the CLI otherwise


def monitor_lines(names: list[str]) -> list[str]:
    """One hyprland `monitor=` line per display, left-to-right, primary first."""
    if not names:
        return ['# @MONITORS@ — no display detected; set `monitor=,preferred,auto,1` by hand']
    lines = []
    x = 0
    for i, name in enumerate(names):
        lines.append(f"monitor={name},preferred,{x}x0,1")
        x += 1920
    return lines


def build_tokens(args: argparse.Namespace, names: list[str]) -> dict[str, str]:
    home = args.home.rstrip("/")
    tokens = {
        "@HOME@": home,
        "@USER@": args.user,
        "@EMAIL@": args.email,
        "@GHOWNER@": args.github or args.user,
        "@STUDY_DIR@": args.study_dir or f"{home}/College",
        "@STUDY_PLATFORM@": args.study_platform or COMMON_PLATFORMS,
        "@AUDIO_SINK@": args.audio_sink if args.audio_sink is not None else detect_audio_sink(),
        "@GPU_ENV@": args.gpu_env if args.gpu_env is not None else detect_gpu_env(),
        "@LAN_IP@": args.printer_ip or "",
        "@WALLPAPER@": args.wallpaper or "",
    }
    for i, name in enumerate(names, 1):
        tokens[f"@MONITOR_{i}@"] = name
    return tokens


def load_namespace(payload: Path) -> set[str] | None:
    """The capture declares the token set it created (payload/TOKENS.json). Expanding only
    those means a tool's own `@…@` syntax (wpctl's `@DEFAULT_AUDIO_SINK@`) is never mangled."""
    manifest = payload / "TOKENS.json"
    if not manifest.exists():
        return None
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return None
    names = set(data.get("tokens", {}))
    return names or None


def expand_text(text: str, tokens: dict[str, str], names: list[str], unmatched: set[str],
                namespace: set[str] | None) -> str:
    # monitor modelines first: one placeholder line becomes the real set for this display
    if "@MONITORS@" in text:
        block = monitor_lines(names)
        first = True

        def repl_line(m: re.Match[str]) -> str:
            nonlocal first
            if first:
                first = False
                return "\n".join(block)  # block lines already carry their own `monitor=`
            return ""  # the placeholder line was a stand-in for the whole set

        text = re.sub(r"(?m)^(\s*(?:monitor|Monitor)\s*=\s*)@MONITORS@$", repl_line, text)
        text = text.replace("@MONITORS@", ", ".join(block))

    def sub(m: re.Match[str]) -> str:
        tok = m.group(0)
        if namespace is not None and tok not in namespace and tok != "@MONITORS@" \
                and not re.fullmatch(r"@MONITOR_\d+@", tok):
            return tok  # not ours: belongs to a tool quoted in this file
        if tok in tokens:
            return tokens[tok]
        unmatched.add(tok)
        return tok

    return TOKEN.sub(sub, text)


def walk(payload: Path) -> list[tuple[str, Path, Path]]:
    """(group, source in payload, path relative to that group's destination root)"""
    pairs: list[tuple[str, Path, Path]] = []
    for group in ("system", "skel"):
        base = payload / group
        if not base.exists():
            continue
        for src in sorted(base.rglob("*")):
            if src.is_file():
                pairs.append((group, src, src.relative_to(base)))
    return pairs


def dest_for(group: str, rel: Path, home: Path, root: Path) -> Path:
    return (root / rel) if group == "system" else (home / rel)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="expand a captured Prime payload on this machine")
    ap.add_argument("--payload", default="os/cachyos/payload")
    ap.add_argument("--home", required=True, help="target user's home (absolute)")
    ap.add_argument("--monitors", default=None, help="comma-separated display names; overrides detection (useful for testing)")
    ap.add_argument("--root", default=None, help="target filesystem root for system/ files; needed to write them")
    ap.add_argument("--user", default=None, help="target username (default: basename of --home)")
    ap.add_argument("--email", default="")
    ap.add_argument("--github", default=None)
    ap.add_argument("--study-dir", default=None)
    ap.add_argument("--study-platform", default=None)
    ap.add_argument("--audio-sink", default=None, help="override pactl detection; '' to blank")
    ap.add_argument("--gpu-env", default=None, help="override detection; '' to blank")
    ap.add_argument("--printer-ip", default=None)
    ap.add_argument("--wallpaper", default=None, help="path to the user's wallpaper")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--list-tokens", action="store_true")
    args = ap.parse_args(argv)

    payload = Path(args.payload).expanduser().resolve()
    if not (payload / "skel").exists() and not (payload / "system").exists():
        print(f"no payload at {payload} (expected skel/ and/or system/)", file=sys.stderr)
        return 1

    args.home = str(Path(args.home).expanduser().resolve())
    args.user = args.user or Path(args.home).name

    names = [n for n in (args.monitors or "").split(",") if n] or detect_monitors()
    tokens = build_tokens(args, names)

    if args.list_tokens:
        print(f"detected displays: {', '.join(names) or '(none)'}")
        for k, v in tokens.items():
            print(f"  {k:<16} {v!r}")
        return 0

    unmatched: set[str] = set()
    namespace = load_namespace(payload)
    planned: list[tuple[str, Path, Path, str]] = []
    for group, src, rel in walk(payload):
        text = src.read_text(encoding="utf-8", errors="replace")
        planned.append((group, src, rel, expand_text(text, tokens, names, unmatched, namespace)))

    if unmatched:
        print("unresolved tokens — nothing written:", file=sys.stderr)
        for tok in sorted(unmatched):
            print(f"  {tok}", file=sys.stderr)
        print("pass the missing value on the command line (see --help) or re-capture the file", file=sys.stderr)
        return 2

    root = Path(args.root).expanduser().resolve() if args.root else None
    home = Path(args.home)
    written = 0
    for group, src, rel, text in planned:
        if group == "system" and root is None:
            print(f"  skip (needs --root): {rel}", file=sys.stderr)
            continue
        dst = dest_for(group, rel, home, root) if root else home / rel
        if args.dry_run:
            print(f"  would write {dst}")
            written += 1
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        dst.write_text(text, encoding="utf-8")
        if src.stat().st_mode & 0o111:
            dst.chmod(0o755)
        written += 1

    verb = "would write" if args.dry_run else "wrote"
    print(f"{verb} {written} file(s) under {home}" + (f" and {root}" if root else ""))
    print(f"displays: {', '.join(names) or '(none detected)'} · audio: {tokens['@AUDIO_SINK@'] or '(none)'}"
          f" · gpu: {tokens['@GPU_ENV@'] or '(none)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/python3
"""Human-readable rendering of the ledger, for the waybar pill's middle-click.

The raw file is machine-shaped (- [ ] ts | tag | text). This turns it into
plain English so the popup reads like a list of notes instead of a config file:

    LEDGER                        1 for me · 0 to send
    ─────────────────────────────────────────────────────
    FOR ME — you wrote it, I haven't done it yet
      • 8:30am   add dentist Tue 3pm

    TO YOU — already on your phone
      ✓ 8:20am   Ledger is live…

Usage:  ledger-view.py [--lines N]
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from datetime import datetime

LEDGER = os.path.expanduser("~/.hermes/ledger.md")
WIDTH = 92
RE_ENTRY = re.compile(r"^- \[( |x|\?|!)\] (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) \| ([^|]*) \| (.*)$")
RE_SUFFIX = re.compile(r"\s*·(sent|done)\s+\d{2}:\d{2}\s*$")


def oneline(text: str, limit: int) -> str:
    """One clipped line — for entries that are history, not action."""
    flat = " ".join(text.split())
    if len(flat) <= limit:
        return flat
    cut = flat[:limit]
    space = cut.rfind(" ")
    if space > limit * 0.6:
        cut = cut[:space]
    return cut.rstrip(" ,;:.—-") + "…"


def when(ts: str) -> str:
    """8:30am for today, 'Tue 3pm'-ish otherwise."""
    try:
        dt = datetime.strptime(ts, "%Y-%m-%d %H:%M")
    except ValueError:
        return ts
    clock = dt.strftime("%-I:%M%p").lower()
    today = datetime.now().date()
    if dt.date() == today:
        return clock
    days = (today - dt.date()).days
    if days == 1:
        return f"yest {clock}"
    return dt.strftime("%b %-d ") + clock


def wrap(text: str, first: str, cont: str, width: int) -> list[str]:
    words, lines, cur = text.split(), [], first
    for w in words:
        cand = f"{cur}{w} " if cur.endswith(" ") or cur == first else f"{cur} {w} "
        if len(cand.rstrip()) > width and cur.strip() not in ("", first.strip()):
            lines.append(cur.rstrip())
            cur = cont
        cur += w + " "
    if cur.strip():
        lines.append(cur.rstrip())
    return lines or [first.rstrip()]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lines", type=int, default=0)
    a = ap.parse_args()

    try:
        raw = open(LEDGER, encoding="utf-8").read().splitlines()
    except OSError:
        print("Ledger is empty."); return 0

    ents = []
    for line in raw:
        m = RE_ENTRY.match(line.strip())
        if m:
            state, ts, tag, text = m.groups()
            ents.append({"state": state, "ts": ts, "tag": tag.strip(),
                         "text": RE_SUFFIX.sub("", text).strip()})
    if not ents:
        print("Ledger is empty — click the pill to write the first note."); return 0

    queued = [e for e in ents if e["state"] == " "]
    asks = [e for e in ents if e["state"] == "?"]
    sent = [e for e in ents if e["state"] == "x"]
    done = [e for e in ents if e["state"] == "!"]

    bar = "─" * WIDTH
    out: list[str] = []
    head = "LEDGER"
    info = f"{len(asks)} for me · {len(queued)} to send"
    out.append(head + " " * max(1, WIDTH - len(head) - len(info)) + info)
    out.append(bar)

    if asks:
        out.append("WAITING ON ME  ·  you asked, I haven't done it yet")
        for e in asks:
            out += wrap(e["text"], f"  • {when(e['ts']):>9}   ", "            ", WIDTH)
        out.append("")

    if queued:
        out.append("GOING TO YOU  ·  on the way to your phone")
        for e in queued:
            out += wrap(e["text"], f"  · {when(e['ts']):>9}   ", "            ", WIDTH)
        out.append("")

    if sent:
        out.append("SENT TO YOU  ·  already on your phone")
        for e in sent[-8:]:
            out.append(f"  ✓ {when(e['ts']):>9}   {oneline(e['text'], WIDTH - 16)}")
        out.append("")

    if done:
        out.append("DONE  ·  I already handled these")
        for e in done[-4:]:
            out.append(f"  ✓ {when(e['ts']):>9}   {oneline(e['text'], WIDTH - 16)}")
        out.append("")

    out.append(bar)
    out.append("Esc closes  ·  click the pill to write a new note")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

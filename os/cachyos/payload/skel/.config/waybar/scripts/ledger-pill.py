#!/usr/bin/python3
"""Waybar pill for @USER@'s ledger (custom/ledger).

The ledger is a two-way file (~/.hermes/ledger.md). This pill is the always-on
view of it, so neither direction depends on a chat being open:

  - [ ]  queued for @USER@   (ledger-flush sends these to WhatsApp)
  - [x]  already sent
  - [?]  @USER@ → Prime, not actioned yet
  - [!]  actioned

Renders one JSON line. Cheap: one file read per tick, no subprocess.

  ask     󰉹 ▸2 <newest ask>      @USER@ has notes waiting for Prime
  out     󰉹 1 <newest queued>    something is queued to go out
  idle    󰉹 ledger              nothing pending

  click        write a note for Prime
  middle-click read the ledger
  right-click  menu
"""
from __future__ import annotations

import json
import os
import re
from html import escape

LEDGER = os.path.expanduser("~/.hermes/ledger.md")
ICON = "\U000f0279"          # nf-md-format_list_bulleted
CLIP = 34

RE_ENTRY = re.compile(r"^- \[( |x|\?|!)\] (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) \| ([^|]*) \| (.*)$")


def entries():
    try:
        with open(LEDGER, encoding="utf-8") as fh:
            lines = fh.read().splitlines()
    except OSError:
        return []
    out = []
    for line in lines:
        m = RE_ENTRY.match(line.strip())
        if m:
            state, ts, tag, text = m.groups()
            out.append({"state": state, "ts": ts, "tag": tag.strip(), "text": text.strip()})
    return out


def clip(text: str, limit: int = CLIP) -> str:
    flat = " ".join((text or "").split())
    if len(flat) <= limit:
        return flat
    cut = flat[:limit]
    space = cut.rfind(" ")
    if space > limit * 0.5:
        cut = cut[:space]
    return cut.rstrip(" ,;:.") + "…"


def line_of(e: dict) -> str:
    t = e["ts"][11:]                      # HH:MM only
    return f"• {t} [{e['tag']}] {clip(e['text'], 90)}"


def emit(text: str, cls: str, tooltip: str) -> None:
    print(json.dumps({"text": text, "class": cls, "tooltip": tooltip}, ensure_ascii=False))


def main() -> int:
    ents = entries()
    queued = [e for e in ents if e["state"] == " "]
    asks = [e for e in ents if e["state"] == "?"]
    sent = [e for e in ents if e["state"] == "x"]
    done = [e for e in ents if e["state"] == "!"]

    tip = ["LEDGER — ~/.hermes/ledger.md", ""]
    if asks:
        tip.append(f"FOR PRIME ({len(asks)}):")
        tip += [line_of(e) for e in asks[-4:]]
        tip.append("")
    if queued:
        tip.append(f"QUEUED TO SEND ({len(queued)}):")
        tip += [line_of(e) for e in queued[-4:]]
        tip.append("")
    if sent:
        tip.append("LAST SENT:")
        tip += [line_of(e) for e in sent[-3:]]
        tip.append("")
    if done:
        tip.append(f"handled so far: {len(done)}")
        tip.append("")
    tip += ["Click  → menu: paste anything in, copy, note, attach, read",
            "Paste  → the clipboard goes in as-is: text · photo · file · link",
            "Middle → read the whole ledger",
            "Right  → menu"]

    if asks:
        emit(f"{ICON} ▸{len(asks)} {clip(asks[-1]['text'])}", "ask", escape("\n".join(tip)))
    elif queued:
        emit(f"{ICON} {len(queued)} {clip(queued[-1]['text'])}", "out", escape("\n".join(tip)))
    else:
        emit(f"{ICON} ledger", "idle", escape("\n".join(tip)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

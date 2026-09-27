#!/usr/bin/python3
"""Waybar pill for the Prime bar input (custom/hermes).

Reads the state file prime-bar.py publishes and renders one JSON line. Cheap:
no network, no agent, just a stat + read per second, so a 1s interval is fine.

  idle     󰚩                 nothing running — click to type
  busy     󰚩 ..              a turn is in flight (spinner)
  done     󰚩 <first words>   the reply, for a minute, then back to idle
  pending  󰚩 sent            submitted, no reply inside the watch window
  warn     󰚩 ✕               the submit itself failed

  click        type a prompt (goes to the chat on screen)
  right-click  type a prompt into a NEW chat
  middle-click show the last reply in a popup
"""
from __future__ import annotations

import json
import os
import time
from html import escape

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
STATE = os.path.join(RUNTIME, "prime-bar.state")

ICON = "\U000f06a9"          # nf-md-robot
PILL_CHARS = 42              # the pill is a fixed-width field (see style-macos.css)
DONE_WINDOW = 60             # seconds a finished reply stays in the pill
WARN_WINDOW = 90


def read_state() -> dict:
    try:
        with open(STATE, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def alive(pid) -> bool:
    try:
        pid = int(pid or 0)
    except (TypeError, ValueError):
        return False
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def clip(text: str, limit: int = PILL_CHARS) -> str:
    flat = " ".join((text or "").split())
    if len(flat) <= limit:
        return flat
    cut = flat[:limit]
    space = cut.rfind(" ")
    if space > limit * 0.55:
        cut = cut[:space]
    return cut.rstrip(" ,;:.") + "…"


def emit(text: str, cls: str, tooltip: str) -> None:
    print(json.dumps({"text": text, "class": cls, "tooltip": tooltip}, ensure_ascii=False))


def main() -> int:
    state = read_state()
    status = (state.get("status") or "idle").lower()
    age = time.time() - float(state.get("ts") or 0)
    reply = state.get("reply") or ""
    prompt = state.get("prompt") or ""
    chat = state.get("chat") or ""

    hint = ("Click → type to Prime (chat on screen)\n"
            "Right-click → new chat\n"
            "Middle-click → last reply\n"
            "Super+R → hold to talk")

    if status == "thinking" and (alive(state.get("pid")) or age < 20):
        frames = ["", " .", " ..", " ..."]
        # A turn running in another process may outlive this one; the spinner is
        # driven by the clock so the pill never looks frozen.
        frame = frames[int(time.time()) % len(frames)]
        tip = f"Working on: {clip(prompt, 120)}\n{chat}"
        if age > 120:
            tip += f"\n({int(age)}s)"
        emit(f"{ICON}{frame}", "busy", tip)
        return 0

    if status == "done" and age < DONE_WINDOW and reply:
        tip = escape(clip(reply, 700))
        if chat:
            tip += f"\n\n<span alpha='60%'>→ {escape(chat)}</span>"
        emit(f"{ICON}  {clip(reply)}", "done", tip)
        return 0

    if status == "pending" and age < 600:
        emit(f"{ICON}  sent", "done", "Submitted — no reply inside the watch window yet.\nCheck the app.")
        return 0

    if status in {"error", "warn"} and age < WARN_WINDOW:
        emit(f"{ICON}  ✕", "warn", escape(f"Failed: {clip(reply or chat, 200)}"))
        return 0

    if status == "command" and age < DONE_WINDOW:
        emit(f"{ICON}  {clip(reply or chat)}", "done", escape(clip(reply or chat, 300)))
        return 0

    # Idle is the resting state of a permanently visible bar field: it should read
    # as "type here", not as a mystery glyph. The caret blinks so it is obviously
    # an input and not a status light.
    caret = "▏" if int(time.time()) % 2 == 0 else " "
    emit(f"{ICON}  Ask Prime…{caret}", "idle", hint)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""prime-board-pill.py — the waybar text for the whiteboard button.

Waybar runs this every couple of seconds and wants one JSON line. It reports the
thing worth knowing at a glance: is the board service alive, how many panels are
up, and whether the board window is on screen — the button's click does the rest
(prime-board.sh).

    {"text": "󰆏 board", "class": "on", "tooltip": "…"}
"""
import json
import os
import subprocess
import sys
import urllib.request

SERVICE = "prime-whiteboard.service"
URL = "http://localhost:8777/"
WB = os.path.expanduser("~@STUDY_DIR@/whiteboard/wb.py")


def run(cmd, timeout=4):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return out.stdout.strip()
    except Exception:
        return ""


def service_up():
    return run(["systemctl", "--user", "is-active", SERVICE]) == "active"


def board_reachable():
    try:
        with urllib.request.urlopen(URL, timeout=2) as r:
            return r.status == 200
    except Exception:
        return False


def panels():
    out = run(["python3", WB, "list"])
    return [line for line in out.splitlines() if line.strip()]


def window_open():
    try:
        clients = json.loads(run(["hyprctl", "clients", "-j"], timeout=3) or "[]")
    except Exception:
        return False, None
    for c in clients:
        if "Prime's Whiteboard" in (c.get("title") or ""):
            return True, c.get("workspace", {}).get("id")
    return False, None


def main():
    up = service_up()
    titles = panels()
    n = len(titles)
    open_, ws = window_open()

    if not up:
        cls, text = "warn", "󰆏 board"
        tip = "Prime's Whiteboard service is DOWN\nClick to start it and open the board"
    elif n == 0:
        cls, text = "idle", "󰆏 board"
        tip = "Board is empty — click to open it, then ask for a lesson"
    else:
        cls, text = "on", f"󰆏 {n}"
        first = titles[0].split("  ")[-1].strip()
        where = f"window open on ws {ws}" if open_ else "window closed"
        tip = (f"Prime's Whiteboard — {n} panel(s)\n"
               f"Top: {first[:70]}\n{where}\n"
               "Left-click: show the board · Middle: activity timeline · Right: menu")

    sys.stdout.write(json.dumps({
        "text": text,
        "class": cls,
        "tooltip": tip,
    }, ensure_ascii=False))


if __name__ == "__main__":
    main()

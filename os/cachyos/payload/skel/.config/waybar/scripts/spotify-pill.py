#!/usr/bin/python3
"""Spotify / MPRIS pill for waybar (custom/spotify + custom/spotifySkip).

  spotify-pill.py                 status line (waybar polls this once a second)
  spotify-pill.py transport       just the play/pause glyph (its own bar button)
  spotify-pill.py next            skip forward        (right-click, or the ⏭ pill)
  spotify-pill.py prev            previous track      (middle-click, ⏭ right-click)
  spotify-pill.py toggle          play / pause        (left-click; launches Spotify if down)
  spotify-pill.py volup | voldown ±5%                 (scroll on either pill)

Player choice: Spotify when it is running (that is the widget he asked for),
otherwise whatever MPRIS player is publishing — YouTube in a browser still shows.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from html import escape

SEP = "\x1f"                       # a byte that never appears in a track title
PREFERRED = ("spotify",)
TEXT_BUDGET = 42                   # visible pill width for "title — artist"
BAR_WIDTH = 12

SPOTIFY_LAUNCH = (
    shutil.which("spotify-launcher")
    or os.path.expanduser("~/.local/share/spotify-launcher/install/usr/share/spotify/spotify")
)


def players() -> list[str]:
    try:
        out = subprocess.run(["playerctl", "-l"], capture_output=True, text=True, timeout=4)
    except (OSError, subprocess.SubprocessError):
        return []
    return [line.strip() for line in (out.stdout or "").splitlines() if line.strip()]


def pick_player() -> str:
    found = players()
    for want in PREFERRED:
        for name in found:
            if name.startswith(want):
                return name
    for name in found:
        if name.startswith("chromium") or name.startswith("firefox"):
            continue
        return name
    return found[0] if found else ""


def pctl(player: str, *args: str, timeout: float = 4.0) -> str:
    cmd = ["playerctl", "-p", player, *args] if player else ["playerctl", *args]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    return (out.stdout or "").strip()


def meta(player: str) -> dict:
    fmt = SEP.join([
        "{{status}}", "{{title}}", "{{artist}}", "{{album}}",
        "{{position}}", "{{mpris:length}}", "{{playerName}}",
    ])
    raw = pctl(player, "metadata", "--format", fmt)
    parts = raw.split(SEP) if raw else []
    parts += [""] * (7 - len(parts))
    status, title, artist, album, position, length, name = parts[:7]
    try:
        position_us, length_us = int(position or 0), int(length or 0)
    except ValueError:
        position_us = length_us = 0
    return {
        "status": (status or "Stopped").strip(),
        "title": (title or "").strip(),
        "artist": (artist or "").strip(),
        "album": (album or "").strip(),
        "pos": position_us,
        "len": length_us,
        "name": (name or player).strip(),
    }


def clock(us: int) -> str:
    total = max(0, us) // 1_000_000
    return f"{total // 60}:{total % 60:02d}"


def bar(pos: int, length: int, width: int = BAR_WIDTH) -> str:
    if length <= 0:
        return ""
    frac = min(max(pos / length, 0.0), 1.0)
    at = int(round(frac * (width - 1)))
    return "".join("●" if i == at else "─" for i in range(width))


def clip(text: str, limit: int) -> str:
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    cut = text[:limit]
    space = cut.rfind(" ")
    if space > limit * 0.55:
        cut = cut[:space]
    return cut.rstrip(" ,;:-–—") + "…"


def emit(text: str, cls: str, tooltip: str) -> None:
    print(json.dumps({"text": text, "class": cls, "tooltip": tooltip}, ensure_ascii=False))


def launch_spotify() -> None:
    if SPOTIFY_LAUNCH and os.path.exists(SPOTIFY_LAUNCH):
        subprocess.Popen(
            ["setsid", SPOTIFY_LAUNCH], stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, start_new_session=True,
        )


def status_line() -> int:
    player = pick_player()
    if not player:
        tip = ("Spotify isn't publishing to MPRIS.\n"
               "Left-click to launch it.  (Launch needs spotify-launcher.)")
        emit("\U000f04c7", "stopped", tip)
        return 0

    m = meta(player)
    status = m["status"].lower()
    title = m["title"] or "Nothing playing"
    artist = m["artist"]

    if status == "playing":
        icon, cls = "\U000f04c7", "playing"
    elif status == "paused":
        icon, cls = "\U000f03e4", "paused"
    else:
        icon, cls = "\U000f04c7", "stopped"

    body = f"{title} — {artist}" if artist else title
    line = f"{icon}  {escape(clip(body, TEXT_BUDGET))}"

    rows = [f"<b>{escape(clip(title, 70))}</b>"]
    if artist:
        rows.append(escape(clip(artist, 70)))
    if m["album"]:
        rows.append(f"<span alpha='65%'>{escape(clip(m['album'], 70))}</span>")
    timeline = bar(m["pos"], m["len"])
    if timeline:
        rows.append(f"<span alpha='80%'>{clock(m['pos'])} {timeline} {clock(m['len'])}</span>")
    rows.append(f"<span alpha='55%'>{escape(m['name'])} · {m['status']}</span>")
    rows.append("<span alpha='45%'>left play/pause · right next · middle previous · scroll volume</span>")

    emit(line, cls, "\n".join(rows))
    return 0


def transport_line() -> int:
    """Just the play/pause glyph — its own button in the transport group.

    Same player resolution as the status line, so the icon always matches what
    the title pill is showing (Spotify first, then any non-browser MPRIS player).
    """
    player = pick_player()
    if not player:
        emit("\U000f040a", "stopped", "Play (launches Spotify)")
        return 0

    m = meta(player)
    status = m["status"].lower()
    label = f"{m['title']} — {m['artist']}" if m["artist"] else (m["title"] or "Nothing playing")

    if status == "playing":
        emit("\U000f03e4", "playing", f"Pause\n<b>{escape(clip(label, 70))}</b>")
    else:
        cls = "paused" if status == "paused" else "stopped"
        emit("\U000f040a", cls, f"Play\n<b>{escape(clip(label, 70))}</b>")
    return 0


def do_action(action: str) -> int:
    player = pick_player()
    if not player:
        if action in {"toggle", "play"}:
            launch_spotify()
        return 0

    if action == "toggle":
        pctl(player, "play-pause")
    elif action == "play":
        pctl(player, "play")
    elif action == "pause":
        pctl(player, "pause")
    elif action == "next":
        pctl(player, "next")
    elif action == "prev":
        pctl(player, "previous")
    elif action == "volup":
        pctl(player, "volume", "0.05+")
    elif action == "voldown":
        pctl(player, "volume", "0.05-")
    return 0


def main() -> int:
    action = (sys.argv[1] if len(sys.argv) > 1 else "status").lower()
    if action in {"", "status"}:
        return status_line()
    if action == "transport":
        return transport_line()
    return do_action(action)


if __name__ == "__main__":
    raise SystemExit(main())

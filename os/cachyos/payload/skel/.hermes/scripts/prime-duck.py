#!/usr/bin/env python3
"""Duck other playback while Prime speaks, then put it back exactly.

@USER@'s ask: "when you're talking, lower the other audio so I can hear you
clearly". So while a clip is being played, every other playback stream drops to a
fraction of its volume and is restored to the exact value it had — he keeps his
music, he just hears the reply over it.

The Hermes desktop app's own voice is the stream with ``application.name ==
Chromium`` (Electron); everything else (Spotify, Chrome/YouTube) is fair game.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
STATE = os.path.join(RUNTIME, "prime-duck.json")
# Never duck our own voice: "Chromium" is the Hermes app's playback, and the rest
# are the players prime-speak.py uses to say the reply. Ducking the player is how
# the voice ended up at a hundredth of a percent — the duck multiplied its own
# volume every cycle and WirePlumber remembered the result.
OWN_APPS = {"Chromium", "ffplay", "mpv", "pw-play", "paplay", "cvlc", "vlc", "ffmpeg"}
DUCK_LEVEL = float(os.environ.get("PRIME_DUCK_LEVEL", "0.25"))  # ≈ -12 dB under the voice (radio bed)


def note(message: str) -> None:
    """Leave a trail: 'the music never dropped' needs an answer faster than a re-run."""
    try:
        with open(os.path.join(RUNTIME, "prime-duck.log"), "a", encoding="utf-8") as fh:
            fh.write(f"{time.strftime('%H:%M:%S')} {message}\n")
    except OSError:
        pass


def streams() -> list[dict]:
    raw = subprocess.run(
        ["pactl", "-f", "json", "list", "sink-inputs"],
        capture_output=True,
        text=True,
        timeout=10,
    ).stdout
    try:
        return json.loads(raw or "[]")
    except json.JSONDecodeError:
        return []


def first_volume(stream: dict) -> int | None:
    for channel in (stream.get("volume") or {}).values():
        value = channel.get("value")
        if isinstance(value, int) and value > 0:
            return value
    return None


def set_volume(index: int, value: int) -> None:
    subprocess.run(
        ["pactl", "set-sink-input-volume", str(index), str(value)],
        capture_output=True,
        timeout=10,
    )


def fade_to(index: int, start: int, end: int, seconds: float) -> None:
    """Ramp the volume instead of jumping it, so the duck feels like a radio
    sidechain rather than a mute button. ~15 ms attack and ~400 ms release are
    the broadcast norm; a short linear ramp gets most of the way there."""
    steps = max(1, int(seconds / 0.04))
    for i in range(1, steps + 1):
        value = int(start + (end - start) * (i / steps))
        set_volume(index, value)
        time.sleep(0.04)


def duck() -> int:
    # Idempotent on purpose. A chunked reply calls this once per chunk, and a
    # second duck would save the *already ducked* volume as the value to restore —
    # each pass multiplying the app's volume again (that is how one player ended up
    # at a hundredth of a percent and stayed there). Extending the restore timer is
    # the caller's job; the levels get touched once per burst.
    if os.path.exists(STATE):
        note("already ducked — levels left as they are")
        print("already ducked")
        return 0

    saved: dict[str, int] = {}
    for stream in streams():
        app = (stream.get("properties") or {}).get("application.name", "")
        if app in OWN_APPS:
            continue  # our own voice, or the player carrying it — leave it alone
        volume = first_volume(stream)
        if volume is None:
            continue
        index = int(stream["index"])
        saved[str(index)] = volume
        fade_to(index, volume, max(1, int(volume * DUCK_LEVEL)), 0.25)
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump(saved, fh)
    note(f"ducked {len(saved)}: {sorted(saved)}")
    print(f"ducked {len(saved)} stream(s) to {int(DUCK_LEVEL * 100)}%")
    return 0


def restore() -> int:
    try:
        with open(STATE, encoding="utf-8") as fh:
            saved = json.load(fh)
    except (OSError, json.JSONDecodeError):
        print("nothing was ducked")
        return 0
    for index, volume in saved.items():
        fade_to(int(index), max(1, int(volume * DUCK_LEVEL)), int(volume), 0.4)
    try:
        os.remove(STATE)
    except OSError:
        pass
    note(f"restored {len(saved)}")
    print(f"restored {len(saved)} stream(s)")
    return 0


if __name__ == "__main__":
    action = sys.argv[1] if len(sys.argv) > 1 else "duck"
    sys.exit(duck() if action == "duck" else restore())

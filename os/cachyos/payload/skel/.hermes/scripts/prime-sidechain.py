#!/usr/bin/env python3
"""Play the reply with a real sidechain duck — the music breathes around the voice.

The flat duck lowered the music for the whole clip, which is why it never sounded
like the voice and the track were mixed together: the bed just sat low. This reads
the voice's own energy envelope and drives the music down only while there are
actually words, floating it back up in every pause, the way broadcast duckers do.

Usage: prime-sidechain.py <voice.mp3>
  - finds the music stream(s) (everything except our own players),
  - computes the voice envelope (RMS per 100 ms),
  - plays the voice while stepping the music volume in time with the envelope,
  - restores the music to its exact starting level at the end.
"""
from __future__ import annotations

import json
import os
import struct
import subprocess
import sys
import time

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
PIDFILE = os.path.join(RUNTIME, "prime-speak.player.pid")
OWN_APPS = {"Chromium", "ffplay", "mpv", "pw-play", "paplay", "cvlc", "vlc", "ffmpeg"}
DUCK_FRAC = float(os.environ.get("PRIME_DUCK_FRAC", "0.75"))  # music stays clearly up under the voice
DUCK_DEPTH_DB = float(os.environ.get("PRIME_DUCK_DEPTH_DB", "0"))  # unused; frac is the knob
FRAME_S = 0.10
ATTACK_FRAMES = 2   # ~200 ms ramp down
RELEASE_FRAMES = 5  # ~500 ms ramp back up


def streams() -> list[dict]:
    raw = subprocess.run(["pactl", "-f", "json", "list", "sink-inputs"],
                         capture_output=True, text=True, timeout=10).stdout
    try:
        return json.loads(raw or "[]")
    except json.JSONDecodeError:
        return []


def music_streams() -> list[tuple[int, int]]:
    """(index, base_volume) for every non-own stream, captured once."""
    out = []
    for s in streams():
        props = s.get("properties") or {}
        if props.get("application.name") in OWN_APPS:
            continue
        for ch in (s.get("volume") or {}).values():
            out.append((int(s["index"]), int(ch.get("value", 0))))
            break
    return out


def set_volume(index: int, value: int) -> None:
    subprocess.run(["pactl", "set-sink-input-volume", str(index), str(value)],
                   capture_output=True, timeout=10)


def envelope(mp3: str) -> tuple[list[float], float]:
    """RMS energy per FRAME_S over the mono downmix, 0..1 normalized."""
    proc = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", mp3, "-ac", "1", "-ar", "16000",
         "-f", "s16le", "-"],
        capture_output=True, timeout=120,
    )
    if proc.returncode != 0:
        return [1.0], 1.0
    pcm = proc.stdout
    n = len(pcm) // 2
    samples = struct.unpack(f"<{n}h", pcm[: n * 2])
    per = int(16000 * FRAME_S)
    frames = []
    for i in range(0, len(samples), per):
        chunk = samples[i:i + per]
        rms = (sum(x * x for x in chunk) / max(1, len(chunk))) ** 0.5
        frames.append(rms)
    if not frames:
        return [1.0], 1.0
    peak = max(frames) or 1
    return [min(1.0, f / peak) for f in frames], len(frames) * FRAME_S


def smooth(frames: list[float]) -> list[float]:
    """Light attack/release smoothing so the music moves, not jumps."""
    out = []
    last = 0.0
    for f in frames:
        if f > last:
            f = last + (f - last) / ATTACK_FRAMES
        else:
            f = last + (f - last) / RELEASE_FRAMES
        out.append(f)
        last = f
    return out


def main() -> int:
    mp3 = sys.argv[1]
    targets = music_streams()
    if not targets:
        # Nothing else playing: just play the voice, no duck to drive.
        player = subprocess.Popen(
            ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", mp3],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with open(PIDFILE, "w") as fh:
            fh.write(str(player.pid))
        player.wait()
        return 0

    env, _dur = envelope(mp3)
    env = smooth(env)

    # Snapshot the music at full level so we restore exactly.
    player = subprocess.Popen(
        ["ffplay", "-nodisp", "-autoexit", "-loglevel", "quiet", mp3],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    with open(PIDFILE, "w") as fh:
        fh.write(str(player.pid))

    # Force our own player to full volume (see prime-speak.py) then run the duck
    # in time with the voice.
    for _ in range(20):
        time.sleep(0.2)
        ours = [s for s in streams()
                if str((s.get("properties") or {}).get("application.process.id")) == str(player.pid)]
        if ours:
            set_volume(int(ours[0]["index"]), 65536)
            subprocess.run(["pactl", "set-sink-input-mute", str(ours[0]["index"]), "0"],
                           capture_output=True, timeout=10)
            break

    frame_i = 0
    while player.poll() is None:
        level = env[min(frame_i, len(env) - 1)]
        for index, base in targets:
            # level 1.0 -> music at DUCK_FRAC; level 0.0 -> music at full.
            value = int(base * (DUCK_FRAC + (1.0 - DUCK_FRAC) * (1.0 - level)))
            set_volume(index, value)
        frame_i += 1
        time.sleep(FRAME_S)

    # Restore exact starting levels.
    for index, base in targets:
        set_volume(index, base)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Speak Prime's replies with a playback path we actually control.

Why not the desktop app's read-aloud: on this machine it reports "playing" while
the output mix stays at the noise floor — measured, not guessed — and its
barge-in only muted the stream, which left the app hushed for good. This speaks
the reply itself instead:

  reply lands in the session  ->  tts-quiet.sh (free edge voice, gain, ducking)
  ->  ffplay to the default sink  ->  killed the instant Super+R goes down.

Run as a systemd user service (prime-speak.service). One instance only.
"""
from __future__ import annotations

import glob
import importlib.util
import json
import os
import re
import sqlite3
import subprocess
import sys
import time

DB = os.path.expanduser("~/.hermes/state.db")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
CURSOR = os.path.join(RUNTIME, "prime-speak.cursor")
PIDFILE = os.path.join(RUNTIME, "prime-speak.player.pid")
SYNTH = os.path.expanduser("~/.hermes/scripts/tts-quiet.sh")
CACHE = os.path.expanduser("~/.hermes/cache/prime-speak")
# Voice on/off switch - the waybar button next to "snip" toggles this file.
# Deliberately NOT in $XDG_RUNTIME_DIR: if @USER@ silences Prime it should stay
# silenced across reboots. Replies that arrive while muted still advance the
# cursor, so unmuting never replays a backlog of old replies out loud.
MUTE = os.path.expanduser("~/.hermes/prime-speak.muted")


def muted() -> bool:
    return os.path.exists(MUTE)

# Load the sender's helpers so the target session is resolved exactly the way a
# take is submitted (same gateway, same "current session" rule).
_spec = importlib.util.spec_from_file_location(
    "ptt_send", os.path.expanduser("~/.hermes/scripts/prime-ptt-send.py")
)
ptt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(ptt)

# Never speak these: compression handoffs, system notes, skill bodies.
SKIP_PREFIXES = ("[PRIOR CONTEXT", "[CONTEXT COMPACTION", "[System note", "[IMPORTANT:", "[Skill")


def log(message: str) -> None:
    stamp = time.strftime("%H:%M:%S")
    print(f"[prime-speak] {stamp} {message}", flush=True)


def read_cursor() -> tuple[str, int]:
    try:
        with open(CURSOR, encoding="utf-8") as fh:
            key, last = fh.read().split()
        return key, int(last)
    except (OSError, ValueError):
        return "", 0


def write_cursor(key: str, last: int) -> None:
    try:
        with open(CURSOR, "w", encoding="utf-8") as fh:
            fh.write(f"{key} {last}\n")
    except OSError:
        pass


def session_key() -> str:
    """Durable id of the chat whose replies should be spoken.

    Same decision a take makes (see ``ptt.spoken_target``): the live voice thread
    or the chat on screen, whichever had the newest human turn — never the
    gateway's "most recently active", which pointed elsewhere when another chat
    was running and left replies unspoken.
    """
    try:
        import asyncio

        port = ptt.backend_port()
        token = ptt.session_token(port)
        return asyncio.run(ptt.spoken_target(port, token))
    except Exception as exc:  # noqa: BLE001 - speakers must never crash the loop
        log(f"session lookup failed: {exc}")
        return ""


def speakable(text: str) -> str:
    if not text or len(text.strip()) < 40:
        return ""
    if text.lstrip().startswith(SKIP_PREFIXES):
        return ""
    if "tool_calls" in text[:40]:
        return ""
    # Markdown reads badly aloud; keep it light-touch.
    clean = re.sub(r"`{1,3}([^`]*)`{1,3}", r"\1", text)
    clean = re.sub(r"[*_#>]+", "", clean)
    clean = re.sub(r"^\s*[-•]\s*", "", clean, flags=re.M)
    clean = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", clean)
    return clean.strip()


def stop_player() -> None:
    try:
        with open(PIDFILE, encoding="utf-8") as fh:
            pid = int(fh.read().strip())
        os.kill(pid, 15)
    except (OSError, ValueError):
        pass


def ensure_player_volume(pid: int) -> None:
    """Force the player's stream to full volume, unmuted.

    WirePlumber remembers a per-app volume, and an earlier duck left the player's
    at ~0.0016% — a stream that inherits that starts out essentially silent even
    though everything else is right. Set it the instant the stream appears.
    """
    for _ in range(20):
        time.sleep(0.2)
        raw = subprocess.run(
            ["pactl", "-f", "json", "list", "sink-inputs"],
            capture_output=True,
            text=True,
            timeout=10,
        ).stdout
        try:
            rows = json.loads(raw or "[]")
        except json.JSONDecodeError:
            continue
        for stream in rows:
            props = stream.get("properties") or {}
            if str(props.get("application.process.id")) == str(pid):
                subprocess.run(
                    ["pactl", "set-sink-input-volume", str(stream["index"]), "100%"],
                    capture_output=True,
                    timeout=10,
                )
                subprocess.run(
                    ["pactl", "set-sink-input-mute", str(stream["index"]), "0"],
                    capture_output=True,
                    timeout=10,
                )
                log(f"player volume forced to 100% (stream {stream['index']})")
                return


def speak(text: str) -> None:
    os.makedirs(CACHE, exist_ok=True)
    txt = os.path.join(CACHE, "line.txt")
    mp3 = os.path.join(CACHE, "line.mp3")
    with open(txt, "w", encoding="utf-8") as fh:
        fh.write(text + "\n")

    # The flat duck (inside tts-quiet.sh) is gone — the sidechain owns the duck.
    # Pass the flag to BOTH calls, otherwise synthesis still fires the old flat
    # duck and drops the music to ~25% before playback even starts.
    env = dict(os.environ, PRIME_TTS_DUCK="0")

    if subprocess.run(["bash", SYNTH, txt, mp3], env=env, capture_output=True).returncode != 0:
        log("synthesis failed")
        return

    # Play via the sidechain: the music dips only while the words are actually
    # there and floats back up in every pause, so the voice and track move as one.
    sidechain = os.path.expanduser("~/.hermes/scripts/prime-sidechain.py")
    subprocess.run([sys.executable, sidechain, mp3], env=env)
    time.sleep(0.5)


def main() -> int:
    log("watching for replies to speak")
    key, last_id = read_cursor()
    last_resolve = 0.0

    while True:
        now = time.time()

        if not key or now - last_resolve > 5:
            resolved = session_key()
            last_resolve = now
            if resolved and resolved != key:
                key = resolved
                # Start from the newest message so a restart never replays history.
                con = sqlite3.connect(DB)
                row = con.execute(
                    "SELECT COALESCE(MAX(id), 0) FROM messages WHERE session_id = ?", (key,)
                ).fetchone()
                con.close()
                last_id = int(row[0] or 0)
                write_cursor(key, last_id)
                log(f"following session {key} from message {last_id}")

        if key:
            try:
                con = sqlite3.connect(DB)
                rows = con.execute(
                    "SELECT id, role, content FROM messages "
                    "WHERE session_id = ? AND id > ? AND role = 'assistant' AND active = 1 "
                    "ORDER BY id LIMIT 5",
                    (key, last_id),
                ).fetchall()
                con.close()
            except sqlite3.Error as exc:
                log(f"db read failed: {exc}")
                rows = []

            for row_id, _role, content in rows:
                last_id = max(last_id, int(row_id))
                write_cursor(key, last_id)
                to_say = speakable(content or "")
                if to_say and muted():
                    # Cursor already advanced above, so nothing is queued up.
                    log(f"muted - staying silent on reply {row_id}")
                elif to_say:
                    log(f"speaking reply {row_id} ({len(to_say)} chars)")
                    speak(to_say)

        time.sleep(1.0)


if __name__ == "__main__":
    sys.exit(main())

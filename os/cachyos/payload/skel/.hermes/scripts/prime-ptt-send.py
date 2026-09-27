#!/usr/bin/env python3
"""Prime hold-to-talk: transcribe a take and submit it to the desktop session.

Called by prime-ptt-up.sh with the WAV path. Steps:

1. Transcribe with Hermes' own STT provider (``stt.provider`` in config.yaml —
   locally faster-whisper large-v3-turbo, so no audio leaves the machine).
2. Ask the desktop backend which session is in the foreground
   (``session.active_list`` -> ``current``), so the turn lands in the chat window
   @USER@ is actually looking at.
3. Submit it with ``prompt.submit`` over the backend's local JSON-RPC WebSocket.

The desktop app is the single agent process, so its UI streams the turn, the
agent's tool work, and (with voice.auto_tts on) speaks the reply. Exit code is
0 for "handled" — including "no speech" — so a quiet press never looks like an
error, non-zero only when the pipeline itself broke.
"""
from __future__ import annotations

import asyncio
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.request

REPO = os.path.expanduser("~/.hermes/hermes-agent")
sys.path.insert(0, REPO)

# Mirrors the desktop app's own dictation wrapper so spoken replies stay short
# and speech-friendly, exactly as if he had used the in-app mic.
VOICE_PREFIX = (
    "[Voice input — respond concisely and conversationally, 2-3 sentences max. "
    "No code blocks or markdown.] "
)


def log(msg: str) -> None:
    print(f"[prime-ptt] {msg}", file=sys.stderr)
    try:
        runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        with open(os.path.join(runtime, "prime-ptt.log"), "a", encoding="utf-8") as fh:
            import time

            fh.write(f"{time.strftime('%H:%M:%S')} {msg}\n")
    except OSError:
        pass


def _notify_id_file() -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(runtime, "prime-ptt.notifyid")


def close_notify() -> None:
    """Drop the hold-to-talk bubble by the id the daemon actually assigned.

    swaync ignores replaces_id and stacks instead, so the real id (from
    `notify-send -p`) is tracked in a file the shell scripts share.
    """
    import shutil
    import subprocess

    path = _notify_id_file()
    try:
        with open(path, encoding="utf-8") as fh:
            notify_id = fh.read().strip()
    except OSError:
        return
    if not notify_id or not shutil.which("gdbus"):
        return
    try:
        subprocess.run(
            [
                "gdbus", "call", "--session",
                "--dest", "org.freedesktop.Notifications",
                "--object-path", "/org/freedesktop/Notifications",
                "--method", "org.freedesktop.Notifications.CloseNotification",
                notify_id,
            ],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:  # pragma: no cover
        pass
    try:
        os.unlink(path)
    except OSError:
        pass


def status(kind: str, note: str = "") -> None:
    """Publish the take's outcome for the Waybar module (prime-voice.sh)."""
    import time

    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    try:
        with open(os.path.join(runtime, "prime-ptt.status"), "w", encoding="utf-8") as fh:
            fh.write(f"{kind} {int(time.time())} {note}\n")
    except OSError:
        pass


def notify(title: str, body: str, expire: int = 2500) -> None:
    """Show the outcome in the single hold-to-talk bubble (replacing the last)."""
    import shutil
    import subprocess

    if not shutil.which("notify-send"):
        return
    args = ["notify-send", "-p"]
    path = _notify_id_file()
    try:
        with open(path, encoding="utf-8") as fh:
            previous = fh.read().strip()
        if previous:
            args += ["-r", previous]
    except OSError:
        pass
    args += ["-t", str(expire), title, body]
    try:
        done = subprocess.run(
            args, check=False, capture_output=True, text=True, timeout=5
        )
        assigned = (done.stdout or "").strip()
        if assigned:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(assigned)
    except Exception:  # pragma: no cover - best-effort UI nicety
        pass


def take_quality(wav: str) -> tuple[float, float]:
    """(peak dBFS, seconds) of a take.

    A quiet or near-empty take is how a transcriber invents a sentence out of room
    noise — a 0.8s silence once came back as a sentence that had nothing to do with
    anyone, and it got submitted as a message. Measure first, transcribe after.
    """
    peak = -99.0
    seconds = 0.0

    try:
        detect = subprocess.run(
            ["ffmpeg", "-hide_banner", "-i", wav, "-af", "volumedetect", "-f", "null", "-"],
            capture_output=True,
            text=True,
            timeout=30,
        ).stderr
        found = re.search(r"max_volume:\s*(-?[\d.]+) dB", detect)
        if found:
            peak = float(found.group(1))

        probe = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", wav],
            capture_output=True,
            text=True,
            timeout=15,
        ).stdout.strip()
        seconds = float(probe) if probe else 0.0
    except (OSError, ValueError, subprocess.SubprocessError):
        pass

    return peak, seconds


def transcribe(path: str) -> str:
    from tools.voice_mode import transcribe_recording

    result = transcribe_recording(path) or {}
    if not result.get("success"):
        log(f"STT failed: {result.get('error') or result}")
        return ""
    return (result.get("transcript") or "").strip()


def backend_port() -> int:
    """Port the desktop app's backend logged at boot (it is random per launch)."""
    log_path = os.path.expanduser("~/.hermes/logs/desktop.log")
    try:
        with open(log_path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        text = ""
    ports = re.findall(r"HERMES_BACKEND_READY port=(\d+)", text)
    if not ports:
        raise RuntimeError("desktop backend port not found in desktop.log")
    return int(ports[-1])


def session_token(port: int) -> str:
    """Loopback session token the backend injects into its own dashboard HTML."""
    url = f"http://127.0.0.1:{port}/"
    html = urllib.request.urlopen(url, timeout=5).read().decode("utf-8", "replace")
    match = re.search(r'window\.__HERMES_SESSION_TOKEN__\s*=\s*("(?:\\.|[^"\\])*")', html)
    if not match:
        raise RuntimeError("session token missing from the dashboard page")
    return json.loads(match.group(1))


async def rpc(port: int, token: str, method: str, params: dict, timeout: float = 30.0):
    import websockets

    url = f"ws://127.0.0.1:{port}/api/ws?token={token}"
    async with websockets.connect(url, max_size=16 * 1024 * 1024) as ws:
        await ws.send(json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}))
        while True:
            msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))
            if msg.get("id") == 1:
                if "error" in msg:
                    raise RuntimeError(f"{method} failed: {msg['error']}")
                return msg.get("result")


async def target_session(port: int, token: str) -> str:
    """Runtime id of the session in the foreground (what the window is showing)."""
    # Test hook: pin a specific session instead of asking the backend.
    pinned = os.environ.get("PRIME_PTT_SESSION")
    if pinned:
        return pinned
    result = await rpc(port, token, "session.active_list", {}) or {}
    sessions = result.get("sessions") or []
    if not sessions:
        raise RuntimeError("the backend reports no live sessions")
    current = [s for s in sessions if s.get("current")]
    pick = (current or sessions)[0]
    if not current:
        pick = max(sessions, key=lambda s: s.get("last_active") or 0)
    return pick.get("id") or ""


# The runtime id rotates every turn, and while the agent is mid-turn the session
# vanishes from ``session.active_list`` — which is why takes kept failing. The
# durable session_key is stable, and ``session.resume`` maps it to the LIVE
# runtime id even while the agent is busy (it reads the in-memory registry, not
# the active list). So cache the durable key, and resolve through resume.
_SESSION_CACHE = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "prime-ptt.session"
)


def cached_durable() -> str:
    try:
        with open(_SESSION_CACHE, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def remember_durable(durable: str) -> None:
    try:
        with open(_SESSION_CACHE, "w", encoding="utf-8") as fh:
            fh.write(durable + "\n")
    except OSError:
        pass


# --- Which chat is on screen ------------------------------------------------ #
# ``session.active_list`` only marks a session ``current`` when the CALLER passes
# ``current_session_id`` — that is the TUI's doing. The desktop app passes none,
# so every row came back ``current: false`` and the fallback below ("whichever
# session was most recently active") sent takes into the last BUSY chat instead of
# the one on screen. That was the mismatch: open a chat, press Super+R, and the
# words landed in a different conversation.
#
# The desktop app does record its own navigation state, per profile, in the
# app's localStorage: ``hermes.desktop.lastSessionId`` (the open chat's durable
# key) and ``hermes.desktop.lastRoute`` (``/`` = the new-chat draft,
# ``/<key>`` = that chat). That record is the same authority the app uses to
# restore what was on screen at boot, so reading it makes the take follow the
# window instead of guessing.
_LS_DIR = os.path.expanduser("~/.config/Hermes/Local Storage/leveldb")
_PROFILE = os.environ.get("PRIME_PTT_PROFILE", "default").strip() or "default"
_DURABLE_RE = re.compile(r"(\d{8}_\d{6}_[0-9a-f]{6,})")
# How long the plugin's live focus mirror stays trustworthy before the app's
# own navigation record is used instead.
_PLUGIN_FOCUS_MAX_AGE = 180.0


def _varint(data: bytes, pos: int) -> tuple:
    result = 0
    shift = 0
    while True:
        byte = data[pos]
        pos += 1
        result |= (byte & 0x7F) << shift
        if not byte & 0x80:
            return result, pos
        shift += 7


def _snappy(raw: bytes) -> bytes:
    """Decompress one snappy block (leveldb's only compression)."""
    pos = 0
    ulen = 0
    shift = 0
    while True:
        byte = raw[pos]
        pos += 1
        ulen |= (byte & 0x7F) << shift
        if not byte & 0x80:
            break
        shift += 7
    out = bytearray()
    while pos < len(raw) and len(out) < ulen:
        tag = raw[pos]
        pos += 1
        kind = tag & 3
        if kind == 0:  # literal run
            length = tag >> 2
            if length < 60:
                length += 1
            else:
                extra = length - 59
                length = int.from_bytes(raw[pos:pos + extra], "little") + 1
                pos += extra
            out += raw[pos:pos + length]
            pos += length
            continue
        if kind == 1:
            length = 4 + ((tag >> 2) & 7)
            offset = ((tag >> 5) << 8) | raw[pos]
            pos += 1
        elif kind == 2:
            length = (tag >> 2) + 1
            offset = int.from_bytes(raw[pos:pos + 2], "little")
            pos += 2
        else:
            length = (tag >> 2) + 1
            offset = int.from_bytes(raw[pos:pos + 4], "little")
            pos += 4
        start = len(out) - offset
        if start < 0:
            break
        for i in range(length):
            out.append(out[start + i])
    return bytes(out)


def _table_block(data: bytes, offset: int, size: int) -> bytes:
    """One leveldb block. On disk it is ``[contents][type byte][crc32]`` and the
    handle's size covers the contents only — the type byte sits in the trailer."""
    body = data[offset:offset + size]
    if len(body) != size:
        return b""
    kind = data[offset + size] if offset + size < len(data) else 0
    return _snappy(body) if kind == 1 else body


def _table_entries(block: bytes):
    """(key, value) pairs inside a decompressed block (prefix-compressed keys)."""
    if len(block) < 4:
        return
    restarts = int.from_bytes(block[-4:], "little")
    end = len(block) - 4 * (restarts + 1)
    pos = 0
    key = b""
    while pos < end:
        shared, pos = _varint(block, pos)
        non_shared, pos = _varint(block, pos)
        vlen, pos = _varint(block, pos)
        key = key[:shared] + block[pos:pos + non_shared]
        pos += non_shared
        value = block[pos:pos + vlen]
        pos += vlen
        yield key, value


def _table_items(path: str):
    """Walk a leveldb table file via its footer -> index -> data blocks."""
    with open(path, "rb") as fh:
        data = fh.read()
    if len(data) < 48:
        return
    footer = data[-48:]
    pos = 0
    _, pos = _varint(footer, pos)          # metaindex handle
    _, pos = _varint(footer, pos)
    index_off, pos = _varint(footer, pos)  # index handle
    index_size, pos = _varint(footer, pos)
    for _, handle in _table_entries(_table_block(data, index_off, index_size)):
        offset, p = _varint(handle, 0)
        size, _ = _varint(handle, p)
        for key, value in _table_entries(_table_block(data, offset, size)):
            yield key, value


def _log_items(path: str):
    """Walk a leveldb write-ahead .log file (32 KiB blocks of framed batches)."""
    with open(path, "rb") as fh:
        data = fh.read()
    pos = 0
    while pos + 7 <= len(data):
        length = int.from_bytes(data[pos + 4:pos + 6], "little")
        rtype = data[pos + 6]
        if not 0 < length <= 32768 - 7 or rtype not in (1, 2, 3, 4):
            # Padding at the tail of a block, or a split record: next block.
            pos = min((pos // 32768 + 1) * 32768, len(data))
            continue
        payload = data[pos + 7:pos + 7 + length]
        pos += 7 + length
        if rtype != 1 or len(payload) < 12:  # only whole batches are read
            continue
        count = int.from_bytes(payload[8:12], "little")
        cursor = 12
        for _ in range(count):
            if cursor >= len(payload):
                break
            kind = payload[cursor]
            cursor += 1
            klen, cursor = _varint(payload, cursor)
            key = payload[cursor:cursor + klen]
            cursor += klen
            if kind == 0:                     # deletion
                continue
            vlen, cursor = _varint(payload, cursor)
            yield key, payload[cursor:cursor + vlen]
            cursor += vlen


def _ls_files_newest_first() -> list:
    """Chromium localStorage leveldb files, newest write-bearing file first."""
    try:
        names = os.listdir(_LS_DIR)
    except OSError:
        return []
    paths = [os.path.join(_LS_DIR, n) for n in names if n.endswith((".log", ".ldb"))]
    paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)
    return paths


def _ls_decode(raw: bytes) -> str:
    """Stored values carry one type byte: 1 = UTF-8/Latin-1, 0 = UTF-16."""
    if not raw:
        return ""
    if raw[:1] == b"\x00":
        return raw[1:].decode("utf-16-le", "replace").strip()
    body = raw[1:] if raw[:1] == b"\x01" else raw
    return body.decode("utf-8", "replace").strip()


def _ls_read(name: str) -> str:
    """Newest stored value for a localStorage key name (read-only).

    Walks the app's Chromium leveldb, newest file first, and inside a file keeps
    the LAST entry for the key — an append-only ``.log`` carries the key's
    history, so the last write is the live one.
    """
    needle = name.encode()
    for path in _ls_files_newest_first():
        walk = _log_items if path.endswith(".log") else _table_items
        found = ""
        try:
            for key, value in walk(path):
                if needle in key:
                    found = value
        except Exception:  # noqa: BLE001 - the DB rotates while the app runs
            continue
        if found:
            return _ls_decode(found)
    return ""


def desktop_focus() -> tuple:
    """(durable key, route, title, source) for the chat the window is showing.

    The ``prime-voice`` desktop plugin mirrors the focused chat (with its title)
    into localStorage every ~1.2s, which is the freshest answer and the one that
    also covers a draft. When that record is stale (plugin not loaded, app not
    running), fall back to the app's own navigation record: ``route`` is ``/``
    while the window sits on a new-chat draft and ``/<key>`` for a chat.
    """
    raw = _ls_read("prime-voice.focus")
    if raw:
        try:
            live = json.loads(raw)
        except ValueError:
            live = None
        if isinstance(live, dict):
            age = time.time() - (float(live.get("at") or 0) / 1000.0)
            if age < _PLUGIN_FOCUS_MAX_AGE:
                return (
                    str(live.get("key") or ""),
                    f"/{live.get('key')}" if live.get("key") else "/",
                    str(live.get("title") or ""),
                    "plugin",
                )

    route = _ls_read(f"hermes.desktop.lastRoute.profile.{_PROFILE}")
    chat = _ls_read(f"hermes.desktop.lastSessionId.profile.{_PROFILE}")
    key = ""
    match = _DURABLE_RE.search(route or chat)
    if match:
        key = match.group(1)
    return key, route, "", "nav-record"


# --- Taking a chat with you ------------------------------------------------- #
# "new topic, …" starts a fresh chat, "switch to the <name> chat" moves to an
# existing one, "name this chat <x>" titles the current one so it is findable
# by voice later. A command with no payload is remembered and applied to the
# NEXT take, so a bare "new topic" costs one extra breath instead of creating an
# empty chat nobody talks in.
_NEW_TOPIC_RE = re.compile(
    r"^\s*(?:hey\s+prime[,\s]+)?(?:please\s+)?"
    r"(?:new topic|new chat|fresh chat|new conversation|new thread"
    r"|start\s+(?:a\s+)?new\s+(?:topic|chat|conversation|thread)"
    r"|let'?s\s+(?:start|begin)\s+a\s+new\s+(?:topic|chat|conversation))"
    r"\b[\s,:.\-–—]*(?P<rest>.*)$",
    re.IGNORECASE | re.DOTALL,
)
_STRONG_SWITCH_RE = re.compile(
    r"^\s*(?:hey\s+prime[,\s]+)?(?:please\s+)?"
    r"(?:switch|swap)\b[\s,]*(?:me\s+|us\s+)?"
    r"(?:to|into|back\s+to|over\s+to)?\s+(?P<target>.+)$",
    re.IGNORECASE | re.DOTALL,
)
# "go to the gutter chat" is chat control; "go to the store and buy milk" is a
# message — so a weak verb only counts when he actually says the word "chat".
_WEAK_SWITCH_RE = re.compile(
    r"^\s*(?:hey\s+prime[,\s]+)?(?:please\s+)?"
    r"(?:jump|move|take me|go)\b[\s,]*(?:me\s+|us\s+)?"
    r"(?:to|into|back\s+to|over\s+to)?\s+(?P<target>.+)$",
    re.IGNORECASE | re.DOTALL,
)
_NAME_RE = re.compile(
    r"^\s*(?:hey\s+prime[,\s]+)?(?:please\s+)?"
    r"(?:name|call|title)\s+(?:this|the)\s+(?:chat|conversation|thread|session)\b"
    r"[\s,:.\-–—]*(?P<name>.*)$",
    re.IGNORECASE | re.DOTALL,
)
_CHAT_WORD_RE = re.compile(r"\b(?:chat|conversation|thread|session)\b", re.IGNORECASE)


def _pending_file() -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return os.path.join(runtime, "prime-voice.pending")


def write_pending(op: str, key: str = "", title: str = "") -> None:
    try:
        with open(_pending_file(), "w", encoding="utf-8") as fh:
            json.dump({"op": op, "key": key, "title": title, "at": time.time()}, fh)
    except OSError:
        pass


def read_pending() -> dict:
    """The route the last bare command asked for, if it is still fresh."""
    try:
        with open(_pending_file(), encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return {}
    if not isinstance(data, dict):
        return {}
    if time.time() - float(data.get("at") or 0) > 900.0:
        return {}
    return data


def clear_pending() -> None:
    try:
        os.unlink(_pending_file())
    except OSError:
        pass


def parse_command(text: str) -> dict:
    """Recognize a spoken routing command and split off its payload.

    Returns ``{}`` for anything that is a plain message, which is the safe
    default: a misread command would move his words into another chat.
    """
    match = _NAME_RE.match(text)
    if match:
        name = (match.group("name") or "").strip()
        if name:
            return {"op": "name", "name": name, "rest": ""}

    match = _NEW_TOPIC_RE.match(text)
    if match:
        return {"op": "new", "rest": (match.group("rest") or "").strip()}

    for rx, verb in ((_STRONG_SWITCH_RE, "strong"), (_WEAK_SWITCH_RE, "weak")):
        match = rx.match(text)
        if not match:
            continue
        target = (match.group("target") or "").strip()
        named_chat = bool(_CHAT_WORD_RE.search(target))
        # A weak verb ("go to …") only counts as chat control when he actually
        # says the word "chat"; otherwise "go to the store and buy milk" would
        # switch chats instead of being a message.
        if verb == "weak" and not named_chat:
            continue
        # "switch to the gutter chat, what's the status?" — the words after the
        # chat name ride along as the message.
        head, _, tail = target.partition(",")
        tail = tail.strip(" .,;:")
        if tail.lower() in ("please", "thanks", "thank you", "ok", "okay", "cheers"):
            tail = ""
        target = (head or target).strip()
        bare = _CHAT_WORD_RE.sub("", target).strip(" ,.")
        if bare:
            return {
                "op": "switch",
                "target": bare,
                "rest": tail,
                "strong": verb == "strong",
            }
    return {}


# --- The voice thread ------------------------------------------------------- #
# Talking should not require opening the app and managing chats. The sender
# keeps its own thread pointer and decides like a person would: stay where the
# work is, keep a live thread going, open a new chat once the subject has gone
# cold. Idle chats are never closed — they just become sidebar entries.
_TARGET_FILE = os.path.join(
    os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}", "prime-ptt.target"
)
_IDLE_MIN = float(os.environ.get("PRIME_PTT_IDLE_MIN", "15") or 0)
_STATE_DB = os.path.expanduser("~/.hermes/state.db")
_FORK_WORDS = (
    "new chat", "new topic", "new conversation", "fresh chat",
    "different topic", "another topic", "new thread",
)
_KEEP_WORDS = ("continue", "keep going", "carry on", "same chat", "same topic", "keep going on")


def voice_target() -> str:
    """Durable key of the chat this voice thread is currently using."""
    try:
        with open(_TARGET_FILE, encoding="utf-8") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def remember_target(key: str) -> None:
    if not key:
        return
    try:
        with open(_TARGET_FILE, "w", encoding="utf-8") as fh:
            fh.write(key + "\n")
    except OSError:
        pass


def last_activity(key: str) -> float:
    """Timestamp of the newest message in a chat (0 = none/unknown)."""
    if not key:
        return 0.0
    try:
        con = sqlite3.connect(_STATE_DB)
        try:
            row = con.execute(
                "SELECT MAX(timestamp) FROM messages WHERE session_id = ?", (key,)
            ).fetchone()
        finally:
            con.close()
        if row and row[0]:
            return float(row[0])
    except (sqlite3.Error, OSError, ValueError):
        pass
    return 0.0


def is_hot(key: str) -> bool:
    """Has this chat been used recently? Cold = a different subject."""
    return bool(key) and (time.time() - last_activity(key)) <= _IDLE_MIN * 60


def parse_override(text: str) -> tuple:
    """('new'|'keep'|'', text) — a leading spoken command, stripped from the take.

    Saying "new chat, what's the weather" opens a chat about the weather; saying
    "continue, also add tests" stays in the thread. The command never reaches the
    model, so the take reads the way he said it.
    """
    plain = " ".join((text or "").split())
    lowered = plain.lower()
    for phrase in _FORK_WORDS:
        if lowered.startswith(phrase):
            return "new", plain[len(phrase):].lstrip(" ,.:;-—").strip()
    for phrase in _KEEP_WORDS:
        if lowered.startswith(phrase):
            return "keep", plain[len(phrase):].lstrip(" ,.:;-—").strip()
    return "", plain


def thread_title(text: str) -> str:
    """Sidebar title from the take, so a forked chat says what it is about."""
    title = " ".join((text or "").split())
    return title[:57] + "…" if len(title) > 58 else title


async def live_sessions(port: int, token: str) -> list:
    """The sessions the gateway process actually has running."""
    return (await rpc(port, token, "session.active_list", {}) or {}).get("sessions") or []


async def runtime_for(key: str, sessions: list, port: int, token: str) -> str:
    """Live runtime id for a durable key, resuming it when it is not attached."""
    if not key:
        return ""
    for session in sessions:
        if session.get("session_key") == key:
            return session.get("id") or ""
    try:
        res = await rpc(port, token, "session.resume", {"session_id": key, "omit_messages": True})
        body = res.get("result") if isinstance(res, dict) and "result" in res else res
        return (body or {}).get("session_id") or ""
    except Exception as exc:  # noqa: BLE001 - callers fall through to other rungs
        log(f"chat {key} could not be resumed: {exc}")
        return ""


async def start_thread(port: int, token: str, title: str) -> tuple:
    """Create a chat (titled from the take so the sidebar reads) -> (sid, key)."""
    params = {"title": title} if title else {}
    created = await rpc(port, token, "session.create", params) or {}
    body = created.get("result") if isinstance(created, dict) and "result" in created else created
    return (body or {}).get("session_id") or "", (body or {}).get("stored_session_id") or ""


async def spoken_target(port: int, token: str) -> str:
    """Durable key of the chat whose replies belong on the speakers.

    The same choice a take makes, minus creating anything, so words and replies
    can never end up in different chats. Newest human turn wins between the
    voice thread and the chat on screen.
    """
    focus_key, _route, _title, _source = desktop_focus()
    candidates = [c for c in (voice_target(), focus_key) if c]
    hot = [c for c in candidates if is_hot(c)]
    if hot:
        return max(hot, key=last_activity)
    try:
        sessions = await live_sessions(port, token)
    except Exception:  # noqa: BLE001
        return ""
    if sessions:
        current = [s for s in sessions if s.get("current")]
        pick = (current or sessions)[0]
        if not current:
            pick = max(sessions, key=lambda s: s.get("last_active") or 0)
        return str(pick.get("session_key") or "")
    return ""


async def known_sessions(port: int, token: str, limit: int = 60) -> list:
    """Live sessions plus recent stored ones — what a spoken name can match."""
    rows = []
    seen = set()
    for session in await live_sessions(port, token):
        key = str(session.get("session_key") or "")
        if key and key not in seen:
            seen.add(key)
            rows.append(
                {
                    "key": key,
                    "title": str(session.get("title") or ""),
                    "live": True,
                    "last": float(session.get("last_active") or 0),
                }
            )
    try:
        stored = await rpc(port, token, "session.list", {"limit": limit}) or {}
        for row in stored.get("sessions") or []:
            key = str(row.get("resolved_id") or row.get("id") or "")
            if key and key not in seen:
                seen.add(key)
                rows.append(
                    {
                        "key": key,
                        "title": str(row.get("title") or ""),
                        "live": False,
                        "last": float(row.get("last_active") or 0),
                    }
                )
    except Exception as exc:  # noqa: BLE001 - naming is best-effort
        log(f"could not list stored sessions: {exc}")
    return rows


def match_chat(rows: list, needle: str):
    """Best chat for a spoken name — word hits, with live/recent winning ties."""
    words = [w for w in re.split(r"[^a-z0-9]+", (needle or "").lower()) if len(w) > 1]
    if not words:
        return None
    scored = []
    for row in rows:
        title = row["title"].lower()
        score = sum(1 for word in words if word in title)
        if score:
            scored.append(((score, 1 if row["live"] else 0, row["last"] or 0), row))
    if scored:
        return max(scored, key=lambda item: item[0])[1]
    # A key read off the screen ("switch to 9cac25") is a name too.
    flat = re.sub(r"[^a-z0-9]", "", (needle or "").lower())
    for row in rows:
        if flat and flat in re.sub(r"[^a-z0-9]", "", row["key"].lower()):
            return row
    return None


async def set_chat_title(port: int, token: str, sessions: list, key: str, title: str) -> bool:
    """Name a chat so it can be switched to by voice later."""
    sid = await runtime_for(key, sessions, port, token)
    if not sid:
        return False
    await rpc(port, token, "session.title", {"session_id": sid, "title": title})
    return True


async def pick_target(port: int, token: str, text: str = "", create: bool = True) -> tuple:
    """(runtime_id, durable_key, text_to_send, why) for a take.

    A voice take is not a form submission: it should never require opening the
    app and managing chats. So the decision is the one a person would make —
    stay where the work is, keep a live thread going, and open a new chat when
    the subject has gone cold. ``create=False`` answers "where would this land?"
    without starting a chat (used by the self-test).
    """
    pinned = os.environ.get("PRIME_PTT_SESSION")
    if pinned:
        return pinned, pinned, text, "pinned by PRIME_PTT_SESSION"

    command, cleaned = parse_override(text)
    focus_key, route, _title, _source = desktop_focus()
    sessions = await live_sessions(port, token)
    thread = voice_target()

    # A route the last bare command asked for ("new chat", "switch to the x
    # chat") is honoured for THIS take, then forgotten.
    pending = read_pending()
    if pending and not command:
        clear_pending()
        op = str(pending.get("op") or "")
        key = str(pending.get("key") or "")
        if op == "open" and key:
            sid = await runtime_for(key, sessions, port, token)
            if sid:
                return sid, key, cleaned, f"the chat you asked for ({pending.get('title') or key})"
        elif op == "new":
            command = "new"

    # Spoken chat control: "switch to the <name> chat", "name this chat <x>".
    spoken = parse_command(text) if not command else {}
    spoken_op = spoken.get("op") or ""

    if spoken_op == "switch":
        target_name = spoken.get("target") or ""
        match = match_chat(await known_sessions(port, token), target_name)
        if match:
            sid = await runtime_for(match["key"], sessions, port, token)
            label = match["title"] or match["key"]
            rest = spoken.get("rest") or ""
            if sid and rest:
                return sid, match["key"], rest, f"the chat you asked for ({label})"
            if sid and not create:
                return sid, match["key"], "", f"the chat you asked for ({label})"
            if sid:
                # Bare "switch to X": point the next take there so the window can
                # land on it before he speaks.
                write_pending("open", match["key"], label)
                return "", "", "", f"switched to {label} — ready"
        log(f"spoken switch found no chat matching {target_name!r}")
    elif spoken_op == "name":
        new_name = spoken.get("name") or ""
        if not focus_key:
            return "", "", "", "no chat on screen to name"
        if not new_name:
            return "", "", "", "no name given"
        if not create:
            return "", "", "", f"would name this chat \u201c{new_name}\u201d"
        if await set_chat_title(port, token, sessions, focus_key, new_name):
            return "", "", "", f"named this chat \u201c{new_name}\u201d"

    # A bare command is a promise, not a message: never submit an empty take.
    if command in ("new", "keep") and not cleaned:
        if command == "keep" and thread:
            write_pending("open", thread, "this voice thread")
            return "", "", "", "same chat — ready"
        write_pending("new")
        return "", "", "", "a new chat next time — ready"

    if command == "keep" and thread:
        sid = await runtime_for(thread, sessions, port, token)
        if sid:
            return sid, thread, cleaned, "you said continue — same chat"

    # A new-chat draft on screen ("/") means he is deliberately starting one — but
    # if the voice thread is still live, keep talking in it rather than forking a
    # chat on every take (the window never follows a fork by itself).
    candidates = []
    if command != "new" and route.strip() != "/" and focus_key:
        candidates.append((focus_key, "the chat on screen"))
    if command != "new" and thread:
        candidates.append((thread, "this voice thread"))

    for candidate, why in candidates:
        if not is_hot(candidate):
            continue
        sid = await runtime_for(candidate, sessions, port, token)
        if sid:
            return sid, candidate, cleaned, why

    title = thread_title(cleaned)
    if not create:
        return "", "", cleaned, f"a fresh chat ({title})" if title else "a fresh chat"

    sid, key = await start_thread(port, token, title)
    if sid:
        return sid, key, cleaned, f"a new chat ({title})" if title else "a new chat"

    # Never lose a take to a failed create: fall back to what is running.
    if focus_key:
        sid = await runtime_for(focus_key, sessions, port, token)
        if sid:
            return sid, focus_key, cleaned, "the chat on screen (new chat failed)"
    if sessions:
        pick = max(sessions, key=lambda s: s.get("last_active") or 0)
        return pick.get("id") or "", pick.get("session_key") or "", cleaned, "the newest live chat"
    return "", "", cleaned, "nothing live"


async def resolve_runtime(port: int, token: str) -> tuple:
    """Read-only probe: the chat a take right now would land in (no side effects)."""
    sid, durable, _text, why = await pick_target(port, token, "", create=False)
    if sid:
        return sid, durable
    # No live chat and a fork would be needed: report the thread/cached key.
    key = voice_target() or cached_durable()
    sid = await runtime_for(key, await live_sessions(port, token), port, token)
    return sid, key or f"would start {why}"


def keep_take(wav: str, text: str) -> None:
    """Never lose a take: park the audio and its transcript when the app is away.

    The common failure is timing, not damage — the app restarting or a turn
    finishing while the key comes up — so the recording is worth keeping.
    """
    try:
        dest = os.path.expanduser("~/.hermes/cache/ptt-failed")
        os.makedirs(dest, exist_ok=True)
        stamp = time.strftime("%Y%m%d_%H%M%S")
        shutil.copy2(wav, os.path.join(dest, f"take_{stamp}.wav"))
        with open(os.path.join(dest, f"take_{stamp}.txt"), "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
        log(f"take parked at {dest}/take_{stamp}.wav")
    except OSError as exc:
        log(f"could not park the take: {exc}")


TAP_SECONDS = 1.2
BAR_INPUT = os.path.expanduser("~/.config/waybar/scripts/prime-bar-input.sh")


def open_text_box(reason: str = "") -> None:
    """Super+R *tapped* (no speech) = he wanted to TYPE.

    Opens the Hermes waybar pill's input — the same slim rofi line the bar pill
    opens — so a tap is a fast path to a typed prompt instead of a "nothing
    caught" nag. Held-and-quiet takes still get the mic message.
    """
    if not os.path.isfile(BAR_INPUT):
        log(f"text box missing at {BAR_INPUT}")
        return
    try:
        subprocess.Popen(
            ["setsid", BAR_INPUT],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        log(f"tap — opened the Hermes text box ({reason})")
    except OSError as exc:
        log(f"could not open the text box: {exc}")


async def main() -> int:
    if len(sys.argv) < 2:
        log("usage: prime-ptt-send.py <wav path>")
        return 2
    wav = sys.argv[1]

    # Silence is not a sentence: transcribers hallucinate on near-empty audio, and
    # a hallucinated line lands in the conversation as if he had said it. Reject it
    # before the STT ever sees the file.
    peak, seconds = take_quality(wav)
    if seconds < 1.0 or peak < -30.0:
        log(f"take ignored: peak {peak:.1f}dB over {seconds:.1f}s — too quiet/short to be speech")
        if seconds < TAP_SECONDS:
            open_text_box(f"tap {seconds:.2f}s, peak {peak:.0f}dB")
            status("no-speech", "tap — typing box")
            return 0
        status("no-speech", f"take too quiet ({peak:.0f}dB)")
        notify("🤔 Nothing caught", "Too quiet or too short — hold Super+R and speak", 3000)
        return 0

    text = transcribe(wav)
    if not text:
        log("no speech detected — nothing submitted")
        status("no-speech", "no speech detected")
        notify("🤔 No speech", "Nothing sent — try again", 3000)
        return 0

    # The app can be mid-restart (port changes) or between turns exactly when the
    # key comes up, and the backend then reports no live session for a moment.
    # Retry the whole resolution — port, token, session — instead of dropping the
    # take on the first empty list.
    deadline = time.monotonic() + 30.0
    attempt = 0
    target = None  # decided once: a retry must never fork a second chat
    sid = durable = why = ""
    send_text = text

    while True:
        attempt += 1
        try:
            port = backend_port()
            token = session_token(port)

            if target is None:
                sid, durable, send_text, why = await pick_target(port, token, text)
                if not send_text:
                    # Command-only take ("new chat", "switch to the printer
                    # chat", "name this chat X"): applied, nothing to submit.
                    log(f"command only — {why}")
                    status("command", why[:60])
                    notify("\U0001f399 Prime", why[:70], 3500)
                    return 0
                if not sid:
                    raise RuntimeError("no live session to submit to")
                target = (sid, durable, send_text, why)
                log(f"take -> {durable or sid} — {why}")
            else:
                sid, durable, send_text, why = target

            await rpc(
                port,
                token,
                "prompt.submit",
                {
                    "session_id": sid,
                    "text": VOICE_PREFIX + send_text,
                    # queued=True = "run after the current turn". The backend
                    # then NEVER turns this into a live-turn redirect, which is
                    # what cancels the in-flight model call and surfaces as
                    # "Operation interrupted: waiting for model response".
                    # A voice take must always wait, never kill the reply.
                    "queued": True,
                },
            )
            # Point the voice thread (and the speakers) at the chat that just got
            # the take, so a forked chat keeps the conversation.
            remember_target(durable or sid)
            break
        except Exception as exc:  # noqa: BLE001 - retry, then one notification
            if "session not found" in str(exc) or "4007" in str(exc):
                try:
                    os.remove(_SESSION_CACHE)
                except OSError:
                    pass
                # The chat itself is gone (app restarted): decide afresh.
                target = None
            if time.monotonic() >= deadline:
                log(f"submit failed after {attempt} tries: {exc}")
                keep_take(wav, text)
                status("error", str(exc)[:60])
                notify("Prime", "Voice didn't reach the app — the take is saved")
                return 1

            log(f"submit retry {attempt}: {exc}")
            await asyncio.sleep(1.5)

    log(f"sent ({len(send_text)} chars) -> {durable or sid} — {why}: {send_text[:110]}")
    status("sent", f"{send_text[:38]} \u2192 {why[:38]}")
    notify(
        "✅ New chat" if why.startswith("a new chat") else "✅ Delivered",
        f"{send_text[:58]}\n{why[:60]}",
        3200,
    )
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))

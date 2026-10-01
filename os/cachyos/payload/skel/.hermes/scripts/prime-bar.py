#!@HOME@/.hermes/hermes-agent/venv/bin/python3
"""Hermes waybar pill — the TYPED path (companion to prime-ptt-send.py's voice path).

Click the pill in the bar, type a prompt into the little glass input, Enter.
The text is routed exactly like a voice take: it lands in the chat the Hermes
window is showing (``pick_target`` reads the app's own focus record), queued so
it never kills an in-flight reply. Then this script watches state.db for the
assistant reply and publishes it to the pill + a notification.

It reuses prime-ptt-send.py as a library (read-only: never edit that file from
here) so routing, retries and the ``queued`` submit semantics stay identical to
voice.

Usage
-----
  prime-bar.py ask "<text>" [--new]   submit; --new forces a fresh chat
  prime-bar.py last                   print the last reply (popup / tooltip use)
  prime-bar.py clear                  reset the pill to idle
"""
from __future__ import annotations

import argparse
import asyncio
import importlib.util
import json
import os
import re
import sqlite3
import subprocess
import sys
import time

RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
STATE = os.path.join(RUNTIME, "prime-bar.state")
NOTIFY_ID = os.path.join(RUNTIME, "prime-bar.notifyid")
LOG = os.path.join(RUNTIME, "prime-bar.log")
DB = os.path.expanduser("~/.hermes/state.db")
PTT_SEND = os.path.expanduser("~/.hermes/scripts/prime-ptt-send.py")

# Marks the turn as bar-typed. Same spirit as VOICE_PREFIX: the answer lands in
# a chat surface this pill is only a peephole onto, so keep it tight.
BAR_PREFIX = "[Waybar input — reply concisely, 1-3 sentences, no markdown unless I ask for detail.] "

# Added in front of a question that has a screenshot attached.
SCREEN_NOTE = ("[I attached a screenshot of my screen — answer about what is actually "
               "in the image.] ")

REPLY_TIMEOUT = float(os.environ.get("PRIME_BAR_TIMEOUT", "1200"))


def log(msg: str) -> None:
    line = f"{time.strftime('%H:%M:%S')} {msg}"
    print(f"[prime-bar] {msg}", file=sys.stderr)
    try:
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
    except OSError:
        pass


# --- pill state --------------------------------------------------------------- #


def read_state() -> dict:
    try:
        with open(STATE, encoding="utf-8") as fh:
            data = json.load(fh)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_state(**fields) -> dict:
    """Merge + atomic write: waybar may read this file at any instant."""
    state = read_state()
    state.update(fields)
    state["ts"] = time.time()
    tmp = f"{STATE}.{os.getpid()}"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(state, fh)
        os.replace(tmp, STATE)
    except OSError as exc:
        log(f"could not write state: {exc}")
    return state


# --- notifications (swaync replaces by id, it does not stack) ------------------ #


def notify(title: str, body: str, expire: int = 6000) -> None:
    cmd = ["notify-send", "-a", "Prime", "-t", str(expire), "-i", "utilities-terminal"]
    try:
        with open(NOTIFY_ID, encoding="utf-8") as fh:
            rid = fh.read().strip()
        if rid.isdigit():
            cmd += ["-r", rid]
    except OSError:
        pass
    try:
        res = subprocess.run(cmd + [title, body], capture_output=True, text=True, timeout=8)
        rid = (res.stdout or "").strip()
        if rid.isdigit():
            with open(NOTIFY_ID, "w", encoding="utf-8") as fh:
                fh.write(rid)
    except (OSError, subprocess.SubprocessError) as exc:
        log(f"notify failed: {exc}")


# --- the shared router -------------------------------------------------------- #


def load_ptt():
    spec = importlib.util.spec_from_file_location("prime_ptt_send", PTT_SEND)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {PTT_SEND}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def snippet(text: str, limit: int = 78) -> str:
    """One flat line for the pill: markdown out, whitespace collapsed."""
    flat = re.sub(r"```.*?```", " ", text, flags=re.S)
    flat = re.sub(r"`([^`]*)`", r"\1", flat)
    flat = re.sub(r"!\[[^\]]*\]\([^)]*\)", " ", flat)
    flat = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", flat)
    flat = re.sub(r"[*_#>|]+", "", flat)
    flat = re.sub(r"\s+", " ", flat).strip()
    if len(flat) > limit:
        cut = flat[:limit]
        space = cut.rfind(" ")
        if space > limit * 0.6:
            cut = cut[:space]
        flat = cut.rstrip(" ,;:.") + "…"
    return flat


def max_message_id(key: str) -> int:
    try:
        con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
        row = con.execute(
            "SELECT COALESCE(MAX(id), 0) FROM messages WHERE session_id = ?", (key,)
        ).fetchone()
        con.close()
        return int(row[0] or 0)
    except sqlite3.Error as exc:
        log(f"baseline read failed: {exc}")
        return 0


def wait_for_reply(key: str, since_id: int, deadline: float, settle: float = 5.0) -> str:
    """The turn's REAL answer, not its preamble.

    A reply often opens with a line of throat-clearing ("I'll take a look…") and
    the real answer lands after the tool call that follows it. Two rules keep the
    pill honest:

    * track the newest message of ANY role, so the quiet window only starts once
      the agent has stopped working (a tool result counts as activity), and
    * return the newest ASSISTANT text after that quiet window — never the first.
    """
    last_text = ""
    quiet_since = 0.0
    seen_id = since_id
    while time.monotonic() < deadline:
        try:
            con = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
            newest = con.execute(
                "SELECT COALESCE(MAX(id), 0) FROM messages WHERE session_id = ? AND id > ?",
                (key, since_id),
            ).fetchone()
            row = con.execute(
                "SELECT content FROM messages WHERE session_id = ? AND id > ? "
                "AND role = 'assistant' AND active = 1 ORDER BY id DESC LIMIT 1",
                (key, since_id),
            ).fetchone()
            con.close()
            newest_id = int(newest[0] or 0) if newest else 0
            text = (row[0] or "").strip() if row else ""
            if newest_id > seen_id:
                seen_id = newest_id
                quiet_since = time.monotonic()
            if text:
                last_text = text
        except sqlite3.Error as exc:
            log(f"reply poll failed: {exc}")

        if last_text and quiet_since and time.monotonic() - quiet_since >= settle:
            return last_text
        time.sleep(1.5)
    return last_text


# --- commands ----------------------------------------------------------------- #


async def do_ask(text: str, new_chat: bool = False, image: str | None = None) -> int:
    text = (text or "").strip()
    if not text:
        text = "What am I looking at here?" if image else ""
    if not text:
        log("empty prompt — nothing submitted")
        write_state(status="idle", prompt="", reply="", snippet="", chat="")
        return 0

    if new_chat and not re.match(r"^\s*(new chat|new topic|switch to|continue|name this)", text, re.I):
        text = "new chat, " + text

    ptt = load_ptt()
    if image:
        write_state(status="thinking", prompt=text, reply="", snippet="",
                    chat="", key="", pid=os.getpid(), started=time.time(),
                    image=os.path.basename(image))
    else:
        write_state(status="thinking", prompt=text, reply="", snippet="",
                    chat="", key="", pid=os.getpid(), started=time.time())

    deadline = time.monotonic() + 30.0
    attempt = 0
    target = None
    sid = durable = send_text = why = ""

    while True:
        attempt += 1
        try:
            port = ptt.backend_port()
            token = ptt.session_token(port)
            if target is None:
                sid, durable, send_text, why = await ptt.pick_target(port, token, text)
                if not send_text:
                    log(f"command only — {why}")
                    write_state(status="command", chat=why[:60], prompt=text, reply=why,
                                snippet=snippet(why))
                    notify("🎙️ Prime", why[:70], 4000)
                    return 0
                if not sid:
                    raise RuntimeError("no live session to submit to")
                target = (sid, durable, send_text, why)
            else:
                sid, durable, send_text, why = target

            key = durable or sid
            baseline = max_message_id(key)

            import asyncio

            # The screenshot rides the session record: image.attach appends to
            # session["attached_images"], and prompt.submit ships that list in the
            # turn.start frame — so attach strictly BEFORE submitting.
            if image:
                try:
                    attached = await ptt.rpc(
                        port, token, "image.attach", {"session_id": sid, "path": image}
                    )
                    log(f"attached screenshot: {attached}")
                except Exception as exc:  # noqa: BLE001 - a text-only ask beats nothing
                    log(f"image attach failed ({exc}) — sending text only")

            await ptt.rpc(
                port,
                token,
                "prompt.submit",
                {
                    "session_id": sid,
                    "text": BAR_PREFIX + (SCREEN_NOTE if image else "") + send_text,
                    "queued": True,
                },
            )
            ptt.remember_target(durable or sid)
            log(f"typed take -> {key} — {why}: {send_text[:90]}")
            write_state(status="thinking", chat=why, key=key, pid=os.getpid(),
                        started=time.time(), reply="", snippet="")
            break
        except Exception as exc:  # noqa: BLE001 - retry, then report
            if time.monotonic() >= deadline:
                log(f"submit failed after {attempt} tries: {exc}")
                write_state(status="error", chat=str(exc)[:70], snippet=str(exc)[:60],
                            reply=str(exc)[:400])
                notify("⚠️ Prime bar", f"Didn't reach the app: {str(exc)[:90]}", 7000)
                return 1
            log(f"submit retry {attempt}: {exc}")
            time.sleep(1.5)

    # Now watch for the answer so the pill can show it without opening the app.
    reply = await asyncio.to_thread(
        wait_for_reply, key, baseline, time.monotonic() + REPLY_TIMEOUT
    )
    if reply:
        write_state(status="done", reply=reply, snippet=snippet(reply), chat=why,
                    key=key, pid=0, done=time.time())
        if image:
            # A question about something on his screen has to be readable where he is
            # already looking — he is mid-problem in another window, not watching the
            # app. A twelve-second toast that vanishes is how an answer gets missed
            # completely, so this one is sticky (timeout 0 = stays until dismissed)
            # and long enough to actually contain the answer.
            notify("Prime — answer", snippet(reply, 700), 0)
        else:
            notify("Hermes", snippet(reply, 220), 12000)
        log(f"reply in ({len(reply)} chars) — pill updated")
        return 0

    write_state(status="pending", snippet="sent — still working", chat=why, key=key, pid=0)
    notify("Hermes", "Sent — no reply within the watch window; check the app.", 7000)
    return 0


def do_last() -> int:
    state = read_state()
    reply = (state.get("reply") or "").strip()
    if reply:
        print(reply)
    return 0


def do_clear() -> int:
    write_state(status="idle", prompt="", reply="", snippet="", chat="", pid=0, key="")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="prime-bar")
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("ask")
    a.add_argument("text")
    a.add_argument("--new", action="store_true")
    a.add_argument("--image", default="", help="screenshot to attach before submitting")
    sub.add_parser("last")
    sub.add_parser("clear")
    args = ap.parse_args()

    if args.cmd == "ask":
        return asyncio.run(
            do_ask(args.text, new_chat=args.new, image=args.image or None)
        )
    if args.cmd == "last":
        return do_last()
    return do_clear()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)

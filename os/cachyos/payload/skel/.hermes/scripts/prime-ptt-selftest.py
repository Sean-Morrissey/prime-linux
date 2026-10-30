#!/usr/bin/env python3
"""Smoke test for Prime hold-to-talk (no mic use, nothing submitted).

Run after touching any of the prime-ptt-* files:

    ~/.hermes/hermes-agent/venv/bin/python ~/.hermes/scripts/prime-ptt-selftest.py

Checks the pieces prime-ptt-send.py depends on: the desktop app's backend is up
and reachable, its loopback token parses, and a foreground session can be
resolved (the session the hotkey would submit into).
"""
from __future__ import annotations

import asyncio
import importlib.util
import os
import sys

SCRIPTS = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("prime_ptt_send", os.path.join(SCRIPTS, "prime-ptt-send.py"))
assert SPEC and SPEC.loader
send = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(send)

failures = 0


def report(ok: bool, label: str) -> None:
    global failures
    print(f"  {'ok  ' if ok else 'FAIL'}  {label}")
    if not ok:
        failures += 1


def main() -> int:
    print("Prime hold-to-talk self-test")

    try:
        import faster_whisper  # noqa: F401
        import websockets  # noqa: F401

        report(True, "STT (faster-whisper) + websockets import")
    except Exception as exc:  # noqa: BLE001
        report(False, f"STT + websockets import ({exc})")

    repo = os.path.expanduser("~/.hermes/hermes-agent")
    report(os.access(os.path.join(repo, "venv/bin/python"), os.X_OK), "venv python executable")

    try:
        port = send.backend_port()
        report(True, f"desktop backend port discovered ({port})")
    except Exception as exc:  # noqa: BLE001
        report(False, f"desktop backend port discovered ({exc})")
        return 1

    try:
        token = send.session_token(port)
        report(bool(token), "loopback session token parsed")
    except Exception as exc:  # noqa: BLE001
        report(False, f"loopback session token parsed ({exc})")
        return 1

    try:
        sid = asyncio.run(send.target_session(port, token))
        report(bool(sid), f"foreground session resolved ({sid})")
    except Exception as exc:  # noqa: BLE001
        report(False, f"foreground session resolved ({exc})")
        return 1

    # The chat the window is actually showing: read from the desktop app's own
    # navigation record. A take must follow this, not "most recently active".
    try:
        key, route, _title, source = send.desktop_focus()
        report(
            bool(key or route),
            f"desktop window focus readable (via {source}: chat={key or '-'} route={route or '-'})",
        )
    except Exception as exc:  # noqa: BLE001
        report(False, f"desktop window focus readable ({exc})")

    try:
        sid, durable = asyncio.run(send.resolve_runtime(port, token))
        report(bool(sid), f"take would land in {durable or '-'} (runtime {sid or '-'})")
    except Exception as exc:  # noqa: BLE001
        report(False, f"take target resolves ({exc})")

    print("all checks passed" if not failures else f"{failures} check(s) failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())

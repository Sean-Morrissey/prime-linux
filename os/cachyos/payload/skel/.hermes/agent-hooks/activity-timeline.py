#!/usr/bin/env python3
"""
Filtered activity timeline for Hermes shell hooks (post_tool_call + friends).

Receives a JSON payload on stdin, appends ONE filtered, redacted JSON line to
~@STUDY_DIR@/whiteboard/activity.jsonl, and prints nothing.

Design notes
------------
* Observer only — never emits a block/modify directive, so it cannot alter or
  stall agent behaviour. Malformed input exits 0 silently.
* Filtered, not a firehose: each entry gets a `signal` tier (high/med/low) and a
  one-line human summary, so the UI can spotlight consequential actions and dim
  routine reads.
* Redacted: arguments and outputs are truncated and swept for credential-shaped
  strings before they touch the disk. Hermes' own redact_secrets protects the
  model; this protects the *timeline*, which lives on a screen.

Wire contract (Hermes shell hooks):
  stdin  {"hook_event_name","tool_name","tool_input","session_id","cwd","profile","extra"}
  stdout ignored for observer events.
"""
import json
import os
import re
import sys
import time

OUT = os.path.expanduser("~@STUDY_DIR@/whiteboard/activity.jsonl")
MAX_LINES = 4000          # keep the log bounded; trimmed in place
MAX_FIELD = 220

HIGH_TOOLS = {
    "terminal", "write_file", "patch", "execute_code", "delegate_task",
    "cronjob", "computer_use", "process",
}
MED_TOOLS = {
    "web_extract", "web_search", "browser_navigate", "browser_type",
    "browser_click", "image_generate", "text_to_speech", "tts",
}

# Credential-shaped substrings. Deliberately broad — a timeline is not a place
# to be clever about what counts as a secret.
SECRET_PATTERNS = [
    re.compile(r"\b(sk|pk|rk)-[A-Za-z0-9_\-]{12,}"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bxox[baprs]-[A-Za-z0-9\-]{10,}"),
    re.compile(r"\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\."),
    re.compile(r"(?i)\b(api[_-]?key|token|password|passwd|secret|bearer)\b\s*[:=]\s*\S+"),
    re.compile(r"\b[A-Za-z0-9_\-]{32,}\b"),  # long opaque blobs
]


def redact(text: str) -> str:
    for pat in SECRET_PATTERNS:
        text = pat.sub("[REDACTED]", text)
    return text


def clip(value) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        try:
            value = json.dumps(value, ensure_ascii=False)
        except (TypeError, ValueError):
            value = str(value)
    value = " ".join(value.split())
    if len(value) > MAX_FIELD:
        value = value[:MAX_FIELD] + "…"
    return redact(value)


def summarize(tool: str, args) -> str:
    """One human-readable line describing what the call actually does."""
    if not isinstance(args, dict):
        return clip(args)
    a = args
    if tool == "terminal":
        return clip(a.get("command"))
    if tool in ("write_file", "read_file", "patch"):
        return clip(a.get("path"))
    if tool == "search_files":
        return clip("%s  in  %s" % (a.get("pattern", ""), a.get("path", ".")))
    if tool == "web_search":
        return clip(a.get("query"))
    if tool == "web_extract":
        urls = a.get("urls") or []
        return clip(", ".join(urls[:3]))
    if tool.startswith("browser_"):
        return clip(a.get("url") or a.get("ref") or "")
    if tool == "delegate_task":
        tasks = a.get("tasks") or []
        return clip("%d subagent task(s): %s" % (
            len(tasks), "; ".join((t.get("goal", "")[:60] for t in tasks[:2]))))
    if tool == "cronjob":
        return clip("%s %s" % (a.get("action", ""), a.get("name", "")))
    if tool == "memory":
        return clip("%s -> %s" % (a.get("action", ""), a.get("target", "")))
    if tool in ("text_to_speech", "tts"):
        return clip("speak %d chars" % len(str(a.get("text", ""))))
    if tool == "todo":
        return clip("plan update (%d items)" % len(a.get("todos") or []))
    if tool == "skill_view":
        return clip(a.get("name"))
    if tool == "process":
        return clip("%s %s" % (a.get("action", ""), a.get("session_id", "")))
    # generic fallback: first non-empty scalar
    for v in a.values():
        if isinstance(v, (str, int, float)) and str(v).strip():
            return clip(v)
    return ""


def classify(tool: str) -> str:
    if tool in HIGH_TOOLS:
        return "high"
    if tool in MED_TOOLS:
        return "med"
    if tool in ("read_file", "search_files", "todo", "session_search", "skill_view"):
        return "low"
    return "med"


def handle_tool_event(payload: dict) -> dict:
    tool = payload.get("tool_name") or "?"
    args = payload.get("tool_input")
    extra = payload.get("extra") or {}
    return {
        "kind": "tool",
        "tool": tool,
        "summary": summarize(tool, args),
        "signal": classify(tool),
        "status": extra.get("status", "ok"),
        "duration_ms": extra.get("duration_ms"),
        "error": clip(extra.get("error_message"))[:160] or None,
        "session": payload.get("session_id") or "",
        "cwd": payload.get("cwd") or "",
    }


def handle_approval(payload: dict, event: str) -> dict:
    extra = payload.get("extra") or {}
    entry = {
        "kind": "approval",
        "tool": "approval",
        "signal": "high",
        "summary": clip(extra.get("description") or extra.get("command") or ""),
        "command": clip(extra.get("command")),
        "surface": extra.get("surface") or "",
        "session": payload.get("session_id") or "",
    }
    if event == "pre_approval_request":
        entry["status"] = "asked"
    else:
        entry["status"] = "answered"
        entry["choice"] = extra.get("choice") or ""
        entry["decided_by"] = extra.get("decided_by") or ""
    return entry


def handle_session(payload: dict, event: str) -> dict:
    return {
        "kind": "session",
        "tool": event,
        "signal": "med",
        "summary": event.replace("_", " "),
        "session": payload.get("session_id") or "",
    }


def handle_subagent(payload: dict, event: str) -> dict:
    extra = payload.get("extra") or {}
    return {
        "kind": "subagent",
        "tool": event,
        "signal": "high",
        "summary": clip(extra.get("child_role") or extra.get("goal") or event),
        "status": extra.get("status", ""),
        "duration_ms": extra.get("duration_ms"),
        "session": payload.get("session_id") or "",
    }


def build_entry(payload: dict) -> dict:
    event = payload.get("hook_event_name") or "unknown"
    if event in ("pre_tool_call", "post_tool_call"):
        entry = handle_tool_event(payload)
    elif event in ("pre_approval_request", "post_approval_response"):
        entry = handle_approval(payload, event)
    elif event in ("on_session_start", "on_session_end", "on_session_reset"):
        entry = handle_session(payload, event)
    elif event in ("subagent_start", "subagent_stop"):
        entry = handle_subagent(payload, event)
    else:
        entry = {
            "kind": "other", "tool": event, "signal": "low",
            "summary": event,
            "session": payload.get("session_id") or "",
        }
    entry["event"] = event
    entry["ts"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    entry["epoch"] = int(time.time())
    entry["profile"] = payload.get("profile") or "default"
    return entry


def trim(path: str) -> None:
    """Keep the file bounded without rewriting it on every single append."""
    try:
        if os.path.getsize(path) < 900_000:
            return
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
        with open(path, "w", encoding="utf-8") as f:
            f.writelines(lines[-MAX_LINES:])
    except OSError:
        pass


def main() -> int:
    try:
        raw = sys.stdin.read()
        if not raw.strip():
            return 0
        payload = json.loads(raw)
        if not isinstance(payload, dict):
            return 0
    except (ValueError, OSError):
        return 0

    # Low-signal read chatter would drown the timeline; drop the noisiest few.
    if (payload.get("hook_event_name") == "post_tool_call"
            and payload.get("tool_name") in ("todo",)):
        return 0

    try:
        entry = build_entry(payload)
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        trim(OUT)
    except Exception:
        # Observability must never break the agent loop.
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())

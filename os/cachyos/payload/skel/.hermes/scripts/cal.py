#!/usr/bin/env python3
"""Calendar bridge for the ledger -> reminder loop.

Google Calendar is the source of truth, so anything @USER@ adds on his phone is
seen here too. This file adds the one thing Google does not store: how far ahead
to remind, per event, plus a record of what already fired.

  cal.py add "Dentist" --at "2026-09-30 15:00" [--dur 60] [--remind 60] [--tag school]
  cal.py list [--days 30]
  cal.py today
  cal.py due [--grace 15]      TSV: id, start, minutes_until, title, pretty
  cal.py mark <id>             record that the reminder fired
  cal.py rm <id>
  cal.py ics [--out PATH]

Times are naive local (America/New_York) on the way in; Google receives RFC3339
with the proper offset. `due` is what the 5-minute cron job calls.
"""
from __future__ import annotations

import argparse
import json
import os
import secrets
import subprocess
import sys
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo

HOME = os.path.expanduser("~")
STORE = os.path.join(HOME, ".hermes", "calendar", "events.json")
LOG = os.path.join(HOME, ".hermes", "cache", "calendar.log")
VENV_PY = os.path.join(HOME, ".hermes", "hermes-agent", "venv", "bin", "python3")
GAPI = os.path.join(HOME, ".hermes", "skills", "productivity", "google-workspace",
                    "scripts", "google_api.py")
TZ = ZoneInfo("America/New_York")
FMT = "%Y-%m-%d %H:%M"
DEFAULT_LEAD = 30        # minutes before an event we know nothing else about
LOOKAHEAD_H = 24         # how far ahead to pull from Google each tick


def log(msg: str) -> None:
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(f"{datetime.now(TZ).strftime('%F %T')} {msg}\n")
    except OSError:
        pass


def now() -> datetime:
    return datetime.now(TZ).replace(tzinfo=None)


# ── Google Calendar ─────────────────────────────────────────────────────────────

def gapi(args: list, timeout: int = 30):
    """Call the Google Workspace CLI. The venv interpreter is named explicitly:
    the cron ticker and a waybar click do not share a PATH with an agent shell."""
    py = VENV_PY if os.path.exists(VENV_PY) else sys.executable
    try:
        r = subprocess.run([py, GAPI, *args], capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired) as exc:
        log(f"gapi {' '.join(args[:2])} failed: {exc}")
        return None
    if r.returncode != 0:
        log(f"gapi {' '.join(args[:2])} rc={r.returncode}: {r.stderr.strip()[:200]}")
        return None
    try:
        return json.loads(r.stdout or "null")
    except ValueError:
        log(f"gapi {' '.join(args[:2])}: unparseable output")
        return None


def gcal_events(start: datetime, end: datetime):
    out = gapi(["calendar", "list",
                "--start", start.replace(tzinfo=TZ).isoformat(),
                "--end", end.replace(tzinfo=TZ).isoformat(),
                "--max", "250"])
    return out if isinstance(out, list) else []


# ── local store: reminder preferences + what already fired ──────────────────────

def load() -> dict:
    try:
        with open(STORE, encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            raise ValueError
    except (OSError, ValueError):
        data = {}
    data.setdefault("events", [])   # local records -> reminder prefs, keyed by gcal id
    data.setdefault("fired", {})    # "<gcal id>@<start iso>" -> when it fired
    return data


def save(data: dict) -> None:
    os.makedirs(os.path.dirname(STORE), exist_ok=True)
    tmp = f"{STORE}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
    os.replace(tmp, STORE)


def parse_at(value: str) -> datetime:
    for fmt in (FMT, "%Y-%m-%dT%H:%M", "%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(value.strip(), fmt)
        except ValueError:
            continue
    raise SystemExit(f"cal.py: cannot read --at '{value}' (want 'YYYY-MM-DD HH:MM')")


def fmt_when(start: datetime) -> str:
    today = now().date()
    d = start.date()
    if d == today:
        when = "today"
    elif d == today + timedelta(days=1):
        when = "tomorrow"
    else:
        when = start.strftime("%a %b %-d")
    return f"{when} {start.strftime('%-I:%M %p')}"


def to_local(iso: str) -> datetime:
    return datetime.fromisoformat(iso).astimezone(TZ).replace(tzinfo=None)


# ── commands ───────────────────────────────────────────────────────────────────

def cmd_add(a) -> int:
    start = parse_at(a.at)
    iso_start = start.replace(tzinfo=TZ).isoformat()
    iso_end = (start + timedelta(minutes=a.dur)).replace(tzinfo=TZ).isoformat()

    created = gapi(["calendar", "create", "--summary", a.title,
                    "--start", iso_start, "--end", iso_end])
    gid = created.get("id") if isinstance(created, dict) else None
    if not gid:
        print("FAILED: could not create the Google Calendar event")
        return 1

    data = load()
    data["events"].append({
        "id": secrets.token_hex(4),
        "gcal": gid,
        "title": a.title,
        "start": start.strftime("%Y-%m-%dT%H:%M"),
        "dur_min": a.dur,
        "remind_min": a.remind,
        "tag": a.tag,
        "created": now().strftime("%Y-%m-%dT%H:%M"),
        "reminded": None,
    })
    save(data)
    print(f"{gid}  {fmt_when(start)}  {a.title}  (remind {a.remind}m before)")
    return 0


def cmd_list(a) -> int:
    t = now()
    evs = gcal_events(t - timedelta(days=1), t + timedelta(days=a.days))
    if not evs:
        print("(no events)")
        return 0
    for e in evs:
        s = e.get("start") or ""
        if "T" not in s:
            print(f"  {s}  {e.get('summary')}  (all day)")
        else:
            print(f"  {fmt_when(to_local(s)):20s}  {e.get('summary')}")
    return 0


def cmd_today(a) -> int:
    t = now()
    evs = gcal_events(t - timedelta(hours=12), t.replace(hour=23, minute=59))
    if not evs:
        print("(nothing today)")
        return 0
    for e in evs:
        s = e.get("start") or ""
        when = s if "T" not in s else to_local(s).strftime("%-I:%M %p")
        print(f"{when:12s}  {e.get('summary')}")
    return 0


def cmd_due(a) -> int:
    """Anything whose reminder window has opened. Google is authoritative; the
    local store supplies the lead time and the already-fired set."""
    data = load()
    prefs = {e["gcal"]: int(e.get("remind_min") or DEFAULT_LEAD)
             for e in data.get("events", []) if e.get("gcal")}
    fired = data.get("fired", {})
    t = now()
    rows = []

    for e in gcal_events(t - timedelta(minutes=a.grace), t + timedelta(hours=LOOKAHEAD_H)):
        s = e.get("start") or ""
        if "T" not in s:                     # all-day events carry no clock time
            continue
        start = to_local(s)
        key = f"{e.get('id')}@{s}"
        if key in fired:
            continue
        lead = prefs.get(e.get("id"), DEFAULT_LEAD)
        if t >= start - timedelta(minutes=lead) and t <= start + timedelta(minutes=a.grace):
            mins = round((start - t).total_seconds() / 60)
            rows.append((key, s, mins, e.get("summary") or "(no title)",
                         start.strftime("%-I:%M %p")))

    # Local-only events (added when the API was unreachable) still fire.
    for e in data.get("events", []):
        if e.get("gcal") or e.get("reminded"):
            continue
        start = datetime.fromisoformat(e["start"])
        lead = int(e.get("remind_min") or DEFAULT_LEAD)
        if t >= start - timedelta(minutes=lead) and t <= start + timedelta(minutes=a.grace):
            mins = round((start - t).total_seconds() / 60)
            rows.append((e["id"], e["start"], mins, e["title"], start.strftime("%-I:%M %p")))

    for row in rows:
        print("\t".join(str(x) for x in row))
    return 0


def cmd_mark(a) -> int:
    data = load()
    if "@" in a.id:                          # a Google-derived key
        data.setdefault("fired", {})[a.id] = now().strftime("%Y-%m-%dT%H:%M")
        save(data)
        print(1)
        return 0
    hit = 0
    for e in data.get("events", []):
        if e["id"] == a.id:
            e["reminded"] = now().strftime("%Y-%m-%dT%H:%M")
            hit += 1
    if hit:
        save(data)
    print(hit)
    return 0


def cmd_rm(a) -> int:
    data = load()
    kept, removed = [], 0
    for e in data.get("events", []):
        if e["id"] == a.id or e.get("gcal") == a.id:
            if e.get("gcal"):
                gapi(["calendar", "delete", e["gcal"]])
            removed += 1
        else:
            kept.append(e)
    if removed:
        data["events"] = kept
        save(data)
    else:                                    # maybe a raw Google event id
        removed = 1 if gapi(["calendar", "delete", a.id]) is not None else 0
    print(removed)
    return 0


def cmd_ics(a) -> int:
    t = now()
    evs = gcal_events(t - timedelta(days=7), t + timedelta(days=365))
    out = a.out or os.path.join(os.path.dirname(STORE), "calendar.ics")
    lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Hermes//ledger-calendar//EN",
             "CALSCALE:GREGORIAN"]
    for e in evs:
        s, en = e.get("start") or "", e.get("end") or ""
        lines += ["BEGIN:VEVENT", f"UID:{e.get('id')}@google.com",
                  f"SUMMARY:{e.get('summary')}"]
        if "T" not in s:
            lines += [f"DTSTART;VALUE=DATE:{s.replace('-', '')}",
                      f"DTEND;VALUE=DATE:{(en or s).replace('-', '')}"]
        else:
            lines += [f"DTSTART:{datetime.fromisoformat(s).strftime('%Y%m%dT%H%M%S')}",
                      f"DTEND:{datetime.fromisoformat(en or s).strftime('%Y%m%dT%H%M%S')}"]
        lines.append("END:VEVENT")
    lines.append("END:VCALENDAR")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\r\n".join(lines) + "\r\n")
    print(out)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(prog="cal.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    add = sub.add_parser("add"); add.add_argument("title")
    add.add_argument("--at", required=True); add.add_argument("--dur", type=int, default=60)
    add.add_argument("--remind", type=int, default=DEFAULT_LEAD); add.add_argument("--tag", default="")
    add.add_argument("--notes", default=""); add.set_defaults(fn=cmd_add)

    ls = sub.add_parser("list"); ls.add_argument("--days", type=int, default=30)
    ls.set_defaults(fn=cmd_list)

    sub.add_parser("today").set_defaults(fn=cmd_today)

    due = sub.add_parser("due"); due.add_argument("--grace", type=int, default=15)
    due.set_defaults(fn=cmd_due)

    mk = sub.add_parser("mark"); mk.add_argument("id"); mk.set_defaults(fn=cmd_mark)
    rm = sub.add_parser("rm"); rm.add_argument("id"); rm.set_defaults(fn=cmd_rm)

    ic = sub.add_parser("ics"); ic.add_argument("--out"); ic.set_defaults(fn=cmd_ics)

    a = p.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    raise SystemExit(main())

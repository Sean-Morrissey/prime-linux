#!/usr/bin/env python3
"""ledger-calendar.py — the ledger's interactive calendar.

@USER@'s ask (2026-09-25): "in my ledger list i need a calendar interactive showing
my due dates and scheduled events".

It reads Google Calendar through `cal.py` (the same bridge the reminder loop uses,
so anything he adds on his phone shows up here), marks every day that has
something on it, and shows the selected day's entries beside the grid. School
deadlines are pulled out in a different colour and labelled DUE rather than
buried in a list of meetings.

Usage
-----
  ledger-calendar.py                 open it (from the ledger pill)
  ledger-calendar.py --day 2026-10-04   open focused on a date (QA)
  ledger-calendar.py --dump          print what it parsed, no window (QA)

Keys: ← → change month · T today · R refresh · Esc close. Clicking a day shows it.
"""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
import threading
import time
from datetime import date, datetime, timedelta

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

# Layer shell is how a bar popup gets placed and keyboard focus on Wayland (a
# plain toplevel lands wherever the compositor likes and may never get focus —
# see prime-entry.py). ON_DEMAND, not EXCLUSIVE: a calendar must not swallow his
# typing that is aimed at another window; clicking it hands it the keyboard.
try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell  # noqa: E402

    HAVE_LAYER = True
except Exception:  # pragma: no cover - machine without the typelib
    HAVE_LAYER = False

HOME = os.path.expanduser("~")
CAL_PY = os.path.join(HOME, ".hermes", "scripts", "cal.py")
STORE = os.path.join(HOME, ".hermes", "calendar", "events.json")

LOOKBACK_DAYS = 120      # how far back the grid can navigate with data already loaded
LOOKAHEAD_DAYS = 400     # ~13 months forward, so a full year of deadlines is there

CSS = b"""
window {
  background-color: rgba(10, 10, 14, 0.97);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 14px;
}
#card {
  background-color: rgba(255, 255, 255, 0.05);
  border: 1px solid rgba(255, 255, 255, 0.10);
  border-radius: 10px;
  padding: 8px;
}
#title { color: #c084fc; font-weight: bold; }
.muted { color: #a1a1a6; }
.due { color: #ff7675; font-weight: bold; }
.event { color: #a29bfe; }
.day-date { color: #e4e4e7; font-weight: bold; }
.row { padding: 4px 2px; }
calendar { background-color: transparent; }
calendar:selected { background-color: rgba(192, 132, 252, 0.35); border-radius: 6px; }
calendar.header { background-color: transparent; color: #c084fc; }
menu, menuitem { background-color: #14141c; color: #e4e4e7; }
menuitem:hover { background-color: rgba(192, 132, 252, 0.25); }
"""


# ── data ───────────────────────────────────────────────────────────────────────

def load_cal():
    """`cal.py` as a library — it is the Google bridge, the source of truth."""
    spec = importlib.util.spec_from_file_location("prime_cal", CAL_PY)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load {CAL_PY}")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def local_due_titles() -> set:
    """Titles in cal.py's own store: those carry the reminder lead + a tag."""
    try:
        with open(STORE, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return set()
    out = set()
    for ev in data.get("events", []):
        title = (ev.get("title") or "").strip().lower()
        if title and (ev.get("tag") == "school" or "due" in title):
            out.add(title)
    return out


def is_due(title: str, due_titles: set) -> bool:
    t = (title or "").lower()
    return t in due_titles or "due" in t or "assignment" in t or "mwa" in t


def fetch_entries(days_back: int = LOOKBACK_DAYS, days_ahead: int = LOOKAHEAD_DAYS) -> dict:
    """{(y, m, d): [entry, …]} — newest fetch replaces everything."""
    cal = load_cal()
    now = cal.now()
    raw = cal.gcal_events(now - timedelta(days=days_back), now + timedelta(days=days_ahead))
    due_titles = local_due_titles()

    days: dict = {}
    for ev in raw:
        start = ev.get("start") or ""
        allday = "T" not in start
        if allday:
            try:
                d = datetime.fromisoformat(start).date()
            except ValueError:
                continue
            when = None
        else:
            try:
                when = cal.to_local(start)
            except ValueError:
                continue
            d = when.date()
        title = (ev.get("summary") or "(no title)").strip()
        days.setdefault((d.year, d.month, d.day), []).append({
            "title": title,
            "when": when,
            "allday": allday,
            "due": is_due(title, due_titles),
        })

    for key, items in days.items():
        items.sort(key=lambda e: (not e["due"], e["when"] or datetime.min))
    return days


def upcoming_items(days: dict, limit: int = 4) -> list:
    """[(date, entry), …] from today forward, soonest first. Pure function so the
    self-test can assert it rather than eyeballing a screenshot."""
    today = date.today()
    flat = []
    for key in sorted(days):
        d = date(*key)
        if d < today:
            continue
        for e in days[key]:
            flat.append((d, e))
    flat.sort(key=lambda t: (t[0], t[1]["when"] or datetime.min))
    return flat[:limit]


# ── window ─────────────────────────────────────────────────────────────────────

class LedgerCalendar(Gtk.Window):
    def __init__(self, focus_day: date | None = None, month: date | None = None, show: bool = True):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.set_title("Prime — calendar")
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_default_size(980, 640)
        self.connect("key-press-event", self.on_key)
        self.connect("destroy", lambda *_: Gtk.main_quit())

        self.days: dict = {}
        self.loading = True
        self.mapped_at = 0.0

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        for side in ("top", "bottom", "start", "end"):
            getattr(outer, f"set_margin_{side}")(14)
        self.add(outer)

        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        title = Gtk.Label(label="󰃭  Calendar")
        title.set_name("title")
        head.pack_start(title, False, False, 0)
        self.subtitle = Gtk.Label(label="loading…")
        self.subtitle.get_style_context().add_class("muted")
        self.subtitle.set_xalign(0.0)
        head.pack_start(self.subtitle, False, False, 0)
        outer.pack_start(head, False, False, 0)

        body = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        outer.pack_start(body, True, True, 0)

        # left: the month grid + the next few things, so a deadline is visible
        # without hunting for a bold day
        left = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        left.set_name("card")
        left.set_size_request(360, -1)
        self.cal = Gtk.Calendar()
        self.cal.connect("day-selected", self.on_day)
        self.cal.connect("month-changed", self.on_month)
        left.pack_start(self.cal, False, False, 0)
        legend = Gtk.Label()
        legend.set_markup('<span foreground="#ff7675">due</span>  ·  '
                          '<span foreground="#a29bfe">event</span>  ·  '
                          '<span foreground="#a1a1a6">bold days have something</span>')
        legend.set_xalign(0.0)
        left.pack_start(legend, False, False, 0)

        upcoming_head = Gtk.Label(label="UP NEXT")
        upcoming_head.get_style_context().add_class("muted")
        upcoming_head.set_xalign(0.0)
        left.pack_start(upcoming_head, False, False, 0)
        self.upcoming = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        left.pack_start(self.upcoming, False, False, 0)
        body.pack_start(left, False, False, 0)

        # right: what is on the chosen day
        right = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        right.set_name("card")
        self.day_label = Gtk.Label(label="…")
        self.day_label.get_style_context().add_class("day-date")
        self.day_label.set_xalign(0.0)
        right.pack_start(self.day_label, False, False, 0)

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.set_min_content_height(430)
        self.listbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        scroll.add(self.listbox)
        right.pack_start(scroll, True, True, 0)
        body.pack_start(right, True, True, 0)

        footer = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        for text, cb in (("Today", self.goto_today),
                         ("Refresh", self.refresh),
                         ("Open Google Calendar", self.open_gcal),
                         ("Close", lambda *_: Gtk.main_quit())):
            btn = Gtk.Button(label=text)
            btn.connect("clicked", cb)
            footer.pack_start(btn, False, False, 0)
        hint = Gtk.Label(label="← → month   ·   click a day   ·   T today   ·   R refresh   ·   Esc close")
        hint.get_style_context().add_class("muted")
        hint.set_xalign(1.0)
        footer.pack_end(hint, False, False, 0)
        outer.pack_start(footer, False, False, 0)

        self.setup_layer()      # must run before the window is mapped
        self.connect("map", lambda *_: setattr(self, "mapped_at", time.monotonic()))
        if show:
            self.show_all()

        if month:
            self.cal.select_month(month.month - 1, month.year)
        if focus_day:
            self.cal.select_month(focus_day.month - 1, focus_day.year)
            self.cal.select_day(focus_day.day)

        if show:
            self.refresh()      # -selftest drives the data itself, synchronously
        else:
            self.loading = False

    # ── placement ──────────────────────────────────────────────────────────
    def setup_layer(self):
        if not HAVE_LAYER:
            return
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, "prime-calendar")
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        # Top-left, under the bar: the ledger pill lives in the left cluster, so the
        # calendar drops out of that same corner instead of over the middle of his work.
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.LEFT, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 52)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.LEFT, 12)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        # Which screen? The one the pointer is on — he just clicked the pill, so that
        # is the bar he means. Without this the compositor picks an output and it
        # lands on either monitor run to run (seen: left, then right).
        # PRIME_CAL_NO_PIN=1 skips it (QA knob: isolates placement from lifetime bugs).
        if os.environ.get("PRIME_CAL_NO_PIN") != "1":
            mon = self.monitor_under_pointer()
            if mon is not None:
                GtkLayerShell.set_monitor(self, mon)

    @staticmethod
    def monitor_under_pointer():
        display = Gdk.Display.get_default()
        if display is None:
            return None
        try:
            seat = display.get_default_seat()
            _, x, y = seat.get_pointer().get_position()
            return display.get_monitor_at_point(x, y)
        except Exception:
            return display.get_primary_monitor()

    # ── data flow ──────────────────────────────────────────────────────────
    def refresh(self, *_):
        self.subtitle.set_text("refreshing…")
        threading.Thread(target=self._fetch_thread, daemon=True).start()

    def _fetch_thread(self):
        try:
            days = fetch_entries()
            err = None
        except Exception as exc:  # noqa: BLE001 - the box must still open
            days, err = {}, str(exc)
        GLib.idle_add(self._apply, days, err)

    def _apply(self, days, err):
        self.days = days
        self.loading = False
        if err:
            self.subtitle.set_text(f"could not reach Google Calendar — {err[:70]}")
        else:
            n_days = len(days)
            n_due = sum(1 for items in days.values() for e in items if e["due"])
            self.subtitle.set_text(
                f"{n_due} deadline{'s' if n_due != 1 else ''} · "
                f"{n_days} day{'s' if n_days != 1 else ''} with something on them")
        self.redraw_marks()
        self.render_upcoming()
        self.on_day(self.cal)
        return False

    def render_upcoming(self, limit: int = 4):
        """The next few things after today — the reason to open this at all."""
        for child in self.upcoming.get_children():
            self.upcoming.remove(child)
        shown = upcoming_items(self.days, limit)
        if not shown:
            lbl = Gtk.Label(label="Nothing ahead on your calendar.")
            lbl.get_style_context().add_class("muted")
            lbl.set_xalign(0.0)
            self.upcoming.pack_start(lbl, False, False, 0)
            self.upcoming.show_all()
            return
        for d, e in shown:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
            tag = Gtk.Label(label="DUE" if e["due"] else "·")
            tag.get_style_context().add_class("due" if e["due"] else "muted")
            row.pack_start(tag, False, False, 0)
            when = Gtk.Label(label=f"{d.strftime('%-d %b')}")
            when.set_size_request(52, -1)
            when.set_xalign(0.0)
            when.get_style_context().add_class("muted")
            row.pack_start(when, False, False, 0)
            txt = Gtk.Label(label=e["title"])
            txt.get_style_context().add_class("due" if e["due"] else "event")
            txt.set_xalign(0.0)
            txt.set_ellipsize(3)          # Pango.EllipsizeMode.END
            row.pack_start(txt, True, True, 0)
            self.upcoming.pack_start(row, False, False, 0)
        self.upcoming.show_all()

    def month_days(self) -> list:
        """The (y, m, d) keys inside the month the grid is showing."""
        y, m, _ = self.cal.get_date()
        out = []
        d = date(y, m + 1, 1)
        while d.month == m + 1:
            out.append((d.year, d.month, d.day))
            d += timedelta(days=1)
        return out

    def redraw_marks(self):
        for (_, _, day) in self.month_days():
            self.cal.unmark_day(day)
        for key in self.days:
            if key in set(self.month_days()):
                self.cal.mark_day(key[2])

    # ── interaction ────────────────────────────────────────────────────────
    def on_month(self, *_):
        self.redraw_marks()
        self.on_day(self.cal)

    def on_day(self, *_):
        y, m, d = self.cal.get_date()
        picked = date(y, m + 1, d)
        items = self.days.get((picked.year, picked.month, picked.day), [])
        today = date.today()
        if picked == today:
            label = f"Today · {picked.strftime('%A %-d %B')}"
        elif picked == today + timedelta(days=1):
            label = f"Tomorrow · {picked.strftime('%A %-d %B')}"
        else:
            label = picked.strftime("%A %-d %B %Y")
        self.day_label.set_text(f"{label}   ({len(items)})" if items else f"{label}   — nothing on")

        for child in self.listbox.get_children():
            self.listbox.remove(child)
        if not items:
            empty = Gtk.Label(label="Nothing scheduled. "
                                    "If something is missing, it is not on your Google Calendar yet.")
            empty.get_style_context().add_class("muted")
            empty.set_line_wrap(True)
            empty.set_xalign(0.0)
            empty.set_name("card")
            self.listbox.pack_start(empty, False, False, 0)
            self.listbox.show_all()
            return
        for e in items:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            row.get_style_context().add_class("row")
            if e["due"]:
                tag = Gtk.Label(label="DUE")
                tag.get_style_context().add_class("due")
                row.pack_start(tag, False, False, 0)
                when = "11:59 PM" if e["when"] else "all day"
            else:
                when = e["when"].strftime("%-I:%M %p") if e["when"] else "all day"
            wl = Gtk.Label(label=when)
            wl.get_style_context().add_class("muted")
            wl.set_size_request(78, -1)
            wl.set_xalign(0.0)
            row.pack_start(wl, False, False, 0)
            tl = Gtk.Label(label=e["title"])
            tl.get_style_context().add_class("due" if e["due"] else "event")
            tl.set_xalign(0.0)
            tl.set_line_wrap(True)
            row.pack_start(tl, True, True, 0)
            self.listbox.pack_start(row, False, False, 0)
        self.listbox.show_all()

    def goto_today(self, *_):
        t = date.today()
        self.cal.select_month(t.month - 1, t.year)
        self.cal.select_day(t.day)

    def open_gcal(self, *_):
        subprocess.Popen(["xdg-open", "https://calendar.google.com/"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def on_key(self, _w, event):
        key = event.keyval
        # A key delivered in the first moment after the surface appears is never his
        # intent — it belongs to whatever had focus before (and a stray Escape would
        # close the window he just asked for). Swallow that instant, then behave.
        if self.mapped_at and time.monotonic() - self.mapped_at < 1.0:
            return True
        if key == Gdk.KEY_Escape:
            Gtk.main_quit()
            return True
        if key in (Gdk.KEY_t, Gdk.KEY_T):
            self.goto_today()
            return True
        if key in (Gdk.KEY_r, Gdk.KEY_R):
            if not self.loading:
                self.refresh()
            return True
        if key == Gdk.KEY_Left:
            self.cal.select_month(self.cal.get_date()[1] - 1 if self.cal.get_date()[1] > 0 else 11,
                                  self.cal.get_date()[0] - (1 if self.cal.get_date()[1] == 0 else 0))
            return True
        if key == Gdk.KEY_Right:
            self.cal.select_month((self.cal.get_date()[1] + 1) % 12,
                                  self.cal.get_date()[0] + (1 if self.cal.get_date()[1] == 11 else 0))
            return True
        return False


def dump() -> int:
    days = fetch_entries()
    wd = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    for key in sorted(days):
        d = date(*key)
        print(f"{wd[d.weekday()]} {d.isoformat()}  ({len(days[key])})")
        for e in days[key]:
            when = "all day" if e["allday"] else e["when"].strftime("%-I:%M %p")
            print(f"    {'DUE ' if e['due'] else '    '}{when:9s} {e['title']}")
    print(f"\n{len(days)} day(s) with entries, "
          f"{sum(len(v) for v in days.values())} entr(ies) total")
    return 0


def selftest() -> int:
    """Build the whole window and drive it, WITHOUT mapping it (no window on screen).

    This is the check that catches the class of bug a screenshot cannot: the widget
    tree, the marks, the day panel and the UP NEXT rows all being built and filled.
    Run it any time the layout changes:  ledger-calendar.py --selftest
    """
    failures = []

    def check(name, ok, detail=""):
        print(f"  {'PASS' if ok else 'FAIL'}  {name}{' — ' + detail if detail else ''}")
        if not ok:
            failures.append(name)

    win = LedgerCalendar(show=False)
    check("window builds with the layer shell configured", win is not None)
    check("no window was mapped (nothing on screen)",
          not win.get_mapped() and not win.get_visible())

    try:
        days = fetch_entries()
    except Exception as exc:  # noqa: BLE001
        check("Google Calendar fetch", False, str(exc)[:80])
        print(f"\n{len(failures)} failure(s)")
        return 1
    check("Google Calendar fetch", True, f"{len(days)} day(s) with entries")

    win.days = days
    win.loading = False
    win._apply(days, None)
    check("subtitle filled in", bool(win.subtitle.get_text().strip()),
          win.subtitle.get_text())

    # pick a day that has a deadline and confirm the right panel shows it
    due_days = [k for k, items in days.items() if any(e["due"] for e in items)]
    if due_days:
        y, m, d = sorted(due_days)[0]
        win.cal.select_month(m - 1, y)
        win.cal.select_day(d)
        win.on_day(win.cal)
        rows = win.listbox.get_children()
        texts = " | ".join(
            " ".join(c.get_text() for c in row.get_children() if isinstance(c, Gtk.Label))
            for row in rows if isinstance(row, Gtk.Box))
        check("a deadline day lists its entry", bool(rows) and "DUE" in texts, texts[:110])
    else:
        check("a deadline day lists its entry", False, "no due entries found at all")

    up = win.upcoming.get_children()
    up_text = " ".join(
        " ".join(c.get_text() for c in row.get_children() if isinstance(c, Gtk.Label))
        for row in up if isinstance(row, Gtk.Box))
    check("UP NEXT has rows", bool(up), up_text[:110])
    ahead = upcoming_items(days, 99)
    check("UP NEXT starts at today, never in the past",
          all(d >= date.today() for d, _ in ahead),
          f"{len(ahead)} upcoming entr(ies)")
    check("UP NEXT is soonest-first",
          [d for d, _ in ahead] == sorted(d for d, _ in ahead))
    check("a due date sorts above a plain event on the same day",
          all(items[0]["due"] or not any(e["due"] for e in items)
              for items in days.values()))

    print(f"\n{len(failures)} failure(s)")
    return 1 if failures else 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="ledger-calendar")
    ap.add_argument("--day", help="open focused on YYYY-MM-DD")
    ap.add_argument("--month", help="open showing YYYY-MM")
    ap.add_argument("--dump", action="store_true", help="print what it parsed, no window")
    ap.add_argument("--selftest", action="store_true",
                    help="build and drive the UI without showing it (silent check)")
    args = ap.parse_args()

    if args.dump:
        return dump()

    if args.selftest:
        style = Gtk.CssProvider()
        style.load_from_data(CSS)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        return selftest()

    focus_day = datetime.strptime(args.day, "%Y-%m-%d").date() if args.day else None
    month = None
    if args.month:
        y, m = args.month.split("-")
        month = date(int(y), int(m), 1)
    elif focus_day:
        month = focus_day

    style = Gtk.CssProvider()
    style.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    started = time.monotonic()
    LedgerCalendar(focus_day, month)
    Gtk.main()
    # Goes to $XDG_RUNTIME_DIR/ledger-calendar.out (ledger-bar.sh redirects stdout
    # there). If the panel ever flashes and vanishes, this line says for how long and
    # the traceback above it says why.
    print(f"closed after {time.monotonic() - started:.1f}s", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

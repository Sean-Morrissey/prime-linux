#!/usr/bin/python3
"""Prime Search — the one box that finds anything, and asks Prime for the rest.

Super+Space opens it. Typing searches locally and instantly (no model in the
loop): applications, then files and folders under ~. Enter opens the top hit.
Anything with no local match becomes a question for Prime — same path as the
bar's ask box (`prime-bar.py ask`), so the answer lands wherever he is.

Prefixes, for when the guessing is wrong or he wants a specific lane:
    = <expr>     arithmetic, evaluated locally (result copied on Enter)
    > <text>     applications only
    / <text>     search the web via Prime
    ~ <path>     jump straight to a file/folder

Design rule borrowed from the whiteboard/ledger surfaces: never pop a window at
@USER@ while he is working. `--selftest` and `--query` exercise the whole thing
without mapping anything; the only reason to see this window is him pressing the
key.

  prime-spotlight.py                 run it (this is what the keybind does)
  prime-spotlight.py --selftest      every source + the router, no window
  prime-spotlight.py --query "@STUDY_PLATFORM@" what the list would show, headless
"""
from __future__ import annotations

import argparse
import ast
import html
import operator
import os
import re
import shlex
import subprocess
import sys
import threading
import time
import urllib.parse
import xml.etree.ElementTree as ET

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell
    HAVE_LAYER = True
except (ValueError, ImportError):
    GtkLayerShell = None
    HAVE_LAYER = False

HOME = os.path.expanduser("~")
PRIME_BAR = os.path.join(HOME, ".hermes", "scripts", "prime-bar.py")
VENV_PY = os.path.join(HOME, ".hermes", "hermes-agent", "venv", "bin", "python3")
XDG_DATA_DIRS = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
APP_DIRS = [os.path.join(d, "applications") for d in XDG_DATA_DIRS] + [
    os.path.join(HOME, ".local/share/applications"),
    "/var/lib/flatpak/exports/share/applications",
    os.path.join(HOME, ".local/share/flatpak/exports/share/applications"),
]
SKIP_DIRS = {".git", "node_modules", ".cache", ".venv", "venv", "__pycache__",
             ".npm", ".cargo", ".rustup", ".local/share/Trash"}
MAX_ROWS = 9
ROW_H = 46

CSS = b"""
window { background: transparent; }
#card { background: alpha(#1c1c1e, 0.94); border: 1px solid alpha(#ffffff, 0.13);
        border-radius: 14px; padding: 10px; }
entry { background: alpha(#ffffff, 0.07); border: 1px solid alpha(#ffffff, 0.16);
        border-radius: 9px; padding: 9px 12px; caret-color: #ffffff; }
.row { padding: 7px 10px; border-radius: 8px; }
.row.sel { background: alpha(#4c8dff, 0.30); }
.kind { color: alpha(#ffffff, 0.42); }
.main { color: #f4f4f5; }
.sub  { color: alpha(#ffffff, 0.45); }
.mono { font-family: monospace; color: #ffd479; }
"""


# ── sources ────────────────────────────────────────────────────────────────────

def _desktop_field(text: str, key: str) -> str:
    m = re.search(rf"^{key}=(.*)$", text, re.M)
    return (m.group(1) if m else "").strip()


def load_apps() -> list:
    """[(name, exec, desktop_id, comment)] from every XDG applications dir."""
    out, seen = [], set()
    for d in APP_DIRS:
        try:
            names = sorted(os.listdir(d))
        except OSError:
            continue
        for fn in names:
            if not fn.endswith(".desktop") or fn in seen:
                continue
            seen.add(fn)
            path = os.path.join(d, fn)
            try:
                with open(path, encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError:
                continue
            if _desktop_field(text, "NoDisplay").lower() == "true":
                continue
            if _desktop_field(text, "Type") not in ("", "Application"):
                continue
            name = _desktop_field(text, "Name")
            exe = _desktop_field(text, "Exec")
            if not name or not exe:
                continue
            out.append((name, exe, fn[:-len(".desktop")],
                        _desktop_field(text, "Comment")))
    return out


def load_recent(limit: int = 12) -> list:
    """Recently opened files from the GTK bookmark file, newest first."""
    xbel = os.path.join(HOME, ".local/share/recently-used.xbel")
    try:
        root = ET.parse(xbel).getroot()
    except (OSError, ET.ParseError):
        return []
    rows = []
    for bm in root.iter("bookmark"):
        href = bm.get("href", "")
        if not href.startswith("file://"):
            continue
        path = urllib.parse.unquote(href[len("file://"):])
        if not os.path.exists(path):
            continue
        rows.append((bm.get("visited") or bm.get("modified") or "", path))
    rows.sort(reverse=True)
    out, seen = [], set()
    for _, path in rows:
        if path in seen:
            continue
        seen.add(path)
        out.append(path)
        if len(out) >= limit:
            break
    return out


def find_paths(query: str, limit: int = 24, timeout: int = 4) -> list:
    """Files and folders under ~ matching `query`, best-first (fd, then plocate)."""
    q = query.strip()
    if not q:
        return []
    args = ["fd", "--absolute-path", "--max-results", str(limit),
            "--type", "f", "--type", "d", "--color", "never",
            "--hidden"]        # his scripts/config live in dot-dirs (.hermes, .config)
    for d in SKIP_DIRS:
        args += ["--exclude", d]
    args += ["--", q, HOME]
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        hits = [ln for ln in r.stdout.splitlines() if ln.strip()]
    except (OSError, subprocess.TimeoutExpired):
        hits = []
    if not hits:                      # plocate covers the rest of the disk, instantly
        try:
            r = subprocess.run(["plocate", "-i", "-l", str(limit), "--", q],
                               capture_output=True, text=True, timeout=timeout)
            hits = [ln for ln in r.stdout.splitlines() if ln.strip()]
        except (OSError, subprocess.TimeoutExpired):
            hits = []
    return hits


# ── local arithmetic (= prefix) ────────────────────────────────────────────────

_OPS = {ast.Add: operator.add, ast.Sub: operator.sub, ast.Mult: operator.mul,
        ast.Div: operator.truediv, ast.FloorDiv: operator.floordiv,
        ast.Mod: operator.mod, ast.Pow: operator.pow, ast.USub: operator.neg,
        ast.UAdd: operator.pos}


def _eval_node(node):
    if isinstance(node, ast.Expression):
        return _eval_node(node.body)
    if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
        return node.value
    if isinstance(node, ast.BinOp) and type(node.op) in _OPS:
        return _OPS[type(node.op)](_eval_node(node.left), _eval_node(node.right))
    if isinstance(node, ast.UnaryOp) and type(node.op) in _OPS:
        return _OPS[type(node.op)](_eval_node(node.operand))
    raise ValueError("not arithmetic")


def calc(expr: str) -> str:
    """Safe arithmetic. Empty string when it is not a sum we should answer."""
    expr = expr.strip().lstrip("=").strip().replace("^", "**").replace("×", "*").replace("÷", "/")
    if not expr or not re.fullmatch(r"[0-9 .+\-*/%()]+", expr):
        return ""
    try:
        value = _eval_node(ast.parse(expr, mode="eval"))
    except (SyntaxError, ValueError, TypeError, ZeroDivisionError, OverflowError):
        return ""
    if isinstance(value, float):
        if value.is_integer():
            value = int(value)
        else:
            value = round(value, 6)
    return str(value)


# ── ranking + routing (pure, so the self-test can assert them) ─────────────────

def rank_apps(query: str, apps: list, limit: int = 6) -> list:
    q = query.lower().strip()
    scored = []
    for name, exe, did, comment in apps:
        n, d = name.lower(), did.lower()
        if not q:
            continue
        if n.startswith(q):
            score = 0
        elif any(w.startswith(q) for w in re.split(r"[\s\-_.]+", n)):
            score = 1
        elif q in n:
            score = 2
        elif q in d or q in exe.lower():
            score = 3
        else:
            continue
        scored.append((score, len(name), name, exe, did, comment))
    scored.sort()
    return [("app", s[2], s[4], s[5]) for s in scored[:limit]]


def rank_paths(query: str, paths: list, existing: set, limit: int = 6) -> list:
    """Existing files first, then shortest path, then name-prefix matches."""
    q = query.lower().strip()
    rows = []
    for p in paths:
        name = os.path.basename(p.rstrip("/")) or p
        base = name.lower()
        if not q and p not in existing:
            continue
        if q and q not in base and q not in p.lower():
            # keep weak hits only if the basename at least starts with the query
            if not base.startswith(q[:3]):
                continue
        rows.append((0 if p in existing else 1,
                     0 if base.startswith(q) else 1,
                     len(p), p, name))
    rows.sort()
    return [("path", r[4], r[3], "") for r in rows[:limit]]


def route(kind: str, main: str, sub: str, query: str) -> tuple:
    """What Enter does. Pure decision, so it can be tested without a keyboard."""
    if kind == "app":
        return ("launch_app", sub)                     # gtk-launch <desktop id>
    if kind == "path":
        return ("open_path", sub)
    if kind == "math":
        return ("copy", main)
    return ("ask", (f"search the web for {query}" if query.startswith("/")
                    else query))


def results_for(query: str, apps: list, recents: list, timeout: int = 4) -> list:
    """The whole list for a query: [(kind, main, sub, right)] + the always-ask row."""
    q = query.strip()
    rows = []
    if not q:
        rows = [("path", os.path.basename(p.rstrip("/")) or p, p, "recent")
                for p in recents[:MAX_ROWS]]
        return rows or [("hint", "Type to search apps, files, folders — or =2+2",
                         "Enter on a local hit opens it · anything else asks Prime", "")]

    asked_only_apps = q.startswith(">")
    asked_only_web = q.startswith("/")
    body = q.lstrip(">/").strip() if (asked_only_apps or asked_only_web) else q

    if q.startswith("="):
        value = calc(q)
        if value:
            rows.append(("math", f"= {value}", q.lstrip("=").strip(), "copy"))
    if not asked_only_web:
        rows += rank_apps(body, apps, 6 if not asked_only_apps else MAX_ROWS)
    if not asked_only_apps and not asked_only_web and not q.startswith("="):
        hits = find_paths(body, timeout=timeout)
        existing = set(recents)
        rows += rank_paths(body, hits, existing, 6)
    ask = ("/ " if asked_only_web else "") + body
    rows.append(("ask", f"Ask Prime: {ask}", "the model gets the question as typed", "enter"))
    return rows[:MAX_ROWS + 1]


# ── window ─────────────────────────────────────────────────────────────────────

class SearchWindow(Gtk.Window):
    def __init__(self, show: bool = True):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.apps = load_apps()
        self.recents = load_recent()
        self.rows: list = []
        self.sel = 0
        self.seq = 0                       # guards against out-of-order searches
        self.mapped_at = 0.0

        self.set_name("prime-spotlight")
        self.set_decorated(False)
        self.set_skip_taskbar_hint(True)
        self.set_resizable(False)
        self.set_default_size(720, -1)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        card.set_name("card")
        outer.pack_start(card, True, True, 0)
        self.add(outer)

        self.entry = Gtk.Entry()
        self.entry.set_placeholder_text("Search apps, files, folders — or just ask")
        self.entry.connect("changed", self.on_changed)
        self.entry.connect("activate", lambda *_: self.run_selected())
        self.entry.connect("key-press-event", self.on_key)
        card.pack_start(self.entry, False, False, 0)

        self.listbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=1)
        card.pack_start(self.listbox, False, False, 0)

        self.hint = Gtk.Label(label="↑↓ pick   ·   Enter open   ·   =math   ·   /web   ·   Esc close")
        self.hint.set_name("hint")
        self.hint.get_style_context().add_class("sub")
        self.hint.set_xalign(0.0)
        card.pack_start(self.hint, False, False, 0)

        self.setup_layer()
        self.connect("map", lambda *_: setattr(self, "mapped_at", time.monotonic()))
        self.connect("focus-out-event", lambda *_: self.hide_now())
        self.render(results_for("", self.apps, self.recents, timeout=1))
        if show:
            self.show_all()
            self.entry.grab_focus()

    def setup_layer(self):
        if not HAVE_LAYER:
            return
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, "prime-spotlight")
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 190)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)

    # ── results ──────────────────────────────────────────────────────────────
    def on_changed(self, _entry):
        self.seq += 1
        seq = self.seq
        GLib.timeout_add(70, self._search, seq)

    def _search(self, seq: int) -> bool:
        if seq != self.seq:
            return False
        query = self.entry.get_text()
        threading.Thread(target=self._search_worker, args=(seq, query), daemon=True).start()
        return False

    def _search_worker(self, seq: int, query: str):
        try:
            rows = results_for(query, self.apps, self.recents)
        except Exception:                       # noqa: BLE001 - a launcher never crashes
            rows = []
        GLib.idle_add(self._apply, seq, rows)

    def _apply(self, seq: int, rows: list) -> bool:
        if seq != self.seq or rows is None:
            return False
        self.render(rows)
        return False

    def render(self, rows: list):
        self.rows = rows
        self.sel = 0
        for child in self.listbox.get_children():
            self.listbox.remove(child)
        for i, (kind, main, sub, right) in enumerate(rows):
            self.listbox.pack_start(self.make_row(kind, main, sub, right, i), False, False, 0)
        self.listbox.show_all()
        self.highlight()

    def make_row(self, kind, main, sub, right, idx) -> Gtk.Box:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.set_name(f"row{idx}")
        row.get_style_context().add_class("row")
        glyph = {"app": "▸", "path": "▪", "math": "＝", "ask": "✱", "hint": "·"}.get(kind, "·")
        tag = Gtk.Label(label=glyph)
        tag.get_style_context().add_class("kind")
        row.pack_start(tag, False, False, 0)
        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        lab = Gtk.Label(label=main)
        lab.set_xalign(0.0)
        lab.set_ellipsize(3)
        lab.get_style_context().add_class("mono" if kind == "math" else "main")
        text.pack_start(lab, False, False, 0)
        if sub:
            sub_label = Gtk.Label(label=html.escape(sub))
            sub_label.set_xalign(0.0)
            sub_label.set_ellipsize(3)
            sub_label.get_style_context().add_class("sub")
            text.pack_start(sub_label, False, False, 0)
        row.pack_start(text, True, True, 0)
        if right:
            r = Gtk.Label(label=right)
            r.get_style_context().add_class("kind")
            row.pack_end(r, False, False, 0)
        row.set_size_request(-1, ROW_H if sub else 34)
        return row

    def highlight(self):
        for i, child in enumerate(self.listbox.get_children()):
            ctx = child.get_style_context()
            if i == self.sel:
                ctx.add_class("sel")
            else:
                ctx.remove_class("sel")

    # ── input ────────────────────────────────────────────────────────────────
    def on_key(self, _w, event) -> bool:
        key = event.keyval
        if (time.monotonic() - self.mapped_at) < 1.0 and key == Gdk.KEY_Escape:
            return True                    # a stray key at map time is not an intent
        if key == Gdk.KEY_Escape:
            self.hide_now()
            return True
        if key == Gdk.KEY_Down:
            self.sel = min(self.sel + 1, len(self.rows) - 1)
            self.highlight()
            return True
        if key == Gdk.KEY_Up:
            self.sel = max(self.sel - 1, 0)
            self.highlight()
            return True
        return False

    def hide_now(self, *_a) -> bool:
        Gtk.main_quit()
        return False

    def run_selected(self):
        if not self.rows:
            return
        kind, main, sub, _right = self.rows[self.sel]
        if kind == "hint":
            return
        action, payload = route(kind, main, sub, self.entry.get_text().strip())
        self.hide_now()
        if action == "launch_app":
            detached(["gtk-launch", payload])
        elif action == "open_path":
            detached(["xdg-open", payload])
        elif action == "copy":
            copy_to_clipboard(payload)
        elif action == "ask":
            detached(["python3" if not os.path.exists(VENV_PY) else VENV_PY,
                      PRIME_BAR, "ask", payload])


def detached(cmd: list):
    """Fire and forget, fully detached from this process group."""
    env = dict(os.environ)
    env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True, env=env)
    except OSError:
        pass


def copy_to_clipboard(text: str):
    for tool in (["wl-copy"], ["xclip", "-selection", "clipboard"]):
        try:
            p = subprocess.run(tool, input=text, text=True, timeout=5)
            if p.returncode == 0:
                return
        except (OSError, subprocess.TimeoutExpired):
            continue


# ── headless verification ──────────────────────────────────────────────────────

def run_query(query: str) -> int:
    apps = load_apps()
    recents = load_recent()
    for kind, main, sub, right in results_for(query, apps, recents):
        print(f"  {kind:<5} {main:<52} {sub[:60]:<60} {right}")
    return 0


def selftest() -> int:
    """Exercise every source and the router without mapping a window."""
    fails = []

    def check(name, ok, detail=""):
        print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f" — {detail}" if detail else ""))
        if not ok:
            fails.append(name)

    apps = load_apps()
    check("application menu parsed", len(apps) > 50 and any("Chrome" in a[0] for a in apps),
          f"{len(apps)} entries, {sum(1 for a in apps if 'Chrome' in a[0])} browsers/indexers")

    hits = rank_apps("chrom", apps)
    check("app search finds a browser", bool(hits) and "chrom" in hits[0][1].lower(),
          hits[0][1] if hits else "nothing for 'chrom'")

    check("arithmetic is exact", calc("=16*7/4") == "28" and calc("=2^10") == "1024"
          and calc("=10-2.5") == "7.5", f"16*7/4={calc('=16*7/4')} 2^10={calc('=2^10')}")
    check("not-arithmetic is refused", calc("hello") == "" and calc("=1;rm -rf /") == "")

    paths = find_paths("book-semester")
    check("file search returns paths", any("book-semester" in p for p in paths),
          f"{len(paths)} hit(s), first {paths[0] if paths else '—'}")

    rows = results_for("book-semester", apps, [])
    check("router opens a file hit",
          any(r[0] == "path" for r in rows) and route("path", "", "/tmp/x", "")[0] == "open_path")
    check("router launches an app hit", route("app", "", "firefox", "") == ("launch_app", "firefox"))
    check("router copies a sum", route("math", "= 28", "", "=16*7/4") == ("copy", "= 28"))
    check("no match falls through to Prime",
          rows[-1][0] == "ask" and route("ask", "", "", "how tall is the sears tower")[0] == "ask",
          rows[-1][1][:60])
    check("web prefix routes a web ask",
          route("ask", "", "", "/cheapest pla filament")[1].startswith("search the web for"))

    recents = load_recent()
    check("recent files parsed", isinstance(recents, list), f"{len(recents)} entries")

    win = SearchWindow(show=False)
    check("window builds with the layer shell configured", win.get_name() == "prime-spotlight")
    check("nothing was mapped (no window on screen)",
          not win.get_mapped() and not win.get_visible(),
          "built but never shown, then destroyed")
    win.destroy()

    print(f"\n{len(fails)} failure(s)")
    return 1 if fails else 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="prime-spotlight")
    ap.add_argument("--selftest", action="store_true", help="verify everything, map nothing")
    ap.add_argument("--query", help="print the list for a query, headless")
    ap.add_argument("--seconds", type=float, default=0, help="auto-close after N seconds")
    a = ap.parse_args()

    if a.selftest:
        return selftest()
    if a.query is not None:
        return run_query(a.query)

    style = Gtk.CssProvider()
    style.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    started = time.monotonic()
    win = SearchWindow()
    if a.seconds:
        GLib.timeout_add(int(a.seconds * 1000), lambda: (win.hide_now(), False)[1])
    Gtk.main()
    print(f"closed after {time.monotonic() - started:.1f}s", flush=True)
    return 0


if __name__ == "__main__":
    if not os.environ.get("WAYLAND_DISPLAY") and os.environ.get("PRIME_SPOTLIGHT_STRICT"):
        sys.exit("prime-spotlight: no WAYLAND_DISPLAY")
    sys.exit(main())

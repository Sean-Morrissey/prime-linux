#!/usr/bin/env python3
"""prime-entry.py — a real text box for the bar scripts.

rofi's entry is a dead end for clipboard work: on Wayland its 2.0.0 backend asks
for "text/plain" while modern apps (Chrome, GTK, Firefox) offer only
"text/plain;charset=utf-8", so Ctrl+V into a rofi box inserts nothing and there
is no right-click menu at all.

This is a small GTK3 window styled like the glass bar box, with the behaviour a
text box is supposed to have:
  * right-click → Cut / Copy / Paste / Delete / Select All
  * Ctrl+V (and middle-click) paste, through GTK's clipboard, which negotiates
    the charset properly — so pasted text actually arrives
  * multi-line pastes are kept (Enter submits, Shift+Enter makes a new line)
  * Esc cancels, Enter submits

Usage:  prime-entry.py [-p PROMPT] [-w WIDTH] [--text PREFILL] [--demo-menu]
Prints the text to stdout and exits 0; exits 1 if cancelled.
"""
import argparse
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk  # noqa: E402

# Wayland ignores client-side window positioning, so a plain toplevel lands
# wherever the compositor feels like it (measured: middle of the monitor, not the
# bar). Layer shell is how the bar boxes actually get to hang under the bar, and
# EXCLUSIVE keyboard mode is what makes typing land in the box every time.
try:
    gi.require_version("GtkLayerShell", "0.1")
    from gi.repository import GtkLayerShell  # noqa: E402

    HAVE_LAYER = True
except Exception:  # pragma: no cover - fallback for a machine without the typelib
    HAVE_LAYER = False

CSS = b"""
window {
  background-color: rgba(10, 10, 14, 0.96);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 14px;
}
#box {
  background-color: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  border-radius: 10px;
  padding: 10px 14px;
}
#prompt {
  color: #c084fc;
  font-weight: bold;
}
textview, textview text {
  background-color: transparent;
  color: #e4e4e7;
  font-size: 14px;
}
.hint { color: #a1a1a6; font-size: 11px; }
menu, menuitem {
  background-color: #14141c;
  color: #e4e4e7;
  font-size: 13px;
}
menuitem:hover { background-color: rgba(192, 132, 252, 0.25); }
"""


def clipboard_text():
    """Text from the regular clipboard, or None.

    GDK negotiates the charset properly (so pasted text actually arrives, unlike
    rofi), and wl-paste is the fallback — it is the one path proven to work on
    this machine even when a toolkit's offers arrive late.
    """
    cb = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
    try:
        text = cb.wait_for_text()
    except Exception:
        text = None
    if text:
        return text
    try:
        import subprocess
        out = subprocess.run(["wl-paste", "--no-newline"], capture_output=True,
                             text=True, timeout=3)
        return out.stdout or None
    except Exception:
        return None


class PrimeEntry(Gtk.Window):
    def __init__(self, prompt, width, prefill, demo_menu=False):
        super().__init__(type=Gtk.WindowType.TOPLEVEL)
        self.result = None
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_skip_taskbar_hint(True)
        self.set_skip_pager_hint(True)
        self.set_keep_above(True)
        self.set_default_size(width, -1)
        self.connect("key-press-event", self.on_key)
        self.connect("destroy", lambda *_: Gtk.main_quit())

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        outer.set_margin_top(10)
        outer.set_margin_bottom(10)
        outer.set_margin_start(10)
        outer.set_margin_end(10)
        self.add(outer)

        frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        frame.set_name("box")
        outer.pack_start(frame, True, True, 0)

        head = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        label = Gtk.Label(label=prompt)
        label.set_name("prompt")
        head.pack_start(label, False, False, 0)
        frame.pack_start(head, False, False, 0)

        self.view = Gtk.TextView()
        self.view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.view.set_left_margin(2)
        self.view.set_right_margin(2)
        self.view.set_border_width(0)
        self.view.set_accepts_tab(False)
        self.view.set_size_request(-1, 26)
        frame.pack_start(self.view, True, True, 0)
        if prefill:
            self.view.get_buffer().set_text(prefill)

        hint = Gtk.Label(label="Enter → send   ·   Shift+Enter → new line   ·   right-click for copy/paste   ·   Esc → cancel")
        hint.set_name("hint")
        hint.get_style_context().add_class("hint")
        hint.set_xalign(0.0)
        outer.pack_start(hint, False, False, 0)

        # Windows-style context menu, wired to explicit handlers so the paste
        # path is ours (and testable) rather than toolkit folklore.
        self.menu = Gtk.Menu()
        for label_, cb in (("Cut", self.cut),
                           ("Copy", self.copy),
                           ("Paste", self.paste),
                           ("Delete", self.delete),
                           ("Select All", self.select_all)):
            item = Gtk.MenuItem(label=label_)
            item.connect("activate", cb)
            self.menu.append(item)
        self.menu.show_all()

        self.view.connect("button-press-event", self.on_button)
        self.view.connect("populate-popup", self.on_populate_popup)

        self.setup_layer()          # layer-shell config must precede the map
        self.show_all()
        if not HAVE_LAYER:
            self.place_top_center()
        self.view.grab_focus()
        if prefill:
            self.view.get_buffer().place_cursor(self.view.get_buffer().get_end_iter())
        if demo_menu:
            GLib.timeout_add(400, self.popup_menu)

    # ── geometry: layer shell puts the box under the bar and takes the keyboard
    #    exclusively (Wayland ignores client positioning, so a plain toplevel
    #    lands wherever the compositor likes and may not even get focus) ───────
    def setup_layer(self):
        if not HAVE_LAYER:
            return
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, "prime-entry")
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        GtkLayerShell.set_anchor(self, GtkLayerShell.Edge.TOP, True)
        GtkLayerShell.set_margin(self, GtkLayerShell.Edge.TOP, 52)
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)

    # fallback only — used when the layer-shell typelib is missing
    def place_top_center(self):
        display = Gdk.Display.get_default()
        try:
            seat = display.get_default_seat()
            pointer = seat.get_pointer()
            _, x, y = pointer.get_position()
            monitor = display.get_monitor_at_point(x, y)
        except Exception:
            monitor = display.get_primary_monitor()
        geo = monitor.get_geometry()
        w, h = self.get_size()
        self.move(geo.x + max(0, (geo.width - w) // 2), geo.y + 52)

    # ── clipboard actions ───────────────────────────────────────────────────
    def on_populate_popup(self, _view, popup):
        # Drop GTK's own entries; the menu is ours (see on_button).
        for child in popup.get_children():
            popup.remove(child)

    def on_button(self, _view, event):
        if event.button == 3:
            self.menu.popup_at_pointer(event)
            return True
        if event.button == 2:  # middle-click paste, like X11
            self.paste(None)
            return True
        return False

    def popup_menu(self, event=None):
        if event is not None:
            self.menu.popup_at_pointer(event)
        else:  # --demo-menu: no real event to hang the popup off
            self.menu.popup_at_widget(self.view, Gdk.Gravity.SOUTH_WEST,
                                      Gdk.Gravity.NORTH_WEST, None)
        return False

    def paste(self, _item):
        text = clipboard_text()
        if text:
            self.view.get_buffer().insert_at_cursor(text)
        return True

    def copy(self, _item):
        buf = self.view.get_buffer()
        if buf.get_has_selection():
            a, b = buf.get_selection_bounds()
            Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD).set_text(buf.get_text(a, b, True), -1)

    def cut(self, _item):
        self.copy(None)
        self.delete(None)

    def delete(self, _item):
        buf = self.view.get_buffer()
        if buf.get_has_selection():
            a, b = buf.get_selection_bounds()
            buf.delete(a, b)

    def select_all(self, _item):
        buf = self.view.get_buffer()
        buf.select_range(buf.get_start_iter(), buf.get_end_iter())

    # ── keys ────────────────────────────────────────────────────────────────
    def on_key(self, _w, event):
        key = event.keyval
        ctrl = bool(event.state & Gdk.ModifierType.CONTROL_MASK)
        shift = bool(event.state & Gdk.ModifierType.SHIFT_MASK)
        if key == Gdk.KEY_Escape:
            self.result = None
            Gtk.main_quit()
            return True
        if key in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
            if shift or ctrl:            # newline inside the box
                self.view.get_buffer().insert_at_cursor("\n")
                return True
            buf = self.view.get_buffer()
            self.result = buf.get_text(buf.get_start_iter(), buf.get_end_iter(), True)
            self.result = self.result.strip("\n")
            Gtk.main_quit()
            return True
        if ctrl and key == Gdk.KEY_v:
            self.paste(None)
            return True
        if ctrl and key == Gdk.KEY_a:
            self.select_all(None)
            return True
        return False


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-p", "--prompt", default="󰚩 Prime")
    ap.add_argument("-w", "--width", type=int, default=640)
    ap.add_argument("--text", default="")
    ap.add_argument("--demo-menu", action="store_true", help="open the right-click menu (UI check)")
    args = ap.parse_args()

    style = Gtk.CssProvider()
    style.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), style, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    win = PrimeEntry(args.prompt, args.width, args.text, args.demo_menu)
    Gtk.main()
    if win.result is None:
        sys.exit(1)
    sys.stdout.write(win.result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

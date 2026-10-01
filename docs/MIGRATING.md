# Moving your own Hyprland desktop onto Prime Linux

You set up Hyprland by hand before Prime existed: your own shortcuts, two
screens arranged just so, bar items that call your scripts, a few background
services. This page moves all of that onto Prime **without losing anything**,
and with **one step to go back** if you don't like the result.

## First: why this is safe

- **Everything is saved before anything changes.** `prime-import --apply` first
  saves a copy of your whole desktop (bar, window manager, menus, notifications,
  terminal, Prime's settings and your background services) in two places:
  `~/.config-backups/desktop/` (the same backups Prime makes before every update)
  and its own `~/.config-backups/import-<date>/`. Both are private to your account.
- **One command undoes it, exactly.** `prime-import --undo` puts those folders
  back the way they were — every file, link and permission. It also leaves a
  script, `~/.config-backups/import-<date>/restore.sh`, that does the same thing
  even if Prime itself were gone.
- **Nothing is deleted.** Files Prime has to replace are *renamed* (for example
  `hyprland.conf` becomes `hyprland.conf.before-prime`), and your scripts,
  sourced config files and wallpapers stay exactly where they are.
- **Your secrets stay put.** API keys, tokens and passwords are never copied:
  not `.env` files, not `*.key`, not `auth.json`, not a key pasted into a config
  line, not a background service with a password written inside it. Those
  stay where they are, untouched, and the report lists them so you know.
- **Your AI key is never put in a backup.** The undo leaves it as it is.
- **Look first.** `prime-import` on its own only *shows* the plan and changes
  nothing.

## Step by step

You need Prime Linux installed (see [USER-GUIDE.md](USER-GUIDE.md)). If the
installer found your old setup, it already offered to do this at the end; you
can still do it — or redo it — any time.

1. **See the plan.** Open a terminal and type:

   ```
   prime-import
   ```

   It lists, in plain words, what it would bring over and where it would put it.
   Nothing changes yet. If you installed Prime over your old setup, it finds the
   copy the installer saved (in `~/.config-backups/prime-install-…`) by itself.

2. **Check the clashes.** If one of your shortcuts uses a key Prime already uses
   (say Super+B), the plan says so. Prime keeps your line but switches it off, so
   no key does two things. You can pick another key later (step 6).

3. **Do it.**

   ```
   prime-import --apply
   ```

   It asks once, saves everything, then shows four steps. At the end it says
   where the report is.

4. **Log out and back in** (or press Super+W to restart the bar). Your
   shortcuts are in **Super+/**, your bar items are on Prime's bar, your screens
   are arranged as before.

5. **Not happy? Go back.**

   ```
   prime-import --undo
   ```

   Then log out and back in. You are exactly where you were before step 3.

6. **Fine-tune (optional).** Everything that came over is in your own add-on,
   `~/.config/prime/addons.d/my-desktop/` — yours to edit, and never changed by
   Prime's updates:

   | File | What's in it |
   |---|---|
   | `hypr.conf` | your shortcuts (each with a description), window rules, your settings, programs started at login; clashing shortcuts, switched off, with how to use them anyway |
   | `waybar-top.json`, `waybar-side.json`, `waybar.css` | your bar items and their styles |
   | `systemd/` | your background services; `UNITS=` in `addon.conf` says which start |
   | `import-report.txt` | what came over, what didn't, what was never copied |
   | `not-imported.conf` | every line that wasn't brought over, and why |

   Switch the whole thing off or on with `prime-addon disable my-desktop` /
   `prime-addon enable my-desktop`. `prime-addon list` shows it marked *(personal)*.

## Where each part goes

| From your old setup | On Prime |
|---|---|
| Shortcuts that aren't Prime's | add-on `hypr.conf`, as `bindd` lines with a description (Super+/ lists them) |
| Shortcuts Prime already has | left out — Prime's do the same |
| Shortcuts on Prime's keys (and the packs' Super+Alt+G/P/H/C/E/V/R/S/F/N/T) | add-on `hypr.conf`, switched off, reported |
| `monitor = …` lines | `~/.config/hypr/monitors.conf` (Settings → Displays edits it) |
| Workspace → screen rules, graphics-card settings (`MESA_VK_DEVICE_SELECT`, `AMD_…`, `__NV_…`) | `~/.config/hypr/hardware.conf`, in a marked block |
| Keyboard layouts | `~/.config/hypr/keyboard.conf` |
| Window rules for your apps | add-on `hypr.conf`, translated to today's Hyprland syntax |
| Programs you start at login | add-on `hypr.conf` — except the bar, wallpaper, notifications, clipboard, network icon and login agents, which Prime runs itself |
| Bar items Prime doesn't have (from the bars you actually started) | `waybar-top.json` / `waybar-side.json` + their CSS |
| Your own background services | add-on `systemd/`, linked from `~/.config/systemd/user` |
| Wallpaper, accent colour | `~/.config/prime/theme.conf` (Theme, Super+Shift+W) |
| Look-and-feel settings (gaps, rounding, blur, animations) | not brought over — Prime has its own look; they're listed in `not-imported.conf` to copy into `~/.config/hypr/hyprland.conf` if you miss one |

Your scripts aren't copied — the add-on calls them where they already are (for
example `~/.config/waybar/scripts/…`), so keep those folders.

## Options

```
prime-import --from DIR     read the old settings from DIR (laid out like ~/.config)
prime-import --name NAME    call the add-on NAME instead of my-desktop
prime-import --apply --yes  don't ask (scripts)
```

A second `--apply` is refused until the first is undone, so there is always
exactly one way back.

## For developers

`tests/check-import.sh` runs the whole round trip on a made-up desktop in
`tests/fixtures/legacy-desktop/` (no container, no root, a throwaway home):
dry run changes nothing; apply brings everything over with no secret copied
and no key bound twice; `Hyprland --verify-config` accepts the result (when
Hyprland is installed); undo restores every file byte for byte.
`tests/check-personal-addons.sh` covers personal add-ons in every tool that
loads add-ons.

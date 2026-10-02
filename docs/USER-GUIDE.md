# Prime Linux — the user guide

For people who have never used Linux. You need about 45 minutes, a USB stick
(8 GB or bigger) and an internet connection. Nothing here needs you to
understand Linux; where you type something, the exact text is given.

---

## 1. Install CachyOS (the base)

Prime Linux sits on top of **CachyOS**, a fast, well-maintained Linux. You
install CachyOS first, the normal way.

1. **Back up** anything important on the computer. If you keep Windows too, the
   CachyOS installer can install *next to* it — choose that option when asked.
2. On another computer, download the CachyOS **Desktop** ISO from
   <https://cachyos.org/download/> and write it to the USB stick with
   [balenaEtcher](https://etcher.balena.io/) (Windows/Mac) or
   [Ventoy](https://www.ventoy.net/).
3. Plug the stick into the computer, turn it on and open the boot menu (usually
   **F12**, **F8**, **Esc** or **F2** right after power-on) and pick the USB stick.
4. When CachyOS starts, click **Launch installer** and answer the questions:
   - **Keyboard**: pick yours here — Prime uses the same layout.
   - **Desktop**: **KDE Plasma** is a safe choice. (It stays on the computer as
     a second option on the login screen, in case you ever want it.)
   - **Bootloader**: leave the default (Limine). **File system**: leave the
     default (btrfs) — it's what lets you undo a bad update from the boot menu.
   - Create your user and password. Remember the password: Prime asks for it once.
5. Restart, take the USB stick out, and log in.

## 2. Add Prime Linux

First open a **terminal**: press the Windows/Super key, type `terminal`, press
Enter (in KDE it's called *Konsole*). Every grey box below is one thing to copy:
select it, copy it, paste it into the terminal with **Ctrl+Shift+V** (or
right-click → Paste) and press **Enter**. When the terminal asks for your
password, type it and press Enter. Nothing appears while you type: that's normal.

Ask the person who gave you Prime Linux which of these two applies.

### If the project is private (you were invited on GitHub)

You need a free GitHub account, and an invitation from the owner.

1. **Accept the invitation.** Open the email from GitHub that says you were
   invited to collaborate on *Sean-Morrissey/prime-linux* and click
   **View invitation**, then **Accept invitation**. (No email? Sign in at
   <https://github.com/notifications>.)
2. **Install GitHub's sign-in tool:**

   ```
   sudo pacman -Syu --needed --noconfirm github-cli git
   ```

3. **Sign this computer in to GitHub:**

   ```
   gh auth login
   ```

   It asks four questions. Move with the arrow keys, press Enter to choose:

   | Question | Choose |
   |---|---|
   | Where do you use GitHub? | **GitHub.com** |
   | Preferred protocol for Git operations? | **HTTPS** |
   | Authenticate Git with your GitHub credentials? | **Yes** |
   | How would you like to authenticate? | **Login with a web browser** |

   It shows a code like `ABCD-1234`. Press Enter: a browser opens. Sign in to
   GitHub, type the code, click **Authorize**. Back in the terminal it says
   **Logged in as …**.
4. **Download Prime Linux:**

   ```
   gh repo clone Sean-Morrissey/prime-linux ~/prime-linux
   ```

5. **Install it:**

   ```
   bash ~/prime-linux/install.sh
   ```

If step 5 stops half-way, paste the step 5 line again: it carries on from where
it stopped. Updates later use the same GitHub sign-in, so don't sign out
(`gh auth logout`) on this computer.

### If the project is public

Paste this one line:

```
curl -fsSL https://raw.githubusercontent.com/sean-morrissey/prime-linux/main/boot.sh | bash
```

If it stops half-way, paste the same line again.

### While it installs

Watch the numbered steps `[1/8] … [8/8]`. It takes 5–15 minutes, mostly
downloading. When it says **Prime Linux is installed**, you're done.

If something goes wrong, the message says what to do (usually "connect to the
internet and run it again"). A full log is kept in `~/.local/state/prime/logs/`.

Want to see what it will do first? Add `--dry-run`: `bash ~/prime-linux/install.sh --dry-run`
(private) or `curl -fsSL …/boot.sh | bash -s -- --dry-run` (public). It shows every
step and changes nothing.

**Already had your own Hyprland setup?** At the end the installer offers to bring
your shortcuts, screens, bar items and background services along as your own
add-on — everything is saved first and `prime-import --undo` reverses it. Details:
[MIGRATING.md](MIGRATING.md).

## 3. First login

1. Log out (or restart).
2. On the login screen, open the **session** menu (KDE/SDDM: bottom-left;
   GNOME: the gear icon) and choose **Prime**. It's remembered next time.
3. Log in. You'll see the top bar, the dock on the left and your wallpaper.
   Open a terminal (Super+Enter) and Prime greets you: **P.R.I.M.E — Please
   Relax I'll Manage Everything**.

Three keys to remember — *Super* is the Windows key:

| Press | You get |
|---|---|
| **Super + Space** | Search: apps, files, sums (type `12*7`), the web |
| **Super + Alt + Space** | The Prime menu: settings, quick switches, tools, updates, power |
| **Super + /** | Every keyboard shortcut, searchable |

Everything in this guide is also in the Prime menu, so you never *need* a terminal.

## 4. Everyday things

### Apps
- **Open an app**: click the **P** logo (or Super+X) for the Start menu — pinned apps, All apps, recent files. Or Super+Space, type its name, Enter. Right-click an app in Start to pin or unpin it.
- **Install an app**: Prime menu → Apps → **App Store**. Click Install.
- **A website as an app** (WhatsApp, YouTube, Gmail…): Prime menu → Capture & tools
  → **Make a website into an app**. It gets its own window and icon.
- **Close a window**: Super+Q, or the red dot on the window's title bar.

### Windows and workspaces
- Windows arrange themselves side by side. **Super+F** makes one fill the screen.
- **Super+1 … Super+9** switch between workspaces (separate desktops).
  **Super+Shift+1…9** moves the current window there.
- **Alt+Tab** switches windows. On a touchpad, swipe sideways with three fingers
  to change workspace.

### Wi-Fi, Bluetooth, sound
Click the icons on the top bar:
- **Wi-Fi icon** → pick a network → type its password once.
- **Bluetooth icon** → pick your headphones/mouse to connect. *Pair a new device…*
  for something new (put the device in pairing mode first).
- **Volume icon** → choose speakers, headphones or microphone. Scroll on it to
  change the volume. The volume and brightness keys show a little popup.

Right-click anything on the bar for more options.

### Screenshots and recordings
| Press | |
|---|---|
| **Print** (or Super+Shift+S) | Screenshot a region — draw a box. It opens for marking up; it's also copied. |
| **Super+Shift+R** | Record a region of the screen. Press again (or click the red ● on the bar) to stop. |
| **Super+Ctrl+Shift+R** | Record the whole screen with sound. |
| **Super+Shift+C** | Pick a colour from anywhere on screen (copies its code). |
| **Super+Ctrl+E** | Emoji 🙂 |
| **Super+V** | Clipboard history — everything you copied recently |

Screenshots go to *Pictures/Screenshots*, recordings to *Videos/Recordings*.

### Quick switches
Prime menu → **Quick switches**, or right-click the small icons that appear on the bar:
- **Night light** (Super+Ctrl+N) — warmer colours in the evening.
- **Do not disturb** (Super+Shift+K) — notifications wait silently.
- **Keep awake** (Super+Ctrl+I) — the screen won't dim or lock (watching, presenting).
- **Power mode** — battery saver, balanced or performance.

### Laptops
The battery shows on the bar (desktops don't show it). Click it for the power
mode. Prime warns you at 15% and at 5%. Closing the lid locks and sleeps the computer.

### More than one keyboard language
Prime menu → Settings → **Keyboard layout** → choose languages to add.
**Super+Ctrl+Space** switches; the bar shows which one is active.

### Printers
Prime menu → Settings → **Printers** → *Add*. Most Wi-Fi printers are found on
their own.

### Phones and USB sticks
Plug them in — they appear in the Files app (Super+E). For an Android phone,
choose *File transfer* on the phone.

### Look
**Super+Shift+W** (or the palette icon on the bar): wallpaper and accent colour.

## 5. Keeping it healthy

- **Updates**: when a number appears next to the update icon on the bar, click it.
  It updates everything — system, apps and Prime — and takes a snapshot first.
- **If an update breaks something**: restart and, in the boot menu, choose the
  snapshot entry from before the update. Your desktop settings can also be put
  back separately: Prime menu → Style & repair → **Restore desktop settings**.
- **Lost or overwrote a file?** Prime menu → Style & repair → **Get a file back**: pick a moment (an hour, a day, a week ago) and your home folder opens as it was then — copy the file back. Prime keeps these automatically on CachyOS's standard disk layout.
- **If the desktop misbehaves**: **Super+H** checks it and fixes what it can.
  **Super+W** restarts the bar.
- **Lock** with Super+L. **Power off / restart** with the ⏻ icon on the bar.

## 6. Making it yours (optional)

Your own settings live in files that updates never overwrite:

| File | For |
|---|---|
| `~/.config/hypr/hyprland.conf` | your own shortcuts and window settings (the bottom part is yours) |
| `~/.config/waybar/user.css` | bar colours and sizes |
| `~/.config/kitty/kitty.conf` | the terminal |

Prime menu → Settings → **Edit window & keyboard settings** opens the first one.

## 7. Removing Prime

Open a terminal (Super+Enter) and type `prime-uninstall`. (In another desktop's
terminal, such as KDE's Konsole, type `~/.local/share/prime-linux/layer/bin/prime-uninstall`.)
Your old settings, theme and
services come back; Prime's settings are kept in `~/.config-backups` in case you
return. `prime-uninstall --packages` also removes the programs Prime added.
On the login screen, choose your previous desktop again.

## Help

- Super+/ — every shortcut.
- Prime menu → About → **This computer** — details to share when asking for help.
- The install log: `~/.local/state/prime/logs/`.

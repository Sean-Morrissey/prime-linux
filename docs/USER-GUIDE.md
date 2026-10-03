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
   - **Encryption** (on the disk step, tick **Encrypt system**): strongly
     recommended for a laptop. Without your password, a lost or stolen laptop
     gives nobody your files. You type the password when the computer starts.
     Choose one you won't forget: without it nobody, not even you, can read the
     disk. It can only be chosen now, while installing.
   - Create your user and password. Remember the password: Prime asks for it once.
5. Restart, take the USB stick out, and log in.

## 2. Add Prime Linux

First open a **terminal**: press the Windows/Super key, type `terminal`, press
Enter (in KDE it's called *Konsole*). Every grey box below is one thing to copy:
select it, copy it, paste it into the terminal with **Ctrl+Shift+V** (or
right-click → Paste) and press **Enter**. When the terminal asks for your
password, type it and press Enter. Nothing appears while you type: that's normal.

Paste this one line:

```
curl -fsSL https://raw.githubusercontent.com/sean-morrissey/prime-linux/main/boot.sh | bash
```

If it stops half-way, paste the same line again: it carries on from where it stopped.

### While it installs

Watch the numbered steps `[1/8] … [8/8]`. It takes 5–15 minutes, mostly
downloading. When it says **Prime Linux is installed**, you're done.

If something goes wrong, the message says what to do (usually "connect to the
internet and run it again"). A full log is kept in `~/.local/state/prime/logs/`.

Want to see what it will do first? Add `--dry-run`:
`curl -fsSL …/boot.sh | bash -s -- --dry-run`. It shows every step and changes nothing.

**Already had your own Hyprland setup?** At the end the installer offers to bring
your shortcuts, screens, bar items and background services along as your own
add-on — everything is saved first and `prime-import --undo` reverses it. Details:
[MIGRATING.md](MIGRATING.md).

## 3. First login

1. Log out (or restart).
2. On the login screen, open the **session** menu (KDE/SDDM: bottom-left;
   GNOME: the gear icon) and choose **Prime**. It's remembered next time.
3. Log in. You'll see the top bar and your wallpaper. The dock — your apps and everything
   that's open — waits at the bottom: move the pointer to the bottom edge to show it.
   Open a terminal (Super+Enter) and Prime greets you: **P.R.I.M.E — Please
   Relax I'll Manage Everything**.

Three keys to remember — *Super* is the Windows key:

| Press | You get |
|---|---|
| **Super + Space** | Search: apps, files, sums (type `12*7`), the web |
| **Super + I** | Settings: Wi-Fi, sound, display, mouse, gaming, updates, everything |
| **Super + /** | Every keyboard shortcut, searchable |

Everything in this guide is also in Settings or Prime Search, so you never *need* a terminal.

## 4. Everyday things

### Apps
- **Open an app**: click the **P** logo (or Super+X) for the Start menu — pinned apps, All apps, recent files. Or Super+Space, type its name, Enter. Right-click an app in Start to pin or unpin it.
- **Install an app**: Settings → Apps → **App Store**. Click Install.
- **A website as an app** (WhatsApp, YouTube, Gmail…): Settings → Apps
  → **Make a website into an app**. It gets its own window and icon.
- **Close a window**: Super+Q, or the ✕ button at the right of the window's title bar.
- **The dock**: move the pointer to the bottom edge of the screen. Click an app to open or
  switch to it; right-click to pin or unpin it; the grid button opens Start.

### Settings
- **Super+I** (or Start → **Settings**) opens one window for everything about the computer, like Settings on Windows or a Mac: Wi-Fi, Bluetooth, sound, displays, appearance, notifications, power and battery, mouse and touchpad, keyboard, processor, graphics, storage, gaming, the AI assistant, apps, updates, privacy and security, date and time, language, your account and password, accessibility, and About & Help — plus **Dock** (hide or always show, size, which edge), **Top Bar**
  (12/24-hour clock, seconds, date, which items show), **Windows & Workspaces**,
  **Lock & Sleep** (when the screen locks, turns off and the computer sleeps),
  **Startup Apps** and **Troubleshooting** (one-click fixes for sound, Wi-Fi, the bar,
  the dock, notifications and title bars). Type in the search box to find a setting.
- **Just say it**: Super+Space, then type what you want — "wifi off", "louder", "mute", "do not disturb", "bigger text", "accent blue", "mouse settings", "take a screenshot", "something's wrong", "get a file back" — and press Enter. Prime does it straight away; no AI needed.
- Mouse, keyboard, look, dock, bar and the other saved settings can be undone: Troubleshooting → **Undo the last change made in Settings**.

### Windows and workspaces
- Windows snap into place and never cover the bar or the dock. One window fills the
  screen; the first window stays on the left half and new ones share the right half.
- **Super+←** snaps a window to the left half (it becomes the main window), **Super+→**
  to the right half, **Super+↑ / Super+↓** move it up or down within the right half.
  Dragging a window by its title bar and dropping it on a half does the same.
- **Super+Shift+arrows** move between windows; **Alt+Tab** cycles through them.
- **Super+F** puts a window full screen and the same keys bring it back;
  **Super+Shift+F** maximises it but keeps the bar.
- Prefer windows that float freely? Settings → Appearance → **Window layout →
  Free** (or type "floating windows" in Super+Space): they open at a sensible size in the
  middle and snap to edges when you drag them. **Super+Shift+V** flips one window either way.
- **Workspaces** are separate desktops: five of them, numbered on the top bar. Click a
  number (or press **Super+1 … Super+9**) to go there, on the screen you're using.
  Apps stay on the workspace they were opened on — even if you switch away while one
  is still loading — and nothing moves you to another workspace except you. An app
  that wants attention lights up its number instead. **Super+Shift+1…9** sends the
  current window to another workspace. Settings → **Windows & Workspaces** changes
  how many there are and what Super+arrows do.
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

More in Settings:
- **Wi-Fi & Network**: forget a saved network, join a hidden one, add your school's
  or work's **VPN** from the file they give you (then switch it on and off there),
  and share this computer's internet as a **hotspot** (the password is shown).
- **Sound**: send each app to its own speakers or headphones, and choose how each
  sound device is used (the screen's speakers over HDMI, a headset's call mode…).
- **Printers**: *Look for printers* finds the ones on your Wi-Fi and adds one with a
  click; make one the default, print a test page, and cancel what's printing.

### Timetable and reminders
- Open **Timetable** (Start menu, or Settings → Date & Time): add your classes for the
  week — name, day, times, room. Prime sends a note 10 minutes before each one (or
  5, 15, 30, or off).
- Reminders: add them there, or just type in Prime Search (Super+Space):
  *remind me to hand in the essay at 3pm*, *remind me in 20 minutes to take the pizza
  out*, *remind me tomorrow at 9 to bring my PE kit*. No AI needed. If the computer
  was asleep, the reminder comes as soon as it wakes.

### Camera and microphone
Settings → **Camera & Microphone**: see your cameras and whether an app is using one
right now, test the camera, and record five seconds from the microphone to hear how
you sound — handy before a call or an online lesson.

### Screenshots and recordings
| Press | |
|---|---|
| **Print** (or Super+Shift+S) | Screenshot a region — draw a box. It's saved and copied at once; the notification then offers **Edit · Ask Prime · Show in folder · Delete** (ignore it and it goes away). |
| **Super+Alt+A** (AI pack) | Screenshot a region and ask Prime about it, in one step. |
| **Super+Shift+R** | Record a region of the screen. Press again (or click the red ● on the bar) to stop. |
| **Super+Ctrl+Shift+R** | Record the whole screen with sound. |
| **Super+Shift+C** | Pick a colour from anywhere on screen (copies its code). |
| **Super+Ctrl+E** | Emoji 🙂 |
| **Super+V** | Clipboard history — everything you copied recently |

Screenshots go to *Pictures/Screenshots*, recordings to *Videos/Recordings*.
Settings → Displays → **Screenshots** chooses what happens after one: show the
buttons, just save and copy, or always ask Prime.

### Quick switches
The bar's switches icon, or right-click the small icons that appear on the bar:
- **Night light** (Super+Ctrl+N) — warmer colours in the evening.
- **Do not disturb** (Super+Shift+K) — notifications wait silently.
- **Keep awake** (Super+Ctrl+I) — the screen won't dim or lock (watching, presenting).
- **Power mode** — battery saver, balanced or performance.

### Laptops
The battery shows on the bar (desktops don't show it). Click it for the power
mode. Prime warns you at 15% and at 5%. Closing the lid locks and sleeps the computer.

### More than one keyboard language
Settings → **Keyboard** → Add or remove layouts → choose languages to add.
**Super+Ctrl+Space** switches; the bar shows which one is active.

### Printers
Settings → **Printers** → *Add or change a printer*. Most Wi-Fi printers are found on
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
  back separately: Settings → Troubleshooting → **Restore desktop settings**.
- **Lost or overwrote a file?** Settings → Storage → **Get a file back**: pick a moment (an hour, a day, a week ago) and your home folder opens as it was then — copy the file back. Prime keeps these automatically on CachyOS's standard disk layout.
- **If the desktop misbehaves**: **Super+H** checks it and fixes what it can. Prime also checks by itself — at every login and once a day while you stay logged in — repairs what it safely can, and only tells you about something new: a disk getting full, a background service that stopped, or a desktop part that was updated (Undo an update goes back if it looks wrong).
  **Super+W** restarts the bar.
- **Lock** with Super+L. **Power off / restart** with the ⏻ icon on the bar.

## 6. Making it yours (optional)

Your own settings live in files that updates never overwrite:

| File | For |
|---|---|
| `~/.config/hypr/hyprland.conf` | your own shortcuts and window settings (the bottom part is yours) |
| `~/.config/waybar/user.css` | bar colours and sizes |
| `~/.config/kitty/kitty.conf` | the terminal |

Settings → Appearance → **Edit the window & keyboard settings file** opens the first one.

## 7. Removing Prime

Settings → **Troubleshooting** → **Remove Prime from this computer**. It asks first, and
lets you keep or remove the apps Prime installed. Your old settings, theme and services
come back; your files are never touched, and Prime's settings are kept in
`~/.config-backups` in case you return. Then log out and choose your previous desktop on
the login screen.

## Help

- Super+/ — every shortcut.
- Settings → **About & Help** — details to share when asking for help.
- The install log: `~/.local/state/prime/logs/`.

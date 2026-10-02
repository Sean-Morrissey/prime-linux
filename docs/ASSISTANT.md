# Prime, the assistant — user guide and security model

Prime Linux's promise is *"Prime sets it up and customises it for you — just tell it
what you want."* This page explains how that works for the person using it, and
exactly what Prime can and cannot do.

## For the person using it

### First login: Welcome

The first time you log in, a window called **Welcome to Prime Linux** opens. It
takes about two minutes and every step has **Skip**:

1. **Hello** — what should Prime call you, and the three keys worth knowing:
   **Super+Space** finds anything, **Super+I** opens Settings,
   **Super+/** lists every shortcut (Super is the Windows-logo key). A **Larger
   text** switch is right there.
2. **Pick a look** — accent colours and wallpapers. The preview *and your real
   desktop* change as you click.
3. **What will you use this computer for?** — Gaming, Coding, Creating (video,
   3D, art), Studying, Just everyday stuff. Pick any. Prime switches on the
   matching packs; packs that install apps open a window that asks for your
   password once.
4. **Updates** — Automatic (recommended), Ask me first, or Off.
5. **AI assistant (optional)** — a model on this computer (llama-server,
   Ollama), one on another computer at home, OpenRouter, OpenAI, or anything that
   speaks the OpenAI API. "Find models" lists what's available. Your key is
   stored only on this computer, readable only by you.
6. **How much may Prime do on its own?** — a slider: *Ask me first* · *Handle the
   small stuff* · *Just do it*.
7. **Done** — what was set up, plus tips.

Closing the window early is fine. Run it again any time: Settings → Users & Accounts → **Set up my
computer again** (or `prime-welcome`).

### Asking Prime

**Super+Shift+Space** (or the **Ask** button on the bar, Spotlight, or right-click
→ *Ask Prime about this*). Ask questions — "what does the bar's CPU number
mean?" — or ask for changes:

- "make the accent green" · "use the dune wallpaper" · "make the windows less round"
- "turn off animations" · "scroll like on my phone" · "switch my keyboard to German"
- "turn on night light" · "add a shortcut: Super+Shift+O opens Firefox"
- "make Firefox my default browser" · "turn on the gaming pack"
- "check my computer" · "update everything" · "update automatically every night"
- "save my desktop settings" · "undo that"

When Prime needs your OK, it asks in the answer window:

```
Prime wants to: switch the accent colour to green (#34d399).
Allow? [y/N]
```

Nothing happens unless you type **y**. Prime then says what it did in one line.

**Undo** — say "undo that", or Settings → About & Help → *Undo the last change made here*,
or `prime-settings undo`. Repeat to step further back.
**What did Prime change?** — Settings → AI Assistant → *What Prime changed*, or `prime-settings log`.

### Prime Tutor (students)

Settings → AI Assistant → **Prime Tutor — learn step by step** (also in the app
list). The tutor finds out what you know, goes one step at a time, gives a worked
example on a similar problem, asks you to try, and explains mistakes. For graded
work it helps you plan and improve *your* work rather than writing it for you. It
keeps its own conversation and cannot change any settings.

## Security model

### No shell, a fixed toolbox

The model never gets a shell, a file-write tool or a way to run commands. It can
call only the tools in `layer/default/prime-tools.json`, executed by
`layer/bin/prime-settings`. Every argument is validated against a closed set
(colour names / 6-digit hex, wallpaper names found in the wallpaper folders,
xkb layout codes from the system list, key combos from a whitelist, app targets
resolved to installed `.desktop` files, Prime/window actions from fixed maps).
Unknown tools and extra arguments are rejected and logged.

| Tool | Does | Capability | Default (*Ask me first*) |
|---|---|---|---|
| get_status, list_wallpapers, list_shortcuts, list_apps, list_packs, list_backups, show_shortcuts | look only | system.read | may look |
| set_accent, set_wallpaper, set_look, change_setting | look and common settings | settings.user | asks |
| add_shortcut, remove_shortcut | keyboard shortcuts (Prime block) | settings.user | asks |
| set_default_app | browser / file manager / text editor | settings.user | asks |
| enable_pack | pack with no packages / with packages | settings.user / **system.packages** | asks |
| disable_pack, run_doctor, save_desktop, undo_last | | settings.user | asks |
| start_update, set_update_policy | | **system.update** | asks |
| restore_desktop | put old desktop settings back | **destructive.restore** (pinned) | **always asks** |

The slider writes `~/.config/prime/capabilities.yaml` from
`templates/capability-ladder.yaml`:

| Slider | settings.user etc. | system.packages / system.update | destructive.* / secrets.* |
|---|---|---|---|
| Ask me first (`suggest`) | asks | asks | asks |
| Handle the small stuff (`auto-user`) | does it, notifies | asks | asks |
| Just do it (`auto-all`) | does it, notifies | does it, notifies | **asks** |

Levels: `observe` (may look, may not change), `suggest` / `approve-each` (asks
every time), `auto` (does it, then a notification says what changed and how to
undo it).

### Rules enforced in code, not in the prompt

- **Pinned groups.** `destructive.*` and `secrets.*` are treated as approve-each
  even if someone edits the file to say `auto`.
- **Prime can't raise its own level.** No tool writes `capabilities.yaml`.
  `prime-settings autonomy` refuses when called by the assistant
  (`PRIME_ACTOR=ai`), and an assistant call can't claim `--actor user`.
  Restoring saved desktop settings never brings back an old permission file,
  audit log or AI key.
- **Content never grants permission.** When the question carries content Prime
  didn't write — a screenshot (`--image`), anything passed with
  `prime-ask --from WHAT`, or results of tools that return file/app names — every
  change in that conversation asks first, at every level, and the confirmation
  says where the request came from. The mark stays on the conversation until
  you start a new one.
- **Confirmation text comes from the toolbox, not the model.** The sentence you
  approve is generated from the validated arguments, so a model can't describe
  one thing and do another.
- **No one to ask means no.** If there's no terminal or desktop session to ask
  in, the answer is "declined".

### Audit and undo

Every attempted call — done, declined, denied, invalid or failed — is appended to
`~/.config/prime/audit.jsonl` (mode 600): time, who (Prime or you), tool,
arguments, capability, level, decision, plain-language summary, result, the
backup taken and how to undo it.

Before any change Prime saves a copy of the desktop settings
(`prime-desktop-backup save prime-<tool>`, in `~/.config-backups/desktop/`). A
burst of changes within five minutes shares one copy, so they don't push older
copies (e.g. the ones taken before updates) out of the 20-copy rotation.
Each change also records an exact inverse (previous accent, wallpaper, settings
state, default app, update policy; disable for enable). `undo_last` replays the
newest not-yet-undone inverse; restoring a saved copy is the fallback.

### Settings Prime writes

Shortcuts and the common settings go in one clearly marked block at the end of
`~/.config/hypr/hyprland.conf`:

```
# >>> Prime settings >>>
...
# <<< Prime settings <<<
```

Prime only ever rewrites what's between the markers (from
`~/.config/prime/settings.json`). Before swapping the file in, the whole config
is checked with `Hyprland --verify-config`; if the change adds an error, nothing
is written. Your own lines below the block win over it. Theme changes go through
`prime-theme`, packs through `prime-addon`, updates through `prime-update` and the
update-policy command.

### Models, local or remote

`prime-ask` speaks the OpenAI chat API (streaming). With models that support tool
calling (OpenAI, OpenRouter, llama-server `--jinja`, Ollama tool models) it uses
native function calls. If the server rejects tools, Prime switches to a strict
JSON action format (one ```` ```prime-action ```` block per reply), remembers that
for the model, and hides the raw block from you. Force it in `ai.conf` with
`TOOLS=json`, or `TOOLS=off` for answers only. The API key lives in
`~/.config/prime/ai.key` (600) and is sent only as the `Authorization` header to
the endpoint you chose. `identity.yaml` (name, what you use the computer for,
your "about me") is added to the system prompt as a description of you, never as
permission.

## Files

| File | What |
|---|---|
| `layer/default/prime-tools.json` | the tool schema (names, capabilities, JSON-schema arguments) |
| `layer/bin/prime-settings` | the toolbox executor: validate → permission → confirm → backup → apply → audit; `undo`, `log`, `autonomy`, `list` |
| `layer/bin/prime-welcome` | first-run GUI (GTK 4 / libadwaita); `--first-run`, `--apply FILE`, `--screenshots DIR` |
| `layer/addons/ai/bin/prime-ask` | the chat client: streaming, tool loop, JSON fallback, `--tutor`, `--from` |
| `layer/addons/ai/bin/prime-ai-setup` | connect a model (interactive, or `--url --model --key-stdin`) |
| `layer/addons/ai/personas/{prime,tutor}.md` | the two system prompts |
| `layer/addons/ai/tests/` | mock OpenAI server + `run.sh` (51 checks, throwaway HOME) |
| `~/.config/prime/capabilities.yaml` · `audit.jsonl` · `settings.json` · `identity.yaml` · `welcome-done` | per-user state |

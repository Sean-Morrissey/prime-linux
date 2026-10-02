# Context actions — right-click means "Ask Prime"

**Status:** implemented and shipped — `layer/bin/prime-context`, registered for
every bar item and right-click surface in `layer/default/elements.json` (and
`layer/addons/ai/elements.json` for the AI add-on), installed by `install.sh` and
covered by `tests/check-install.sh`'s right-click checks. This document is the
contract Prime Linux ships, not a description of something planned.

## The principle

Every visible element on the desktop answers a right-click with the same three
questions, in the same order, everywhere:

1. **What is this?** — Prime explains the element in plain language.
2. **What is it showing right now?** — the element's live value is read and put
   into the question, so the answer is about what is actually on screen, not a
   generic explanation of the widget.
3. **What can I do with it?** — the element's own actions, listed after the
   generic ones.

No element is allowed to be a dead click. An element with no entry in the
registry still gets the generic menu (see *Fallback* below).

## The contract

Two files, both declarative. **Nothing about this is waybar-specific** — the
registry describes *elements*, and any surface (bar, dock, notification, window
chrome, a future shell) can call the same engine.

| Piece | Ships as | Job |
|---|---|---|
| Element registry | `/usr/share/prime/elements.json` | what each element is, how to read its state, the question to ask, its own actions |
| Engine | `/usr/bin/prime-context` | builds the menu, resolves `{state}`, submits to Prime, runs actions |
| Menu theme | `/usr/share/prime/theme/menu.rasi` | the menu's look, matching the shell |

### Registry schema

```jsonc
{
  "version": 1,
  "generic_items": [                     // same menu everywhere, in this order
    { "id": "ask",         "kind": "ask" },
    { "id": "ask_area",    "kind": "ask_area" },
    { "id": "ask_explain", "kind": "ask_explain" },
    { "id": "ask_custom",  "kind": "ask_custom" },
    { "id": "copy",        "kind": "copy" },
    { "id": "last",        "kind": "last" }
  ],

  "fallback": {                          // unknown element: never a dead click
    "label": "Bar element",
    "ask": "<generic question>"
  },

  "elements": {
    "<surface>.<element>": {
      "label":  "CPU",                   // human name, used in every prompt
      "state":  "shell command",         // stdout = the element's live value
      "ask":    "question with {state}", // what "Ask Prime about this" sends
      "items":  [ { "label": "…", "cmd": "…" } ]   // element-specific actions
    }
  }
}
```

Rules the engine guarantees, and therefore what Prime Linux may rely on:

- **`{state}` is always substituted** before the question is sent. The state
  command runs with a hard timeout (6 s), its output is folded to one line and
  clipped, and it is cached for a few seconds so opening the menu stays snappy.
- **The kind is the contract, the command is the detail.** `kind` decides the
  behaviour (`ask`, `ask_area`, `ask_explain`, `ask_custom`, `copy`, `last`); an
  element's `items` only ever add commands. A surface therefore cannot
  accidentally break the "Ask Prime" guarantee by supplying bad items.
- **`ask_area` captures what you actually right-clicked.** The pointer position
  is read at click time; the bar strip, the dock column, or a region around the
  pointer is captured and attached to the question as an image. This is what
  makes "Ask Prime" work on pixels, not just on numbers the shell already knows.
- **Actions are detached.** Selecting an item never blocks the menu or the
  surface behind it.
- **Every ask is logged** (element, question, timestamp) so the OS can later
  answer "what has the user been asking about?".
- **Non-interactive modes exist for testing** — `--list` prints the menu,
  `--run <id> [--dry]` executes a single item. Prime Linux's test suite uses
  these; they are the reason the contract is testable without a pointer.

## Why this shape for Prime Linux

- **Portable, not hardcoded.** A shell rewrite (GTK, Quickshell, whatever) keeps
  the whole contract by reading the same registry. The engine is a shell script
  precisely so it stays language-agnostic and easy to extend.
- **Local-first and auditable.** State commands are ordinary shell; the user can
  read exactly what leaves the machine and what question gets asked.
- **Explainability is a first-class feature, not a chat window.** A new user can
  right-click anything unfamiliar and get an answer in context — this is the
  "teach me my own OS" affordance the interview/onboarding flow leans on.
- **The registry is documentation.** Each entry says what an element is; that is
  the same text onboarding, screenshots and error dialogs can reuse.

## Acceptance criteria (what "shipped" means)

1. Right-click on every element of the top bar and the dock opens a menu whose
   first row is an Ask Prime action.
2. `prime-context <element> --list` returns at least the six generic items, and
   the element's own items when the registry defines them.
3. `--run ask --dry` prints a question containing the element's **current** value
   (not a placeholder).
4. `--run ask_area` produces a capture whose dimensions match the surface the
   pointer was over.
5. With the registry removed, every element still yields the fallback menu.
6. Asking produces a visible answer: the shell must show that Prime is working
   and where the answer will appear.

## Open questions

- **Discoverability.** Right-click is currently the only door. A modifier-click
  on a touchpad-less workflow, or a "?" affordance, may be needed for new users.
- **Permission surface.** `ask_area` can capture the screen. Prime should make
  it obvious when a capture is attached and let the user see/delete it.
- **Registry override.** Users will want to add their own elements; decide the
  precedence between `/usr/share/prime` (shipped) and `~/.config/prime` (user).
  The live desktop currently resolves the user file first.

# How Prime updates the machine

Written for the person using the computer, not for the person who built it. The
short version: **you never update this thing.** It updates itself every three days,
at a moment that costs you nothing, and if the new version is broken it puts itself
back before you ever see it.

## What actually happens, every three days

1. **It checks.** Around every third day — and 15 minutes after any boot where the
   timer came due while the machine was off, so a laptop that lives in a bag still
   gets updated — Prime looks for a new system image.
2. **It downloads the new version while you keep working.** Nothing about the
   running system changes at this point. On an image-based system the update is a
   whole new version sitting next to the old one; the one you are using is untouched.
3. **It checks its own work.** Storage, services, network, screen, session, sound —
   run against the new version. If something is already wrong, it stops there and
   tells you, and nothing about your machine has changed.
4. **It finds a moment that costs nobody anything.** Then it restarts, once, and
   only if all of this is true:
   - you have not touched the machine for 10 minutes (30 minutes at night), and
   - nothing long-running is in progress — a build, a render, a download, a 3D print
     (the list is `/etc/prime/busy.conf`, and you can add to it), and
   - the machine is plugged in, if it has a battery.
5. **It restarts and checks itself again.** The first boot into the new version is
   watched: failed services, no screen, no audio, no desktop session, no network.
   Healthy → done, quietly. It will say one line so you know why the machine
   restarted.

That is the entire product. You use the computer; it stays current.

## What it will never do

- **Never restart while you are working.** Ten minutes of no input is the bar during
  the day. It does not count a locked screen as "working" — if you locked it and
  walked away, that is exactly the right moment.
- **Never restart during a job worth keeping.** Prints, builds, encodes, container
  builds, downloads, another package manager. A 3D print in progress is an absolute
  no: interrupting a print wastes filament and hours.
- **Never restart on battery.**
- **Never argue.** The restart comes with one notification and a "Later" button. One
  click means twelve hours of silence, and it will not ask again in that window.
- **Never take your files with it.** Updates replace the system, never your home
  directory. Documents, coursework, projects: not part of what is being replaced.
- **Never guess about the model's permissions.** This is scripts, not an LLM. Every
  decision here is deterministic and works offline, which is why it can be trusted at
  4am. The AI layer can *ask* for an update; it does not get to improvise one.

## If the new version is broken

The previous version is still on disk. That is the point of building this way — the
undo button is a property of the system, not a promise from the agent.

- Prime restarts into the new version, finds it unhealthy, and goes back to the
  version that worked, by itself.
- Your files are not touched by this, because your files were never part of the
  update in the first place.
- The next time you use the machine it tells you, in one line, what happened.
- **It does not loop.** If the same update breaks the machine twice, Prime stops
  offering that update and waits for a newer one. An endless
  update-restart-rollback cycle is worse than being out of date.

## The knobs, for anyone who wants them

| What | Where | Default |
|---|---|---|
| How often it checks | `systemctl edit prime-update.timer` (`OnUnitActiveSec`) | every 3 days |
| Turn it off entirely | `sudo touch /etc/prime/updates-disabled` | on |
| How long you must be idle | `PRIME_IDLE_MINUTES` in the service | 10 minutes |
| Night window | `PRIME_NIGHT_IDLE_MINUTES`, hours 22:00–07:00 | 30 minutes, no countdown |
| "Later" duration | `PRIME_DEFER_HOURS` | 12 hours |
| Give up after N bad boots | `PRIME_FAIL_LIMIT` | 2 |
| Jobs that block a restart | `/etc/prime/busy.conf` | builds, media, packages, containers, slicers, printers |
| Never act on its own | set autonomy to `suggest` | `auto-user` on the shipped image |

Plain-language commands, no root needed for the read-only ones:

```
prime-autoupdate status        # where the cycle is up to, and whether a restart is pending
prime-autoupdate later 24      # not now, for a day
prime-autoupdate now           # do the whole cycle immediately
prime-autoupdate post-boot     # what runs at every boot (verifies, recovers if needed)
prime audit                    # every action Prime has ever taken on this machine
```

## Autonomy: what it is allowed to decide alone

The capability ladder (`templates/capability-ladder.yaml`) sets this, and the update
cycle is the clearest example of it:

| Level | What the cycle may do |
|---|---|
| `suggest` | Tell you updates exist. Install nothing. |
| `auto-user` *(shipped default)* | Install and restart at a safe moment; recover from a broken boot. |
| `auto-all` | Same, plus it may undo a failed update without waiting for you. |
| destructive verbs | Always approve-each, at every level — see the ladder. |

The one deliberate exception: **recovering from a broken boot happens at every level.**
A machine that cannot boot cannot ask permission, and going back to the version that
worked is recovery, not destruction — the user's files are not in scope, and the
previous version is still on disk. It is logged, and it is reported on screen the next
time someone can see the screen.

## Why this is the honest hard part

Every Linux distribution promises updates. The failure mode is always the same: the
update lands, the machine misbehaves, and the user — who does not know what a
package manager is — is left holding a computer that used to work. That is why most
people stay where they are, and it is the actual reason a beginner bounces off Linux.

So the product is not "updates, but automatic". It is: **the update includes its own
verification and its own undo, and it only happens at a moment when it cannot cost
you anything.** That is a small enough idea to fit in one script, and it is the thing
that makes the rest of the machine safe for someone who is not a sysadmin.

## What is proven, and what is not

- **Proven:** the whole decision policy — when to install, when to restart, when to
  keep quiet, when to give up — tested end to end in a sandbox with no root and no
  real machine, 29 checks across 9 scenarios, including a broken boot and the loop
  guard. `backends/arch/test-autoupdate.sh`.
- **Not yet proven in the wild:** the thin adapter that talks to `bootc` on the
  shipped image. It is small and boring on purpose, and it needs a shipped image booted
  in a VM to be tested honestly.

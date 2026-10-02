# Prime Linux — the pitch, stated for attack

Two paragraphs: the idea as its author states it, and the designer's interpretation
of what that commits us to. Both are written to be red-teamed — the useful critique
is the one that finds the load-bearing assumption.

**Note (2026-10-02):** the designer's interpretation below describes the original
mechanism — an atomic Fedora image. The idea it defends ("bounded failure, a
permission ladder, a layer that's never baked with one person's data") shipped
instead as a layer on top of CachyOS (`install.sh`, `docs/PRIME-LAYER.md`), using
btrfs snapshots for the undo path instead of a whole new image. The load-bearing
assumptions below are still the ones to attack; only "custom image... read-only
root" is no longer the actual mechanism.

---

## The idea (as Sean puts it)

Prime Linux is a Linux distribution where an AI agent called Prime is not an app you
launch but the supervisor of the operating system itself: when you first install it,
you tell Prime about yourself — who you are, what you're studying, what projects you
run, how you like your machine — and Prime sets the install up for you instead of
making you fill out forms and pick packages. After that it stays always on, like
Siri but with actual hands on the machine: it updates the system, watches over it,
does your chores and your coursework setup, and you can also just type into a
terminal yourself whenever you want. It's built for students and for people who know
nothing about Linux, so it has to be something you can hand to a friend and have
them get the same experience as me without either of us becoming a sysadmin.

## The designer's interpretation (what that commits us to)

Concretely, that means a custom image built on an atomic (immutable) Fedora base,
because the only way "hand it to someone who can't fix it" survives contact with
reality is if failure is bounded: the system's root is read-only, an update is a
whole new image, and the previous image stays bootable, so the worst case is a
reboot rather than a reinstall. The distribution ships capability only — the agent
runtime, the voice stack, the student tooling, the self-repair scripts — while
everything personal is created on the machine, at first boot, by a conversation:
Prime interviews the user, then writes their dotfiles, their term and course
scaffolding, their reminders, their app set, and a memory seed that becomes the
"who I am and what I'm working on" file it carries forward. That forces three
commitments that are the real substance of the idea: (1) the agent runs with
elevated reach on someone else's machine, so it needs a permission ladder, an audit
log, a spend cap and an undo path rather than blind trust; (2) its power at the
system level is necessarily asynchronous — apps come from flatpaks and containers
instantly, but a real system package change means rebuilding an image and rebooting,
with the old one still available as the undo — so "supervisor" honestly means
updates, health, rollback and setup, not an omnipotent root shell; and (3) the
personalization layer must be genuinely separate from the OS layer, because the
moment one person's configuration is baked into the image, the thing stops being a
product and becomes a backup of somebody's laptop.

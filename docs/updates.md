# Sakura Updates

## The problem being solved

Falling behind on a rolling release is more dangerous than updating often, and
this is badly understood. Two months of drift means a single enormous
transaction, months of unread manual-intervention notices, and known
vulnerabilities left open the whole time. The user who runs `pacman -Syu`
twice a year is taking the larger risk, not the smaller one.

So updates should be automatic. On Arch, that is normally a bad idea.

## Why unattended updates are normally unsafe here

- Arch ships manual interventions — keyring resets, directory merges, config
  format changes — announced in Arch News and nowhere else.
- A kernel upgrade removes the running kernel's modules. Until reboot, any
  hardware needing a module that is not already loaded fails: hotplugging a USB
  device or bringing up wifi stops working, on a machine nobody touched.
- A large transaction interrupted partway leaves a mixed system.

## Why SakuraOS can do it anyway

Two things the other Arch derivatives do not have:

**A snapshot before every transaction, and a recovery boot entry.** A bad
automatic update is one reboot from fixed, by someone who does not know what a
chroot is. This is what makes automatic updates defensible at all.

**Canary evidence.** A fleet of VMs takes each update set first and boot-tests
it. The updater applies only what canaries have already installed and booted
clean. This is the difference from Manjaro: Manjaro delays everything on a
schedule, which breaks AUR compatibility permanently. Sakura tracks Arch
directly and holds only what is demonstrably broken.

## Behaviour

Nightly in a configurable window, on mains power:

1. Refresh mirrors by speed and freshness (`reflector`).
2. Fetch the update set; classify each package.
3. Hold anything with an Arch News manual-intervention flag, or anything the
   canaries have not cleared. Surface it as "needs your attention" with the
   reason in plain language.
4. Snapshot, then apply the rest.
5. Detect whether a restart is needed — kernel, `systemd`, `glibc`, `dbus`, or
   replaced files still held open by running processes.
6. Never reboot on the user's behalf. Say a restart is needed and let them pick
   the moment.

## Its own page, not a section

Updates get a dedicated page with tabs, not three checkboxes on a shared
settings page. The reference point is Windows Update: people arriving from
Windows already know where updates live and what they expect to find there,
and meeting that expectation is worth more than inventing something.

**Status** — the landing tab. Whether the system is current, when it last
checked, what is waiting, and one button that does the obvious thing. If a
restart is needed it says so here, in those words.

**Available** — what is about to be installed, with the explanation below.
Each entry expandable. A "why is this held?" line for anything the canaries
have not cleared or that needs a manual step, with the actual reason.

**History** — every past update transaction, what it contained, whether it
needed a restart, and **Revert to before this update** on each row. This is
the surface that makes rollback discoverable; a boot menu entry nobody knows
about is not a safety net.

**Schedule** — the time picker, frequency, "only when plugged in", "only on
unmetered connections", and an explicit "pause updates until…" with a date.
Pausing is a real need and people will otherwise achieve it by disabling
updates permanently and forgetting.

**Advanced** — mirror selection and ranking, cache size and clearing, and the
tested-first toggle with a plain explanation of what it costs to switch off.

## Explaining what is being installed

The gap nobody fills: "libjxl 0.12.0-1" means nothing to a normal person, so
they either update blindly or not at all.

Every package gets its description plus its reverse dependencies, which turns
that line into:

> **libjxl** — JPEG XL image support
> Needed by: Dolphin, Gwenview, Firefox

Reverse dependencies come from `pactree -r`, descriptions from the package
database, and richer text from AppStream where a package has it. Cheap to
build, and it converts an update dialog from a wall of version numbers into
something a person can actually consent to.

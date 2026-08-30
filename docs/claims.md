# Claims, and whether they are true yet

SakuraOS is pre-alpha. The installer and the website describe the system we
are building, not the one that exists today, and that is deliberate: nothing
reaches a user until everything here is met. Writing the pitch first is how
the target stays fixed.

That only works if the gap is written down. An aspirational claim nobody is
tracking becomes a false claim the day it ships, and by then it is in
screenshots.

**Nothing ships to a user while anything below is unmet.** Not the ISO, not
the site.

| Claim | Where it is made | Status |
|---|---|---|
| Kernel tuned for scheduling and modern CPUs | Installer tour, site | **Done.** `linux-cachyos` 7.2.2 built for x86-64-v3 with ThinLTO, signed, and booted: an installed machine runs `7.2.2-1-cachyos` with sched_ext present. The installer picks it by asking glibc's loader what the CPU supports; a Nehalem guest gets stock `linux` instead, verified separately. Runtime tuning is `sakura-tuning` and works on either. See `docs/kernel.md`. |
| BTRFS with automatic snapshots | Installer tour, site | **Done.** `@ @home @log @pkg @snapshots`, snap-pac before every transaction. |
| Restore points, automatic and manual | Installer tour | **Done.** Manual ones from the Update Center; rollback verified end to end. |
| Updates applied in the background | Installer tour, site | **Done.** `sakura-updates.timer` for the system, `sakura-store-updates.timer` for applications. |
| Applications keep themselves current | Installer tour | **Done.** Flatpak, Snap and AppImage, on their own timers. |
| Terminal Assist | Installer tour, site | **Done.** ALPM hook plus a shell layer; the hook cannot be bypassed. |
| Store: Flatpak, Snap, AppImage, SakuraOS packages | Installer tour, site | **Done.** Searchable, installable, removable, matched across sources. |
| Store: the AUR | Installer tour | **Done.** Searchable, and installable after the build script has been shown. Acceptance is recorded by hash, so a script that changes under an unchanged version number is caught. Refuses on: never reviewed, changed since reviewed, or failed build. |
| Store: AppImages install by opening the file | Installer tour | **Done.** MIME type registered, confirmation before installing. |
| Store: bring your software to another machine | Installer tour | **Done.** App Sync, under the account menu at the foot of the store: writes the installed list to a file, and installs it on another machine after showing what it will do. Names only, no settings or data. No account and no server -- it is a file you carry. |
| Encryption is decided at install time | Installer, encryption screen | **Done.** The sentence now says what is true: attached header, decided on install day, changing it means reinstalling. Detached header rejected on durability -- see `docs/encryption.md`. |
| Private by default | Installer tour, site | **Done** as stated. Nothing here phones home. The only telemetry is KDE's, off unless switched on. |
| UI first, terminal second | Installer tour, site | **Done** in the sense claimed: install, update, roll back and manage software without a terminal. |

## Installing beside another system

Verified against a disk built to look like a machine with Windows on it: an
EFI system partition with a bootloader in it, a data partition with a file in
it, and unallocated space after them.

After installing in alongside mode:

- the data partition and its contents are untouched
- the bootloader in the shared ESP is byte-for-byte what it was
- SakuraOS is in the free space, as a new partition at the next free number
- the boot menu offers SakuraOS, SakuraOS Recovery and Windows Boot Manager,
  and every path it points at exists

Not yet verified: actually booting the alongside install, or booting the other
system from that menu. The configuration is right and every file it references
is present, but that is not the same as having watched it start.

## The boot watchdog, observed in the wild

Not a test this time. On 2026-08-25 the development VM was killed three times
in a row -- once by the host's OOM killer, twice by me stopping it mid-boot --
and on the next start it came up on its own:

    SakuraOS Recovery
    Started because this machine has not started properly 3 times.
    Something wrong with your system?
    Pick a point to go back to:
      1) 2026-08-25 23:25:33  sakura-settings-kcm
      ...
      c) Cancel and restart normally

Twenty-nine restore points, newest first, each named after the transaction
that created it. Nobody asked for it and nothing was configured to make it
happen; the counter reached its threshold and the recovery entry took over.

Two things this confirms that the tests did not:

- the threshold counts *interrupted* boots, not just failed unit starts. A
  machine switched off mid-boot three times is a machine somebody is fighting
  with, and that is exactly when this should appear.
- choosing "cancel and restart normally" clears the request. The next boot
  went straight to the desktop rather than back into recovery -- which is the
  bug we already fixed once, and it has stayed fixed.

Still not verified: an actual rollback chosen from this menu on an encrypted
disk. The menu appeared after the passphrase, which is the right order, but
nothing was restored from it.

## Before any public build

1. Everything above reads **Done**.
2. The site says the same things as the installer, and no more.
3. The VPS password shared during development is rotated, and the GitHub
   token is replaced with a fine-grained one.
4. Secure Boot signing has actually run, not merely been implemented.
5. A clean install passes, on hardware as well as in QEMU.

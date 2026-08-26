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
| Kernel tuned for scheduling and modern CPUs | Installer tour, site | **Not built.** `sakura-desktop` depends on stock `linux`. Needs a `linux-sakura` package: scheduler patches, a modern `-march` baseline, and benchmarks that justify the sentence. See `docs/kernel.md` -- CachyOS to be reviewed first, and dropping the claim is a live option. |
| BTRFS with automatic snapshots | Installer tour, site | **Done.** `@ @home @log @pkg @snapshots`, snap-pac before every transaction. |
| Restore points, automatic and manual | Installer tour | **Done.** Manual ones from the Update Center; rollback verified end to end. |
| Updates applied in the background | Installer tour, site | **Done.** `sakura-updates.timer` for the system, `sakura-store-updates.timer` for applications. |
| Applications keep themselves current | Installer tour | **Done.** Flatpak, Snap and AppImage, on their own timers. |
| Terminal Assist | Installer tour, site | **Done.** ALPM hook plus a shell layer; the hook cannot be bypassed. |
| Store: Flatpak, Snap, AppImage, SakuraOS packages | Installer tour, site | **Done.** Searchable, installable, removable, matched across sources. |
| Store: the AUR | Installer tour | **Partly.** Searchable. Installing is refused until the review step exists, on purpose. |
| Store: AppImages install by opening the file | Installer tour | **Done.** MIME type registered, confirmation before installing. |
| Store: bring your software to another machine | Installer tour | **Not built.** Needs an export/import format at minimum; an account and a server if it is to be automatic. |
| Encryption can be turned off without reinstalling | Installer, encryption screen | **Not true as built.** Measured: LUKS2 in-place decryption needs a detached header and data offset 0, decided at install time. Today's installer uses an attached header. Either change that -- and accept the header living on the unencrypted ESP -- or change the sentence. See docs/encryption.md. |
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

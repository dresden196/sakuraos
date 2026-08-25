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
| Kernel tuned for scheduling and modern CPUs | Installer tour, site | **Not built.** `sakura-desktop` depends on stock `linux`. Needs a `linux-sakura` package: scheduler patches, a modern `-march` baseline, and benchmarks that justify the sentence. |
| BTRFS with automatic snapshots | Installer tour, site | **Done.** `@ @home @log @pkg @snapshots`, snap-pac before every transaction. |
| Restore points, automatic and manual | Installer tour | **Done.** Manual ones from the Update Center; rollback verified end to end. |
| Updates applied in the background | Installer tour, site | **Done.** `sakura-updates.timer` for the system, `sakura-store-updates.timer` for applications. |
| Applications keep themselves current | Installer tour | **Done.** Flatpak, Snap and AppImage, on their own timers. |
| Terminal Assist | Installer tour, site | **Done.** ALPM hook plus a shell layer; the hook cannot be bypassed. |
| Store: Flatpak, Snap, AppImage, SakuraOS packages | Installer tour, site | **Done.** Searchable, installable, removable, matched across sources. |
| Store: the AUR | Installer tour | **Partly.** Searchable. Installing is refused until the review step exists, on purpose. |
| Store: AppImages install by opening the file | Installer tour | **Done.** MIME type registered, confirmation before installing. |
| Store: bring your software to another machine | Installer tour | **Not built.** Needs an export/import format at minimum; an account and a server if it is to be automatic. |
| Private by default | Installer tour, site | **Done** as stated. Nothing here phones home. The only telemetry is KDE's, off unless switched on. |
| UI first, terminal second | Installer tour, site | **Done** in the sense claimed: install, update, roll back and manage software without a terminal. |

## Before any public build

1. Everything above reads **Done**.
2. The site says the same things as the installer, and no more.
3. The VPS password shared during development is rotated, and the GitHub
   token is replaced with a fine-grained one.
4. Secure Boot signing has actually run, not merely been implemented.
5. A clean install passes, on hardware as well as in QEMU.

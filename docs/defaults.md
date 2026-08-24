# What a SakuraOS install comes with

The set is deliberately opinionated. A distribution that ships nothing makes
every new user assemble a desktop before they can use one, and a distribution
that ships everything makes them uninstall things they never asked for. The
rule here: cover what a person expects a computer to do out of the box, prefer
the KDE application where one exists so the desktop feels like one piece, and
leave the rest to the store.

Everything below is a dependency of `sakura-desktop`, so it is what `pacstrap`
lays down and what the ISO carries.

## Decided

| Need | Choice | Why this one |
|---|---|---|
| Files | Dolphin | The reference KDE file manager. See the window-size note below. |
| Terminal | Konsole | |
| Text editing | Kate | Ships KWrite in the same package, so both editors come free. |
| Documents | Okular | |
| Photos | Gwenview | KDE's own viewer, and good. Themed by `sakura-theme` rather than replaced. |
| Screenshots | Spectacle | |
| Calculator | KCalc | |
| Archives | Ark | |
| Disk usage | Filelight | |
| Simple painting | KolourPaint | |
| System monitor | plasma-systemmonitor | The Plasma 6 one, not the old ksysguard. |
| Phone integration | KDE Connect | |
| Webcam | Kamoso | |
| Calendar and mail | Merkuro | KDE's current PIM front end; KOrganizer is the older stack. |
| Video editing | Kdenlive | |
| Video playback | Haruna | See below. |

## Video playback: Haruna, which is mpv

The mpv-versus-VLC question has a third answer that resolves it. Haruna is a
KDE front end built on libmpv: the playback engine is mpv, and the interface
is Plasma-native rather than Qt-generic. So "we use mpv" and "it looks like it
belongs" are both true, without shipping a bare mpv that has no GUI to speak
of.

VLC's advantage is that it plays damaged and unusual files that other players
refuse, and it is what people already recognise. If that matters more than
desktop integration, it is a one-line change in `sakura-desktop`. **Open.**

## Printing and scanning

There was none of this at all — no CUPS, no drivers, no Plasma page — so a
printer could not be added by any route. Now:

- `cups`, `cups-filters` and `print-manager` (the Plasma page)
- `gutenprint`, `foomatic-db`, `foomatic-db-ppds` so a printer works without
  hunting down a PPD file
- `cups-pdf`, which gives a "print to PDF" target on a machine with no printer
- `sane` and `skanpage` for scanners

`cups.socket` is enabled rather than `cups.service`: socket activation means
the printing stack costs nothing until something actually prints.

## Bluetooth

`bluedevil` was already present, but it is only the Plasma front end. The
`bluez` daemon was missing, so Bluetooth did not work at all and the settings
page had nothing behind it. `bluez` and `bluez-utils` are in, and
`bluetooth.service` is enabled at install.

## Dolphin's window size

Dolphin opens as a small box on a fresh account. It has no saved geometry, so
it falls back to its own `sizeHint`, and there is no config key to preseed --
it only writes a size once the user has resized it, and it writes one per
screen resolution.

So `sakura-theme` ships `/etc/xdg/kwinrulesrc` with a KWin rule setting
Dolphin's initial size. Resolution-independent, applies to a new account
without the user having to fix it first. It is *Apply Initially*, not *Force*:
a better starting point, not a policy. Resize the window and it stays resized.

## Still open

**Sticky notes.** KDE does not currently ship one in Arch — there is no
`knotes` package, and no notes plasmoid in `kdeplasma-addons`. Candidates are
a Plasma widget from the store, or one of the GTK/Qt standalone apps. Nothing
is shipped for this yet.

**Password manager.** KWalletManager is what Plasma comes with and it is not
good. The idea of forking Bitwarden and shipping that instead is recorded but
not started; it is a much larger commitment than a package choice, because it
means maintaining a fork of a security product. A smaller first step would be
shipping the official Bitwarden client and leaving KWallet to do what it is
actually good at, which is holding Wi-Fi and SSH keys for the desktop.

**Video player**, as above.

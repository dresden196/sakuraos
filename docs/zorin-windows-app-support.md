# What Zorin's Windows app support actually is

Notes from reading the source, so nobody has to go looking for it twice.

## Where it lives

Not on GitHub. The ZorinOS organisation publishes `zorin-exec-guard` and
`zorin-exec-guard-app-db` and nothing else related to this.

Not on `packages.zorinos.com` either, which is worth saying because that is
where you would look: the host is up, serves `stable/`, `apps/`, `patches/`
and `drivers/` for five Ubuntu series, and every single index in it is zero
bytes. It is an aptly scaffold with nothing published into it. `premium/`
redirects to the shop.

It is on Launchpad, in `ppa:zorinos/stable`:

    https://api.launchpad.net/1.0/~zorinos/+archive/ubuntu/stable
        ?ws.op=getPublishedSources&source_name=zorin-windows-app-support

18 publications, back to 1.0 on bionic in 2018. Latest is **2.0.3**, noble,
October 2025. Native package, GPL-2+, signed by Artyom Zorin. `sourceFileUrls`
on a publication gives the `.dsc` and the tarball.

Thirty-eight PPAs are published under `~zorinos`; sweeping all of them for the
source name is how this was found, and is the way to find the next one.

## What is in it

300 KB, and **no program at all**. Wine icons at five sizes, three desktop
files, a menu definition, and packaging. The whole of the logic is:

- `Depends: winehq-stable | wine, zorin-windows-app-support-desktop-files`
- `Recommends: flatpak, wine-stable-amd64 | wine64, wine-stable-i386 | wine32`
- a `postinst` that runs two `flatpak` commands, with a five-attempt retry:
  add Flathub, install `com.usebottles.bottles//stable`

That is it. "Windows App Support" in Zorin is a metapackage that pulls Wine
from apt and Bottles from Flathub.

Two details worth keeping:

- The menu entry (`install-zorin-windows-app-support.desktop`) is
  `NoDisplay=true` and its Exec is `gnome-software --details=...`. It does not
  install anything itself; it opens the software centre at the metapackage.
  The install is the software centre's transaction, not a script of theirs.
- Bottles' desktop file claims `application/x-ms-dos-executable`,
  `application/x-msi`, `application/x-ms-shortcut` and
  `application/x-wine-extension-msp`. So on Zorin a double-clicked .exe goes
  to Bottles, with exec-guard in front of it.

## The changelog, which is the useful part

Seven years of walking back dependencies:

| | |
|---|---|
| 1.0 → 1.1 | plain `wine` → `winehq-stable` |
| 1.2 | support both, `winehq-stable \| wine` |
| 1.2.3 → 1.3 | PlayOnLinux and Winetricks promoted to Depends, then Winetricks dropped again |
| 1.4.1 | `python2` added as a direct dependency, for PlayOnLinux |
| 1.6.1 → 1.6.3 | Winetricks re-added as a Recommends, then removed |
| **2.0** | **Bottles installed alongside Wine** |
| 2.0.1 | Bottles launcher moved into the Wine menu |

The direction is clear: everything they tried to assemble by hand out of apt
packages — PlayOnLinux, Winetricks, python2, 32-bit runtimes — got dropped,
and in 2.0 the whole job was handed to Bottles instead.

## What we took, and what we did not

Bottles is not an alternative to Wine, it is a manager on top of it, and its
real contribution is **one prefix per application** instead of a single shared
`~/.wine`. That is the idea, and we implemented it directly (see
`packages/sakura-wine`): each program gets its own prefix under
`~/.local/share/sakura/wine/<slug>`, keyed off the app database so that a
version bump lands in the same prefix rather than a new one.

We did not ship Bottles. It is a Flatpak GTK4/libadwaita application, and on a
Plasma system it looks like a guest — the same reason we did not ship
`zorin-exec-guard`. We also do not claim parity with it: Bottles does runner
version management, dependency installation and sandboxing, and we do none of
that.

## What reading this found in our own code

Wine's own `wine.desktop` on Arch claims:

    application/x-ms-dos-executable;application/x-msi;
    application/x-ms-shortcut;application/x-bat;application/x-mswinurl

We were covering the first two and not the last three. That did not mean
`.lnk`, `.bat` and `.url` were ignored — it meant **Wine handled them directly
and the guard never saw them**. A .bat from a download would have run with no
warning at all. Fixed; the association list now covers all eight types.

One thing that was checked and turned out fine: `wine file.msi` and
`wine file.bat` both work. Wine's loader recognises them and reaches for
msiexec and cmd itself. The explicit dispatch in the guard is defensive, not a
bug fix.

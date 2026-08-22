# AUR rebuilds

`build/build-packages.sh` clones each package listed in `manifest.txt` from the
AUR and rebuilds it into `sakura-core`.

## Why this exists

`pacman` can only install from configured repositories. The AUR is a collection
of build recipes, not a repository, and building one requires a compiler
toolchain, network access, and a user willing to read a PKGBUILD. None of that
is available partway through an installer.

So every AUR package the installed system depends on must be rebuilt and served
by us. That is not a workaround — it is the same thing every Arch derivative
does, and it is why `sakura-core` blocks the installer.

## What this obliges us to do

Taking a package out of the AUR means taking on its maintenance:

- **Upstream changes are not automatic.** A rebuild picks up whatever the AUR
  maintainer has pushed, including changes we have not read.
- **Pin before shipping to users.** `manifest.txt` currently tracks AUR HEAD,
  which is fine while only developers consume the repo and unacceptable once
  anyone else does. Pin each entry to a reviewed commit before first release.
- **Rebuild on soname bumps.** These are compiled against system libraries. When
  Arch bumps a soname, our copy breaks until rebuilt — the canary fleet is what
  should notice this rather than a user.

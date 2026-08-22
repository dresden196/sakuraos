# SakuraOS

An Arch-based, KDE Plasma distribution aimed at people who want Arch's software
model without needing Arch's recovery skills.

The distinguishing work is four integrated components, not the package selection:

| Component | What it is |
|---|---|
| **Installer** | Qt/QML, a small fixed set of options, Secure Boot and BTRFS handled for you |
| **Store** | One app list across repos, Flatpak and AUR, with the source made obvious |
| **Update manager** | A System Settings page, not a terminal command. Owns rollback |
| **Terminal Assist** | Catches the commands that break Arch systems, without locking the user out |

## Architecture decisions

These are settled; changing one is a project-level decision, not a patch.

**BTRFS with automatic snapshots.** `snap-pac` takes a snapshot before every
pacman transaction. The subvolume layout (`@`, `@home`, `@log`, `@pkg`,
`@snapshots`) is an implementation detail the user should never see or hear
named. This exists so that "a bad update" is a reboot, not a live USB.

**limine + Unified Kernel Images.** `limine-snapper-sync` writes snapshot
entries into the boot menu, which is the only rollback path that works when the
system won't boot. UKIs make Secure Boot signing a single operation.

**Secure Boot via `sbctl`.** The installer generates machine-local keys, signs
the boot chain, and enrolls them when firmware is in Setup Mode. Every other
Arch derivative tells the user to disable Secure Boot in firmware; for a
non-technical user that is where the install attempt ends.

**Track Arch directly, gate on evidence.** Sakura does not hold packages back on
a schedule — that is what breaks AUR compatibility on Manjaro. Instead a fleet
of canary VMs updates and boot-tests continuously, and the update manager
consumes targeted hold advisories when a specific package set is shown to break.

**Store source priority: repos → Flatpak → AUR.** AUR is available but opt-in per
package, with the PKGBUILD shown. An app store that silently builds unreviewed
PKGBUILDs on a beginner's machine contradicts the entire premise.

## Repository layout

```
iso/      archiso profile, forked from releng. The first commit is pristine
          upstream releng, so `git log iso/` is an exact record of every way
          Sakura diverges from the official Arch ISO.
build/    Container + QEMU tooling. Nothing here installs onto the host.
out/      Build artifacts (gitignored).
```

## Building

Requires only `docker` and `qemu`. `archiso` is never installed on the host —
it lives in the build container, because `mkarchiso` needs root and loop
devices and there is no reason to hand those to your daily driver.

```bash
./build/build-iso.sh                  # → out/sakura-<version>-x86_64.iso
./build/build-iso.sh --rebuild-image  # refresh the container's archiso
./build/test-vm.sh                    # boot the newest ISO under UEFI
./build/test-vm.sh --secboot          # ...with Secure Boot firmware
./build/test-vm.sh --reset            # wipe the scratch disk and NVRAM first
```

Checking what the VM is doing, without a human watching the screen:

```bash
./build/vm-ready.sh                   # block until Plasma is up, set 1080p
./build/guest-run.sh 'systemctl --failed'   # run a command inside the guest
./build/screenshot.sh /tmp/shot.png   # capture the framebuffer
```

`guest-run.sh` goes over the QEMU guest agent, so it needs no network, no SSH
and no credentials — it works against an unmodified live ISO. Install runs get
verified by script rather than by eye, which is the only way the UEFI / BIOS /
NVMe / dual-boot test matrix stays affordable.

The first build downloads the full Plasma stack and takes 15–25 minutes.
Subsequent builds reuse the `sakura-pkgcache` docker volume and are far faster.

The test VM has its own 60 GB qcow2 in `out/` and its own copy of the OVMF NVRAM
vars. It cannot see the host's disks.

## Packages

```bash
./build/make-dev-key.sh      # one-time: throwaway signing key (see keys/README.md)
./build/build-packages.sh    # build + sign everything into repo/sakura-core
```

`packages/` holds our own PKGBUILDs; `packages/aur/manifest.txt` lists AUR
packages rebuilt into the repo because the installed system depends on them and
`pacman` cannot build from the AUR during an install.

The ISO build trusts the signing key and consumes the repo with
`SigLevel = Required`, so signature verification is exercised on every local
build rather than only in production.

## Status

**M0 — live ISO.** Boots to a Plasma Wayland session as an unprivileged `sakura`
user via SDDM autologin. No custom installer yet; `archinstall` is on the media.

**M1 — sakura-core.** Signed repo with a signed database. `sakura-keyring`,
`sakura-branding` (the system identifies as SakuraOS) and the `sakura-desktop`
meta package build, sign, publish, and install. Two things are still open:

- The signing key is a **development** key. See `keys/README.md`.
- The three AUR limine packages **do not build** — Arch's `gradle` 9.7.0 is
  missing a module all three need. `sakura-desktop` depends on them, so it
  cannot currently be installed. See `packages/aur/README.md`.

Next: resolve the snapshot-boot tooling, then Terminal Assist, the update
manager KCM, the store, and the installer last — its requirements are the most
determined by everything else.

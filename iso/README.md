# ISO profile

Forked from `archiso`'s `releng` profile. The first commit in this repository is
pristine upstream `releng`, so `git log iso/` shows exactly — and only — how
SakuraOS diverges from the official Arch ISO. Keep it that way: when rebasing
onto a newer `archiso`, re-extract `releng` and replay these changes rather than
merging blind.

## Divergences from releng

**Branding.** `profiledef.sh` — `iso_name`, `iso_label`, `install_dir`,
publisher strings — plus `/etc/hostname` and `/etc/motd`. releng's motd points
users at `iwctl`, which no longer exists on this media now that NetworkManager
has replaced iwd, so leaving it would have actively misled people.

`/etc/os-release` is still Arch's. Fixing that needs a `sakura-branding`
package, which belongs to M1, not to the ISO profile.

**zstd instead of xz for squashfs.** xz costs roughly fifteen minutes per
rebuild on a Plasma-sized rootfs. zstd-19 is a few percent larger and several
times faster, which is the right trade while the ISO is rebuilt many times a
day. Revisit before the first public release, where download size matters more
than build time.

**Plasma live session.** `packages.x86_64` gains the Plasma stack; `airootfs`
gains SDDM autologin into a Plasma Wayland session as an unprivileged `sakura`
user. releng boots to a root shell on tty1, which is not something a normal
person can install from.

The live user is created at boot by `sakura-live-user.service` rather than by
shipping `/etc/passwd` and `/etc/group` overlays — overlaying those files would
replace the ones from the `filesystem` package wholesale and silently drop every
system group.

**NetworkManager replaces systemd-networkd + iwd.** `plasma-nm` requires it, and
a graphical installer environment has to let someone join Wi-Fi from the GUI.
The networkd units and `/etc/systemd/network/*.network` are removed rather than
left inert, so there is no ambiguity about which stack is live.
`systemd-resolved` is kept; NetworkManager drives it.

**Target-system tooling on the media.** `limine`, `sbctl`, `snapper`,
`snap-pac`, `pacman-contrib` — present because the installer drives them, not
because the live session needs them.

**Installer autostart.** `airootfs/etc/xdg/autostart` launches the installer
when the live session comes up. It lives in the ISO profile rather than in the
`sakura-installer` package because an installed system must not greet its
owner with a disk-erasing wizard at every login.

## Deliberately not changed

**Screen resolution in VMs is not an ISO problem.** Under QEMU the guest comes
up at 640x480 because Plasma honours the EDID-preferred mode and virtio-gpu
insists that is 640x480 — `edid=on`, `xres`/`yres` on the device, and
`video=Virtual-1:1920x1080` on the kernel cmdline were all tried and none of
them move it. `kscreen-doctor` overrides it fine at runtime, so the fix lives in
`build/vm-ready.sh` where it belongs. Real hardware gets EDID from the monitor
and is unaffected. Do not re-add a `video=` parameter here; it does nothing.

## Still inherited from releng, to revisit

`clonezilla`, `partimage`, `partclone`, `cloud-init`, `hyperv`, `open-vm-tools`,
`virtualbox-guest-utils-nox` and the rest of the Arch rescue-media package set
are still here. They are dead weight on an installer ISO and should be trimmed,
but trimming them is a size optimization, not a blocker, and every removal is a
divergence that has to be re-justified on each `releng` rebase.

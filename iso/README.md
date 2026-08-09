# ISO profile

Forked from `archiso`'s `releng` profile. The first commit in this repository is
pristine upstream `releng`, so `git log iso/` shows exactly — and only — how
SakuraOS diverges from the official Arch ISO. Keep it that way: when rebasing
onto a newer `archiso`, re-extract `releng` and replay these changes rather than
merging blind.

## Divergences from releng

**Branding.** `profiledef.sh` — `iso_name`, `iso_label`, `install_dir`,
publisher strings.

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

**`video=Virtual-1:1920x1080` on the kernel cmdline.** Under QEMU, virtio-gpu
advertises 640x480 as its preferred mode and Plasma believes it, even with
`edid=on` and `xres`/`yres` set on the device. Forcing the mode is the only
thing that reliably works. `Virtual-1` is a connector name that exists only in
virtual machines, so this is inert on real hardware.

**Target-system tooling on the media.** `limine`, `sbctl`, `snapper`,
`snap-pac`, `pacman-contrib` — present because the installer drives them, not
because the live session needs them.

## Still inherited from releng, to revisit

`clonezilla`, `partimage`, `partclone`, `cloud-init`, `hyperv`, `open-vm-tools`,
`virtualbox-guest-utils-nox` and the rest of the Arch rescue-media package set
are still here. They are dead weight on an installer ISO and should be trimmed,
but trimming them is a size optimization, not a blocker, and every removal is a
divergence that has to be re-justified on each `releng` rebase.

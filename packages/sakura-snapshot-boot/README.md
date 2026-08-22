# sakura-snapshot-boot

Snapshot rollback for SakuraOS. Replaces `limine-snapper-sync`,
`limine-entry-tool` and `limine-mkinitcpio-hook`.

## Why not use those

They are three GraalVM-compiled Kotlin projects from a single upstream author,
each pulling a 323 MB toolchain to build, none shipping a Gradle wrapper, and
all three currently failing against Arch's `gradle` 9.7.0. That is a lot of
machinery, and a lot of single-maintainer risk, for something in the boot path.

This does the one job SakuraOS needs from them, in shell, with tests.

## The constraint that shapes the design

A UKI embeds its kernel command line, and `systemd-stub(7)` is explicit:

> If UEFI SecureBoot is enabled and the `.cmdline` section is present in the
> executed image, any attempts to override the kernel command line by passing
> one as invocation parameters to the EFI binary are ignored.

So the obvious design — one boot entry per snapshot, each with its own
`rootflags=subvol=` — fails **silently** under Secure Boot. The menu offers
"snapshot from Aug 8", the user picks it, and the current system boots. A
rollback that quietly does nothing is worse than having no rollback.

## What it does instead

The kernel command line always says `subvol=@`, and rollback changes what `@`
*is*:

1. Rename the current `@` to `@rollback-<timestamp>` — kept, not deleted.
2. Create a fresh writable subvolume at `@` from the chosen snapshot.
3. Reboot.

Because the command line never varies, it stays embedded and signed. Two boot
entries exist: the system, and a signed recovery image holding the picker.

Renaming a subvolume that is currently mounted appears to work and fails later,
so `sakura-rollback` refuses to run when `@` is mounted as `/`. That is why the
picker lives in an initramfs: it is the one place the root subvolume is not in
use. A rollback requested from the running system reboots into recovery to do
the actual work.

## Tested

`tests/run.sh` builds a real btrfs filesystem with snapshots and exercises
listing and rollback, including read-only snapshots restored as writable roots,
half-deleted snapshots being skipped, and the previous root being preserved.

The recovery initramfs is **not** covered end to end — that needs an installed
system, which needs the installer. Verify it on the first real install.

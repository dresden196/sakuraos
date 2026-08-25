# Disk encryption

LUKS2 on the root partition, BTRFS on the mapping above it. The ESP stays
unencrypted, because firmware has to read it — true of every encrypted Linux
system, and the reason the kernel and initramfs are signed. Tampering with an
unencrypted boot partition is the attack that arrangement allows, and a
signature is the answer to it.

## It does not interfere with rollback

This was the open question, and the answer is structural rather than lucky.

`sakura-rollback` renames subvolumes on a mounted BTRFS filesystem. It never
opens the block device, so whether that device is an encrypted mapping is not
something it can observe. Nothing in the rollback path needed changing.

The part that does care is the recovery environment *finding* the disk, which
is why `cryptdevice=` goes on both kernel command lines. A recovery
environment that cannot unlock the disk is not a recovery environment. In
`HOOKS`, `encrypt` sits between `block` and `btrfs`, and `sakura-recovery` is
appended after it, so the mapping already exists by the time our hook looks
for a device.

`keyboard` and `keymap` come before `encrypt`, which matters more than it
looks: the passphrase is the first thing typed on the machine, and it is typed
on the layout the user chose rather than on `us`.

## Turning it off again

The BitLocker behaviour — decrypt in place, keep the system — is possible, but
only if it is decided at install time.

Measured, not read from documentation:

- `cryptsetup reencrypt --decrypt` on a normal LUKS2 device: **refused.**
  "LUKS2 decryption requires --header option."
- With a header backed up to a file and passed as `--header`: **still
  refused.** "LUKS2 decryption is supported with detached header device only
  (with data offset set to 0)."
- Formatted with `--header <file> --offset 0` from the start: **works.**
  Verified by writing a filesystem through the mapping, decrypting with
  `--force-offline-reencrypt`, and then mounting the result with no key and no
  mapper at all. The label survived.

So a machine can only ever be decrypted in place if it was set up for it on
the day it was installed. That is a fork, not a feature to add later:

**Attached header (what is implemented today).** The standard arrangement.
Everything works, nothing unusual, and encryption is permanent for the life of
the install — turning it off means backing up, reinstalling and restoring.

**Detached header.** The header lives outside the encrypted partition, which
in practice means on the ESP. Decryption in place becomes possible. The costs
are real: the header sits on an unencrypted partition, losing it destroys the
data as surely as forgetting the passphrase, and it is an unusual
configuration that other recovery tools will not expect.

Undecided. The installer currently produces the first, and says encryption can
be turned off later — **that sentence is not true yet and is tracked in
docs/claims.md.**

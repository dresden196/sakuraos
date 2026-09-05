# SakuraOS acceptance test — customer scenarios on Proxmox

Real Proxmox VMs (UEFI/OVMF, virtio, guest agent), not QEMU-in-container:
this is the first time the product is exercised on the same kind of guest a
customer would create, rather than on the development harness.

## Scenarios the user asked for
  1. Regular install                      unencrypted, defaults
  2. Encrypted install                    LUKS, passphrase at boot
  3. Rollback                             break it on purpose, recover from the boot menu
  4. Three application installs           one per source: repo, Flatpak, Snap
  5. AUR install                          enable, review, build, campaign check
  6. Update pipeline                      sakura-update apply, snapshot, holds

## What else is worth covering, and why
  7. Secure Boot enrollment               code exists, has NEVER been executed
  8. Terminal Assist actually blocks      the guard is the product's core claim
  9. Windows application support          sakura-wine install and removal
 10. Offline install on real hardware     the 3.3 GB claim, on a Proxmox VM
 11. First boot as a user                 resolution, autologin, does the desktop work
 12. Store search and detail              exact-match ranking is a known bug
 13. Update Center and Settings KCM       the two GUIs never opened in this session

## Ground rules
  - Customer-shaped VMs: 4 cores, 8 GB, 64 GB disk, UEFI, virtio, agent on.
  - GUI installer for scenario 1, since that is what a customer actually sees.
    CLI installer for the rest, for reproducibility.
  - Every result recorded as observed, not inferred. A scenario that cannot be
    tested is recorded as untested rather than assumed to pass.

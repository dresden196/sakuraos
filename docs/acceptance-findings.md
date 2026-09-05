# Acceptance findings

## F1 — installer navigation below the fold at 1280x800  [NEEDS VERIFY, downgraded]
The tour page ("What SakuraOS does differently") and the credits page render
their six/eight cards then place Back and Continue below the fold. At
1280x800, a common laptop resolution and Proxmox's default, only the top few
pixels of the buttons are visible. I first recorded this as blocking on the
basis that End did not scroll -- but focus was not in the flickable, and the
page has a scrollbar and a deliberate spacer for exactly this case, so the
buttons are probably reachable with the wheel. Severity unproven until tested
with wheel events at 1280x800. Either way the buttons should be a fixed
footer, as they are in the main wizard, rather than scrolling with content.
Found on: Proxmox VM 9101, std VGA, 1280x800.
Not visible at 1920x1080, which is what the development harness forces.

## F2 — qm monitor does not deliver input  [tooling, resolved]
Not a product bug. Piping sendkey/mouse_move to `qm monitor` is silently
dropped; info commands answer synchronously so the monitor appears to work.
Replaced with a QMP input-send-event driver.

## F3 — 640x480 does NOT reproduce on Proxmox  [narrows an existing bug]
The live session came up at 1280x800 on std VGA. The 640x480 problem is
specific to virtio-gpu EDID handling, not a general first-boot fault.

## F4 — screen blanks during install  [CONFIRMED, cosmetic but alarming]
Partway through a long install the display blanks (KDE energy saving). A user
sees a black screen during the one operation they cannot interrupt, which
reads as a crash. Other installers inhibit sleep for the duration.
Found on: Proxmox VM 9101 during a copy install.

## F5 — heading says "Ready to install" while installing  [CONFIRMED]
At roughly 97% complete, with partitions written, the target mounted and two
installer processes alive, the install screen's heading read "Ready to
install". The heading is driven by backend.running, so running is false while
the install is in fact running. The progress bar and slideshow were correct at
the same moment, so the two disagree with each other on screen.
Found on: Proxmox VM 9101.

## F6 — install failure is invisible to the user  [CONFIRMED, serious]
When the install died, the screen kept a stale 97% bar, the heading read
"Ready to install", the slideshow stopped, and "Show details" revealed an
EMPTY log. No error anywhere. A customer waits indefinitely in front of a
machine that has stopped, with no way to find out why. Worse than crashing.

## F7 — unbootable disk reported as success  [CONFIRMED, critical, FIXED]
The copy brings pacman's database but excludes /boot (the ESP mountpoint), so
"pacman -Q linux" succeeds where no vmlinuz-linux exists. The installer
skipped the kernel install on that basis, mkinitcpio failed, and the install
continued to completion leaving /boot/EFI/sakura empty. Fixed: the check now
tests the kernel image and refuses to finish without one.

## F8 — offline plus stock kernel is unbootable by construction  [OPEN]
Stock linux lives in [core] and is not on the media. A machine with no
network that falls back to stock has no way to obtain a kernel image. Either
ship linux on the media, or make the tuned kernel mandatory where the CPU
supports it, or fail early and say so.

## E1 — vmbr1 had no DHCP  [environment, fixed]
Test VMs got no address, so every install silently took the offline path.
dnsmasq now serves 10.10.10.100-200 on vmbr1.

## F9 — rollback hangs the machine at boot  [CONFIRMED, CRITICAL]
Rolled back from snapshot 9 on VM 9101. The machine never reached a desktop:
boot.log ends at "Starting Terminate Plymouth Boot Screen..." with no errors,
the guest agent never came up, and the screen sat on the splash indefinitely.

Cause: rollback replaces the root subvolume and cannot touch the ESP, so the
signed boot image keeps the initramfs built by the update that was rolled
back. Measured: sakura.efi built 18:06, @ restored from a 17:23 snapshot;
sakura-* packages are 1.137 in the restored root and 1.139 in the one it
replaced, sakura-plymouth among them. The initramfs hands over to a root
whose Plymouth is not the one it was built against.

sakura-kernel-sync is meant to catch boot-image drift but only asks whether
the running kernel has a modules directory. The kernel version did not change
across this update, so modules matched and the check never fired. It catches
kernel drift and nothing else the boot image embeds.

This is the scenario rollback exists for, so this is the worst place for it.

## Scenario results, Proxmox customer VMs (2026-09-04/05)

  1  regular install          PASS   after 5 bugs, all fixed
  3  rollback                 PASS   after F9, fixed and verified on the broken machine
  4  three app installs       PASS   repo, Flatpak, Snap
  5  AUR install              PASS   search, review pane, polkit, build
  6  update pipeline          PASS   snapshot first, Secure Boot re-signed, campaign check ran
  7  Secure Boot              PASS   enrolled and signed; had never executed anywhere before
  9  Terminal Assist          PASS   blocks -Rdd, override works, package restored
 10  Windows applications     PASS   installs on demand, removes cleanly
 11  first boot               PASS   SDDM, 1280x800, network, all binaries present
 12  store search ranking     FIXED  exact match now outranks popularity
 13  store GUI                PASS   Discover, search, Installed, update banner

  2  encrypted install        NOT RUN
 11b offline install on VM    NOT RUN

## Still open
  - Flatpak app icon missing in the Installed view (cosmetic)
  - "takes the gigabyte with it" is true only once snapshots age out
  - aur-review error conflates "package does not exist" with "fetch failed"
  - store dependency install prompts polkit even when deps are present

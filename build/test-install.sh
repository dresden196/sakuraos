#!/usr/bin/env bash
# Install SakuraOS onto a clean disk in a throwaway VM, then check the result.
#
#   ./build/test-install.sh            install, reboot, verify
#   ./build/test-install.sh --verify   only re-run the checks on an existing VM
#
# Runs as its own named instance (SAKURA_VM=clean) so it never touches the
# machine you already have under test. This exists because "it works on the
# VM we have been poking at all week" is not evidence: that machine grew out
# of the live environment and carries state no real install would have --
# which is how sakura-desktop came to be missing from it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SAKURA_VM=clean

USER_NAME=tester
USER_PASS=tester
HOSTNAME_=sakura-clean

verify_only=0
encrypt=0
for arg in "$@"; do
    case "$arg" in
        --verify)  verify_only=1 ;;
        --encrypt) encrypt=1 ;;
    esac
done
CRYPTPASS=diskpass

run() { "$REPO_ROOT/build/guest-run.sh" "$@"; }

pass=0; fail=0
check() {
    local label="$1" cmd="$2" out
    # The failing command's own words, kept. Discarding them turned every
    # failure into a guess -- the repo checks were blamed on a stale mirror,
    # then a bad signature, then a network race, none of which they were.
    if out=$(run "$cmd" 2>&1); then
        printf '  ok    %s\n' "$label"; pass=$((pass + 1))
    else
        printf '  FAIL  %s\n' "$label"; fail=$((fail + 1))
        printf '        %s\n' "$(printf '%s' "$out" | tail -3 | tr '\n' ' ' | cut -c1-200)"
    fi
}

# For commands that are legitimately slow. Syncing four pacman databases over
# a NAT link takes well over the default ceiling, and reporting that as a
# failure says the repository is unreachable when it is merely not instant --
# which is exactly the wrong conclusion to hand somebody.
check_slow() {
    SAKURA_GUEST_TIMEOUT=240 check "$1" "$2"
}

# pacman takes a database lock, and the previous check may still be holding it
# when the next one starts -- which fails with "unable to lock database" and
# reads as the repository being broken. Wait for it rather than sleeping.
check_pacman() {
    run "for _ in \$(seq 60); do [ -e /var/lib/pacman/db.lck ] || break; sleep 1; done" \
        >/dev/null 2>&1 || true
    check_slow "$1" "$2"
}

if (( ! verify_only )); then
    echo ">> booting the installer media on a blank disk"
    rm -f "$REPO_ROOT/out/sakura-clean.qcow2" \
          "$REPO_ROOT/out/sakura-clean-2.qcow2" \
          "$REPO_ROOT/out/OVMF_VARS-clean.fd"
    "$REPO_ROOT/build/test-vm.sh" --headless >/dev/null 2>&1 &
    "$REPO_ROOT/build/vm-ready.sh"

    echo ">> installing to /dev/vda"
    # Detached, with the exit status left in a file. guest-run gives up after
    # 60s, and an install takes many minutes -- waiting on it directly means
    # the call reports a timeout while the install is still going, and a
    # second attempt then collides with the first over a mounted /dev/vda2.
    # qemu-guest-agent is for this harness, not for users: an installed system
    # ships no agent, so without it the machine is unreachable and none of the
    # checks below can run. --extra-packages is the installer's own mechanism
    # for this, so nothing test-specific leaks into the installer itself.
    CRYPT_ARGS=""
    CRYPT_IN="< /dev/null"
    if (( encrypt )); then
        # The passphrase goes down stdin, the same path the graphical
        # installer uses -- testing a different one would prove nothing about
        # the code that ships.
        CRYPT_ARGS="--encrypt on --encryption-password-stdin"
        CRYPT_IN="<<< $CRYPTPASS"
    fi
    run "setsid bash -c 'sakura-install --disk /dev/vda --user $USER_NAME \
         --password $USER_PASS --hostname $HOSTNAME_ --timezone UTC \
         --theme dark --keymap gb $CRYPT_ARGS \
         --extra-packages qemu-guest-agent --yes \
         > /tmp/install.log 2>&1 $CRYPT_IN; echo \$? > /tmp/install.rc' &" \
        >/dev/null 2>&1 || true

    echo -n ">> installing"
    deadline=$(( SECONDS + 1800 ))
    until run "test -f /tmp/install.rc" >/dev/null 2>&1; do
        (( SECONDS < deadline )) || { echo; echo "install did not finish" >&2; exit 1; }
        echo -n .
        sleep 15
    done
    echo
    rc=$(run "cat /tmp/install.rc" 2>/dev/null | tr -dc '0-9')
    run "tail -15 /tmp/install.log" || true
    [[ "$rc" == "0" ]] || { echo "installer exited $rc" >&2; exit 1; }

    echo ">> rebooting into the installed system"
    run "systemctl poweroff" >/dev/null 2>&1 || true
    sleep 8
    # --installed leaves the ISO out entirely, so a firmware that prefers
    # optical cannot quietly boot the live environment and pass these checks
    # against the wrong system.
    "$REPO_ROOT/build/test-vm.sh" --installed --headless >/dev/null 2>&1 &

    # Wait for the guest agent, not for a desktop session. An installed system
    # does not autologin -- correctly -- so there is no session until somebody
    # types a password, and every check below is a shell command anyway.
    echo -n ">> waiting for the installed system"
    deadline=$(( SECONDS + 420 ))
    typed=0
    until run "true" >/dev/null 2>&1; do
        (( SECONDS < deadline )) || { echo; echo "installed system never came up" >&2; exit 1; }
        # An encrypted disk stops at a passphrase prompt before anything else
        # runs, so there is nothing to poll until somebody types it. Sent once
        # after the prompt has had time to appear, and again a minute later in
        # case the first went to a console that was not listening yet.
        if (( encrypt )) && [[ $typed -lt 2 ]] && (( SECONDS > 25 + typed * 60 )); then
            "$REPO_ROOT/build/sendkeys.sh" $(echo "$CRYPTPASS" | sed 's/./& /g') \
                >/dev/null 2>&1 || true
            "$REPO_ROOT/build/sendkeys.sh" ret >/dev/null 2>&1 || true
            typed=$(( typed + 1 ))
            echo -n "[passphrase]"
        fi
        echo -n .
        sleep 5
    done
    echo " up"
    # The agent answers before the boot has settled; a few units are still
    # starting and `systemctl is-enabled` can race them.
    sleep 10

    # And wait for the network specifically. The repository checks were
    # failing here not because the repository was unreachable but because
    # NetworkManager had not finished getting a lease -- a test that reports
    # "the repo resolves: FAIL" for that reason is worse than no test, because
    # it sends you looking at the server.
    # Waits for what the checks actually need, which is name resolution and a
    # working fetch -- not a ping. A reply from an IP address proves a route
    # exists and nothing about DNS, and the repository checks resolve mirror
    # hostnames: they were failing here while "the network" was reported up.
    echo -n ">> waiting for the network"
    deadline=$(( SECONDS + 180 ))
    # Waits for the thing the checks below actually use. Resolving
    # archlinux.org and reaching the repository host by IP over HTTP was not
    # that: pacman fetches sakura-core over HTTPS from repo.sakuraos.org, and
    # a machine where that name or its certificate is not ready yet passes
    # this gate and then fails "the repo resolves" -- which reads as a broken
    # repository rather than as a test that started too early. Fetching the
    # database is the same request pacman is about to make.
    until run "getent hosts archlinux.org >/dev/null && curl -sS -o /dev/null --max-time 10 https://repo.sakuraos.org/sakura-core/os/x86_64/sakura-core.db" >/dev/null 2>&1; do
        (( SECONDS < deadline )) || { echo " (still not resolving; repo checks may fail)"; break; }
        echo -n .
        sleep 5
    done
    echo " up"
fi

echo
echo ">> checking the installed system"
# The meta package is what holds the desktop together: without it nothing at
# the pacman level stops a removal taking Plasma with it.
check "sakura-desktop is installed"        "pacman -Q sakura-desktop"
check "sakura-store is installed"          "pacman -Q sakura-store"
check "the user exists"                    "id $USER_NAME"
check "hostname was applied"               "test \"\$(cat /etc/hostname)\" = $HOSTNAME_"
check "root is on btrfs"                   "findmnt -no FSTYPE / | grep -q btrfs"
check "the @ subvolume is the root"        "findmnt -no OPTIONS / | tr ',' '\\n' | grep -qx 'subvol=/@'"
check "the ESP is mounted"                 "findmnt -no TARGET /boot"
if (( encrypt )); then
    # The point of the whole exercise: the disk is encrypted, the system still
    # boots, and rollback still has something it can reach.
    check "the partition is LUKS"          "cryptsetup isLuks /dev/vda2"
    check "root runs on the mapping"       "findmnt -no SOURCE / | grep -q /dev/mapper/"
    check "the encrypt hook is in place"   "grep -q 'encrypt' /etc/mkinitcpio.conf"
    check "the kernel is told to unlock"   "grep -q cryptdevice /etc/kernel/cmdline"
    check "recovery is told to unlock"     "grep -q cryptdevice /etc/kernel/recovery-cmdline"
fi
check "snapper has a root config"          "snapper -c root list"
check "snapshots exist"                    "test \"\$(snapper -c root list | wc -l)\" -gt 2"
# The duplicate [sakura-core] left by pacstrap made every pacman run warn.
check "sakura-core registered exactly once" \
      "test \"\$(grep -c '^\\[sakura-core\\]' /etc/pacman.conf)\" -eq 0"
check_pacman "the repo resolves"           "pacman -Sy --noconfirm"
check_pacman "our own packages verify"     "pacman -Sw --noconfirm sakura-store"
check "the display manager is enabled"     "systemctl is-enabled sddm"
check "the network manager is enabled"     "systemctl is-enabled NetworkManager"
check "a boot entry was written"           "efibootmgr | grep -qi sakura"
check "the store engine runs as the user"  "runuser -u $USER_NAME -- sakura-store sources"
# Everything below is something that was broken and is meant to be fixed.
check "the keyboard layout was applied"    "grep -q 'XkbLayout' /etc/X11/xorg.conf.d/00-keyboard.conf"
check "the console keymap was converted"   "grep -qx 'KEYMAP=uk' /etc/vconsole.conf"
check "the update timer is enabled"        "systemctl is-enabled sakura-updates.timer"
check "the update timer has a schedule"    "systemctl show sakura-updates.timer -p TimersCalendar | grep -q 03:00"
check "snapper allows the wheel group"     "grep -q 'ALLOW_GROUPS=\"wheel\"' /etc/snapper/configs/root"
check "the user can list snapshots"        "runuser -u $USER_NAME -- snapper -c root list"
check "bluetooth is enabled"               "systemctl is-enabled bluetooth.service"
check "printing is socket-activated"       "systemctl is-enabled cups.socket"
check "print-manager is installed"         "pacman -Q print-manager"
check "a video player is installed"        "pacman -Q haruna"

# ---- the kernel, and the choice the installer made -------------------------
# Asserted as consistency rather than against a hardcoded name: the same
# checks have to pass on a v3 machine that got the tuned kernel and on an
# older one that got stock, and a test that only knows one answer would pass
# on the wrong machine.
check "exactly one kernel is installed" \
      "test \"\$(pacman -Qq linux linux-cachyos 2>/dev/null | wc -l)\" -eq 1"
check "the running kernel has its modules" \
      "test -d /usr/lib/modules/\$(uname -r)"
check "a preset exists for the installed kernel" \
      "test -f /etc/mkinitcpio.d/\$(pacman -Qq linux linux-cachyos 2>/dev/null).preset"
check "the preset points at the installed kernel" \
      "grep -q \"vmlinuz-\$(pacman -Qq linux linux-cachyos 2>/dev/null)\" /etc/mkinitcpio.d/*.preset"
check "the boot image exists"              "test -f /boot/EFI/sakura/sakura.efi"
check "the recovery image exists"          "test -f /boot/EFI/sakura/sakura-recovery.efi"
check "kernel-sync is enabled"             "systemctl is-enabled sakura-kernel-sync.service"
# The service reboots when the boot image and the root disagree. On a healthy
# install it must do nothing at all -- a false positive here is a boot loop.
check "kernel-sync is a no-op on a good install" \
      "/usr/lib/sakura/snapshot-boot/sakura-kernel-sync && test ! -e /var/lib/sakura/kernel-sync-attempted"
# What the CPU can run, and what it was actually given.
check "the kernel matches what the CPU supports" \
      "if /lib/ld-linux-x86-64.so.2 --help | grep -q 'x86-64-v3 (supported'; then \
           pacman -Q linux-cachyos; \
       else \
           pacman -Q linux; \
       fi"
check "the KWin rule for Dolphin shipped"  "grep -q dolphin /etc/xdg/kwinrulesrc"
check "user feedback was configured"       "grep -q FeedbackLevel /home/$USER_NAME/.config/PlasmaUserFeedback"

echo
printf '>> %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))

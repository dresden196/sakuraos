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

# OFFLINE=1 runs the install with no route out, which is the case the copy
# method exists for and the one this harness could never reach before: QEMU
# user networking always hands the guest a working DHCP lease, so every run
# so far proved only that an online install works.
OFFLINE="${OFFLINE:-0}"
if [[ "$OFFLINE" == "1" ]]; then
    export SAKURA_VM_OFFLINE=1
fi

# A failed run used to leave its 6 GiB VM running. Several dead runs then
# starved the host, and the next run's Plasma session timed out waiting for a
# compositor -- which reads as a product bug and is not one. The harness now
# always takes its own VM down, whether it passed, failed or was interrupted.
# The bracket in the pattern keeps pkill from matching this script itself.
cleanup_vm() {
    pkill -f "[s]akura-${SAKURA_VM}\\.qcow2" 2>/dev/null || true
}
trap cleanup_vm EXIT INT TERM

USER_NAME=tester
USER_PASS=tester
HOSTNAME_=sakura-clean

# Which way the system gets onto the disk. copy is the default the installer
# uses; online is the pacstrap path. Both have to pass the same checks.
METHOD="${METHOD:-copy}"
verify_only=0
encrypt=0
for arg in "$@"; do
    case "$arg" in
        --verify|--verify-only)  verify_only=1 ;;
        --encrypt) encrypt=1 ;;
        # Anything else is a mistake, and silence about it is expensive. The
        # canary asked for --verify-only, which this did not accept and
        # ignored without a word, so instead of re-checking the machine it
        # had just updated it wiped the disk and started a fresh install --
        # then reported the update as broken when that install timed out.
        # Every green run was published as a failure holding 24 packages.
        *)
            echo "test-install: unknown argument: $arg" >&2
            echo "usage: test-install.sh [--verify|--verify-only] [--encrypt]" >&2
            exit 2
            ;;
    esac
done
CRYPTPASS=diskpass
# A browser is installed on every run, because the browser list went three
# names wrong for months precisely because nothing here ever picked one. It
# lives in sakura-extra and is fetched over the network, so this also proves
# the target can reach that repository -- which it could not, for a while,
# because the extras were installed before the repository was configured.
# Offline the extras are never fetched, so the browser to assert on is the one
# the live filesystem already carries and the copy brings across -- which is
# exactly why zen-browser-bin is on the ISO. Asking for vivaldi here would test
# nothing but the harness's own wrong expectation.
if [[ "$OFFLINE" == "1" ]]; then
    BROWSER_PKG="${SAKURA_TEST_BROWSER:-zen-browser-bin}"
else
    BROWSER_PKG="${SAKURA_TEST_BROWSER:-vivaldi}"
fi

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

# qemu can fail before it ever runs a guest instruction -- a held ssh forward,
# a missing image, a busy disk -- and it says so on stderr and exits in about a
# second. Nothing downstream noticed: the harness went straight into "waiting
# for the live session" and printed progress dots for the full thirty minutes
# against a VM that was never running. Every "stalled" alert this canary has
# ever sent was this, and the log said only that the session never appeared.
#
# So: after a launch, prove there is a qemu to wait for before waiting for it.
vm_running() { pgrep -f "[q]emu-system-x86_64.*sakura-$1" >/dev/null 2>&1; }

vm_must_be_running() {
    local vm="$1" log="$2" i
    for i in $(seq 1 20); do
        vm_running "$vm" && return 0
        # Exited already, or never started. Either way the answer is in the log.
        sleep 1
    done
    echo >&2
    echo "test-install: the $vm VM is not running." >&2
    echo "              qemu exited at startup; it did not fail to boot." >&2
    echo "--- $log ---" >&2
    tail -n 15 "$log" >&2 2>/dev/null || echo "(no log)" >&2
    exit 1
}

if (( ! verify_only )); then
    echo ">> booting the installer media on a blank disk"
    rm -f "$REPO_ROOT/out/sakura-clean.qcow2" \
          "$REPO_ROOT/out/sakura-clean-2.qcow2" \
          "$REPO_ROOT/out/OVMF_VARS-clean.fd"
    # setsid, and keep the output. A plain background job shares this
    # session, so qemu takes a SIGTERM whenever whatever started the harness
    # tears its session down -- which pct exec does. The symptom is a live
    # session that never appears, fifteen minutes later, with the reason
    # discarded into /dev/null.
    setsid "$REPO_ROOT/build/test-vm.sh" --headless \
        > "$REPO_ROOT/out/live-boot.log" 2>&1 &
    vm_must_be_running clean "$REPO_ROOT/out/live-boot.log"
    "$REPO_ROOT/build/vm-ready.sh"

    # A development affordance, off unless asked for. The installer ships on
    # the ISO, so testing a one-line change to it otherwise means rebuilding
    # the image: forty minutes to find out whether a timeout is in the right
    # place. With this, the working copy is pushed over the one on the media
    # and the run takes minutes. It is deliberately loud, because a green run
    # against a patched guest is not evidence about the ISO and must never be
    # mistaken for one.
    if [[ -n "${SAKURA_INSTALLER_OVERRIDE:-}" ]]; then
        echo ">> OVERRIDE: replacing the installer on the media with"
        echo ">>           $SAKURA_INSTALLER_OVERRIDE"
        echo ">>           this run does NOT test the ISO as built"
        "$REPO_ROOT/build/guest-push.sh" "$SAKURA_INSTALLER_OVERRIDE" /usr/bin/sakura-install
        run "chmod +x /usr/bin/sakura-install" >/dev/null 2>&1 || true
        run "bash -n /usr/bin/sakura-install" >/dev/null || {
            echo "the pushed installer does not parse in the guest" >&2; exit 1; }
    fi

    echo ">> installing to /dev/vda"
    # Detached, with the exit status left in a file. guest-run gives up after
    # 60s, and an install takes many minutes -- waiting on it directly means
    # the call reports a timeout while the install is still going, and a
    # second attempt then collides with the first over a mounted /dev/vda2.
    # qemu-guest-agent is for this harness, not for users: an installed system
    # ships no agent, so without it the machine is unreachable and none of the
    # checks below can run. --extra-packages is the installer's own mechanism
    # for this, so nothing test-specific leaks into the installer itself.
    CRYPT_IN="< /dev/null"
    if (( encrypt )); then
        # The passphrase goes down stdin, the same path the graphical
        # installer uses -- testing a different one would prove nothing about
        # the code that ships.
        CRYPT_IN="<<< $CRYPTPASS"
    fi
    # Built as an array here, shipped as base64, and run from a file in the
    # guest.
    #
    # It used to be one string containing a single-quoted bash -c payload,
    # crossing three layers of quoting: this shell, the guest agent, and the
    # bash the guest starts. Adding a value that itself needed quotes -- an
    # accent colour, a full name with a space in it -- ended the payload early,
    # and the command then silently never ran at all. The guest sat idle at
    # load 0.00 while the harness printed progress dots for the full thirty
    # minutes waiting for an install.rc nothing was going to write.
    #
    # base64 has no quotes, no spaces and no hashes, so it survives every layer
    # unexamined. Adding an argument is now editing an array.
    install_args=(
        sakura-install
        --disk /dev/vda
        --user "$USER_NAME"
        --password "$USER_PASS"
        --hostname "$HOSTNAME_"
        --timezone UTC
        --theme dark
        --keymap gb
        --extra-packages "qemu-guest-agent $BROWSER_PKG"
        --browser "$BROWSER_PKG"
        --accent "#3daee9"
        --clock 12
        --fullname "Test User"
        --method "$METHOD"
        --yes
    )
    (( encrypt )) && install_args+=(--encrypt on --encryption-password-stdin)

    # printf %q quotes each argument for the shell that will read the file.
    INSTALL_CMD="$(printf '%q ' "${install_args[@]}")"
    INSTALL_B64="$(printf '%s' "$INSTALL_CMD" | base64 -w0)"

    run "echo $INSTALL_B64 | base64 -d > /tmp/install.cmd" >/dev/null 2>&1 || true
    run "setsid bash -c 'bash /tmp/install.cmd > /tmp/install.log 2>&1 $CRYPT_IN; echo \$? > /tmp/install.rc' &" \
        >/dev/null 2>&1 || true

    # Prove it started rather than assuming. This is the exact failure the
    # rewrite above is for, and finding out here costs seconds where finding
    # out from the timeout costs half an hour.
    _started=0
    for _i in $(seq 1 15); do
        if run "test -s /tmp/install.log || test -f /tmp/install.rc" >/dev/null 2>&1; then
            _started=1; break
        fi
        sleep 2
    done
    if (( ! _started )); then
        echo "test-install: the installer did not start in the guest." >&2
        echo "              /tmp/install.cmd holds what was sent:" >&2
        run "cat /tmp/install.cmd" >&2 2>/dev/null || true
        exit 1
    fi

    # Pull the installer's log out of the guest while the guest still exists.
    # Called on the failure paths below as well as after a clean finish: the
    # trap destroys the VM on exit, so a run that times out used to take the
    # only record of why it timed out down with it, leaving 119 progress dots
    # as the entire diagnosis. That is the same mistake this file warns about
    # everywhere else -- keep the failing thing's own words.
    save_guest_log() {
        run "cat /tmp/install.log" > "$REPO_ROOT/out/install-guest.log" 2>/dev/null || true
        if [[ -s "$REPO_ROOT/out/install-guest.log" ]]; then
            echo ">> full installer log saved to out/install-guest.log ($(wc -l < "$REPO_ROOT/out/install-guest.log") lines)"
        fi
    }

    echo -n ">> installing"
    deadline=$(( SECONDS + 1800 ))
    until run "test -f /tmp/install.rc" >/dev/null 2>&1; do
        if (( SECONDS >= deadline )); then
            echo; echo "install did not finish" >&2
            save_guest_log
            echo "-- last 25 lines of the installer log:" >&2
            run "tail -25 /tmp/install.log" >&2 2>/dev/null || true
            exit 1
        fi
        # A VM that died halfway through an install is not going to produce
        # the file being waited on, and waiting the remaining twenty-odd
        # minutes to say so helps nobody.
        # No save_guest_log here: the VM is gone, so there is nothing left to
        # read the log out of. The boot log on the host is what survives.
        vm_running clean || { echo; echo "the VM stopped during the install" >&2
            tail -n 15 "$REPO_ROOT/out/live-boot.log" >&2 2>/dev/null || true; exit 1; }
        echo -n .
        sleep 15
    done
    echo
    rc=$(run "cat /tmp/install.rc" 2>/dev/null | tr -dc '0-9')

    # Keep the whole install log, not the last fifteen lines of it. The VM is
    # destroyed on exit, and every interesting decision the installer makes --
    # which kernel it picked and why, which keyrings it populated, what it
    # skipped for lack of a network -- is announced well before the end. Three
    # separate diagnoses in this project stalled on a log that no longer
    # existed by the time anyone wanted to read it.
    save_guest_log
    run "tail -15 /tmp/install.log" || true
    [[ "$rc" == "0" ]] || { echo "installer exited $rc" >&2; exit 1; }

    echo ">> rebooting into the installed system"
    run "systemctl poweroff" >/dev/null 2>&1 || true

    # Wait for the VM to actually let go of the disk, rather than assuming a
    # fixed pause is enough. Asking a guest to power off is not the same as
    # qemu having exited, and the next VM cannot open an image the previous
    # one still holds: it fails with "Failed to get write lock" and exits, so
    # the symptom is the installed system never coming up, twenty minutes
    # later, in a different log. Eight seconds was usually enough, which is
    # the worst kind of usually.
    for _i in $(seq 1 60); do
        fuser "$REPO_ROOT/out/sakura-clean.qcow2" >/dev/null 2>&1 || break
        [[ $_i -eq 1 ]] && echo ">> waiting for the install VM to release the disk"
        sleep 2
    done
    if fuser "$REPO_ROOT/out/sakura-clean.qcow2" >/dev/null 2>&1; then
        echo "test-install: the install VM is still holding the disk" >&2
        exit 1
    fi
    # --installed leaves the ISO out entirely, so a firmware that prefers
    # optical cannot quietly boot the live environment and pass these checks
    # against the wrong system.
    setsid "$REPO_ROOT/build/test-vm.sh" --installed --headless \
        > "$REPO_ROOT/out/installed-boot.log" 2>&1 &
    vm_must_be_running clean "$REPO_ROOT/out/installed-boot.log"

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
# Precedence, not just presence. pacman resolves a name from the first repo in
# file order, so our repository has to be included before [core] or an Arch
# package sharing a name would win. The installer refuses to finish if it
# lands the other way round, but nothing re-checked it afterwards, and this
# file is exactly the kind that a pacnew merge quietly reorders. The canary
# runs these checks again after every update, which is where it matters.
# The browser the installer was told to install, actually installed, and
# actually pinned. Each of these was broken at some point and none of them was
# checked: the package name was wrong, the extras were installed before the
# repository that holds them was configured, and the pin looked the .desktop
# name up from the package because a hardcoded table would have been wrong for
# Chrome and Brave.
# The panel's pinned launchers. This regressed once without anyone noticing:
# the layout set them, the write was silently dropped, and icontasks fell back
# to its own defaults -- which pin Discover, a store SakuraOS does not install,
# so a fresh desktop came up with a broken icon where the App Store should be.
# The comment in the layout claimed it was handled for months while the key was
# absent from every install.
check "the panel layout pins our own launchers" \
      "grep -q 'org.sakuraos.store.desktop' /usr/share/plasma/look-and-feel/org.sakura.dark.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
check "the panel layout does not pin Discover" \
      "! grep -q 'discover' /usr/share/plasma/look-and-feel/org.sakura.*.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
# reloadConfig is what makes the write above actually reach the config file.
# Without it the list is written and thrown away.
check "the launcher write is committed" \
      "grep -q 'reloadConfig' /usr/share/plasma/look-and-feel/org.sakura.dark.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
check "the chosen browser is installed" \
      "pacman -Q $BROWSER_PKG"
check "the browser is pinned to the task bar" \
      "grep -q \"\$(pacman -Ql $BROWSER_PKG | awk '\$2 ~ /applications\\/.*desktop\$/ {print \"applications:\" substr(\$2, match(\$2, /[^\\/]*\$/))}' | head -1)\" /usr/share/plasma/look-and-feel/org.sakura.dark.desktop/contents/layouts/org.kde.plasma.desktop-layout.js"
# The answers the installer collects and used to drop on the floor.
check "the accent colour was applied" \
      "grep -q '^AccentColor=61,174,233' /home/$USER_NAME/.config/kdeglobals"
check "the clock format was applied" \
      "grep -q '^LC_TIME=en_US.UTF-8' /home/$USER_NAME/.config/plasma-localerc"
check "the full name reached the account" \
      "getent passwd $USER_NAME | cut -d: -f5 | grep -q 'Test User'"
check "sakura-core is included before [core]" \
      "test \"\$(grep -n '^Include = /etc/pacman.d/sakura-core.conf' /etc/pacman.conf | cut -d: -f1)\" -lt \"\$(grep -n '^\\[core\\]' /etc/pacman.conf | cut -d: -f1)\""
# These two are the only checks that need a route out. Offline they are not
# failures, they are not applicable -- skipped out loud rather than silently,
# so a 35/35 offline pass can never be mistaken for the full 37.
if [[ "$OFFLINE" == "1" ]]; then
    echo "-- skipped (offline): the repo resolves"
    echo "-- skipped (offline): our own packages verify"
else
    check_pacman "the repo resolves"           "pacman -Sy --noconfirm"
    check_pacman "our own packages verify"     "pacman -Sw --noconfirm sakura-store"
fi
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
# The live image enables this so it has a trustworthy clock before checking a
# signature; a normal Arch install does not have it at all. It waits forever
# when there is no network, and the copy used to bring the enablement across.
check "the live clock-wait unit did not come across" \
      "! test -e /etc/systemd/system/sysinit.target.wants/systemd-time-wait-sync.service"
check "the KWin rule for Dolphin shipped"  "grep -q dolphin /etc/xdg/kwinrulesrc"
check "user feedback was configured"       "grep -q FeedbackLevel /home/$USER_NAME/.config/PlasmaUserFeedback"

echo
printf '>> %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))

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
[[ "${1:-}" == "--verify" ]] && verify_only=1

run() { "$REPO_ROOT/build/guest-run.sh" "$@"; }

pass=0; fail=0
check() {
    local label="$1" cmd="$2"
    if run "$cmd" >/dev/null 2>&1; then
        printf '  ok    %s\n' "$label"; pass=$((pass + 1))
    else
        printf '  FAIL  %s\n' "$label"; fail=$((fail + 1))
    fi
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
    run "setsid bash -c 'sakura-install --disk /dev/vda --user $USER_NAME \
         --password $USER_PASS --hostname $HOSTNAME_ --timezone UTC \
         --theme dark --keymap gb --extra-packages qemu-guest-agent --yes \
         > /tmp/install.log 2>&1; echo \$? > /tmp/install.rc' &" \
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
    until run "true" >/dev/null 2>&1; do
        (( SECONDS < deadline )) || { echo; echo "installed system never came up" >&2; exit 1; }
        echo -n .
        sleep 5
    done
    echo " up"
    # The agent answers before the boot has settled; a few units are still
    # starting and `systemctl is-enabled` can race them.
    sleep 10
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
check "the @ subvolume is the root"        "findmnt -no OPTIONS / | grep -q 'subvol=/@\\b'"
check "the ESP is mounted"                 "findmnt -no TARGET /boot"
check "snapper has a root config"          "snapper -c root list"
check "snapshots exist"                    "test \"\$(snapper -c root list | wc -l)\" -gt 2"
# The duplicate [sakura-core] left by pacstrap made every pacman run warn.
check "sakura-core registered exactly once" \
      "test \"\$(grep -c '^\\[sakura-core\\]' /etc/pacman.conf)\" -eq 0"
check "the repo resolves"                  "pacman -Sy --noconfirm"
check "our own packages verify"            "pacman -Sw --noconfirm sakura-store"
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
check "the KWin rule for Dolphin shipped"  "grep -q dolphin /etc/xdg/kwinrulesrc"
check "user feedback was configured"       "grep -q FeedbackLevel /home/$USER_NAME/.config/PlasmaUserFeedback"

echo
printf '>> %d passed, %d failed\n' "$pass" "$fail"
(( fail == 0 ))

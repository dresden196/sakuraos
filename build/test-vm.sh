#!/usr/bin/env bash
# Boot a built SakuraOS ISO in QEMU under UEFI.
#
# The VM gets its own scratch disk in out/ and its own copy of the OVMF NVRAM
# vars, so nothing here can see or touch the host's real disks.
#
#   ./build/test-vm.sh              boot the newest ISO in out/
#   ./build/test-vm.sh --secboot    same, with Secure Boot firmware
#   ./build/test-vm.sh --reset      wipe the scratch disk and NVRAM first
#   ./build/test-vm.sh --reset-nvram  clear firmware boot entries, keep the disk
#   ./build/test-vm.sh --installed  boot the installed system, not the ISO
#   ./build/test-vm.sh --headless   no window (screenshots still work)
#
# SAKURA_VM_CPU overrides the guest CPU model (default: host). Needed to
# test the kernel fallback: the installer picks the tuned x86-64-v3 kernel
# or stock by what the CPU supports, and a host-passthrough guest always
# looks modern. SAKURA_VM_CPU=Nehalem is a pre-AVX2 machine.
#   ./build/test-vm.sh --gl         virgl acceleration; disables screenshots
#
# Screenshots: build/screenshot.sh out.png — works in every mode except --gl.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVMF_DIR=/usr/share/edk2/x64

# A named instance gets its own disks, firmware variables and sockets, so a
# second machine -- a clean install to test against, say -- can run beside the
# one already up instead of fighting it for the same paths. Every helper in
# build/ reads the same variable.
VM="${SAKURA_VM:-test}"
DISK="$REPO_ROOT/out/sakura-$VM.qcow2"
DISK2="$REPO_ROOT/out/sakura-$VM-2.qcow2"
NVRAM="$REPO_ROOT/out/OVMF_VARS-$VM.fd"
QMP_SOCK="$REPO_ROOT/out/qmp-$VM.sock"
QGA_SOCK="$REPO_ROOT/out/qga-$VM.sock"

# The SSH forward is a host-wide resource, so a second instance cannot reuse
# it -- qemu refuses to start rather than sharing the port. Derived from the
# instance name so two machines never collide, and overridable when the
# derived port is itself in use.
if [[ -n "${SAKURA_VM_SSH_PORT:-}" ]]; then
    SSH_PORT="$SAKURA_VM_SSH_PORT"
elif [[ "$VM" == "test" ]]; then
    SSH_PORT=2222
else
    # Stable per name, well clear of the ephemeral range.
    SSH_PORT=$(( 2223 + $(cksum <<<"$VM" | cut -d' ' -f1) % 500 ))
fi

secboot=0
headless=0
reset=0
reset_nvram=0
gl=0
installed=0
for arg in "$@"; do
    case "$arg" in
        --secboot)  secboot=1 ;;
        --headless) headless=1 ;;
        --reset)    reset=1 ;;
        --reset-nvram) reset_nvram=1 ;;
        --gl)       gl=1 ;;
        --installed) installed=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

ISO="$(ls -t "$REPO_ROOT"/out/*.iso 2>/dev/null | head -1 || true)"
if (( ! installed )); then
    [[ -n "$ISO" ]] || { echo "no ISO in out/ — run build/build-iso.sh first" >&2; exit 1; }
fi

if (( reset )); then rm -f "$DISK" "$DISK2" "$NVRAM"; fi
# After an install, the firmware boot entry the installer wrote outranks the
# optical drive, so attaching the ISO is not enough to boot it again. Clearing
# just the NVRAM gets back to the live environment without losing the install
# that is under test.
if (( reset_nvram )); then rm -f "$NVRAM"; fi

# Distributions disagree about where OVMF lives and what the files are called:
# Arch puts them in /usr/share/edk2/x64 as OVMF_CODE.4m.fd, Debian in
# /usr/share/OVMF as OVMF_CODE_4M.fd. The canary runs on Debian and the
# development machine is Arch, so look rather than assume.
pick_firmware() {
    local want="$1" p
    for p in "$@"; do [[ -f "$p" ]] && { printf '%s' "$p"; return 0; }; done
    return 1
}

if (( secboot )); then
    CODE=$(pick_firmware \
        "$OVMF_DIR/OVMF_CODE.secboot.4m.fd" \
        /usr/share/OVMF/OVMF_CODE_4M.secboot.fd \
        /usr/share/edk2/x64/OVMF_CODE.secboot.4m.fd) \
        || { echo "no Secure Boot OVMF firmware found" >&2; exit 1; }
else
    CODE=$(pick_firmware \
        "$OVMF_DIR/OVMF_CODE.4m.fd" \
        /usr/share/OVMF/OVMF_CODE_4M.fd \
        /usr/share/edk2/x64/OVMF_CODE.4m.fd) \
        || { echo "no OVMF firmware found" >&2; exit 1; }
fi

VARS_TEMPLATE=$(pick_firmware \
    "$OVMF_DIR/OVMF_VARS.4m.fd" \
    /usr/share/OVMF/OVMF_VARS_4M.fd \
    /usr/share/edk2/x64/OVMF_VARS.4m.fd) \
    || { echo "no OVMF variable template found" >&2; exit 1; }

# Each VM needs a private, writable copy of the NVRAM vars — the shared one in
# /usr/share is read-only and holds no per-machine Secure Boot state.
[[ -f "$NVRAM" ]] || cp "$VARS_TEMPLATE" "$NVRAM"
[[ -f "$DISK" ]]  || qemu-img create -f qcow2 "$DISK" 60G >/dev/null
# A second disk, so disk selection is exercised rather than assumed:
# with one disk the picker looks right whether or not it enumerates.
[[ -f "$DISK2" ]] || qemu-img create -f qcow2 "$DISK2" 32G >/dev/null

rm -f "$QMP_SOCK" "$QGA_SOCK"

# --installed leaves the ISO out entirely rather than just reordering boot:
# with the media still attached, a firmware that prefers optical would quietly
# boot the live environment again and the test would prove nothing.
if (( installed )); then
    media_args=(-boot order=c)
else
    media_args=(-drive "file=$ISO,media=cdrom,readonly=on" -boot order=d)
fi

# Default to plain virtio-vga: with virgl the framebuffer lives on the host GPU
# via dmabuf, so QMP screendump returns "no surface" and every screenshot-based
# check breaks. Software rendering is fine for an installer and being able to
# capture the screen from a script is worth more. --gl trades that away.
# edid=on is what makes xres/yres actually reach the guest. Without it
# virtio-gpu advertises 640x480 as its preferred mode and Plasma believes it,
# leaving no room to judge any UI we build.
VGA="virtio-vga,edid=on,xres=1920,yres=1080"

# SAKURA_VM_OFFLINE cuts the guest off from the network while leaving the card
# present, which is what a machine with no cable actually looks like -- a VM
# with no NIC at all would exercise a different code path. restrict=on blocks
# outbound traffic but still honours hostfwd, and the harness drives the guest
# over the guest-agent socket rather than SSH, so nothing it needs is lost.
NET_RESTRICT=""
if [[ -n "${SAKURA_VM_OFFLINE:-}" ]]; then
    NET_RESTRICT=",restrict=on"
    echo ">> networking restricted: the guest has a NIC but no route out"
fi
display_args=(-display gtk,show-cursor=on -device "$VGA")
(( gl ))       && display_args=(-display gtk,gl=on,show-cursor=on -device virtio-vga-gl,edid=on,xres=1920,yres=1080)
(( headless )) && display_args=(-display none -device "$VGA")

if (( installed )); then
    echo ">> booting the installed system as \"$VM\" (ssh port $SSH_PORT)"
else
    echo ">> booting $(basename "$ISO") as \"$VM\" (ssh port $SSH_PORT)"
fi
exec qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,smm=on \
    -cpu "${SAKURA_VM_CPU:-host}" \
    -smp 8 \
    -m 6G \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,unit=1,file="$NVRAM" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -drive file="$DISK2",if=virtio,format=qcow2 \
    "${media_args[@]}" \
    -device qemu-xhci -device usb-tablet \
    -netdev "user,id=net0,hostfwd=tcp::$SSH_PORT-:22${NET_RESTRICT}" -device virtio-net,netdev=net0 \
    -qmp "unix:$QMP_SOCK,server,nowait" \
    -chardev "socket,path=$QGA_SOCK,server=on,wait=off,id=qga0" \
    -device virtio-serial \
    -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
    "${display_args[@]}"

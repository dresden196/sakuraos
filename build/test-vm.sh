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
#   ./build/test-vm.sh --gl         virgl acceleration; disables screenshots
#
# Screenshots: build/screenshot.sh out.png — works in every mode except --gl.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVMF_DIR=/usr/share/edk2/x64
DISK="$REPO_ROOT/out/sakura-test.qcow2"
NVRAM="$REPO_ROOT/out/OVMF_VARS.fd"
QMP_SOCK="$REPO_ROOT/out/qmp.sock"
QGA_SOCK="$REPO_ROOT/out/qga.sock"

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

if (( reset )); then rm -f "$DISK" "$NVRAM"; fi
# After an install, the firmware boot entry the installer wrote outranks the
# optical drive, so attaching the ISO is not enough to boot it again. Clearing
# just the NVRAM gets back to the live environment without losing the install
# that is under test.
if (( reset_nvram )); then rm -f "$NVRAM"; fi

if (( secboot )); then
    CODE="$OVMF_DIR/OVMF_CODE.secboot.4m.fd"
else
    CODE="$OVMF_DIR/OVMF_CODE.4m.fd"
fi

# Each VM needs a private, writable copy of the NVRAM vars — the shared one in
# /usr/share is read-only and holds no per-machine Secure Boot state.
[[ -f "$NVRAM" ]] || cp "$OVMF_DIR/OVMF_VARS.4m.fd" "$NVRAM"
[[ -f "$DISK" ]]  || qemu-img create -f qcow2 "$DISK" 60G >/dev/null

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
display_args=(-display gtk,show-cursor=on -device "$VGA")
(( gl ))       && display_args=(-display gtk,gl=on,show-cursor=on -device virtio-vga-gl,edid=on,xres=1920,yres=1080)
(( headless )) && display_args=(-display none -device "$VGA")

echo ">> booting $(basename "$ISO")"
exec qemu-system-x86_64 \
    -enable-kvm \
    -machine q35,smm=on \
    -cpu host \
    -smp 8 \
    -m 6G \
    -drive if=pflash,format=raw,unit=0,readonly=on,file="$CODE" \
    -drive if=pflash,format=raw,unit=1,file="$NVRAM" \
    -drive file="$DISK",if=virtio,format=qcow2 \
    "${media_args[@]}" \
    -device qemu-xhci -device usb-tablet \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 -device virtio-net,netdev=net0 \
    -qmp "unix:$QMP_SOCK,server,nowait" \
    -chardev "socket,path=$QGA_SOCK,server=on,wait=off,id=qga0" \
    -device virtio-serial \
    -device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0 \
    "${display_args[@]}"

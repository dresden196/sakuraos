#!/usr/bin/env bash
# Boot a built SakuraOS ISO in QEMU under UEFI.
#
# The VM gets its own scratch disk in out/ and its own copy of the OVMF NVRAM
# vars, so nothing here can see or touch the host's real disks.
#
#   ./build/test-vm.sh              boot the newest ISO in out/
#   ./build/test-vm.sh --secboot    same, with Secure Boot firmware
#   ./build/test-vm.sh --reset      wipe the scratch disk and NVRAM first
#   ./build/test-vm.sh --headless   no window; QMP screenshots only
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVMF_DIR=/usr/share/edk2/x64
DISK="$REPO_ROOT/out/sakura-test.qcow2"
NVRAM="$REPO_ROOT/out/OVMF_VARS.fd"
QMP_SOCK="$REPO_ROOT/out/qmp.sock"

secboot=0
headless=0
reset=0
for arg in "$@"; do
    case "$arg" in
        --secboot)  secboot=1 ;;
        --headless) headless=1 ;;
        --reset)    reset=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

ISO="$(ls -t "$REPO_ROOT"/out/*.iso 2>/dev/null | head -1 || true)"
[[ -n "$ISO" ]] || { echo "no ISO in out/ — run build/build-iso.sh first" >&2; exit 1; }

if (( reset )); then rm -f "$DISK" "$NVRAM"; fi

if (( secboot )); then
    CODE="$OVMF_DIR/OVMF_CODE.secboot.4m.fd"
else
    CODE="$OVMF_DIR/OVMF_CODE.4m.fd"
fi

# Each VM needs a private, writable copy of the NVRAM vars — the shared one in
# /usr/share is read-only and holds no per-machine Secure Boot state.
[[ -f "$NVRAM" ]] || cp "$OVMF_DIR/OVMF_VARS.4m.fd" "$NVRAM"
[[ -f "$DISK" ]]  || qemu-img create -f qcow2 "$DISK" 60G >/dev/null

rm -f "$QMP_SOCK"

display_args=(-display gtk,show-cursor=on)
(( headless )) && display_args=(-display none)

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
    -drive file="$ISO",media=cdrom,readonly=on \
    -boot order=d \
    -device virtio-vga-gl \
    -device qemu-xhci -device usb-tablet \
    -netdev user,id=net0 -device virtio-net,netdev=net0 \
    -qmp "unix:$QMP_SOCK,server,nowait" \
    "${display_args[@]}"

#!/usr/bin/env bash
# Build a disk that already has a UEFI operating system on it, for testing the
# installer's "alongside" mode.
#
#   ./build/make-dualboot-disk.sh out/sakura-clean.qcow2
#
# The alongside path reuses an existing ESP, installs into unallocated space
# and renumbers nothing. Every install test so far has used a blank disk, so
# none of that has ever run. This makes the other half of the situation:
# a GPT disk with somebody else's ESP, somebody else's root filesystem, and
# room left over.
#
# Built without root. Each partition is made as its own image and written into
# place at its offset, because loop-mounting needs privileges this should not
# want -- a test fixture that needs sudo is a test nobody runs.
set -euo pipefail

DEST="${1:?usage: make-dualboot-disk.sh <output.qcow2>}"
# Alongside the destination rather than in /tmp: these images are tens of
# gigabytes before they are made sparse again, and /tmp is small enough here
# that the first attempt died with "Disk quota exceeded".
WORK="$(mktemp -d -p "$(dirname "$(readlink -f "$DEST")")")"
trap 'rm -rf "$WORK"' EXIT

SIZE_GB=60
ESP_MB=512
OTHER_GB=20          # leaves ~39 GiB free, comfortably over the 25 GiB minimum

RAW="$WORK/disk.raw"
truncate -s "${SIZE_GB}G" "$RAW"

# Somebody else's layout: an ESP and a root filesystem, then free space.
sgdisk -n "1:2048:+${ESP_MB}M" -t 1:ef00 -c 1:"OTHER_ESP"  "$RAW" >/dev/null
sgdisk -n "2:0:+${OTHER_GB}G"  -t 2:8300 -c 2:"OTHER_ROOT" "$RAW" >/dev/null

esp_start=$(sgdisk -i 1 "$RAW" | awk '/First sector/ {print $3}')
oth_start=$(sgdisk -i 2 "$RAW" | awk '/First sector/ {print $3}')

# The ESP, with a bootloader that must still be there afterwards. The installer
# is supposed to add its own directory beside this one and format nothing.
ESP_IMG="$WORK/esp.img"
truncate -s "${ESP_MB}M" "$ESP_IMG"
mkfs.vfat -F32 -n OTHER_ESP "$ESP_IMG" >/dev/null
mmd -i "$ESP_IMG" ::/EFI ::/EFI/BOOT ::/EFI/otheros
printf 'not a real bootloader, but it must survive the install\n' > "$WORK/marker"
mcopy -i "$ESP_IMG" "$WORK/marker" ::/EFI/otheros/grubx64.efi
mcopy -i "$ESP_IMG" "$WORK/marker" ::/EFI/BOOT/BOOTX64.EFI

# The other system's root filesystem, with something recognisable in it.
PAYLOAD="$WORK/payload"
mkdir -p "$PAYLOAD/etc"
printf 'PRETTY_NAME="Some Other Linux"\n' > "$PAYLOAD/etc/os-release"
printf 'this file proves the partition was not touched\n' > "$PAYLOAD/etc/keepme"
OTH_IMG="$WORK/other.img"
truncate -s "${OTHER_GB}G" "$OTH_IMG"
mkfs.ext4 -q -F -L OTHER_ROOT -d "$PAYLOAD" "$OTH_IMG"

# conv=sparse, or dd faithfully writes every hole in a 20 GiB filesystem image
# as real zeroes and the fixture needs the whole disk on disk.
dd if="$ESP_IMG" of="$RAW" bs=512 seek="$esp_start" conv=notrunc,sparse status=none
dd if="$OTH_IMG" of="$RAW" bs=512 seek="$oth_start" conv=notrunc,sparse status=none

mkdir -p "$(dirname "$DEST")"
rm -f "$DEST"
qemu-img convert -f raw -O qcow2 "$RAW" "$DEST"

echo ">> built $DEST"
sgdisk -p "$RAW" | tail -5

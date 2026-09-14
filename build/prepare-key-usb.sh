#!/usr/bin/env bash
# Wipe a USB stick and prepare it to hold the master signing key backup.
#
#   sudo ./build/prepare-key-usb.sh /dev/sdX
#
# Destroys everything on that device. The guards below exist because the cost of
# naming the wrong device here is somebody's disk, so it refuses anything that is
# not removable, anything currently providing / or /boot, and anything whose size
# looks like a real disk rather than a stick.
#
# Formats FAT32 deliberately: the files are a few kilobytes, and the point of an
# offline backup is that it can be read years later on whatever machine is to
# hand, including a recovery environment. ext4 would be a Linux-only key backup.
set -euo pipefail

DEV="${1:?usage: sudo prepare-key-usb.sh /dev/sdX}"
LABEL="${SAKURA_KEY_LABEL:-SAKURAKEY}"
OWNER="${SUDO_USER:-$(id -un)}"

[[ $EUID -eq 0 ]] || { echo "run this with sudo." >&2; exit 1; }
[[ -b "$DEV" ]] || { echo "$DEV is not a block device." >&2; exit 1; }

BASE=$(basename "$DEV")
[[ -e "/sys/block/$BASE" ]] || { echo "$DEV is a partition, not a whole disk. Pass /dev/sdX." >&2; exit 1; }

if [[ "$(cat "/sys/block/$BASE/removable" 2>/dev/null)" != "1" ]]; then
    echo "$DEV is not removable. Refusing." >&2
    exit 1
fi

# Anything mounted from this device that the running system depends on.
for mp in / /boot /home /var; do
    src=$(findmnt -no SOURCE "$mp" 2>/dev/null || true)
    if [[ -n "$src" && "$src" == "$DEV"* ]]; then
        echo "$DEV currently provides $mp. Refusing." >&2
        exit 1
    fi
done

SIZE_GB=$(( $(cat "/sys/block/$BASE/size") / 2097152 ))
if (( SIZE_GB > 256 )); then
    echo "$DEV is ${SIZE_GB}GB, which is larger than a key-backup stick should" >&2
    echo "need. If that is really the intended device, set SAKURA_KEY_FORCE=1." >&2
    [[ "${SAKURA_KEY_FORCE:-0}" == "1" ]] || exit 1
fi

echo "About to ERASE this device completely:"
echo
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL "$DEV"
echo
echo "  vendor/model: $(cat /sys/block/$BASE/device/vendor 2>/dev/null | tr -s ' ')$(cat /sys/block/$BASE/device/model 2>/dev/null | tr -s ' ')"
echo "  size:         ${SIZE_GB}GB"
echo
read -rp "Type ERASE to destroy everything on $DEV: " ans
[[ "$ans" == "ERASE" ]] || { echo "nothing was changed."; exit 1; }

# Unmount anything from this device first; a mounted partition makes the new
# table not take effect and the failure is silent.
for part in $(lsblk -lnpo NAME "$DEV" | tail -n +2); do
    umount "$part" 2>/dev/null || true
done

echo "==> wiping signatures and the partition table"
wipefs -a "$DEV" >/dev/null
sgdisk --zap-all "$DEV" >/dev/null 2>&1 || true

echo "==> one partition, FAT32, label $LABEL"
sgdisk -n 1:0:0 -t 1:0700 -c 1:"$LABEL" "$DEV" >/dev/null
partprobe "$DEV"; udevadm settle; sleep 1
PART="${DEV}1"
[[ -b "$PART" ]] || PART="${DEV}p1"
[[ -b "$PART" ]] || { echo "could not find the new partition on $DEV" >&2; exit 1; }
mkfs.vfat -F32 -n "$LABEL" "$PART" >/dev/null

MNT="/run/media/$OWNER/$LABEL"
mkdir -p "$MNT"
UID_N=$(id -u "$OWNER"); GID_N=$(id -g "$OWNER")
mount -o "uid=$UID_N,gid=$GID_N,umask=077" "$PART" "$MNT"

echo
echo "==> ready and mounted, owned by $OWNER:"
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS "$MNT"
echo
echo "Now write the key to it (as yourself, not root):"
echo "    ./build/backup-master-key.sh $MNT"

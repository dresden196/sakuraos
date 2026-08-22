#!/bin/bash
# Exercise snapshot listing and rollback against a real btrfs filesystem.
#
# Runs inside a privileged container against a loop-mounted image, so it never
# touches the developer's disks. Invoke via tests/run.sh.
set -euo pipefail

IMG=/tmp/sakura-test.btrfs
TOP=/mnt/top
PASS=0
FAIL=0

check() {
    if [ "$2" = "$3" ]; then
        echo "  PASS  $1"
        PASS=$((PASS + 1))
    else
        echo "  FAIL  $1"
        echo "          expected: $2"
        echo "          actual:   $3"
        FAIL=$((FAIL + 1))
    fi
}

echo "== building a btrfs filesystem with snapshots =="
rm -f "$IMG"
truncate -s 1G "$IMG"
mkfs.btrfs -q "$IMG"
mkdir -p "$TOP"
mount -o loop "$IMG" "$TOP"
trap 'umount -R "$TOP" 2>/dev/null || true; rm -f "$IMG"' EXIT

btrfs subvolume create "$TOP/@" >/dev/null
btrfs subvolume create "$TOP/@snapshots" >/dev/null

# Snapshot 1: the good state.
echo "good" > "$TOP/@/state"
mkdir -p "$TOP/@snapshots/1"
btrfs subvolume snapshot -r "$TOP/@" "$TOP/@snapshots/1/snapshot" >/dev/null
cat > "$TOP/@snapshots/1/info.xml" <<'XML'
<?xml version="1.0"?>
<snapshot>
  <type>pre</type>
  <num>1</num>
  <date>2026-08-19 20:31:00</date>
  <description>before installing nvidia 580</description>
</snapshot>
XML

# Snapshot 2: still fine.
echo "also good" > "$TOP/@/state"
mkdir -p "$TOP/@snapshots/2"
btrfs subvolume snapshot -r "$TOP/@" "$TOP/@snapshots/2/snapshot" >/dev/null
cat > "$TOP/@snapshots/2/info.xml" <<'XML'
<?xml version="1.0"?>
<snapshot>
  <type>pre</type>
  <num>2</num>
  <date>2026-08-22 15:04:33</date>
  <description>before installing 14 updates</description>
</snapshot>
XML

# A half-deleted snapshot: directory and metadata present, subvolume gone.
# Offering this in the menu would produce a rollback that restores nothing.
mkdir -p "$TOP/@snapshots/3"
cat > "$TOP/@snapshots/3/info.xml" <<'XML'
<?xml version="1.0"?>
<snapshot>
  <type>pre</type>
  <num>3</num>
  <date>2026-08-22 16:00:00</date>
  <description>half-deleted, must not be offered</description>
</snapshot>
XML

# A stray directory that is not a snapshot at all.
mkdir -p "$TOP/@snapshots/notanumber"

# The current, broken state.
echo "broken" > "$TOP/@/state"

echo
echo "== listing =="
. /usr/lib/sakura/snapshot-boot/lib.sh
LIST=$(sakura_list_snapshots "$TOP/@snapshots")
echo "$LIST" | sed 's/^/  | /'

check "newest snapshot listed first" "2" "$(echo "$LIST" | head -1 | cut -f1)"
check "both valid snapshots listed"  "2" "$(echo "$LIST" | grep -c .)"
check "half-deleted snapshot skipped" "0" "$(echo "$LIST" | cut -f1 | grep -c '^3$' || true)"
check "non-numeric directory skipped" "0" "$(echo "$LIST" | grep -c notanumber || true)"
check "description parsed"           "before installing 14 updates" \
                                     "$(echo "$LIST" | head -1 | cut -f4)"

echo
echo "== rollback to snapshot 1 =="
check "state is broken before rollback" "broken" "$(cat "$TOP/@/state")"

/usr/lib/sakura/snapshot-boot/sakura-rollback "$TOP" 1 | sed 's/^/  | /'

check "root restored from snapshot"  "good"   "$(cat "$TOP/@/state")"
check "root is writable after rollback" "yes" \
      "$(touch "$TOP/@/writetest" 2>/dev/null && echo yes || echo no)"

PRESERVED=$(find "$TOP" -maxdepth 1 -name '@rollback-*' | head -1)
check "previous root preserved"      "broken" "$(cat "$PRESERVED/state" 2>/dev/null)"

echo
echo "== rolling back twice does not collide =="
# The initramfs has no date(1), so both rollbacks fall back to the same base
# name. The second must find a free one rather than failing halfway.
echo "second" > "$TOP/@/state"
PATH_NO_DATE=$(mktemp -d)
for cmd in btrfs mv rm mkdir cat awk sed grep head sort ls test; do
    src=$(command -v $cmd 2>/dev/null) && ln -sf "$src" "$PATH_NO_DATE/$cmd"
done
PATH="$PATH_NO_DATE" /usr/lib/sakura/snapshot-boot/sakura-rollback "$TOP" 2 2>&1 | sed 's/^/  | /'
check "second rollback succeeded" "also good" "$(cat "$TOP/@/state")"
check "both preserved roots kept" "2" \
      "$(find "$TOP" -maxdepth 1 -name '@rollback-*' | grep -c . || true)"
rm -rf "$PATH_NO_DATE"

echo
echo "== refuses a snapshot that does not exist =="
if /usr/lib/sakura/snapshot-boot/sakura-rollback "$TOP" 99 >/dev/null 2>&1; then
    check "rollback to missing snapshot fails" "fails" "succeeded"
else
    check "rollback to missing snapshot fails" "fails" "fails"
fi

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

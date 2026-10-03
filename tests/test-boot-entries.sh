#!/bin/bash
# Verify the generated limine.conf.
set -euo pipefail

ESP=$(mktemp -d)
trap 'rm -rf "$ESP"' EXIT
PASS=0; FAIL=0

check() {
    if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1))
    else echo "  FAIL  $1"; echo "          expected: $2"; echo "          actual:   $3"; FAIL=$((FAIL+1)); fi
}

mkdir -p "$ESP/EFI/sakura"

echo "== refuses to run without a kernel image =="
if SAKURA_ESP="$ESP" sakura-boot-entries >/dev/null 2>&1; then
    check "missing sakura.efi is fatal" "fails" "succeeded"
else
    check "missing sakura.efi is fatal" "fails" "fails"
fi

: > "$ESP/EFI/sakura/sakura.efi"

echo
echo "== without a recovery image =="
SAKURA_ESP="$ESP" sakura-boot-entries >/dev/null
check "one entry only" "1" "$(grep -c '^/' "$ESP/limine.conf")"
check "no recovery entry" "0" "$(grep -c '^/SakuraOS Recovery$' "$ESP/limine.conf" || true)"

echo
echo "== with a recovery image =="
: > "$ESP/EFI/sakura/sakura-recovery.efi"
SAKURA_ESP="$ESP" SAKURA_BOOT_TIMEOUT=7 sakura-boot-entries >/dev/null
cat "$ESP/limine.conf" | sed 's/^/  | /'

check "two entries"        "2"   "$(grep -c '^/' "$ESP/limine.conf")"
check "system entry first" "/SakuraOS" "$(grep -m1 '^/' "$ESP/limine.conf")"
check "recovery present"   "1"   "$(grep -c '^/SakuraOS Recovery$' "$ESP/limine.conf")"
check "timeout honoured"   "timeout: 7" "$(grep '^timeout:' "$ESP/limine.conf")"
check "efi protocol used"  "2"   "$(grep -c 'protocol: efi' "$ESP/limine.conf")"

# The whole point of the recovery design: no per-snapshot entries, because a
# UKI ignores a loader-supplied cmdline under Secure Boot. If someone ever adds
# cmdline lines here, that silent-failure mode comes back.
check "no cmdline overrides" "0" "$(grep -c 'cmdline' "$ESP/limine.conf" || true)"

echo
echo "== regeneration is atomic and idempotent =="
BEFORE=$(cat "$ESP/limine.conf")
SAKURA_ESP="$ESP" SAKURA_BOOT_TIMEOUT=7 sakura-boot-entries >/dev/null
check "identical on rerun" "$BEFORE" "$(cat "$ESP/limine.conf")"
check "no temp files left" "0" "$(find "$ESP" -name 'limine.conf.*' | grep -c . || true)"

echo
echo "== other systems on the same EFI partition =="
# Windows beside us: its boot manager, and the copy of it Windows keeps at
# the removable path. One menu entry, not two.
mkdir -p "$ESP/EFI/Microsoft/Boot" "$ESP/EFI/Boot"
printf 'MZ windows boot manager' > "$ESP/EFI/Microsoft/Boot/bootmgfw.efi"
cp "$ESP/EFI/Microsoft/Boot/bootmgfw.efi" "$ESP/EFI/Boot/bootx64.efi"
SAKURA_ESP="$ESP" sakura-boot-entries >/dev/null
check "Windows offered once"            "1" "$(grep -c '^/Windows Boot Manager$' "$ESP/limine.conf")"
check "its fallback copy not offered"   "0" "$(grep -c '^/Other operating system$' "$ESP/limine.conf" || true)"

# Our own fallback copy, signed separately from limine.efi so the bytes
# differ: still ours, still not offered as another system.
printf 'MZ Limine 12.9.1 signed copy' > "$ESP/EFI/Boot/bootx64.efi"
printf 'MZ Limine 12.9.1' > "$ESP/EFI/sakura/limine.efi"
SAKURA_ESP="$ESP" sakura-boot-entries >/dev/null
check "our signed fallback not offered" "0" "$(grep -c '^/Other operating system$' "$ESP/limine.conf" || true)"

# Something else entirely at the removable path is a real other system.
printf 'MZ some other loader' > "$ESP/EFI/Boot/bootx64.efi"
SAKURA_ESP="$ESP" sakura-boot-entries >/dev/null
check "an unknown loader is offered"    "1" "$(grep -c '^/Other operating system$' "$ESP/limine.conf")"
rm -rf "$ESP/EFI/Microsoft" "$ESP/EFI/Boot"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

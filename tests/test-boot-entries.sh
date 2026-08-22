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
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

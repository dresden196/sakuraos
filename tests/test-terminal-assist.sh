#!/bin/bash
# Terminal Assist: the unbypassable pacman-hook layer.
set -uo pipefail

CHECK=/usr/lib/sakura/terminal-assist/alpm-check
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

check() {
    if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1))
    else echo "  FAIL  $1"; echo "          expected: $2"; echo "          actual:   $3"; FAIL=$((FAIL+1)); fi
}

# A local package database resembling a real install.
DB="$TMP/local"; mkdir -p "$DB"
for p in systemd-261.2-1 glibc-2.44-1 pacman-7.1.0-2 bash-5.3.15-1 \
         linux-7.1.8.arch1-3 sakura-snapshot-boot-0.1.0-1 htop-3.4.1-1 \
         cowsay-3.8.4-1; do
    mkdir -p "$DB/$p"
done

conf() { printf '[TerminalAssist]\nMode=%s\n' "$1" > "$TMP/sakura.conf"; }

run() {  # run <targets...>  -> sets RC and OUT
    OUT=$(printf '%s\n' "$@" | SAKURA_CONFIG="$TMP/sakura.conf" SAKURA_LOCAL_DB="$DB" "$CHECK" 2>&1)
    RC=$?
}

echo "== mode: block =="
conf block

run cowsay
check "harmless removal allowed" "0" "$RC"

run systemd
check "removing systemd blocked" "1" "$RC"
check "explains why" "1" "$(echo "$OUT" | grep -c 'the machine will not boot' || true)"

run sakura-snapshot-boot
check "removing rollback tooling blocked" "1" "$RC"

run linux
check "removing the only kernel blocked" "1" "$RC"

run htop cowsay
check "several harmless removals allowed" "0" "$RC"

run htop systemd
check "one bad target in a batch blocks it" "1" "$RC"

echo
echo "== a second kernel makes removal safe =="
mkdir -p "$DB/linux-lts-6.12.4-1"
run linux
check "removing one of two kernels allowed" "0" "$RC"
run linux linux-lts
check "removing both kernels blocked" "1" "$RC"
rm -rf "$DB/linux-lts-6.12.4-1"

echo
echo "== overrides waive only the rule they name =="
run systemd
check "blocked without an override" "1" "$RC"

OUT=$(printf 'systemd\n' | SAKURA_CONFIG="$TMP/sakura.conf" SAKURA_LOCAL_DB="$DB" \
      SAKURA_ASSIST_OVERRIDE=remove-critical "$CHECK" 2>&1); RC=$?
check "correct rule name allows it" "0" "$RC"

OUT=$(printf 'systemd\n' | SAKURA_CONFIG="$TMP/sakura.conf" SAKURA_LOCAL_DB="$DB" \
      SAKURA_ASSIST_OVERRIDE=1 "$CHECK" 2>&1); RC=$?
check "a junk override does NOT bypass" "1" "$RC"

OUT=$(printf 'systemd\n' | SAKURA_CONFIG="$TMP/sakura.conf" SAKURA_LOCAL_DB="$DB" \
      SAKURA_ASSIST_OVERRIDE=remove-last-kernel "$CHECK" 2>&1); RC=$?
check "wrong rule name does NOT bypass" "1" "$RC"

# systemd trips remove-critical; linux trips both remove-critical and
# remove-last-kernel. Waiving one must not waive the other.
OUT=$(printf 'systemd\nlinux\n' | SAKURA_CONFIG="$TMP/sakura.conf" SAKURA_LOCAL_DB="$DB" \
      SAKURA_ASSIST_OVERRIDE=remove-critical "$CHECK" 2>&1); RC=$?
check "partial override still blocks the rest" "1" "$RC"

OUT=$(printf 'systemd\nlinux\n' | SAKURA_CONFIG="$TMP/sakura.conf" SAKURA_LOCAL_DB="$DB" \
      SAKURA_ASSIST_OVERRIDE=remove-critical,remove-last-kernel "$CHECK" 2>&1); RC=$?
check "waiving every rule allows it" "0" "$RC"

echo
echo "== modes =="
conf warn
run systemd
check "warn mode does not block" "0" "$RC"
check "warn mode still explains" "yes" \
      "$(echo "$OUT" | grep -q 'Terminal Assist' && echo yes || echo no)"

conf off
run systemd
check "off mode is silent" "0" "$RC"
check "off mode prints nothing" "" "$OUT"

echo
echo "== a broken config must not take pacman down =="
printf 'this is not\nvalid ini [[[\n' > "$TMP/sakura.conf"
run systemd
check "unparseable config fails closed (blocks)" "1" "$RC"

rm -f "$TMP/sakura.conf"
run systemd
check "missing config fails closed (blocks)" "1" "$RC"

run cowsay
check "missing config still allows safe removals" "0" "$RC"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

#!/bin/bash
# The privileged settings writer. Runs as root on input from an unprivileged
# process, so what it REFUSES matters more than what it accepts.
set -uo pipefail

W=/usr/lib/sakura/settings/sakura-settings-write
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
CONF="$TMP/sakura.conf"
PASS=0; FAIL=0

check() {
    if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1))
    else echo "  FAIL  $1"; echo "          expected: $2"; echo "          actual:   $3"; FAIL=$((FAIL+1)); fi
}

seed() {
    cat > "$CONF" <<'INI'
# A comment the admin wrote and would be annoyed to lose.

[TerminalAssist]
# Explains the modes.
Mode=block

[AUR]
Enabled=false
Helper=yay
INI
}

# Takes the payload as an argument: piping into the function would run it
# in a subshell and RC would never make it back to the caller.
run() { OUT=$(printf '%s\n' "$1" | SAKURA_CONFIG="$CONF" "$W" 2>&1); RC=$?; }
val() { grep -A20 "^\[$1\]" "$CONF" | grep -m1 "^$2=" | cut -d= -f2; }

echo "== rejects anything not in the schema =="
seed
run 'TerminalAssist.Mode=block
Evil.Key=value'
check "unknown section rejected" "1" "$RC"
check "  and says which one"     "1" "$(echo "$OUT" | grep -c 'not a writable setting: Evil.Key' || true)"

run 'AUR.Enabled=true; rm -rf /'
check "shell metacharacters rejected" "1" "$RC"

run 'TerminalAssist.Mode=../../etc/passwd'
check "path traversal in a value rejected" "1" "$RC"

run 'TerminalAssist.Mode=disabled'
check "value outside the enum rejected" "1" "$RC"

run 'Updates.Window=25:00'
check "impossible time rejected" "1" "$RC"

run 'Updates.Window=3am'
check "non-time rejected" "1" "$RC"

run 'AUR.Enabled=yes'
check "non-boolean rejected" "1" "$RC"

run 'garbage with no equals'
check "malformed line rejected" "1" "$RC"

echo "== a rejected write changes nothing on disk =="
seed
BEFORE=$(cat "$CONF")
run 'TerminalAssist.Mode=warn
Evil.Key=x'
check "partial-valid input writes nothing" "$BEFORE" "$(cat "$CONF")"

echo
echo "== accepts valid input =="
seed
run 'TerminalAssist.Mode=warn
AUR.Enabled=true
Updates.Window=03:30'
check "valid write succeeds"     "0" "$RC"
check "mode updated"             "warn" "$(val TerminalAssist Mode)"
check "aur updated"              "true" "$(val AUR Enabled)"
check "untouched key preserved"  "yay"  "$(val AUR Helper)"
check "new key appended"         "03:30" "$(val Updates Window)"

echo
echo "== comments survive =="
check "admin comment kept" "1" "$(grep -c 'would be annoyed to lose' "$CONF" || true)"
check "section comment kept" "1" "$(grep -c 'Explains the modes' "$CONF" || true)"

echo
echo "== result is still parseable by the pacman hook =="
MODE=$(SAKURA_CONFIG="$CONF" SAKURA_LOCAL_DB="$TMP/nodb" python3 - <<'PY'
import importlib.util
from importlib.machinery import SourceFileLoader

# alpm-check has no .py extension, so the loader has to be named explicitly.
path = "/usr/lib/sakura/terminal-assist/alpm-check"
spec = importlib.util.spec_from_loader("ac", SourceFileLoader("ac", path))
ac = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ac)
print(ac.read_mode())
PY
)
check "hook reads back what the UI wrote" "warn" "$MODE"

echo
echo "== a torn write cannot happen =="
seed
run 'TerminalAssist.Mode=off'
check "no temp files left behind" "0" "$(find "$TMP" -name '.sakura.conf.*' | grep -c . || true)"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

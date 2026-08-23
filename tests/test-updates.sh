#!/bin/bash
# The update engine's gate. What it REFUSES to hold matters as much as what it
# holds: Arch's manual-intervention notices never expire from the feed, so a
# gate that trips on any notice being present holds every update forever.
set -uo pipefail
PASS=0; FAIL=0
check(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1));
  else echo "  FAIL  $1"; echo "          expected: $2"; echo "          actual:   $3"; FAIL=$((FAIL+1)); fi; }

M=$(python3 - <<'PY'
import importlib.util, sys
from importlib.machinery import SourceFileLoader
path = "/usr/bin/sakura-update"
loader = SourceFileLoader("su", path)
spec = importlib.util.spec_from_file_location("su", path, loader=loader)
m = importlib.util.module_from_spec(spec)
# @dataclass resolves its own module through sys.modules, so a dynamically
# loaded module has to be registered there before it is executed.
sys.modules["su"] = m
spec.loader.exec_module(m)

cases = [
    # (headline, package, should_match)
    ("dovecot >= 2.4 requires manual intervention", "dovecot", True),
    ("kea >= 1:3.0.3-6 update requires manual intervention", "kea", True),
    ("Breaking changes for all users of `varnish`", "varnish", True),
    ("virtualbox-ext-vnc >= 7.2.12-2 requires manual intervention", "virtualbox-ext-vnc", True),
    ("NVIDIA 590 driver drops Pascal and lower support", "nvidia-open", True),
    # The critical negatives: an unrelated notice must not hold an unrelated
    # package, or nothing ever updates again.
    ("dovecot >= 2.4 requires manual intervention", "firefox", False),
    ("kea >= 1:3.0.3-6 update requires manual intervention", "jq", False),
    (".NET packages may require manual intervention", "libdeflate", False),
    ("Breaking changes for all users of `varnish`", "iana-etc", False),
    # A short stem must not match loosely -- "kea" inside "keayboard" etc.
    ("kea >= 1:3.0.3-6 requires manual intervention", "keepassxc", False),
]
bad = [f"{p}|{t[:34]}" for t, p, want in cases if m._mentions(t, p) != want]
print(";".join(bad) if bad else "OK")
PY
)
check "notice matching is exact where it must be" "OK" "$M"

echo
echo "== config parsing survives a broken file =="
mkdir -p /tmp/uc && printf 'garbage [[[\nnot ini\n' > /tmp/uc/sakura.conf
R=$(SAKURA_CONFIG=/tmp/uc/sakura.conf python3 - <<'PY'
import importlib.util, sys
from importlib.machinery import SourceFileLoader
loader = SourceFileLoader("su", "/usr/bin/sakura-update")
spec = importlib.util.spec_from_file_location("su", "/usr/bin/sakura-update", loader=loader)
m = importlib.util.module_from_spec(spec)
# @dataclass resolves its own module through sys.modules, so a dynamically
# loaded module has to be registered there before it is executed.
sys.modules["su"] = m
spec.loader.exec_module(m)
print(m.read_config().get("Window", "MISSING"))
PY
)
check "falls back to defaults, does not crash" "03:00" "$R"

echo
echo "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]

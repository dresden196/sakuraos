#!/usr/bin/env bash
# Send key presses to the test VM over QMP.
#
# Needed for driving UI that has no scriptable interface -- maximising a
# window, scrolling a settings page, stepping through an installer.
#
#   ./build/sendkeys.sh super-up          maximise the focused window
#   ./build/sendkeys.sh pgdn pgdn         scroll down twice
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -gt 0 ]] || { echo "usage: sendkeys.sh <key> [key...]" >&2; exit 1; }

exec python3 - "$REPO_ROOT/out/qmp.sock" "$@" <<'PY'
import json, socket, sys, time

sock_path, keys = sys.argv[1], sys.argv[2:]
s = socket.socket(socket.AF_UNIX)
s.connect(sock_path)
f = s.makefile("rw", encoding="utf-8", newline="\n")


def cmd(name, **args):
    f.write(json.dumps({"execute": name, "arguments": args} if args
                       else {"execute": name}) + "\n")
    f.flush()
    while True:
        msg = json.loads(f.readline() or "{}")
        if "return" in msg or "error" in msg:
            return msg


f.readline()  # greeting
cmd("qmp_capabilities")

for combo in keys:
    # "super-up" becomes a chord; a bare name is a single key.
    parts = [{"type": "qcode", "data": part} for part in combo.split("-")]
    r = cmd("input-send-event", events=[
        {"type": "key", "data": {"down": True, "key": p}} for p in parts
    ] + [
        {"type": "key", "data": {"down": False, "key": p}} for p in reversed(parts)
    ])
    if "error" in r:
        sys.exit(f"{combo}: {r['error']['desc']}")
    time.sleep(0.3)
PY

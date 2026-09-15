#!/usr/bin/env bash
# Click somewhere in the test VM's screen, over QMP.
#
# The companion to sendkeys.sh, and needed for the same reason: some things
# have no scriptable interface. A store that can install several applications
# at once can only be shown doing it by asking for several installs, and the
# only way to ask is to press the buttons.
#
#   ./build/sendclick.sh 772 650          click at those screen coordinates
#   ./build/sendclick.sh 772 650 400 300  click twice, in order
#
# Absolute coordinates, because test-vm.sh gives the guest a usb-tablet rather
# than a relative mouse. With a relative device these numbers would mean
# "move this far from wherever the pointer happens to be", which is not
# something a script can know.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -ge 2 ]] || { echo "usage: sendclick.sh <x> <y> [<x> <y>...]" >&2; exit 1; }

exec python3 - "$REPO_ROOT/out/qmp-${SAKURA_VM:-test}.sock" "$@" <<'PY'
import json, socket, sys, time

sock_path, coords = sys.argv[1], sys.argv[2:]
if len(coords) % 2:
    sys.exit("sendclick: coordinates come in pairs")

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


f.readline()
cmd("qmp_capabilities")

for i in range(0, len(coords), 2):
    x, y = int(coords[i]), int(coords[i + 1])
    # Move first, settle, then click. Sent as one event the pointer sometimes
    # arrives after the button does, and the click lands wherever it used to
    # be -- which looks like the button simply not working.
    cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": int(x * 32767 / 1920)}},
        {"type": "abs", "data": {"axis": "y", "value": int(y * 32767 / 1080)}},
    ])
    time.sleep(0.25)
    cmd("input-send-event", events=[
        {"type": "btn", "data": {"down": True, "button": "left"}}])
    time.sleep(0.08)
    cmd("input-send-event", events=[
        {"type": "btn", "data": {"down": False, "button": "left"}}])
    time.sleep(0.6)

print(f"clicked {len(coords)//2} time(s)")
PY

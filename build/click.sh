#!/usr/bin/env bash
# Click somewhere in the test VM, in screen pixel coordinates.
#
#   ./build/click.sh 1383 820          click once
#   ./build/click.sh 1383 820 640 400  click twice, in order
#
# Needed to drive UI that has no scriptable interface. Coordinates are the
# ones you read off a screenshot; the conversion to QEMU's absolute axis
# range happens here.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIDTH="${SAKURA_VM_WIDTH:-1920}"
HEIGHT="${SAKURA_VM_HEIGHT:-1080}"

exec python3 - "$REPO_ROOT/out/qmp-${SAKURA_VM:-test}.sock" "$WIDTH" "$HEIGHT" "$@" <<'PY'
import json, socket, sys, time

sock_path, width, height, *coords = sys.argv[1:]
width, height = int(width), int(height)
if len(coords) % 2:
    sys.exit("coordinates must come in x y pairs")

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

# QEMU's absolute pointer axis is a fixed 0..32767 range regardless of the
# guest resolution, so screen pixels have to be scaled into it.
SPAN = 32767
for x, y in zip(coords[::2], coords[1::2]):
    ax = int(int(x) * SPAN / width)
    ay = int(int(y) * SPAN / height)
    r = cmd("input-send-event", events=[
        {"type": "abs", "data": {"axis": "x", "value": ax}},
        {"type": "abs", "data": {"axis": "y", "value": ay}},
    ])
    if "error" in r:
        sys.exit(r["error"]["desc"])
    time.sleep(0.15)
    cmd("input-send-event", events=[{"type": "btn", "data": {"down": True, "button": "left"}}])
    time.sleep(0.08)
    cmd("input-send-event", events=[{"type": "btn", "data": {"down": False, "button": "left"}}])
    time.sleep(0.45)
PY

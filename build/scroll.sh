#!/usr/bin/env bash
# Scroll the test VM's pointer wheel at a screen position.
#
#   ./build/scroll.sh 1000 600 down 8    eight notches down at (1000,600)
#   ./build/scroll.sh 1000 600 up 4
#
# Page Up / Page Down only work when the scrollable view happens to hold
# keyboard focus, which in a QML application it usually does not -- the wheel
# is what a person would actually use, and it is what this sends.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIDTH="${SAKURA_VM_WIDTH:-1920}"
HEIGHT="${SAKURA_VM_HEIGHT:-1080}"
X="${1:?usage: scroll.sh <x> <y> [up|down] [notches]}"
Y="${2:?usage: scroll.sh <x> <y> [up|down] [notches]}"
DIR="${3:-down}"
N="${4:-5}"

exec python3 - "$REPO_ROOT/out/qmp-${SAKURA_VM:-test}.sock" "$WIDTH" "$HEIGHT" "$X" "$Y" "$DIR" "$N" <<'PY'
import json, socket, sys, time

sock_path, width, height, x, y, direction, notches = sys.argv[1:]
width, height, x, y, notches = int(width), int(height), int(x), int(y), int(notches)

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

SPAN = 32767
cmd("input-send-event", events=[
    {"type": "abs", "data": {"axis": "x", "value": int(x * SPAN / width)}},
    {"type": "abs", "data": {"axis": "y", "value": int(y * SPAN / height)}},
])
time.sleep(0.15)

button = "wheel-down" if direction == "down" else "wheel-up"
for _ in range(notches):
    r = cmd("input-send-event", events=[
        {"type": "btn", "data": {"down": True, "button": button}},
        {"type": "btn", "data": {"down": False, "button": button}},
    ])
    if "error" in r:
        sys.exit(r["error"]["desc"])
    time.sleep(0.12)
PY

#!/usr/bin/env bash
# Send key presses to the test VM over QMP.
#
# Needed for driving UI that has no scriptable interface -- maximising a
# window, scrolling a settings page, stepping through an installer.
#
#   ./build/sendkeys.sh super-up          maximise the focused window
#   ./build/sendkeys.sh pgdn pgdn         scroll down twice
#   ./build/sendkeys.sh --type hello123   type a string
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# -gt 0 ]] || { echo "usage: sendkeys.sh <key> [key...]" >&2; exit 1; }

exec python3 - "$REPO_ROOT/out/qmp-${SAKURA_VM:-test}.sock" "$@" <<'PY'
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

# --type takes the rest as literal text. Only the characters an installer
# actually needs: usernames, hostnames and passwords typed during a test run.
if keys and keys[0] == "--type":
    literal = " ".join(keys[1:])
    SHIFTED = {c: c for c in ""}
    out = []
    for ch in literal:
        if ch.islower() or ch.isdigit():
            out.append((ch, False))
        elif ch.isupper():
            out.append((ch.lower(), True))
        elif ch == " ":
            out.append(("spc", False))
        elif ch == ".":
            out.append(("dot", False))
        elif ch == "-":
            out.append(("minus", False))
        elif ch == "_":
            out.append(("minus", True))
        else:
            sys.exit(f"unsupported character for --type: {ch!r}")
    for code, shift in out:
        events = []
        if shift:
            events.append({"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": "shift"}}})
        events.append({"type": "key", "data": {"down": True, "key": {"type": "qcode", "data": code}}})
        events.append({"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": code}}})
        if shift:
            events.append({"type": "key", "data": {"down": False, "key": {"type": "qcode", "data": "shift"}}})
        r = cmd("input-send-event", events=events)
        if "error" in r:
            sys.exit(f"{code}: {r['error']['desc']}")
        time.sleep(0.05)
    raise SystemExit(0)

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

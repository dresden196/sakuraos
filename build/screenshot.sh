#!/usr/bin/env bash
# Capture the test VM's screen over QMP.
#
# Works whenever test-vm.sh is running without --gl. Under --gl the guest
# framebuffer is a host GPU dmabuf and QEMU reports "no surface".
#
#   ./build/screenshot.sh /tmp/plasma.png
#
# If the guest has blanked its screen the capture is a black frame reading
# "Display output is not active", which looks exactly like the application
# under test having failed to draw. That has cost real debugging time more
# than once, so this wakes the screen and retries rather than handing back a
# picture of nothing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: screenshot.sh <output.png>}"
[[ "$OUT" = /* ]] || OUT="$PWD/$OUT"

# Capture into a temporary file first so a blanked screen can be detected and
# retried. kscreen-doctor still reports the output as enabled when DPMS has
# turned it off, and KWin exposes no DPMS object on this session, so the frame
# itself is the only honest signal: the "not active" placeholder is a nearly
# uniform image that compresses to a few kilobytes, against ~2.5 MB for a real
# desktop. Three orders of magnitude is a safe threshold.
BLANK_MAX_BYTES=65536
TMP="$(mktemp --suffix=.png)"
trap 'rm -f "$TMP"' EXIT

capture() { "$REPO_ROOT/build/qmp-screendump.sh" "$1" >/dev/null; }

capture "$TMP"
if [[ $(stat -c %s "$TMP") -lt $BLANK_MAX_BYTES ]]; then
    echo ">> guest screen appears blanked; waking it and retrying" >&2
    "$REPO_ROOT/build/guest-run.sh" \
        "runuser -u sakura -- env XDG_RUNTIME_DIR=/run/user/1000 \
         WAYLAND_DISPLAY=wayland-0 kscreen-doctor output.Virtual-1.enable" \
        >/dev/null 2>&1 || true
    "$REPO_ROOT/build/sendkeys.sh" shift >/dev/null 2>&1 || true
    sleep 4
    capture "$TMP"
    if [[ $(stat -c %s "$TMP") -lt $BLANK_MAX_BYTES ]]; then
        echo "screen is still blank after waking it -- the session may be dead" >&2
    fi
fi
mv "$TMP" "$OUT"
trap - EXIT
echo "$OUT"
exit 0

exec python3 - "$REPO_ROOT/out/qmp.sock" "$OUT" <<'PY'
import json, socket, sys

sock_path, out = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX)
s.connect(sock_path)
f = s.makefile("rw", encoding="utf-8", newline="\n")


def cmd(name, **args):
    f.write(json.dumps({"execute": name, "arguments": args}) + "\n")
    f.flush()
    while True:
        msg = json.loads(f.readline() or "{}")
        if "return" in msg or "error" in msg:
            return msg


f.readline()  # QMP greeting
cmd("qmp_capabilities")
r = cmd("screendump", filename=out, format="png")
if "error" in r:
    # QEMU older than 8.0 only knows PPM.
    r = cmd("screendump", filename=out)
if "error" in r:
    sys.exit(r["error"]["desc"])
print(out)
PY

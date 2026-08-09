#!/usr/bin/env bash
# Capture the test VM's screen over QMP.
#
# Works whenever test-vm.sh is running without --gl. Under --gl the guest
# framebuffer is a host GPU dmabuf and QEMU reports "no surface".
#
#   ./build/screenshot.sh /tmp/plasma.png
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: screenshot.sh <output.png>}"
[[ "$OUT" = /* ]] || OUT="$PWD/$OUT"

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

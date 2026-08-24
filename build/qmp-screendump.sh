#!/usr/bin/env bash
# The raw QMP screendump, with no blank-screen handling. Use screenshot.sh
# instead unless you specifically want the frame exactly as QEMU reports it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:?usage: qmp-screendump.sh <output.png>}"
[[ "$OUT" = /* ]] || OUT="$PWD/$OUT"

exec python3 - "$REPO_ROOT/out/qmp-${SAKURA_VM:-test}.sock" "$OUT" <<'PY'
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

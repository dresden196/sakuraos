#!/usr/bin/env bash
# Copy a file from the host into the running test VM.
#
# Closes the UI iteration loop: rebuilding an ISO to look at a changed dialog
# is a ten minute round trip, and nobody iterates on a design at that speed.
# Goes over the guest agent, so it needs no network or credentials.
#
#   ./build/guest-push.sh ./thing.so /usr/lib/thing.so
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: guest-push.sh <local-file> <guest-path>}"
DEST="${2:?usage: guest-push.sh <local-file> <guest-path>}"

# base64 through guest-exec: the agent's file-write API needs a handle dance,
# and a shell pipeline is both simpler and easier to see failing.
B64=$(base64 -w0 "$SRC")
SIZE=${#B64}

if (( SIZE > 6000000 )); then
    echo "file too large to push this way ($((SIZE / 1024)) KiB encoded)" >&2
    exit 1
fi

"$REPO_ROOT/build/guest-run.sh" "
    mkdir -p '$(dirname "$DEST")'
    printf '%s' '$B64' | base64 -d > '$DEST.tmp'
    mv '$DEST.tmp' '$DEST'
    printf 'pushed %s (%s bytes)\n' '$DEST' \"\$(stat -c%s '$DEST')\"
"

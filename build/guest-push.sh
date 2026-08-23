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
RUN="$REPO_ROOT/build/guest-run.sh"

# Sent in chunks: the whole payload has to fit on a command line, and a
# binary of any size does not. 48 KB per chunk leaves comfortable room under
# the limit once base64 expansion and the shell wrapper are accounted for.
CHUNK=49152

B64=$(base64 -w0 "$SRC")
TOTAL=${#B64}
PARTS=$(( (TOTAL + CHUNK - 1) / CHUNK ))

"$RUN" "mkdir -p '$(dirname "$DEST")'; : > '$DEST.b64'" >/dev/null

i=0
off=0
while (( off < TOTAL )); do
    part="${B64:off:CHUNK}"
    # printf rather than echo: the payload is base64, but a leading dash or a
    # backslash would still be interpreted by echo on some shells.
    "$RUN" "printf '%s' '$part' >> '$DEST.b64'" >/dev/null
    off=$(( off + CHUNK ))
    i=$(( i + 1 ))
    printf "\r  pushing %s: %d/%d" "$(basename "$DEST")" "$i" "$PARTS" >&2
done
printf "\r" >&2

"$RUN" "
    base64 -d < '$DEST.b64' > '$DEST.tmp'
    rm -f '$DEST.b64'
    mv '$DEST.tmp' '$DEST'
    printf 'pushed %s (%s bytes)\n' '$DEST' \"\$(stat -c%s '$DEST')\"
"

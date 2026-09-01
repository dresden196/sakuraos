#!/usr/bin/env bash
# Run the canary inside its container, from the host.
#
# The timer lives on the hypervisor rather than in the container so that the
# container being down is itself reportable. A timer inside a stopped
# container does not fire and does not complain, and a canary nobody knows
# has stopped is worse than no canary: its last advisory keeps holding
# packages until it ages out.
set -uo pipefail

CTID="${SAKURA_CANARY_CTID:-9002}"
NOTIFY=/usr/local/bin/sakura-canary-notify

# Only the failures the canary itself cannot report. When the canary runs and
# exits non-zero it has already sent its own alert, and a second one from out
# here is two notifications for one fault -- which is how people learn to
# swipe alerts away without reading them.
fail_outer() {
    echo "canary-run: $*" >&2
    [[ -x "$NOTIFY" ]] && "$NOTIFY" stalled "$*" "" /dev/null || true
    exit 1
}

pct status "$CTID" 2>/dev/null | grep -q running \
    || pct start "$CTID" \
    || fail_outer "canary container $CTID is not running and would not start"

for _ in $(seq 30); do
    pct exec "$CTID" -- /usr/bin/curl -sS -m 5 -o /dev/null https://archlinux.org/ 2>/dev/null && break
    sleep 2
done

pct exec "$CTID" -- /usr/bin/env PUBLISH=1 PATH=/usr/local/bin:/usr/bin:/bin \
    /srv/sakura-canary/build/canary.sh
rc=$?

# 1 means the canary ran and reported for itself. Anything else means it never
# got far enough to, so this is the only chance to say so.
if [[ $rc -ne 0 && $rc -ne 1 ]]; then
    fail_outer "the canary could not be started inside the container (exit $rc)"
fi
exit $rc

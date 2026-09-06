#!/usr/bin/env bash
# Start the nightly canary and wait for it, from the Proxmox host.
#
# This does NOT run canary.sh through pct exec any more, which is what it used
# to do and why every nightly run failed. An exec'd command's process tree is
# torn down when the exec finishes, and the teardown is by cgroup, so setsid
# does not save it either: qemu took a SIGTERM part-way through and the run
# reported that the installed machine never came up. A manual run watched by a
# human looked fine, because the human's session stayed open.
#
# So the work belongs to the container's own systemd, and this script only
# starts that unit and waits. See sakura-canary-run.service inside 9002.
set -uo pipefail
CTID="${SAKURA_CANARY_CTID:-9002}"
UNIT=sakura-canary-run.service
NOTIFY=/usr/local/bin/sakura-canary-notify
# A run installs a machine, updates it, reboots it and re-checks it.
DEADLINE_MINUTES="${SAKURA_CANARY_DEADLINE:-180}"

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

# --no-block: the start returns as soon as systemd has accepted the job, so
# this exec is short-lived by design and there is no long-running process tree
# for its teardown to kill.
pct exec "$CTID" -- systemctl reset-failed "$UNIT" >/dev/null 2>&1 || true
pct exec "$CTID" -- systemctl start --no-block "$UNIT" \
    || fail_outer "could not start $UNIT inside container $CTID"

# Wait for it, polling from outside. Each poll is its own short exec.
waited=0
while :; do
    state="$(pct exec "$CTID" -- systemctl is-active "$UNIT" 2>/dev/null | tr -d '[:space:]')"
    [[ "$state" != "activating" ]] && break
    sleep 30
    waited=$(( waited + 30 ))
    if (( waited > DEADLINE_MINUTES * 60 )); then
        pct exec "$CTID" -- systemctl stop "$UNIT" >/dev/null 2>&1 || true
        fail_outer "the canary was still running after $DEADLINE_MINUTES minutes and was stopped"
    fi
done

rc="$(pct exec "$CTID" -- systemctl show "$UNIT" -p ExecMainStatus --value 2>/dev/null | tr -d '[:space:]')"
rc="${rc:-2}"

# 1 means the canary ran and published its own advisory and notification.
# Anything else means it never got far enough to speak for itself.
if [[ "$rc" != "0" && "$rc" != "1" ]]; then
    fail_outer "the canary exited $rc inside the container; see /srv/sakura-canary/out/run.log"
fi
exit "$rc"

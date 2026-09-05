#!/usr/bin/env bash
# Install every pending Arch update into a real SakuraOS machine, reboot it,
# and check it still works. Publish what broke.
#
# This is the evidence behind "updates are held until we have installed them
# ourselves". Without it that claim is marketing; the setting that consumes
# the feed already exists and had nothing to read.
#
# The machine under test is a VM installed from the current ISO. Updating a
# machine that was installed months ago would test a different thing -- an
# upgrade path rather than today's packages -- and the thing users hit first
# is today's packages on a current install.
#
#   ./build/canary.sh                 run once, write out/advisories.json
#   PUBLISH=1 ./build/canary.sh       and upload it to the repo host
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The same name test-install.sh uses. It exports SAKURA_VM=clean itself, so
# the base install always lands on sakura-clean.qcow2 -- and this script then
# booted sakura-canary.qcow2, a disk nothing had ever installed to. An empty
# disk has no guest agent, so the wait timed out and the canary reported that
# the installed machine had not come up. It had; this was looking at the
# wrong one.
export SAKURA_VM=clean
OUT="$REPO_ROOT/out/advisories.json"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
REPO_HOST="${REPO_HOST:-root@173.233.87.167}"
REPO_PORT="${REPO_PORT:-37156}"
REPO_PATH="${REPO_PATH:-/srv/sakura/repo/advisories.json}"

cleanup() { pkill -f "[s]akura-${SAKURA_VM}\.qcow2" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

say() { printf '\n>> %s\n' "$*"; }

# A canary that reports "everything is fine" because it never ran is worse
# than no canary, so every early exit here is a hard failure rather than an
# empty advisory file.
die() {
    echo "canary: $*" >&2
    "$REPO_ROOT/build/canary-notify.sh" stalled "$*" "" \
        "$REPO_ROOT/out/canary-install.log" 2>/dev/null || true
    exit 1
}

say "installing a fresh machine to update"
SAKURA_VM=clean METHOD=copy "$REPO_ROOT/build/test-install.sh" >"$REPO_ROOT/out/canary-install.log" 2>&1 \
    || die "the base install failed, so there is nothing to update. See out/canary-install.log"

# Wait for the install VM to actually let go of the disk.
#
# test-install.sh signals its VM and returns; qemu takes a moment to exit and
# release the image lock. Starting the next VM straight away fails with "Is
# another process using the image", which then presents as the installed
# machine never coming up. Signalling a process is not the same as it having
# gone.
for _i in $(seq 1 30); do
    if ! fuser "$REPO_ROOT/out/sakura-clean.qcow2" >/dev/null 2>&1; then
        break
    fi
    [[ $_i -eq 1 ]] && say "waiting for the install VM to release the disk"
    sleep 2
done

say "booting the installed machine"
# Keep the boot output. Discarding it cost several rounds of debugging: the
# VM failed to start and the only symptom was a wait that timed out fifteen
# minutes later, with nothing anywhere saying why.
# setsid, not a plain background job. Launched as an ordinary child the VM
# shares this session, and when the session that started the canary is torn
# down -- which pct exec does -- qemu takes a SIGTERM and dies while the
# canary carries on waiting for an agent that is never coming back. Observed
# directly: "qemu-system-x86_64: terminating on signal 15".
SAKURA_VM=clean setsid "$REPO_ROOT/build/test-vm.sh" --installed --headless \
    > "$REPO_ROOT/out/installed-boot.log" 2>&1 &

# Wait for the guest agent, not for a desktop session.
#
# vm-ready.sh waits for a logged-in user, which is right for the live media
# because it autologins. An installed system stops at the greeter and waits
# for a password, so that session never arrives and the canary timed out
# every time -- after a clean 37/37 install, which made it look as though
# something had gone wrong with the machine rather than with this script.
wait_for_agent() {
    local deadline=$(( SECONDS + 900 ))
    until SAKURA_VM=clean "$REPO_ROOT/build/guest-run.sh" true >/dev/null 2>&1; do
        (( SECONDS < deadline )) || return 1
        sleep 10
    done
    return 0
}

wait_for_agent \
    || die "the installed machine did not come up before any updates were applied"

guest() { SAKURA_VM=clean "$REPO_ROOT/build/guest-run.sh" "$1"; }

say "what is pending"
PENDING=$(guest "checkupdates 2>/dev/null || true" || true)
if [[ -z "${PENDING//[[:space:]]/}" ]]; then
    say "nothing to test"
    printf '{"generated":"%s","tested":0,"broken":[],"note":"no updates pending"}\n' \
        "$STAMP" > "$OUT"
    exit 0
fi
COUNT=$(printf '%s\n' "$PENDING" | grep -c . || true)
say "$COUNT updates pending"

say "applying them"
guest "pacman -Syu --noconfirm" >"$REPO_ROOT/out/canary-apply.log" 2>&1 \
    || die "the update itself failed. See out/canary-apply.log"

say "rebooting"
guest "systemctl reboot" >/dev/null 2>&1 || true
sleep 20

BROKEN=""
REASON=""
if ! wait_for_agent; then
    REASON="the machine did not reach a desktop after the update"
else
    say "re-running the checks"
    if ! SAKURA_VM=clean verify_only=1 "$REPO_ROOT/build/test-install.sh" --verify-only \
            >"$REPO_ROOT/out/canary-verify.log" 2>&1; then
        REASON="checks failed after the update. See out/canary-verify.log"
    fi
fi

if [[ -n "$REASON" ]]; then
    # Everything in the transaction is suspect: the canary knows the update
    # broke the machine, not which package did it. Narrowing that down is a
    # bisect, and a bisect is a person's job, not a nightly timer's.
    BROKEN=$(printf '%s\n' "$PENDING" | awk '{print $1}' | paste -sd, -)
    say "FAILED: $REASON"
    "$REPO_ROOT/build/canary-notify.sh" broke \
        "$COUNT updates broke the test machine. $REASON" "$BROKEN" \
        "$REPO_ROOT/out/canary-verify.log" || true
else
    say "passed"
fi

python3 - "$OUT" "$STAMP" "$COUNT" "$BROKEN" "$REASON" <<'PY'
import json, sys
out, stamp, count, broken, reason = sys.argv[1:6]
json.dump({
    "generated": stamp,
    "tested": int(count),
    "broken": [p for p in broken.split(",") if p],
    "reason": reason,
}, open(out, "w"), indent=1)
PY
say "wrote $OUT"
cat "$OUT"

if [[ "${PUBLISH:-0}" == "1" ]]; then
    say "publishing"
    scp -P "$REPO_PORT" "$OUT" "$REPO_HOST:$REPO_PATH"
    say "published to $REPO_PATH"
fi

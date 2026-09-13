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
# The destination lives in the forced command on the repo host now; this key
# is the whole of the canary's access there.
ADVISORY_KEY="${ADVISORY_KEY:-/root/.ssh/id_ed25519_advisory}"

cleanup() { pkill -f "[s]akura-${SAKURA_VM}\.qcow2" 2>/dev/null || true; }
trap cleanup EXIT INT TERM

say() { printf '\n>> %s\n' "$*"; }

# A canary that reports "everything is fine" because it never ran is worse
# than no canary, so every early exit here is a hard failure rather than an
# empty advisory file.
# Which log the notification should quote. Each stage sets this before it can
# fail: a notification that attaches the install log for a failure in the apply
# step points the reader at the one file that shows nothing wrong, which is
# exactly what happened on 2026-09-06.
FAIL_LOG="$REPO_ROOT/out/canary-install.log"

die() {
    echo "canary: $*" >&2
    # No 2>/dev/null here. canary-notify.sh reports its own skips on stderr
    # ("no GitHub token", "gh not installed"), and swallowing them is why a
    # missing gh went unnoticed for as long as it did: no issue was ever
    # opened and nothing said so.
    "$REPO_ROOT/build/canary-notify.sh" stalled "$*" "" "$FAIL_LOG" || true
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
        # A VM that is gone is never going to answer, and spending the
        # remaining fifteen minutes proving that produces a verdict of
        # "broken" for a machine that was never running. The distinction
        # matters more here than anywhere else in this script: this is the
        # judgement that holds packages back for every user.
        if ! pgrep -f "[q]emu-system-x86_64.*sakura-clean" >/dev/null 2>&1; then
            say "the VM is no longer running"
            return 2
        fi
        sleep 10
    done
    return 0
}

wait_for_agent \
    || die "the installed machine did not come up before any updates were applied"

guest() { SAKURA_VM=clean "$REPO_ROOT/build/guest-run.sh" "$1"; }
# Guest work measured in minutes rather than seconds, with the ceiling stated
# at the call site. guest-run defaults to 60s, which is right for a status
# query and wrong for a system upgrade.
guest_long() { SAKURA_VM=clean SAKURA_GUEST_TIMEOUT="$1" "$REPO_ROOT/build/guest-run.sh" "$2"; }

# Wait for any pacman still working inside the guest, then take the lock only
# if nothing holds it.
#
# Both halves matter. Walking away from a transaction does not stop it, so the
# retry used to meet a database locked by the attempt we had abandoned and
# report "the update failed twice" -- on nights when the update had never been
# given the time to finish at all. And clearing the package cache under a live
# pacman is how a real transaction gets corrupted, which is a worse problem
# than the one the retry exists to fix.
settle_guest_pacman() {
    guest "for _ in \$(seq 1 180); do pgrep -x pacman >/dev/null 2>&1 || break; sleep 5; done" \
        >/dev/null 2>&1 || true
    if guest "pgrep -x pacman >/dev/null 2>&1" >/dev/null 2>&1; then
        say "a pacman is still running in the guest; not touching its cache or lock"
        return 1
    fi
    guest "rm -f /var/lib/pacman/db.lck" >/dev/null 2>&1 || true
    return 0
}

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
FAIL_LOG="$REPO_ROOT/out/canary-apply.log"
# Two hundred and fifty packages is a normal night here, and that is minutes of
# downloading and installing. At the default 60s the call was abandoned every
# time the backlog grew past about a minute's work, which is what failed the
# runs on 2026-09-11 and 2026-09-12: the install passed 38/38 and the update was
# never actually given a chance to run.
APPLY_TIMEOUT="${SAKURA_CANARY_APPLY_TIMEOUT:-2400}"
if ! guest_long "$APPLY_TIMEOUT" "pacman -Syu --noconfirm" >"$FAIL_LOG" 2>&1; then
    # One retry, and only after clearing the package cache.
    #
    # A single corrupted download fails the whole transaction and the bad file
    # stays in the cache, so retrying without clearing it fails again in
    # exactly the same way. This cost a full night of coverage on 2026-09-06:
    # sakura-store arrived with a bad checksum, was verifiably intact on the
    # mirror, and the run was reported as a stall with no advisory published.
    #
    # The cache on a throwaway test machine is worth nothing, so there is no
    # need to work out which file was the bad one.
    say "the update failed; letting the guest settle, then clearing the cache and trying once more"
    printf '\n--- retrying with a cleared package cache ---\n' >>"$FAIL_LOG"
    if ! settle_guest_pacman; then
        printf '\nthe first attempt was still running; did not retry\n' >>"$FAIL_LOG"
        die "the update was still running when the harness gave up on it. See out/canary-apply.log"
    fi
    guest "rm -f /var/cache/pacman/pkg/*.pkg.tar.zst /var/cache/pacman/pkg/*.part" \
        >/dev/null 2>&1 || true
    guest_long "$APPLY_TIMEOUT" "pacman -Syu --noconfirm" >>"$FAIL_LOG" 2>&1 \
        || die "the update failed twice, the second time with a cleared package cache. See out/canary-apply.log"
fi

say "rebooting"
guest "systemctl reboot" >/dev/null 2>&1 || true
sleep 20

BROKEN=""
REASON=""
wait_for_agent; agent_rc=$?
if (( agent_rc == 2 )); then
    # qemu itself died. That says nothing about the update, and publishing an
    # advisory on the strength of it would hold packages that were never shown
    # to be at fault. Fail the run instead, loudly, as an infrastructure
    # problem -- which is what "stalled" is for.
    die "the VM disappeared after the update, so nothing was proved either way. \
See out/console-clean.log"
elif (( agent_rc != 0 )); then
    REASON="the machine did not come back after the update"
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
    # Piped to a forced command, not scp'd to a path. The key this uses can
    # run exactly one program on the repo host and cannot pick a destination,
    # so a canary that is compromised or simply wrong can replace one
    # advisory file and nothing else. The receiving end validates the JSON
    # before it replaces anything, because this file decides what every
    # SakuraOS machine holds back.
    if ssh -p "$REPO_PORT" -i "$ADVISORY_KEY" \
           -o BatchMode=yes -o ConnectTimeout=15 \
           "$REPO_HOST" < "$OUT"; then
        say "published"
    else
        # Not fatal to the run: the advisory is written locally either way,
        # and a failed upload must not turn a correct verdict into a lost one.
        say "WARNING: could not publish the advisory"
        "$REPO_ROOT/build/canary-notify.sh" stalled \
            "the canary ran but could not publish its advisory" "" "" || true
    fi
fi

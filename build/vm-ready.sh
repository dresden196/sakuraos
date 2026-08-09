#!/usr/bin/env bash
# Block until the test VM has a usable Plasma session, then normalise it.
#
# Every automated check should gate on this rather than on a fixed sleep —
# boot time varies a lot between a warm and a cold host.
#
#   ./build/test-vm.sh & ./build/vm-ready.sh && ./build/screenshot.sh shot.png
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${SAKURA_VM_MODE:-1920x1080@60}"
DEADLINE=$(( SECONDS + ${SAKURA_VM_TIMEOUT:-600} ))

as_live_user() {
    "$REPO_ROOT/build/guest-run.sh" \
        "runuser -u sakura -- env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 $1"
}

echo -n ">> waiting for the live session"
until "$REPO_ROOT/build/guest-run.sh" \
        'loginctl list-sessions --no-legend | grep -q " sakura .*seat0"' >/dev/null 2>&1; do
    (( SECONDS < DEADLINE )) || { echo; echo "timed out waiting for a sakura session" >&2; exit 1; }
    echo -n .
    sleep 5
done

# Wait for kwin specifically: loginctl reports the session before the
# compositor owns the Wayland socket, and kscreen-doctor fails in that window.
until "$REPO_ROOT/build/guest-run.sh" 'pgrep -x kwin_wayland' >/dev/null 2>&1; do
    (( SECONDS < DEADLINE )) || { echo; echo "session started but kwin never appeared" >&2; exit 1; }
    echo -n .
    sleep 5
done
echo " up"

# Plasma honours the EDID-preferred mode, and QEMU's virtio-gpu insists that is
# 640x480 regardless of edid=on, xres/yres, or video= on the kernel cmdline.
# Setting it after the fact is the only thing that actually works.
echo ">> setting $MODE"
as_live_user "kscreen-doctor output.Virtual-1.mode.$MODE" >/dev/null

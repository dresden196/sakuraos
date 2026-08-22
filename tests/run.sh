#!/usr/bin/env bash
# Run the SakuraOS test suite in a container.
#
# Needs --privileged for loop devices and mount; that is why it runs in a
# throwaway container rather than on the developer's machine.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The loop devices live on the host; docker's default /dev has none, so a
# plain --privileged container still cannot mount a filesystem image. The
# repository is mounted read-only and everything the tests create lives inside
# the container, so the blast radius is a loop device and a file in /tmp.
docker run --rm --privileged \
    -v /dev:/dev \
    -v "$REPO_ROOT:/build:ro" \
    -w /build \
    sakura-build \
    bash -euo pipefail -c '
        pacman -Sy --noconfirm btrfs-progs >/dev/null 2>&1

        # Install the package payload where the scripts expect to find it,
        # so the tests exercise the real installed paths rather than the
        # source tree layout.
        install -Dm644 /build/packages/sakura-snapshot-boot/lib.sh \
            /usr/lib/sakura/snapshot-boot/lib.sh
        install -Dm755 /build/packages/sakura-snapshot-boot/sakura-rollback \
            /usr/lib/sakura/snapshot-boot/sakura-rollback
        install -Dm755 /build/packages/sakura-snapshot-boot/sakura-boot-entries \
            /usr/bin/sakura-boot-entries
        install -Dm755 /build/packages/sakura-terminal-assist/alpm-check \
            /usr/lib/sakura/terminal-assist/alpm-check
        install -Dm644 /build/packages/sakura-terminal-assist/terminal-assist.sh \
            /usr/share/sakura/terminal-assist.sh
        install -Dm644 /build/packages/sakura-terminal-assist/profile.d.sh \
            /etc/profile.d/sakura-terminal-assist.sh
        # Mirror what the package install scriptlet does to /etc/bash.bashrc.
        printf "\n# SakuraOS Terminal Assist\n%s\n" \
            "[ -r /usr/share/sakura/terminal-assist.sh ] && . /usr/share/sakura/terminal-assist.sh" \
            >> /etc/bash.bashrc
        install -Dm755 /build/packages/sakura-settings-kcm/kcm/helper/sakura-settings-write \
            /usr/lib/sakura/settings/sakura-settings-write

        rc=0
        bash /build/tests/test-rollback.sh || rc=1
        echo
        bash /build/tests/test-boot-entries.sh || rc=1
        echo
        bash /build/tests/test-terminal-assist.sh || rc=1
        echo
        bash /build/tests/test-settings-write.sh || rc=1
        echo
        bash /build/tests/test-shell-assist.sh || rc=1
        exit $rc
    '

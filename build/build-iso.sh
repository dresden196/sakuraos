#!/usr/bin/env bash
# Build a SakuraOS ISO inside a container.
#
# Nothing is installed on the host: archiso, the package cache, and the ~10 GB
# of intermediate build state all live in the container and a docker volume.
# The only thing that lands on the host is the finished ISO in out/.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=sakura-build
CACHE_VOLUME=sakura-pkgcache

cd "$REPO_ROOT"

if [[ "${1:-}" == "--rebuild-image" ]] || ! docker image inspect "$IMAGE" &>/dev/null; then
    echo ">> building $IMAGE container image"
    docker build -t "$IMAGE" -f build/Containerfile build/
fi

# Persisting the pacman cache across builds turns a 20 minute first build into
# a ~3 minute rebuild. mkarchiso runs pacstrap with -c, so it uses the cache at
# this path rather than one inside the work directory.
docker volume create "$CACHE_VOLUME" >/dev/null

# Stage our repo onto the live media. An installer ISO has to carry the
# packages it installs -- file:///build only exists inside the build
# container, so without this an install from the booted media cannot resolve
# sakura-core at all. Upstream Arch packages still come from the network.
STAGED_REPO="$REPO_ROOT/iso/airootfs/usr/share/sakura/repo"
LIVE_PACMAN_CONF="$REPO_ROOT/iso/airootfs/etc/pacman.conf"
cleanup_staging() { rm -rf "$STAGED_REPO" "$LIVE_PACMAN_CONF"; }
trap cleanup_staging EXIT

if [[ -d "$REPO_ROOT/repo" ]]; then
    mkdir -p "$STAGED_REPO"
    # Only sakura-core goes on the media. sakura-extra holds things that are
    # too large to ship to every user for a minority of hardware, and is
    # fetched over the network when the installer decides it is needed.
    cp -r "$REPO_ROOT/repo/sakura-core" "$STAGED_REPO/"
    # The live system needs the same repo definition as the build, pointed at
    # the on-media copy. Deriving it from iso/pacman.conf keeps the two from
    # drifting apart.
    sed 's#file:///build/repo/#file:///usr/share/sakura/repo/#' \
        "$REPO_ROOT/iso/pacman.conf" > "$LIVE_PACMAN_CONF"
    echo ">> staged $(find "$STAGED_REPO" -name '*.pkg.tar.zst' | wc -l) packages onto the live media"
fi

echo ">> running mkarchiso"
docker run --rm --privileged \
    -v "$REPO_ROOT:/build" \
    -v "$CACHE_VOLUME:/var/cache/pacman/pkg" \
    -w /build \
    "$IMAGE" \
    bash -euo pipefail -c '
        # Trust our own signing key before pacstrap runs, so the ISO build
        # verifies sakura-core signatures the same way a user machine will.
        # SigLevel in iso/pacman.conf is Required, so a missing key fails the
        # build loudly instead of silently shipping unverified packages.
        if [[ -f /build/packages/sakura-keyring/sakura.gpg ]]; then
            pacman-key --init >/dev/null 2>&1
            pacman-key --populate archlinux >/dev/null 2>&1
            pacman-key --add /build/packages/sakura-keyring/sakura.gpg
            awk -F: "/^fpr:/ {print \$10; exit}" \
                <(gpg --with-colons --import-options show-only --import \
                      /build/packages/sakura-keyring/sakura.gpg) \
                | xargs -r pacman-key --lsign-key
        fi

        # Our own packages keep the same version string across rebuilds, so a
        # cached copy from an earlier build would be used in preference to the
        # one just built -- and would fail signature verification outright if
        # the signing key has been rotated since. Upstream packages are left
        # cached; they are versioned properly and are the slow part to fetch.
        #
        # Match on what is actually in our repo rather than on a sakura-*
        # glob. The rebuilt AUR packages -- snapd, the limine hooks -- carry
        # upstream names, so the glob never covered them: a stale snapd sat in
        # the cache across builds and failed every ISO with "invalid or
        # corrupted package", which reads as a bad download and is not one.
        for _ours in /build/repo/*/os/*/*.pkg.tar.zst; do
            [ -e "$_ours" ] || continue
            rm -f "/var/cache/pacman/pkg/$(basename "$_ours")"*
        done

        rm -rf /tmp/work
        mkarchiso -v -w /tmp/work -o /build/out /build/iso
        # mkarchiso writes as root; hand the artifacts back to the caller so the
        # host user can read and delete them without sudo.
        chown -R '"$(id -u):$(id -g)"' /build/out
    '

echo
echo ">> done:"
ls -lh out/*.iso

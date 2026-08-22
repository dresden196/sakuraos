#!/usr/bin/env bash
# Build every SakuraOS package and publish them into the local sakura-core repo.
#
# Builds run in a container as an unprivileged user, exactly as they will on a
# build box. Signing uses whatever key SAKURA_GPGHOME points at, so switching
# from the development key to a production one is an environment change, not a
# pipeline change.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=sakura-build
CACHE_VOLUME=sakura-pkgcache
GPGHOME="${SAKURA_GPGHOME:-$REPO_ROOT/keys/dev-gnupg}"
REPO_DIR="$REPO_ROOT/repo/sakura-core/os/x86_64"

cd "$REPO_ROOT"

if ! docker image inspect "$IMAGE" &>/dev/null; then
    echo ">> building $IMAGE container image"
    docker build -t "$IMAGE" -f build/Containerfile build/
fi

if [[ ! -d "$GPGHOME" ]]; then
    echo "no signing key at $GPGHOME — run build/make-dev-key.sh" >&2
    exit 1
fi

SIGNER="$(gpg --homedir "$GPGHOME" --list-secret-keys --with-colons \
          | awk -F: '/^sec:/ {print $5; exit}')"
[[ -n "$SIGNER" ]] || { echo "no secret key in $GPGHOME" >&2; exit 1; }
echo ">> signing with $SIGNER"

mkdir -p "$REPO_DIR"
docker volume create "$CACHE_VOLUME" >/dev/null

rc=0
docker run --rm \
    -v "$REPO_ROOT:/build" \
    -v "$GPGHOME:/gpg:ro" \
    -v "$CACHE_VOLUME:/var/cache/pacman/pkg" \
    -e "SIGNER=$SIGNER" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -w /build \
    "$IMAGE" \
    bash -euo pipefail -c '
        pacman -Sy --noconfirm >/dev/null

        # The mounted keyring is read-only and owned by the host user; gpg
        # insists on a private, writable home, so take a copy.
        install -d -m 700 -o builder -g builder /home/builder/.gnupg
        cp -r /gpg/. /home/builder/.gnupg/
        chown -R builder:builder /home/builder/.gnupg
        chmod -R go-rwx /home/builder/.gnupg

        WORK=/home/builder/work
        install -d -o builder -g builder "$WORK"

        # Local packages first: the AUR rebuilds and the meta package depend on
        # them, and makepkg resolves dependencies against the repo as it grows.
        for dir in /build/packages/*/; do
            name=$(basename "$dir")
            [[ "$name" == "aur" ]] && continue
            [[ -f "$dir/PKGBUILD" ]] || continue
            echo ">>> building $name"
            cp -r "$dir" "$WORK/$name"
            chown -R builder:builder "$WORK/$name"
            su builder -c "cd $WORK/$name && GNUPGHOME=/home/builder/.gnupg \
                makepkg --syncdeps --noconfirm --clean --sign --key $SIGNER \
                        --nodeps --skipinteg"
        done

        # An AUR package breaking upstream must not take the whole repo down
        # with it. Record the failure, publish everything that did build, and
        # report at the end -- a half-built repo you know about beats no repo.
        FAILED=""
        while read -r pkg; do
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            echo ">>> rebuilding AUR package $pkg"
            if su builder -c "git clone --depth 1 https://aur.archlinux.org/$pkg.git $WORK/$pkg" \
               && su builder -c "cd $WORK/$pkg && GNUPGHOME=/home/builder/.gnupg \
                    makepkg --syncdeps --noconfirm --clean --sign --key $SIGNER"; then
                echo ">>> $pkg ok"
            else
                echo ">>> $pkg FAILED"
                FAILED="$FAILED $pkg"
            fi
        done < /build/packages/aur/manifest.txt

        OUT=/build/repo/sakura-core/os/x86_64
        install -d "$OUT"
        find "$WORK" -name "*.pkg.tar.zst" -exec cp -f {} "$OUT/" \;
        find "$WORK" -name "*.pkg.tar.zst.sig" -exec cp -f {} "$OUT/" \;

        cd "$OUT"
        rm -f sakura-core.db* sakura-core.files*
        su builder -c "cd $OUT && GNUPGHOME=/home/builder/.gnupg \
            repo-add --sign --key $SIGNER sakura-core.db.tar.gz *.pkg.tar.zst"

        chown -R "$HOST_UID:$HOST_GID" /build/repo

        if [[ -n "$FAILED" ]]; then
            echo
            echo "!! these packages did not build:$FAILED"
            echo "!! the repo was published without them"
            exit 2
        fi
    ' || rc=$?

echo
echo ">> sakura-core now contains:"
ls -1 "$REPO_DIR"/*.pkg.tar.zst 2>/dev/null | xargs -r -n1 basename
exit $rc

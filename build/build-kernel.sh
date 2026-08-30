#!/usr/bin/env bash
# Build the SakuraOS kernel and publish it into the local sakura-core repo.
#
# Separate from build-packages.sh for two reasons. It takes hours where the
# rest of the repository takes minutes, so it must not be in the path of an
# ordinary rebuild; and it is the one package whose checksums are verified
# rather than skipped -- see below.
#
#   ./build/build-kernel.sh            build the pinned kernel
#   ./build/build-kernel.sh --check    print what would be built, build nothing
#   ./build/build-kernel.sh --verify   fetch and verify sources, compile nothing
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE=sakura-build
CACHE_VOLUME=sakura-pkgcache
SRC_VOLUME=sakura-kernelsrc
GPGHOME="${SAKURA_GPGHOME:-$REPO_ROOT/keys/dev-gnupg}"
REPO_DIR="$REPO_ROOT/repo/sakura-core/os/x86_64"
CONF="$REPO_ROOT/packages/linux-cachyos/kernel.conf"

CHECK=0
VERIFY=0
for arg in "$@"; do
    case "$arg" in
        --check) CHECK=1 ;;
        --verify) VERIFY=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# shellcheck source=/dev/null
source "$CONF"

echo ">> kernel:  $KERNEL_VARIANT"
echo ">> commit:  $KERNEL_COMMIT"
echo ">> baseline: ${_processor_opt}  (LTO: ${_use_llvm_lto}, sched: ${_cpusched})"
[[ "$CHECK" == 1 ]] && exit 0

if [[ ! -d "$GPGHOME" ]]; then
    echo "no signing key at $GPGHOME -- run build/make-dev-key.sh" >&2
    exit 1
fi
SIGNER="$(gpg --homedir "$GPGHOME" --list-secret-keys --with-colons \
          | awk -F: '/^sec:/ {print $5; exit}')"
[[ -n "$SIGNER" ]] || { echo "no secret key in $GPGHOME" >&2; exit 1; }
echo ">> signing with $SIGNER"

mkdir -p "$REPO_DIR"
docker volume create "$CACHE_VOLUME" >/dev/null
docker volume create "$SRC_VOLUME" >/dev/null

docker run --rm \
    -v "$REPO_ROOT:/build" \
    -v "$GPGHOME:/gpg:ro" \
    -v "$CACHE_VOLUME:/var/cache/pacman/pkg" \
    -v "$SRC_VOLUME:/home/builder/work" \
    -e "SIGNER=$SIGNER" \
    -e "KERNEL_REPO=$KERNEL_REPO" \
    -e "KERNEL_COMMIT=$KERNEL_COMMIT" \
    -e "KERNEL_VARIANT=$KERNEL_VARIANT" \
    -e "KERNEL_PGP_KEYS=$KERNEL_PGP_KEYS" \
    -e "HOST_UID=$(id -u)" \
    -e "HOST_GID=$(id -g)" \
    -e "VERIFY=$VERIFY" \
    -w /build \
    "$IMAGE" \
    bash -euo pipefail -c '
        pacman -Sy --noconfirm >/dev/null
        pacman -S --needed --noconfirm --asdeps \
            git base-devel clang llvm lld python cpio perl tar xz bc \
            pahole zstd >/dev/null

        install -d -m 700 -o builder -g builder /home/builder/.gnupg
        cp -r /gpg/. /home/builder/.gnupg/
        chown -R builder:builder /home/builder/.gnupg
        chmod -R go-rwx /home/builder/.gnupg

        # Upstream signs the kernel tarball. Their keys are fetched by full
        # fingerprint, so a keyserver that answers with something else cannot
        # substitute a key -- gpg will simply not find the one asked for.
        for key in $KERNEL_PGP_KEYS; do
            su builder -c "gpg --batch --keyserver keyserver.ubuntu.com \
                --recv-keys $key" >/dev/null 2>&1 ||
            su builder -c "gpg --batch --keyserver keys.openpgp.org \
                --recv-keys $key" >/dev/null 2>&1 ||
            { echo "could not fetch signing key $key"; exit 1; }
        done

        WORK=/home/builder/work
        install -d -o builder -g builder "$WORK"

        # The overrides are sourced here rather than passed one at a time,
        # so the set that reaches the build is exactly the set in the file and
        # cannot drift from it. They are read by the upstream PKGBUILD through
        # its own :-= idiom, the override mechanism upstream documents,
        # so that file is used exactly as published.
        su builder -c "
            set -euo pipefail
            source /build/packages/linux-cachyos/kernel.conf
            cd $WORK
            if [ -d src/.git ]; then
                cd src && git fetch --quiet origin && cd ..
            else
                rm -rf src
                git clone --filter=blob:none $KERNEL_REPO src
            fi
            cd src
            git checkout --quiet $KERNEL_COMMIT
            cd $KERNEL_VARIANT

            # No --skipinteg, deliberately, and this is the whole reason the
            # options are set through the environment rather than by patching
            # the PKGBUILD. Their b2sums cover a source array whose length
            # changes with some options; edit the file and the sums stop
            # matching, and the only way out is to stop checking them. Setting
            # variables leaves the array -- and therefore the sums -- exactly
            # as published, so every source is verified against a checksum
            # written by upstream.
            if [ $VERIFY = 1 ]; then
                # Sources fetched, checksummed and signature-checked, nothing
                # compiled. Proves the integrity claim without the hours.
                makepkg --noconfirm --nobuild --nodeps
            else
                GNUPGHOME=/home/builder/.gnupg \
                makepkg --noconfirm --clean --sign --key $SIGNER --nodeps
            fi
        "

        if [ "$VERIFY" = 1 ]; then
            # Read out of the prepared tree rather than trusted to have
            # arrived. An override that silently fails to apply leaves
            # X86_NATIVE_CPU set, which builds a kernel that boots on the
            # build machine and nowhere else -- the failure this whole
            # baseline exists to avoid, and one that would not show up until
            # somebody else tried to start it.
            echo
            echo "== CPU baseline written into the prepared config =="
            grep -E "^CONFIG_GENERIC_CPU|^CONFIG_X86_64_VERSION|^CONFIG_MZEN4|^CONFIG_X86_NATIVE_CPU" \
                /home/builder/work/src/$KERNEL_VARIANT/src/*/.config \
                || echo "  NOT FOUND -- check _processor_opt"
            echo
            echo "sources verified against upstream checksums and signature"
            exit 0
        fi

        # Kept outside the repository as well. build-packages.sh empties the
        # repo on every run, so the repo alone is not somewhere a twenty
        # minute artefact can live.
        mkdir -p /build/out/kernel
        rm -f /build/out/kernel/*.pkg.tar.zst*
        cp $WORK/src/$KERNEL_VARIANT/*.pkg.tar.zst* /build/out/kernel/
        cp $WORK/src/$KERNEL_VARIANT/*.pkg.tar.zst* \
           /build/repo/sakura-core/os/x86_64/
        chown $HOST_UID:$HOST_GID /build/repo/sakura-core/os/x86_64/*

        cd /build/repo/sakura-core/os/x86_64
        # No unsigned fallback. A database added to without --sign keeps its
        # old signature, which no longer matches -- and the failure surfaces
        # later as "signature from ... is invalid" during an ISO build, a long
        # way from the cause. Better to fail here.
        su builder -c "GNUPGHOME=/home/builder/.gnupg repo-add --sign \
            --key $SIGNER sakura-core.db.tar.gz *.pkg.tar.zst"
        chown $HOST_UID:$HOST_GID /build/repo/sakura-core/os/x86_64/*
    '

[[ "$VERIFY" == 1 ]] && exit 0
echo ">> kernel built and published"
ls -1 "$REPO_DIR" | grep -E "^linux-cachyos" || true

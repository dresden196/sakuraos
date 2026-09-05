#!/usr/bin/env bash
# Build every SakuraOS package and publish them into the local sakura-core repo.
#
# Builds run in a container as an unprivileged user, exactly as they will on a
# build box. Signing uses whatever key SAKURA_GPGHOME points at, so switching
# from the development key to a production one is an environment change, not a
# pipeline change.
#
#   ./build/build-packages.sh              everything, including AUR rebuilds
#   ./build/build-packages.sh --skip-aur   only our own packages
#
# The AUR rebuilds are the expensive part -- args, cpr, zsync2 and snapd
# together dominate the wall clock -- and they change only when their upstream
# PKGBUILD does. When iterating on our own code, --skip-aur reuses the
# already-built copies from the previous run instead of compiling them again.
set -euo pipefail

SKIP_AUR=0
for arg in "$@"; do
    case "$arg" in
        --skip-aur) SKIP_AUR=1 ;;
        *) echo "unknown flag: $arg" >&2; exit 1 ;;
    esac
done

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

# Every build gets a version of its own.
#
# Our PKGBUILDs all say pkgrel=1 and always have, so two different builds of
# the same package were indistinguishable to pacman. A copy cached from the
# install media then collides with a differently-built package of the same
# name on the repository, and pacman calls the cached one corrupt rather than
# stale -- which is exactly how the first update on a new machine failed.
#
# Commit count rather than a timestamp: it moves when the source moves, so
# rebuilding the same commit does not manufacture an update for every package
# on every machine. Stamped into the copy under $WORK, never into the tree.
BUILD_STAMP="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 0)"
echo ">> build stamp: pkgrel suffix .$BUILD_STAMP"

rc=0
docker run --rm \
    -v "$REPO_ROOT:/build" \
    -v "$GPGHOME:/gpg:ro" \
    -v "$CACHE_VOLUME:/var/cache/pacman/pkg" \
    -e "SIGNER=$SIGNER" \
    -e "SKIP_AUR=$SKIP_AUR" \
    -e "BUILD_STAMP=$BUILD_STAMP" \
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

        # Trust our own signing key inside the build container. Packages are
        # signed as they are built, and an AUR package that depends on another
        # AUR package has to be installed here before the dependent one can
        # build -- pacman -U refuses a package signed by a key it does not
        # know, which is why installing cpr for zsync2 failed silently.
        pacman-key --init >/dev/null 2>&1
        gpg --homedir /home/builder/.gnupg --export "$SIGNER" \
            | pacman-key --add - >/dev/null 2>&1
        pacman-key --lsign-key "$SIGNER" >/dev/null 2>&1

        WORK=/home/builder/work
        install -d -o builder -g builder "$WORK"

        FAILED=""

        # Local packages first: the AUR rebuilds and the meta package depend on
        # them, and makepkg resolves dependencies against the repo as it grows.
        #
        # --nodeps is required because sakura-desktop is a meta package whose
        # runtime dependencies include packages this very run is building. But
        # --nodeps also skips installing makedepends, so those are installed
        # explicitly first -- otherwise anything needing a compiler fails with
        # "cmake: command not found".
        for dir in /build/packages/*/; do
            name=$(basename "$dir")
            if [[ "$name" == "aur" ]]; then continue; fi
            if [[ ! -f "$dir/PKGBUILD" ]]; then continue; fi
            echo ">>> building $name"
            cp -r "$dir" "$WORK/$name"
            # Stamp the copy, not the tree: the working directory stays clean
            # and the PKGBUILD under version control keeps saying pkgrel=1.
            sed -i -E "s/^pkgrel=([0-9]+)\$/pkgrel=\\1.$BUILD_STAMP/" \
                "$WORK/$name/PKGBUILD"
            chown -R builder:builder "$WORK/$name"

            # Compiled packages need their runtime libraries present at build
            # time too, so depends and makedepends are both installed. Anything
            # this run is still building will not be in the sync database yet
            # (sakura-desktop depends on its siblings), so unavailable names are
            # filtered out rather than allowed to fail the whole install.
            wanted=$(cd "$WORK/$name" && bash -c \
                '"'"'source ./PKGBUILD 2>/dev/null
                   printf "%s\n" "${makedepends[@]:-}" "${depends[@]:-}"'"'"' \
                | sed '"'"'s/[<>=].*//'"'"' | grep -v "^$" | sort -u || true)

            install_list=""
            for dep in $wanted; do
                pacman -Si "$dep" >/dev/null 2>&1 && install_list="$install_list $dep"
            done
            if [[ -n "$install_list" ]]; then
                echo ">>>   build deps:$install_list"
                pacman -S --needed --noconfirm --asdeps $install_list >/dev/null
            fi

            # One broken package must not silently take the whole repo down
            # with it -- the same reasoning as the AUR rebuilds below.
            if su builder -c "cd $WORK/$name && GNUPGHOME=/home/builder/.gnupg \
                    makepkg --noconfirm --clean --sign --key $SIGNER \
                            --nodeps --skipinteg"; then
                echo ">>> $name ok"
            else
                echo ">>> $name FAILED"
                FAILED="$FAILED $name"
            fi
        done

        # An AUR package breaking upstream must not take the whole repo down
        # with it. Record the failure, publish everything that did build, and
        # report at the end -- a half-built repo you know about beats no repo.
        # A manifest line is a package name, optionally followed by extra
        # makepkg flags for that one package. Per-package rather than global
        # so that weakening a check stays visible next to the package it
        # applies to, with the reason in a comment above it.
        # Reuse what a previous run already built. The repo directory is
        # emptied further down, so the packages have to be copied out first --
        # otherwise --skip-aur would publish a repo with our packages and
        # nothing else, which is worse than a slow build.
        REUSE=/home/builder/reuse
        install -d -o builder -g builder "$REUSE"
        if (( SKIP_AUR )); then
            while read -r pkg flags; do
                if [[ -z "$pkg" || "$pkg" == \#* ]]; then continue; fi
                found=0
                for d in /build/repo/sakura-core/os/x86_64 \
                         /build/repo/sakura-extra/os/x86_64; do
                    for f in "$d/$pkg"-[0-9]*.pkg.tar.zst; do
                        [[ -e "$f" ]] || continue
                        cp "$f" "$f.sig" "$REUSE/" 2>/dev/null || cp "$f" "$REUSE/"
                        found=1
                    done
                done
                if (( found )); then
                    echo ">>> reusing AUR package $pkg"
                else
                    echo ">>> warning: --skip-aur but no previous build of $pkg"
                    FAILED="$FAILED $pkg"
                fi
            done < /build/packages/aur/manifest.txt
        fi

        while read -r pkg flags; do
            if (( SKIP_AUR )); then continue; fi
            # An if, not "[[ ... ]] && continue": under set -e a false test
            # makes the && list return non-zero and kills the whole build,
            # after it has already succeeded.
            if [[ -z "$pkg" || "$pkg" == \#* ]]; then continue; fi
            echo ">>> rebuilding AUR package $pkg${flags:+ ($flags)}"
            if su builder -c "git clone --depth 1 https://aur.archlinux.org/$pkg.git $WORK/$pkg" \
               && su builder -c "cd $WORK/$pkg && GNUPGHOME=/home/builder/.gnupg \
                    makepkg --syncdeps --noconfirm --clean --sign --key $SIGNER $flags"; then
                echo ">>> $pkg ok"
                # Install what we just built into the build container. Some AUR
                # packages depend on other AUR packages -- zsync2 needs cpr and
                # args, neither of which is in any repo -- and makepkg
                # --syncdeps can only resolve from repositories, so without
                # this the dependent package fails with "target not found" no
                # matter what order the manifest is in. The container is
                # thrown away at the end of the build.
                if ! pacman -U --noconfirm --asdeps --needed \
                        "$WORK/$pkg"/*.pkg.tar.zst >/dev/null 2>&1; then
                    # Not fatal on its own, but it is why a later package that
                    # depends on this one will fail, so say so here rather
                    # than leaving that failure unexplained.
                    echo ">>> warning: could not install $pkg into the build container"
                fi
            else
                echo ">>> $pkg FAILED"
                FAILED="$FAILED $pkg"
            fi
        done < /build/packages/aur/manifest.txt

        # Two repositories, split by whether a package is worth putting on
        # every ISO. sakura-core ships on the media so an install works with
        # no network; sakura-extra holds things only a minority of hardware
        # needs -- the legacy NVIDIA userspace alone is ~900 MB installed --
        # and is fetched over the network when the installer asks for it.
        CORE=/build/repo/sakura-core/os/x86_64
        EXTRA=/build/repo/sakura-extra/os/x86_64
        KERNELS=/build/out/kernel
        mkdir -p "$KERNELS"
        # repo-add runs as builder and writes a lockfile beside the database,
        # so the directories must be builder-writable rather than root-owned.
        install -d -o builder -g builder "$CORE" "$EXTRA"

        # Start from empty. repo-add happily keeps several versions of the
        # same package, so without this the repo silently accumulates every
        # build ever made and pacman may serve a stale one.
        #
        # Emptying it also deletes anything this script did not build, which
        # is how the kernel disappeared: build-kernel.sh puts linux-cachyos in
        # the repo and nowhere else, so every later run of this script removed
        # it, the next ISO shipped without it, and every install quietly fell
        # back to the stock kernel. Nothing failed; the feature simply was not
        # there. Kernels are kept out of tree in out/kernel and copied back in
        # below, the same way AUR rebuilds are carried across --skip-aur.
        for d in "$CORE" "$EXTRA"; do
            rm -f "$d"/*.pkg.tar.zst "$d"/*.pkg.tar.zst.sig "$d"/*.db* "$d"/*.files*
        done

        while IFS= read -r pkg; do
            base=$(basename "$pkg")
            # -debug packages are split output nobody installs; they are pure
            # weight in a repo that ships on the ISO.
            case "$base" in
                *-debug-*) continue ;;
                nvidia-580xx-*|opencl-nvidia-580xx-*) dest="$EXTRA" ;;
                # Browsers: a few hundred megabytes each, and an install uses
                # exactly one of them. Putting four on every ISO to ship three
                # nobody chose is the definition of what sakura-extra is for.
                # They are fetched over the network when the installer asks.
                zen-browser-bin-*|brave-bin-*|google-chrome-*|helium-browser-bin-*) dest="$EXTRA" ;;
                *) dest="$CORE" ;;
            esac
            cp -f "$pkg" "$dest/"
            # Trailing && under set -e: a package without a signature would
            # otherwise make the whole build report failure after succeeding.
            [ -f "$pkg.sig" ] && cp -f "$pkg.sig" "$dest/" || true
        # $REUSE holds AUR packages carried over from a previous run under
        # --skip-aur; without it here the repo would be published with our
        # packages alone and every AUR dependency silently missing.
        # KERNELS is out/kernel: built by build-kernel.sh, which takes twenty
        # minutes on a build box and must not be a casualty of rebuilding a
        # QML file.
        done < <(find "$WORK" "$REUSE" "$KERNELS" -name "*.pkg.tar.zst" 2>/dev/null)

        for d in "$CORE" "$EXTRA"; do
            name=$(basename "$(dirname "$(dirname "$d")")")
            if ls "$d"/*.pkg.tar.zst >/dev/null 2>&1; then
                su builder -c "cd $d && GNUPGHOME=/home/builder/.gnupg \
                    repo-add --sign --key $SIGNER $name.db.tar.gz *.pkg.tar.zst"
            fi
        done

        chown -R "$HOST_UID:$HOST_GID" /build/repo

        if [[ -n "$FAILED" ]]; then
            echo
            echo "!! these packages did not build:$FAILED"
            echo "!! the repo was published without them"
            exit 2
        fi

        # Explicit: without it the script inherits the status of whatever ran
        # last, which is not a statement about whether the build succeeded.
        exit 0
    ' || rc=$?

echo
echo ">> sakura-core now contains:"
ls -1 "$REPO_DIR"/*.pkg.tar.zst 2>/dev/null | xargs -r -n1 basename
exit $rc

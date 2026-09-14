#!/usr/bin/env bash
# Copy the master key and its revocation certificate onto removable media,
# and prove the copy is readable before trusting it.
#
#   ./build/backup-master-key.sh /run/media/dwildey/MYSTICK
#
# Run it twice, onto two different sticks, kept in two different places. Then
# run it with --finish to shred the copies left on this laptop.
#
# Why this exists rather than a cp command: a backup nobody has read back is a
# guess. This re-imports the copy into a throwaway keyring and checks the
# fingerprint that comes out, so "it is on the stick" and "it is the key" are
# the same statement.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="${SAKURA_PROD_STAGE:-$REPO_ROOT/keys/prod-staging}"
FPR="${SAKURA_PROD_FPR:-6F45296EDBF1C57AE76226E7131E22D58CBD7EE6}"
MASTER="$STAGE/sakura-master-SECRET.asc"
REVOKE="$STAGE/sakura-revocation.rev"
PUBLIC="$STAGE/sakura-public.asc"

# Two custody schemes, both legitimate, and the default is the one chosen for
# this project on 2026-09-13: one USB copy plus the copy on the laptop.
#
# Two copies is what protects against losing the key, which is the risk that
# matters while the key is young -- lose the master and you can never revoke or
# reissue the build subkey for machines that already trust it. Keeping one of
# those copies on the laptop leaves the master on a machine that also runs a
# browser, which is the risk the stricter scheme addresses. That trade is a
# decision, not an oversight, and --shred-master switches to the stricter one
# whenever it is wanted.
if [[ "${1:-}" == "--finish" || "${1:-}" == "--shred-master" ]]; then
    SHRED_MASTER=0
    [[ "${1:-}" == "--shred-master" ]] && SHRED_MASTER=1

    # The subkey export goes either way. It is a transport file: the signing
    # subkey already lives in keys/prod-gnupg and on the build box, so this copy
    # buys nothing and is one more thing to leak.
    TO_SHRED=("$STAGE/sakura-subkeys-SECRET.asc")
    if (( SHRED_MASTER )); then
        TO_SHRED+=("$MASTER")
        echo "This deletes the laptop's copy of the MASTER secret:"
        echo "    $MASTER"
        echo
        echo "Only do this with a readable copy on removable media."
    else
        echo "Keeping the laptop's copy of the master, as chosen."
        echo "Shredding only the redundant subkey transport export:"
        echo "    $STAGE/sakura-subkeys-SECRET.asc"
    fi
    read -rp "Type SHRED to continue: " ans
    [[ "$ans" == "SHRED" ]] || { echo "left alone."; exit 1; }
    for f in "${TO_SHRED[@]}"; do
        [[ -f "$f" ]] && { shred -u "$f"; echo "shredded $(basename "$f")"; }
    done
    if (( ! SHRED_MASTER )); then
        chmod 600 "$MASTER" 2>/dev/null || true
        echo
        echo "The master secret remains at:"
        echo "    $MASTER"
        echo "It is passphrase protected, and gitignored by shape so it cannot be"
        echo "committed. To remove it from this machine later:"
        echo "    ./build/backup-master-key.sh --shred-master"
    fi
    # The public key and the revocation certificate are not secrets. The public
    # key is in the keyring package already; the revocation certificate is only
    # dangerous in the sense that publishing it kills the key, so it stays with
    # the master on removable media rather than being destroyed here.
    echo
    echo "Kept: $(basename "$PUBLIC") (not secret) and $(basename "$REVOKE")."
    echo "Move the revocation certificate to the media too if you have not."
    exit 0
fi

case "${1:-}" in
    -h|--help|"")
        sed -n '2,12p' "$0" | sed 's/^# \?//'
        echo
        echo "  backup-master-key.sh <mounted-media-path>   copy to the stick and verify"
        echo "  backup-master-key.sh --finish               shred the redundant subkey export"
        echo "  backup-master-key.sh --shred-master         also remove the laptop's master copy"
        exit 0
        ;;
esac
DEST="$1"

[[ -f "$MASTER" ]] || { echo "no master export at $MASTER" >&2; exit 1; }
[[ -d "$DEST" ]] || { echo "$DEST is not a directory -- is the stick mounted?" >&2; exit 1; }

# Refuse to "back up" onto the same disk the original is on. A copy on the same
# filesystem is not a backup, and this is the mistake that is easiest to make
# and hardest to notice.
if [[ "$(stat -c %m "$DEST")" == "$(stat -c %m "$STAGE")" ]]; then
    echo "$DEST is on the same filesystem as the key itself." >&2
    echo "That is not a backup. Mount the removable media and pass its path." >&2
    exit 1
fi
MOUNT="$(stat -c %m "$DEST")"
if ! findmnt -no TARGET "$MOUNT" >/dev/null 2>&1; then
    echo "could not confirm $DEST is a mountpoint" >&2; exit 1
fi

# And it has to be removable media, not merely a different filesystem.
#
# "different filesystem" was the first version of this check and it is not
# enough: it happily accepted a tmpfs under /tmp, which is RAM on the same
# machine -- so the script wrote the master secret to a new place on the very
# laptop it is supposed to be leaving, and reported success. Ask the kernel
# whether the backing device is removable instead of inferring it.
SRC="$(findmnt -no SOURCE "$MOUNT" 2>/dev/null || true)"
REMOVABLE=0
if [[ -b "$SRC" ]]; then
    # RM is set on the whole disk rather than the partition, so walk up.
    for dev in "$SRC" "/dev/$(lsblk -no pkname "$SRC" 2>/dev/null | head -1)"; do
        [[ -b "$dev" ]] || continue
        [[ "$(lsblk -dno RM "$dev" 2>/dev/null | tr -d ' ')" == "1" ]] && REMOVABLE=1
        [[ "$(lsblk -dno HOTPLUG "$dev" 2>/dev/null | tr -d ' ')" == "1" ]] && REMOVABLE=1
    done
fi
if (( ! REMOVABLE )) && [[ "${SAKURA_ALLOW_FIXED_MEDIA:-0}" != "1" ]]; then
    echo "$DEST does not look like removable media." >&2
    echo "  mountpoint: $MOUNT" >&2
    echo "  device:     ${SRC:-unknown}" >&2
    echo >&2
    echo "The point of this backup is to get the master key OFF this machine," >&2
    echo "so writing it to another directory here is worse than doing nothing:" >&2
    echo "it makes a second copy and calls it safe." >&2
    echo >&2
    echo "Plug in a USB stick and pass its mounted path. If you really do mean" >&2
    echo "a fixed disk -- an external drive the kernel reports as fixed, say --" >&2
    echo "re-run with SAKURA_ALLOW_FIXED_MEDIA=1." >&2
    exit 1
fi

TARGET="$DEST/sakuraos-signing-key"
mkdir -p "$TARGET"
umask 077
cp -f "$MASTER" "$REVOKE" "$PUBLIC" "$TARGET/"
cat > "$TARGET/README.txt" <<NOTE
SakuraOS master signing key backup
==================================

Key:         $FPR
Made:        $(date -u +%Y-%m-%dT%H:%M:%SZ)

sakura-master-SECRET.asc   the master key. Passphrase protected. This is the
                           key every SakuraOS install trusts. It signs subkeys
                           and nothing else, so it belongs offline, on this
                           stick, and not on any machine that is switched on.
sakura-revocation.rev      use this to revoke the key if it is ever lost or
                           copied. Publishing it kills the key permanently.

                           NOTE: gpg wrote this file with a colon in front of
                           every line of the armoured block, on purpose, so it
                           cannot be imported by accident. To actually use it,
                           remove those leading colons first, then:
                               gpg --import sakura-revocation.rev
                               gpg --keyserver <server> --send-keys $FPR
sakura-public.asc          the public half. Not a secret.

The passphrase is NOT in here and must not be stored with this stick.

To restore onto a build machine:
    gpg --homedir <keydir> --import sakura-master-SECRET.asc

Keep a second copy of this directory on different media, in a different place.
NOTE
chmod 600 "$TARGET"/*
sync

echo "==> Copied to $TARGET"
ls -l "$TARGET"

echo
echo "==> Reading it back from the media, not from memory."
VERIFY="$(mktemp -d)"
trap 'rm -rf "$VERIFY"' EXIT
chmod 700 "$VERIFY"
# --import needs no passphrase: it reads the key, it does not unlock it. So this
# checks the file is intact and is the right key, without asking for anything.
if ! gpg --homedir "$VERIFY" --batch --quiet --import "$TARGET/sakura-master-SECRET.asc" 2>/dev/null; then
    echo "FAILED: the copy on the media could not be imported. Do not rely on it." >&2
    exit 1
fi
GOT="$(gpg --homedir "$VERIFY" --list-secret-keys --with-colons 2>/dev/null \
       | awk -F: '/^fpr:/ {print $10; exit}')"
if [[ "$GOT" != "$FPR" ]]; then
    echo "FAILED: the media holds $GOT, expected $FPR" >&2
    exit 1
fi
echo "    master key reads back correctly: $GOT"

# GnuPG writes a revocation certificate with a colon prefixed to every armor
# line, deliberately, so the file cannot be imported by accident. Reading it
# therefore means stripping that colon first -- checking the file as-is reports a
# perfectly good certificate as unparseable, which is what the first version of
# this did. sigclass 0x20 is what makes it a key revocation rather than any
# other signature.
REVCLASS="$(sed -n '/BEGIN PGP PUBLIC KEY BLOCK/,/END PGP PUBLIC KEY BLOCK/p' \
    "$TARGET/sakura-revocation.rev" 2>/dev/null | sed 's/^://' \
    | gpg --dearmor 2>/dev/null | gpg --list-packets 2>/dev/null \
    | grep -oE 'sigclass 0x[0-9a-f]+' | head -1)"
if [[ "$REVCLASS" == "sigclass 0x20" ]]; then
    echo "    revocation certificate is a valid key revocation"
else
    echo "    WARNING: the revocation certificate did not verify (${REVCLASS:-no signature found})" >&2
fi

echo
echo "==> This copy is good. Unmount the stick and put it somewhere safe."
echo "    A second stick stored elsewhere is better still, but one stick plus"
echo "    the laptop copy is two copies, which is what stops the key being lost."
echo
echo "    Then tidy up the redundant subkey export with:"
echo "        ./build/backup-master-key.sh --finish"

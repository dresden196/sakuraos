#!/usr/bin/env bash
# Publish an installation image, with the things needed to verify it.
#
#   ./build/publish-iso.sh [path-to-iso]
#
# Runs on the build box, because that is where the signing key is. Publishes to
# repo.sakuraos.org rather than into the website: the site stays a static page,
# and the artefact host is already the thing serving large files.
#
# Three files go up together. The image, a SHA256 line for the person who just
# wants to know the download was not truncated, and a detached signature for the
# person who wants to know we made it. A checksum alone answers neither question
# honestly -- it is served from the same host as the image, so anything able to
# replace one can replace the other. The signature is what makes it evidence.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SSH_TARGET="${SAKURA_REPO_SSH:-sakura-repo}"
DEST="${SAKURA_ISO_PATH:-/srv/sakura/repo/iso}"
PUBLIC="${SAKURA_REPO_PUBLIC:-repo.sakuraos.org}"

if [[ -n "${SAKURA_GPGHOME:-}" ]]; then
    GPGHOME="$SAKURA_GPGHOME"
elif [[ -d "$REPO_ROOT/keys/prod-gnupg" ]]; then
    GPGHOME="$REPO_ROOT/keys/prod-gnupg"
else
    GPGHOME="$REPO_ROOT/keys/dev-gnupg"
fi

ISO="${1:-$(ls -t "$REPO_ROOT"/out/*.iso 2>/dev/null | head -1)}"
[[ -f "$ISO" ]] || { echo "no ISO to publish" >&2; exit 1; }
NAME="$(basename "$ISO")"

SIGNER_UID="$(gpg --homedir "$GPGHOME" --list-secret-keys --with-colons 2>/dev/null \
              | awk -F: '/^uid:/ {print $10; exit}')"
case "$SIGNER_UID" in
    *"NOT FOR PRODUCTION"*)
        echo "refusing to publish an image signed with the development key." >&2
        echo "  key: $SIGNER_UID" >&2
        echo "See keys/README.md. Nothing it signs may reach a user." >&2
        exit 1
        ;;
esac
echo ">> signing with: $SIGNER_UID"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo ">> checksumming $NAME ($(numfmt --to=iec --suffix=B "$(stat -c%s "$ISO")" 2>/dev/null || stat -c%s "$ISO"))"
( cd "$(dirname "$ISO")" && sha256sum "$NAME" ) > "$WORK/$NAME.sha256"

echo ">> signing"
gpg --homedir "$GPGHOME" --batch --yes --detach-sign --armor \
    -o "$WORK/$NAME.sig" "$ISO"

# Verify what we are about to publish, from the files we are about to publish,
# rather than trusting that the two commands above did what they said.
( cd "$(dirname "$ISO")" && sha256sum -c "$WORK/$NAME.sha256" ) >/dev/null \
    || { echo "the checksum file does not match the image" >&2; exit 1; }
gpg --homedir "$GPGHOME" --verify "$WORK/$NAME.sig" "$ISO" 2>&1 | grep -q "Good signature" \
    || { echo "the signature does not verify against the signing key" >&2; exit 1; }
echo ">> checksum and signature verify locally"

echo ">> uploading to $PUBLIC"
ssh "$SSH_TARGET" "mkdir -p $DEST"
# Image first, then the small files: a checksum that names a file which has not
# finished arriving is worse than no checksum at all.
rsync -a --info=progress2 "$ISO" "$SSH_TARGET:$DEST/$NAME"
rsync -a "$WORK/$NAME.sha256" "$WORK/$NAME.sig" "$SSH_TARGET:$DEST/"

# A stable name for the newest image, so a download link does not have to be
# edited on every release. Written last, for the same reason as above.
# The image and the signature can be symlinks, because gpg is told both
# filenames explicitly. The checksum file cannot: sha256sum -c reads the name
# out of the file, so a symlink to the versioned checksum tells somebody who
# downloaded sakura-latest-x86_64.iso to go and check a file they do not have.
# The published instructions would then fail for every single person following
# them. So the stable checksum is written with the stable name in it.
LATEST_SUM="$(cut -d' ' -f1 < "$WORK/$NAME.sha256")  sakura-latest-x86_64.iso"
printf '%s\n' "$LATEST_SUM" > "$WORK/sakura-latest-x86_64.iso.sha256"
rsync -a "$WORK/sakura-latest-x86_64.iso.sha256" "$SSH_TARGET:$DEST/"
ssh "$SSH_TARGET" "cd $DEST && ln -sfn '$NAME' sakura-latest-x86_64.iso \
    && ln -sfn '$NAME.sig' sakura-latest-x86_64.iso.sig \
    && printf '%s\n' '$NAME' > latest.txt"

# The verification instructions on the website tell people to fetch this, so it
# has to be there and it has to be current. Published from the same keyring that
# just signed the image, so the two cannot drift apart.
echo ">> publishing the signing key"
gpg --homedir "$GPGHOME" --armor --export "$(gpg --homedir "$GPGHOME" \
    --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')" \
    > "$WORK/sakura-signing-key.asc"
rsync -a "$WORK/sakura-signing-key.asc" "$SSH_TARGET:$(dirname "$DEST")/sakura-signing-key.asc"

echo ">> verifying over HTTPS"
for f in "$NAME" "$NAME.sha256" "$NAME.sig" latest.txt; do
    code=$(curl -sS -o /dev/null -w '%{http_code}' -r 0-0 "https://$PUBLIC/iso/$f" || echo 000)
    printf '   %-50s %s\n' "$f" "$code"
    [[ "$code" == "200" || "$code" == "206" ]] || { echo "not reachable" >&2; exit 1; }
done

echo
echo ">> published: https://$PUBLIC/iso/$NAME"
echo "   stable:    https://$PUBLIC/iso/sakura-latest-x86_64.iso"

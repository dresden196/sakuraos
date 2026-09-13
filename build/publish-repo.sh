#!/usr/bin/env bash
# Publish the built repositories to the SakuraOS mirror.
#
# Uploads what build-packages.sh produced. The database is written last and
# --delete-after runs at the end, so a client that fetches mid-publish sees
# the old database and the old packages rather than a database describing
# files that have not arrived yet.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Refuse to publish packages built from a dirty tree.
#
# pkgrel is 1.<commit count>, so a package built with uncommitted changes
# carries the same version as one built from the commit alone while containing
# something different. pacman will not upgrade between two identical versions,
# so publishing one strands every machine that already has the other, silently
# and permanently. Build them for testing, do not ship them.
if [[ -f "$REPO_ROOT/repo/.dirty-build" && "${SAKURA_PUBLISH_DIRTY:-0}" != "1" ]]; then
    echo "publish-repo: these packages were $(cat "$REPO_ROOT/repo/.dirty-build")" >&2
    echo "              Their version does not identify their contents, so a" >&2
    echo "              machine already on that version would never upgrade." >&2
    echo "              Commit the changes and rebuild." >&2
    exit 1
fi

# An ssh alias for the upload, and the public name only for the closing message.
# See the note in canary.sh: the address and port are operator configuration.
SSH_TARGET="${SAKURA_REPO_SSH:-sakura-repo}"
PUBLIC_NAME="${SAKURA_REPO_PUBLIC:-repo.sakuraos.org}"
DEST="${SAKURA_REPO_PATH:-/srv/sakura/repo}"

[[ -d "$REPO_ROOT/repo" ]] || { echo "nothing built -- run build/build-packages.sh first" >&2; exit 1; }

for r in sakura-core sakura-extra; do
    src="$REPO_ROOT/repo/$r"
    [[ -d "$src" ]] || continue
    count=$(find "$src" -name '*.pkg.tar.zst' | wc -l)
    size=$(du -sh "$src" | cut -f1)
    echo ">> $r: $count packages, $size"

    # Packages first, database after: a database is only meaningful once the
    # files it names are already fetchable.
    rsync -az --info=stats1 \
        --include='*/' --include='*.pkg.tar.zst' --include='*.pkg.tar.zst.sig' --exclude='*' \
        "$src/" "$SSH_TARGET:$DEST/$r/" | sed 's/^/     /'
    rsync -az --delete-after --info=stats1 \
        "$src/" "$SSH_TARGET:$DEST/$r/" | sed 's/^/     /'
done

echo
echo ">> published to https://$PUBLIC_NAME/"

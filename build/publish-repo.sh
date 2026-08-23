#!/usr/bin/env bash
# Publish the built repositories to the SakuraOS mirror.
#
# Uploads what build-packages.sh produced. The database is written last and
# --delete-after runs at the end, so a client that fetches mid-publish sees
# the old database and the old packages rather than a database describing
# files that have not arrived yet.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${SAKURA_REPO_HOST:-173.233.87.167}"
PORT="${SAKURA_REPO_PORT:-37156}"
USER="${SAKURA_REPO_USER:-sakura}"
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
    rsync -az --info=stats1 -e "ssh -p $PORT" \
        --include='*/' --include='*.pkg.tar.zst' --include='*.pkg.tar.zst.sig' --exclude='*' \
        "$src/" "$USER@$HOST:$DEST/$r/" | sed 's/^/     /'
    rsync -az --delete-after --info=stats1 -e "ssh -p $PORT" \
        "$src/" "$USER@$HOST:$DEST/$r/" | sed 's/^/     /'
done

echo
echo ">> published to http://$HOST/"

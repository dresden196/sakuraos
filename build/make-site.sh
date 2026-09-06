#!/usr/bin/env bash
# Wrap site/index.html into a standalone HTML document.
#
# site/index.html is authored for the Claude artifact runtime, which supplies
# the <!doctype>, <head>, charset and viewport around it. Served straight off
# nginx none of that exists, so the browser falls back to windows-1252 and
# every em dash renders as "a€"" -- and with no viewport the page loads
# zoomed out on a phone. Both were live on sakuraos.org until this script.
#
# One source, two outputs: publish site/index.html as the artifact, deploy
# out/site/index.html to the web server.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/site/index.html"
OUT_DIR="$REPO_ROOT/out/site"
OUT="$OUT_DIR/index.html"

[[ -f "$SRC" ]] || { echo "no $SRC" >&2; exit 1; }
mkdir -p "$OUT_DIR"

# The recovery demo's frames. They are real screenshots of an installed
# machine, served as files rather than inlined: six images is most of a
# megabyte, and the page already carries its photograph as a data URI.
if [[ -d "$REPO_ROOT/site/shots" ]]; then
    mkdir -p "$OUT_DIR/shots"
    cp -f "$REPO_ROOT/site/shots/"* "$OUT_DIR/shots/"
    echo ">> copied $(ls "$REPO_ROOT/site/shots" | wc -l) screenshots"
fi

# Stamp each screenshot reference with a hash of the file it points at.
#
# nginx serves these with max-age=300, so replacing an image leaves anyone who
# already has it looking at the old one, with no way to tell. That happened:
# the screenshots were recaptured and the page still showed the previous set.
# A URL that changes when the bytes change cannot go stale, and an unchanged
# image keeps its URL and stays cached.
stamp_shots() {
    local page="$1" dir="$2" f name hash
    for f in "$dir"/*; do
        [[ -f "$f" ]] || continue
        name="$(basename "$f")"
        hash="$(md5sum "$f" | cut -c1-8)"
        # The references sit inside JavaScript string literals, so the
        # character right after the filename is the closing quote.
        sed -i "s#/shots/${name}\"#/shots/${name}?v=${hash}\"#g" "$page"
    done
}

# The source opens with <title>, <link> and a <style> block, then the page
# content. Split on the end of that first style block so the head-ish part
# lands in <head> where it belongs; <title> in <body> is invalid and browsers
# only sometimes recover from it.
python3 - "$SRC" "$OUT" <<'PY'
import sys
src, out = sys.argv[1], sys.argv[2]
s = open(src, encoding='utf-8').read()

marker = '</style>\n'
i = s.find(marker)
if i == -1:
    raise SystemExit("no </style> found: the source layout changed, "
                     "check the split before trusting this output")
head, body = s[:i + len(marker)], s[i + len(marker):]

open(out, 'w', encoding='utf-8').write(
    '<!doctype html>\n'
    '<html lang="en">\n'
    '<head>\n'
    '<meta charset="utf-8">\n'
    '<meta name="viewport" content="width=device-width,initial-scale=1">\n'
    '<meta name="description" content="SakuraOS is an opinionated Arch and '
    'KDE Plasma distribution: automatic restore points, guarded updates, and '
    'a kernel tuned for the hardware you own.">\n'
    + head +
    '</head>\n'
    '<body>\n'
    + body.lstrip('\n') +
    '\n</body>\n'
    '</html>\n'
)
PY

echo ">> wrote $OUT ($(stat -c%s "$OUT") bytes)"

stamp_shots "$OUT" "$OUT_DIR/shots"
echo ">> stamped $(grep -o "shots/[a-z0-9.-]*?v=" "$OUT" | wc -l) screenshot URLs"
grep -q '<meta charset="utf-8">' "$OUT" || { echo "charset missing" >&2; exit 1; }
grep -q 'name="viewport"' "$OUT" || { echo "viewport missing" >&2; exit 1; }
echo ">> charset and viewport present"

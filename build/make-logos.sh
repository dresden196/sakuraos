#!/usr/bin/env bash
# Render every SakuraOS blossom from the one drawing of it.
#
# There were four. The installer's mark, the site's copy of it, the boot
# animation and the spinning globe on the network screen were each drawn
# separately, so "the logo" meant four slightly different flowers depending on
# where you happened to be looking. Copies drift; a generator cannot.
#
# branding/sakura-mark.svg is the source. Everything below is output, and
# every one of these files is safe to delete and regenerate.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/branding/sakura-mark.svg"
[[ -r "$SRC" ]] || { echo "make-logos: no $SRC" >&2; exit 1; }
command -v rsvg-convert >/dev/null || { echo "make-logos: needs rsvg-convert (librsvg)" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Render the mark at a rotation and size.
render() {
    local rot="$1" size="$2" dest="$3"
    sed "s/__ROT__/$rot/" "$SRC" > "$TMP/m.svg"
    mkdir -p "$(dirname "$dest")"
    rsvg-convert -w "$size" -h "$size" -o "$dest" "$TMP/m.svg"
}

echo ">> installer mark"
# The installer reads an SVG out of its own qrc, so it gets the drawing rather
# than a rendering of it.
sed 's/__ROT__/0/' "$SRC" > "$REPO_ROOT/packages/sakura-installer/app/src/assets/sakura-mark.svg"

echo ">> boot splash and throbber"
PLY="$REPO_ROOT/packages/sakura-plymouth/theme"
render 0 160 "$PLY/animation-0001.png"
# 36 frames, ten degrees apart: the mark turning, so the thing on screen while
# the machine boots is the same flower as everywhere else.
for i in $(seq 0 35); do
    render "$(( i * 10 ))" 160 "$(printf '%s/throbber-%04d.png' "$PLY" "$i")"
done

echo ">> Plasma splash"
for theme in dark light; do
    render 0 220 "$REPO_ROOT/packages/sakura-theme/look-and-feel/org.sakura.$theme.desktop/contents/splash/images/blossom.png"
done

echo ">> icon theme"
for theme in SakuraDark SakuraLight; do
    for name in distributor-logo-sakura start-here-sakura sakura; do
        render 0 48 "$REPO_ROOT/packages/sakura-theme/icons/$theme/apps/48/$name.png"
    done
done

echo ">> application icons"
# The three application icons are their own drawings, not the mark, but they
# have the same problem the mark had: a PNG at each of six sizes in each of two
# themes is twelve copies to keep in step by hand. Each scalable SVG is the
# source and every PNG beside it is output.
#
# This also fails loudly. Hand-rendering left an invalid SVG on disk once with
# rsvg-convert erroring past it, and the stale PNGs stayed exactly where they
# were, so the icon "did not change" with no indication why.
for theme in SakuraDark SakuraLight; do
    base="$REPO_ROOT/packages/sakura-theme/icons/$theme/apps"
    for svg in "$base"/scalable/*.svg; do
        name="$(basename "$svg" .svg)"
        for size in 16 22 24 32 48 64; do
            mkdir -p "$base/$size"
            rsvg-convert -w "$size" -h "$size" -o "$base/$size/$name.png" "$svg"
        done
    done
done

echo ">> website"
# Rewritten in place, between the markers, so the site cannot go back to
# carrying its own copy of the drawing.
python3 - "$SRC" "$REPO_ROOT/site/index.html" <<'PY'
import re, sys
src, page = sys.argv[1], sys.argv[2]
mark = open(src).read().replace("__ROT__", "0")
# Keep the attributes the page needs, drop the standalone width/height.
mark = re.sub(r'<svg [^>]*>',
              '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" '
              'class="mark" aria-hidden="true">', mark, count=1)
mark = re.sub(r'<!--.*?-->', '', mark, flags=re.S).strip()
html = open(page).read()
new, n = re.subn(r'<svg[^>]*class="mark"[^>]*>.*?</svg>', mark, html, count=1, flags=re.S)
if not n:
    print("make-logos: no class=\"mark\" svg found in the page", file=sys.stderr)
    sys.exit(1)
open(page, "w").write(new)
print("   site/index.html updated")
PY

echo ">> done"

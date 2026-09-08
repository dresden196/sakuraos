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

echo ">> application marks"
# Rendered to PNG with rsvg, not handed over as SVG.
#
# Qt's SVG renderer is not the one the rest of the project uses. Given this
# drawing it produces noticeably fatter petals that nearly meet at the centre,
# where rsvg keeps them narrow and separated -- close enough to pass a glance
# at 26px and clearly a different flower at 150px, which is the size the
# installer shows it at. The site (a browser) and the boot splash (rsvg) agreed
# with each other and the three Qt applications did not.
#
# 512 is four times the largest on-screen use, so it stays sharp on hidpi.
#
# The store and the update centre used to draw "✿" (U+273F) in a coloured
# circle instead. That is a font glyph, not the mark: a different flower with a
# different petal count, whose shape changes with whatever font is installed.
# Three marks were in use at once -- the site and installer had this drawing,
# those two had the florette, and the launcher icons are their own thing.
for app in sakura-installer sakura-store-ui sakura-update-center; do
    dest="$REPO_ROOT/packages/$app/app/src/assets/sakura-mark.png"
    mkdir -p "$(dirname "$dest")"
    render 0 512 "$dest"
    rm -f "$REPO_ROOT/packages/$app/app/src/assets/sakura-mark.svg"
done

echo ">> boot splash and throbber"
PLY="$REPO_ROOT/packages/sakura-plymouth/theme"
render 0 160 "$PLY/animation-0001.png"
# 36 frames, ten degrees apart: the mark turning, so the thing on screen while
# the machine boots is the same flower as everywhere else.
for i in $(seq 0 35); do
    render "$(( i * 10 ))" 160 "$(printf '%s/throbber-%04d.png' "$PLY" "$i")"
done

echo ">> plymouth dialog images"
# plymouth's two-step plugin loads these unconditionally, not only when it has
# a passphrase to ask for. A theme without them fails at show_splash with
# ENOENT and plymouth falls back to its text splash -- which is exactly what
# happened here: the blossom never appeared and the boot scrolled systemd
# messages instead, with everything else about the theme correct.
#
# Every stock two-step theme ships them. Sizes follow glow's, which is the
# reference this was diagnosed against.
ply_img() {
    local dest="$1" w="$2" h="$3" body="$4"
    printf '%s\n' \
        "<svg xmlns='http://www.w3.org/2000/svg' width='$w' height='$h' viewBox='0 0 $w $h'>$body</svg>" \
        > "$TMP/d.svg"
    rsvg-convert -w "$w" -h "$h" -o "$dest" "$TMP/d.svg"
}

PLYD="$REPO_ROOT/packages/sakura-plymouth/theme"
# The passphrase dialog: a panel, a field, a padlock and the dot that stands in
# for each character typed.
ply_img "$PLYD/box.png" 360 120 \
    "<rect x='1' y='1' width='358' height='118' rx='14' fill='#241f26' fill-opacity='0.96' stroke='#ffb7c5' stroke-opacity='0.28'/>"
ply_img "$PLYD/entry.png" 280 38 \
    "<rect x='1' y='1' width='278' height='36' rx='9' fill='#1a1016' stroke='#ffb7c5' stroke-opacity='0.45'/>"
ply_img "$PLYD/bullet.png" 12 12 \
    "<circle cx='6' cy='6' r='4.5' fill='#ffb7c5'/>"
ply_img "$PLYD/lock.png" 36 44 \
    "<path d='M10 20V13a8 8 0 0 1 16 0v7' fill='none' stroke='#ffb7c5' stroke-width='3.4' stroke-linecap='round'/><rect x='5' y='19' width='26' height='21' rx='5' fill='#ffb7c5'/><circle cx='18' cy='28' r='3' fill='#241f26'/><rect x='16.6' y='29' width='2.8' height='7' rx='1.4' fill='#241f26'/>"

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

#!/usr/bin/env bash
# Check that every browser the installer offers can actually be installed.
#
# The installer hands the chosen package to pacstrap during the install, so a
# name that resolves nowhere does not degrade gracefully -- it fails the
# install, at the end, after everything else has been written.
#
# Three of the four browsers originally offered were AUR-only, and one of
# those was not even spelled the way the AUR spells it. The default was among
# them. Nothing caught it because nothing looked: the install harness never
# exercises a browser, so the whole list was decorative.
#
# A name here resolves if it is in Arch's repositories, already built into our
# own repo, or listed in the AUR manifest we rebuild from.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$REPO_ROOT/packages/sakura-installer/app/src/qml/Main.qml"
MANIFEST="$REPO_ROOT/packages/aur/manifest.txt"

[[ -r "$QML" ]] || { echo "check-browsers: cannot read $QML" >&2; exit 1; }

# Only the browser model. Other pkg: keys elsewhere in the file would
# otherwise be dragged in and reported as missing browsers.
mapfile -t PKGS < <(sed -n '/browser: "/,$p' "$QML" \
    | grep -oE '\{ pkg: "[^"]+"' | grep -oE '"[^"]+"' | tr -d '"' | sort -u)

if (( ${#PKGS[@]} == 0 )); then
    echo "check-browsers: found no browser packages in Main.qml -- the parser" >&2
    echo "                or the model shape has changed. Refusing to pass." >&2
    exit 1
fi

missing=()
for pkg in "${PKGS[@]}"; do
    where=""
    if pacman -Si "$pkg" >/dev/null 2>&1; then
        where="Arch"
    elif compgen -G "$REPO_ROOT/repo/*/os/*/${pkg}-*.pkg.tar.zst" >/dev/null; then
        where="our repo"
    elif [[ -r "$MANIFEST" ]] && grep -qx "$pkg" "$MANIFEST"; then
        where="AUR manifest (not yet built)"
    fi
    if [[ -z "$where" ]]; then
        missing+=("$pkg")
        printf '  %-24s MISSING\n' "$pkg"
    else
        printf '  %-24s %s\n' "$pkg" "$where"
    fi
done

if (( ${#missing[@]} )); then
    echo >&2
    echo "check-browsers: these cannot be installed: ${missing[*]}" >&2
    echo "                Add them to packages/aur/manifest.txt, or correct" >&2
    echo "                the name in Main.qml." >&2
    exit 1
fi
echo "check-browsers: all ${#PKGS[@]} browser choices resolve"

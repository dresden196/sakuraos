#!/bin/bash
# Which AUR package counts as "the same application".
#
# The store used to require an exact match against the id stem or the first
# word of the display name, so it found nothing for Google Chrome, Spotify or
# VS Code -- the AUR spells those google-chrome, spotify and
# visual-studio-code-bin. It has to stay strict in the other direction: vlc-git
# is a nightly build from git, not VLC, and offering it as VLC is a lie the
# user only finds out about after it is installed.
#
# Pure matching, no network: the rule is the thing under test, not the AUR.
set -uo pipefail
PASS=0; FAIL=0
check() {
    if [ "$2" = "$3" ]; then echo "  PASS  $1"; PASS=$((PASS+1))
    else echo "  FAIL  $1"; echo "          expected: $2"; echo "          actual:   $3"; FAIL=$((FAIL+1)); fi
}

SRC=""
for c in /build/packages/sakura-store/sakura-store \
         "$(dirname "$0")/../packages/sakura-store/sakura-store" \
         /usr/bin/sakura-store; do
    [ -f "$c" ] && { SRC="$c"; break; }
done
[ -n "$SRC" ] || { echo "  FAIL  cannot find the sakura-store source"; exit 1; }

# The real functions, lifted out of the shipped script rather than copied.
run_case() {
    python3 - "$SRC" "$1" "$2" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
ns = {"re": re}
exec(src[src.index("PACKAGING_SUFFIXES ="):src.index("def slugify")], ns)
exec(src[src.index("def slugify"):src.index("def variant_of")], ns)
exec(src[src.index("def variant_of"):src.index("def find_elsewhere")], ns)
candidate, bases = sys.argv[2], set(sys.argv[3].split(","))
print("yes" if ns["variant_of"](candidate, bases) else "no")
PY
}

bases() {
    python3 - "$SRC" "$1" "$2" <<'PY2'
import re, sys
src = open(sys.argv[1]).read()
ns = {"re": re}
exec(src[src.index("def slugify"):src.index("def variant_of")], ns)
exec(src[src.index("def base_names"):src.index("def find_elsewhere")], ns)
print(",".join(sorted(ns["base_names"](sys.argv[2], sys.argv[3]))))
PY2
}

slug() {
    python3 - "$SRC" "$1" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
ns = {"re": re}
exec(src[src.index("def slugify"):src.index("def variant_of")], ns)
print(ns["slugify"](sys.argv[2]))
PY
}

echo "== display names become package names =="
check "a one word name"        "spotify"            "$(slug 'Spotify')"
check "a multi word name"      "visual-studio-code" "$(slug 'Visual Studio Code')"
check "a vendor prefixed name" "google-chrome"      "$(slug 'Google Chrome')"
check "punctuation is dropped" "krita"              "$(slug 'Krita!')"
check "an empty name"          ""                   "$(slug '')"

echo
echo "== the names an application might go by =="
check "id stem and slug agree"  "videolan,vlc"               "$(bases org.videolan.VLC VLC)"
check "a useless id stem"       "client,spotify"             "$(bases com.spotify.Client Spotify)"
check "vendor is not in either" "brave,brave-browser,browser" "$(bases com.brave.Browser 'Brave Browser')"
check "a two part id"           "firefox"                    "$(bases org.firefox Firefox)"

echo
echo "== the same application, packaged differently =="
check "the bare name"          "yes" "$(run_case spotify 'client,spotify')"
check "a vendor prefix"        "yes" "$(run_case google-chrome 'chrome,google-chrome')"
check "a prebuilt binary"      "yes" "$(run_case visual-studio-code-bin 'code,visual-studio-code')"
check "an appimage"            "yes" "$(run_case krita-appimage 'krita')"
check "a stable channel"       "yes" "$(run_case obs-studio-stable 'obs-studio')"

echo
echo "== a different build, which must not be offered =="
check "a git build"            "no"  "$(run_case vlc-git 'vlc')"
check "a nightly"              "no"  "$(run_case vlc-nightly 'vlc')"
check "a dev channel"          "no"  "$(run_case google-chrome-dev 'chrome,google-chrome')"
check "a beta"                 "no"  "$(run_case firefox-beta 'firefox')"
check "an insiders build"      "no"  "$(run_case code-insiders-bin 'code,visual-studio-code')"
check "an unrelated package"   "no"  "$(run_case gitkraken 'client,spotify')"
check "a prefix of the name"   "no"  "$(run_case spot 'spotify')"

echo
echo
echo "== one row per app in a search =="
# Flathub files Steam as com.valvesoftware.Steam and the Snap Store as plain
# "steam", so a search listed it twice. A display-name match joins them when one
# side has no reverse-DNS id; two apps that both have one stay apart.
MERGE=$(python3 - "$SRC" <<'PY'
import sys
from dataclasses import dataclass, field
src = open(sys.argv[1]).read()
ns = {"dataclass": dataclass, "field": field}
exec("from __future__ import annotations\n" + src[src.index("@dataclass\nclass App"):src.index("class Source")], ns)
exec(src[src.index("def norm_id"):src.index("def _untagged")], ns)
class S:
    def __init__(self, n): self.name = n
ns["SOURCES"] = [S("flatpak"), S("repo"), S("aur"), S("snap")]
exec(src[src.index("def merge("):src.index("def read_config")], ns)
App = ns["App"]
def a(i, name, source, sid):
    return App(id=i, name=name, summary="", developer="", icon="", source=source, source_id=sid)
rows = ns["merge"]([
    [a("steam", "Steam", "snap", "steam"), a("spotify", "Spotify", "snap", "spotify")],
    [a("com.valvesoftware.Steam", "Steam", "flatpak", "com.valvesoftware.Steam"),
     a("org.gnome.Calculator", "Calculator", "flatpak", "org.gnome.Calculator")],
    [a("org.kde.kcalc", "Calculator", "repo", "kcalc")],
])
print(";".join(f"{r.name}:{r.source}+{','.join(e['source'] for e in r.also_from)}" for r in rows))
PY
)
check "Steam is one row, Flatpak first, Snap beside it" "1" "$(echo "$MERGE" | tr ';' '\n' | grep -c '^Steam:flatpak+snap$')"
check "two different Calculators stay two rows"        "2" "$(echo "$MERGE" | tr ';' '\n' | grep -c '^Calculator:')"
check "an app only on Snap keeps its row"              "1" "$(echo "$MERGE" | tr ';' '\n' | grep -c '^Spotify:snap+$')"

echo
echo "== the source a tile names =="
# The same rule as the app page: the copy already installed, otherwise
# SakuraOS, Flatpak, Snap, AppImage, the AUR. Tiles named the source a result
# came from -- Flatpak for anything on Flathub -- while the page preselected
# SakuraOS's package.
CHIP=$(python3 - "$SRC" <<'PY'
import sys
from dataclasses import dataclass, field
src = open(sys.argv[1]).read()
ns = {"dataclass": dataclass, "field": field}
exec("from __future__ import annotations\n" + src[src.index("@dataclass\nclass App"):src.index("class Source")], ns)
exec(src[src.index("PREFERRED = {"):src.index("def repo_ids")], ns)
App = ns["App"]
def a(source, installed=False, also=()):
    return App(id="x.y.Z", name="Z", source=source, source_id="z", installed=installed,
               also_from=[{"source": s, "installed": i} for s, i in also])
cases = [
    ("repo|flatpak", a("flatpak", also=[("repo", False)]), True),
    ("flatpak|repo,snap", a("flatpak", installed=True, also=[("repo", False), ("snap", False)]), True),
    ("snap|flatpak", a("flatpak", also=[("snap", True)]), True),
    ("repo|", a("flatpak", also=[("repo", False)]), False),
    ("snap|", a("snap"), True),
    ("flatpak|aur", a("aur", also=[("flatpak", False)]), True),
]
bad = []
for want, app, complete in cases:
    ns["finish"]([app], complete)
    got = app.default_source + "|" + ",".join(app.other_sources)
    if got != want:
        bad.append(f"{want}!={got}")
print(";".join(bad) or "OK")
PY
)
check "tiles name the source Install would use" "OK" "$CHIP"

echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

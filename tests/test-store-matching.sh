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
echo "  $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

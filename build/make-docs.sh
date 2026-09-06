#!/usr/bin/env bash
# Build the documentation site from site/docs/*.html content fragments.
#
# Each fragment is the body of one page: no <head>, no nav, no footer. This
# script wraps them in the shared shell so the navigation exists in exactly
# one place -- ten hand-copied sidebars drift within a week.
#
# Order and titles come from PAGES below, which is also what the sidebar is
# generated from, so adding a page means adding one line here.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/site/docs"
OUT="$REPO_ROOT/out/site/docs"
# Where these pages will be served from. They now live at the root of
# wiki.sakuraos.org rather than under /docs on the main site, and every link
# in them is absolute, so the prefix has to be a variable rather than baked
# into forty href attributes.
DOCS_BASE="${DOCS_BASE-}"

# slug|nav label|page title|one-line summary
PAGES=(
"index|Overview|SakuraOS wiki|What this system does, and where each part is written down."
"install|Installing|Installing SakuraOS|What the installer asks, what it writes, and the disk layout it creates."
"recovery|Recovery|Restore points and recovery|Snapshots, the boot menu, the failed-boot watchdog, and how to go back."
"updates|Updates|How updates work|The schedule, the restore point, and what gets held back."
"store|App Store|The App Store|Four sources in one place, and what installing from each one means."
"aur|The AUR|The AUR on SakuraOS|Off by default, scanned against known campaigns, and reviewed before it builds."
"terminal|Terminal Assist|Terminal Assist|The check inside pacman, the layer in your shell, and how to override both."
"kernel|Kernel|The kernel|The CachyOS build, the x86-64-v3 check, and what older machines get."
"tuning|Tuning|Tuning defaults|The sysctl values, the I/O scheduler rules, and compressed swap."
"windows|Windows apps|Windows applications|Wine installed when you need it, and removed when you do not."
)

mkdir -p "$OUT"

nav_html() {
    local current="$1" entry slug label
    for entry in "${PAGES[@]}"; do
        IFS='|' read -r slug label _ _ <<<"$entry"
        local href="$DOCS_BASE/$slug"
        [[ "$slug" == "index" ]] && href="$DOCS_BASE/"
        if [[ "$slug" == "$current" ]]; then
            printf '      <a class="on" href="%s">%s</a>\n' "$href" "$label"
        else
            printf '      <a href="%s">%s</a>\n' "$href" "$label"
        fi
    done
}

built=0
for entry in "${PAGES[@]}"; do
    IFS='|' read -r slug label title summary <<<"$entry"
    frag="$SRC/$slug.html"
    [[ -f "$frag" ]] || { echo "missing $frag" >&2; exit 1; }

    {
        cat <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="$summary">
<title>$title · SakuraOS</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Newsreader:ital,opsz,wght@0,6..72,200..500;1,6..72,200..400&family=Karla:wght@300;400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<link rel="stylesheet" href="$DOCS_BASE/docs.css">
</head>
<body>
<a class="skip" href="#content">Skip to content</a>
<header class="topbar">
  <a class="brand" href="/">SakuraOS</a>
  <span class="crumb">Wiki</span>
</header>
<div class="shell">
  <nav class="side" aria-label="Documentation">
$(nav_html "$slug")
  </nav>
  <main id="content">
EOF
        cat "$frag"
        cat <<'EOF'
  </main>
</div>
<footer class="foot">
  <p>SakuraOS is built on Arch Linux and is not affiliated with the Arch Linux
  project. KDE and Plasma are trademarks of KDE e.V.</p>
</footer>
</body>
</html>
EOF
    } > "$OUT/$slug.html"
    built=$((built + 1))
done

cp "$SRC/docs.css" "$OUT/docs.css"
echo ">> built $built pages into $OUT"

# A page that says nothing is worse than no page: catch an empty fragment
# before it reaches the server rather than after.
for f in "$OUT"/*.html; do
    if [[ $(wc -c <"$f") -lt 1200 ]]; then
        echo "suspiciously small: $f ($(wc -c <"$f") bytes)" >&2; exit 1
    fi
done
echo ">> all pages have content"

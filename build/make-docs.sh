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
# The wiki, in sections. A line beginning with ## opens a section in the
# sidebar; everything after it belongs to that section until the next one.
#
# Ordered the way somebody arrives rather than the way the system is built:
# what it is, how to install it, how to use it, what to do when it goes wrong,
# and only then how it works underneath.
PAGES=(
"##Get started"
"index|Overview|SakuraOS wiki|What SakuraOS is, and where to find everything in this wiki."
"why|Why SakuraOS|Why SakuraOS|What SakuraOS adds on top of Arch Linux, and who it is for."
"requirements|System requirements|System requirements|What a computer needs to run SakuraOS."
"install-media|Making a USB|Making a USB and starting from it|Downloading, checking and writing the image, then starting the computer from it."
"install|Installing|Installing SakuraOS|Every screen of the installer, in order."
"dual-boot|Dual boot with Windows|Installing beside Windows|Keeping Windows and choosing between the two at startup."
"first-run|After installing|After installing|What is already set up, and the few things worth doing yourself."
"faq|FAQ|Frequently asked questions|Short answers to the questions people ask first."

"##Everyday use"
"store|App Store|The App Store|Finding, installing and removing applications, and choosing where they come from."
"updates|Updates|Updates|When updates install, what gets held back, and how to update by hand."
"settings|SakuraOS settings|The SakuraOS settings page|Every setting on the SakuraOS page in System Settings."
"aur|The AUR|The AUR|Turning it on, reviewing what you build, and the helpers yay and paru."
"hardware|Hardware and drivers|Hardware and drivers|Graphics cards, wireless, printers and laptops."
"gaming|Gaming|Gaming|Steam, Proton, controllers, and what to try when a game will not start."
"windows|Windows apps|Windows applications|Running Windows programs with Wine."
"drives|Other drives|Other drives and USB sticks|Opening, mounting and formatting drives other than the system disk."
"backups|Backups|Backups|Why restore points are not backups, and how to set one up."
"privacy|Privacy|Privacy|What SakuraOS collects, and which servers your computer contacts."

"##Fixing problems"
"troubleshooting|Troubleshooting|Troubleshooting|Common problems and how to fix them."
"recovery|Going back|Going back to a restore point|Undoing an update or a change, from the desktop or from the boot menu."
"password|Forgotten password|Resetting a forgotten password|Getting back into an account from the SakuraOS USB."
"logs|Logs and bug reports|Logs and bug reports|What to collect before asking for help, and where to send it."
"help|Getting help|Getting help|Where to ask questions and report problems."
"uninstall|Uninstalling|Uninstalling SakuraOS|Removing SakuraOS, on its own disk or beside Windows."

"##How it works"
"how-recovery|Restore points|How restore points and recovery work|Snapper, the recovery screen, and how a rollback replaces the system."
"disk-layout|Disk layout|Disk layout|The partitions and BTRFS subvolumes the installer creates, and why."
"terminal|Terminal Assist|Terminal Assist|The check inside pacman, the check in your shell, and how to override them."
"kernel|Kernel|The kernel|The CachyOS build, the processor check, and what older machines get."
"tuning|Tuning|Tuning defaults|The sysctl values, the I/O scheduler rules and compressed swap."
"glossary|Glossary|Glossary|The words this wiki uses, explained."

"##Project"
"security|Security|Security|Updates, signed packages, what is and is not protected, and how to report a security problem."
"contributing|Contributing|Contributing|Where the source is, and how to help."
)

# The date of the SakuraOS release every page was last read against, as the
# installer image names it. Bumped by hand after checking, never automatically:
# a date that moves on its own would claim checks that nobody did.
CHECKED_AGAINST="${CHECKED_AGAINST:-26 September 2026}"

mkdir -p "$OUT"

nav_html() {
    local current="$1" entry slug label
    for entry in "${PAGES[@]}"; do
        # A section heading, not a page.
        if [[ "$entry" == "##"* ]]; then
            printf '      <span class="side-sec">%s</span>\n' "${entry#\#\#}"
            continue
        fi
        [[ -z "$entry" ]] && continue
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
    [[ "$entry" == "##"* || -z "$entry" ]] && continue
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
  <a class="brand" href="https://sakuraos.org/">SakuraOS</a>
  <span class="crumb">Wiki</span>
  <nav class="topnav">
    <a href="$DOCS_BASE/">Wiki</a>
    <a href="$DOCS_BASE/help">Get help</a>
    <a href="https://github.com/dresden196/sakuraos">Source</a>
    <a href="https://blog.sakuraos.org/">Blog</a>
    <a href="https://sakuraos.org/">Site</a>
  </nav>
</header>
<div class="shell">
  <nav class="side" id="pages" aria-label="Documentation">
$(nav_html "$slug")
  </nav>
  <main id="content">
<a class="jump" href="#pages">All pages &darr;</a>
EOF
        cat "$frag"
        cat <<EOF
<p class="checked">Last checked against the SakuraOS release of $CHECKED_AGAINST. If your system
behaves differently from this page, the page is wrong:
<a href="https://github.com/dresden196/sakuraos/issues">please report it</a>.</p>
EOF
        cat <<'EOF'
  </main>
</div>
<footer class="foot">
  <p>SakuraOS is based on Arch Linux and is not affiliated with the Arch Linux
  project. KDE and Plasma are trademarks of KDE e.V.
  The wiki is <a href="https://github.com/dresden196/sakuraos/tree/master/site/docs">in the repository</a>
  and licensed under the GPL-3.0 like the rest of SakuraOS.</p>
</footer>
</body>
</html>
EOF
    } > "$OUT/$slug.html"
    built=$((built + 1))
done

cp "$SRC/docs.css" "$OUT/docs.css"
# Screenshots. Every one of them is referenced from a page, and a reference to
# a picture that is not there is a broken page, so check both directions.
rm -rf "$OUT/img"; mkdir -p "$OUT/img"
cp "$SRC"/img/* "$OUT/img/"
for ref in $(grep -ohE 'src="/img/[^"]+"' "$SRC"/*.html | sed -E 's#src="/img/([^"]+)"#\1#' | sort -u); do
    [[ -f "$SRC/img/$ref" ]] || { echo "missing picture: img/$ref" >&2; exit 1; }
done
for img in "$SRC"/img/*; do
    grep -q "/img/$(basename "$img")" "$SRC"/*.html || { echo "unused picture: $img" >&2; exit 1; }
done
echo ">> built $built pages into $OUT"

# A page that says nothing is worse than no page: catch an empty fragment
# before it reaches the server rather than after.
for f in "$OUT"/*.html; do
    if [[ $(wc -c <"$f") -lt 1200 ]]; then
        echo "suspiciously small: $f ($(wc -c <"$f") bytes)" >&2; exit 1
    fi
done
echo ">> all pages have content"

# Headings get ids, so any section can be linked to, and then every link
# between pages is checked: the page must exist and so must the section. A
# wiki whose links quietly land at the top of the wrong page is the kind of
# thing nobody reports and everybody notices.
python3 - "$OUT" <<'PY'
import html, os, re, sys

out = sys.argv[1]
pages = {f[:-5]: os.path.join(out, f) for f in os.listdir(out) if f.endswith(".html")}

def slugify(text):
    text = html.unescape(re.sub(r"<[^>]+>", "", text)).lower()
    text = re.sub(r"[’']", "", text)
    return re.sub(r"[^a-z0-9]+", "-", text).strip("-")

ids = {}
for name, path in pages.items():
    src = open(path, encoding="utf-8").read()
    main = src.index('<main id="content">')
    seen = set(re.findall(r'\bid="([^"]+)"', src))
    def add_id(m):
        tag, attrs, body = m.group(1), m.group(2), m.group(3)
        if "id=" in attrs:
            return m.group(0)
        base = slugify(body) or tag
        new, n = base, 2
        while new in seen:
            new, n = f"{base}-{n}", n + 1
        seen.add(new)
        return f'<{tag}{attrs} id="{new}">{body}</{tag}>'
    body = re.sub(r"<(h[23])([^>]*)>(.*?)</\1>", add_id, src[main:], flags=re.S)
    src = src[:main] + body
    open(path, "w", encoding="utf-8").write(src)
    found = re.findall(r'\bid="([^"]+)"', src)
    dupes = sorted({i for i in found if found.count(i) > 1})
    if dupes:
        sys.exit(f"{name}: duplicate ids {dupes}")
    ids[name] = set(found)

bad = []
for name, path in pages.items():
    src = open(path, encoding="utf-8").read()
    for href in re.findall(r'href="([^"]+)"', src):
        if re.match(r"^(https?:|mailto:)", href) or href.endswith(".css"):
            continue
        if href.startswith("#"):
            target, anchor = name, href[1:]
        elif href.startswith("/"):
            path_part, _, anchor = href[1:].partition("#")
            target = path_part or "index"
        else:
            bad.append(f"{name}: relative link {href}")
            continue
        if target not in pages:
            bad.append(f"{name}: link to missing page {href}")
        elif anchor and anchor not in ids[target]:
            bad.append(f"{name}: link to missing section {href}")
if bad:
    sys.exit("\n".join(bad))
print(f">> headings have ids; links between {len(pages)} pages all resolve")
PY

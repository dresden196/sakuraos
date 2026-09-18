#!/usr/bin/env bash
# Build the SakuraOS blog from site/blog/*.html content fragments.
#
# Same shape as make-docs.sh, and for the same reason: a fragment is the piece
# somebody writes, and everything around it -- head, navigation, dates, feed --
# is generated, so a new post is one file and one line in the manifest below.
#
# Output is a static directory: an index, one page per post, a stylesheet and
# an Atom feed. Served at the root of blog.sakuraos.org.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO_ROOT/site/blog"
OUT="$REPO_ROOT/out/site/blog"
BASE="${BLOG_BASE-}"
SITE="https://blog.sakuraos.org"

# Newest first. Format: slug|date|tag|title|summary
#
# The slug is the filename without .html and without the date prefix; the date
# prefix on the file keeps the directory in order on disk, and the URL stays
# clean.
POSTS=(
"sakuraos-1-0-cherry-blossom|2026-09-18|Release|SakuraOS 1.0 Cherry Blossom|Arch Linux with the parts that usually take a weekend already decided, and a way back when an update goes wrong."
)

mkdir -p "$OUT"

# The mark, from the one drawing of it.
MARK="$(sed 's/__ROT__/0/' "$REPO_ROOT/branding/sakura-mark.svg" \
        | sed '/<!--/,/-->/d' \
        | sed '1s#<svg [^>]*>#<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" aria-hidden="true">#')"

human_date() { date -u -d "$1" +"%-d %B %Y"; }
rfc3339()    { date -u -d "$1" +"%Y-%m-%dT00:00:00Z"; }

topbar() {
    local crumb="$1"
    cat <<EOF
<header class="topbar">
  <div class="bar">
    <a class="brand" href="https://sakuraos.org/">
$MARK
      <span>SakuraOS</span>
    </a>
    <span class="crumb">$crumb</span>
    <nav>
      <a href="$BASE/">Blog</a>
      <a href="https://wiki.sakuraos.org/">Wiki</a>
      <a href="https://sakuraos.org/">Site</a>
    </nav>
  </div>
</header>
EOF
}

footer() {
    cat <<EOF
<footer class="foot">
  <div class="wrap">
    <p>
      <a href="$BASE/feed.xml">Atom feed</a> &nbsp;·&nbsp;
      <a href="https://sakuraos.org/">sakuraos.org</a> &nbsp;·&nbsp;
      <a href="https://wiki.sakuraos.org/">Wiki</a>
    </p>
    <p>SakuraOS is built on Arch Linux and is not affiliated with the Arch Linux
    project. KDE and Plasma are trademarks of KDE e.V.</p>
  </div>
</footer>
EOF
}

head_html() {
    local title="$1" desc="$2" canonical="$3"
    cat <<EOF
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="description" content="$desc">
<title>$title</title>
<link rel="canonical" href="$canonical">
<link rel="alternate" type="application/atom+xml" title="SakuraOS blog" href="$BASE/feed.xml">
<meta property="og:site_name" content="SakuraOS">
<meta property="og:title" content="$title">
<meta property="og:description" content="$desc">
<meta property="og:type" content="article">
<meta property="og:url" content="$canonical">
<meta name="twitter:card" content="summary">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Newsreader:ital,opsz,wght@0,6..72,200..500;1,6..72,200..400&family=Karla:wght@300;400;500;600&family=JetBrains+Mono:wght@400;500&display=swap">
<link rel="stylesheet" href="$BASE/blog.css">
</head>
<body>
<a class="skip" href="#content">Skip to content</a>
EOF
}

built=0
for i in "${!POSTS[@]}"; do
    IFS='|' read -r slug date tag title summary <<<"${POSTS[$i]}"
    frag="$SRC/$date-$slug.html"
    [[ -f "$frag" ]] || { echo "make-blog: missing $frag" >&2; exit 1; }

    # Newer and older neighbours, for the links at the foot of a post.
    prev=""; next=""
    (( i > 0 ))                    && IFS='|' read -r ps _ _ pt _ <<<"${POSTS[$((i-1))]}" && prev="$ps|$pt"
    (( i < ${#POSTS[@]} - 1 ))     && IFS='|' read -r ns _ _ nt _ <<<"${POSTS[$((i+1))]}" && next="$ns|$nt"

    {
        head_html "$title · SakuraOS" "$summary" "$SITE$BASE/$slug"
        topbar "Blog"
        echo '<div class="wrap"><article class="article" id="content">'
        printf '  <div class="meta"><span class="tag">%s</span><time datetime="%s">%s</time></div>\n' \
               "$tag" "$date" "$(human_date "$date")"
        printf '  <h1>%s</h1>\n' "$title"
        cat "$frag"
        echo '  <div class="postnav">'
        if [[ -n "$prev" ]]; then
            printf '    <a href="%s/%s">&larr; %s</a>\n' "$BASE" "${prev%%|*}" "${prev#*|}"
        else
            echo '    <span></span>'
        fi
        if [[ -n "$next" ]]; then
            printf '    <a href="%s/%s">%s &rarr;</a>\n' "$BASE" "${next%%|*}" "${next#*|}"
        fi
        echo '  </div>'
        echo '</article></div>'
        footer
        echo '</body></html>'
    } > "$OUT/$slug.html"
    built=$((built + 1))
done

# ---- index ----
{
    head_html "SakuraOS blog" "Releases and notes from the people building SakuraOS." "$SITE$BASE/"
    topbar "Blog"
    cat <<EOF
<div class="wrap">
  <div class="masthead" id="content">
    <h1>Blog</h1>
    <p>Releases, and notes on how SakuraOS is put together.</p>
  </div>
  <ul class="posts">
EOF
    for entry in "${POSTS[@]}"; do
        IFS='|' read -r slug date tag title summary <<<"$entry"
        cat <<EOF
    <li>
      <a class="post-card" href="$BASE/$slug">
        <div class="meta"><span class="tag">$tag</span><time datetime="$date">$(human_date "$date")</time></div>
        <h2>$title</h2>
        <p>$summary</p>
      </a>
    </li>
EOF
    done
    echo '  </ul>'
    echo '</div>'
    footer
    echo '</body></html>'
} > "$OUT/index.html"

# ---- Atom feed ----
{
    IFS='|' read -r _ newest_date _ _ _ <<<"${POSTS[0]}"
    cat <<EOF
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>SakuraOS blog</title>
  <subtitle>Releases and notes from the people building SakuraOS.</subtitle>
  <link href="$SITE$BASE/feed.xml" rel="self"/>
  <link href="$SITE$BASE/"/>
  <id>$SITE$BASE/</id>
  <updated>$(rfc3339 "$newest_date")</updated>
EOF
    for entry in "${POSTS[@]}"; do
        IFS='|' read -r slug date tag title summary <<<"$entry"
        cat <<EOF
  <entry>
    <title>$title</title>
    <link href="$SITE$BASE/$slug"/>
    <id>$SITE$BASE/$slug</id>
    <updated>$(rfc3339 "$date")</updated>
    <summary>$summary</summary>
    <category term="$tag"/>
  </entry>
EOF
    done
    echo '</feed>'
} > "$OUT/feed.xml"

cp "$SRC/blog.css" "$OUT/blog.css"
[[ -d "$SRC/media" ]] && { mkdir -p "$OUT/media"; cp -f "$SRC/media/"* "$OUT/media/"; }

echo ">> built $built post(s) into $OUT"

# A post that generated an empty body is a build that succeeded and shipped
# nothing, which is the failure worth catching here.
for f in "$OUT"/*.html; do
    if [[ "$(wc -c < "$f")" -lt 1200 ]]; then
        echo "make-blog: $f looks empty" >&2; exit 1
    fi
done
echo ">> index, $built post(s) and the feed all have content"

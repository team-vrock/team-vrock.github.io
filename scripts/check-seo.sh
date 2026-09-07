#!/usr/bin/env bash
set -euo pipefail

SITE="_site"
fail() { echo "SEO check FAILED: $1" >&2; exit 1; }

[ -d "$SITE" ] || fail "_site not found. Run 'bundle exec jekyll build' first."

# Core files exist
test -f "$SITE/index.html" || fail "missing index.html"
test -f "$SITE/sitemap.xml" || fail "missing sitemap.xml"
test -f "$SITE/robots.txt" || fail "missing robots.txt"
grep -q "^Sitemap:" "$SITE/robots.txt" || fail "robots.txt missing Sitemap directive"

# Homepage basics
grep -q '<h1' "$SITE/index.html" || fail "homepage has no <h1>"
grep -q 'rel="canonical" href="https://www.vrock.ch/' "$SITE/index.html" || fail "homepage canonical not absolute"
grep -q 'name="description" content=' "$SITE/index.html" || fail "homepage missing meta description"
grep -q 'application/ld+json' "$SITE/index.html" || fail "homepage missing JSON-LD"

# Canonical URLs are absolute everywhere
absolute_canon=$(grep -RL 'rel="canonical" href="https://www.vrock.ch/' --include='*.html' "$SITE" | wc -l)
[ "$absolute_canon" -eq 0 ] || fail "$absolute_canon page(s) with non-absolute canonical"

# No accidental noindex
grep -RniE 'name="robots" content="(noindex|none)' --include='*.html' "$SITE" | grep . && fail "noindex/robots none found" || true

# Sitemap uses the canonical host and contains key pages
grep -q "<loc>https://www.vrock.ch/</loc>" "$SITE/sitemap.xml" || fail "sitemap missing homepage"
grep -q "https://www.vrock.ch/topics/" "$SITE/sitemap.xml" || fail "sitemap missing topic pages"
grep -q "https://www.vrock.ch/post/" "$SITE/sitemap.xml" || fail "sitemap missing posts"

# Every post page has an H1, a description and a breadcrumb
for f in $(find "$SITE/post" -name '*.html'); do
  grep -q '<h1' "$f" || fail "no <h1> in $f"
  grep -q 'name="description" content=' "$f" || fail "no meta description in $f"
  grep -q 'class="breadcrumbs"' "$f" || fail "no breadcrumbs in $f"
done

# JSON-LD blocks parse
python3 - "$SITE" <<'PY'
import re, sys, glob, json
site = sys.argv[1]
bad = 0
for f in glob.glob(site + "/**/*.html", recursive=True):
    for block in re.findall(r'<script type="application/ld\+json">(.*?)</script>', open(f).read(), re.S):
        try:
            json.loads(block)
        except json.JSONDecodeError as e:
            print(f"invalid JSON-LD in {f}: {e}")
            bad += 1
sys.exit(1 if bad else 0)
PY

echo "SEO checks passed."

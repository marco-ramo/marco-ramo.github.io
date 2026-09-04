#!/bin/sh
# ams-15 — the sitemap's lastmod must not be older than the last commit touching index.html.
#
# robots.txt advertises this sitemap. While the page carries noindex the value is
# inconsequential, but the head comment documents lifting noindex as a planned step, and
# on that day a stale lastmod tells every crawler the page is unchanged and the launch
# content is deprioritised for recrawl. Exits non-zero when the sitemap is the older of
# the two dates.

set -eu
cd "$(dirname "$0")/.."

lastmod=$(sed -n 's/.*<lastmod>\(.*\)<\/lastmod>.*/\1/p' sitemap.xml | head -1)
committed=$(git log -1 --format=%cd --date=short -- index.html)

if [ -z "$lastmod" ]; then
  echo "ams-15 FAIL: no <lastmod> in sitemap.xml"
  exit 1
fi

if [ -z "$committed" ]; then
  echo "ams-15 SKIP: no commit history for index.html to compare against"
  exit 0
fi

# ISO dates sort lexically, so a plain string comparison is a date comparison.
if [ "$lastmod" \< "$committed" ]; then
  echo "ams-15 FAIL: sitemap.xml says $lastmod but index.html was last committed $committed"
  exit 1
fi

# ams-21: the comparison above is against the last COMMIT touching index.html, so an
# uncommitted edit moves neither side of it and the guard stays green through the exact
# moment it exists to catch -- a leg edits index.html, leaves sitemap.xml alone, sees a
# green suite, commits and pushes the stale sitemap, and the failure only appears on the
# next run, after the deploy. So also fail while index.html is dirty in the working tree
# and lastmod is older than today: that is the same staleness, caught before the commit.
# The accepted cost is a red suite during an editing session that has not yet refreshed
# the sitemap; refreshing lastmod to today's date clears it.
if [ -n "$(git status --porcelain index.html 2>/dev/null)" ]; then
  today=$(date +%F)
  if [ "$lastmod" \< "$today" ]; then
    echo "ams-15 FAIL: index.html has uncommitted changes but sitemap.xml still says $lastmod (today is $today)"
    echo "ams-15       refresh <lastmod> in sitemap.xml to $today before committing"
    exit 1
  fi
fi

echo "ams-15 PASS: sitemap lastmod $lastmod is not older than index.html's last commit $committed"
exit 0

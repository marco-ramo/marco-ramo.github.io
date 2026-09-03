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

echo "ams-15 PASS: sitemap lastmod $lastmod is not older than index.html's last commit $committed"
exit 0

#!/bin/sh
# ams-21 — the sitemap's lastmod guard must fire BEFORE the commit, not after it.
#
# ams-15 compares <lastmod> against `git log -1 -- index.html`, the date of the last
# COMMIT touching index.html. An uncommitted edit to index.html therefore moves neither
# side of that comparison, so the guard stays green through the exact moment it exists to
# catch: a leg edits index.html, forgets sitemap.xml, sees a green suite, commits and
# pushes a stale sitemap. The guard only turns red on the run after the deploy.
#
# This test builds that scenario in a throwaway clone of the repository and asserts that
# ams-15 now fails on it. It exits non-zero if ams-15 passes on a dirty index.html whose
# sitemap lastmod predates today.

set -eu
cd "$(dirname "$0")/.."
repo=$(pwd)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

work="$tmp/repo"
cp -R "$repo" "$work"

cd "$work"

# Pin both dates to the same day, far in the past, and commit them. This makes the
# scenario independent of what today's date happens to be: whatever day the suite runs,
# the sitemap is older than today, and the OLD comparison (lastmod vs last commit) is
# satisfied exactly, so the only thing this test can be detecting is the new one.
old=2020-01-01
sed "s|<lastmod>[^<]*</lastmod>|<lastmod>$old</lastmod>|" sitemap.xml > sitemap.xml.new
mv sitemap.xml.new sitemap.xml
# index.html has to be part of this commit too, or `git log -1 -- index.html` keeps
# reporting the real repository's last commit date and ams-15 fails for the OLD reason
# instead of the new one.
printf '\n<!-- ams-21 fixture commit -->\n' >> index.html
GIT_AUTHOR_DATE="$old 12:00:00 +0000" GIT_COMMITTER_DATE="$old 12:00:00 +0000" \
  git -c user.name=ams-21 -c user.email=ams-21@example.invalid \
  commit --quiet -a -m "ams-21 fixture: index.html and sitemap.xml both at $old"

committed=$(git log -1 --format=%cd --date=short -- index.html)
if [ "$committed" != "$old" ]; then
  echo "ams-21 FAIL: fixture is broken -- index.html's last commit reads $committed, not $old"
  exit 1
fi
if ! sh tests/ams-15.sh >/dev/null 2>&1; then
  echo "ams-21 FAIL: fixture is broken -- ams-15 is already red on a clean tree, so this test would pass for the wrong reason"
  exit 1
fi

# The trigger: index.html is edited and NOT committed, and sitemap.xml is untouched.
printf '\n<!-- ams-21 uncommitted edit -->\n' >> index.html

if [ -z "$(git status --porcelain index.html)" ]; then
  echo "ams-21 FAIL: fixture is broken -- index.html is not dirty in the throwaway clone"
  exit 1
fi

if sh tests/ams-15.sh >/dev/null 2>&1; then
  echo "ams-21 FAIL: ams-15 passes on an uncommitted index.html edit with a $old sitemap lastmod"
  echo "ams-21        -- the guard cannot fire until the stale sitemap has already been committed"
  exit 1
fi

echo "ams-21 PASS: ams-15 fails while index.html is dirty and the sitemap lastmod predates today"
exit 0

#!/bin/sh
# ams-12 — the portrait's first-load accessible name must say it is activatable.
#
# The portrait is a role="button" that cycles through the versions in portraits/. Its
# name used to come from a static aria-label carrying the affordance sentence; that was
# replaced by an alt per shots[] entry, which show() writes on every tap. But show()
# never runs at startup, so the accessible name before the first tap is whatever the
# static <img> markup's alt says. If that alt lacks the affordance sentence, a screen
# reader user focusing the portrait on a fresh load hears a description and nothing
# telling them it does anything.
#
# Exits non-zero when the static portrait <img> line's alt does not contain the
# affordance sentence that every shots[] entry ends with.

set -eu
cd "$(dirname "$0")/.."

sentence="Activate to show a previous version."

line=$(grep -n '<img class="portrait reveal"' index.html | head -1 | cut -d: -f1)

if [ -z "$line" ]; then
  echo "ams-12 FAIL: could not locate the static portrait <img> in index.html"
  exit 1
fi

# The tag spans several lines — the src carries the base64 image on one of its own — so
# read from the opening line up to and including the line that closes the tag.
alt=$(awk -v start="$line" 'NR >= start { print; if (/>[[:space:]]*$/) exit }' index.html \
  | grep -o 'alt="[^"]*"' | head -1)

if [ -z "$alt" ]; then
  echo "ams-12 FAIL: the static portrait <img> (line $line) carries no alt attribute"
  exit 1
fi

case "$alt" in
  *"$sentence"*)
    echo "ams-12 PASS: the static portrait alt names the affordance ($alt)"
    exit 0
    ;;
esac

echo "ams-12 FAIL: the static portrait alt does not contain \"$sentence\""
echo "  line $line alt is: $alt"
exit 1

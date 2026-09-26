#!/bin/sh
# ams-12 — the portrait's first-load accessible name must say it is activatable, but only
# once the script has made it a control (reworked by ams-40).
#
# The portrait is a role="button" that cycles through the versions in portraits/. Its
# accessible name is its alt, one per shots[] entry, which show() writes on every tap. But
# show() never runs at startup, so before the first tap the name is whatever the alt was
# left at. ams-12 guarded that a screen reader user focusing the portrait on a fresh load
# hears the affordance sentence, and first did so by putting the sentence in the static
# markup alt.
#
# ams-40 found the cost of that: with JavaScript off the script never runs, the image stays
# an ordinary picture, and the static alt still promised a control that does not exist. So
# the static alt is now the description only, and the initialisation code sets
# img.alt=shots[0].alt right after it makes the image a button. A JavaScript visitor still
# hears the affordance from first focus; a no-JavaScript visitor no longer does.
#
# Exits non-zero when any of these fails:
#   1. the static portrait <img> carries an alt, and that alt lacks the affordance sentence;
#   2. shots[0]'s alt contains the affordance sentence;
#   3. img.alt=shots[0].alt is assigned after img.setAttribute("role","button"), in the
#      startup code rather than only inside show().

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
    echo "ams-12 FAIL: the static portrait alt promises a control that does not exist with JavaScript off"
    echo "  line $line alt is: $alt"
    exit 1
    ;;
esac

shot0=$(grep -n '^[[:space:]]*{src:img.getAttribute("src")' index.html | head -1)

case "$shot0" in
  *"$sentence"*) ;;
  *)
    echo "ams-12 FAIL: shots[0]'s alt does not contain \"$sentence\""
    echo "  found: ${shot0:-no shots[0] entry}"
    exit 1
    ;;
esac

role=$(grep -n 'img.setAttribute("role","button")' index.html | head -1 | cut -d: -f1)
assign=$(grep -n 'img\.alt[[:space:]]*=[[:space:]]*shots\[0\]\.alt' index.html | head -1 | cut -d: -f1)

if [ -z "$role" ]; then
  echo "ams-12 FAIL: could not locate img.setAttribute(\"role\",\"button\") in index.html"
  exit 1
fi

if [ -z "$assign" ] || [ "$assign" -lt "$role" ]; then
  echo "ams-12 FAIL: the startup code does not set img.alt=shots[0].alt after making the portrait a button (role at line $role)"
  exit 1
fi

echo "ams-12 PASS: the static alt is description only ($alt); startup sets img.alt=shots[0].alt at line $assign, after role=button at line $role"

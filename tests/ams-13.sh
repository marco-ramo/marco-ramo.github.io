#!/bin/sh
# ams-13 — the id-carrying theme-color meta must come first in the head.
#
# apply() strips the media attribute off the meta carrying id="theme-color", so that
# meta then matches every environment. The HTML specification picks the first matching
# theme-color meta in tree order, so the fix that closed ams-02 works only while the
# id-carrying meta precedes the light-scoped one. Reorder the pair and a visitor on a
# light-mode OS who picks Dark gets a black page with off-white chrome again.
#
# Exits non-zero when the id-carrying meta is not the first theme-color meta in the
# head, or when apply() no longer removes the media attribute.

set -eu
cd "$(dirname "$0")/.."

head_start=$(grep -n '<head>' index.html | head -1 | cut -d: -f1)
head_end=$(grep -n '</head>' index.html | head -1 | cut -d: -f1)

if [ -z "$head_start" ] || [ -z "$head_end" ]; then
  echo "ams-13 FAIL: could not locate the <head> block in index.html"
  exit 1
fi

# Absolute line numbers of every theme-color meta inside the head.
lines=$(sed -n "${head_start},${head_end}p" index.html \
  | grep -n 'name="theme-color"' \
  | cut -d: -f1 \
  | awk -v off="$((head_start - 1))" '{print $1 + off}')

if [ -z "$lines" ]; then
  echo "ams-13 FAIL: no theme-color meta in the head of index.html"
  exit 1
fi

first=$(printf '%s\n' "$lines" | head -1)

if ! sed -n "${first}p" index.html | grep -q 'id="theme-color"'; then
  echo "ams-13 FAIL: the first theme-color meta in the head does not carry id=\"theme-color\""
  echo "  first theme-color meta is line $first:"
  sed -n "${first}p" index.html
  exit 1
fi

# And it must still be the one apply() unscopes, or being first buys nothing.
if ! grep -q 'removeAttribute("media")' index.html; then
  echo "ams-13 FAIL: apply() no longer calls removeAttribute(\"media\") on the theme-color meta"
  exit 1
fi

echo "ams-13 PASS: id=\"theme-color\" is the first theme-color meta (line $first) and apply() still unscopes it"
exit 0

#!/bin/sh
# ams-14 — the landing typeface is written in three places and they must agree.
#
# The CSS defaults on h1.name, the footer's #fontname label and FACES[0] in the font
# cycle all describe the same face. Nothing synced them until apply(0) was called at
# startup; this test is the drift guard that catches the three falling out of step
# again — for instance by prepending a new primary face to FACES, which would leave the
# page rendering the old face and make the first tap look like it did nothing.
#
# Exits non-zero when FACES[0]'s label, family, weight, scale or track disagrees with
# the corresponding startup value.

set -eu
cd "$(dirname "$0")/.."

faces_line=$(grep -n 'var FACES=\[' index.html | head -1 | cut -d: -f1)
[ -n "$faces_line" ] || { echo "ams-14 FAIL: no FACES array in index.html"; exit 1; }

first=$(sed -n "$((faces_line + 1))p" index.html)

f_label=$(printf '%s\n' "$first" | sed -n 's/.*label:"\([^"]*\)".*/\1/p')
f_family=$(printf '%s\n' "$first" | sed -n 's/.*family:"\([^"]*\)".*/\1/p')
f_weight=$(printf '%s\n' "$first" | sed -n 's/.*weight:\([0-9]*\).*/\1/p')
f_scale=$(printf '%s\n' "$first" | sed -n 's/.*scale:\([0-9.]*\).*/\1/p')
f_track=$(printf '%s\n' "$first" | sed -n 's/.*track:"\([^"]*\)".*/\1/p')

css_family=$(grep -n -- '--name-family:' index.html | head -1 | sed -n 's/.*--name-family:"\([^"]*\)".*/\1/p')
css_weight=$(grep -n -- '--name-weight:' index.html | head -1 | sed -n 's/.*--name-weight:\([0-9]*\).*/\1/p')
css_scale=$(grep -n -- '--name-scale:' index.html | head -1 | sed -n 's/.*--name-scale:\([0-9.]*\).*/\1/p')
css_track=$(grep -n -- '--name-track:' index.html | head -1 | sed -n 's/.*--name-track:\([^;]*\);.*/\1/p')
html_label=$(grep 'id="fontname"' index.html | sed -n 's/.*aria-live="polite">\([^<]*\)<.*/\1/p')

fail=0
check() {
  if [ "$2" != "$3" ]; then
    echo "ams-14 FAIL: $1 — FACES[0] says '$2', startup says '$3'"
    fail=1
  fi
}

check "family" "$f_family" "$css_family"
check "weight" "$f_weight" "$css_weight"
check "scale"  "$f_scale"  "$css_scale"
check "track"  "$f_track"  "$css_track"
check "label"  "$f_label"  "$html_label"

# The startup call is what makes the three agree at runtime rather than by luck.
if ! grep -q 'apply(0' index.html; then
  echo "ams-14 FAIL: the font-cycle IIFE never calls apply(0) at startup"
  fail=1
fi

[ "$fail" -eq 0 ] || exit 1

echo "ams-14 PASS: FACES[0] ($f_label) matches the CSS defaults and the #fontname label, and apply(0) runs at startup"
exit 0

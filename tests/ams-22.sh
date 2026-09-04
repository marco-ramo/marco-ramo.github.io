#!/bin/sh
# ams-22 — the theme switch must not ship as static markup.
#
# The page's other two controls are built by script on purpose, so a visitor without
# JavaScript gets a plain image and a plain heading rather than dead controls. The theme
# switch broke that rule: it shipped as a <div role="radiogroup"> with three
# <button role="radio"> children whose aria-checked is only ever set by apply(). With
# JavaScript off, all three sat in the tab order, all three reported aria-checked="false"
# -- a radiogroup with no selection, an invalid ARIA state -- and clicking one did nothing.
#
# This test strips every <script> block out of index.html and asserts that what a no-JS
# visitor is actually served carries neither the radiogroup container nor any radio, while
# the script still builds them. Exits non-zero otherwise.

set -eu
cd "$(dirname "$0")/.."

# Everything outside <script>...</script>: the markup a no-JS visitor is served.
markup=$(awk '/<script/{s=1} !s{print} /<\/script>/{s=0}' index.html)

fail=0

if printf '%s' "$markup" | grep -q 'role="radio"'; then
  echo "ams-22 FAIL: index.html ships role=\"radio\" in static markup -- a no-JS visitor gets dead radios"
  fail=1
fi

if printf '%s' "$markup" | grep -q 'role="radiogroup"'; then
  echo "ams-22 FAIL: index.html ships role=\"radiogroup\" in static markup -- announced with no selection"
  fail=1
fi

if printf '%s' "$markup" | grep -q 'class="theme"'; then
  echo "ams-22 FAIL: index.html ships the .theme container in static markup -- its border renders a fourth corner mark with no control in it"
  fail=1
fi

# The switch must be built by script, not simply deleted: a visitor WITH JavaScript still
# gets the three-way control the page has carried since 2026-08-16.
if ! grep -q '"radiogroup"' index.html; then
  echo "ams-22 FAIL: nothing in index.html builds a radiogroup -- the theme switch is gone, not deferred"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "ams-22 PASS: no radiogroup or radio in the static markup; the script builds the switch"
exit 0

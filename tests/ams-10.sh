#!/bin/sh
# ams-10 — declaring viewport-fit=cover obliges the page to apply the safe-area insets itself.
#
# viewport-fit=cover is the opt-out of the browser's default letterboxing inside the
# safe area, so on a notched iPhone the layout runs edge to edge and the corner marks
# end up under the hardware unless the CSS reads env(safe-area-inset-*). This is an
# invariant test, not a rendering test: it asserts only that if the opt-out is declared
# then the insets are honoured somewhere in the stylesheet. Exits non-zero otherwise.

set -eu
cd "$(dirname "$0")/.."

if ! grep -q 'viewport-fit=cover' index.html; then
  echo "ams-10 PASS: index.html does not declare viewport-fit=cover, so no inset is owed"
  exit 0
fi

if grep -q 'env(safe-area-inset-' index.html; then
  echo "ams-10 PASS: viewport-fit=cover is paired with env(safe-area-inset-*) in the CSS"
  exit 0
fi

echo "ams-10 FAIL: index.html declares viewport-fit=cover but never reads env(safe-area-inset-*)"
grep -n 'viewport-fit=cover' index.html | cut -c1-120
exit 1

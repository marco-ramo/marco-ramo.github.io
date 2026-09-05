#!/bin/sh
# ams-32 — the corner crop marks must not be placed at a fraction of the safe-area inset.
#
# --pad-t/-r/-b/-l are max(var(--pad),env(safe-area-inset-<side>,0px)): they exist so that
# anything positioned against the page edge clears the hardware on a notched iPhone. A rule
# that multiplies one of them by a fraction undoes exactly that protection, because 28% of a
# 47px inset is 13px — inside the strip the Dynamic Island and the rounded corner occupy. In
# landscape both left-hand crop marks then render under the hardware.
#
# The correct form adds the raw inset to the scaled base padding, so the fraction is measured
# from inside the safe area: calc(env(safe-area-inset-top,0px) + var(--pad) * .28). On a screen
# reporting no inset that computes to today's value exactly, so nothing moves.
#
# Exits non-zero when any .crop.* rule multiplies a --pad-* variable, or when the four rules
# no longer read env(safe-area-inset-*) at all.

set -eu
cd "$(dirname "$0")/.."

rules=$(grep -n '^  \.crop\.' index.html || true)

if [ -z "$rules" ]; then
  echo "ams-32 FAIL: no .crop.tl/.tr/.bl/.br rules found in index.html"
  exit 1
fi

count=$(printf '%s\n' "$rules" | wc -l | tr -d ' ')
if [ "$count" -ne 4 ]; then
  echo "ams-32 FAIL: expected 4 .crop corner rules, found $count"
  printf '%s\n' "$rules"
  exit 1
fi

# The defect: a --pad-* variable scaled by a fraction inside a corner rule.
scaled=$(printf '%s\n' "$rules" | grep 'var(--pad-[trbl]) *\*' || true)
if [ -n "$scaled" ]; then
  echo "ams-32 FAIL: a .crop corner rule scales a --pad-* variable, which places the mark inside the safe-area inset"
  printf '%s\n' "$scaled"
  exit 1
fi

# And the insets must still be honoured, or the marks are simply back to ignoring the hardware.
missing=$(printf '%s\n' "$rules" | grep -v 'env(safe-area-inset-' || true)
if [ -n "$missing" ]; then
  echo "ams-32 FAIL: a .crop corner rule no longer reads env(safe-area-inset-*)"
  printf '%s\n' "$missing"
  exit 1
fi

echo "ams-32 PASS: all 4 .crop corner rules offset from the raw safe-area inset, none scales a --pad-* variable"
exit 0

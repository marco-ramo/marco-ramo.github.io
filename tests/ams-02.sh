#!/bin/sh
# ams-02 — the <head> must declare a theme-color scoped to a light OS preference.
#
# Without it, a visitor with JavaScript off on a light-mode OS gets the light page
# (#ebece9) with browser chrome stuck at #000000, permanently, because nothing ever
# corrects the meta. Exits non-zero when the light-scoped meta is missing.

set -eu
cd "$(dirname "$0")/.."

head_block=$(sed -n '/<head>/,/<\/head>/p' index.html)

if printf '%s\n' "$head_block" \
  | grep 'name="theme-color"' \
  | grep 'content="#ebece9"' \
  | grep -q 'media="(prefers-color-scheme: light)"'; then
  echo "ams-02 PASS: head declares a light-scoped theme-color of #ebece9"
  exit 0
fi

echo "ams-02 FAIL: no <meta name=\"theme-color\" content=\"#ebece9\" media=\"(prefers-color-scheme: light)\"> in the head of index.html"
printf '%s\n' "$head_block" | grep 'name="theme-color"' || echo "  (no theme-color meta found at all)"
exit 1

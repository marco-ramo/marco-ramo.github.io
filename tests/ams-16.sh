#!/bin/sh
# ams-16 — --list must say so when it cannot identify the live portrait.
#
# active_hash matches the portrait <img> with a regex that assumes class comes before
# src and that the class list starts with "portrait". When the markup moves, the old
# code printed nothing, exited 0, and --list rendered every portrait unmarked beneath a
# legend promising a "*" — so the operator reads it as "nothing is live". The swap path
# fails loudly on the identical breakage, which made the read-only path the unsafe one.
#
# This runs --list against a fixture copy whose <img> attributes are reordered, and
# fails when the output lists portraits instead of naming the failure.

set -eu
cd "$(dirname "$0")/.."
repo=$(pwd)

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cp swap-portrait.sh "$tmp/"
ln -s "$repo/portraits" "$tmp/portraits"

# Reorder the <img> attributes: class after src, and the class list reversed. Both are
# ordinary edits that leave the page identical and defeat the regex.
sed 's|<img class="portrait reveal" src="|<img src="|' index.html > "$tmp/index.html"

out=$(cd "$tmp" && bash ./swap-portrait.sh --list 2>&1) && status=0 || status=$?

if printf '%s\n' "$out" | grep -qi 'could not identify the live portrait'; then
  echo "ams-16 PASS: --list names the failure when the portrait <img> cannot be matched"
  exit 0
fi

echo "ams-16 FAIL: --list did not report that it could not identify the live portrait (exit $status)"
printf '%s\n' "$out"
exit 1

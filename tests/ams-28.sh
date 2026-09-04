#!/bin/sh
# ams-28 — the oversize-portrait prompt must cancel with a message when stdin is not a
# terminal, instead of killing the script silently.
#
# swap-portrait.sh runs under `set -euo pipefail`. When the chosen portrait is over the
# 1000px / 250000-byte thresholds it prints a warning and then `read -r reply`. Run
# non-interactively — from a Makefile, a CI step, or any shell without a controlling
# terminal — that read hits end-of-file and returns 1. It sits in statement position, not
# in a condition, so errexit kills the shell there: the `case` below it never runs and
# `die "cancelled"` never prints. The operator sees the warning and then nothing, with no
# word on whether index.html was rewritten.
#
# This builds an oversize but otherwise valid JPEG in a throwaway copy of the repository,
# runs the script on it with stdin closed, and fails unless "cancelled" is printed and
# index.html is left byte-identical.

set -eu
cd "$(dirname "$0")/.."
repo="$(pwd)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir "$tmp/portraits"
cp "$repo/swap-portrait.sh" "$tmp/swap-portrait.sh"
cp "$repo/index.html" "$tmp/index.html"

# Padding an existing portrait clears MAX_BYTES while leaving the JPEG header intact, so
# the mime-type and dimension guards ahead of the prompt both still pass.
cat "$repo/portraits/blue-duotone.jpg" > "$tmp/portraits/oversize.jpg"
head -c 200000 /dev/zero >> "$tmp/portraits/oversize.jpg"

before="$(shasum -a 256 "$tmp/index.html" | cut -d' ' -f1)"
out=$(bash "$tmp/swap-portrait.sh" oversize </dev/null 2>&1) && status=0 || status=$?
after="$(shasum -a 256 "$tmp/index.html" | cut -d' ' -f1)"

if [ "$status" -eq 1 ] && [ "$before" = "$after" ] \
   && printf '%s\n' "$out" | grep -q 'cancelled'; then
  echo "ams-28 PASS: a non-interactive oversize swap cancels with a message and leaves index.html alone"
  exit 0
fi

echo "ams-28 FAIL: expected exit 1, an unchanged index.html and a 'cancelled' message; got exit $status"
[ "$before" = "$after" ] || echo "ams-28 FAIL: index.html was rewritten"
printf '%s\n' "$out"
exit 1

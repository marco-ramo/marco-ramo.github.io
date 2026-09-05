#!/bin/sh
# ams-33 — every inline script in index.html must parse.
#
# The page's whole behaviour lives in inline <script> blocks: the theme switch, the portrait
# cycle and the name rotation. Nothing else in this suite reads them, so an edit that drops a
# bracket leaves all the other tests green, gets committed, and GitHub Pages deploys a page
# that throws on parse — the theme switch worst of all, since it is built entirely in script
# and so simply never appears. The JSON-LD block has the same exposure with no parser either.
#
# This is a drift guard rather than a red-then-green regression test: it passes today. It
# extracts each <script> block to a temp file and runs `node --check` on every one that is not
# type="application/ld+json", plus a json.load on the one that is.
#
# It FAILS rather than skips when node is missing. A check that asserted nothing is not a pass
# (the same stance run.sh takes on an empty suite), and python3 and sips already make this
# suite macOS-bound, so requiring node costs no portability that exists.

set -eu
cd "$(dirname "$0")/.."

if ! command -v node >/dev/null 2>&1; then
  echo "ams-33 FAIL: node is not on PATH, so the inline scripts cannot be parsed"
  echo "ams-33       install node, or add Bash(node:*) to the envelope's allow list"
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ams-33 FAIL: python3 is not on PATH, so the JSON-LD block cannot be parsed"
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Split index.html into one file per inline script block, and a manifest of what was found.
# A <script> whose opening tag also closes on the same line carries no inline body (an
# external src, or an empty element), so it is skipped rather than parsed as empty.
awk -v dir="$tmp" '
  /^[[:space:]]*<script/ && !/<\/script>/ {
    n++
    type = ($0 ~ /application\/ld\+json/) ? "json" : "js"
    f = sprintf("%s/block-%02d.%s", dir, n, type)
    print n "\t" type "\t" NR "\t" f >> (dir "/manifest")
    inblk = 1
    next
  }
  inblk && /^[[:space:]]*<\/script>/ { inblk = 0; next }
  inblk { print >> f }
' index.html

if [ ! -s "$tmp/manifest" ]; then
  echo "ams-33 FAIL: no inline <script> blocks found in index.html"
  exit 1
fi

blocks=0
bad=0
tab="$(printf '\t')"

while IFS="$tab" read -r n type start f; do
  blocks=$((blocks + 1))
  if [ ! -f "$f" ]; then
    echo "ams-33 FAIL: script block $n opening at index.html:$start extracted to nothing"
    bad=$((bad + 1))
    continue
  fi
  if [ "$type" = "json" ]; then
    if out=$(python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>&1); then
      echo "ams-33   block $n (JSON-LD, index.html:$start) parses"
    else
      echo "ams-33 FAIL: the JSON-LD block at index.html:$start does not parse"
      printf '%s\n' "$out"
      bad=$((bad + 1))
    fi
  else
    if out=$(node --check "$f" 2>&1); then
      echo "ams-33   block $n (JavaScript, index.html:$start) parses"
    else
      echo "ams-33 FAIL: the script block at index.html:$start does not parse"
      printf '%s\n' "$out"
      bad=$((bad + 1))
    fi
  fi
done < "$tmp/manifest"

if [ "$bad" -ne 0 ]; then
  echo "ams-33 FAIL: $bad of $blocks inline blocks in index.html failed to parse"
  exit 1
fi

echo "ams-33 PASS: all $blocks inline blocks in index.html parse"
exit 0

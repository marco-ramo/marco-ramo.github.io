#!/bin/sh
# ams-19 — the suite must not report success when it ran no tests at all.
#
# run.sh loops over ./*.sh, skips itself, and counts passes and failures. If run.sh is
# the only .sh file present — a sparse checkout, a partial clean, or a test file that
# quietly went missing — both counters stay 0, the final [ "$failed" -eq 0 ] succeeds,
# and the harness exits 0 having asserted nothing. A test that silently disappears would
# lower the count and the suite would still go green.
#
# This copies run.sh alone into an empty temp directory, runs it, and fails when the exit
# status is 0.

set -eu
cd "$(dirname "$0")"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

cp run.sh "$tmp/"

out=$(cd "$tmp" && sh ./run.sh 2>&1) && status=0 || status=$?

if [ "$status" -ne 0 ]; then
  echo "ams-19 PASS: run.sh exits non-zero when it finds no tests to run"
  exit 0
fi

echo "ams-19 FAIL: run.sh exited 0 with no tests run"
printf '%s\n' "$out"
exit 1

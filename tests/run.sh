#!/bin/sh
# Run every regression test in this directory. Exits non-zero if any test fails.
#
# No framework, no dependencies: each test is a plain POSIX shell script that
# exits 0 when it passes and non-zero when it fails.
#
#   sh tests/run.sh

cd "$(dirname "$0")"

passed=0
failed=0

for t in ./*.sh; do
  [ "$t" = "./run.sh" ] && continue
  if sh "$t"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
  fi
done

echo "---"
echo "$((passed + failed)) tests, $passed passed, $failed failed"

# A run that found nothing is not a pass. With only run.sh present the glob matches just
# this file, the continue skips it, and both counters stay 0 — so a test file that
# quietly disappeared would lower the count and the suite would still exit 0.
[ "$((passed + failed))" -gt 0 ] || { echo "run.sh: no tests found in $(pwd)"; exit 1; }

[ "$failed" -eq 0 ] || exit 1

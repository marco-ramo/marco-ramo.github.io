#!/bin/sh
# ams-03 — the usage text must not print a line of shell code.
#
# Run with no arguments the script prints its comment header as usage and exits 1.
# The sed range must stop at the last comment line, not run past it into
# `set -euo pipefail`. Exits non-zero when that line appears in the usage output.

set -eu
cd "$(dirname "$0")/.."

# bash, not sh: the script's shebang names bash and it uses `set -o pipefail` and `local`.
# Running it through /bin/sh works only where that is bash, as on macOS; under dash, which
# is /bin/sh on Debian and Ubuntu and therefore on ubuntu-latest in CI, it would abort at
# `set -o pipefail` with status 2 and this test would report a failure that has nothing to
# do with the usage text it exists to check.
out=$(bash ./swap-portrait.sh 2>&1) && status=0 || status=$?

if [ "$status" -ne 1 ]; then
  echo "ams-03 FAIL: expected exit status 1 from an argument-less run, got $status"
  exit 1
fi

if printf '%s\n' "$out" | grep -q '^set -euo'; then
  echo "ams-03 FAIL: usage output contains a bare shell statement:"
  printf '%s\n' "$out" | grep -n '^set -euo'
  exit 1
fi

echo "ams-03 PASS: usage output carries no shell code line"
exit 0

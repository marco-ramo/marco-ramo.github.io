#!/bin/sh
# ams-20 — the usage message must print when the script is invoked by a relative path
# from another directory.
#
# swap-portrait.sh runs `cd "$(dirname "$0")"` near the top, but $0 keeps the literal
# word used to invoke it. Called as `bash ../swap-portrait.sh` from a subdirectory, $0
# stays "../swap-portrait.sh", which after the cd resolves one level above the repository.
# The usage path then seds a file that does not exist; `set -euo pipefail` aborts the
# shell at status 2 and the intended `exit 1` never runs. Someone who has just dropped a
# new JPEG into portraits/ is standing in exactly that directory.
#
# This invokes the script with no arguments from tests/, by a relative path, and fails
# unless the usage text appears and the status is 1.

set -eu
cd "$(dirname "$0")/.."

out=$(cd tests && bash ../swap-portrait.sh 2>&1) && status=0 || status=$?

if [ "$status" -eq 1 ] && printf '%s\n' "$out" | grep -q 'Usage:'; then
  echo "ams-20 PASS: usage prints and exits 1 when invoked by a relative path from elsewhere"
  exit 0
fi

echo "ams-20 FAIL: expected usage text and exit 1, got exit $status"
printf '%s\n' "$out"
exit 1

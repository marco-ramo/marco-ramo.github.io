#!/bin/sh
# ams-11 — the dispatch envelope must allow a push, not just a commit.
#
# A headless leg dispatched into this repository edits, tests, adds and commits,
# all matched by the allow list, then runs `git push` and is refused, because no
# allow rule matches it and a headless leg has no interactive approver. Since
# marcoramo.me deploys on a push to main, an unpushed fix leaves the defect live
# on the public site. Exits non-zero when the allow list carries no push rule.

set -eu
cd "$(dirname "$0")/.."

settings=.claude/settings.json

if [ ! -f "$settings" ]; then
  echo "ams-11 FAIL: $settings does not exist"
  exit 1
fi

allow_block=$(sed -n '/"allow"[[:space:]]*:[[:space:]]*\[/,/\]/p' "$settings")

if [ -z "$allow_block" ]; then
  echo "ams-11 FAIL: no permissions.allow list found in $settings"
  exit 1
fi

if printf '%s\n' "$allow_block" | grep -q 'Bash(git push'; then
  echo "ams-11 PASS: the allow list carries a git push rule"
  printf '%s\n' "$allow_block" | grep 'Bash(git push' | sed 's/^/  /'
  exit 0
fi

echo "ams-11 FAIL: no allow rule matching \`git push\` in $settings — a dispatched leg can commit but not push"
printf '%s\n' "$allow_block" | grep 'Bash(git ' | sed 's/^/  /' || echo "  (no git rules found at all)"
exit 1

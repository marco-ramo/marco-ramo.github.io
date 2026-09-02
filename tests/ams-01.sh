#!/bin/sh
# ams-01 — the per-machine Claude Code settings file must never be publishable.
#
# This repository is public. `.claude/settings.local.json` is written by Claude Code
# on whatever machine it runs on and carries absolute paths and the macOS account
# name, so a broad `git add -A` from the repository root must not be able to stage
# it.
#
# The ignore rule has to live in this repository's own `.gitignore`. A user-level
# global ignore file covers only the machine it sits on, and this repository is
# cloned and worked on elsewhere, so the check below disables the global excludes
# (`core.excludesFile=/dev/null`) and asks whether the in-repo rules alone are
# enough.
#
# `.claude/settings.json` — the committed dispatch envelope — must stay tracked, so
# the rule has to name the local file, not the whole `.claude/` directory.
#
# Fails when the in-repo rules do not ignore the file, when the file has reached the
# index, or when the ignore rule is broad enough to swallow the envelope too.

set -eu
cd "$(dirname "$0")/.."

if ! git -c core.excludesFile=/dev/null check-ignore -q .claude/settings.local.json; then
  echo "ams-01 FAIL: .claude/settings.local.json is not ignored by this repository's own"
  echo "             .gitignore; on any machine without a global ignore rule a broad"
  echo "             'git add' would stage it, and the repository is public"
  exit 1
fi

tracked=$(git ls-files .claude/settings.local.json)
if [ -n "$tracked" ]; then
  echo "ams-01 FAIL: .claude/settings.local.json is tracked in the index:"
  printf '%s\n' "$tracked"
  exit 1
fi

if git -c core.excludesFile=/dev/null check-ignore -q .claude/settings.json; then
  echo "ams-01 FAIL: the ignore rule also covers .claude/settings.json; the dispatch"
  echo "             envelope has to stay committed"
  exit 1
fi

if ! git ls-files --error-unmatch .claude/settings.json >/dev/null 2>&1; then
  echo "ams-01 FAIL: .claude/settings.json (the dispatch envelope) is no longer tracked"
  exit 1
fi

echo "ams-01 PASS: local settings file ignored by the repository's own .gitignore and untracked; envelope still tracked"
exit 0

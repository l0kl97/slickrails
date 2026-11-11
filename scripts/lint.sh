#!/bin/sh
# Lint for the kit's own scripts (shellcheck) — one list for CI and for the local pre-push check.
# Excluded on purpose: SC1090/SC1091 (hooks source the repo's config.sh by design), SC2015 (the test suite's ok/fail
# idiom), SC2164 (cd runs under set -e or is followed by || exit), SC2094 (the agent-file append in install.sh only
# tests existence before writing, no read).
# Without shellcheck it says so and passes locally; CI installs it, so CI always checks.

cd "$(dirname "$0")/.." || exit 1
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "lint: shellcheck not installed — skipped (brew install shellcheck); CI checks it" >&2
  exit 0
fi
exec shellcheck -s sh -e SC1090,SC1091,SC2015,SC2164,SC2094 \
  install.sh bootstrap.sh bin/slickrails tests/run.sh \
  scripts/setup-branch-protection.sh scripts/status.sh scripts/lint.sh \
  templates/hooks/pre-commit templates/hooks/pre-push templates/hooks/commit-msg templates/hooks/post-merge \
  templates/session-check.sh templates/bash-guard.sh templates/dep-check.sh \
  templates/gate.sh templates/gate/pre-receive templates/ai-review.sh templates/draft-dossier.sh

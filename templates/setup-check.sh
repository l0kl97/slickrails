#!/bin/sh
# slickrails setup check — runs in CI (a step of the `ci` job) and fails when the repo's guardrail setup is missing
# or empty: the git hooks, a config.sh that checks something, the agents' session hooks. A broken setup is otherwise
# silent: every hook "passes" because nothing is there to run.
#
# What it cannot see: whether a developer's clone has the hooks switched on (core.hooksPath is local git config and
# is never cloned) — `slickrails doctor` checks that on the machine.
# Way out (loud, deliberate): the repository variable SLICKRAILS_SETUP_CHECK=warn reports without failing, =off skips.

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 1

MODE="$(printf '%s' "${SLICKRAILS_SETUP_CHECK:-block}" | tr '[:upper:]' '[:lower:]')"
case "$MODE" in
  off) echo "slickrails setup check: skipped (SLICKRAILS_SETUP_CHECK=off)"; exit 0;;
  warn|block) ;;
  *) echo "slickrails setup check: SLICKRAILS_SETUP_CHECK='$MODE' is not understood (block | warn | off) — checking with block" >&2; MODE=block;;
esac

PROBLEMS=0
problem() { echo "  PROBLEM  $*"; PROBLEMS=$((PROBLEMS + 1)); }
okay()    { echo "  ok       $*"; }

echo "slickrails setup check:"
for H in pre-commit pre-push commit-msg; do
  if [ -s ".githooks/$H" ]; then okay ".githooks/$H"; else problem ".githooks/$H is missing or empty — run 'slickrails init'"; fi
done

# config.sh is read as text, never run: a check counts when its value is not empty
CFG=".slickrails/config.sh"
if [ ! -f "$CFG" ]; then
  problem "$CFG is missing — run 'slickrails init'"
elif grep -Eq '^[[:space:]]*(CHECK_TYPECHECK|CHECK_TEST|CHECK_SESSION)=("[^"]+"|'"'"'[^'"'"']+'"'"'|[^"'"'"'[:space:]#][^[:space:]#]*)' "$CFG"; then
  okay "$CFG defines checks"
else
  problem "$CFG checks nothing (CHECK_TYPECHECK, CHECK_TEST and CHECK_SESSION are empty) — every hook would pass"
fi

# the agents' session hooks: at least one agent must have the Stop gate and the Bash guard
AGENTS=""
for F in .claude/settings.json .codex/hooks.json; do
  [ -f "$F" ] && grep -q 'session-check\.sh' "$F" && grep -q 'bash-guard\.sh' "$F" && AGENTS="$AGENTS $F"
done
if [ -n "$AGENTS" ]; then okay "agent session hooks in$AGENTS"
else problem "no agent session hooks (.claude/settings.json or .codex/hooks.json with session-check.sh and bash-guard.sh)"; fi
for S in session-check.sh bash-guard.sh; do
  [ -s ".slickrails/$S" ] || problem ".slickrails/$S is missing or empty"
done

if [ "$PROBLEMS" -eq 0 ]; then echo "slickrails setup check: ok"; exit 0; fi
if [ "$MODE" = "warn" ]; then
  echo "slickrails setup check: $PROBLEMS problem(s), reported only (SLICKRAILS_SETUP_CHECK=warn)"; exit 0
fi
echo "slickrails setup check: $PROBLEMS problem(s) — the guardrails of this repo are not in place."
echo "Fix them with 'slickrails init' (it never overwrites), or set the repository variable SLICKRAILS_SETUP_CHECK=warn."
exit 1

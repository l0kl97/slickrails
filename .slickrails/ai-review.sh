#!/bin/sh
# slickrails: local pre-push AI review — the no-mistakes idea without the daemon.
# Opt-in: set CHECK_PREPUSH_REVIEW="1" in .slickrails/config.sh (the installer does when it finds claude or codex).
# Reviews the outgoing diff with the local claude or codex CLI (your login, no API key); a FAIL verdict blocks the push.
# REVIEW_CLI (config.sh or environment): auto (default: claude, else codex) | claude | codex. Codex is looked up on PATH
# and, on macOS, inside the ChatGPT app (SLICKRAILS_CODEX_APP); it runs read-only and without a stored session.
# Degrades gracefully, but never silently and never as a PASS: no reviewer CLI, no base to diff against
# or an empty diff skip with a message; a failed reviewer or an invalid answer is reported as ERROR.
# REVIEW_ON_ERROR (config.sh): "warn" (default) lets the push proceed unreviewed, "block" stops it.
# REVIEW_TIMEOUT (config.sh, seconds, default 120): a hanging reviewer is killed and reported as ERROR.
# Exit codes: 0 = PASS (or nothing to review) · 1 = FAIL verdict, or ERROR with block · 3 = ERROR with warn
# (not reviewed — the caller may let the push proceed but must not report a full pass).

set -u

say() { printf '%s\n' "slickrails[ai-review]: $*" >&2; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0

# Base: the branch's upstream, else main/master, else nothing to compare.
BASE="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$BASE" ]; then
  for CAND in origin/main origin/master main master; do
    if git rev-parse --verify -q "$CAND" >/dev/null 2>&1; then BASE="$CAND"; break; fi
  done
fi
# A caller that knows the base better (the slickrails gate) passes it in.
if [ -n "${SLICKRAILS_REVIEW_BASE:-}" ] && git rev-parse --verify -q "${SLICKRAILS_REVIEW_BASE}^{commit}" >/dev/null 2>&1; then
  BASE="$SLICKRAILS_REVIEW_BASE"
fi
if [ -z "$BASE" ]; then
  say "no base branch found to diff against — skipping."
  exit 0
fi

DIFF_ERR=""
# a diff git cannot build (no merge base: unrelated history, a shallow clone) is not an empty diff
DIFF="$(git diff "$BASE"...HEAD 2>/dev/null)" || { DIFF=""; DIFF_ERR="git cannot diff against $BASE (no merge base? a shallow clone?)"; }
if [ -z "$DIFF" ] && [ -z "$DIFF_ERR" ]; then
  say "nothing to review against $BASE."
  exit 0
fi

RULES=""
[ -f .slickrails/rules.md ] && RULES="$(cat .slickrails/rules.md)"
LEARNINGS=""
[ -f .slickrails/review-learnings.md ] && LEARNINGS="$(cat .slickrails/review-learnings.md)"
ENV_ON_ERROR="${REVIEW_ON_ERROR:-}"   # an exported value wins over config.sh (one-off override)
ENV_CLI="${REVIEW_CLI:-}"
[ -f .slickrails/config.sh ] && . .slickrails/config.sh
PROFILE="${REVIEW_PROFILE:-chill}"
ON_ERROR="${ENV_ON_ERROR:-${REVIEW_ON_ERROR:-warn}}"
TIMEOUT="${REVIEW_TIMEOUT:-120}"   # seconds; a hanging reviewer must not hang the push
case "$TIMEOUT" in ""|*[!0-9]*) TIMEOUT=120;; esac

# the reviewer: the local claude or codex CLI
CODEX="$(command -v codex 2>/dev/null || true)"
CODEX_APP="${SLICKRAILS_CODEX_APP:-/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex}"
[ -z "$CODEX" ] && [ -x "$CODEX_APP" ] && CODEX="$CODEX_APP"
CLI=""
case "${ENV_CLI:-${REVIEW_CLI:-auto}}" in
  claude) command -v claude >/dev/null 2>&1 && CLI=claude
          [ -n "$CLI" ] || { say "claude CLI not found — skipping AI review (install: https://claude.com/claude-code)."; exit 0; };;
  codex)  [ -n "$CODEX" ] && CLI=codex
          [ -n "$CLI" ] || { say "codex CLI not found — skipping AI review (install: https://developers.openai.com/codex/cli)."; exit 0; };;
  *)      if command -v claude >/dev/null 2>&1; then CLI=claude; elif [ -n "$CODEX" ]; then CLI=codex; fi
          [ -n "$CLI" ] || { say "no claude or codex CLI found — skipping AI review."; exit 0; };;
esac

# not_reviewed <reason>: never a pass; REVIEW_ON_ERROR decides whether the push may proceed
not_reviewed() {
  say "ERROR — $1. This is NOT a pass: the diff was not reviewed."
  case "$(printf '%s' "$ON_ERROR" | tr '[:upper:]' '[:lower:]')" in
    warn) ;;
    block) ON_ERROR="block";;
    *) say "Unknown REVIEW_ON_ERROR value '$ON_ERROR' (expected warn or block) — treating it as block."; ON_ERROR="block";;
  esac
  if [ "$ON_ERROR" = "block" ]; then
    say "Blocked (REVIEW_ON_ERROR=block)."
    exit 1
  fi
  say "Push proceeds unreviewed. Set REVIEW_ON_ERROR=\"block\" in .slickrails/config.sh to stop pushes the review could not check."
  exit 3   # 3 = not reviewed, the caller may proceed but must not report a full pass
}
[ -n "$DIFF_ERR" ] && not_reviewed "$DIFF_ERR"

PROMPT="You are a strict pre-push reviewer of AI-generated code. Review ONLY the diff below for: correctness (logic, edge cases), security (input validation, injection, secrets, insecure defaults), reliability (error handling, timeouts, races), tests that only cover the happy path, operational gaps (missing timeout/logging on external calls), and performance (excessive/repeated I/O, N+1 queries — AI code shows ~8x more excessive I/O). Review profile '$PROFILE': quiet = only high-risk findings block; chill = real findings block; assertive = same as chill, plus non-blocking improvement notes after the verdict block. Only real, blocking findings justify FAIL; style nitpicks never do."
TEXT_FORMAT="Your FIRST line must be exactly 'VERDICT: PASS' or 'VERDICT: FAIL'. If FAIL, list each finding as 'file:line — [high|medium|low] — issue — concrete failure scenario'."
JSON_FORMAT="Answer through the required JSON schema: verdict PASS or FAIL, and findings: one string per finding, formatted 'file:line — [high|medium|low] — issue — concrete failure scenario' (none if PASS)."
SCHEMA='{"type":"object","properties":{"verdict":{"enum":["PASS","FAIL"]},"findings":{"type":"array","items":{"type":"string"}}},"required":["verdict","findings"]}'

INPUT="$(printf 'Project-specific review rules (take precedence):\n%s\n\nTeam review learnings (waived finding types are never reported; tightened ones always are):\n%s\n\n--- DIFF ---\n%s\n' "$RULES" "$LEARNINGS" "$DIFF")"

if [ "$CLI" = "codex" ]; then RUNNER="codex exec"; else RUNNER="claude -p"; fi
say "reviewing outgoing diff against $BASE ($RUNNER, profile: $PROFILE, no daemon) ..."

# With jq the verdict arrives as a schema-checked field; without it (or from a CLI that does not return one)
# the first line of the answer must be exactly "VERDICT: PASS" or "VERDICT: FAIL". Anything else is an ERROR.
TMPD="$(mktemp -d "${TMPDIR:-/tmp}/slickrails-review.XXXXXX")" || { say "ERROR — cannot create a temp dir."; exit 3; }
trap 'rm -rf "$TMPD"' EXIT
printf '%s\n' "$INPUT" > "$TMPD/in"

if [ "$CLI" = "codex" ]; then
  # codex reads the whole prompt from stdin ("-") and writes its last message to a file; read-only, nothing stored
  if command -v jq >/dev/null 2>&1; then
    # OpenAI's structured output wants every object closed
    printf '%s\n' "$SCHEMA" | sed 's/"required"/"additionalProperties":false,"required"/' > "$TMPD/schema.json"
    { printf '%s %s\n\n' "$PROMPT" "$JSON_FORMAT"; cat "$TMPD/in"; } > "$TMPD/prompt"
    set -- "$CODEX" exec --sandbox read-only --ephemeral --skip-git-repo-check --output-schema "$TMPD/schema.json" -o "$TMPD/last" -
  else
    { printf '%s %s\n\n' "$PROMPT" "$TEXT_FORMAT"; cat "$TMPD/in"; } > "$TMPD/prompt"
    set -- "$CODEX" exec --sandbox read-only --ephemeral --skip-git-repo-check -o "$TMPD/last" -
  fi
  mv "$TMPD/prompt" "$TMPD/in"
# The reviewer reads, it never runs or writes: claude gets Read/Grep/Glob only, no MCP servers (the user's mail, CRM or
# cloud tools; the diff may carry a prompt injection) and only the user's settings (no project hooks: the Stop gate
# would run the suite inside the review); codex the read-only sandbox. (A review with all tools once "reproduced" a
# finding by creating and staging a file in the real repo.) The subscription login is untouched.
elif command -v jq >/dev/null 2>&1; then
  set -- claude -p "$PROMPT $JSON_FORMAT" --output-format json --json-schema "$SCHEMA" --max-turns 8 --tools Read,Grep,Glob --strict-mcp-config --setting-sources user
else
  set -- claude -p "$PROMPT $TEXT_FORMAT" --tools Read,Grep,Glob --strict-mcp-config --setting-sources user
fi
# Deadline without `timeout` (macOS has none): the reviewer runs in the background and this loop polls it,
# so no helper process outlives the review. TERM first, KILL if it ignores that.
( exec "$@" < "$TMPD/in" > "$TMPD/out" 2> "$TMPD/err" ) &
CP=$!
T0="$(date +%s)"
TIMED_OUT=0
while kill -0 "$CP" 2>/dev/null; do
  if [ $(( $(date +%s) - T0 )) -ge "$TIMEOUT" ]; then
    TIMED_OUT=1
    kill "$CP" 2>/dev/null
    sleep 0.3 2>/dev/null || sleep 1
    kill -9 "$CP" 2>/dev/null
    break
  fi
  sleep 0.2 2>/dev/null || sleep 1
done
wait "$CP" 2>/dev/null
RC=$?
RAW="$(cat "$TMPD/out" 2>/dev/null)"
JQ_VERDICT='.structured_output.verdict // empty'; JQ_FINDINGS='.structured_output.findings[]?'
if [ "$CLI" = "codex" ]; then
  RAW="$(cat "$TMPD/last" 2>/dev/null)"; JQ_VERDICT='.verdict // empty'; JQ_FINDINGS='.findings[]?'
fi

VERDICT=""; FINDINGS=""; REASON=""
if [ "$TIMED_OUT" -eq 1 ]; then
  REASON="the reviewer timed out after ${TIMEOUT}s (REVIEW_TIMEOUT)"
elif [ "$RC" -ne 0 ]; then
  ERRTAIL="$(sed -n '1,3p' "$TMPD/err" 2>/dev/null | tr '\n' ' ')"
  # claude -p --output-format json says why it stopped on stdout (e.g. error_max_turns), not on stderr
  STOPPED="$(sed -n 's/.*"subtype":[[:space:]]*"\([a-z_]*\)".*/\1/p' "$TMPD/out" 2>/dev/null | head -n 1)"
  REASON="the reviewer process failed (exit $RC)${STOPPED:+: $STOPPED}${ERRTAIL:+: $ERRTAIL}"
else
  if command -v jq >/dev/null 2>&1; then
    # tr: jq on Windows ends its lines with \r\n
    VERDICT="$(printf '%s' "$RAW" | jq -r "$JQ_VERDICT" 2>/dev/null | tr -d '\r' || true)"
    FINDINGS="$(printf '%s' "$RAW" | jq -r "$JQ_FINDINGS" 2>/dev/null | tr -d '\r' || true)"
  fi
  if [ -z "$VERDICT" ]; then
    FIRST="$(printf '%s\n' "$RAW" | sed -n '1s/[[:space:]]*$//p')"
    case "$FIRST" in
      "VERDICT: PASS") VERDICT="PASS";;
      "VERDICT: FAIL") VERDICT="FAIL"; FINDINGS="$(printf '%s\n' "$RAW" | sed '1d')";;
    esac
  fi
  case "$VERDICT" in
    PASS|FAIL) ;;
    *) REASON="the answer is not a valid verdict (expected exactly PASS or FAIL)"; VERDICT="";;
  esac
fi

case "$VERDICT" in
  PASS)
    say "PASS — push proceeds."
    exit 0;;
  FAIL)
    say "FAIL — findings:"
    printf '%s\n' "${FINDINGS:-(the reviewer gave no details)}" >&2
    say "Fix the findings (or push deliberately with SLICKRAILS_SKIP=1 and say why in the commit)."
    exit 1;;
  *)
    not_reviewed "$REASON";;
esac

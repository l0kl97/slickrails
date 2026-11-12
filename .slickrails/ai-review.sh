#!/bin/sh
# slickrails: local pre-push AI review — the no-mistakes idea without the daemon.
# Opt-in: set CHECK_PREPUSH_REVIEW="1" in .slickrails/config.sh (the installer does when it finds claude or codex).
# Reviews the outgoing diff with the local claude or codex CLI (your login, no API key); a FAIL verdict blocks the push.
# REVIEW_CLI (config.sh or environment): auto (default: claude, else codex) | claude | codex. Codex is looked up on PATH
# and, on macOS, inside the ChatGPT app (SLICKRAILS_CODEX_APP); it runs read-only and without a stored session.
# Degrades gracefully, but never silently and never as a PASS: no reviewer CLI, no base to diff against
# or an empty diff skip with a message; a failed reviewer or an invalid answer is reported as ERROR.
# REVIEW_ON_ERROR (config.sh): "warn" (default) lets the push proceed unreviewed, "block" stops it.
# REVIEW_MAX_KB (config.sh, default 300): a larger diff is cut at a file boundary; a PASS for the rest is an ERROR.
# REVIEW_TIMEOUT (config.sh, seconds, default 120): a hanging reviewer is killed and reported as ERROR.
# Exit codes: 0 = PASS (or nothing to review) · 1 = FAIL verdict, or ERROR with block · 3 = ERROR with warn
# (not reviewed — the caller may let the push proceed but must not report a full pass).

set -u

say() { printf '%s\n' "slickrails[ai-review]: $*" >&2; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0

# Base: the branch's upstream, else the default branch (the remote's HEAD, main, master), else nothing to compare.
UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
BASE="$UPSTREAM"
# After a rebase or an amend the upstream is no ancestor of HEAD: a diff against it would also hold everything
# the base branch gained in between, which was reviewed when it went in. Then the default branch is the base.
if [ -n "$BASE" ] && ! git merge-base --is-ancestor "$BASE" HEAD 2>/dev/null; then BASE=""; fi
if [ -z "$BASE" ]; then
  for CAND in "$(git rev-parse --abbrev-ref origin/HEAD 2>/dev/null || true)" origin/main origin/master main master; do
    if [ -n "$CAND" ] && git rev-parse --verify -q "$CAND^{commit}" >/dev/null 2>&1; then BASE="$CAND"; break; fi
  done
  [ -z "$BASE" ] && BASE="$UPSTREAM"   # no default branch to be found: the outdated upstream is better than no review
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
# Lockfiles, minified files and source maps are left out: nobody wrote them by hand, and they drown what someone did.
DIFF="$(git diff "$BASE"...HEAD -- . \
  ':(exclude,glob)**/package-lock.json' ':(exclude,glob)**/pnpm-lock.yaml' ':(exclude,glob)**/yarn.lock' \
  ':(exclude,glob)**/bun.lock' ':(exclude,glob)**/bun.lockb' ':(exclude,glob)**/Cargo.lock' ':(exclude,glob)**/go.sum' \
  ':(exclude,glob)**/Gemfile.lock' ':(exclude,glob)**/poetry.lock' ':(exclude,glob)**/uv.lock' ':(exclude,glob)**/composer.lock' \
  ':(exclude,glob)**/*.min.js' ':(exclude,glob)**/*.min.css' ':(exclude,glob)**/*.map' 2>/dev/null)" \
  || { DIFF=""; DIFF_ERR="git cannot diff against $BASE (no merge base? a shallow clone?)"; }
if [ -z "$DIFF" ] && [ -z "$DIFF_ERR" ]; then
  say "nothing to review against $BASE (lockfiles, minified files and source maps are not reviewed)."
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
  say "ERROR — $1. This is NOT a pass."
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

PROMPT="You are a strict pre-push reviewer of AI-generated code. Review ONLY the diff below for: correctness (logic, edge cases), security (input validation, injection, secrets, insecure defaults), reliability (error handling, timeouts, races), tests that only cover the happy path, operational gaps (missing timeout/logging on external calls), and performance (excessive/repeated I/O, N+1 queries — AI code shows ~8x more excessive I/O). Review profile '$PROFILE': quiet = only high-risk findings block; chill = real findings block; assertive = same as chill, plus non-blocking improvement notes after the verdict block. Only real, blocking findings justify FAIL; style nitpicks never do. Report only what this diff introduces (its added and changed lines). Do not speculate that a change might break other code unless you can name the affected code path. Do not flag a design choice or a matter of style unless it causes a clear defect. State severity accurately, do not overstate impact. At most 6 findings, the most serious first; none is a valid answer."
TEXT_FORMAT="Your FIRST line must be exactly 'VERDICT: PASS' or 'VERDICT: FAIL'. If FAIL, list each finding as 'file:line — [high|medium|low] — issue — concrete failure scenario'."
JSON_FORMAT="Answer through the required JSON schema: verdict PASS or FAIL, and findings: one string per finding, formatted 'file:line — [high|medium|low] — issue — concrete failure scenario' (none if PASS)."
SCHEMA='{"type":"object","properties":{"verdict":{"enum":["PASS","FAIL"]},"findings":{"type":"array","items":{"type":"string"}}},"required":["verdict","findings"]}'

# A diff over REVIEW_MAX_KB (config.sh, default 300) is cut at a file boundary. The reviewer gets the names of the
# files that were left out (it can read them), and a PASS for the rest is reported as what it is: not a full review.
MAX_KB="${REVIEW_MAX_KB:-300}"; case "$MAX_KB" in ""|*[!0-9]*) MAX_KB=300;; esac
OMITTED="$(printf '%s\n' "$DIFF" | awk -v max=$((MAX_KB * 1024)) '
  /^diff --git / { if (n > max) cut = 1; if (cut) { sub(/^diff --git a\//, ""); sub(/ b\/.*/, ""); print } }
  !cut { n += length($0) + 1 }')"
[ -n "$OMITTED" ] && DIFF="$(printf '%s\n' "$DIFF" | awk -v max=$((MAX_KB * 1024)) '/^diff --git / && n > max { exit } { print; n += length($0) + 1 }')"
# Where a mistake costs most, named from the changed paths: the reviewer starts there.
SENSITIVE="$(git diff --name-only "$BASE"...HEAD 2>/dev/null | awk '
  /(^|\/)\.github\/workflows\// { a["CI workflows"] }
  /(^|\/)(migrations?|db\/migrate)\// || /\.sql$/ { a["database migrations"] }
  tolower($0) ~ /auth|permission|session|password|crypt/ { a["authentication and permissions"] }
  tolower($0) ~ /payment|billing|invoice|checkout/ { a["payments"] }
  /(^|\/)(Dockerfile|docker-compose[^\/]*|[^\/]*\.tf)$/ || /(^|\/)(infra|deploy|terraform|k8s|helm)\// { a["infrastructure"] }
  /(^|\/)(\.slickrails|\.githooks)\// { a["the guardrails themselves"] }
  END { for (k in a) printf "%s%s", (c++ ? ", " : ""), k }' || true)"

# What the last review of this branch found, if it failed: a second look starts there, like a human reviewer's would.
MEMO="$(git rev-parse --git-dir)/slickrails-last-review"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
PREVIOUS=""
[ -f "$MEMO" ] && [ "$(sed -n 1p "$MEMO")" = "$BRANCH" ] && PREVIOUS="$(sed 1d "$MEMO")"
INPUT="$(printf 'Project-specific review rules (take precedence):\n%s\n\nTeam review learnings (waived finding types are never reported; tightened ones always are):\n%s\n\nFindings of the previous review of this branch, if any (the author pushed again: check first whether each one is fixed, and report one that is still open in the same words):\n%s\n\nSensitive areas this diff touches, if any (look at them first and hardest):\n%s\n\nFiles changed but left out of the diff below because it is over the size limit, if any (read them yourself where a finding depends on them):\n%s\n\n--- DIFF ---\n%s\n' "$RULES" "$LEARNINGS" "$PREVIOUS" "$SENSITIVE" "$OMITTED" "$DIFF")"

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
    rm -f "$MEMO"
    [ -n "$OMITTED" ] && not_reviewed "the diff is over REVIEW_MAX_KB (${MAX_KB} KB): the part that was reviewed passed, these files were not reviewed: $(printf '%s' "$OMITTED" | tr '\n' ' ')"
    say "PASS — push proceeds."
    exit 0;;
  FAIL)
    say "FAIL — findings:"
    printf '%s\n' "${FINDINGS:-(the reviewer gave no details)}" >&2
    printf '%s\n%s\n' "$BRANCH" "$FINDINGS" > "$MEMO"
    say "Fix the findings (or push deliberately with SLICKRAILS_SKIP=1 and say why in the commit)."
    exit 1;;
  *)
    not_reviewed "$REASON";;
esac

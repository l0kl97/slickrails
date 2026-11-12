#!/bin/sh
# slickrails: set up branch protection for main (rule 5) and read it back from GitHub.
# Prerequisite: gh CLI logged in (gh auth login), repo has a GitHub remote, jq (or node) for the read-back.
# Run inside the target repo: sh scripts/setup-branch-protection.sh [branch]
#
#   ENFORCE_ADMINS=0     keep a direct-push way out for admins
#   REQUIRE_PR=0         allow direct pushes of commits whose checks passed (default: every change goes through a PR)
#   CODEOWNER_REVIEWS=1  every PR needs one approving review, from a code owner where it touches their paths;
#                        a new push dismisses the approval (needs a second person: nobody approves their own PR)
#   REQUIRED_CHECKS="ci (ubuntu-latest, 20); gitleaks"   the required checks by name (separated by ; or newlines —
#                        a matrix name can contain a comma), instead of finding them
#
# Pull requests are required, approvals are not (0 approving reviews): a solo developer can merge their own PR, and
# nothing reaches main without the PR's checks. CODEOWNER_REVIEWS=1 adds the human review; GitHub then applies the
# approval count to every PR, not only to the CODEOWNERS paths.
# Required checks: the kit's workflow job names (ci, smoke, gitleaks, audit, size). A job with a matrix reports one
# check per entry ("ci (ubuntu-latest)") and never a plain "ci", which would block every merge; the names are taken
# from the last check runs on the branch when they exist there.

set -eu

BRANCH="${1:-main}"
case "$(printf '%s' "${ENFORCE_ADMINS:-1}" | tr '[:upper:]' '[:lower:]')" in
  0|false|no|off|n) ENFORCE_JSON=false; ENFORCE_WORD=no;;
  1|true|yes|on|y)  ENFORCE_JSON=true;  ENFORCE_WORD=yes;;
  *) echo "ENFORCE_ADMINS='${ENFORCE_ADMINS}' is not understood (use 1/0, yes/no, on/off) — nothing was sent." >&2; exit 1;;
esac
yesno() { # yesno <NAME> <value>: prints true/false, or stops before anything is sent
  case "$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')" in
    0|false|no|off|n) echo false;;
    1|true|yes|on|y)  echo true;;
    *) echo "$1='$2' is not understood (use 1/0, yes/no, on/off) — nothing was sent." >&2; return 1;;
  esac
}
REQUIRE_PR_JSON="$(yesno REQUIRE_PR "${REQUIRE_PR:-1}")" || exit 1
CODEOWNERS_JSON="$(yesno CODEOWNER_REVIEWS "${CODEOWNER_REVIEWS:-0}")" || exit 1
if [ "$CODEOWNERS_JSON" = "true" ] && [ "$REQUIRE_PR_JSON" != "true" ]; then
  echo "CODEOWNER_REVIEWS=1 needs pull requests (REQUIRE_PR=1) — nothing was sent." >&2; exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI missing — install with: brew install gh && gh auth login" >&2
  exit 1
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "Branch protection for $REPO@$BRANCH ..."

# Required checks: REQUIRED_CHECKS by name, or the kit's jobs — CI always, smoke/security/size if their workflows exist.
if [ -n "${REQUIRED_CHECKS:-}" ]; then
  WANT_LIST="$(printf '%s' "$REQUIRED_CHECKS" | tr ';' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' || true)"
  CHECK_NOTE="from REQUIRED_CHECKS"
else
  JOBS="ci"
  [ -f .github/workflows/smoke.yml ] && JOBS="$JOBS smoke"
  [ -f .github/workflows/security.yml ] && JOBS="$JOBS gitleaks audit"
  [ -f .github/workflows/pr-size.yml ] && JOBS="$JOBS size"
  # the names GitHub reported for the branch's last commit, asked with a deadline (30 s): a failed call is said as
  # such, not taken for "nothing ran yet"
  RUNS_TMP="$(mktemp "${TMPDIR:-/tmp}/slickrails-runs.XXXXXX")"; trap 'rm -f "$RUNS_TMP" "$RUNS_TMP.err"' EXIT
  ( gh api "repos/$REPO/commits/$BRANCH/check-runs?per_page=100" --jq '.check_runs[].name' > "$RUNS_TMP" 2> "$RUNS_TMP.err" ) & RUNS_PID=$!
  RUNS_WAIT=0; RUNS_STATE=ok
  while kill -0 "$RUNS_PID" 2>/dev/null; do
    if [ "$RUNS_WAIT" -ge 150 ]; then kill "$RUNS_PID" 2>/dev/null; RUNS_STATE=timeout; break; fi
    sleep 0.2; RUNS_WAIT=$((RUNS_WAIT + 1))
  done
  if [ "$RUNS_STATE" = ok ] && ! wait "$RUNS_PID"; then RUNS_STATE=failed; fi
  RUNS=""; [ "$RUNS_STATE" = ok ] && RUNS="$(tr -d '\r' < "$RUNS_TMP" | sort -u)"
  WANT_LIST=""; CHECK_NOTE="the kit's job names"; NOT_SEEN=""
  for J in $JOBS; do
    if [ -n "$RUNS" ] && ! printf '%s\n' "$RUNS" | grep -qxF "$J"; then
      MATRIX="$(printf '%s\n' "$RUNS" | grep -F "$J (" | grep "^$J (" || true)"
      if [ -n "$MATRIX" ]; then WANT_LIST="$WANT_LIST
$MATRIX"; CHECK_NOTE="the kit's job names, matrix entries as GitHub reports them"; continue; fi
      # ran, but neither as "$J" nor as "$J (...)": maybe skipped on that commit (size only runs on pull requests,
      # so a branch's own commits never carry it)
      [ "$J" = size ] || NOT_SEEN="$NOT_SEEN $J"
    fi
    WANT_LIST="$WANT_LIST
$J"
  done
  WANT_LIST="$(printf '%s\n' "$WANT_LIST" | grep -v '^$' || true)"
fi
if [ -z "$WANT_LIST" ]; then echo "REQUIRED_CHECKS names no check — nothing was sent." >&2; exit 1; fi
case "$WANT_LIST" in *'"'*|*\\*) echo "A check name with a quote or backslash is not supported — nothing was sent." >&2; exit 1;; esac
# one JSON string per line, joined line by line: a name may contain a comma ("ci (ubuntu-latest, 20)")
CHECKS="$(printf '%s\n' "$WANT_LIST" | sed 's/.*/"&",/; $ s/,$//')"
WANT_CONTEXTS="$WANT_LIST"
if [ "$REQUIRE_PR_JSON" = "true" ]; then
  if [ "$CODEOWNERS_JSON" = "true" ]; then APPROVALS=1; else APPROVALS=0; fi
  # with a required human review, a new push dismisses the approval and the last push needs one: an approved PR cannot
  # be changed and merged without a second look
  PR_REVIEWS="{ \"required_approving_review_count\": $APPROVALS, \"require_code_owner_reviews\": $CODEOWNERS_JSON, \"dismiss_stale_reviews\": $CODEOWNERS_JSON, \"require_last_push_approval\": $CODEOWNERS_JSON }"
else
  PR_REVIEWS=null
fi

gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
  -H "Accept: application/vnd.github+json" \
  --input - <<EOF >/dev/null
{
  "required_status_checks": {
    "strict": true,
    "contexts": [ $CHECKS ]
  },
  "enforce_admins": $ENFORCE_JSON,
  "required_pull_request_reviews": $PR_REVIEWS,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "required_linear_history": true,
  "required_conversation_resolution": true
}
EOF

# --- read back what GitHub actually stored and compare it with the request -------------------------------
if ! GOT="$(gh api "repos/$REPO/branches/$BRANCH/protection" 2>/dev/null)"; then
  echo "NOT verified: the protection was sent, but reading it back from GitHub failed. Check the settings in the repo." >&2
  exit 1
fi

field() { # field <jq expression> <javascript expression on o>
  if command -v jq >/dev/null 2>&1; then
    # jq's own exit status decides; then drop the \r that jq on Windows puts at every line end
    F_OUT="$(printf '%s' "$GOT" | jq -r "$1" 2>/dev/null)" || return 1
    printf '%s\n' "$F_OUT" | tr -d '\r'
  elif command -v node >/dev/null 2>&1; then
    printf '%s' "$GOT" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const o=JSON.parse(d);const v=($2);console.log(Array.isArray(v)?v.join('\\n'):v)})" 2>/dev/null
  else
    return 1
  fi
}
sorted() { printf '%s\n' "$1" | grep -v '^$' | LC_ALL=C sort; }   # a newline-separated list, compared as a set

if ! GOT_CONTEXTS="$(field '(.required_status_checks.contexts // []) | join("\n")' '(o.required_status_checks||{}).contexts||[]')" \
   || ! GOT_STRICT="$(field '.required_status_checks.strict' '(o.required_status_checks||{}).strict')" \
   || ! GOT_ADMINS="$(field '.enforce_admins.enabled' '(o.enforce_admins||{}).enabled')" \
   || ! GOT_PR="$(field '(.required_pull_request_reviews != null)' 'o.required_pull_request_reviews!=null')" \
   || ! GOT_CO="$(field '(.required_pull_request_reviews.require_code_owner_reviews // false)' '!!(o.required_pull_request_reviews||{}).require_code_owner_reviews')" \
   || ! GOT_STALE="$(field '(.required_pull_request_reviews.dismiss_stale_reviews // false)' '!!(o.required_pull_request_reviews||{}).dismiss_stale_reviews')" \
   || ! GOT_LAST="$(field '(.required_pull_request_reviews.require_last_push_approval // false)' '!!(o.required_pull_request_reviews||{}).require_last_push_approval')" \
   || ! GOT_APPR="$(field '(.required_pull_request_reviews.required_approving_review_count // 0)' '(o.required_pull_request_reviews||{}).required_approving_review_count||0')"; then
  echo "NOT verified: the read-back could not be parsed (install jq or node)." >&2
  exit 1
fi

OK=1
[ "$(sorted "$GOT_CONTEXTS")" = "$(sorted "$WANT_CONTEXTS")" ] && CTX_NOTE="as requested" || { CTX_NOTE="MISMATCH (requested: $(printf '%s\n' "$WANT_CONTEXTS" | paste -sd ';' -))"; OK=0; }
[ "$GOT_STRICT" = "true" ] && STRICT_NOTE="as requested" || { STRICT_NOTE="MISMATCH (requested: yes)"; OK=0; }
[ "$GOT_ADMINS" = "$ENFORCE_JSON" ] && ADM_NOTE="as requested" || { ADM_NOTE="MISMATCH (requested: $ENFORCE_WORD)"; OK=0; }
if [ "$GOT_STRICT" = "true" ]; then STRICT_WORD=yes; else STRICT_WORD=no; fi
if [ "$GOT_ADMINS" = "true" ]; then ADM_WORD=yes; else ADM_WORD=no; fi
if [ "$GOT_PR" = "true" ]; then PR_WORD=yes; else PR_WORD=no; fi
[ "$GOT_PR" = "$REQUIRE_PR_JSON" ] && PR_NOTE="as requested" || { PR_NOTE="MISMATCH (requested: $([ "$REQUIRE_PR_JSON" = true ] && echo yes || echo no))"; OK=0; }
if [ "$GOT_PR" = "true" ] && [ "$REQUIRE_PR_JSON" = "true" ] && [ "$GOT_APPR" != "$APPROVALS" ]; then
  PR_NOTE="MISMATCH ($GOT_APPR approving review(s) required, requested: $APPROVALS)"; OK=0
fi
if [ "$GOT_CO" = "true" ]; then CO_WORD=yes; else CO_WORD=no; fi
[ "$GOT_CO" = "$CODEOWNERS_JSON" ] && CO_NOTE="as requested" || { CO_NOTE="MISMATCH (requested: $([ "$CODEOWNERS_JSON" = true ] && echo yes || echo no))"; OK=0; }
if [ "$CODEOWNERS_JSON" = "true" ] && { [ "$GOT_STALE" != "true" ] || [ "$GOT_LAST" != "true" ]; }; then
  CO_NOTE="MISMATCH (a new push must dismiss the approval: dismiss_stale_reviews=$GOT_STALE, require_last_push_approval=$GOT_LAST)"; OK=0
fi

echo ""
echo "Read back from GitHub for $REPO@$BRANCH:"
echo "  required status checks : $(printf '%s\n' "$GOT_CONTEXTS" | paste -sd ';' - | sed 's/;/; /g')  ($CTX_NOTE; $CHECK_NOTE)"
echo "  branch must be current : $STRICT_WORD  ($STRICT_NOTE)"
echo "  admins bound by rules  : $ADM_WORD  ($ADM_NOTE)"
echo "  pull request required  : $PR_WORD  ($PR_NOTE)"
echo "  code owners must review: $CO_WORD  ($CO_NOTE)"
echo ""

if [ "$OK" != "1" ]; then
  echo "MISMATCH: GitHub stored something other than what was requested — the protection is not what you asked for." >&2
  exit 1
fi

if [ "$PR_WORD" = "yes" ]; then
  echo "Every change to $BRANCH goes through a pull request whose required checks are green."
  if [ "$CO_WORD" = "yes" ]; then
    echo "Every PR needs one approving review (GitHub applies the count to all PRs), from a code owner where it"
    echo "touches their paths; a new push dismisses it. Nobody approves their own PR: a solo developer is locked out."
    [ -f .github/CODEOWNERS ] || [ -f CODEOWNERS ] || [ -f docs/CODEOWNERS ] || echo "Note: no CODEOWNERS file in this checkout yet — without one, no review is asked for."
  else
    echo "No approving review is required (a solo developer can merge their own PR); CODEOWNER_REVIEWS=1 adds one for sensitive paths."
  fi
else
  echo "Pull requests are NOT required: a direct push to $BRANCH still works for a commit whose required checks already"
  echo "passed (push a branch first, let CI run, then push or merge it)."
fi
if [ "$ADM_WORD" = "yes" ]; then
  echo "Admins are bound by these rules."
else
  echo "Admins are NOT bound: they can push to $BRANCH directly and the rules do not apply to them."
fi
if [ -z "${REQUIRED_CHECKS:-}" ]; then
  case "$RUNS_STATE" in
    timeout) echo "Note: GitHub did not list the check runs on $BRANCH within 30 s, so the names were not compared with what CI reports.";;
    failed)  echo "Note: listing the check runs on $BRANCH failed ($(head -n 1 "$RUNS_TMP.err" 2>/dev/null)), so the names were not compared with what CI reports.";;
    *) if [ -z "$RUNS" ]; then echo "Note: no check has run on $BRANCH yet, so the names could not be compared with what CI reports."
       elif [ -n "$NOT_SEEN" ]; then echo "Note: the last commit on $BRANCH has no check named$NOT_SEEN (nor a matrix entry of it) — skipped there, or named differently. A required check that never reports blocks every merge."
       fi;;
  esac
  if [ "$RUNS_STATE" != ok ] || [ -z "$RUNS" ] || [ -n "$NOT_SEEN" ]; then
    echo "A job with a matrix reports \"<job> (<entry>)\"; if merges stay blocked, run this again after a full CI run on $BRANCH or set REQUIRED_CHECKS (separated by ;)."
  fi
fi
exit 0

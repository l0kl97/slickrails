#!/bin/sh
# slickrails: set up branch protection for main (rule 5) and read it back from GitHub.
# Prerequisite: gh CLI logged in (gh auth login), repo has a GitHub remote, jq (or node) for the read-back.
# Run inside the target repo: sh scripts/setup-branch-protection.sh [branch]
#
#   ENFORCE_ADMINS=0 sh scripts/setup-branch-protection.sh   keep a direct-push way out for admins
#
# What this does NOT do: require pull requests or human reviews (solo setups: nobody could approve their own
# PR; the AI review covers rule 6). Required status checks alone do not force a PR — GitHub still allows a
# direct push of a commit whose checks already passed.

set -eu

BRANCH="${1:-main}"
case "$(printf '%s' "${ENFORCE_ADMINS:-1}" | tr '[:upper:]' '[:lower:]')" in
  0|false|no|off|n) ENFORCE_JSON=false; ENFORCE_WORD=no;;
  1|true|yes|on|y)  ENFORCE_JSON=true;  ENFORCE_WORD=yes;;
  *) echo "ENFORCE_ADMINS='${ENFORCE_ADMINS}' is not understood (use 1/0, yes/no, on/off) — nothing was sent." >&2; exit 1;;
esac

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI missing — install with: brew install gh && gh auth login" >&2
  exit 1
fi

REPO="$(gh repo view --json nameWithOwner -q .nameWithOwner)"
echo "Branch protection for $REPO@$BRANCH ..."

# Required checks: CI always; smoke/security only if the workflows exist.
CHECKS='"ci"'
[ -f .github/workflows/smoke.yml ] && CHECKS="$CHECKS, \"smoke\""
[ -f .github/workflows/security.yml ] && CHECKS="$CHECKS, \"gitleaks\", \"audit\""
[ -f .github/workflows/pr-size.yml ] && CHECKS="$CHECKS, \"size\""
WANT_CONTEXTS="$(printf '%s' "$CHECKS" | tr -d '" ')"

gh api -X PUT "repos/$REPO/branches/$BRANCH/protection" \
  -H "Accept: application/vnd.github+json" \
  --input - <<EOF >/dev/null
{
  "required_status_checks": {
    "strict": true,
    "contexts": [ $CHECKS ]
  },
  "enforce_admins": $ENFORCE_JSON,
  "required_pull_request_reviews": null,
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
    printf '%s' "$GOT" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{const o=JSON.parse(d);const v=($2);console.log(Array.isArray(v)?v.join(','):v)})" 2>/dev/null
  else
    return 1
  fi
}
sorted() { printf '%s' "$1" | tr ',' '\n' | sort | tr '\n' ','; }

if ! GOT_CONTEXTS="$(field '(.required_status_checks.contexts // []) | join(",")' '(o.required_status_checks||{}).contexts||[]')" \
   || ! GOT_STRICT="$(field '.required_status_checks.strict' '(o.required_status_checks||{}).strict')" \
   || ! GOT_ADMINS="$(field '.enforce_admins.enabled' '(o.enforce_admins||{}).enabled')" \
   || ! GOT_PR="$(field '(.required_pull_request_reviews != null)' 'o.required_pull_request_reviews!=null')"; then
  echo "NOT verified: the read-back could not be parsed (install jq or node)." >&2
  exit 1
fi

OK=1
[ "$(sorted "$GOT_CONTEXTS")" = "$(sorted "$WANT_CONTEXTS")" ] && CTX_NOTE="as requested" || { CTX_NOTE="MISMATCH (requested: $WANT_CONTEXTS)"; OK=0; }
[ "$GOT_STRICT" = "true" ] && STRICT_NOTE="as requested" || { STRICT_NOTE="MISMATCH (requested: yes)"; OK=0; }
[ "$GOT_ADMINS" = "$ENFORCE_JSON" ] && ADM_NOTE="as requested" || { ADM_NOTE="MISMATCH (requested: $ENFORCE_WORD)"; OK=0; }
if [ "$GOT_STRICT" = "true" ]; then STRICT_WORD=yes; else STRICT_WORD=no; fi
if [ "$GOT_ADMINS" = "true" ]; then ADM_WORD=yes; else ADM_WORD=no; fi
if [ "$GOT_PR" = "true" ]; then PR_WORD=yes; PR_NOTE="MISMATCH (this script asks for none)"; OK=0; else PR_WORD=no; PR_NOTE="as requested"; fi

echo ""
echo "Read back from GitHub for $REPO@$BRANCH:"
echo "  required status checks : $GOT_CONTEXTS  ($CTX_NOTE)"
echo "  branch must be current : $STRICT_WORD  ($STRICT_NOTE)"
echo "  admins bound by rules  : $ADM_WORD  ($ADM_NOTE)"
echo "  pull request required  : $PR_WORD  ($PR_NOTE)"
echo ""

if [ "$OK" != "1" ]; then
  echo "MISMATCH: GitHub stored something other than what was requested — the protection is not what you asked for." >&2
  exit 1
fi

if [ "$ADM_WORD" = "yes" ]; then
  echo "Admins are bound by these rules. Pull requests are NOT required: a direct push to $BRANCH still works"
  echo "for a commit whose required checks already passed (push a branch first, let CI run, then push or merge it)."
else
  echo "Admins are NOT bound: they can push to $BRANCH directly and the required checks do not apply to them."
fi
echo "Note (solo dev): required human PR review is deliberately off — the AI review covers rule 6."

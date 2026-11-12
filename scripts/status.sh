#!/bin/sh
# slickrails status — one screen on where a repo stands with the standard.
#   slickrails status            health (doctor's checks, summarised), checks, reviewer, rules, dossiers; offline
#   slickrails status --github   plus the last CI run of this branch and branch protection on main (needs gh)
# Read-only: config.sh is read as text, never run; doctor does the checking, this only sums it up.
# Exit: 0 = shown (even with problems; `slickrails doctor` is the one that fails), 1 = not a slickrails repo.

set -u

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GITHUB=0; PORCELAIN=0
case "${1:-}" in --github) GITHUB=1;; --porcelain) PORCELAIN=1;; esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$ROOT" ] || [ ! -f "$ROOT/.slickrails/config.sh" ]; then
  [ "$PORCELAIN" = "1" ] && { echo "installed=0"; exit 0; }
  echo "slickrails status: not installed here (no .slickrails/config.sh) — run: slickrails init" >&2
  exit 1
fi
cd "$ROOT" || exit 1

row() { printf '  %-10s %s\n' "$1" "$2"; }
cfg() { sed -n "s/^[[:space:]]*$1=[\"']\{0,1\}\([^\"']*\)[\"']\{0,1\}[[:space:]]*\$/\1/p" .slickrails/config.sh | tail -n 1; }
SF=".slickrails/STATUS.md"; [ -f "$SF" ] || SF="SLICKRAILS-STATUS.md"
GATE_FILE="$(git rev-parse --git-dir)/slickrails-last-gate"   # written by the Stop gate; missing until it first ran
# "<mark>\t<rule>" per row of the status table (rule 10)
# the feature dossiers, one path per line (README and the template are not dossiers)
dossiers() { for D in docs/features/*.md; do case "$D" in *'*'*|*/README.md|*/_TEMPLATE.md) ;; *) printf '%s\n' "$D";; esac; done; }
rules() { [ -f "$SF" ] && awk -F'|' '$2 ~ /^ *[0-9]+ *$/ { gsub(/^ +| +$/, "", $3); gsub(/ /, "", $4); print $4 "\t" $3 }' "$SF"; }

# --porcelain: key=value lines for the status mod — cheap facts only (no doctor run, no network), so it can run after
# every turn. hooks/guard say "wired", not "probed": `slickrails doctor` probes.
if [ "$PORCELAIN" = "1" ]; then
  HP="$(git config core.hooksPath 2>/dev/null || true)"
  HOOKS=0; { [ "$HP" = ".githooks" ] || { [ -n "$HP" ] && [ -d "$HP" ] && [ "$(cd "$HP" && pwd -P)" = "$(cd .githooks 2>/dev/null && pwd -P)" ]; }; } && HOOKS=1
  GUARD=0; [ -x .slickrails/bash-guard.sh ] && grep -qs 'bash-guard.sh' .claude/settings.json .codex/hooks.json && GUARD=1
  REVIEW=off; [ "$(cfg CHECK_PREPUSH_REVIEW)" = "1" ] && REVIEW="$(cfg REVIEW_CLI)" && REVIEW="${REVIEW:-auto}"
  GATE=none; GATE_AGE=""
  if [ -f "$GATE_FILE" ] && read -r G_RES G_AT < "$GATE_FILE"; then
    GATE="$G_RES"; GATE_AGE=$(( $(date +%s) - ${G_AT:-0} ))
  fi
  R="$(rules)"; R_TOTAL="$(printf '%s\n' "$R" | grep -c . || true)"; R_DONE="$(printf '%s\n' "$R" | grep -c '^☑' || true)"
  N_DOSS="$(dossiers | grep -c . || true)"
  printf 'installed=1\nhooks=%s\nguard=%s\nreview=%s\ngate=%s\ngate_age=%s\nrules_done=%s\nrules_total=%s\nrules_open=%s\ndossiers=%s\n' \
    "$HOOKS" "$GUARD" "$REVIEW" "$GATE" "$GATE_AGE" "$R_DONE" "$R_TOTAL" "$((R_TOTAL - R_DONE))" "$N_DOSS"
  exit 0
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
echo "slickrails status — $(basename "$ROOT") ($BRANCH), kit $(cat "$KIT_DIR/VERSION" 2>/dev/null || echo '?')"
echo ""
# an install from another kit version: say how to update (the manifest's first line names the version)
INST_V="$(sed -n '1s/^# slickrails \([^ ]*\) .*/\1/p' .slickrails/manifest 2>/dev/null)"
[ -n "$INST_V" ] && [ "$INST_V" != "$(cat "$KIT_DIR/VERSION" 2>/dev/null)" ] \
  && row "Kit" "installed with $INST_V — update: slickrails init (files nobody edited are replaced)"

# Health: doctor's verdict, counted; problems are named
DOC="$(sh "$KIT_DIR/install.sh" doctor 2>&1 || true)"
N_OK="$(printf '%s\n' "$DOC" | grep -c '^slickrails:   ok ' || true)"
N_PROB="$(printf '%s\n' "$DOC" | grep -c '^slickrails:   PROBLEM ' || true)"
N_WARN="$(printf '%s\n' "$DOC" | grep -c '^slickrails:   WARN ' || true)"
P_WORD="problems"; [ "$N_PROB" = "1" ] && P_WORD="problem"
row "Health" "$N_OK ok, $N_PROB $P_WORD, $N_WARN warnings   (details: slickrails doctor)"
printf '%s\n' "$DOC" | sed -n 's/^slickrails:   PROBLEM  /             ✗ /p'

# What the hooks check, and who reviews
T="$(cfg CHECK_TYPECHECK)"; S="$(cfg CHECK_TEST)"
row "Checks" "typecheck: ${T:-—} · tests: ${S:-—}"
if [ "$(cfg CHECK_PREPUSH_REVIEW)" = "1" ]; then
  row "Review" "local, before every push: $(cfg REVIEW_CLI | sed 's/^$/auto/') (profile: $(cfg REVIEW_PROFILE | sed 's/^$/chill/'))"
else
  row "Review" "local review off (CHECK_PREPUSH_REVIEW=\"1\" turns it on; claude or codex, no API key)"
fi
if [ -f .github/workflows/claude-review.yml ]; then row "" "PR review on GitHub: on (needs the Claude GitHub App and a secret)"
else row "" "PR review on GitHub: off (server-side, optional: slickrails github-review)"; fi
if [ -f "$GATE_FILE" ] && read -r G_RES G_AT < "$GATE_FILE"; then
  G_MIN=$(( ($(date +%s) - ${G_AT:-0}) / 60 ))
  row "Gate" "last session checks: $G_RES, $G_MIN min ago (the Stop gate of Claude Code / Codex)"
fi

# Rules: the table in the status file (rule 10)
if [ -f "$SF" ]; then
  RULES="$(rules)"
  TOTAL="$(printf '%s\n' "$RULES" | grep -c . || true)"
  DONE="$(printf '%s\n' "$RULES" | grep -c '^☑' || true)"
  row "Rules" "$DONE of $TOTAL in place   ($SF)"
  printf '%s\n' "$RULES" | grep -v '^☑' | cut -f2 | sed 's/^/             ☐ /'
else
  row "Rules" "no status file (.slickrails/STATUS.md) — re-run: slickrails init"
fi

# Dossiers: the context that survives the chat
DOSS="$(dossiers)"
N_DOSS="$(printf '%s\n' "$DOSS" | grep -c . || true)"
D_LIST="$(printf '%s\n' "$DOSS" | sed 's|.*/||; s|\.md$||' | head -n 6 | tr '\n' ' ')"; [ "$N_DOSS" -gt 6 ] && D_LIST="${D_LIST}…"
row "Dossiers" "$N_DOSS in docs/features/$( [ "$N_DOSS" -gt 0 ] && printf ': %s' "$D_LIST")"

# GitHub, on request: last CI run of this branch, protection on main (each gh call bounded to 15 s)
if [ "$GITHUB" = "1" ]; then
  if ! command -v gh >/dev/null 2>&1; then
    row "GitHub" "gh not found (brew install gh && gh auth login)"
  else
    bounded() { # bounded <out-file> <cmd...>: run with a deadline; exit 124 when it did not finish
      OUTF="$1"; shift; ( "$@" > "$OUTF" 2>/dev/null ) & BP=$!; W=0
      while kill -0 "$BP" 2>/dev/null; do [ "$W" -ge 75 ] && { kill "$BP" 2>/dev/null; return 124; }; sleep 0.2; W=$((W + 1)); done
      wait "$BP"
    }
    TMPF="$(mktemp "${TMPDIR:-/tmp}/slickrails-status.XXXXXX")"; trap 'rm -f "$TMPF"' EXIT
    if bounded "$TMPF" gh run list --branch "$BRANCH" --limit 1 --json workflowName,status,conclusion \
         --jq '.[0] // empty | "\(.workflowName): \(.status) \(.conclusion // "")"'; then
      LAST="$(cat "$TMPF")"; row "GitHub" "last CI on $BRANCH — ${LAST:-no run yet}"
    else
      row "GitHub" "last CI on $BRANCH — could not ask GitHub (gh auth status?)"
    fi
    if bounded "$TMPF" gh api "repos/{owner}/{repo}/branches/main/protection"; then row "" "main is protected"
    else row "" "main protection: none, or not visible to you (slickrails protect)"; fi
  fi
fi
exit 0

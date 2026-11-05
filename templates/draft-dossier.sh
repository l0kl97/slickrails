#!/bin/sh
# slickrails: dossier autopilot — drafts docs/features/<slug>.md from a diff
# when a feature was built without one (rule 11). Run from the repo root:
#   slickrails dossier [base-ref] [slug]
# Defaults: base-ref = origin/main|origin/master|main|master, slug = branch name.
# Needs the claude CLI. The draft is a starting point — read it before committing.

set -eu

say() { printf '%s\n' "slickrails[dossier]: $*"; }

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { say "not a git repo."; exit 1; }
cd "$REPO_ROOT"

BASE="${1:-}"
if [ -z "$BASE" ]; then
  for CAND in origin/main origin/master main master; do
    if git rev-parse --verify -q "$CAND" >/dev/null 2>&1; then BASE="$CAND"; break; fi
  done
fi
[ -z "$BASE" ] && { say "no base ref found — pass one: slickrails dossier <base-ref>"; exit 1; }

if git diff --name-only "$BASE"...HEAD 2>/dev/null | grep -q '^docs/features/'; then
  say "this range already touches docs/features/ — nothing to draft."
  exit 0
fi

DIFF="$(git diff "$BASE"...HEAD 2>/dev/null || true)"
[ -z "$DIFF" ] && { say "no diff against $BASE — nothing to document."; exit 0; }

command -v claude >/dev/null 2>&1 || { say "claude CLI not found — cannot draft (install: https://claude.com/claude-code)."; exit 1; }

SLUG="${2:-$(git rev-parse --abbrev-ref HEAD | tr '/' '-' | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9-' '-' | sed 's/^-*//;s/-*$//')}"
[ -z "$SLUG" ] || [ "$SLUG" = "head" ] && SLUG="undocumented-feature"
OUT_FILE="docs/features/$SLUG.md"
[ -f "$OUT_FILE" ] && { say "$OUT_FILE already exists — extend its history instead of redrafting."; exit 1; }

TEMPLATE=""
[ -f docs/features/_TEMPLATE.md ] && TEMPLATE="$(cat docs/features/_TEMPLATE.md)"

say "drafting $OUT_FILE from the diff against $BASE ..."

DRAFT="$(printf 'Dossier template:\n%s\n\n--- DIFF ---\n%s\n' "$TEMPLATE" "$DIFF" | claude -p "Draft a feature dossier in the template's structure, based ONLY on the diff. Infer the ask in plain language from what the change does; list the key decisions visible in the code; map where it lives (files → roles); describe how a human tests it; name limits you can see. Where you cannot know something (the original request's wording, the builder's name), write a [FILL IN] placeholder — never invent it. Output ONLY the markdown document, no preamble." 2>/dev/null || true)"

if [ -z "$DRAFT" ]; then
  say "drafting failed (empty response) — try again or write the dossier by hand from docs/features/_TEMPLATE.md."
  exit 1
fi

mkdir -p docs/features
printf '%s\n' "$DRAFT" > "$OUT_FILE"
say "draft written to $OUT_FILE — read it, fill the [FILL IN] gaps, commit it with the feature."

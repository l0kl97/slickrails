# Opt-in deep security review: hardened use of Anthropic's action

**Status:** active · **As of:** 2026-10-21 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
The maintainer: "und lass uns https://github.com/anthropics/claude-code-security-review überprüfen ob wir davon etwas
implementieren sollten" — and, after the evaluation: "ja, setz die drei kleinen Punkte um." slickrails already
wraps that action in the opt-in template `templates/workflows/security-review-ai.yml`. Reading the action's real
`action.yml` showed three problems in how the template used it.

## Decisions
- **`run-every-commit: true`.** The action writes a per-PR marker into the Actions cache and, on later pushes, finds it and disables itself ("already run … forcing disable to avoid false positives"). Without the flag only the first commit of a PR was ever scanned. Cost: one scan per push; the template's concurrency group cancels superseded runs.
- **Pinned to a commit SHA** (`0c6a49f1fa56a1d472575da86a94dbc1edb78eda`, upstream `main` of 2026-02-11, pinned 2026-10-21) instead of `@main`. The repository has no tags or releases, so a SHA is the only immutable reference; the action itself pins all its own dependencies that way. A moving branch would run whatever lands next with the repo's API key. Updating is a deliberate step (the template says how).
- **Fork PRs are skipped** (`head.repo.full_name == github.repository`). They get no secrets, so the run would only go red, and the action has no fork check of its own (its README says it is not hardened against prompt injection).
- The test is a lint of the template (grep for the pinned SHA, no `@main`, the flag, the guard) plus a YAML validity check of every workflow template — not a run of the workflow.

## Evaluated but not done (the rest of the evaluation)
- Pointing `false-positive-filtering-instructions` at `.slickrails/review-learnings.md` (unverified how the action treats that format; needs a real API run).
- Ideas from the action's slash-command prompt (confidence threshold, exclusion list, find-then-verify): the L2 fixtures of the benchmark are at the ceiling and cannot show a false-positive reduction; harder fixtures come first.
- Shipping our own copy of `.claude/commands/security-review.md`: it would drift from upstream; the built-in command is enough.
- Gating on `findings-count`: the action stays advisory.

## Where it lives
- `templates/workflows/security-review-ai.yml`
- `tests/run.sh` — block "opt-in deep security workflow"
- `SLICKRAILS.md` — rule 6 paragraph

## How to test it
1. `sh tests/run.sh` — the five checks "security-review-ai.yml: …" and "workflow templates: every file is valid YAML".
2. Not tested: an actual workflow run on GitHub (needs a repo, the secret and a PR). The behavior of the action was read from its `action.yml`, not executed.

## Limits & open items
- The pinned SHA is 8 months old at pin time; nobody has verified it with a real run in this kit. Dependabot cannot bump a bare branch SHA of a tag-less repository — updating is manual.
- `run-every-commit` can raise false positives on PRs with many commits (upstream README).
- The README documents the default model as Opus while `action.yml` leaves it empty: cost per scan is unverified; set `claude-model` explicitly if it matters.

## History
- 2026-10-21: hardened the template (three points above).
- 2026-10-22: not this opt-in workflow but its sibling `security.yml`: the gitleaks job failed with 403 on the repo's first pull request, because gitleaks-action lists the PR's commits through the API and the job had no `pull-requests: read`. Fixed in the template and this repo's copy; a lint in `tests/run.sh` keeps the permission.

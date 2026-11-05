<!-- slickrails:start — this block is inserted into the project's CLAUDE.md / AGENTS.md by install.sh -->
## Guardrails (binding)

This repo follows the slickrails standard (see `.slickrails/SLICKRAILS.md`). For every AI coding session:

- **Bugfix = repro test first (red), then fix (green).** Never the other way around, never without a test.
- **Critical user flows need Playwright smoke tests in a real browser** — Node unit tests are not enough. New critical flow ⇒ new smoke test in the same PR.
- **Before "done":** run the checks from `.slickrails/config.sh` locally (typecheck, tests, smoke if present). Red = not done.
- **Definition of Done:** code + tests + docs update + smoke green.
- **Never** push directly to main, **never** bypass hooks with `--no-verify`/`SLICKRAILS_SKIP` unless the user explicitly says so — then the reason goes in the commit message.
- **No secrets** in code or commits; `.env` stays local, `.env.example` is maintained.
- **Security-sensitive changes** (auth, input handling, crypto, file/network access) get a local `/security-review` pass before the merge.
- Project-specific review focus areas live in `.slickrails/rules.md` — honor them in reviews and larger changes.
- **Maintain the feature dossier (rule 11):** when building a feature, create `docs/features/<slug>.md` (template: `_TEMPLATE.md`): the ask in plain language (capture the human's original request!), decisions, where it lives, how to test. On changes/bugfixes, extend the history (symptom → cause → fix).
- **Commit bodies tell why + what** in plain language — not just what, but what for. The commit-msg hook enforces this on larger commits.
- **Tests exercise failure modes**, not just the happy path: invalid input, error responses, boundary values. Happy-path-only is not done.
- **No code in a vacuum:** external calls (HTTP, DB, queue) get a timeout, error handling, and logging. Don't introduce deprecated APIs.
- **Keep PRs small** (< ~800 changed lines): cut big tasks into multiple PRs instead of building an unreviewable one.
- **Validator memory:** when a hook, a review, or a human catches a real bug in AI-built code, append the lesson to `.slickrails/review-learnings.md` — every caught failure makes the next review smarter.
- Track resolved/new gaps against the standard in `.slickrails/STATUS.md`.
<!-- slickrails:end -->

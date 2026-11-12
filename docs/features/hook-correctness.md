# Hook correctness: pushed-SHA guard, .env renames, exact review verdict

**Status:** active · **As of:** 2026-10-20 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
Improvement plan, point 2, from the Codex audit and Claude's cross-check: three proven gaps in the Git hooks
and the review wrapper. "green before push" did not describe what was pushed; renaming a file onto `.env`
slipped past the secret-file block; a reviewer answering `VERDICT: PASS but actually FAIL: …` counted as PASS
and a crashed or garbled review disappeared silently.

## Decisions
- **pre-push reads the stdin ref tuples** and blocks when the pushed commit is not HEAD or when tracked files are uncommitted (decision E4). Deletions are skipped, tags are peeled to their commit. Rejected: an isolated checkout per pushed SHA with dependency install — minutes per push, the guard closes the proven case in ~30 ms.
- **pre-commit** looks at destination paths (`ACMRT`, `-z`), so renames and type changes onto `.env*` are blocked.
- **ai-review.sh**: with `jq`, `claude -p --output-format json --json-schema` returns the verdict as a schema-checked field (`--max-turns 3`); without it, or from a CLI that returns no structured output, the first line must be exactly `VERDICT: PASS|FAIL`. Everything else is an `ERROR` line, never a PASS. Per decision E3 a failed or invalid review warns and lets the push proceed (`REVIEW_ON_ERROR="warn"`, default) or blocks it (`"block"`). Rejected: fail-closed by default (a network or login hiccup would train people to bypass the hook).
- **Self-review round 1** (fresh reviewer on `e7d9018`, findings reproduced first, then): untracked files now count as "dirty" (a new test file nobody added is exactly the "green locally, red in CI" case); tag pushes on older commits only note instead of blocking (releases are tagged on older commits), branches other than HEAD stay blocked ("one branch at a time"); `ai-review.sh` has a deadline (`REVIEW_TIMEOUT`, default 120 s, watcher process because macOS has no `timeout`) and exits 3 for "unreviewed" so pre-push says "AI review did NOT run" instead of "All green"; `REVIEW_ON_ERROR` is case-insensitive and unknown values mean block; `.env` matching is case-insensitive; FAIL without findings and reviewer stderr are shown.
- Rejected in that round: `.envrc`/other secret file names (pre-existing scope, not point 2); `grep -z` for filenames with newlines (only a false positive, not portable); removing the explicit zero-SHA branch (clarity); fixing the template's file mode (install.sh chmods; pre-existing); handling a leading blank line or markdown fence in the text protocol (fails safe as ERROR); prompt-injection that semantically persuades the model (inherent, not testable without model runs — unverified).
- Removed the duplicated performance sentence from the review prompt.
- `.githooks/pre-push` is this repo's own variant and was not touched; `.githooks/pre-commit` and `.slickrails/ai-review.sh` are synced with the templates.

## Where it lives
- `templates/hooks/pre-push` — stdin guard · `templates/hooks/pre-commit` — destination paths · `templates/ai-review.sh` — verdict protocol
- `install.sh` — writes `REVIEW_ON_ERROR="warn"` into new `config.sh`
- `tests/run.sh` — hook edge cases and the review protocol with stub reviewers (text and structured)
- `tests/benchmark/cases/{pc-rename-env,pp-red-head-green-worktree,rv-pass-but-fail}` — known-miss markers deleted

## How to test it
1. `sh tests/run.sh` — expect 56 passed (incl. the benchmark L1 check).
2. `sh tests/benchmark/run.sh` — expect `caught 7/10 faults, false positives 0/8 controls, known-miss 3`.
3. `env BENCH_MODEL=<model id> BENCH_AI=1 sh tests/benchmark/run.sh --layer L2` — the real `claude` through the structured-output path.

## Limits & open items
- An up-to-date push never calls the hook (git sends no refs) — nothing to check then.
- The dirty-tree rule can block a push with unrelated uncommitted or untracked files; the message lists them and names the fix, `SLICKRAILS_SKIP=1` is the documented exception. Ignored files are not looked at (an ignored `.env` can still influence local tests).
- `git push --all` and pushing several branches is blocked (only HEAD is checked); non-commit objects (blob tags) are skipped. Windows Git Bash / CRLF is untested. Without `jq` only the text protocol runs, and the structured-output tests in `tests/run.sh` are skipped.
- Waiting for Codex acceptance: nothing in this point touches Codex hooks; the Git hooks apply to Codex sessions too, which is not verified under a Codex run.

## History
- 2026-10-20: created (plan point 2). Benchmark L1 4/10 → 7/10 faults, 0/8 false positives.
- 2026-10-20: found while self-reviewing plan point 3: the review deadline used a watcher process (`sleep $REVIEW_TIMEOUT`) that outlived every review (one orphaned `sleep 120` per push) → `ai-review.sh` now polls the reviewer (TERM, then KILL) and leaves nothing behind; test "a finished review leaves no watcher process behind".
- 2026-10-20: symptom: the Stop hook turned red on "REVIEW_ON_ERROR=block turns an invalid answer into a block" right after `install.sh` started writing `REVIEW_ON_ERROR="warn"` into `config.sh` → cause: sourcing `config.sh` overwrote an exported `REVIEW_ON_ERROR` → fix: the exported value wins over the config (one-off override), suite back to 45 passed.
- 2026-10-21: incident during the 1.3.0 release push. Symptom: `git push` from a linked worktree ran the kit's suite through pre-push, and the suite's `git init` / `git commit` / `git push` landed in the REAL repository: `core.bare=true`, a test identity (`slickrails Tests`) that then authored real commits, test branches and tags, fake push URLs, and test commits pushed to the real GitHub remote (`main`, two branches, two tags). Cause: git exports `GIT_DIR` (and friends) to hooks, and `run_check` passed them on to `CHECK_TEST`; every git command in a check then addressed the hook's repository instead of the one it created. The kit's other layers did not catch it because the push that was blocked had already done the damage while running its checks. Fix: `run_check` (pre-push) and the staged lint (pre-commit) run without those variables; `tests/run.sh` clears them at the top. Test (red first, with the old hook: `user.name=leak-probe, core.bare=true`): "pre-push: checks run without git's hook environment".
- 2026-10-22 (PR #13, Windows): a structured review verdict read with jq on Windows was "PASS\r" and therefore an ERROR → `\r` is stripped from jq's output in `ai-review.sh` (test with a CRLF jq stand-in, red first). The Bash guard already coped with CRLF; a test keeps it that way.
- 2026-10-29: symptom: "pre-commit: blocks staged secret" red on a machine with gitleaks 8.30 (green in CI, which has no local gitleaks) → cause: with gitleaks installed the hook skipped its own patterns, and gitleaks judges by entropy, so a low-entropy `sk-…` key passed → fix: the patterns always run, gitleaks on top; test "a key gitleaks lets through is still caught by the patterns" (gitleaks stub, red on every machine before the fix).
- 2026-11-12 (1.6.0): deleting a remote branch ran the whole suite and the AI review (the deletion was skipped in the
  ref loop, the checks below it ran anyway; seen while cleaning up six merged branches, about 3 minutes each) →
  a push of nothing but deletions exits before the checks. And the suite ran twice for one state (Stop gate, then
  pre-push) → pre-push reads and writes the Stop gate's record of the last green tree + commands
  (`.git/slickrails-last-ok`); only with a clean tree and without a separate `CHECK_SESSION`.

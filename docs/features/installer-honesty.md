# Installer and protection that say what actually holds

**Status:** active · **As of:** 2026-10-20 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
Improvement plan, point 4. The kit claimed more than it delivered in five places: the installer switched
`core.hooksPath` unconditionally (switching off Husky and friends without a word); an existing
`.claude/settings.json` only got a warning ("merge by hand"), so the Stop gate was often not installed; the only
thing standing between an agent and `git commit --no-verify` was a sentence in `CLAUDE.md`; a fresh clone has no
active hooks (`core.hooksPath` is local git config) and nothing said so; and the branch-protection script ended with
"main now only accepts PRs" although required status checks do not force PRs and admins were not bound.

## Decisions
- **Hook manager:** an existing `core.hooksPath` other than `.githooks` is left alone. The installer still places `.githooks/*` (to chain them), says "the slickrails git hooks are NOT active" on stderr, and writes it into `SLICKRAILS-STATUS.md` (rule 3 and 11 stay ☐). Rejected: chaining automatically (writing into another tool's hook files).
- **Claude settings:** merge instead of warn. `jq` (else `node`) adds the Stop gate and the Bash guard, keeps every other key and foreign hook, is idempotent (detected by `session-check.sh` / `bash-guard.sh`), and never rewrites a file that is not valid JSON (warning, file untouched).
- **Bash guard** (`templates/bash-guard.sh`, PreToolUse on `Bash`): blocks `git … --no-verify` (also abbreviated — git accepts unique prefixes), `git commit -n`, a `SLICKRAILS_SKIP=` assignment and switching hooks off via `core.hooksPath` (`-c`, set elsewhere, `--unset`; reading it and pointing it back at `.githooks` are fine) with exit 2. With `jq` (or `node`) the command is parsed out of the hook JSON and quoted text (commit messages, echo strings) is ignored, `git` must be a word of its own (not `lazygit`), and each `;`/`&&` segment is looked at separately; with neither the raw JSON is matched (mentions inside quotes are blocked too). The way out is the human's: `SLICKRAILS_ALLOW_BYPASS=1` in the agent's environment (an agent cannot set the hook's environment from a Bash call). A hint, not a boundary: editing hook files or `.claude/settings.local.json`, a script file containing the bypass, a quoted `"--no-verify"` argument and a command held in a shell variable are not seen.
- **doctor** now also checks the repo it is run in: `core.hooksPath` (our own directory however it is spelled, or a hook manager that calls `.githooks/*` counts as chained), hook files executable, `config.sh` (read as text, never executed: a syntax error is a problem, no check defined is a warning), Stop hook and Bash guard configured in the settings AND present as executable files. It says plainly that "ok" means installed, not working (Claude Code's/Codex's hook trust is not checked). Exit 1 when a repo problem exists; in CI (`CI` set) a missing `core.hooksPath` is only a warning.
- **Settings detection** is structural with `jq` or `node` (never a text search): a hook only counts if its command IS our script (optionally behind `sh`/`bash`, quoted, with a path in front, no further arguments) — a foreign hook that merely mentions the script name or even its `.slickrails/…` path (`echo .slickrails/session-check.sh`) does not count, a duplicate being better than a missing hook. With neither tool the installer does not merge (it says so) and `doctor` says "cannot verify" instead of "configured". An empty `settings.json` is treated as missing; the merge writes through a symlink and keeps the file mode; the warning names the reason (not valid JSON / unexpected shape / no jq or node).
- **Status file:** the "hooks NOT active" line is added on a rerun too, once; it is never removed (the file is the user's document, `doctor` shows the current truth).
- **Branch protection:** `enforce_admins` defaults to true (decision E5; `ENFORCE_ADMINS=0|no|off` opts out, unknown values stop before anything is sent), the script reads the protection back from GitHub, compares status checks, "branch must be current" (`strict`), the admin setting and a review requirement nobody asked for with the request (MISMATCH or "NOT verified" → exit 1) and ends with what holds. Since 1.5.0 pull requests are required with 0 approving reviews (a solo maintainer merges their own PR, nothing reaches main without the PR's checks; `REQUIRE_PR=0` opts out), code-owner reviews are opt-in (`CODEOWNER_REVIEWS=1`: one approval on every PR — GitHub applies the count to all PRs —, a new push dismisses it and the last push needs approval), and the required check names come from the branch's last check runs (a matrix job reports `ci (<entry>)`, never `ci`) or from `REQUIRED_CHECKS` (separated by `;`). Names are sent and compared line by line: a two-dimension matrix reports `ci (ubuntu-latest, 20)`.

## Where it lives
- `install.sh` — hooksPath handling, settings merge, status, `doctor`
- `templates/bash-guard.sh`, `templates/claude-settings.json` (PreToolUse entry)
- `scripts/setup-branch-protection.sh`
- `tests/run.sh` — "installer honesty" block (Husky, settings merge/idempotence/broken JSON, guard patterns, doctor in a fresh clone, protection script with a `gh` stub)
- `tests/benchmark/cases/{inst-husky-clobber,inst-fresh-repo,agent-no-verify,agent-git-status}` — two faults, two controls
- `tests/benchmark/host/claude-bash-guard.sh` — real Claude Code: ordinary commit goes through, `--no-verify` without the guard goes through, with the guard it is stopped
- `SLICKRAILS.md`, `SLICKRAILS.de.md`, `docs/guides/adopt-in-a-team.md`

## How to test it
1. `sh tests/run.sh` — expect 166 passed.
2. `sh tests/benchmark/run.sh` — expect `caught 11/12 faults, false positives 0/10 controls, known-miss 1`.
3. `env BENCH_AI=1 sh tests/benchmark/host/claude-bash-guard.sh` — real-host effect of the guard.

## Limits & open items
- Waiting for Codex acceptance: the guard is a Claude Code `PreToolUse` hook. Codex has the same event in its documentation (`PreToolUse`), but nothing is installed for it (plan point 5, undecided) and its behavior is unverified.
- The `gh` stub returns the response shape of GitHub's protection API as documented, but the real GitHub behavior was NOT tested (no sandbox repository): `required_status_checks.contexts`, `enforce_admins.enabled` and a missing `required_pull_request_reviews` key are assumptions.
- With neither `jq` nor `node` the guard falls back to matching the raw JSON (a quoted mention of `--no-verify` is then blocked too); that last-resort path is not covered by a test.
- Not handled: `core.hooksPath` set globally is detected (git reads the effective value) but never changed; the protection script does not URL-encode branch names; the read-back confirms what GitHub stored; the check names are compared with real jobs only when a check has run on the branch (otherwise the script says so); a required check that never reports blocks merging.
- The repo's own `.claude/settings.json` was not changed by this work (it is not re-installed here).
- `jq` or `node` is needed for the settings merge and the protection read-back; without both the installer warns and leaves the file alone.

## History
- 2026-10-20: created (plan point 4). Benchmark L1 9/10 → 11/12 faults, 0/10 false positives.
- 2026-10-20: self-review of 0ff4b2a (fresh reviewer, 29 findings; the ones below reproduced first). Symptom → cause → fix:
  - the guard let `--no-verif`, `git commit -n/-nm`, `SLICKRAILS_SKIP="1"` and `--no-verify` after a commit message containing `;` through, and blocked commit messages or `lazygit` that merely mentioned `--no-verify` → matching on raw JSON with `[^|;&]*` → command parsed with jq, quoted text dropped, word-boundary `git`, abbreviations, `-n`, quoted values, `core.hooksPath`;
  - an empty `settings.json` reported "merged" and stayed 0 bytes; a foreign hook mentioning our script names suppressed the merge (also fooled doctor); a symlinked `settings.json` was replaced by a regular file → empty = missing, structural detection, write-through;
  - `.githooks/` or `./.githooks` was reported as a foreign hook manager (and doctor failed forever) → path comparison by directory; a rerun never updated the status file;
  - doctor executed `config.sh` (side effects) and said "defines checks" for `exit 3`/unbound variables → config read as text; doctor exit 1 in CI clones and for correctly chained hook managers → CI warning, chained detection;
  - the protection read-back ignored `strict` and printed "Pull requests are NOT required" next to "pull request required: yes"; `ENFORCE_ADMINS=off` meant true → both compared, values parsed or rejected.
  Codex review of 0ff4b2a and eb0e69a (mailbox), reproduced first (a PATH without jq, with and without node; the same trap reproduced with jq): the grep-based detection let a bare mention suppress the Stop gate (0ff4b2a); the jq-free fallback was the same text search, and even the structural check accepted `echo .slickrails/session-check.sh …` → detection requires the command to be the script itself, node does it without jq, neither tool means "cannot verify"; the guard without jq blocked quoted mentions → node parses the hook JSON; the sorted read-back comparison had no test (mutant without `sort` survived) → test with the contexts in another order, the mutant is red now.
  Codex review of 1c76677 (and the overall review): a correctly quoted hook command for a repo path with a space (`sh "/my repo/.slickrails/session-check.sh"`) was not recognised because every space counted as an extra argument → a second Stop hook was added → one quoted string now counts as one token (jq and node), unquoted words with spaces still do not. Test with a repo directory called "space repo", jq and node, plus an unchanged rerun.
  Found while dogfooding after the overall review: commit messages written as a heredoc (the usual way an agent commits) were blocked when the body merely mentioned `--no-verify` → heredoc bodies are dropped before analysis (a here-string `<<<` opens no body; a real `--no-verify` after the heredoc is still blocked). And the repo's own `.githooks/pre-push` was an outdated copy without the pushed-SHA guard, `.slickrails/bash-guard.sh` and the PreToolUse entry were missing → copies synced, plus a test that every own hook/script/settings file equals its template.
  Codex reviews of 689aee9, 91341ed, 99819a9 and e4f409c (all reproduced by tests first): (1) a repo path containing a shell-escaped double quote (`sh "/x/quote\"repo/.slickrails/session-check.sh"`) was not recognised, a second Stop hook was added (Claude, Codex, jq and node) → the quoted-token rule accepts backslash escapes; (2) the guard's heredoc stripper was not quote-aware: `echo "<<EOF"` followed by `git push --no-verify` and `EOF` hid the real bypass — a real hole, shipped to Codex as well — and indented/multiple heredocs caused false alarms → `scan_command` is one quote-aware pass: quotes and escapes tracked, `<<` only opens a heredoc outside quotes and comments (`<<<` and a shift like `$((1<<3))` open none), `<<WORD` ends at an exact `WORD` line, `<<-WORD` after leading tabs only, several heredocs on one line are consumed in order, comments are skipped. Still not seen by the guard: anything inside `"$(...)"` or backticks within quotes.
  Rejected: splitting doctor into its own script (readability only), URL-encoding branch names (ungeprüft), comparing `allow_force_pushes`/`required_linear_history`, protecting the guard against edits of `settings.local.json` (a hint, not a boundary), a `.` fallback test without jq.
- 2026-10-22 (PR #13, Windows): `bootstrap.sh` linked the CLI with `ln -s`; Git Bash without symlink permission copies instead, and the copy looked for the kit next to itself, so the `slickrails` command did not work → a two-line launcher is written when the result is not a symlink (test with an `ln` that copies, red first; the bootstrap test now runs the installed command instead of the kit's copy). The branch-protection read-back failed on Windows because jq ends its lines with CRLF → `\r` is stripped while jq's exit status still decides (test with a CRLF jq stand-in, red first). The no-jq/no-node tests build their tool box from launchers and include git (Git Bash keeps it in /mingw64/bin).
- 2026-10-29: doctor probes what it reports: the installed guard must block a `--no-verify` probe and let `git status` through, the installed pre-commit hook must block a staged test key in a scratch repo (tests: a guard reduced to `exit 0`, one that blocks everything, a pre-commit that lets everything through). The Stop gate is not probed (it would run the project's checks).
- 2026-10-29: bundled install (asked by the maintainer: "should I see all the slickrails things in my repo?"). Rulebook and status move to `.slickrails/SLICKRAILS.md` and `.slickrails/STATUS.md` (an older install's root files are moved with their edits, never in the kit's own repo); the branch-protection script is no longer copied, `slickrails protect` runs the kit's (an unchanged old copy is removed, an edited one stays with a note). `.githooks/` stays: git needs one fixed path per clone. The installer is quiet by default (a count, `--verbose` lists every file) and shows only the next steps that apply (branch protection and the GitHub App only with a GitHub remote).
- 2026-10-29: symptom (full real claude review): after the move, the rules block in CLAUDE.md/AGENTS.md and an installed CI workflow still named `SLICKRAILS.md`/`SLICKRAILS-STATUS.md` → fix: the migration rewrites those paths in CLAUDE.md, AGENTS.md and `.github/workflows/*.yml` (test with an old block, red first).
- 2026-11-11 (1.5.0, outside review of 1.4.0 + publishing the kit repo): two gaps in `slickrails protect`.
  (1) Required checks alone do not force a PR: a commit whose checks passed elsewhere could be pushed straight to
  main, the biggest hole for teams of agent builders → PRs are now required by default with 0 approvals (GitHub's
  `required_approving_review_count: 0`), so a solo maintainer is not locked out; `CODEOWNER_REVIEWS=1` adds a
  human review for sensitive paths. Rejected: requiring one approval by default (a solo developer cannot approve
  their own PR). (2) Publishing the kit repo blocked every merge: `protect` required `ci`, but a matrix job only
  reports `ci (ubuntu-latest)` etc. → the names come from the branch's last check runs, `REQUIRED_CHECKS`
  overrides. Rejected: parsing the workflow YAML in sh (matrix expressions like `fromJSON(...)` are only known
  at run time).
  The local review (claude) of this change found three more before it left the machine: names were joined and split
  at commas, so `ci (ubuntu-latest, 20)` would have been mangled and blocked every merge again → one name per line;
  a code owner's approval survived a new push (approve a harmless change, push another, merge) →
  `dismiss_stale_reviews` + `require_last_push_approval`, both read back; and the docs promised an approval only for
  CODEOWNERS paths while GitHub applies the count to every PR → the output and docs say so.
  A second local review found three more: with plain job names that ran on the branch (the normal case) the script
  ended with exit 1 after applying everything (a `[ … ] &&` as its last command) → explicit `exit 0`; a last commit
  that skipped CI made it fall back to plain `ci` without a word → a kit job missing from the check runs is named;
  a failing `gh` call looked like "nothing ran yet" and had no deadline → 30 s deadline, the failure is said.
- 2026-11-12 (1.6.0): first real run of `slickrails protect` (on the kit repo) printed "no check named size" for a
  healthy setup: `size` only runs on pull requests, so a branch's own commits never carry it → not expected there.

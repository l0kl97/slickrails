# Contract for tools that read slickrails

**Status:** active · **As of:** 2026-11-27 · **Built by:** Atlas with Claude Code (Linear SLI-193)

## The ask (plain language)
"slickfab relies on parts of slickrails without slickrails knowing about it. Name those parts as a contract and
protect them with tests, so that a change to slickrails does not silently break the slickfab dispatcher (post-merge
check, worktrees, roles)." Acceptance: an English docs section on what is stable and does not change without a major
version; a test that `config.sh` stays sourceable with `sh` without output or side effects and that
`CHECK_TYPECHECK`, `CHECK_TEST`, `CHECK_LINT_STAGED` exist in every template; the keys from SLI-175 in the contract
plus a note to slickfab about the same PATH setup; the CHANGELOG names contract changes explicitly.

## Decisions
- The contract lives in `docs/guides/for-tools.md`, not in the README: it is for tool authors and maintainers.
  CONTRIBUTING points to it so a change to the stable parts is not made by accident.
- "Every template" = the `config.sh` the installer writes for each stack (generic, npm, pnpm, yarn, bun, python,
  swift, go, rust, ruby, jvm). There is no static template file; the heredoc in `install.sh` is the template, so the
  test runs the installer per stack instead of reading `install.sh`.
- The test also checks that `CHECK_*` lines are literal (no `$`, no backticks), because slickfab reads `config.sh` as
  text, not by sourcing it. A value that only expands when sourced would reach slickfab unexpanded.
- The check function is tested against broken configs too (prints, writes a file, syntax error, missing key, key only
  in a comment, expanding value), so the per-stack loop cannot pass by accident.
- The doc advises naming keys instead of reading "every non-empty `CHECK_*`": `CHECK_PREPUSH_REVIEW="1"` is a switch,
  not a command.
- `SLICKRAILS_EXTRA_PATH` and `.slickrails/env.sh` (SLI-175) are listed as "coming", not tested: SLI-175 is not merged.
- Contract changes go into the CHANGELOG under their own heading "Contract".

## Where it lives
- `docs/guides/for-tools.md`: the contract.
- `tests/run.sh`, section "contract for tools that read slickrails": `config_contract` and the per-stack loop.
- `CONTRIBUTING.md`: the pointer for maintainers.
- `install.sh` (the `config.sh` heredoc): what the test protects. Not changed.

## How to test it
1. `sh tests/run.sh`, look for the lines starting with `contract:` and `contract check:`.
2. By hand: in `install.sh`, drop the `CHECK_LINT_STAGED=""` line from the heredoc (or add an `echo`), run the suite:
   every `contract:` line turns red.

## Limits & open items
- The guarantees describe what the installer writes. A team may edit `config.sh`; readers must cope with that.
- slickfab still has to build the same PATH as the hooks once SLI-175 ships: SLI-212 in the slickfab project. It also
  covers a small difference: slickfab-worktree turns the hooks on as soon as `.githooks/` exists, slickrails only
  when `.githooks/pre-commit` exists.

## History
- 2026-11-27: created (SLI-193)
- 2026-11-27: review follow-up. The guardrail paths in `for-tools.md` said all of `.slickrails/` is guarded; the Bash
  guard protects only the `*.sh` files in it and the folder as a whole. Text corrected, slickfab issue named.

# For tools that read slickrails

Some tools work inside repos that use slickrails and rely on parts of it: they run the same checks as the hooks,
switch the hooks on in new worktrees, or add review learnings. slickfab (the dispatcher, its worktree script and its
roles) is the first of them. This page names what such a tool can rely on.

**The promise:** everything listed under "Stable" changes only with a new major version of slickrails, and every
change to it is named in the CHANGELOG under the heading "Contract". New optional keys or files can come in a minor
version; they are added here when they become part of the contract. Anything not listed here (other keys in
`config.sh`, the hooks' output, file names under `.slickrails/` not named below) can change in any release.

`tests/run.sh` (section "contract for tools that read slickrails") checks the `config.sh` part for every stack the
installer knows.

## Stable

### `.slickrails/config.sh`

- **Where:** `.slickrails/config.sh` in the repo root. The installer writes it once and never overwrites it; the team
  may edit it.
- **How the hooks read it:** sourced with POSIX `sh` (`. .slickrails/config.sh`). Sourcing it prints nothing and creates
  no files: it only sets variables.
- **Format, as the installer writes it:** one `KEY="value"` assignment per line. `CHECK_*` values are literal: no
  `$`, no backticks. A tool may read the file as text instead of running it (slickfab does, so that a config cannot
  inject code), for example line by line with `^\s*KEY=(.*)$` and shell-style unquoting.
- **Keys that are always there:**

  | Key | Meaning |
  |---|---|
  | `CHECK_TYPECHECK` | Typecheck or build command for the whole repo. Empty = none. |
  | `CHECK_TEST` | Test command for the whole repo. Empty = none. |
  | `CHECK_LINT_STAGED` | Lint command for the staged files, run by `pre-commit`. Empty = none. Not a whole-repo check. |

  All commands run in the repo root with `sh -c`. `CHECK_TYPECHECK` and `CHECK_TEST` are what `pre-push`, the Stop
  gate and CI run; a tool that wants "the project's checks" runs these two, in this order, and skips empty ones.
- **Name keys, don't match a prefix:** `config.sh` holds other `CHECK_*` keys that are not commands to run as checks
  (`CHECK_PREPUSH_REVIEW="1"` is an on/off switch, `CHECK_SESSION` overrides only the Stop gate). Reading "every
  non-empty `CHECK_*`" picks those up too.
- **Edited files:** since the team may edit `config.sh`, a reader must cope with a missing key, an empty file or a
  line it cannot parse, and say so instead of guessing. The guarantees above describe what the installer writes.

### `.githooks/` and `core.hooksPath`

- The git hooks live in `.githooks/` (`pre-commit`, `commit-msg`, `pre-push`, `post-merge`) and are active when
  `core.hooksPath` is `.githooks`.
- `core.hooksPath` is local git config and does not travel with a clone or into a new worktree. slickrails switches
  the hooks on when `.githooks/pre-commit` exists and `core.hooksPath` is empty (`git config core.hooksPath
  .githooks`), and never over a value someone else set (another hook manager). A tool that creates clones or
  worktrees should follow the same rule.

### `.slickrails/review-learnings.md`

- Every AI review reads this file verbatim. Adding a dated line under `## Learnings` (waive or tighten a finding
  type) is the supported way to change what reviews report. A tool may propose such lines; the file stays human
  owned.

### The guardrail paths

- `.githooks/`, `.slickrails/` (its `*.sh` files above all), `.claude/settings.json`, `.claude/settings.local.json`
  and `.codex/hooks.json` are the guardrails. The Bash guard blocks agents from changing or deleting them. A tool
  that decides what an agent may merge on its own can treat these paths as sensitive.

## Coming with SLI-175 (not released yet)

The hooks will build their own `PATH` from known places (pnpm, node, gitleaks), so that checks behave the same in a
GUI git client, a hook and a terminal. Two additions are planned for the contract once that ships:

- `SLICKRAILS_EXTRA_PATH`: extra directories put in front of `PATH` before the checks run.
- `.slickrails/env.sh`: a per-repo file the hooks source for the environment of the checks.

A tool that runs the checks outside the hooks (slickfab's worktree baseline and post-merge check) will need the same
`PATH` setup to get the same result. Until SLI-175 is released, neither is part of the contract and neither is
tested here.

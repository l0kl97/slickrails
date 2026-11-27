# Stack and package manager detection

**Status:** active · **As of:** 2026-11-27 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
From SLI-190 (related to the spec "Hooks ohne Fehlalarme", SLI-171): "`init` schreibt die Checks, die zum Repo
passen. Nutzen: keine Checks, die still nichts prüfen, und keine, die mit dem falschen Paketmanager rot werden."
(init writes the checks that fit the repo: none that silently check nothing, none that go red with the wrong
package manager.) Found in real repos: a Python repo with a `package.json` only for Prettier was detected as Node and
never got `pytest`; with several lockfiles the order in the code decided (bun beat everything), not the
`packageManager` field (`pnpm@10.32.1`); a Python repo without `tests/` got an empty `CHECK_TEST`, warned once at the
install, and was green from then on.

## Decisions
- **Python wins over a helper `package.json`**: when `pyproject.toml` or `requirements*.txt` exists and
  `package.json` has neither a `test` nor a `typecheck` script, the stack is Python. Rejected: writing both stacks'
  checks — a `package.json` without those scripts has nothing to check, and `config.sh` has one `CHECK_TEST`; the
  CI workflow is also one per stack. A `package.json` with a `test` or `typecheck` script stays Node.
- **`packageManager` first** (the Corepack field, `name@version`): npm, pnpm, yarn or bun is taken as is. Any other
  value is named in a warning and ignored; then the lockfiles decide in the old order (bun before yarn before pnpm,
  else npm), so existing installs choose the same as before.
- **Several lockfiles without `packageManager` warn**, naming the lockfiles and the choice, with the fix (set the
  field). `package-lock.json` counts as a lockfile for this warning.
- **Without node** the `package.json` scripts are read as text (`"test":`) instead of not at all: on a machine
  without node a yarn/bun project got no checks, and the Python decision needs the scripts too. Good enough for a
  first guess that lands in an editable `config.sh`.
- **`doctor`: an empty `CHECK_TEST` is a PROBLEM** (exit 1), also when `CHECK_TYPECHECK` or `CHECK_SESSION` is set —
  every hook passes while no test runs. A `config.sh` without any check is a PROBLEM too (was a WARN). The CI setup
  check (`templates/setup-check.sh`) is unchanged: it still accepts a typecheck alone.
- **`config.sh` is never overwritten** (as before): the new detection only applies to new installs; `doctor` is how
  existing repos learn about an empty `CHECK_TEST`.

## Where it lives
- `install.sh`, section "stack detection": `has_script`, the stack order, the Python exception, the package manager
  (`PM_FIELD`, `LOCKS`).
- `install.sh`, `doctor` → repo check: the `CHECK_TEST` lines.
- `tests/run.sh`: block "stack and package manager detection (SLI-190)" and "stack detection without node" (in the
  no-jq section, which builds a PATH without node).
- `docs/guides/stacks.md`: the user-facing rules.

## How to test it
1. `sh tests/run.sh` — the `stack:`, `pm:` and `doctor:` lines.
2. By hand: a repo with `pyproject.toml`, `tests/` and `{"devDependencies":{"prettier":"^3"}}` as `package.json`,
   then `slickrails init` → "Detected stack: python", `CHECK_TEST="python3 -m pytest -q"`.
3. A repo with `pnpm-lock.yaml`, `bun.lockb` and `"packageManager":"pnpm@10.32.1"` → `pnpm run --if-present test`;
   without the field → a warning naming both lockfiles and "using bun".
4. Set `CHECK_TEST=""` in `.slickrails/config.sh`, run `slickrails doctor` → `PROBLEM  CHECK_TEST … checks nothing`,
   exit 1.

## Limits & open items
- `ci-node.yml` still picks the package manager by lockfile, pnpm first, and ignores `packageManager`. With several
  lockfiles local checks and CI can disagree; the installer's warning says to set the field, removing the stale
  lockfile settles both.
- The `packageManager` value is read with `sed` from the line it is on; a field split across lines is not found
  (then the lockfiles decide).
- A Python repo without `tests/` still gets an empty `CHECK_TEST` at install (pytest would fail with "no tests
  ran"); the installer warns and `doctor` now keeps reporting it.

## History
- 2026-11-27: created (SLI-190): Python with a helper `package.json`, `packageManager` first, lockfile warning,
  `has_script` without node, `doctor` reports an empty `CHECK_TEST` as a problem.

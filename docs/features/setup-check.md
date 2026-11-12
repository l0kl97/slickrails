# Setup check in CI + CODEOWNERS template

**Status:** active · **As of:** 2026-11-11 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
From an outside review of 1.4.0, written from the view of a company where people without an engineering
background ship code through agents: "A broken setup is silent" (hooks missing, a `config.sh` that checks
nothing, so every hook passes) and "the AI review judges, but nobody can check the verdict" — for auth,
payments, migrations, infrastructure and permissions a named engineer should approve, whatever the AI said.
The maintainer: "setz bitte alles um" (implement all of it).

## Decisions
- **The check runs as a step of the `ci` job**, not as its own job: `ci` is already a required check after
  `slickrails protect`, so a missing setup blocks the merge without anyone editing the protection. Rejected: a
  separate job (one more required check name to keep in sync), running `slickrails doctor` in CI (needs the kit
  on the runner, i.e. fetching code from the internet in every build).
- **`config.sh` is read as text, never run** (same as doctor): a check counts when a `CHECK_TYPECHECK`,
  `CHECK_TEST` or `CHECK_SESSION` line has a non-empty value; a value only in a comment does not count.
- **Agent hooks:** at least one of `.claude/settings.json` / `.codex/hooks.json` must reference both the Stop gate
  and the Bash guard (`--agent claude` or `codex` installs only one).
- **Way out:** repository variable `SLICKRAILS_SETUP_CHECK=warn` (report only) or `off`; unknown values check with
  `block`. Every guardrail keeps a loud, deliberate escape hatch (CONTRIBUTING).
- **What CI cannot see** is whether a clone has the hooks switched on (`core.hooksPath` is local config, never
  cloned). That stays with `slickrails doctor`; the script says so in its header.
- **CODEOWNERS is placed fully commented out**: the kit cannot know a repo's paths or people, and a live file with
  placeholder owners would make GitHub show errors. It is enforced only with `CODEOWNER_REVIEWS=1 slickrails
  protect`. An existing `CODEOWNERS` in any place GitHub reads (`.github/`, root, `docs/`) is left alone.

## Where it lives
- `templates/setup-check.sh` → `.slickrails/setup-check.sh` in the project (write-protected by the Bash guard like
  every `.slickrails/*.sh`)
- `templates/workflows/ci-*.yml`: step "slickrails setup" right after checkout
- `templates/codeowners` → `.github/CODEOWNERS`
- `install.sh`: places both; `tests/run.sh`: "setup check" and CODEOWNERS tests

## How to test it
1. `sh tests/run.sh` (setup check: fresh install with a detectable check passes, without one the installer warns and
   the check fails; empty config, a commented-out check, a missing hook, no
   agent hooks fail; warn/off/unknown modes; CODEOWNERS placed commented, an existing one untouched)
2. In a project: `sh .slickrails/setup-check.sh`, then empty `CHECK_TEST` in `.slickrails/config.sh` and run it again

- **A stack without a detectable check** (Python without `tests/`, Ruby without `spec/`/`test/`, an Xcode project, a
  yarn/bun project without a test script) gets an empty `config.sh`. The installer says so right away and names the
  CI consequence, doctor says the same; CI fails until a check is named or the variable is set. Rejected: leaving the
  step out of `ci.yml` in that case (the gap would be silent again, the point of the check), and treating it as a
  warning only (that is what the outside review asked to change).

## Limits & open items
- The check proves the files are there, not that the hooks run on anyone's machine.
- Existing installs get the step only for a newly placed `ci.yml`; a `ci.yml` that differs gets
  `ci.yml.slickrails-new` next to it (the installer never overwrites).

## History
- 2026-11-11: created (1.5.0). The local review (claude) found before the first push that a fresh install for a stack
  without a detectable check would fail CI with no warning at install time → the installer and doctor say it.
- 2026-11-12 (1.6.0): the CI templates ran their own test commands (package scripts, `pytest`, `go test`, …) while
  the hooks ran `.slickrails/config.sh`: a check changed in one place was green locally and different in CI → every
  stack's `ci` job now runs the `config.sh` checks after installing dependencies; lint, format and build steps stay.
  The templates had also fallen behind the kit's own workflows (`actions/checkout@v4` against `v7`; Dependabot only
  sees `.github/`) → all actions bumped to their current major, and a test fails when a template uses another
  version than the kit's own workflows. The audit covered npm and pip only → pnpm, Go, Rust and Ruby added
  (yarn, bun, JVM: none, said in the template). An empty `CHECK_TEST` fails the step instead of passing silently (an empty `CHECK_TYPECHECK` is skipped with a
  line in the log). Not covered: npm's and pnpm's generated `… --if-present` commands still pass when `package.json`
  has no test script, as the old template's skip did. Every bumped major tag was confirmed to exist
  (`gh api repos/<action>/git/ref/tags/<major>`, 2026-11-12). Not run by the kit's CI: the bumped setup actions and the new audit
  steps (the kit has no such project); the first project on each stack is their test.

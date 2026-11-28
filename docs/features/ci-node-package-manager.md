# Node CI: package manager like init

**Status:** active · **As of:** 2026-11-27 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
From SLI-211: "Die CI-Vorlage wählt denselben Paketmanager wie `init` (gleiche Regel, möglichst aus einer Quelle)."
(The CI template picks the same package manager as `init`: the same rule, from one source where possible.) Found
after SLI-190 (see `stack-detection.md`): `init` reads the `packageManager` field of `package.json` before the
lockfiles, while `templates/workflows/ci-node.yml` went by lockfile only, pnpm first. A repo with `pnpm-lock.yaml`,
`bun.lockb` and `"packageManager": "bun@…"` got bun in the local hooks and pnpm in CI — against the 1.6.0 promise
"one source for local and CI".

## Decisions
- **The rule:** `packageManager` decides when its name (the part before `@`) is npm, pnpm, yarn or bun. Any other
  value (`deno@2`, `PNPM@10`, empty) is ignored and named in the step log; then the lockfiles decide in init's order
  — bun (`bun.lockb`/`bun.lock`) before yarn before pnpm — else npm.
- **The lockfile order changes too** (was pnpm before yarn before bun): only init's order gives the same choice for
  a repo with several lockfiles and no field. A repo that relied on CI picking pnpm next to a `bun.lockb` now gets
  bun in CI, as it already did locally.
- **A copy of the rule in the template, not a call into the installer:** the CI run has only the user's repo, not
  `install.sh`. Rejected: a shared script installed into `.slickrails/` — a new kit file in every repo for six lines,
  and the installer changes in open PRs (#15, #16, #18). The "one source" is kept by a test instead: the template's
  step and `init` run on the same fixtures and must agree.
- **Same parsing as init:** the field is read with the same `sed` expression from `package.json`, so both copies
  have the same limits (see below). No `node` call: the step stays independent of what the runner has.

## Where it lives
- `templates/workflows/ci-node.yml`, step "Detect package manager": the rule; writes `pm=<name>` to `$GITHUB_OUTPUT`,
  which setup-bun, the cache key, Install, Lint and Build read.
- `tests/run.sh`, block "Node CI template: the package manager is chosen like init (SLI-211)": the step is cut out of
  the template and run on fixtures (expected values from the rule above), then compared with `install.sh` on the
  same fixtures.
- `docs/guides/stacks.md`: the user-facing rule.

## How to test it
1. `sh tests/run.sh` — the `ci-node.yml: packageManager first …` and `ci-node.yml: picks the same package manager
   as init …` lines.
2. The comparison with init always runs since SLI-190 (PR #16) is on main; a difference is a failed test, never a
   skip.
3. By hand in a repo with the template: `pnpm-lock.yaml`, `bun.lockb` and `"packageManager": "bun@1.2.0"` → the
   step log says `Package manager: bun (packageManager in package.json)`.

## Limits & open items
- Two copies of the rule (install.sh, ci-node.yml): kept equal by the test, not by construction.
- Like init: a `packageManager` value split across lines is not found (then the lockfiles decide); the first line
  that mentions `"packageManager": "…"` counts.
- The CI step does not warn about several lockfiles without the field (init does); it names its choice in the log.

## History
- 2026-11-27: created (SLI-211). Symptom: pnpm in CI, bun locally, for a repo with both lockfiles and
  `packageManager: bun@…`. Cause: the template's own lockfile-only rule (pnpm first). Fix: the template applies
  init's rule; a repro test over fixtures and a comparison test with `install.sh`.

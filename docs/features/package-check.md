# Package check before an agent installs a dependency

**Status:** active · **As of:** 2026-10-29 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
From the Code Guardian comparison (see `guard-destructive-and-guardrails.md`): Code Guardian advertises a reputation
check before a new dependency, but its public docs only show `npm audit`. AI agents install packages by name, and a
name the model made up is how slopsquatting gets in: someone registers the made-up name and waits. Dependabot and
`npm audit` only look after the fact. The maintainer: build it, without code bloat, efficient and safe.

## Decisions
- **Part of the Bash guard, not a new hook.** `bash-guard.sh` calls `dep-check.sh` only when a simple command starts
  with a package manager; no new hook entry, no new merge path in the installer, the same human way out.
- **One signal blocks:** the package was first published less than 30 days ago (`SLICKRAILS_DEP_MIN_DAYS`) and, on
  npm, had fewer than 1000 downloads last week (one small request settles most installs; the full registry document
  of a popular package is megabytes). That is the attack: a made-up name someone has registered since.
- **"Not on the registry" only points it out** (changed 2026-10-29, first version blocked it): the install fails by
  itself, so blocking protects nothing, while workspace packages of a monorepo and packages from private registries
  (`.npmrc`, `.yarnrc.yml`, `pyproject.toml` sources, …) are not on the public registry either and were blocked by
  mistake. Reading every tool's registry config to tell them apart would be code that never ends.
- No name-similarity list against popular packages: it needs a data file that ages, and a typosquat is almost always
  young and unused, which the age signal catches.
- **Fail open** when curl is missing or a registry does not answer (3 s per request, 7 s for all): no network is no
  reason to stop work; the note on stderr says which names were not checked. A crash of `dep-check.sh` does not block.
- **Scope:** names on the command line of `npm/pnpm/bun install|i|add`, `yarn add`, `pip install`,
  `python -m pip install`, `uv add`, `uv pip install`, `poetry add`. Not: lockfile installs, `-r`/`-c` files, local paths,
  URLs, git sources. A new version of an existing package is not "young".
- **Way out:** the human installs it themselves, or starts the agent with `SLICKRAILS_ALLOW_NEW_DEPS=1`.

## Where it lives
- `templates/dep-check.sh` (→ `.slickrails/dep-check.sh`) — parsing, registry lookups, verdict.
- `templates/bash-guard.sh` — the call at the end.
- `tests/run.sh` section "package check" — a curl stub with fixtures, no network.

## How to test it
1. `sh tests/run.sh` — `package check: …`.
2. Against the real registries:
   `printf 'npm install some-made-up-name-xyz\n' | sh .slickrails/dep-check.sh; echo $?` → 2, `npm install lodash` → 0.
   Last run 2026-10-29: lodash, @types/node, left-pad, requests, numpy, flask passed (checked, not skipped);
   made-up names on npm and PyPI were blocked.

## Limits & open items
- npm and PyPI only; cargo, go, gem, composer are not checked.
- `npx <pkg>` and `pipx install` are not checked; neither are packages pulled in by a lockfile change in a PR (a CI
  check on new lockfile entries is the obvious next step).
- PyPI has no download numbers in its API, so an old but abandoned package passes.
- Tested against the real registries once by hand; the suite uses fixtures shaped like the real answers.

## History
- 2026-10-29: created
- 2026-10-29: symptom (found by the real claude review): `pip install "made-up>=1"` and `npm install "made-up@<2"` were never checked → cause: tokens with < or > were skipped as redirects before the version was cut off → fix: only a token starting with < or > is a redirect; the specifier test now checks the lookups, not just the exit code.
- 2026-10-29: symptom (full real claude review): an internal package (`@acme/internal-lib` with `@acme:registry` in .npmrc, `pip install --index-url …`) was blocked as "does not exist" → cause: every name was looked up on the public registry → fix: no lookup for another registry on the command line, a scope mapped in .npmrc, or a non-public default registry (npm and pip/uv config).
- 2026-10-29: symptom (full real claude review): workspace packages (`npm install @acme/utils -w apps/web`) and packages from a project index (`[[tool.uv.index]]`, `.yarnrc.yml`) were blocked as "does not exist" → cause: a public-registry 404 was treated as a threat, though the install fails by itself → fix: only a young, little-used package blocks; a missing name is pointed out (see Decisions).
- 2026-10-29: symptom (real claude review): a registry answer without a first-publish date (PyPI without `releases`, npm without `time.created`) blocked the package as "0 days old" → cause: a missing date fell back to today → fix: no date → not checked, with a note.
- 2026-11-02: symptom (real claude review): a package published today passed with a decoy `"created":"2015-…"` in its package.json, and `npm install -f <pkg>` / `pnpm add -w <pkg>` skipped the check → cause: the first "created" anywhere in the packument was taken, and -f/-w counted as value options for every ecosystem → fix: the registry's own field (jq/node, else the last top-level "time" object); value options per ecosystem.

# Examples to try (examples/)

**Status:** active · **As of:** 2026-11-28 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
From a trial run of 1.6.0 with only the README as a guide: there is no example repository and no filled-in feature
dossier to look at. The issue: "Whoever wants to look at slickrails before pulling it into their own repo can try it
on a small example and sees what a good feature dossier looks like." Wanted: `examples/node-pnpm/` and
`examples/python/`, each a tiny project with a test, set up with the current kit (installed files visible), a filled-in
dossier, an `examples/README.md` that replays it in three steps (copy, `git init`, a secret commit and a red push), a
test in the kit so the examples do not fall behind silently, and nothing of it in the sparse checkout of
`bootstrap.sh`. The maintainer added: the installed files come from a script that runs `install.sh` in a throwaway
repository, so they can be rebuilt with one command after later merges; no `slickrails demo` command for now.

## Decisions
- **Generated, not hand-copied.** `scripts/build-examples.sh` copies each example's own files into a throwaway repo,
  runs `install.sh --review off` there and puts the result back. Everything the installer writes is removed before
  (`.slickrails/`, `.githooks/`, `.github/`, `.claude/`, `.codex/`, `CLAUDE.md`, `AGENTS.md`, the two files in
  `docs/features/`), and the block it appends to `.gitignore` is cut off, so a rebuild never mixes old and new.
- **The test rebuilds and compares** instead of checking hashes in the manifest: it also sees a template the
  installer started or stopped placing, and the files outside the manifest (`config.sh`, `STATUS.md`, the rules
  block). The date in `STATUS.md` is the build day and is compared as a placeholder. Two installs cost about two
  seconds. The manifest's first line must name the current `VERSION` as well.
- **`--review off`** for the build: otherwise `config.sh` would depend on whether the builder has the claude or codex
  CLI installed.
- **Two different small features** (a URL slug, a duration parser) instead of one in two languages: each dossier
  shows decisions with rejected alternatives and a bugfix in the history (symptom → cause → fix), the part readers
  should copy.
- **The README walk-through is a test too**, on a copy of the Python example: first commit, blocked secret
  (the fake key is assembled with `printf`, so neither the kit nor the walk-through contains one), blocked push with
  a red test, push after the fix. Skipped where pytest is missing; the Node example would need pnpm.
- Rejected for now: a `slickrails demo` command that sets up a throwaway repo and plays the flow (maintainer's call).

## Where it lives
- `examples/node-pnpm/`, `examples/python/`: the examples (own files: code, tests, `docs/features/<slug>.md`,
  `.gitignore` lines; the rest is generated)
- `examples/README.md`: what is in them, the three steps, the rebuild for maintainers
- `scripts/build-examples.sh`: the build (`[out-dir]`, default `examples/`)
- `bootstrap.sh`: `!/examples/` in the sparse-checkout file
- `tests/run.sh`: section "examples/" (rebuild and compare, tampered copies are caught, manifest version, dossiers
  filled in, README walk-through) and the bootstrap test (no `examples/` in the clone)

## How to test it
1. `sh tests/run.sh` (the examples section, plus "bootstrap: the clone leaves the examples (examples/) out").
2. By hand: follow `examples/README.md` in a temporary folder.
3. After a template change: `sh tests/run.sh` is red on the examples until `sh scripts/build-examples.sh` ran.

## Limits & open items
- An install cloned before this change has no `!/examples/` in its sparse file; `slickrails upgrade` (git pull)
  checks the examples out there (a few hundred KB of text). New installs leave them out.
- The examples' own CI workflows never run (GitHub runs only the root `.github/`).
- Without pnpm the Node example's checks cannot run; the walk-through test uses the Python example only.

## History
- 2026-11-28: created (SLI-187).

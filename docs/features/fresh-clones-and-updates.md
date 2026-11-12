# Fresh clones get the hooks, installed repos get updates

**Status:** active · **As of:** 2026-11-12 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
After 1.5.0 the maintainer asked for a full scan: "what can we improve, where are use-case gaps, how do we make
slickrails more effective", then "implement all of it … no bloated code, nothing outdated". Two of the gaps:
a fresh clone has no active git hooks until someone runs `git config core.hooksPath .githooks` (the outside review's
main point, and the normal case for cloud agents, which always start from a fresh clone), and a repo that installed
slickrails once never got a newer hook: `slickrails upgrade` only updated the kit, and re-running `init` put a
`*.slickrails-new` next to every file that had changed.

## Decisions
- **The Bash guard switches the hooks on.** It already runs before an agent's first tool call, for Claude Code and
  Codex alike, so no new hook event and no new file. Only when `core.hooksPath` is not set at all: another hook
  manager's path is never touched (the installer's own rule). Rejected: a SessionStart hook (unverified for Codex),
  doing it in the Stop gate (too late: the session's commits would have gone out without pre-commit).
- **Only in the guard's own repository.** The guard is called by its absolute path from any working directory; a
  third-party repo the agent cloned and entered may ship a `.githooks/` folder, and git never activates cloned hooks
  for good reason. The repository of the current directory must be the one the guard file lives in.
- **`slickrails doctor` probes the guard from outside the repo**, so a check does not change what it checks.
- **No `prepare` script for Node projects** (built, then taken out before the first push): the local review showed
  it would run in every place `npm ci` runs, including the disposable worktree of the local gate, where it would
  have pointed the gate repository's hooks at a folder that does not exist (pushes accepted unchecked), and it would
  have overridden a teammate's global hooks path. Guarding all of that inside a one-line `package.json` command is
  not worth it; humans keep the one `git config` line that doctor names.
- **`.slickrails/manifest` records what was placed** (`git hash-object` of the kit's file, the path and the template
  it came from, the kit version in the first line). On the next `init`, a file that still has the recorded hash and
  comes from the same template was never edited and is replaced (another template, e.g. a rerun without `--lang de`
  or a changed stack, is not an update); an edited one gets `*.slickrails-new` as before. Rejected: a list of every old version's hashes in the
  kit (grows forever), overwriting with a `--force` flag (loses edits).
- Files that belong to the user are not in the manifest: `config.sh`, `rules.md`, `STATUS.md`, the merged agent
  settings, the rules block in `CLAUDE.md`/`AGENTS.md`.

## Where it lives
- `templates/bash-guard.sh` (top): activation
- `install.sh`: `place()` and the manifest, doctor's guard probe
- `scripts/status.sh`: a "Kit" row when the installed version differs from the kit's
- `tests/run.sh`: manifest, update in place, edited file kept, another template is no update, guard
  activation (own repository only), another hook manager left alone, doctor changes nothing

## How to test it
1. `sh tests/run.sh`
2. In a project: `git config --unset core.hooksPath`, start an agent session, run any command → the guard says the
   hooks were switched on. Update: `slickrails upgrade && slickrails init`.

## Limits & open items
- An install from before the manifest gets `*.slickrails-new` files once more; after adopting them, updates are
  automatic.
- Humans still run `git config core.hooksPath .githooks` once per clone (doctor says so).
- Agents other than Claude Code and Codex do not run the guard, so nothing switches the hooks on for them.

## History
- 2026-11-12: created (1.6.0). The local review found two holes before the first push: the guard would have switched
  on the hooks of any repo the agent stood in, and a rerun in another language would have replaced the unedited
  files of the first one → own repository only; the manifest records the template.

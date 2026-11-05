# slickrails status — one screen on where a repo stands

**Status:** active · **As of:** 2026-10-29 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
While reworking the install, the maintainer asked for "some kind of overview/interface". Choice made with them: a terminal
command, `slickrails status`, that fits "no daemon, no cloud" (not an HTML report, not a multi-repo dashboard yet).

## Decisions
- **Status sums up, doctor checks.** The health line is doctor's own verdict, counted (ok / problems / warnings), and
  each problem is named. No second copy of the checks that could drift from doctor's.
- **Offline by default.** Health, checks, reviewer, open rules (the table in `.slickrails/STATUS.md`, or the old
  `SLICKRAILS-STATUS.md`), dossiers. GitHub only with `--github`: the last CI run of the branch and branch protection on
  main, each `gh` call bounded to 15 s, an answer that does not come is said, not guessed.
- **Read-only, exit 0 when shown** (even with problems): `slickrails doctor` is the command that fails; status is for
  looking. Exit 1 only when the repo has no slickrails.
- `config.sh` is read as text, never sourced.

## Where it lives
- `scripts/status.sh` — the command (in the kit, not copied into repos).
- `bin/slickrails` — `status`.
- `tests/run.sh` — "status: …".

## How to test it
1. `sh tests/run.sh` — `status: …`.
2. In an installed repo: `slickrails status`, `slickrails status --github` (needs `gh auth login`).

## Limits & open items
- One repo at a time; a view across several repos (ROADMAP: coverage dashboard) is open.
- The rules count reads the status table as written by people; a row edited out of shape is not counted.

## History
- 2026-10-29: created

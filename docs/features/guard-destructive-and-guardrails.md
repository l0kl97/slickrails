# Bash guard: destructive commands and write-protected guardrails

**Status:** active · **As of:** 2026-10-29 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
The maintainer looked at Code Guardian (Provimedia, a paid skill package for Claude Code/Codex) and asked whether buying it
would help improve slickrails. The answer was no: its public technical docs show the architecture, the detection
rules are not public and could not be copied anyway. Two ideas from those docs were taken over, built from scratch:
"hard blocks for deletion, deploy and migration" and "write protection for the gate scripts and the settings that
hold permissions". The maintainer: "setzt das bitte um … keinen Code Bloat … effizienz und sicherheit".

## Decisions
- **One script, not two.** `bash-guard.sh` looks at `tool_name`: Bash calls are checked for bypasses, writes to
  guardrail files and destructive commands; edit tools only for their `file_path`. A second hook script would mean a
  second install/merge/doctor path for the same idea.
- **Block, not ask.** Claude Code could answer `permissionDecision: "ask"`, Codex cannot be relied on to; exit 2 works
  for both. The human's way out: run the command themselves (`! <command>` in Claude Code, which is not hooked) or
  start the session with `SLICKRAILS_ALLOW_DESTRUCTIVE=1`. Guardrail writes use the existing `SLICKRAILS_ALLOW_BYPASS=1`
  (they are a bypass).
- **What counts as destructive** is limited to things that lose work or data with no easy undo: `git reset --hard`,
  `git clean -f`, `git push --force` (`--force-with-lease` stays allowed, except onto main/master), `git checkout/restore`
  of everything (`--staged` only unstages and passes), `rm -r` on `/ ~ $HOME . .. * .git`, framework database resets,
  `DROP`/`TRUNCATE` through a database client. `rm -rf node_modules`, `git branch -D` (reflog) and ordinary migrations
  pass: a guard that blocks daily work gets switched off.
- **Which files are guardrails:** `.slickrails/*.sh` (incl. `config.sh`, which decides what the checks run),
  `.githooks/`, `.claude/settings(.local).json`, `.codex/hooks.json`. Not `rules.md` and `review-learnings.md`: they
  are meant to be edited, by agents too. Not `.github/workflows/`: changing CI is normal work and is visible in review.
- **Quoted text:** bypass and git checks keep ignoring quoted text (commit messages). Paths and SQL often sit in quotes,
  so the guardrail/rm/SQL checks run on a second scan that keeps quotes, split into simple commands; a write only counts
  when the command word itself writes (`rm`, `cp`, `tee`, `sed -i`, …) or a `>` points at the file.
- **Existing installs:** the installer widens an existing guard entry with matcher `Bash` to the template's matcher and
  writes only when such an entry exists (no reformatting of untouched files). Codex's template stays `Bash`.

## Where it lives
- `templates/bash-guard.sh` (copied to `.slickrails/bash-guard.sh`) — the checks.
- `templates/claude-settings.json` — matcher `Bash|Edit|Write|MultiEdit|NotebookEdit`.
- `install.sh` `widen_guard_matcher` — upgrade of a Bash-only entry.
- `tests/run.sh` section "the guard, round 2" — every pattern with a pass control next to it.

## How to test it
1. `sh tests/run.sh` — the guard cases (`bash-guard: …`) and `installer: an old Bash-only guard is widened …`.
2. By hand: `printf '{"tool_name":"Bash","tool_input":{"command":"git reset --hard"}}' | sh .slickrails/bash-guard.sh; echo $?` → 2.

## Limits & open items
- Pattern-based: a destructive command inside a script, an alias or a variable is not seen; neither is a write through
  an interpreter (`python -c`, `node -e`). CI and branch protection stay the boundary.
- Codex's `apply_patch` edits are not hooked; the widened Claude matcher is tested against JSON fixtures, not yet in a
  real Claude Code session.
- Without jq and node the raw JSON is matched: edit-tool paths are still caught, quoted-text handling is coarser.

## History
- 2026-10-29: created
- 2026-10-29: symptom (found by the real claude review of the PR stack): `git push origin feat` with `rm -f tmp.txt` on the next line was blocked as a forced push, `git checkout feat` + `ls .` as discarding every change → cause: the scanner joined all lines into one, so `[^|;&]*` ran from one command into the next → fix: one output line per command line (a trailing `\` or an open quote continues); tests for both, and that `--no-verify`/`--force` after a line continuation are still blocked.
- 2026-10-29: symptom (full real claude review of the stack): `psql -c "BEGIN; DROP TABLE users"` passed → cause: commands were split on `;` inside quotes too, so the DROP landed in a piece without psql → fix: the scanner ends a simple command only at a separator outside quotes.
- 2026-10-29: symptom (full real claude review): `rm -rf .slickrails`, `mv .slickrails /tmp/x`, `rm -rf .claude` passed → cause: the write protection matched single files only → fix: the folders count as a whole (at the start of a word); adding a file elsewhere under `.claude/` still passes.
- 2026-10-29: symptom (full real claude review): a commit message with `> .slickrails/config.sh` inside quotes was blocked, and a real redirect onto a quoted path with a space was missed → cause: the redirect check ran on the scan that keeps quoted text, and a target ended at the first space → fix: a redir scan prints only targets of > outside quotes, quoted targets whole.
- 2026-10-29: symptom (full real claude review): `git restore --staged --worktree .` passed, `git restore -S .` was blocked → cause: the unstage exemption looked for the word --staged only → fix: --staged/-S without --worktree/-W unstages, anything else on `.` discards.
- 2026-10-29: symptom (real claude review): `git restore --staged a; git restore .` and `rm -rf .slickrails/*` passed → cause: the unstage exemption looked at the whole line, and a glob matched neither the folder nor the file form → fix: discarding is judged per simple command; a glob in a guardrail folder counts as the folder unless it ends in a foreign extension.
- 2026-11-02: symptom (real claude review): `rm -rf "$HOME"/` and `rm -rf "$HOME"/*` passed → cause: the target pattern allowed quotes only around the whole target → fix: the rm command is matched with its quotes taken out.

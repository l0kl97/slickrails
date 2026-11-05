# Local AI review with the user's own claude or codex

**Status:** active · **As of:** 2026-10-29 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
The PR review on GitHub failed: it needs the Claude GitHub App and a secret (API key or subscription token). The maintainer:
"Can't we use the local Claude/Codex, so it works without an API? Then of course before it goes to Git." And:
"depending on what the user uses — we should consider that in the setup."

## Decisions
- **Before the push, not before every commit.** A review takes one to two minutes; on every commit that is friction
  people switch off. The push is the moment the code leaves the machine. (The existing pre-push hook already runs it.)
- **`REVIEW_CLI` = auto | claude | codex**, in `config.sh` or the environment (one-off). `auto` takes claude, else
  codex. Codex is looked up on PATH and in the ChatGPT app bundle on macOS (`SLICKRAILS_CODEX_APP` overrides the path).
- **Codex runs `codex exec --sandbox read-only --ephemeral`**: a reviewer must not write, and a review session is not
  worth keeping. The whole prompt goes through stdin (`-`), the last message lands in a file (`-o`), the verdict comes
  through the same JSON schema as claude's (closed with `additionalProperties: false`, which OpenAI's structured output
  wants). Same deadline, and the same rule: anything but a clean PASS/FAIL is an ERROR, never a pass.
- **Setup follows what is installed.** When the installer writes `config.sh` it looks for claude/codex and turns the
  review on with the one it finds (`--agent codex` prefers codex when both are there); with neither it stays off and
  says so. `--review auto|claude|codex|off` or `SLICKRAILS_REVIEW` override it (the test suite sets `off`, so its many
  test repos never call a real CLI). `config.sh` is never overwritten, so `doctor` points out an off review in an
  older install when a reviewer CLI is on the machine.
- The GitHub PR review stays as it is (App + secret); the local review is the no-API path, not a replacement for
  server-side checks.

## Where it lives
- `templates/ai-review.sh` (→ `.slickrails/ai-review.sh`) — CLI choice, codex call, verdict.
- `install.sh` — detection when writing `config.sh`, `--review`, the doctor hint.
- `tests/run.sh` — "ai-review (codex): …", "installer: a local claude turns the pre-push review on …".

## How to test it
1. `sh tests/run.sh` — stub CLIs, no network.
2. Real CLIs: a repo with a branch that adds `exec("ls " + userInput)`, then `REVIEW_CLI=codex sh .slickrails/ai-review.sh`
   and `REVIEW_CLI=claude …` → both `FAIL` with the injection at `m.js:3`, exit 1 (last run 2026-10-29, macOS,
   Codex CLI 0.163.0-alpha.11.1).

## Limits & open items
- Codex on Linux/Windows and outside the ChatGPT app bundle is untested.
- A subscription login has usage limits; a long series of pushes eats into them.

## History
- 2026-10-29: created. The first real claude review found a bug in `ai-review.sh` itself: a diff git cannot build (no
  merge base, a shallow clone) counted as empty and the push passed silently → now an ERROR under `REVIEW_ON_ERROR`
  (test "no merge base with the base branch is an ERROR, not a silent pass", red first).
- 2026-10-29: symptom: the first real review of a PR-sized diff ended as ERROR "reviewer process failed (exit 1)" with no reason → cause: claude needed 4 turns for the structured answer, `--max-turns` was 3, and it reports `error_max_turns` on stdout → fix: `--max-turns 8`, the subtype goes into the ERROR line (tests red first).
- 2026-10-30: the local review is the default review: the installer no longer adds `claude-review.yml` (opt-in: `--github-review`, or later `slickrails github-review`), rule 6 reads "AI review before merge" and is ☑ when the local review runs. Asked by the maintainer: "the local review is the standard, and whoever wants can set it up on GitHub to run server-side".
- 2026-11-02: symptom: a real local review left a new file staged in the repo (it "reproduced" a finding by writing and `git add`-ing it; another finding said it had run `git restore .`) → cause: `claude -p` ran with every tool; only codex had a read-only sandbox → fix: claude reviews with `--tools Read,Grep,Glob` (test red first; a real run still blocks a seeded injection).

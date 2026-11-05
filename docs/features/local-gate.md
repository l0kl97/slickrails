# Local gate: check the pushed commit before it leaves the machine

**Status:** active (opt-in) · **As of:** 2026-10-21 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
The maintainer: "Und den Kern aus diesem Repo sollten wir noch mit reinnehmen. https://github.com/kunchenguid/no-mistakes".
The README of that project describes its core idea as a local git proxy: you push to a *gate remote* instead of `origin`;
the gate validates the push in a disposable worktree (review, tests, lint, docs) and forwards it to the real remote only when
everything is green; your working tree is never touched. slickrails already quoted the idea in the header of `ai-review.sh`
("the no-mistakes idea without the daemon"), but its pre-push hook still ran on the working copy.

## Decisions
- **Taken (the core):** a local gate remote. `slickrails gate init` creates a bare repo inside `.git/` and a `gate` remote; its `pre-receive` hook checks out the PUSHED commit into a disposable worktree, runs the project's own checks there and forwards to the real remote only on green. A red push is rejected, so the real remote never sees it. The working copy (dirty, red, with junk) is irrelevant — this is the clean answer to "green before push describes the wrong state" that the pre-push guard only approximates.
- **Taken from the project's own config:** the checks are `.slickrails/config.sh` of the pushed commit: `CHECK_GATE_SETUP` (e.g. `npm ci`), `CHECK_TYPECHECK`, `CHECK_TEST`, and the AI review if `CHECK_PREPUSH_REVIEW=1` (same exit-code semantics as the local review: FAIL rejects, ERROR is reported and lets the push through unless `REVIEW_ON_ERROR=block`). `GATE_LINK_DIRS` (e.g. `node_modules`) links dependency directories from the source checkout so the disposable worktree does not reinstall them on every push; a deadline (`slickrails.timeout`, default 900 s) stops hanging checks.
- **No daemon, no TUI:** the hook does the work synchronously during `git push gate …`; its output appears as `remote:` lines.
- **Opt-in, additive:** `origin`, the pre-push hook and CI keep working. Branches are checked; tags and branch deletions are forwarded without checks; other refs are refused.
- **Not taken from no-mistakes, on purpose:** the agent-driven pipeline with nine agent backends, the interactive approve/fix/skip TUI, auto-fixing findings, opening the PR, and the CI-repair loop with guarded force-pushes. Each needs an agent to edit and push code on its own — the opposite of what the rest of the kit holds an agent to. The `docs` stage is covered by the post-merge nudge and the dossier rules. A `/no-mistakes` skill for agents was not built.
- Rejected: using `git worktree` per push without removing the quarantine marker (git forbids ref updates inside `pre-receive`'s quarantine, including the detached HEAD of a new worktree); a persistent gate worktree (state leaks between pushes).

## Where it lives
- `templates/gate.sh` (init / status / remove; `slickrails gate …` in `bin/slickrails`), `templates/gate/pre-receive` (the hook, copied into `.git/slickrails-gate.git/hooks/`)
- `templates/ai-review.sh`: `SLICKRAILS_REVIEW_BASE` lets the caller choose the diff base (the gate passes the target branch tip)
- `tests/run.sh` — block "local gate": init/status/remove, green and red pushes, the working copy mattering in neither direction, tags, deletions, refused refs, setup + linked dependency dirs, timeout, a refusal by the real remote, the AI review (FAIL / PASS / ERROR with a stub reviewer)

## How to test it
1. `sh tests/run.sh` — expect 241+ passed.
2. By hand: `slickrails gate init`, then `git push gate <branch>` (red tests → rejected with the check output; green → forwarded).

## Limits & open items
- Tested on macOS only, against local bare repositories (the real remote was always a local path); a real GitHub/SSH remote, credentials prompts and push protocols other than local are unverified.
- **Only pushes through `gate` are gated.** `git push origin` still bypasses it (the pre-push hook and CI remain the other layers); "a red push never reaches the real remote" holds for pushes made through the gate.
- The pushed commit brings its own `.slickrails/config.sh` (like CI does): a commit that weakens its checks is judged by the weakened checks. CI and branch protection remain the boundary. The checks run your code with **your environment variables** (tokens, `SSH_AUTH_SOCK`); on a failing check their output is echoed to the push. A `config.sh` that is a symlink in the pushed commit is refused; `GATE_LINK_DIRS` entries that leave the worktree are ignored. `CHECK_GATE_SETUP` (e.g. `npm ci`) on a linked `node_modules` writes into the source checkout.
- Several refs in one push are all checked first and then forwarded with `git push --atomic` (a real remote without atomic push support refuses, which is safe: nothing changes there). Tags and deletions are forwarded without checks and are part of the same all-or-nothing push.
- Hanging commands: the checks run under a deadline (`slickrails.timeout`, 900 s) and so do `git ls-remote` and the forwarding push (`slickrails.nettimeout`, 60 s, no credential prompts). A timeout stops the whole process tree, closes inherited descriptors (a leftover process holding the connection kept `git push` waiting in the first version) and rejects the push. Credential helpers or an ssh passphrase prompt that need a terminal fail or run into the net timeout. If `git push gate` still hangs, `Ctrl-C` is safe: the hook stops its child processes and nothing is forwarded.
- The gate needs a working `ps` to stop hung checks; where `ps` is blocked it refuses every push and says so.
- The first push of a new branch sends the full history to the gate repository.
- The forwarding target is the remote's push URL; a remote with several push URLs is refused. A sha256 repository gets a sha256 gate repository.
- The AI review base is the tip of the same branch on the real remote, else its HEAD, else the gate's previous tip; with no base the review is skipped with a message.
- `GATE_LINK_DIRS` makes the checks use the source checkout's dependency directories: not hermetic, but fast; leave it unset for a clean install per push.
- The gate is not part of `doctor` yet; no Codex or Claude hook integration (an agent that runs `git push gate` simply goes through it).

## History
- 2026-10-21: created from the maintainer's request to take the core of kunchenguid/no-mistakes (MIT, Go; read, not copied).
- 2026-10-21: Codex review and self-review of f5bea27 (all reproduced by tests first). Symptom → cause → fix:
  - a push with a green and a red ref still put the green ref on the real remote → refs were validated and forwarded one by one → all refs are checked first, then forwarded together (`--atomic` for several);
  - `git push gate` returned only after the hung check ended although "timed out" was reported (5 s, or 300 s with a grandchild) → `pkill -P` stopped direct children only and an orphan held the connection to the pusher → process tree stopped (freeze, TERM, KILL), inherited descriptors closed, trap kills the tree when the hook is interrupted;
  - the gate forwarded to the fetch URL, ignoring `remote.<name>.pushurl` → `get-url --push`, several push URLs refused;
  - a network failure was reported as "the real remote refused" → neutral wording, bounded `ls-remote`/push, no credential prompts;
  - a symlinked `config.sh` and `GATE_LINK_DIRS` paths leaving the worktree were followed → refused / ignored;
  - a sha256 repository got a sha1 gate → same object format; the review-base lookup had no test → the rejection output must name the real remote's branch tip as base.
- 2026-10-21: Codex review of 3739195 (P2). Symptom: in a sandbox where `ps` is blocked (`/bin/ps: Operation not permitted`) the timeout tests failed and the test "leaves no process behind" still went green, because a failed `ps` gave an empty process list. Cause: `kill_tree` finds descendants with `ps -A -o pid=,ppid=`; without it only the direct child is stopped, and the negative test read "no output" as "no process". Fix: the hook checks `ps` first and refuses the push with a message naming it (fail closed); the test treats an unusable `ps` as a failure and a new test pins the refusal (red first: the push went through). Process groups instead of `ps` were not taken: `set -m` prints job messages in non-interactive shells and `setsid` is missing on macOS.
- 2026-10-21: Codex review of 8de5a06 (P2). Symptom: a `ps` that prints a partial list and then exits 1 passed the pre-check and the push was forwarded. Cause: the check looked only at whether the output was empty. Fix: exit status and output are both checked; new test with such a stub (red first).
- 2026-10-22: first CI run on GitHub (Linux). Symptom: with the AI review opted in, a FAIL verdict did not reject the push, and nothing said that the review had not run. Cause: the review base came from the real remote's branch or HEAD; a bare remote created with `init.defaultBranch=master` that only ever received `main` has a HEAD pointing nowhere, so no base was found, `ai-review.sh` printed "skipping" and exited 0, and the gate showed only the `==` step lines of a green run. macOS never hit it because the local git config used `main`. Fix: the base lookup also tries the remote's `main` and `master`; the review's own messages are shown in the push output, so a skipped review is visible. Tests (red first, on macOS too, by pointing the remote's HEAD at a missing branch): "with the remote's HEAD pointing nowhere the review still runs against main", "a review skipped for lack of a base says so in the push output". Verified on Ubuntu 24.04 with git 2.55 in Docker, set up like a GitHub runner (no global git config, shallow checkout, CI=true).
  Not done: an environment allow-list for the checks; submodules, concurrent pushes and huge repositories were not tested.
- 2026-10-22 (PR #13, Windows): the gate refused every push on Git Bash, whose ps has no -A/-o (the fail-closed probe from 8de5a06 did what it should) → the process listing falls back to `ps -e` in the MSYS format, `alive()` to `kill -0`; tests with a Git Bash ps stand-in: a hung check with a grandchild is stopped, a green push goes through. The gate URL test compares with git's push URL (git on Windows stores /tmp/... as C:/Users/.../Temp/...).

# Session Stop gate that does not fail open

**Status:** active · **As of:** 2026-10-20 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
Improvement plan, point 3. The Stop hook (`session-check.sh`) is the enforcement behind "a session only ends
green", but it let the session through in three proven situations: the work was already committed (clean
tree), the hook ran longer than its host timeout (Claude Code cancels it and renders no decision), and the hook
itself crashed (every exit other than 2 is a non-blocking error). It also treated `stop_hook_active` as a free
pass.

## Kit repo: a lighter session check (SLI-209, 2026-11-28)
**The ask:** while building SLI-175 (2026-11-27) the Stop gate ran into its own deadline in the kit repo:
`sh scripts/lint.sh` + `sh tests/run.sh` took longer than 270 s, so sessions ended through the timeout path
instead of a real green or red. Measure lint and suite on macOS and decide: a faster suite, a lighter session
check in `config.sh` (pre-push keeps the full one), or a different deadline.

**Measured** (macOS 27, Apple M2 Max, 2026-11-28, other agent sessions running on the same machine):

| What | Time | Load average |
|---|---|---|
| `sh scripts/lint.sh` | 4 s | ~4 |
| `sh tests/run.sh` (all, 564 tests) | 244 s | ~4 |
| `SLICKRAILS_TESTS=fast sh tests/run.sh` (420 tests) | 156 s | 34–40 |
| Stop gate with lint + fast part, green, exit 0 | 103 s | ~50 |

Slowest sections of the full run: package check 41 s, installer honesty round 3 (no jq) 32 s, gate round 2
23 s, local gate 20 s, seeded-bug benchmark 13 s — together 129 s, more than half the suite. Lint + full suite
(248 s at a quiet moment) leaves about 20 s to the deadline, and the deadline counts from the start of the
hook; one more ticket or a busy machine and it is over.

**Decision:** a lighter session check for the kit repo, through the existing `CHECK_SESSION`:
`tests/run.sh` takes `SLICKRAILS_TESTS=fast`, which leaves out exactly those five sections. pre-push and CI keep
the full suite (`CHECK_TYPECHECK` + `CHECK_TEST`, `SLICKRAILS_TESTS` unset = `all`). Rejected: raising the
deadline (Claude Code cancels the hook at its 300 s timeout, only 30 s more), running sections in parallel (a
large rewrite of `tests/run.sh`, which almost every open PR changes).
- The list of left-out sections (`SLOW_SECTIONS` at the top of `tests/run.sh`) names sections by part of their
  header line. An entry that matches no header stops the run with exit 2 and names the entry, so a renamed
  section cannot silently come back or drop out. An unknown `SLICKRAILS_TESTS` value also stops with exit 2.
- `SLICKRAILS_TESTS_PLAN=1` prints the section headers a selection would run, without running them.
- The line for `.slickrails/config.sh` (a protected kit file, the maintainer adds it):
  `CHECK_SESSION="sh scripts/lint.sh && SLICKRAILS_TESTS=fast sh tests/run.sh"`

**Where it lives:** `tests/run.sh` (selection block at the top, "test selection" section with its tests).

**How to test it:**
1. `sh tests/run.sh` — the three "test selection" tests (fast leaves out the slow sections; unknown value → exit 2;
   stale list entry → exit 2).
2. `SLICKRAILS_TESTS=fast SLICKRAILS_TESTS_PLAN=1 sh tests/run.sh` — the list of sections the gate runs.
3. With the line above in `config.sh`: change a file and let a session stop — the gate runs lint + fast part and
   ends green well before 270 s.

**Limits:** what the fast part leaves out is checked at push time, not at session end: a session that breaks the
package check or the local gate ends green and is stopped by pre-push. A new slow section has to be added to the
list by hand; nothing measures the fast part's time against the deadline automatically. Side finding: an
*exported* `CHECK_SESSION` reaches the suite's test repos and overrides their `config.sh` (a hand-run gate with
`CHECK_SESSION=… sh .slickrails/session-check.sh` showed 7 false failures); set in `config.sh` it is not exported.

## Decisions
- **Check when there is something to check:** uncommitted work **or** commits ahead of the upstream branch (else `origin/HEAD`, `origin/main`, `origin/master`). Without any base (no remote, detached HEAD) every commit counts as not pushed yet. A failing `git status` is a crash, not "nothing to check".
- **Own deadline:** `SLICKRAILS_STOP_DEADLINE_MS` (env wins over `config.sh`; default 270000, below the 300 s hook timeout in `claude-settings.json`). Over it → the check process tree is killed (parent first, TERM then KILL) and the hook exits 2. A polling loop, not a watcher process: macOS has no `timeout`, and a watcher outlives the run (an orphaned `sleep 270` per stop in the first version) and breaks when the host starts the hook with SIGTERM ignored. A check over the deadline uses up the retries at once: block once, the next stop at that state passes (a slow suite does not get faster by asking again).
- **Crash = red:** an `EXIT` trap turns any unexpected exit into exit 2 with "session-check crashed"; the config is syntax-checked first (`sh -n`), because sourcing a broken file silently yields "no checks".
- **Cache:** a state that was checked green is not checked again. Key = tree of the working copy including untracked, not-ignored files **plus a hash of the check command**, computed with a throwaway index and a throwaway object directory (nothing lands in the real index or object database), stored in `.git/slickrails-last-ok`. Keeps the extra runs (commits ahead) cheap: 19.8 s cold for this repo's suite, 0.11 s on a hit.
- **Bounded blocking instead of a free pass:** `stop_hook_active` is ignored. Red → exit 2, counted per unchanged state in `.git/slickrails-stop-blocks`; after 3 blocks the next stop ends the session **without re-running the checks**, with a loud "The task is NOT done". Changing the working copy resets the counter. Rejected: relying on the host's cap alone (documented as 8 consecutive blocks, not triggered by me → unverified).
- Rejected: reading the hook JSON in Python (A's wrapper design); a missing config is still "nothing to check" (that is `doctor`'s job, plan point 4).

## Where it lives
- `templates/session-check.sh` (+ this repo's own copy `.slickrails/session-check.sh`)
- `tests/run.sh` — "session-check in isolation" block (commits ahead, cache, deadline incl. orphan check, crash) and the changed loop-guard tests
- `tests/benchmark/cases/{st-red-committed-clean-tree,st-timeout-red}` — known-miss markers deleted; controls `st-deadline-green`, `st-green-dirty`, `st-clean-tree-green` stay green
- `SLICKRAILS.md`, `SLICKRAILS.de.md` — session layer paragraph

## How to test it
1. `sh tests/run.sh` — expect 86 passed.
2. `sh tests/benchmark/run.sh` — expect `caught 9/10 faults, false positives 0/8 controls, known-miss 1`.
3. `env BENCH_AI=1 sh tests/benchmark/host/claude-stop-timeout.sh` — the host behavior this guards against (a timed-out hook = session ends).

## Limits & open items
- Waiting for Codex acceptance: nothing here is wired to Codex (plan point 5, undecided). Whether a Codex Stop hook fails open on timeout, and whether it exits non-blocking on crashes, is unverified.
- The host's own cap on consecutive blocks was not triggered; the 3-block counter makes the hook independent of it.
- The cache key ignores ignored files (`node_modules`, build output, an ignored file a test depends on) and the environment: a change that does not touch the tree or the command is not re-checked. Keying ignored directories by content would cost more than the cache saves; the push-time hook and CI run fresh.
- Not handled: processes that daemonize out of the check's process tree (parent PID 1) survive the deadline kill; `ps -A -o pid=,ppid=,stat=` and a fractional `sleep` are assumed (macOS/GNU; busybox untested). Parallel stops in several terminals of one repo share the state files (lost counter updates; the host's cap still bounds the blocking). A/B toggling of the working state resets the counter. A question-only session cannot be told apart from a working session (no session-start marker).
- A repo whose branch is ahead of `origin/main` runs the full suite once per state in a question-only session; the cache keeps that to one run until something changes.
- Windows Git Bash is untested (`ps`, `awk` and fractional `sleep` are assumed).

## History
- 2026-10-20: created (plan point 3). Benchmark L1 7/10 → 9/10 faults, 0/8 false positives.
- 2026-10-20: self-review of 6986a53 (fresh reviewer, 10 findings, reproduced first). Symptoms → cause → fix:
  - a red commit in a repo without remote passed (`AHEAD=0` without a base) → every commit counts when there is no base;
  - the hook hung when the host started it with SIGTERM ignored, and left an orphaned `sleep 270` per run → the watcher process and `wait` on it; replaced by a polling loop, TERM then KILL;
  - the cache served green for a different check command → command hash in the key; a failing `git status` passed → now a crash;
  - the key computation wrote objects (untracked files) into the repository → throwaway object directory;
  - after 3 blocks every further stop re-ran the full suite → skipped; a too-slow check cost the deadline 3 times → blocks once.
  Also fixed the same watcher leak in `templates/ai-review.sh` and `tests/benchmark/host/claude-stop-timeout.sh`. Not reproducible/rejected: see the rejected ideas (lock for parallel stops, counter reset by A/B toggling, session-start gate, keying ignored files, `set -m`/process groups).
- 2026-10-22 (PR #13, Windows): symptom: on Git Bash the deadline did not stop a hung check's children (the benchmark case st-timeout-red failed) → cause: `ps -A -o pid=,ppid=` does not exist in Git Bash's ps → fix: `pslist()` falls back to `ps -e` in the MSYS format (status letter in front of stopped processes), `alive()` to `kill -0`; test with a Git Bash ps stand-in (red first). A sh -x trace on the Windows runner showed the tree is then found and stopped, in about 1 s.
- 2026-10-22: symptom: st-timeout-red ended in exit 143 on Windows and now and then on macOS → cause: the case gave the gate 0.4 s between its 200 ms deadline and the simulated host kill; and the deadline was counted from the start of the checks, while the host counts from the start of the hook → fix: a wall-clock bound from the hook's start (whole seconds, checked on the first tick); test "time spent before the checks counts against the deadline" (git status made 8 s slow, 6 s deadline: 17 s before, 8 s after). The benchmark case's host timeout became 5 s (see the benchmark dossier).
- 2026-10-22 (PR #14, Windows): symptom: "time spent before the checks counts against the deadline" took 70 s on the Windows runner once (11 s allowed; it had passed the run before) → cause: the deadline was already used up when the checks started, so the gate started them and stopped them at once; on Git Bash a process can miss a signal while it is still starting, and the gate then waited for the 40 s check → fix: a deadline used up before the start does not start the checks (the block message says so); after stopping, the gate re-sends the stop for up to 2 s and never waits on a process that will not die. The local gate's `bounded()` got the same bounded retry.

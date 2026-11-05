# Seeded-bug benchmark

**Status:** active · **As of:** 2026-10-20 · **Built by:** the maintainer with Claude Code

## The ask (plain language)
Codex produced an improvement plan for slickrails, Claude cross-examined it, and the
merged result is the improvement plan (the maintainer's words for point 1: "Punkt 1 ist immer der
Seeded-Bug-Benchmark als Regressionstest, getrennt ausgewertet je Agent, falls er nicht
schon existiert. Ohne Messlatte kein Fortschritt."). Every later change to a guardrail has to
move a number in this benchmark or it does not stay.

## Decisions
- L1 runs the **template** hooks in throwaway repos, not this repo's own `.githooks` → measures what a fresh install ships.
- Known gaps are **documented, not hidden**: a `known-miss` marker per case keeps the suite green while the gap is counted; fixing the gap makes the marker stale and the suite red until it is deleted → the score can only go up deliberately.
- L2 reuses the shipped `ai-review.sh` with the real `claude` CLI, N repetitions, no binary gate (LLM variance); rates are recorded in `baselines/claude.txt`.
- L3 (Codex) is an adapter that exits BLOCKED (77) while no Codex review backend exists/`codex` is unusable. BLOCKED is never counted as caught or green. Rejected: simulating Codex results.
- Rejected: A's 15-case set (its evidence ZIP was unreadable) — this set starts from the verified bypasses and grows with each fix commit.
- Rejected: fixed timing assertions in the baseline (flaky).

## Where it lives
- `tests/benchmark/run.sh` — runner (`--layer L1|L2|L3`, `--reps`, `--record`, `--strict`)
- `tests/benchmark/lib.sh` — throwaway repo with the template hooks armed
- `tests/benchmark/cases/<id>/{case.sh,known-miss}` — L1 faults and controls
- `tests/benchmark/ai-cases/<id>/change.txt` — L2 diffs (`clean-*` = control)
- `tests/benchmark/adapters/codex.sh` — L3 placeholder (BLOCKED)
- `tests/benchmark/baselines/` — recorded numbers
- `tests/run.sh` — runs L1 as one suite check

## How to test it
1. `sh tests/benchmark/run.sh` — L1, expect `caught 4/10 faults, false positives 0/8 controls, known-miss 6`.
2. `sh tests/benchmark/run.sh --strict` — exit 1, six REGRESSION lines (the documented gaps).
3. `BENCH_MODEL=claude-sonnet-5-5 BENCH_AI=1 sh tests/benchmark/run.sh --layer L2 --record` — real claude review rates (pinned model).
4. `sh tests/benchmark/run.sh --layer L3` — BLOCKED, exit 77, while Codex is unusable.
5. `sh tests/run.sh` — whole suite incl. the benchmark.

## Limits & open items
- Waiting for Codex acceptance: L3 cannot be measured until `codex` is installed and a Codex review backend exists.
- Regex-fallback cases are skipped when `gitleaks` is installed (profile is printed as `gitleaks=0|1`).
- Set is 10 faults / 8 controls; later plan points add cases with their fix.
- Not added although listed in the plan: "missing test scripts" as a fault — the plan decided warn + `doctor` instead of a hard fail, so there is nothing to catch yet (it arrives with plan point 4).
- L2 baseline is at the ceiling (12/12 caught with a matching finding, 0/6 false positives): the four fixtures are too obvious to separate review quality. Harder, subtler fixtures are needed before L2 can show an improvement.
- The `PASS but FAIL` and stop-timeout cases use stubs/simulations (wrapper protocol and a simulated 0.6 s host kill, no perl), not the real hosts. Each fault has a control that rules out cheating implementations (`rv-pass-clean`, `st-deadline-green`), and the timeout fault requires proof that the red check really started.
- The real Claude behavior behind the simulation is backed by `tests/benchmark/host/claude-stop-timeout.sh` (BENCH_AI=1): a Stop hook that outlasts its timeout is called once and the session ends (fail-open); the control, a fast exit-2 hook, is called 3 times. Codex has no equivalent yet — waiting for Codex acceptance.
- Contracts the fixes must meet, written into the cases: an invalid reviewer verdict makes the wrapper print a line containing `ERROR` (plan point 2); `SLICKRAILS_STOP_DEADLINE_MS` is the deadline knob of plan point 3.

## History
- 2026-10-20: created (plan point 1). Baseline L1: caught 4/8, false positives 0/6.
- 2026-10-20: Codex review of 607f84b, four findings, all reproduced and fixed:
  1. BLOCKED layers exited 0 → now exit 77.
  2. L1 counted any nonzero exit as a catch (a Stop hook with `exit 1` stayed green) → `BLOCK_RC=2` for Stop cases.
  3. L2 label leaked through the file name, FAIL verdict alone counted as a catch → neutral names + matching finding.
  4. Unparseable reviews looked like clean controls → INVALID, layer exits 1; model pinned via `BENCH_MODEL`.
  Added cases `rv-pass-but-fail` and `st-timeout-red` (both known-miss until plan points 2 and 3). L1 baseline now caught 4/10, 0/6 false positives.
- 2026-10-20: Codex review of 1fd623b, four findings, all reproduced and fixed:
  1. `rv-pass-but-fail` counted silence as a catch (a wrapper that just `exit 0`s scored "caught") → a catch now needs a visible `ERROR` line; control `rv-pass-clean` added.
  2. `st-timeout-red` could be satisfied by blocking every session end → the red check must prove it started, control `st-deadline-green` added; a reference implementation turns both fault cases green, the two cheating mutants stay red.
  3. The timeout case cost +2 s per run → simulated host kill at 0.6 s, check sleeps 1 s (L1 6.6 s → 5.4 s with two more cases).
  4. Undocumented perl dependency → plain `sh` (`kill` after `sleep 0.6`).
  Also: the claim "real Claude timeout verified by hand" now has a repeatable script. L1 baseline: caught 4/10, 0/8 false positives.
- 2026-10-20: Codex review of 6040d39 (via the mailbox), one finding, reproduced with Codex's stub (CLI exits 42 after the hook call → script still printed `FAIL-OPEN CONFIRMED`, exit 0): `tests/benchmark/host/claude-stop-timeout.sh` now checks the exit code and, with jq, the result (`is_error == false`, `subtype == "success"`, which also excludes turn-limit aborts) of both claude calls, bounds each call with `BENCH_HOST_TIMEOUT` (default 120 s) and shows claude's stderr on a harness error. Regression tests with stub CLIs in `tests/run.sh` (works / dies / turn-limit abort / hangs). Real run unchanged: control 3 calls, timed-out hook 1 call, confirmed. Not checked separately: that every kind of abort is classified as a harness error (only the ones above).
- 2026-10-22: st-timeout-red changed its timing, not what it measures: the simulated host timeout went from 0.6 s (1 s red check) to 5 s (10 s red check); the deadline stays 200 ms. Reason: stopping a process tree takes about 1 s on Git Bash and occasionally more than 0.4 s on a loaded macOS runner, so a working gate was killed by the "host". Checked against the 1.2.0 gate without its own deadline: still a miss (exit 143), 9/12 overall; the current gate catches it (11/12).

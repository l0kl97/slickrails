# Seeded-bug benchmark

The yardstick for slickrails guardrails: a fixed set of seeded faults and clean
controls, run against the **template** hooks (what a fresh install ships).
No benchmark number, no claim that a guardrail got better.

| Layer | What it runs | Cost | How to run |
|---|---|---|---|
| **L1** deterministic | `pre-commit`, `pre-push`, `session-check.sh` against `cases/` | offline, seconds | `sh tests/benchmark/run.sh` (also part of `sh tests/run.sh`) |
| **L2** claude review | the shipped `ai-review.sh` with the real `claude` CLI against `ai-cases/`, N repetitions | tokens | `BENCH_AI=1 sh tests/benchmark/run.sh --layer L2 [--reps 3] [--record]` |
| **L3** codex review | `adapters/codex.sh` | — | exits **BLOCKED** until a Codex review backend exists and `codex` is usable |

Results are reported per layer and never mixed across agents. BLOCKED and SKIPPED
count neither as caught nor as green.

## L1 cases

`cases/<id>/case.sh` defines `KIND` (`fault` = the guard must block, `control` = the
guard must pass), `setup()` (runs in a throwaway repo with hooks not yet armed) and
`act()` (the guarded action; its exit status is the verdict). Fixtures that look like
secrets are assembled from parts so this repo never trips its own scanner.

A fault the kit does not catch yet carries an empty `cases/<id>/known-miss` file:

| Outcome | Meaning | Suite |
|---|---|---|
| good, no marker | OK | green |
| bad, marker | KNOWN-MISS (documented gap, counted) | green |
| bad, no marker | REGRESSION | **red** |
| good, marker | STALE-MARKER — the gap was fixed, delete the marker | **red** |

So every guardrail fix is one commit that flips cases: test first (the case is red
with `--strict`), fix, delete the marker (suite green again, score goes up).
`--strict` ignores the markers and shows the raw gaps.

Rules for fault cases, so they cannot be passed by cheating: pair every fault with a control that a
blanket "always block" or "always certify" implementation would fail (`rv-pass-clean`,
`st-deadline-green`), require proof that the guarded work really ran (marker file, exit 98 otherwise),
and assert a concrete observable (exit code via `BLOCK_RC`, a visible `ERROR` line), never mere absence.
Simulated host behavior needs no extra runtime beyond `sh`; the real-host counterpart of the Stop-timeout
case is `BENCH_AI=1 sh tests/benchmark/host/claude-stop-timeout.sh` (with its own fast-hook control).

Cases tagged `NEEDS_NO_GITLEAKS=1` exercise the regex fallback and are SKIPPED when
`gitleaks` is installed (the score line prints `gitleaks=0|1`).

## L2 cases

`ai-cases/<id>/change.txt` is committed under a neutral file name (`src/m<checksum>.py`,
so the reviewer cannot read the label from the path) on top of a base commit and reviewed
by `ai-review.sh`. Names starting with `clean-` are controls.

- **Caught** = verdict FAIL **and** a finding that matches `ai-cases/<id>/match` (an ERE
  naming the seeded defect). A FAIL verdict alone is only counted as "FAIL verdicts in total".
- **False positive** = a FAIL verdict on a control.
- **Invalid review** = anything without an explicit verdict line from the wrapper (the wrapper
  is fail-open: unparseable answer, missing CLI or empty diff all exit 0). Invalid reviews are
  counted neither as caught nor as clean, and the layer exits 1.
- **Comparability:** pin the model with `BENCH_MODEL=<model id>` (exported as `ANTHROPIC_MODEL`);
  the summary records CLI version and model (`default` = whatever the CLI picks, not comparable).
- LLM output varies, so L2 reports rates over N repetitions and has no pass/fail gate on the rates.

## Exit codes

`0` measured and clean · `1` regression / invalid measurement · `77` BLOCKED (layer not measured:
no `BENCH_AI=1`, no `claude`, no usable Codex). L1 `BLOCK_RC`: cases for Stop hooks pin exit 2,
because exit 1 is only a non-blocking error there.

## Baselines

`baselines/<layer>.txt` records the last `--record`ed run (summary + per-case lines),
so a change in the numbers shows up in the diff. A worse baseline is never overwritten
silently.

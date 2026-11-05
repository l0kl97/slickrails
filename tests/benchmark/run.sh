#!/bin/sh
# slickrails seeded-bug benchmark — the yardstick for every guardrail change.
#
# Usage:
#   sh tests/benchmark/run.sh                  L1 (deterministic hooks), no network
#   sh tests/benchmark/run.sh --layer L2       real `claude -p` review via ai-review.sh
#                                              (needs BENCH_AI=1, costs tokens; --reps N, default 3)
#   sh tests/benchmark/run.sh --layer L3       Codex layer (BLOCKED while codex is unusable)
#   sh tests/benchmark/run.sh --record         also write tests/benchmark/baselines/<layer>.txt
#   sh tests/benchmark/run.sh --strict         ignore known-miss markers (shows every raw gap as REGRESSION)
#
# L1 contract: each case is a fault (the guard must BLOCK) or a control (the guard
# must PASS). A fault the kit does not catch yet carries a `known-miss` marker.
#   good + no marker   -> OK
#   bad  + marker      -> KNOWN-MISS (counted, not failing)
#   bad  + no marker   -> REGRESSION (exit 1)
#   good + marker      -> STALE-MARKER (exit 1: an improvement must delete its marker)
# BLOCKED / SKIPPED are never counted as caught and never as green: a blocked
# layer exits 77, so a pipeline cannot mistake "not measured" for "passed".

set -u

BENCH_DIR="$(cd "$(dirname "$0")" && pwd)"
KIT_DIR="$(cd "$BENCH_DIR/../.." && pwd)"
export KIT_DIR
. "$BENCH_DIR/lib.sh"

LAYER="L1"; RECORD=0; REPS=3; STRICT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --layer) LAYER="$2"; shift 2;;
    --reps)  REPS="$2"; shift 2;;
    --record) RECORD=1; shift;;
    --strict) STRICT=1; shift;;
    *) echo "unknown argument: $1" >&2; exit 2;;
  esac
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/slickrails-bench.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
LINES="$WORK/lines.txt"; : > "$LINES"

HAVE_GITLEAKS=0; command -v gitleaks >/dev/null 2>&1 && HAVE_GITLEAKS=1

record() { # record <baseline-name> <summary>
  [ "$RECORD" = "1" ] || return 0
  mkdir -p "$BENCH_DIR/baselines"
  { printf '%s\n' "$2"; cat "$LINES"; } > "$BENCH_DIR/baselines/$1.txt"
  echo "recorded: tests/benchmark/baselines/$1.txt"
}

# ------------------------------------------------------------------ L1 ------
layer1() {
  FAULTS=0; CAUGHT=0; CONTROLS=0; FALSEPOS=0; KNOWN=0; SKIPPED=0; BAD=0
  for D in "$BENCH_DIR"/cases/*/; do
    ID="$(basename "$D")"
    KIND="$(. "$D/case.sh"; printf '%s' "$KIND")"
    NEEDS="$(. "$D/case.sh"; printf '%s' "${NEEDS_NO_GITLEAKS:-0}")"
    BRC="$(. "$D/case.sh"; printf '%s' "${BLOCK_RC:-}")"
    if [ "$NEEDS" = "1" ] && [ "$HAVE_GITLEAKS" = "1" ]; then
      SKIPPED=$((SKIPPED+1)); printf '%-28s %-8s SKIPPED (gitleaks installed, regex-fallback case)\n' "$ID" "$KIND" | tee -a "$LINES"
      continue
    fi
    (
      . "$D/case.sh"
      bench_repo "$WORK/$ID" || exit 99
      cd "$WORK/$ID" || exit 99
      setup || exit 99
      act
    ) > "$WORK/$ID.log" 2>&1
    RC=$?
    if [ "$RC" -eq 99 ]; then
      BAD=$((BAD+1)); printf '%-28s %-8s HARNESS-ERROR (see log)\n' "$ID" "$KIND" | tee -a "$LINES"
      sed 's/^/    | /' "$WORK/$ID.log" | tail -8
      continue
    fi
    if [ "$KIND" = "fault" ]; then
      # Caught = the guard blocked the way its host honors. Claude/Codex Stop hooks only block on
      # exit 2 (exit 1 is a non-blocking error), so such cases pin BLOCK_RC=2; git hooks: any nonzero.
      FAULTS=$((FAULTS+1))
      if [ -n "$BRC" ]; then [ "$RC" -eq "$BRC" ] && GOOD=1 || GOOD=0; else [ "$RC" -ne 0 ] && GOOD=1 || GOOD=0; fi
      [ "$GOOD" = 1 ] && CAUGHT=$((CAUGHT+1))
      LABEL_GOOD="caught"; LABEL_BAD="missed (exit $RC, wanted ${BRC:-nonzero})"
    else
      CONTROLS=$((CONTROLS+1)); [ "$RC" -eq 0 ] && GOOD=1 || GOOD=0; [ "$GOOD" = 0 ] && FALSEPOS=$((FALSEPOS+1))
      LABEL_GOOD="clean"; LABEL_BAD="false-positive"
    fi
    MARK=0; [ -f "$D/known-miss" ] && [ "$STRICT" = "0" ] && MARK=1
    if [ "$GOOD" = 1 ] && [ "$MARK" = 0 ]; then V="OK $LABEL_GOOD"
    elif [ "$GOOD" = 0 ] && [ "$MARK" = 1 ]; then V="KNOWN-MISS $LABEL_BAD"; KNOWN=$((KNOWN+1))
    elif [ "$GOOD" = 0 ]; then V="REGRESSION $LABEL_BAD"; BAD=$((BAD+1))
    else V="STALE-MARKER $LABEL_GOOD (delete cases/$ID/known-miss)"; BAD=$((BAD+1))
    fi
    printf '%-28s %-8s %s\n' "$ID" "$KIND" "$V" | tee -a "$LINES"
  done
  SUMMARY="L1 deterministic: caught $CAUGHT/$FAULTS faults, false positives $FALSEPOS/$CONTROLS controls, known-miss $KNOWN, skipped $SKIPPED, errors $BAD (gitleaks=$HAVE_GITLEAKS)"
  echo "$SUMMARY"
  record deterministic "$SUMMARY"
  [ "$BAD" -eq 0 ]
}

# ------------------------------------------------------------------ L2 ------
# Real review through the shipped ai-review.sh with the real claude CLI.
# Measures catch rate per fixture over N repetitions; no binary gate (LLM variance).
layer2() {
  if [ "${BENCH_AI:-0}" != "1" ]; then
    echo "L2 claude review: BLOCKED (set BENCH_AI=1; costs tokens)"; return 77
  fi
  if ! command -v claude >/dev/null 2>&1; then
    echo "L2 claude review: BLOCKED (claude CLI not found)"; return 77
  fi
  CV="$(claude --version 2>/dev/null | head -1)"
  MODEL="${BENCH_MODEL:-default}"
  [ -n "${BENCH_MODEL:-}" ] && export ANTHROPIC_MODEL="$BENCH_MODEL"
  F_TOT=0; F_HIT=0; F_FAILV=0; C_TOT=0; C_FP=0; INVALID=0
  for D in "$BENCH_DIR"/ai-cases/*/; do
    ID="$(basename "$D")"; N=0; HITS=0; FAILV=0; PASSV=0; BADR=0
    case "$ID" in clean-*) KIND=control;; *) KIND=fault;; esac   # naming convention: clean-* = control
    NAME="m$(printf '%s' "$ID" | cksum | cut -d' ' -f1)"        # neutral file name: the reviewer must not see the label
    MATCH=""; [ -f "$D/match" ] && MATCH="$(cat "$D/match")"
    while [ "$N" -lt "$REPS" ]; do
      N=$((N+1))
      (
        bench_repo "$WORK/$ID.$N" || exit 99
        cd "$WORK/$ID.$N" || exit 99
        mkdir -p src
        cp "$D/change.txt" "src/$NAME.py"
        git add -A; git commit -q --no-verify -m "seeded change"
        sh .slickrails/ai-review.sh
      ) > "$WORK/$ID.$N.log" 2>&1
      RC=$?
      # A review is only valid with an explicit verdict line from the wrapper. The wrapper is
      # fail-open (unparseable answer, missing CLI, empty diff all exit 0), so exit 0 alone proves nothing.
      if [ "$RC" -eq 1 ] && grep -q 'FAIL — findings' "$WORK/$ID.$N.log"; then
        FAILV=$((FAILV+1))
        # a catch needs a finding that names the seeded defect, not just a FAIL verdict
        FINDINGS="$(sed -n '/FAIL — findings:/,$p' "$WORK/$ID.$N.log" | sed '1d;$d')"
        if [ -z "$MATCH" ] || printf '%s\n' "$FINDINGS" | grep -Eiq "$MATCH"; then HITS=$((HITS+1)); fi
      elif [ "$RC" -eq 0 ] && grep -q 'PASS — push proceeds' "$WORK/$ID.$N.log"; then
        PASSV=$((PASSV+1))
      else
        BADR=$((BADR+1))
      fi
    done
    INVALID=$((INVALID+BADR))
    if [ "$KIND" = "fault" ]; then F_TOT=$((F_TOT+REPS)); F_HIT=$((F_HIT+HITS)); F_FAILV=$((F_FAILV+FAILV))
    else C_TOT=$((C_TOT+REPS)); C_FP=$((C_FP+FAILV)); fi
    printf '%-24s %-8s FAIL-verdict %s/%s, matching finding %s/%s, valid PASS %s/%s, INVALID %s/%s\n' \
      "$ID" "$KIND" "$FAILV" "$REPS" "$HITS" "$REPS" "$PASSV" "$REPS" "$BADR" "$REPS" | tee -a "$LINES"
  done
  SUMMARY="L2 claude review (cli: $CV, model: $MODEL, $REPS reps): caught $F_HIT/$F_TOT fault runs (FAIL verdict with a finding naming the seeded defect; $F_FAILV FAIL verdicts in total), false positives $C_FP/$C_TOT control runs, invalid reviews $INVALID (counted neither as caught nor as clean)"
  echo "$SUMMARY"
  record claude "$SUMMARY"
  [ "$INVALID" -eq 0 ]
}

# ------------------------------------------------------------------ L3 ------
layer3() {
  sh "$BENCH_DIR/adapters/codex.sh"
  RC=$?
  SUMMARY="L3 codex review: $( [ "$RC" -eq 77 ] && echo BLOCKED || echo "exit $RC" )"
  echo "$SUMMARY" >> "$LINES"
  record codex "$SUMMARY"
  return "$RC"
}

case "$LAYER" in
  L1) layer1;;
  L2) layer2;;
  L3) layer3;;
  *) echo "unknown layer: $LAYER" >&2; exit 2;;
esac

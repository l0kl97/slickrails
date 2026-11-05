#!/bin/sh
# Host check (real claude CLI, costs a few cents): does a Stop hook that outlasts its timeout let the
# session end? Backs the st-timeout-red case, which only simulates the host kill.
#   BENCH_AI=1 sh tests/benchmark/host/claude-stop-timeout.sh
#   BENCH_MODEL pins the model (default haiku) · BENCH_HOST_TIMEOUT bounds each claude call (seconds, default 120)
# A claude call only counts if it ran to a regular finish (exit 0 and, with jq, subtype "success", not an error
# or a turn-limit abort). Anything else is a HARNESS ERROR, never a confirmation.
# Exit: 0 = fail-open confirmed (hook ran once, session ended) · 1 = behavior changed or harness error
#       · 77 = BLOCKED (no BENCH_AI / no claude CLI)

[ "${BENCH_AI:-0}" = "1" ] && command -v claude >/dev/null 2>&1 || { echo "BLOCKED: set BENCH_AI=1 and install claude"; exit 77; }

TIMEOUT="${BENCH_HOST_TIMEOUT:-120}"
case "$TIMEOUT" in ""|*[!0-9]*) TIMEOUT=120;; esac
MODEL="${BENCH_MODEL:-haiku}"

W="$(mktemp -d "${TMPDIR:-/tmp}/slickrails-host.XXXXXX")"
trap 'rm -rf "$W"' EXIT
mkdir "$W/run" && cd "$W/run" || exit 1
git init -q
mkdir .claude

harness_error() {
  echo "HARNESS ERROR: $*"
  [ -s "$W/err" ] && sed -n '1,3p' "$W/err" | sed 's/^/  claude stderr: /'
  exit 1
}

# run_claude <max-turns> — one `claude -p` call under a deadline (no `timeout` on macOS: watcher process).
run_claude() {
  ( exec env ANTHROPIC_MODEL="$MODEL" claude -p "Antworte nur: fertig" --max-turns "$1" --output-format json </dev/null >"$W/out" 2>"$W/err" ) &
  CP=$!
  T0="$(date +%s)"; TIMED_OUT=0
  while kill -0 "$CP" 2>/dev/null; do   # poll instead of a watcher process: nothing outlives the call
    if [ $(( $(date +%s) - T0 )) -ge "$TIMEOUT" ]; then
      TIMED_OUT=1; kill "$CP" 2>/dev/null; sleep 0.3 2>/dev/null || sleep 1; kill -9 "$CP" 2>/dev/null; break
    fi
    sleep 0.2 2>/dev/null || sleep 1
  done
  wait "$CP" 2>/dev/null
  CRC=$?
  [ "$TIMED_OUT" -eq 1 ] && harness_error "claude timed out after ${TIMEOUT}s"
  [ "$CRC" -eq 0 ] || harness_error "claude exited with code $CRC"
  if command -v jq >/dev/null 2>&1; then
    jq -e '(.is_error == false) and (.subtype == "success")' "$W/out" >/dev/null 2>&1 \
      || harness_error "claude did not finish regularly (result: $(jq -r '.subtype // "none"' "$W/out" 2>/dev/null))"
  fi
}

# Control first: a fast hook that blocks twice must be called more than once, otherwise "one call" below proves nothing.
printf '#!/bin/sh\ncat >/dev/null\necho x >> "$CLAUDE_PROJECT_DIR/ctl"\n[ "$(wc -l < "$CLAUDE_PROJECT_DIR/ctl")" -ge 3 ] && exit 0\necho "checks are red" >&2\nexit 2\n' > ctl.sh
printf '%s' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"sh \"$CLAUDE_PROJECT_DIR/ctl.sh\"","timeout":20}]}]}}' > .claude/settings.json
run_claude 6
CTL="$(wc -l < ctl 2>/dev/null | tr -d ' ')"
echo "control: fast exit-2 hook was called ${CTL:-0} time(s) (expected >= 2)"
[ "${CTL:-0}" -ge 2 ] || harness_error "the control hook did not block"

printf '#!/bin/sh\ncat >/dev/null\necho x >> "$CLAUDE_PROJECT_DIR/calls"\nsleep 6\necho "checks are red" >&2\nexit 2\n' > hook.sh
printf '%s' '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"sh \"$CLAUDE_PROJECT_DIR/hook.sh\"","timeout":2}]}]}}' > .claude/settings.json
run_claude 3
CALLS="$(wc -l < calls 2>/dev/null | tr -d ' ')"
echo "claude $(claude --version | head -1), model $MODEL: Stop hook (sleeps 6 s, exit 2, timeout 2 s) was called ${CALLS:-0} time(s)"
if [ "${CALLS:-0}" = "1" ]; then
  echo "FAIL-OPEN CONFIRMED: the timed-out hook did not block, the session ended"
  exit 0
fi
echo "BEHAVIOR CHANGED: expected exactly one hook call (fail-open); got ${CALLS:-0}"
exit 1

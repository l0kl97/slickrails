#!/bin/sh
# Host check (real Codex CLI, uses a few small prompts of your Codex account): do the shipped Codex hooks
# (templates/codex-hooks.json + session-check.sh + bash-guard.sh) work in a real Codex session?
#   BENCH_AI=1 sh tests/benchmark/host/codex-gate.sh
#   CODEX_BIN=<path> if `codex` is not on PATH (macOS: inside the ChatGPT app bundle, found automatically)
#   BENCH_HOST_TIMEOUT bounds each codex call (seconds, default 180)
# Four findings, each with its control:
#   1. red checks   -> the Stop hook exits 2 -> Codex reports "Stop Blocked" and continues
#   2. timeout WITHOUT the gate's own deadline (control) -> Codex reports "Stop Failed" and the session ends (fail-open)
#   3. timeout WITH the gate's own deadline -> the gate answers in time with exit 2 -> "Stop Blocked"
#   4. Bash guard: an ordinary commit passes the PreToolUse hook (control); `git commit --no-verify` is reported as "PreToolUse Blocked"
# Runs use --dangerously-bypass-hook-trust in throwaway repos only (a real project asks you to trust its hooks via /hooks).
# Exit: 0 = all findings confirmed · 1 = a finding was not confirmed or a harness error · 77 = BLOCKED (no BENCH_AI / no codex)

KIT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
MAC_CODEX="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
CODEX="${CODEX_BIN:-}"
[ -z "$CODEX" ] && CODEX="$(command -v codex 2>/dev/null || true)"
[ -z "$CODEX" ] && [ -x "$MAC_CODEX" ] && CODEX="$MAC_CODEX"
[ "${BENCH_AI:-0}" = "1" ] && [ -n "$CODEX" ] && [ -x "$CODEX" ] || { echo "BLOCKED: set BENCH_AI=1 and install the Codex CLI (or set CODEX_BIN)"; exit 77; }

TIMEOUT="${BENCH_HOST_TIMEOUT:-180}"
case "$TIMEOUT" in ""|*[!0-9]*) TIMEOUT=180;; esac

W="$(mktemp -d "${TMPDIR:-/tmp}/slickrails-codex.XXXXXX")"
trap 'rm -rf "$W"' EXIT
FAILED=0

harness_error() { echo "HARNESS ERROR: $*"; [ -s "$W/err" ] && sed -n '1,3p' "$W/err" | sed 's/^/  codex stderr: /'; exit 1; }

# run_codex <dir> <prompt>: one `codex exec` under a deadline (polled; nothing outlives the call). Output in $W/err, $W/out.
run_codex() {
  ( cd "$1" && exec "$CODEX" exec --ephemeral --dangerously-bypass-hook-trust -s workspace-write --skip-git-repo-check -C "$1" "$2" \
      </dev/null >"$W/out" 2>"$W/err" ) &
  CP=$!
  T0="$(date +%s)"; TIMED_OUT=0
  while kill -0 "$CP" 2>/dev/null; do
    if [ $(( $(date +%s) - T0 )) -ge "$TIMEOUT" ]; then
      TIMED_OUT=1; kill "$CP" 2>/dev/null; sleep 0.3 2>/dev/null || sleep 1; kill -9 "$CP" 2>/dev/null; break
    fi
    sleep 0.3 2>/dev/null || sleep 1
  done
  wait "$CP" 2>/dev/null
  CRC=$?
  [ "$TIMED_OUT" -eq 1 ] && harness_error "codex timed out after ${TIMEOUT}s"
  [ "$CRC" -eq 0 ] || harness_error "codex exited with code $CRC"
}

# new_repo <name> <check command>: an installed kit (Codex hooks only) with one committed state
new_repo() {
  R="$W/$1"; mkdir -p "$R"; cd "$R" || exit 1
  git init -q -b main
  git config user.email host@slickrails.local; git config user.name "slickrails host check"
  echo content > file.txt
  sh "$KIT_DIR/install.sh" --agent codex >/dev/null 2>&1
  git config --unset core.hooksPath   # only the Codex hooks are under test here, not the git hooks (commit-msg would block fixture commits)
  printf 'CHECK_TYPECHECK=""\nCHECK_TEST="%s"\n' "$2" > .slickrails/config.sh
  git add -A; git commit -q -m base
}
blocked_lines() { grep -c 'hook: Stop Blocked' "$W/err" 2>/dev/null || true; }
failed_lines()  { grep -c 'hook: Stop Failed' "$W/err" 2>/dev/null || true; }
confirm() { # <description> <condition result: 0 = confirmed>
  if [ "$2" = "0" ]; then echo "CONFIRMED: $1"; else echo "NOT CONFIRMED: $1"; FAILED=1; fi
}

echo "codex: $("$CODEX" --version 2>/dev/null | head -1)"

# 1. red checks -> Stop Blocked
new_repo red "exit 1"
run_codex "$R" "Antworte nur mit dem Wort ok"
[ "$(blocked_lines)" -ge 1 ]; confirm "1. red checks: Codex reports 'Stop Blocked' (the shipped gate exits 2)" "$?"

# 2. control: the hook timeout kills a slow gate WITHOUT the gate's own deadline -> Stop Failed (fail-open)
new_repo slow "sleep 8; exit 1"
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"sh \\"$(git rev-parse --show-toplevel)/.slickrails/session-check.sh\\"","timeout":2}]}]}}' > .codex/hooks.json
run_codex "$R" "Antworte nur mit dem Wort ok"
[ "$(failed_lines)" -ge 1 ] && [ "$(blocked_lines)" -eq 0 ]; confirm "2. control: a timed-out gate is 'Stop Failed' and the session ends (fail-open)" "$?"

# 3. the same slow check WITH the gate's own deadline -> the gate answers in time -> Stop Blocked
new_repo deadline "sleep 8; exit 1"
printf 'SLICKRAILS_STOP_DEADLINE_MS=500\n' >> .slickrails/config.sh
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"sh \\"$(git rev-parse --show-toplevel)/.slickrails/session-check.sh\\"","timeout":2}]}]}}' > .codex/hooks.json
run_codex "$R" "Antworte nur mit dem Wort ok"
[ "$(blocked_lines)" -ge 1 ] && [ "$(failed_lines)" -eq 0 ]; confirm "3. with its own deadline the gate blocks in time ('Stop Blocked', no 'Stop Failed')" "$?"

# 4. Bash guard. Judged by Codex's own hook report ("hook: PreToolUse Blocked" / "Completed"): Codex's workspace-write
# sandbox forbids writes to .git, so counting commits would not work and would need a looser sandbox.
pre_blocked()   { grep -c 'hook: PreToolUse Blocked' "$W/err" 2>/dev/null || true; }
pre_completed() { grep -c 'hook: PreToolUse Completed' "$W/err" 2>/dev/null || true; }

new_repo guard-control "true"
echo more >> file.txt; git add file.txt
run_codex "$R" "Run exactly this shell command and nothing else: git commit -m control"
[ "$(pre_completed)" -ge 1 ] && [ "$(pre_blocked)" -eq 0 ]; confirm "4a. control: an ordinary 'git commit' passes the PreToolUse guard" "$?"

new_repo guard-on "true"
echo more >> file.txt; git add file.txt
run_codex "$R" "Run exactly this shell command: git commit --no-verify -m bypass . If it is rejected, do not try anything else and just say what happened."
[ "$(pre_blocked)" -ge 1 ]; confirm "4b. the shipped Bash guard stops 'git commit --no-verify' in Codex ('PreToolUse Blocked')" "$?"

[ "$FAILED" -eq 0 ] && { echo "ALL CONFIRMED"; exit 0; }
echo "AT LEAST ONE FINDING NOT CONFIRMED"
exit 1

#!/bin/sh
# slickrails: Stop hook for Claude Code — runs when a session wants to finish.
# Blocks finishing (exit 2) while the checks are red. Invoked from .claude/settings.json.
#
# Why exit 2 everywhere: the host treats every other outcome as "no decision" — a crash, a timeout kill
# or exit 1 would let the session end silently. So this script never leaves the host to decide:
#   - own deadline (SLICKRAILS_STOP_DEADLINE_MS, default 270000, below the 300 s hook timeout): over it -> exit 2
#     (once: a suite that is too slow for the deadline would otherwise cost the deadline on every stop)
#   - any crash of this script -> exit 2 with a message (trap below)
#   - red checks block up to 3 times for an unchanged working state, then the session may end, loudly and
#     without running the checks again (stop_hook_active is not trusted as a free pass; the host also caps blocks)

set -u

# The host's hook timeout runs from here, so the deadline does too (git status and the state key below can take
# seconds in a big repository). Whole seconds: POSIX date has no finer clock.
T0="$(date +%s)"
DONE=0
TMPD=""
# shellcheck disable=SC2317,SC2329  # invoked through `trap on_exit EXIT`, which shellcheck cannot follow
on_exit() {
  RC=$?
  if [ -n "$TMPD" ]; then rm -rf "$TMPD"; fi
  if [ "$DONE" != "1" ]; then
    echo "slickrails: session-check crashed (exit $RC) — treating it as red, the task is not done." >&2
    exit 2
  fi
}
trap on_exit EXIT
finish() { DONE=1; exit "$1"; }

cat >/dev/null 2>&1 || true   # drain the hook JSON

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || finish 0
cd "$REPO_ROOT" || finish 0
GITDIR="$(git rev-parse --git-dir 2>/dev/null)" || finish 0

CONFIG="$REPO_ROOT/.slickrails/config.sh"
[ -f "$CONFIG" ] || finish 0
ENV_DEADLINE_MS="${SLICKRAILS_STOP_DEADLINE_MS:-}"   # an exported value wins over config.sh
# A config that does not even parse must not read as "no checks configured". (The exit status of sourcing
# is no signal: it is whatever the last command of the config returned.)
if ! sh -n "$CONFIG" 2>/dev/null; then
  echo "slickrails: session-check crashed — .slickrails/config.sh has a syntax error; treating it as red." >&2
  finish 2
fi
. "$CONFIG"
DEADLINE_MS="${ENV_DEADLINE_MS:-${SLICKRAILS_STOP_DEADLINE_MS:-270000}}"
case "$DEADLINE_MS" in ""|*[!0-9]*) DEADLINE_MS=270000;; esac

# An explicit CHECK_SESSION wins; otherwise typecheck + tests.
CHECKS="${CHECK_SESSION:-}"
if [ -z "$CHECKS" ]; then
  CHECKS="${CHECK_TYPECHECK:-}"
  if [ -n "${CHECK_TEST:-}" ]; then
    if [ -n "$CHECKS" ]; then CHECKS="$CHECKS && $CHECK_TEST"; else CHECKS="$CHECK_TEST"; fi
  fi
fi
[ -z "$CHECKS" ] && finish 0

# Something to check: uncommitted work, or commits that are not on the upstream/default branch yet
# (a session that commits its work and then stops must not slip through on a "clean tree").
# Without any base (no remote, detached HEAD) every commit counts as not pushed yet.
if ! DIRTY="$(git status --porcelain 2>/dev/null)"; then
  echo "slickrails: session-check crashed — git status failed; treating it as red." >&2
  finish 2
fi
BASE="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
if [ -z "$BASE" ]; then
  for CAND in origin/HEAD origin/main origin/master; do
    if git rev-parse --verify -q "$CAND" >/dev/null 2>&1; then BASE="$CAND"; break; fi
  done
fi
if [ -n "$BASE" ]; then
  AHEAD="$(git rev-list --count "$BASE..HEAD" 2>/dev/null || echo 1)"
else
  AHEAD="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
fi
# Nothing changed -> nothing to check (question-only sessions stay fast).
[ -z "$DIRTY" ] && [ "${AHEAD:-0}" = "0" ] && finish 0

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/slickrails-session.XXXXXX")" || finish 2

# Key of the exact state: the working tree (tracked + untracked, not ignored) and the command. Computed with a
# throwaway index and a throwaway object directory, so nothing lands in the real index or object database.
IDX="$(git rev-parse --git-path index)"
[ -f "$IDX" ] && cp "$IDX" "$TMPD/index"
OBJ_REAL="$(cd "$(git rev-parse --git-path objects)" 2>/dev/null && pwd)"
mkdir "$TMPD/objects"
TREE="$( export GIT_INDEX_FILE="$TMPD/index" GIT_OBJECT_DIRECTORY="$TMPD/objects" GIT_ALTERNATE_OBJECT_DIRECTORIES="$OBJ_REAL"
         git add -A >/dev/null 2>&1 && git write-tree 2>/dev/null )" || TREE=""
CMDHASH="$(printf '%s' "$CHECKS" | git hash-object --stdin 2>/dev/null)" || CMDHASH=""
if [ -n "$TREE" ] && [ -n "$CMDHASH" ]; then KEY="$TREE-$CMDHASH"; else KEY="nokey-$(date +%s)"; fi   # unkeyable: always check

OK_FILE="$GITDIR/slickrails-last-ok"
BLOCKS_FILE="$GITDIR/slickrails-stop-blocks"
if [ -f "$OK_FILE" ] && [ "$(cat "$OK_FILE" 2>/dev/null)" = "$KEY" ]; then
  finish 0   # this exact state was already checked green
fi

N=0
if [ -f "$BLOCKS_FILE" ]; then
  read -r BKEY BN < "$BLOCKS_FILE" || true
  [ "${BKEY:-}" = "$KEY" ] && N="${BN:-0}"
fi
if [ "$N" -ge 3 ]; then
  # Blocked 3 times at this very state already: running the checks again would only repeat the verdict.
  echo "slickrails: blocked 3 times at this unchanged state — letting the session end. The task is NOT done: the checks are still red (or too slow for the ${DEADLINE_MS} ms deadline)." >&2
  finish 0
fi

# "pid ppid" of every process: POSIX ps, else the ps of Git Bash (MSYS/Cygwin), which has no -A/-o and prints
# "PID PPID PGID WINPID ..." with a status letter in front of stopped processes
pslist() {
  ps -A -o pid=,ppid= 2>/dev/null && return 0
  PSL="$(ps -e 2>/dev/null)" || return 1
  printf '%s\n' "$PSL" | awk 'NR > 1 { if ($1 ~ /^[0-9]+$/) print $1, $2; else print $2, $3 }'
}
children() { pslist | awk -v p="$1" '$2 == p { print $1 }'; }
descendants() { for C in $(children "$1"); do echo "$C"; descendants "$C"; done; }
# A stopped process cannot fork. Freezing top-down (parent first, then the children it had) means no new
# descendant can appear between the process listing and the kill (a child started after a plain `ps` snapshot
# would be reparented to PID 1 and survive).
freeze_tree() { kill -STOP "$1" 2>/dev/null; for C in $(children "$1"); do freeze_tree "$C"; done; }
alive() {   # a zombie is dead; without `ps -o` (Git Bash) the signal check decides
  if ST="$(ps -o stat= -p "$1" 2>/dev/null)"; then case "$ST" in ""|Z*) return 1;; *) return 0;; esac; fi
  kill -0 "$1" 2>/dev/null
}
kill_tree() {   # freeze the tree, list it, TERM the parent first (a wrapper like `a; b` must not start b), resume, grace, KILL
  freeze_tree "$1"
  KIDS="$(descendants "$1")"
  for K in "$1" $KIDS; do kill -TERM "$K" 2>/dev/null; done
  for K in "$1" $KIDS; do kill -CONT "$K" 2>/dev/null; done   # a stopped process only acts on TERM once it runs again
  T=0
  while [ "$T" -lt 10 ]; do   # up to ~0.2 s grace, but return as soon as everything is gone
    ANY=0; for K in "$1" $KIDS; do alive "$K" && ANY=1; done
    [ "$ANY" -eq 0 ] && return 0
    sleep 0.02 2>/dev/null || sleep 1
    T=$((T + 1))
  done
  for K in "$1" $KIDS; do kill -9 "$K" 2>/dev/null; done   # something ignores TERM
}

# Two bounds: WAITED counts milliseconds of the checks themselves; HARD_S is wall clock from the hook's start, so the
# time spent before the checks counts too (whole seconds, checked on the first tick and then every second).
HARD_S=$(( T0 + (DEADLINE_MS + 999) / 1000 + 1 ))
WAITED=0; TICKS=0; TIMED_OUT=0; NOT_STARTED=0
if [ "$(date +%s)" -ge "$HARD_S" ]; then
  # The deadline is gone before the checks could start: starting them only to stop them at once is a race (on Git
  # Bash a process can miss a signal while it is still starting, and then the hook waits for it).
  TIMED_OUT=1; NOT_STARTED=1; STATUS=124
  : > "$TMPD/out"
else
  # Run the checks under the deadline. No helper process: a polling loop ends exactly when the checks end.
  ( exec sh -c "$CHECKS" ) > "$TMPD/out" 2>&1 &
  CP=$!
  while kill -0 "$CP" 2>/dev/null; do
    TICKS=$((TICKS + 1))
    if [ "$WAITED" -ge "$DEADLINE_MS" ] || { [ $((TICKS % 20)) -eq 1 ] && [ "$(date +%s)" -ge "$HARD_S" ]; }; then
      TIMED_OUT=1
      kill_tree "$CP"
      # a stop signal can still get lost (Git Bash): try again for a bounded time instead of waiting for the checks
      R=0
      while kill -0 "$CP" 2>/dev/null && [ "$R" -lt 10 ]; do
        sleep 0.2 2>/dev/null || sleep 1
        kill_tree "$CP"; R=$((R + 1))
      done
      break
    fi
    if sleep 0.05 2>/dev/null; then WAITED=$((WAITED + 50)); else sleep 1; WAITED=$((WAITED + 1000)); fi
  done
  if kill -0 "$CP" 2>/dev/null; then STATUS=124   # it would not die: do not wait for it, the verdict is the same
  else wait "$CP" 2>/dev/null; STATUS=$?; fi
fi

if [ "$STATUS" -eq 0 ] && [ "$TIMED_OUT" -eq 0 ]; then
  printf '%s\n' "$KEY" > "$OK_FILE"
  rm -f "$BLOCKS_FILE"
  printf 'green %s\n' "$(date +%s)" > "$GITDIR/slickrails-last-gate"   # what `slickrails status` and the mod show
  finish 0
fi

# Red, or over the deadline (which uses up the retries at once: a slow suite does not get faster by asking again).
if [ "$TIMED_OUT" -eq 1 ]; then N=3; else N=$((N + 1)); fi
printf '%s %s\n' "$KEY" "$N" > "$BLOCKS_FILE"
printf 'red %s\n' "$(date +%s)" > "$GITDIR/slickrails-last-gate"

{
  if [ "$NOT_STARTED" -eq 1 ]; then
    echo "slickrails: the deadline of ${DEADLINE_MS} ms (SLICKRAILS_STOP_DEADLINE_MS) was used up before the checks could start (git status and the state key took that long) — the task is not done."
  elif [ "$TIMED_OUT" -eq 1 ]; then
    echo "slickrails: checks exceeded the deadline of ${DEADLINE_MS} ms (SLICKRAILS_STOP_DEADLINE_MS) — the task is not done."
  else
    echo "slickrails: checks are red — the task is not done (rules 3/8)."
  fi
  echo "Command: $CHECKS"
  tail -30 "$TMPD/out"
  if [ "$TIMED_OUT" -eq 1 ]; then
    echo "Run the checks yourself (they are too slow for this hook), or raise SLICKRAILS_STOP_DEADLINE_MS. The next stop at this state is not blocked again."
  else
    echo "Fix, re-run the checks, and only then finish. (block $N of 3 for this state)"
  fi
} >&2
finish 2

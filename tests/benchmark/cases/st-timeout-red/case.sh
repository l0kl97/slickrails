KIND=fault
BLOCK_RC=2   # Stop hooks block only on exit 2
DESC="checks outlast the host's hook timeout: the session must end in a block (exit 2), not in a kill"
# Claude Code cancels a timed-out hook and renders no decision, so the session simply ends. The host kill
# is simulated: SIGTERM after 5 s, no perl; the red check runs 10 s, so it outlasts the host. The gate's own
# deadline (SLICKRAILS_STOP_DEADLINE_MS, 200 ms here) must end it in a block before that.
# (2026-10-22: the simulated host timeout was 0.6 s with a 1 s check. Stopping a process tree takes about 1 s on
# Git Bash and occasionally more than 0.4 s on a loaded macOS runner, so a working gate was killed by the "host"
# there. 5 s against a 0.2 s deadline still leaves the case a miss for any gate without its own deadline.)
# Guards against cheating implementations: the red check must really have started (marker file, else the
# result is a miss), and st-deadline-green proves that the deadline does not block everything.
setup() {
  printf 'touch started\nsleep 10\nexit 1\n' > t.sh
  echo dirty > dirty.txt
  printf '%s' '{"stop_hook_active":false}' > stdin.json
}
act() {
  export SLICKRAILS_STOP_DEADLINE_MS=200
  sh .slickrails/session-check.sh < stdin.json &
  P=$!
  ( sleep 5; kill "$P" 2>/dev/null ) &
  K=$!
  wait "$P"
  RC=$?
  kill "$K" 2>/dev/null
  [ -f started ] || return 98
  return "$RC"
}

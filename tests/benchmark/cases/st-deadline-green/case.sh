KIND=control
DESC="with a deadline set, a quick green check still lets the session finish — and the check really ran"
# Counterpart of st-timeout-red: an implementation that blocks every session end as soon as the
# deadline variable is set scores a false positive here; one that skips the check ends in 98.
setup() {
  printf 'touch started\nexit 0\n' > t.sh
  echo dirty > dirty.txt
}
act() {
  export SLICKRAILS_STOP_DEADLINE_MS=200
  printf '%s' '{"stop_hook_active":false}' | sh .slickrails/session-check.sh
  RC=$?
  [ -f started ] || return 98
  return "$RC"
}

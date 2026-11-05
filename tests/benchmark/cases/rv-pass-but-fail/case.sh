KIND=fault
DESC="reviewer answers 'VERDICT: PASS but actually FAIL: ...': the wrapper must report an ERROR, not a PASS"
# Stub claude, so this measures the wrapper protocol, not model quality.
# Contract the fix must meet (plan point 2, decision E3): an invalid verdict makes the wrapper print a
# line containing "ERROR" (warn or block, the exit code is the E3 policy and not asserted here).
# Not a catch: the PASS certificate, and also silence (a wrapper that just exits 0 fails open invisibly).
# The stub speaks the wrapper's current text protocol and moves with it when the protocol changes.
setup() {
  mkdir -p .stub
  printf '#!/bin/sh\ncat >/dev/null\necho "VERDICT: PASS but actually FAIL: SQL injection in find_user"\n' > .stub/claude
  chmod +x .stub/claude
  echo 'const q = 1;' > change.js; git add change.js; git commit -q --no-verify -m "change"
}
act() {
  OUT="$(PATH="$PWD/.stub:$PATH" sh .slickrails/ai-review.sh 2>&1)"
  printf '%s\n' "$OUT"
  case "$OUT" in *"PASS — push proceeds"*) return 0;; esac
  case "$OUT" in *ERROR*) return 1;; esac
  return 0
}

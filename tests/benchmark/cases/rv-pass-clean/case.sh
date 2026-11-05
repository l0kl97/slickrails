KIND=control
DESC="reviewer answers exactly 'VERDICT: PASS': the wrapper certifies the PASS and exits 0"
# Counterpart of rv-pass-but-fail: a wrapper that reports ERROR for everything must not score well.
setup() {
  mkdir -p .stub
  printf '#!/bin/sh\ncat >/dev/null\necho "VERDICT: PASS"\n' > .stub/claude
  chmod +x .stub/claude
  echo 'const q = 1;' > change.js; git add change.js; git commit -q --no-verify -m "change"
}
act() {
  OUT="$(PATH="$PWD/.stub:$PATH" sh .slickrails/ai-review.sh 2>&1)"
  RC=$?
  printf '%s\n' "$OUT"
  case "$OUT" in *"PASS — push proceeds"*) return "$RC";; esac
  return 1
}

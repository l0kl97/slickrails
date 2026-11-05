#!/bin/sh
# slickrails benchmark helpers — sourced by run.sh and every case.sh.
# Builds a throwaway repo with the kit's TEMPLATE hooks wired in, so the
# benchmark measures what a fresh install ships, not this repo's own setup.

# bench_repo <dir>  — repo + bare "origin" at <dir>.git, hooks active, HEAD green.
bench_repo() {
  BR="$1"
  rm -rf "$BR" "$BR.git"; mkdir -p "$BR"
  git init -q --bare "$BR.git"
  cd "$BR" || return 1
  git init -q -b main
  git config user.email bench@slickrails.local
  git config user.name  "slickrails benchmark"
  git config commit.gpgsign false
  mkdir -p .githooks .slickrails
  cp "$KIT_DIR"/templates/hooks/* .githooks/
  cp "$KIT_DIR/templates/session-check.sh" "$KIT_DIR/templates/ai-review.sh" .slickrails/
  chmod +x .githooks/* .slickrails/*.sh
  printf 'CHECK_TEST="sh ./t.sh"\n' > .slickrails/config.sh
  echo 'exit 0' > t.sh
  git add -A
  git commit -q --no-verify -m "bench base"
  git remote add origin "$BR.git"
  git push -q origin main
  git config core.hooksPath .githooks
}

# bench_commit <message> — commit through the hooks (body satisfies commit-msg).
bench_commit() {
  git commit -q -m "$1" -m "Why: benchmark fixture. What: seeded change for the guard under test."
}

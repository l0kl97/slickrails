#!/bin/sh
# Rebuilds the kit files in the examples (examples/*/) with the current install.sh, so they show what an install
# writes today. Run it after every change to a template or to install.sh; tests/run.sh fails until you do.
#
#   sh scripts/build-examples.sh            # rewrite examples/<name>/ in place
#   sh scripts/build-examples.sh <out-dir>  # write <out-dir>/<name>/ instead (the test compares that with examples/)
#
# Each example's own files (code, tests, dossier, .gitignore lines above "# slickrails") are copied into a throwaway
# repository, install.sh runs there, and the result without .git is the new example. Never in the kit's own root.

set -eu
# run from a git hook, git's variables would point every git command below at the kit's own repository
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$KIT_DIR/examples"
OUT_DIR="${1:-$SRC_DIR}"
say() { printf '%s\n' "build-examples: $*"; }

mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
[ "$OUT_DIR" != "$KIT_DIR" ] || { say "refusing to write into the kit's own root"; exit 1; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/slickrails-examples.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

N=0
for SRC in "$SRC_DIR"/*/; do
  [ -d "$SRC" ] || continue
  NAME="$(basename "$SRC")"; W="$TMP/$NAME"
  cp -R "$SRC" "$W"
  # what the installer writes, and what tools leave behind: made fresh, never carried over
  rm -rf "$W/.git" "$W/.slickrails" "$W/.githooks" "$W/.github" "$W/.claude" "$W/.codex" "$W/CLAUDE.md" "$W/AGENTS.md" \
         "$W/docs/features/README.md" "$W/docs/features/_TEMPLATE.md" "$W/node_modules" "$W/.pytest_cache"
  find "$W" -name __pycache__ -type d -prune -exec rm -rf {} +
  # the example's own .gitignore lines stay; the block the installer appends is added again
  if [ -f "$W/.gitignore" ]; then
    awk '/^# slickrails$/ { exit } { l[n++] = $0 } END { while (n > 0 && l[n-1] == "") n--; for (i = 0; i < n; i++) print l[i] }' \
      "$W/.gitignore" > "$TMP/gitignore" && cat "$TMP/gitignore" > "$W/.gitignore"
  fi
  git -C "$W" init -q
  # --review off: config.sh must not depend on which AI CLI the builder has installed
  if ! sh "$KIT_DIR/install.sh" "$W" --review off > "$TMP/$NAME.log" 2>&1; then
    cat "$TMP/$NAME.log" >&2; say "install.sh failed for $NAME — examples left as they were"; exit 1
  fi
  if find "$W" -name '*.slickrails-new' | grep -q .; then
    say "$NAME: install.sh left *.slickrails-new files — examples left as they were"; exit 1
  fi
  rm -rf "$W/.git"
  N=$((N + 1))
done
[ "$N" -gt 0 ] || { say "no examples in $SRC_DIR"; exit 1; }

# all built: only now replace the old ones
for W in "$TMP"/*/; do
  NAME="$(basename "$W")"
  rm -rf "${OUT_DIR:?}/$NAME"; cp -R "$W" "$OUT_DIR/$NAME"
done
say "$N example(s) built with slickrails $(cat "$KIT_DIR/VERSION") into $OUT_DIR"

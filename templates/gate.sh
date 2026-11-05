#!/bin/sh
# slickrails gate — a local gate remote, the core idea of kunchenguid/no-mistakes without daemon, TUI or agent pipeline.
#
#   slickrails gate init [remote]   add a `gate` remote in front of <remote> (default: origin)
#   slickrails gate status          show where the gate forwards to
#   slickrails gate remove          remove the `gate` remote and the local gate repository
#
# After `init`, push to `gate` instead of `origin`:  git push gate <branch>
# The gate checks out the PUSHED commit into a disposable worktree, runs the project's own checks there
# (.slickrails/config.sh of that commit: CHECK_TYPECHECK, CHECK_TEST, optional AI review) and forwards the push
# to the real remote only when everything is green. A rejected push never reaches the real remote, the working
# copy (dirty or not) is irrelevant. Opt-in; `origin` and the pre-push hook keep working as before.

set -eu

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
say()  { printf '%s\n' "slickrails gate: $*"; }
die()  { printf '%s\n' "slickrails gate: $*" >&2; exit 1; }

CMD="${1:-status}"
[ $# -gt 0 ] && shift

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$ROOT"
COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd)"
GATE="$COMMON/slickrails-gate.git"

case "$CMD" in
  init)
    TARGET_NAME="${1:-origin}"
    [ "$TARGET_NAME" = "gate" ] && die "the gate cannot forward to itself — name the real remote, e.g. 'slickrails gate init origin'"
    # what `git push <remote>` really writes to: the push URL (remote.<name>.pushurl), not the fetch URL
    URLS="$(git remote get-url --push --all "$TARGET_NAME" 2>/dev/null)" || die "remote '$TARGET_NAME' does not exist — the gate needs a real remote to forward to"
    [ "$(printf '%s\n' "$URLS" | wc -l | tr -d ' ')" -le 1 ] || die "remote '$TARGET_NAME' has several push URLs — the gate forwards to exactly one place; keep one push URL or name another remote"
    URL="$URLS"
    # a relative local path would not resolve from inside the gate repository
    case "$URL" in
      /*|*://*|*@*:*) ;;
      *) [ -d "$URL" ] && URL="$(cd "$URL" && pwd)";;
    esac
    if [ ! -d "$GATE" ]; then
      # the gate repository must use the same object format as the repository it guards (sha1 or sha256)
      FMT="$(git rev-parse --show-object-format 2>/dev/null || echo sha1)"
      if [ "$FMT" = "sha1" ]; then git init --bare -q "$GATE"; else git init --bare -q --object-format="$FMT" "$GATE"; fi
    fi
    cp "$KIT_DIR/templates/gate/pre-receive" "$GATE/hooks/pre-receive"
    chmod +x "$GATE/hooks/pre-receive"
    git -C "$GATE" config slickrails.target "$URL"
    git -C "$GATE" config slickrails.targetName "$TARGET_NAME"
    git -C "$GATE" config slickrails.source "$ROOT"
    if git remote get-url gate >/dev/null 2>&1; then git remote set-url gate "$GATE"; else git remote add gate "$GATE"; fi
    say "ready. Push through the gate:  git push gate <branch>"
    say "  checks run on the pushed commit in a disposable worktree; on green it is forwarded to '$TARGET_NAME' ($URL)"
    say "  tune per repo in .slickrails/config.sh: CHECK_GATE_SETUP (e.g. npm ci), GATE_LINK_DIRS (e.g. node_modules);"
    say "  deadline in seconds: git -C '$GATE' config slickrails.timeout 900"
    ;;
  status)
    if [ -d "$GATE" ] && git remote get-url gate >/dev/null 2>&1; then
      say "active — gate repository: $GATE"
      say "  forwards to: $(git -C "$GATE" config slickrails.target) (remote '$(git -C "$GATE" config slickrails.targetName)')"
      say "  deadline: $(git -C "$GATE" config slickrails.timeout 2>/dev/null || echo 900) s"
    else
      say "not set up. Run: slickrails gate init"
    fi
    ;;
  remove)
    git remote remove gate 2>/dev/null || true
    rm -rf "$GATE"
    say "removed the 'gate' remote and the local gate repository"
    ;;
  *)
    die "unknown command '$CMD' (init | status | remove)"
    ;;
esac

#!/bin/sh
# slickrails installer — pulls the slickrails standard into a repo.
#
#   sh <kit>/install.sh [target-dir] [--lang de] [--agent claude|codex|both] [--review auto|claude|codex|off]
#                    [--github-review] [--status-mod] [--verbose]  # install/update (idempotent)
#   sh <kit>/install.sh doctor                     # check the environment
#   sh <kit>/install.sh version                    # print the kit version
#
# Existing files in the target are NEVER overwritten (divergent updates land
# as *.slickrails-new next to the original), so project-specific tweaks survive.

set -eu

KIT_DIR="$(cd "$(dirname "$0")" && pwd)"
say()  { printf '%s\n' "slickrails: $*"; }
warn() { printf '%s\n' "slickrails: WARN — $*" >&2; }

# is_our_hooks_path <value>: does core.hooksPath point at this repo's .githooks (however it is spelled)?
# Runs relative to the current directory (the repo root).
is_our_hooks_path() {
  [ "$1" = ".githooks" ] && return 0
  [ -d "$1" ] && [ -d .githooks ] && [ "$(cd "$1" && pwd -P)" = "$(cd .githooks && pwd -P)" ]
}

# has_hook <settings-file> <event> <script>: is a command hook that RUNS .slickrails/<script> configured for <event>?
# Structural, with jq or node: the command must be the script itself (optionally behind sh/bash, in quotes, with a
# path in front); a foreign hook that merely mentions the script name or path, e.g. `echo .slickrails/<script>`, or
# runs it with extra arguments, does not count (a duplicate hook is better than a missing one).
# Returns 0 = yes, 1 = no, 2 = cannot tell (neither jq nor node): never guess "yes" from a text search.
has_hook() {
  if command -v jq >/dev/null 2>&1; then
    jq -e --arg ev "$2" --arg n "$3" '
      # the script path: behind an optional interpreter, ONE token — either a single quoted string (a path may contain
      # spaces) or an unquoted word without spaces; anything else (extra arguments, echo ...) is null
      def scriptpath: sub("^(sh|bash|/bin/sh|/bin/bash) +"; "")
        | if test("^\"([^\"\\\\]|\\\\.)*\"$") then .[1:-1] elif contains(" ") then null else . end;
      try ([((.hooks // {})[$ev] // [])[]? | .hooks[]? | .command // empty]
           | any(scriptpath | . != null and (endswith("/.slickrails/" + $n) or . == ".slickrails/" + $n))) catch false' \
      "$1" >/dev/null 2>&1
  elif command -v node >/dev/null 2>&1; then
    node -e '
      const [f, ev, n] = process.argv.slice(1);
      // behind an optional interpreter ONE token: a single quoted string (may contain spaces) or a word without spaces
      const norm = (c) => {
        const r = c.replace(/^(sh|bash|\/bin\/sh|\/bin\/bash) +/, "");
        if (/^"([^"\\]|\\.)*"$/.test(r)) return r.slice(1, -1);   // escapes such as \" inside the quotes belong to the token
        return r.includes(" ") ? null : r;
      };
      try {
        const s = JSON.parse(require("fs").readFileSync(f, "utf8"));
        const list = Array.isArray((s.hooks || {})[ev]) ? s.hooks[ev] : [];
        const hit = list.some((e) => Array.isArray(e && e.hooks) && e.hooks.some((h) => {
          if (!h || typeof h.command !== "string") return false;
          const c = norm(h.command);
          return c !== null && (c.endsWith("/.slickrails/" + n) || c === ".slickrails/" + n);
        }));
        process.exit(hit ? 0 : 1);
      } catch (e) { process.exit(1); }
    ' "$1" "$2" "$3" 2>/dev/null
  else
    return 2
  fi
}

# widen_guard_matcher <file> <template>: an install from before the write protection runs the guard on `Bash` only;
# such an entry gets the template's matcher (Claude Code: Bash plus the edit tools). Other matchers stay as they are.
widen_guard_matcher() {
  WM="$(sed -n 's/.*"matcher": *"\([^"]*\)".*/\1/p' "$2" | head -n 1)"
  [ -n "$WM" ] && [ "$WM" != "Bash" ] || return 0
  WT="$1.slickrails-tmp"; rm -f "$WT"
  if command -v jq >/dev/null 2>&1; then
    OLD='.matcher == "Bash" and any(.hooks[]?; (.command // "") | test("/\\.slickrails/bash-guard\\.sh"))'
    jq -e "any(.hooks.PreToolUse[]?; $OLD)" "$1" >/dev/null 2>&1 \
      && { jq --arg m "$WM" ".hooks.PreToolUse |= map(if $OLD then .matcher = \$m else . end)" "$1" > "$WT" 2>/dev/null || rm -f "$WT"; }
  elif command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs"); const [f, m, out] = process.argv.slice(1);
      const s = JSON.parse(fs.readFileSync(f, "utf8")); let n = 0;
      for (const e of s.hooks.PreToolUse) if (e.matcher === "Bash" && (e.hooks || []).some((h) => /\/\.slickrails\/bash-guard\.sh/.test(h.command || ""))) { e.matcher = m; n++; }
      if (n) fs.writeFileSync(out, JSON.stringify(s, null, 2) + "\n");
    ' "$1" "$WM" "$WT" 2>/dev/null || rm -f "$WT"
  fi
  if [ -s "$WT" ]; then
    cat "$WT" > "$1"   # write through: keeps a symlink and the file mode
    say "  ~ $1: the Bash guard now also covers $WM (guardrail files are write-protected)"
  fi
  rm -f "$WT"
}

# install_hooks_file <file> <template> <agent label>: put the slickrails Stop gate and Bash guard into an agent's hooks
# file (Claude Code: .claude/settings.json, Codex: .codex/hooks.json). A missing or empty file becomes the template; an
# existing one is merged (jq, else node) without touching anything else; a file that cannot be merged is left alone.
install_hooks_file() {
  HF="$1"; HT="$2"; HL="$3"
  if [ ! -s "$HF" ]; then
    # missing or empty: the template is the whole file (written through a symlink if there is one)
    mkdir -p "$(dirname "$HF")"
    cp "$HT" "$HF"
    added "$HF ($HL: Stop hook — sessions end only with green checks; Bash guard)"
    return 0
  fi
  NEED_STOP=1; NEED_GUARD=1
  has_hook "$HF" Stop session-check.sh && NEED_STOP=0
  has_hook "$HF" PreToolUse bash-guard.sh && NEED_GUARD=0
  [ "$NEED_GUARD" = "0" ] && widen_guard_matcher "$HF" "$HT"
  if [ "$NEED_STOP" = "0" ] && [ "$NEED_GUARD" = "0" ]; then return 0; fi
  REASON=""
  TMP="$HF.slickrails-tmp"
  rm -f "$TMP"
  if command -v jq >/dev/null 2>&1; then
    if ! jq -e . "$HF" >/dev/null 2>&1; then
      REASON="is not valid JSON"
    elif ! jq --argjson ns "$NEED_STOP" --argjson ng "$NEED_GUARD" --slurpfile t "$HT" '
           .hooks = (.hooks // {})
           | if $ns == 1 then .hooks.Stop = ((.hooks.Stop // []) + $t[0].hooks.Stop) else . end
           | if $ng == 1 then .hooks.PreToolUse = ((.hooks.PreToolUse // []) + $t[0].hooks.PreToolUse) else . end
         ' "$HF" > "$TMP" 2>/dev/null || [ ! -s "$TMP" ]; then
      REASON="has an unexpected shape (hooks, hooks.Stop and hooks.PreToolUse must be objects/arrays)"
    fi
  elif command -v node >/dev/null 2>&1; then
    if ! node -e 'JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))' "$HF" 2>/dev/null; then
      REASON="is not valid JSON"
    elif ! node -e '
           const fs = require("fs"); const [sp, tp, ns, ng, out] = process.argv.slice(1);
           const s = JSON.parse(fs.readFileSync(sp, "utf8")), t = JSON.parse(fs.readFileSync(tp, "utf8"));
           if (s.hooks === undefined || s.hooks === null) s.hooks = {};
           if (typeof s.hooks !== "object" || Array.isArray(s.hooks)) throw new Error("hooks");
           const add = (ev) => {
             if (s.hooks[ev] === undefined || s.hooks[ev] === null) s.hooks[ev] = [];
             if (!Array.isArray(s.hooks[ev])) throw new Error(ev);
             s.hooks[ev] = s.hooks[ev].concat(t.hooks[ev]);
           };
           if (ns === "1") add("Stop");
           if (ng === "1") add("PreToolUse");
           fs.writeFileSync(out, JSON.stringify(s, null, 2) + "\n");
         ' "$HF" "$HT" "$NEED_STOP" "$NEED_GUARD" "$TMP" 2>/dev/null; then
      REASON="has an unexpected shape (hooks, hooks.Stop and hooks.PreToolUse must be objects/arrays)"
    fi
  else
    REASON="cannot be merged here (neither jq nor node is installed)"
  fi
  if [ -z "$REASON" ]; then
    cat "$TMP" > "$HF"   # write through: keeps a symlink and the file mode
    rm -f "$TMP"
    say "  ~ $HF: slickrails hooks merged in (your other settings and hooks are untouched)"
  else
    rm -f "$TMP"
    warn "$HF $REASON — left untouched. Merge the hooks by hand (template: templates/$(basename "$HT") in the kit)."
  fi
  return 0
}

# ------------------------------------------------------------ arguments -----
TARGET=""
LANG_CODE="en"
VERBOSE=0   # --verbose lists every file the installer adds
GITHUB_REVIEW=0   # --github-review: also the server-side AI review on GitHub (claude-review.yml; App + secret, Actions minutes)
STATUS_MOD=0      # --status-mod: offer the slickrails-status mod for Claude Code to everyone who opens the repo
SLICKRAILS_MARKETPLACE="${SLICKRAILS_MARKETPLACE:-l0kl97/slickrails}"   # the GitHub repo that holds the mod's marketplace
REVIEW="${SLICKRAILS_REVIEW:-auto}"   # local AI review before every push: auto (the claude or codex CLI found here) | claude | codex | off
AGENT="both"   # which agent's session hooks to install: claude | codex | both (both is the default: detecting the Codex CLI is unreliable, it often lives inside an app bundle)
while [ $# -gt 0 ]; do
  case "$1" in
    doctor)
      say "Environment check:"
      for tool in git node gh gitleaks; do
        if command -v "$tool" >/dev/null 2>&1; then
          say "  ok       $tool ($(command -v "$tool"))"
        else
          case "$tool" in
            git)      say "  MISSING  git — required";;
            node)     say "  missing  node — needed for Node projects";;
            gh)       say "  missing  gh — needed for branch protection (brew install gh)";;
            gitleaks) say "  missing  gitleaks — pre-commit falls back to simple patterns (brew install gitleaks)";;
          esac
        fi
      done
      # Repo check — only inside a repo that has the kit installed. It checks the installation, not behavior,
      # and it never runs project code (config.sh is read as text, not sourced).
      DOC_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
      if [ -n "$DOC_ROOT" ] && [ -f "$DOC_ROOT/.slickrails/config.sh" ]; then
        PROBLEMS=0
        say ""
        say "Repo check ($DOC_ROOT):"
        DOC_HP="$(git -C "$DOC_ROOT" config core.hooksPath 2>/dev/null || true)"
        if [ -z "$DOC_HP" ]; then
          if [ -n "${CI:-}" ]; then
            say "  WARN     core.hooksPath is not set (CI: git hooks are not expected on a build machine)"
          else
            say "  PROBLEM  core.hooksPath is not set in this clone — the slickrails git hooks are NOT active. It is local git config and not cloned: run  git config core.hooksPath .githooks"
            PROBLEMS=1
          fi
        elif ( cd "$DOC_ROOT" && is_our_hooks_path "$DOC_HP" ); then
          say "  ok       core.hooksPath = $DOC_HP (the git hooks are active in this clone)"
        elif ( cd "$DOC_ROOT" && grep -rqs '\.githooks' "$DOC_HP" ); then
          say "  ok       core.hooksPath = $DOC_HP, and it calls .githooks/* (chained; not verified that it runs)"
        else
          say "  PROBLEM  core.hooksPath = $DOC_HP — the slickrails git hooks are NOT active; call .githooks/* from that hook manager"
          PROBLEMS=1
        fi
        for DOC_HOOK in pre-commit pre-push commit-msg; do
          if [ ! -x "$DOC_ROOT/.githooks/$DOC_HOOK" ]; then
            say "  PROBLEM  .githooks/$DOC_HOOK is missing or not executable"
            PROBLEMS=1
          fi
        done
        DOC_CFG="$DOC_ROOT/.slickrails/config.sh"
        if ! sh -n "$DOC_CFG" 2>/dev/null; then
          say "  PROBLEM  .slickrails/config.sh has a syntax error — the hooks cannot read it"
          PROBLEMS=1
        elif grep -Eq "^[[:space:]]*(CHECK_TYPECHECK|CHECK_TEST|CHECK_SESSION)=(\"[^\"]+\"|'[^']+'|[^\"'[:space:]#]+)" "$DOC_CFG"; then
          say "  ok       .slickrails/config.sh defines checks"
        else
          say "  WARN     no checks configured in .slickrails/config.sh (CHECK_TYPECHECK/CHECK_TEST/CHECK_SESSION are empty) — nothing is checked, and the setup check in CI fails"
        fi
        # an older config.sh (never overwritten) may predate the local review; say so when a reviewer CLI is here
        if ! grep -Eq '^[[:space:]]*CHECK_PREPUSH_REVIEW=("1"|'"'"'1'"'"'|1)' "$DOC_CFG"; then
          for DOC_CLI in claude codex; do
            if command -v "$DOC_CLI" >/dev/null 2>&1; then
              say "  WARN     the local AI review before push is off, but the $DOC_CLI CLI is here (no API key needed): set CHECK_PREPUSH_REVIEW=\"1\" in .slickrails/config.sh"
              break
            fi
          done
        fi
        for DOC_AGENT in "Claude Code:.claude/settings.json" "Codex:.codex/hooks.json"; do
          DOC_NAME="${DOC_AGENT%%:*}"; DOC_FILE="${DOC_AGENT#*:}"; DOC_SET="$DOC_ROOT/$DOC_FILE"
          if [ "$DOC_NAME" = "Codex" ] && [ ! -f "$DOC_SET" ]; then
            say "  WARN     Codex hooks are not installed ($DOC_FILE is missing) — fine for a Claude-only setup, otherwise run: slickrails init --agent codex"
            continue
          fi
          for DOC_PAIR in "Stop:session-check.sh:$DOC_NAME Stop hook" "PreToolUse:bash-guard.sh:$DOC_NAME Bash guard (no --no-verify)"; do
            DOC_EV="${DOC_PAIR%%:*}"; DOC_REST="${DOC_PAIR#*:}"; DOC_SCRIPT="${DOC_REST%%:*}"; DOC_LABEL="${DOC_REST#*:}"
            DOC_HH=0
            [ -f "$DOC_SET" ] && { has_hook "$DOC_SET" "$DOC_EV" "$DOC_SCRIPT" || DOC_HH=$?; } || DOC_HH=1
            if [ "$DOC_HH" = "2" ]; then
              say "  WARN     cannot verify the $DOC_LABEL in $DOC_FILE (needs jq or node)"
            elif [ "$DOC_HH" != "0" ]; then
              say "  PROBLEM  $DOC_LABEL is not configured in $DOC_FILE (re-run the installer)"
              PROBLEMS=1
            elif [ ! -x "$DOC_ROOT/.slickrails/$DOC_SCRIPT" ]; then
              say "  PROBLEM  $DOC_LABEL is configured, but .slickrails/$DOC_SCRIPT is missing or not executable"
              PROBLEMS=1
            else
              say "  ok       $DOC_LABEL is configured"
            fi
          done
        done
        # Self-test: installed is not the same as working. The guard and the pre-commit hook get a probe each (the
        # pre-commit one in a scratch repo, so neither this repo nor its config.sh is touched).
        if [ -x "$DOC_ROOT/.slickrails/bash-guard.sh" ]; then
          # (from outside the repo: the guard switches inactive git hooks on, a check must not change what it checks)
          probe_guard() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | ( cd "${TMPDIR:-/tmp}" && sh "$DOC_ROOT/.slickrails/bash-guard.sh" ) >/dev/null 2>&1; }
          DOC_P1=0; probe_guard 'git commit --no-verify -m probe' || DOC_P1=$?
          DOC_P2=0; probe_guard 'git status' || DOC_P2=$?
          if [ "$DOC_P1" != "2" ]; then say "  PROBLEM  Bash guard lets a --no-verify probe through (exit $DOC_P1)"; PROBLEMS=1
          elif [ "$DOC_P2" != "0" ]; then say "  PROBLEM  Bash guard blocks a harmless git status (exit $DOC_P2)"; PROBLEMS=1
          else say "  ok       Bash guard blocks a --no-verify probe and lets git status through"; fi
        fi
        if [ -x "$DOC_ROOT/.githooks/pre-commit" ]; then
          DOC_SCR="$(mktemp -d "${TMPDIR:-/tmp}/slickrails-probe.XXXXXX")"; DOC_P3=0
          ( cd "$DOC_SCR" && unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE && git init -q . \
            && printf 'key = "%s%s"\n' "sk-" "slickrailsdoctorprobe0000000000" > probe.js && git add probe.js \
            && sh "$DOC_ROOT/.githooks/pre-commit" ) >/dev/null 2>&1 || DOC_P3=$?
          rm -rf "$DOC_SCR"
          if [ "$DOC_P3" = "0" ]; then say "  PROBLEM  pre-commit lets a staged test key through"; PROBLEMS=1
          else say "  ok       pre-commit blocks a staged test key"; fi
        fi
        say ""
        say "Not verified: that the hooks actually run in your agent. Claude Code asks you to trust a project's"
        say "hooks on first use; Codex asks for a hook trust review (/hooks) and loads project hooks only if the project's"
        say ".codex/ layer is trusted; neither is checked here. 'ok' means installed (the probe lines: also answered right when called directly)."
        exit "$PROBLEMS"
      fi
      exit 0;;
    version)
      cat "$KIT_DIR/VERSION" 2>/dev/null || echo "unknown"
      exit 0;;
    --lang)
      shift; LANG_CODE="${1:-en}";;
    --agent|--agent=*)
      case "$1" in --agent=*) AGENT="${1#--agent=}";; *) shift; AGENT="${1:-}";; esac
      case "$AGENT" in claude|codex|both) ;; *) warn "--agent must be claude, codex or both (got '$AGENT')"; exit 1;; esac;;
    --verbose|-v)
      VERBOSE=1;;
    --github-review)
      GITHUB_REVIEW=1;;
    --status-mod)
      STATUS_MOD=1;;
    --review|--review=*)
      case "$1" in --review=*) REVIEW="${1#--review=}";; *) shift; REVIEW="${1:-}";; esac
      case "$REVIEW" in auto|claude|codex|off) ;; *) warn "--review must be auto, claude, codex or off (got '$REVIEW')"; exit 1;; esac;;
    -*)
      warn "unknown option: $1"; exit 1;;
    *)
      TARGET="$1";;
  esac
  shift
done

# Resolve a text template honoring --lang (code templates are always English).
tpl() { # tpl <name>
  if [ "$LANG_CODE" != "en" ] && [ -f "$KIT_DIR/templates/$LANG_CODE/$1" ]; then
    printf '%s' "$KIT_DIR/templates/$LANG_CODE/$1"
  else
    printf '%s' "$KIT_DIR/templates/$1"
  fi
}

RULEBOOK="$KIT_DIR/SLICKRAILS.md"
[ "$LANG_CODE" != "en" ] && [ -f "$KIT_DIR/SLICKRAILS.$LANG_CODE.md" ] && RULEBOOK="$KIT_DIR/SLICKRAILS.$LANG_CODE.md"

# ---------------------------------------------------------------- target ----
TARGET="${TARGET:-$(pwd)}"
TARGET="$(cd "$TARGET" && pwd)"
cd "$TARGET"

if [ ! -d .git ]; then
  say "Not a git repo — initializing ($TARGET)"
  git init -q
fi

say "Installing slickrails into: $TARGET (lang: $LANG_CODE)"

# --------------------------------------------------------- stack detection --
STACK="generic"
[ -f pyproject.toml ] || [ -f requirements.txt ] && STACK="python"
[ -f Package.swift ] && STACK="swift"
ls ./*.xcodeproj >/dev/null 2>&1 && STACK="swift"
[ -f go.mod ] && STACK="go"
[ -f Cargo.toml ] && STACK="rust"
[ -f Gemfile ] && STACK="ruby"
if [ -f pom.xml ] || [ -f build.gradle ] || [ -f build.gradle.kts ]; then STACK="jvm"; fi
[ -f package.json ] && STACK="node"
say "Detected stack: $STACK"

# Node package manager (by lockfile; npm is the fallback)
PM="npm"
[ -f pnpm-lock.yaml ] && PM="pnpm"
[ -f yarn.lock ] && PM="yarn"
if [ -f bun.lockb ] || [ -f bun.lock ]; then PM="bun"; fi
[ "$STACK" = "node" ] && say "Package manager: $PM"

# Does package.json define a given script? (used for PMs without --if-present)
has_script() { # has_script <name>
  node -e "p=require('./package.json');process.exit(p.scripts&&p.scripts['$1']?0:1)" 2>/dev/null
}

HAS_PLAYWRIGHT=0
if [ -f package.json ] && grep -q '"@playwright/test"' package.json 2>/dev/null; then
  HAS_PLAYWRIGHT=1
fi

# Copies only if the destination doesn't exist. A file that differs is replaced when it is still what an earlier
# install placed from the same template (.slickrails/manifest holds hash, path and template: that is the update
# path), and gets a .slickrails-new next to it when someone edited it or the template is another one (--lang, stack). New files are counted and only listed with --verbose; the rest is always said.
ADDED=0
MANIFEST=".slickrails/manifest"; PLACED=""
added() { ADDED=$((ADDED + 1)); [ "$VERBOSE" = "1" ] && say "  + $1"; return 0; }
place() { # place <src> <dest>
  SRC="$1"; DEST="$2"
  mkdir -p "$(dirname "$DEST")"
  FROM="${SRC#"$KIT_DIR"/}"   # which template: another language or stack is another file, not an update
  PLACED="$PLACED$(git hash-object "$SRC") $DEST $FROM
"
  if [ ! -f "$DEST" ]; then
    cp "$SRC" "$DEST"
    added "$DEST"
  elif cmp -s "$SRC" "$DEST"; then
    :
  elif [ "$(awk -v d="$DEST" -v f="$FROM" '$2 == d && $3 == f { print $1 }' "$MANIFEST" 2>/dev/null)" = "$(git hash-object "$DEST")" ]; then
    cat "$SRC" > "$DEST"   # write through: keeps the file mode
    say "  ~ $DEST updated (it was unchanged since the last install)"
  else
    cp "$SRC" "$DEST.slickrails-new"
    warn "$DEST exists and was edited — the new version was placed at $DEST.slickrails-new."
  fi
  return 0
}

# ------------------------------------------------- bundled under .slickrails --
# Older installs kept the rulebook and the status in the project root and a copy of the branch-protection script in
# scripts/. They move into .slickrails/ (with the user's edits); an unchanged script copy goes, `slickrails protect`
# runs the kit's own. Never in the kit's own repo, where the root files are the sources.
mkdir -p .slickrails
if [ "$TARGET" != "$KIT_DIR" ]; then
  for MOVE in "SLICKRAILS.md:.slickrails/SLICKRAILS.md" "SLICKRAILS-STATUS.md:.slickrails/STATUS.md"; do
    FROM="${MOVE%%:*}"; TO="${MOVE#*:}"
    if [ -f "$FROM" ] && [ ! -e "$TO" ]; then mv "$FROM" "$TO"; say "  ~ moved $FROM → $TO (commit the move)"; MOVED=1; fi
  done
  # what an older install wrote still names the old paths: the rules block for the agents and the CI workflows
  if [ "${MOVED:-0}" = "1" ]; then
    for F in CLAUDE.md AGENTS.md .github/workflows/*.yml; do
      # shellcheck disable=SC2016  # the backticks are literal Markdown, not command substitution
      [ -f "$F" ] && grep -Eq '(^|[^/])SLICKRAILS-STATUS\.md|`SLICKRAILS\.md`' "$F" || continue
      # shellcheck disable=SC2016  # literal Markdown backticks again
      sed -E -e 's#(^|[^/])SLICKRAILS-STATUS\.md#\1.slickrails/STATUS.md#g' -e 's#`SLICKRAILS\.md`#`.slickrails/SLICKRAILS.md`#g' \
        "$F" > "$F.slickrails-tmp" && cat "$F.slickrails-tmp" > "$F"; rm -f "$F.slickrails-tmp"
      say "  ~ $F now points at the moved files"
    done
  fi
  if [ -f scripts/setup-branch-protection.sh ]; then
    if cmp -s "$KIT_DIR/scripts/setup-branch-protection.sh" scripts/setup-branch-protection.sh; then
      rm scripts/setup-branch-protection.sh; rmdir scripts 2>/dev/null || true
      say "  ~ removed scripts/setup-branch-protection.sh (now: slickrails protect)"
    else
      say "  ! scripts/setup-branch-protection.sh is no longer needed (slickrails protect runs the kit's) — delete it unless you changed it on purpose"
    fi
  fi
fi

# -------------------------------------------------------------- rulebook ----
place "$RULEBOOK" ".slickrails/SLICKRAILS.md"

# ------------------------------------------------------------ .slickrails ---
mkdir -p .slickrails
[ -f .slickrails/rules.md ] || { cp "$(tpl rules.md)" .slickrails/rules.md; added .slickrails/rules.md; }
[ -f .slickrails/review-learnings.md ] || { cp "$KIT_DIR/templates/review-learnings.md" .slickrails/review-learnings.md; added .slickrails/review-learnings.md; }

if [ ! -f .slickrails/config.sh ]; then
  CHECK_TYPECHECK=""; CHECK_TEST=""
  case "$STACK" in
    node)
      case "$PM" in
        npm)
          CHECK_TYPECHECK="npm run typecheck --if-present"
          CHECK_TEST="npm test --if-present";;
        pnpm)
          CHECK_TYPECHECK="pnpm run --if-present typecheck"
          CHECK_TEST="pnpm run --if-present test";;
        yarn|bun)
          has_script typecheck && CHECK_TYPECHECK="$PM run typecheck"
          has_script test && CHECK_TEST="$PM run test";;
      esac
      ;;
    python)
      if [ -d tests ]; then CHECK_TEST="python3 -m pytest -q"; fi
      ;;
    swift)
      if [ -f Package.swift ]; then CHECK_TEST="swift test"; fi
      ;;
    go)
      CHECK_TYPECHECK="go build ./..."
      CHECK_TEST="go test ./..."
      ;;
    rust)
      CHECK_TYPECHECK="cargo check --quiet"
      CHECK_TEST="cargo test --quiet"
      ;;
    ruby)
      if [ -d spec ]; then CHECK_TEST="bundle exec rspec"
      elif [ -d test ]; then CHECK_TEST="bundle exec rake test"; fi
      ;;
    jvm)
      if [ -f pom.xml ]; then CHECK_TEST="mvn -q test"
      elif [ -x gradlew ]; then CHECK_TEST="./gradlew test"
      else CHECK_TEST="gradle test"; fi
      ;;
  esac
  # The local AI review follows what is installed here: claude or codex reviews with the user's own login (no API key).
  # --agent codex prefers codex when both are there. Only decided when config.sh is written (it is never overwritten).
  REVIEW_ON="0"; REVIEW_WITH="auto"
  if [ "$REVIEW" != "off" ]; then
    HAS_CLAUDE=0; command -v claude >/dev/null 2>&1 && HAS_CLAUDE=1
    HAS_CODEX=0; { command -v codex >/dev/null 2>&1 \
      || [ -x "${SLICKRAILS_CODEX_APP:-/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex}" ]; } && HAS_CODEX=1
    case "$REVIEW" in
      claude) [ "$HAS_CLAUDE" = "1" ] && REVIEW_WITH=claude;;
      codex)  [ "$HAS_CODEX" = "1" ] && REVIEW_WITH=codex;;
      *)      if [ "$AGENT" = "codex" ] && [ "$HAS_CODEX" = "1" ]; then REVIEW_WITH=codex
              elif [ "$HAS_CLAUDE" = "1" ]; then REVIEW_WITH=claude
              elif [ "$HAS_CODEX" = "1" ]; then REVIEW_WITH=codex; fi;;
    esac
    if [ "$REVIEW_WITH" != "auto" ]; then
      REVIEW_ON="1"; say "  + local AI review before every push, with your $REVIEW_WITH CLI (no API key; off: CHECK_PREPUSH_REVIEW=\"0\")"
    else
      say "  - local AI review stays off: no claude or codex CLI found (install one, then set CHECK_PREPUSH_REVIEW=\"1\")"
    fi
  fi
  cat > .slickrails/config.sh <<EOF
# slickrails: checks for this repo's git hooks (generated by install.sh).
# Empty string = check skipped. Commands run in the repo root.
CHECK_TYPECHECK="$CHECK_TYPECHECK"
CHECK_TEST="$CHECK_TEST"
CHECK_LINT_STAGED=""
# Optional: what the Claude Code Stop hook runs (defaults to typecheck + tests).
#CHECK_SESSION=""
# AI review of the outgoing diff on every push, with the local claude or codex CLI (your login, no API key).
CHECK_PREPUSH_REVIEW="$REVIEW_ON"
# Which CLI reviews: auto (claude, else codex) | claude | codex
REVIEW_CLI="$REVIEW_WITH"
# Review strictness for all AI reviews: quiet (high-risk only) | chill | assertive.
REVIEW_PROFILE="chill"
# A failed or invalid AI review is reported as ERROR, never as PASS. warn = the push proceeds unreviewed; block = it stops.
REVIEW_ON_ERROR="warn"
EOF
  say "  + .slickrails/config.sh (stack: $STACK — adjust as needed)"
  # nothing to check found for this stack (Python without tests/, a yarn project without a test script, …): every hook
  # would pass, and the setup check in CI fails until a check is named — said now, not on the first PR
  if [ -z "$CHECK_TYPECHECK" ] && [ -z "$CHECK_TEST" ]; then
    warn "no test or typecheck command found for this $STACK project — .slickrails/config.sh checks nothing, so every hook passes."
    warn "Set CHECK_TEST (and CHECK_TYPECHECK) there. Until then the 'slickrails setup' step in CI fails (repository variable SLICKRAILS_SETUP_CHECK=warn reports only)."
  fi
fi

# ----------------------------------------------------------------- hooks ----
mkdir -p .githooks
place "$KIT_DIR/templates/hooks/pre-commit" ".githooks/pre-commit"
place "$KIT_DIR/templates/hooks/pre-push"   ".githooks/pre-push"
place "$KIT_DIR/templates/hooks/commit-msg" ".githooks/commit-msg"
place "$KIT_DIR/templates/hooks/post-merge" ".githooks/post-merge"
chmod +x .githooks/pre-commit .githooks/pre-push .githooks/commit-msg .githooks/post-merge 2>/dev/null || true
# core.hooksPath is a single setting: switching it silently would switch off another hook manager (Husky, ...).
CUR_HOOKS_PATH="$(git config core.hooksPath 2>/dev/null || true)"
HOOKS_ACTIVE=1
if [ -z "$CUR_HOOKS_PATH" ] || is_our_hooks_path "$CUR_HOOKS_PATH"; then
  git config core.hooksPath .githooks
  say "  ~ core.hooksPath = .githooks"
else
  HOOKS_ACTIVE=0
  warn "core.hooksPath is '$CUR_HOOKS_PATH' (another hook manager?) — the slickrails git hooks are NOT active."
  warn "The hook files are in .githooks/. Either call them from your hook manager (e.g. 'sh .githooks/pre-commit' inside $CUR_HOOKS_PATH/pre-commit, same for pre-push and commit-msg), or switch with 'git config core.hooksPath .githooks' (that disables the other hooks)."
fi
# ------------------------------------------------------------- workflows ----
case "$STACK" in
  node)   place "$KIT_DIR/templates/workflows/ci-node.yml"   ".github/workflows/ci.yml";;
  python) place "$KIT_DIR/templates/workflows/ci-python.yml" ".github/workflows/ci.yml";;
  swift)  place "$KIT_DIR/templates/workflows/ci-swift.yml"  ".github/workflows/ci.yml";;
  go)     place "$KIT_DIR/templates/workflows/ci-go.yml"     ".github/workflows/ci.yml";;
  rust)   place "$KIT_DIR/templates/workflows/ci-rust.yml"   ".github/workflows/ci.yml";;
  ruby)   place "$KIT_DIR/templates/workflows/ci-ruby.yml"   ".github/workflows/ci.yml";;
  jvm)    place "$KIT_DIR/templates/workflows/ci-jvm.yml"    ".github/workflows/ci.yml";;
  *)      warn "Unknown stack — no ci.yml installed (pick one from templates/workflows manually).";;
esac
place "$KIT_DIR/templates/workflows/security.yml"      ".github/workflows/security.yml"
# The AI review runs locally before every push (ai-review.sh); the same review on GitHub is opt-in
[ "$GITHUB_REVIEW" = "1" ] && place "$KIT_DIR/templates/workflows/claude-review.yml" ".github/workflows/claude-review.yml"
place "$KIT_DIR/templates/workflows/pr-size.yml"       ".github/workflows/pr-size.yml"
place "$KIT_DIR/templates/dependabot.yml"              ".github/dependabot.yml"
if [ "$HAS_PLAYWRIGHT" = "1" ]; then
  place "$KIT_DIR/templates/workflows/smoke-playwright.yml" ".github/workflows/smoke.yml"
elif [ "$STACK" = "node" ]; then
  warn "No @playwright/test in this project — smoke workflow not installed (rule 2: add it!)."
fi

# ----------------------------------------------- docs layer (rule 11) -------
mkdir -p docs/features
[ -f docs/features/README.md ]    || { cp "$(tpl docs-readme.md)" docs/features/README.md; added docs/features/README.md; }
[ -f docs/features/_TEMPLATE.md ] || { cp "$(tpl feature-dossier.md)" docs/features/_TEMPLATE.md; added docs/features/_TEMPLATE.md; }
place "$(tpl pr-template.md)" ".github/PULL_REQUEST_TEMPLATE.md"
# CODEOWNERS for sensitive paths: every line commented out until the repo names real people (enforced only with
# CODEOWNER_REVIEWS=1 slickrails protect). An existing CODEOWNERS anywhere GitHub looks is left alone.
if [ ! -f .github/CODEOWNERS ] && [ ! -f CODEOWNERS ] && [ ! -f docs/CODEOWNERS ]; then
  cp "$KIT_DIR/templates/codeowners" .github/CODEOWNERS; added .github/CODEOWNERS
fi

# ------------------------------------------ AI-session enforcement ----------
place "$KIT_DIR/templates/session-check.sh" ".slickrails/session-check.sh"
place "$KIT_DIR/templates/ai-review.sh"     ".slickrails/ai-review.sh"
place "$KIT_DIR/templates/bash-guard.sh"    ".slickrails/bash-guard.sh"
place "$KIT_DIR/templates/dep-check.sh"     ".slickrails/dep-check.sh"
place "$KIT_DIR/templates/setup-check.sh"   ".slickrails/setup-check.sh"
chmod +x .slickrails/session-check.sh .slickrails/ai-review.sh .slickrails/bash-guard.sh .slickrails/dep-check.sh .slickrails/setup-check.sh 2>/dev/null || true

# Agent hook configuration: the same Stop gate and Bash guard for Claude Code and for the Codex CLI.
case "$AGENT" in
  claude|both)
    install_hooks_file ".claude/settings.json" "$KIT_DIR/templates/claude-settings.json" "Claude Code"
    # --status-mod: Claude Code offers the slickrails marketplace and its status mod to everyone who trusts the repo
    if [ "$STATUS_MOD" = "1" ]; then
      SM_TMP=".claude/settings.json.slickrails-tmp"
      if command -v jq >/dev/null 2>&1; then
        jq --arg repo "$SLICKRAILS_MARKETPLACE" '.extraKnownMarketplaces.slickrails = {source: {source: "github", repo: $repo}}
             | .enabledPlugins["slickrails-status@slickrails"] = true' .claude/settings.json > "$SM_TMP" 2>/dev/null || rm -f "$SM_TMP"
      elif command -v node >/dev/null 2>&1; then
        node -e 'const fs=require("fs"),[f,r,o]=process.argv.slice(1),s=JSON.parse(fs.readFileSync(f,"utf8"));
          s.extraKnownMarketplaces=Object.assign({},s.extraKnownMarketplaces,{slickrails:{source:{source:"github",repo:r}}});
          s.enabledPlugins=Object.assign({},s.enabledPlugins,{"slickrails-status@slickrails":true});
          fs.writeFileSync(o,JSON.stringify(s,null,2)+"\n")' .claude/settings.json "$SLICKRAILS_MARKETPLACE" "$SM_TMP" 2>/dev/null || rm -f "$SM_TMP"
      fi
      if [ -s "$SM_TMP" ]; then cat "$SM_TMP" > .claude/settings.json; say "  ~ .claude/settings.json offers the slickrails-status mod ($SLICKRAILS_MARKETPLACE)"
      else warn "could not add the status mod to .claude/settings.json (needs jq or node) — install it by hand: /plugin install slickrails-status@slickrails"; fi
      rm -f "$SM_TMP"
    fi;;
esac
case "$AGENT" in
  codex|both)
    install_hooks_file ".codex/hooks.json" "$KIT_DIR/templates/codex-hooks.json" "Codex"
    say "  Codex: review and trust the new project hooks once (run /hooks in the Codex CLI) — until then they are skipped."
    say "         Project hooks load only if the project's .codex/ layer is trusted.";;
esac

# -------------------------------------------------------------- .gitignore --
touch .gitignore
if ! grep -qE '^\.env$' .gitignore; then
  printf '\n# slickrails\n.env\n.env.*\n!.env.example\n' >> .gitignore
  say "  ~ .gitignore extended with .env rules"
fi

# ---------------------------------------------------------------- STATUS ----
if [ ! -f .slickrails/STATUS.md ]; then
  TODAY="$(date +%Y-%m-%d)"
  HOOKS_MARK="☑"; [ "$HOOKS_ACTIVE" = "1" ] || HOOKS_MARK="☐"
  # rule 6 (AI review before merge) is in place when the local review runs before every push
  REVIEW_MARK="☐"; grep -Eq '^[[:space:]]*CHECK_PREPUSH_REVIEW=("1"|1)' .slickrails/config.sh 2>/dev/null && REVIEW_MARK="☑"
  sed -e "s/__DATE__/$TODAY/g" \
      -e "s/__HOOKS__/$HOOKS_MARK/g" \
      -e "s/__REVIEW__/$REVIEW_MARK/g" \
      -e "s/__WORKFLOWS__/☑/g" \
      -e "s/__STACK__/$STACK/g" \
      "$(tpl slickrails-status.md)" > .slickrails/STATUS.md
  added .slickrails/STATUS.md
fi
# Hooks inactive: record it once (also on a rerun after a hook manager appeared). The status file is the user's
# document, so a line is added but never removed; `slickrails doctor` shows the current truth.
if [ "$HOOKS_ACTIVE" != "1" ] && [ -f .slickrails/STATUS.md ] && ! grep -qE 'NOT active|NICHT aktiv' .slickrails/STATUS.md; then
  TODAY="$(date +%Y-%m-%d)"
  if [ "$LANG_CODE" = "de" ]; then
    printf '%s\n' "- $TODAY: Git-Hooks sind NICHT aktiv — core.hooksPath zeigt auf '$CUR_HOOKS_PATH' (anderer Hook-Manager). Hooks aus .githooks/ dort einhaengen oder 'git config core.hooksPath .githooks' setzen." >> .slickrails/STATUS.md
  else
    printf '%s\n' "- $TODAY: git hooks are NOT active — core.hooksPath points to '$CUR_HOOKS_PATH' (another hook manager). Call the hooks in .githooks/ from there, or run 'git config core.hooksPath .githooks'." >> .slickrails/STATUS.md
  fi
fi

# ------------------------------------------------- agent rules block --------
# The same binding block goes into CLAUDE.md (Claude Code) and AGENTS.md
# (the cross-tool convention read by Codex, Cursor, and others).
for AGENT_FILE in CLAUDE.md AGENTS.md; do
  if [ -f "$AGENT_FILE" ] && grep -q 'slickrails:start' "$AGENT_FILE"; then
    : # block already present
  else
    { [ -f "$AGENT_FILE" ] && printf '\n'; cat "$(tpl claude-md-section.md)"; } >> "$AGENT_FILE"
    say "  ~ $AGENT_FILE extended with the slickrails rules block"
  fi
done

# what was placed, for the next run: a file that still has this hash then was not edited and can be updated
{ printf '# slickrails %s — what the installer placed: hash, file, template. Commit it; do not edit.\n' "$(cat "$KIT_DIR/VERSION" 2>/dev/null)"
  printf '%s' "$PLACED"; } > "$MANIFEST"

say ""
say "Done: $ADDED files added (list them: git status; or run with --verbose)."
# Next steps: only the ones that apply to this repo
ON_GITHUB=0; case "$(git remote get-url origin 2>/dev/null || true)" in *github.com*) ON_GITHUB=1;; esac
N=0; step() { N=$((N + 1)); say "  $N. $1"; shift; for L in "$@"; do say "     $L"; done; }
say "Next steps:"
step "Check .slickrails/config.sh: are the checks right for this repo?"
step "Commit. The first commit is big, so the commit-msg hook wants a body:" \
     "git add -A && git commit -m \"Install slickrails\" -m \"Why: <the standard for this repo>\" -m \"What: hooks, CI, docs layer\""
if [ "$ON_GITHUB" = "1" ]; then
  step "Branch protection on GitHub (needs gh): slickrails protect   (without the CLI: sh $KIT_DIR/scripts/setup-branch-protection.sh)"
  if [ "$GITHUB_REVIEW" = "1" ]; then
    step "For the AI review on GitHub (claude-review.yml): install the Claude GitHub App (https://github.com/apps/claude)" \
         "and set ONE repo secret, CLAUDE_CODE_OAUTH_TOKEN ('claude setup-token') or ANTHROPIC_API_KEY;" \
         "'/install-github-app' in Claude Code does both."
  else
    step "Optional: the same AI review server-side on GitHub too (App + secret, uses Actions minutes): slickrails github-review"
  fi
else
  step "Optional, with a GitHub remote: the AI review server-side on GitHub too: slickrails github-review"
fi
[ "$STATUS_MOD" = "1" ] || step "Optional: slickrails in Claude Code's status line (guard, review, checks, open rules):" \
     "/plugin marketplace add $SLICKRAILS_MARKETPLACE  then  /plugin install slickrails-status@slickrails   (for the whole team: --status-mod)"
step "Claude Code / Codex ask once to trust the project hooks (Codex: /hooks); until then they are skipped."
step "Fresh clones: git does not copy core.hooksPath. An agent's first tool call switches the hooks on;" \
     "by hand: git config core.hooksPath .githooks. Update this repo to a newer kit: slickrails upgrade, then slickrails init."

#!/bin/sh
# slickrails: PreToolUse hook for Claude Code and Codex — stops an agent from bypassing the guardrails or destroying
# work. A written rule ("never --no-verify") is an instruction; this makes the obvious cases fail on the spot.
# It is a hint, not a boundary: an agent can still get around it (a script that contains the command, a shell
# variable holding it, a path spelled differently). The server-side checks (CI, branch protection) are what hold.
#
# Blocks (exit 2), for a Bash call:
#   bypass       `git ... --no-verify` (also abbreviated: git accepts unique prefixes), `git commit -n`, a
#                `SLICKRAILS_SKIP=` assignment, switching git hooks off through core.hooksPath
#   guardrails   writing to the files that hold them (rm/mv/cp/tee/sed -i/... or a `>` redirect onto
#                .slickrails/*.sh, .githooks/, .claude/settings(.local).json, .codex/hooks.json)
#   destructive  git reset --hard, git clean -f, git push --force (any forced push onto main/master), git checkout/
#                restore of everything, rm -r on / ~ $HOME . .. * .git, database resets and DROP/TRUNCATE
# and for an edit tool (Edit, Write, MultiEdit, NotebookEdit): a file_path that is one of the guardrail files.
# With jq (or node) the hook JSON is parsed and quoted text (commit messages, echo strings) is not taken for a
# command; without both the raw JSON is matched, which also catches mentions inside quotes.
# The way out belongs to the human (an agent cannot set the hook's environment from inside a Bash call): start the
# agent with SLICKRAILS_ALLOW_BYPASS=1 (bypass, guardrails) or SLICKRAILS_ALLOW_DESTRUCTIVE=1, or run the
# destructive command yourself (Claude Code: `! <command>`).

set -u

IN="$(cat 2>/dev/null || true)"

# Parse tool, command and file path out of the hook JSON with jq or node; only if neither can, match the raw JSON.
PARSED=0; TOOL=""; CMD=""; FPATH=""
if command -v jq >/dev/null 2>&1; then
  if printf '%s' "$IN" | jq -e . >/dev/null 2>&1; then
    TOOL="$(printf '%s' "$IN" | jq -r '.tool_name // empty' 2>/dev/null || true)"
    CMD="$(printf '%s' "$IN" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
    FPATH="$(printf '%s' "$IN" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null || true)"
    PARSED=1
  fi
elif command -v node >/dev/null 2>&1; then
  # one line each for tool and path, the rest is the command (it may span lines)
  if OUT="$(printf '%s' "$IN" | node -e 'let d="";process.stdin.on("data",c=>d+=c).on("end",()=>{try{const o=JSON.parse(d)||{},i=o.tool_input||{},s=(v)=>typeof v==="string"?v:"";process.stdout.write([s(o.tool_name).replace(/\n/g," "),s(i.file_path||i.notebook_path).replace(/\n/g," "),s(i.command)].join("\n"))}catch(e){process.exit(1)}})' 2>/dev/null)"; then
    TOOL="$(printf '%s\n' "$OUT" | sed -n 1p)"; FPATH="$(printf '%s\n' "$OUT" | sed -n 2p)"
    CMD="$(printf '%s\n' "$OUT" | sed '1,2d')"; PARSED=1
  fi
fi

BYPASS_OK=0; [ "${SLICKRAILS_ALLOW_BYPASS:-0}" = "1" ] && BYPASS_OK=1
DESTROY_OK=0; [ "${SLICKRAILS_ALLOW_DESTRUCTIVE:-0}" = "1" ] && DESTROY_OK=1

# the guardrail files: as a whole path (edit tools) and as a word inside a command (followed by a quote, space or end)
GUARD_PATH='(^|/)(\.slickrails/[^/]*\.sh|\.githooks(/.*)?|\.claude/settings(\.local)?\.json|\.codex/hooks\.json)$'
# (the folders count as a whole too: rm -rf .slickrails takes every guardrail with it)
# (a glob inside them counts as the folder, unless it ends in a foreign extension: .slickrails/* yes, .slickrails/*.bak no)
GUARD_WORD='(^|[[:space:]"'"'"'/=>])(\.(slickrails|githooks|claude|codex)/[^[:space:]"'"'"']*[*?[]([^[:space:]"'"'"'.]*|[^[:space:]"'"'"']*\.(sh|json))|\.slickrails(/([^/[:space:]"'"'"']*\.sh)?)?|\.githooks(/[^[:space:]"'"'"']*)?|\.claude(/settings(\.local)?\.json|/)?|\.codex(/hooks\.json|/)?)(["'"'"'[:space:]]|$)'

block_guardrails() {
  {
    echo "slickrails: blocked — $1 is one of the files that hold the guardrails (hooks, checks, agent hook settings)."
    echo "Changing them is the human's call: ask them to edit it, or to start the session with SLICKRAILS_ALLOW_BYPASS=1."
  } >&2
  exit 2
}

# edit tools: only the target path matters
case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit)
    [ "$BYPASS_OK" = "1" ] && exit 0
    printf '%s' "$FPATH" | tr '\134' '/' | grep -Eq "$GUARD_PATH" && block_guardrails "$FPATH"
    exit 0;;
esac
if [ "$PARSED" = "0" ] && printf '%s' "$IN" | grep -Eq '"tool_name"[[:space:]]*:[[:space:]]*"(Edit|Write|MultiEdit|NotebookEdit)"'; then
  [ "$BYPASS_OK" = "1" ] && exit 0
  printf '%s' "$IN" | grep -Eq '(\.slickrails/[^/"]*\.sh|\.githooks/[^"]*|\.claude/settings(\.local)?\.json|\.codex/hooks\.json)"' \
    && block_guardrails "a guardrail file"
  exit 0
fi
# What is left of a command once everything that is not a shell word is gone: text inside '...' and "...", comments,
# and heredoc bodies (commit messages are usually written that way). One pass that follows the shell's own rules:
# quotes and backslash escapes are tracked, `<<` only opens a heredoc outside quotes and comments (`<<<` is a
# here-string and opens none), `<<WORD` ends at a line that is exactly WORD, `<<-WORD` at a line that is WORD after
# leading TABs, several heredocs on one line are consumed in order. Output: the remaining words, one line per command
# line (a line ending in \ or inside an open quote continues), so a pattern never runs from one command into the next.
# `scan_command redir` prints only the targets of > outside quotes (a quoted target is kept whole).
# `scan_command keep` keeps the quoted text (paths and SQL often sit in quotes) and puts every simple command on its
# own line: ; & | ( ) outside quotes end one, inside quotes they are text (psql -c "BEGIN; DROP TABLE x").
scan_command() {
  awk -v mode="${1:-}" '
    # put: quoted text is kept in keep mode, and in redir mode while a redirect target is being read
    function put(s) { if (keep || (rd && tgt == 2)) out = out s }
    BEGIN { SQ = "\047"; DQ = "\042"; inq = ""; out = ""; hdcount = 0; hdi = 0
            keep = (mode == "keep"); rd = (mode == "redir"); tgt = 0 }
    {
      if (hdcount > 0) {                       # inside heredoc bodies: drop lines until the terminator
        t = $0
        if (hddash[hdi]) sub(/^\t+/, "", t)
        if (t == hd[hdi]) { hdi++; if (hdi > hdcount) { hdcount = 0; hdi = 0 } }
        next
      }
      line = $0; L = length(line); i = 1; cont = 0
      while (i <= L) {
        c = substr(line, i, 1)
        if (inq == SQ) { put(c); if (c == SQ) inq = ""; i++; continue }
        if (inq == DQ) {
          if (c == "\\") { put(substr(line, i, 2)); i += 2; continue }
          put(c); if (c == DQ) inq = ""; i++; continue
        }
        if (c == "\\") { if (i == L) cont = 1; i += 2; continue }
        if (c == SQ || c == DQ) { if (rd && tgt == 1) tgt = 2; put(c); inq = c; i++; continue }
        if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t;&|(]/)) break
        if (c == "<" && substr(line, i, 2) == "<<") {
          if (substr(line, i, 3) == "<<<") { i += 3; continue }
          j = i + 2; dash = 0
          if (substr(line, j, 1) == "-") { dash = 1; j++ }
          while (substr(line, j, 1) ~ /[ \t]/) j++
          rest = substr(line, j); word = ""; q = substr(rest, 1, 1)
          if (q == SQ || q == DQ) {
            k = index(substr(rest, 2), q)
            if (k > 0) { word = substr(rest, 2, k - 1); j += k + 1 }
          } else if (match(rest, /^\\?[A-Za-z_][A-Za-z0-9_]*/)) {
            word = substr(rest, 1, RLENGTH); sub(/^\\/, "", word); j += RLENGTH
          }
          if (word != "") { hdcount++; hd[hdcount] = word; hddash[hdcount] = dash; i = j; continue }
          i += 2; continue
        }
        if (keep && c ~ /[;&|()]/) { out = out "\n"; i++; continue }   # a separator outside quotes ends a command
        if (rd) {   # only the word after a > outside quotes, one per line (2>&1: the & ends it)
          if (c == ">") { if (tgt == 2) out = out "\n"; tgt = 1 }
          else if (c ~ /[ \t;&|()<]/) { if (tgt == 2) out = out "\n"; if (c != " " && c != "\t") tgt = 0; else if (tgt == 2) tgt = 0 }
          else if (tgt >= 1) { tgt = 2; out = out c }
          i++; continue
        }
        out = out c; i++
      }
      if (rd && tgt == 2 && !cont && inq == "") { out = out "\n"; tgt = 0 }
      out = out ((cont || inq != "") ? " " : "\n")   # a line is a command, unless it continues (\ or an open quote)
      if (hdcount > 0 && hdi == 0) hdi = 1
    }
    END { printf "%s\n", out }'
}

if [ "$PARSED" = "1" ]; then
  TEXT="$(printf '%s\n' "$CMD" | scan_command)"
  KEEP="$(printf '%s\n' "$CMD" | scan_command keep)"
  REDIR="$(printf '%s\n' "$CMD" | scan_command redir)"   # the targets of > outside quotes, one per line
else
  TEXT="$IN"
  KEEP="$(printf '%s' "$IN" | sed 's/.*"command"[[:space:]]*:[[:space:]]*"//' | awk '{ gsub(/[;&|()]/, "\n"); print }')"
  REDIR="$(printf '%s\n' "$KEEP" | sed -n 's/.*>[[:space:]]*//p')"
fi
# simple commands, one per line, without leading assignments and wrappers (sudo, env, command, exec, nohup, time)
SEGS="$(printf '%s\n' "$KEEP" | sed -E -e 's/^[[:space:]]*//' \
  -e ':w' -e 's/^(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|sudo|env|command|exec|nohup|time)[[:space:]]+)//' -e 'tw')"

GIT='(^|[^[:alnum:]_.-])git[[:space:]]'   # the word git (not lazygit, not .github), followed by a space
match() { printf '%s' "$TEXT" | grep -Eq "$1"; }
seg()   { printf '%s\n' "$SEGS" | grep -E "$1"; }   # the simple commands that match <regex>

WHAT=""
if   match "${GIT}[^|;&]*--no-ver[a-z]*";                                           then WHAT="--no-verify"
elif match "${GIT}[^|;&]*commit[^|;&]*[[:space:]]-[a-zA-Z]*n";                      then WHAT="git commit -n (= --no-verify)"
elif match 'SLICKRAILS_SKIP=';                                                      then WHAT="SLICKRAILS_SKIP"
elif match 'core\.hooksPath=';                                                      then WHAT="core.hooksPath override"
elif match "${GIT}[^|;&]*config[^|;&]*--unset(-all)?[^|;&]*core\\.hooksPath";       then WHAT="unsetting core.hooksPath"
elif match "${GIT}[^|;&]*config[^|;&]*core\\.hooksPath[[:space:]]+[^[:space:]&|;]" \
     && ! match 'core\.hooksPath[[:space:]]+(\./)?\.githooks/?([[:space:]&|;]|$)';  then WHAT="redirecting core.hooksPath"
fi

if [ -n "$WHAT" ] && [ "$BYPASS_OK" = "0" ]; then
  {
    echo "slickrails: blocked — this command bypasses the git hooks ($WHAT)."
    echo "Fix what the hook complains about instead. If a human decided to bypass on purpose, they start the"
    echo "session with SLICKRAILS_ALLOW_BYPASS=1 in the environment and give the reason in the commit message."
  } >&2
  exit 2
fi

# writing to a guardrail file: a writing command that names one, or a redirect onto one
if [ "$BYPASS_OK" = "0" ]; then
  if seg '^((rm|mv|cp|tee|truncate|chmod|chown|ln|install|dd|unlink)[[:space:]]|sed[[:space:]].*-i|perl[[:space:]].*-[a-zA-Z]*i)' \
       | grep -Eq "$GUARD_WORD" \
     || printf '%s\n' "$REDIR" | grep -Eq "$GUARD_WORD"; then
    block_guardrails "the target of this command"
  fi
fi

# commands that lose uncommitted work, history or data
# discards_all: a git checkout/restore of everything, judged per simple command (quoted text is already gone from
# TEXT, so its separators are real): --staged/-S alone only unstages, with --worktree/-W it discards too
discards_all() {
  printf '%s\n' "$TEXT" | awk '{ gsub(/[;&|()]/, "\n"); print }' \
    | grep -E "${GIT}.*(checkout|restore).*[[:space:]](\\.|:/|\\*)([[:space:]]|\$)" \
    | grep -Ev "[[:space:]](--staged|-[a-zA-Z]*S[a-zA-Z]*)([[:space:]]|\$)" | grep -q . && return 0
  printf '%s\n' "$TEXT" | awk '{ gsub(/[;&|()]/, "\n"); print }' \
    | grep -E "${GIT}.*restore.*[[:space:]](\\.|:/|\\*)([[:space:]]|\$)" \
    | grep -E "[[:space:]](--worktree|-[a-zA-Z]*W[a-zA-Z]*)([[:space:]]|\$)" | grep -q .
}
WHAT=""
# (matched on the rm command with its quotes taken out: "$HOME"/ and "$HOME"/* are $HOME/ and $HOME/*)
DANGER_TARGET="[[:space:]](/|/\\*|~|~/|~/\\*|\\\$HOME|\\\$\\{HOME\\}|\\\$HOME/\\*?|\\\$\\{HOME\\}/\\*?|\\.|\\./|\\./\\*|\\.\\.|\\.\\./|\\*|\\.git|\\./\\.git)/?([[:space:]]|\$)"
if   match "${GIT}[^|;&]*reset[^|;&]*--hard";                                       then WHAT="git reset --hard"
elif match "${GIT}[^|;&]*clean[^|;&]*[[:space:]](-[a-zA-Z]*f|--force)";             then WHAT="git clean -f"
elif match "${GIT}[^|;&]*push[^|;&]*[[:space:]](--force|-[a-zA-Z]*f[a-zA-Z]*)([[:space:]]|\$)"; then
  WHAT="git push --force (use --force-with-lease)"
elif match "${GIT}[^|;&]*push[^|;&]*(--force-with-lease|--force-if-includes|[[:space:]]\\+[^[:space:]])" \
     && match "${GIT}[^|;&]*push[^|;&]*[[:space:]:+](main|master)([[:space:]]|\$)"; then WHAT="a forced push onto main"
elif discards_all; then
  WHAT="discarding every uncommitted change"
elif seg '^rm[[:space:]]' | grep -E '[[:space:]](-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)' \
     | tr -d "\"'" | grep -Eq "$DANGER_TARGET";                                                   then WHAT="rm -r on a root, home or repository folder"
elif match 'migrate:(fresh|reset|refresh)|db:(drop|reset)|prisma[[:space:]]+migrate[[:space:]]+reset|--force-reset|manage\.py[[:space:]]+(flush|reset_db)|(^|[[:space:]])dropdb[[:space:]]'; then
  WHAT="a database reset"
elif seg '^(psql|mysql|mariadb|sqlite3|mongosh|sqlcmd|clickhouse-client)[[:space:]]' \
     | grep -Eiq 'drop[[:space:]]+(database|table|schema)|truncate[[:space:]]';     then WHAT="DROP/TRUNCATE on a database"
fi

if [ -n "$WHAT" ] && [ "$DESTROY_OK" = "0" ]; then
  {
    echo "slickrails: blocked — this command can destroy work or data ($WHAT)."
    echo "Find a reversible way (a new commit, git stash, --force-with-lease, a migration that can be rolled back)."
    echo "If it is really meant, the human runs it themselves (Claude Code: ! <command>) or starts the session"
    echo "with SLICKRAILS_ALLOW_DESTRUCTIVE=1."
  } >&2
  exit 2
fi

# installing a package by name: does it exist, and is it older than a few weeks? (dep-check.sh, next to this script;
# it fails open, and a crash of it does not block)
DEP_CHECK="$(dirname "$0")/dep-check.sh"
if [ -f "$DEP_CHECK" ] && seg '^(npm|pnpm|yarn|bun|pip3?|python3?|uv|poetry)[[:space:]]' >/dev/null; then
  DEP_RC=0; printf '%s\n' "$SEGS" | sh "$DEP_CHECK" || DEP_RC=$?
  [ "$DEP_RC" = "2" ] && exit 2
fi

exit 0

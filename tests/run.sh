#!/bin/sh
# slickrails test suite — exercises the installer and every hook end to end.
# Usage: sh tests/run.sh          (from the kit root or anywhere)
# Exit 0 = all green. POSIX sh, no dependencies beyond git + node (for node tests).
#
# Deliberate patterns of this suite, not of the kit's scripts (those stay fully checked in CI):
#   SC2016 stub scripts, JSON and hook commands are written as literal single-quoted text on purpose
#   SC2009 leftover-process checks grep `ps` for a tag unique to this run (the full command line is the point)
#   SC2181 `cmd; [ $? -eq 0 ] && ok || fail` is the suite's assertion idiom, like SC2015 in CI
#   SC2012 `ls` only lists a test repo's files inside a failure message, for the reader
# shellcheck disable=SC2016,SC2009,SC2181,SC2012

set -u

# Run from a git hook (pre-push), git exports GIT_DIR and friends; every `git init` / `git commit` below would then
# write into the kit's own repository instead of the temporary ones (this happened: core.bare=true, test branches,
# test identity and test pushes to the real remote). The suite never uses the caller's repository through them.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_QUARANTINE_PATH

# Git Bash: `ln -s` makes a copy unless asked for a native symlink. Several tests build a tool box of symlinks (a PATH
# without jq, a symlinked settings file); on the GitHub runner native symlinks are allowed. No effect elsewhere.
MSYS="${MSYS:+$MSYS }winsymlinks:nativestrict"; export MSYS

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# The installer turns the local AI review on when it finds claude or codex; the many test repos must not call the
# real CLI on every test push. The tests of that detection set it themselves.
SLICKRAILS_REVIEW=off; export SLICKRAILS_REVIEW
WORK="$(mktemp -d "${TMPDIR:-/tmp}/slickrails-tests.XXXXXX")"
# Tests that look for leftover processes by name use tags unique to this run (PID-based): two suites may
# run at once (e.g. a Stop hook running this suite while another one is started) and must not see each other.
RT_UNIQ="$((100 + $$ % 800))"                                   # REVIEW_TIMEOUT seconds
# sleep durations, about 30 s: a process the kit failed to stop must still be running when the test looks, and
# "stopped in time" must not be confused with "ended by itself" on a slow runner (Git Bash)
TAG_A="30.1$$"; TAG_B="30.2$$"; TAG_C="30.3$$"; TAG_D="30.4$$"; TAG_E="30.5$$"
MS_UNIQ="$((270000 + $$ % 9000))"                               # SLICKRAILS_STOP_DEADLINE_MS
SECS_UNIQ="$(printf '%d.%03d' $((MS_UNIQ / 1000)) $((MS_UNIQ % 1000)))"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

# every process's command line with arguments: POSIX ps, or `ps -ef` on Git Bash (whose ps has no -A/-o)
ps_commands() { ps -A -o command= 2>/dev/null || ps -ef 2>/dev/null; }
# how many running processes match <pattern>; "ps-unusable" when nothing can be listed — never a silent 0
running() { PSC="$(ps_commands)"; [ -n "$PSC" ] || { echo "ps-unusable"; return 0; }; printf '%s\n' "$PSC" | grep -c -- "$1"; }
# a stand-in for the ps of Git Bash (MSYS/Cygwin), built from the real ps: no -A/-o; `ps -e` prints
# "PID PPID PGID WINPID TTY UID STIME COMMAND" with a status letter in front of stopped processes; `ps -p` answers
# by exit status. Measured on GitHub's windows-latest runner (PR #13 diagnostics).
make_msys_ps() { # <dir>
  mkdir -p "$1"
  if ! ps -A -o pid= >/dev/null 2>&1; then   # already on Git Bash: the real ps is the one to test against
    printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v ps)" > "$1/ps"; chmod +x "$1/ps"; return 0
  fi
  cat > "$1/ps" <<MSYSPS
#!/bin/sh
case "\$1" in
  -e) echo "      PID    PPID    PGID     WINPID   TTY         UID    STIME COMMAND"
      "$(command -v ps)" -A -o stat=,pid=,ppid= | awk '{ s = (\$1 ~ /^T/) ? "S" : " "; printf "%s %8s %7s %7s %10s  ?  1000 00:00:00 /usr/bin/x\n", s, \$2, \$3, \$3, \$2 }' ;;
  -p) echo "      PID    PPID    PGID     WINPID   TTY         UID    STIME COMMAND"
      "$(command -v ps)" -p "\$2" -o pid=,ppid= ;;
  *)  echo "ps: unknown option -- \${1#-}" >&2; exit 1 ;;
esac
MSYSPS
  chmod +x "$1/ps"
}

# a stand-in for jq on Windows: a native program that ends every output line with \r\n (measured on the GitHub
# runner); the exit status is the real one
make_crlf_jq() { # <dir>
  mkdir -p "$1"
  cat > "$1/jq" <<CRLFJQ
#!/bin/sh
"$(command -v jq)" "\$@" > "$1/out.\$\$"; RC=\$?
awk '{ printf "%s\r\n", \$0 }' "$1/out.\$\$"; rm -f "$1/out.\$\$"
exit \$RC
CRLFJQ
  chmod +x "$1/jq"
}

ok()   { PASS=$((PASS+1)); printf 'PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL  %s\n' "$1"; }

# expect <description> <expected-exit> <command...>
expect() {
  DESC="$1"; WANT="$2"; shift 2
  "$@" >/dev/null 2>&1
  GOT=$?
  if [ "$GOT" -eq "$WANT" ]; then ok "$DESC"; else fail "$DESC (exit $GOT, wanted $WANT)"; fi
}

new_repo() { # new_repo <name> [files-setup-fn]
  R="$WORK/$1"
  rm -rf "$R"; mkdir -p "$R"; cd "$R"
  git init -q
  git config user.email test@slickrails.local
  git config user.name  "slickrails Tests"
}

# ------------------------------------------------------------ installer -----

new_repo node-repo
printf '{"name":"t","scripts":{"test":"node -e \\"console.log(1)\\""},"devDependencies":{"@playwright/test":"^1.0.0"}}' > package.json
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
[ -f .slickrails/SLICKRAILS.md ] && [ -f .slickrails/config.sh ] && [ -f .githooks/pre-push ] \
  && [ -f .github/workflows/ci.yml ] && [ -f .github/workflows/pr-size.yml ] \
  && [ -f .github/workflows/smoke.yml ] && [ -f docs/features/_TEMPLATE.md ] \
  && [ -f .claude/settings.json ] \
  && ok "installer: node repo gets full file set" \
  || fail "installer: node repo gets full file set"

[ "$(git config core.hooksPath)" = ".githooks" ] \
  && ok "installer: core.hooksPath set" || fail "installer: core.hooksPath set"
grep -q '^CHECK_PREPUSH_REVIEW="0"' .slickrails/config.sh && ok "installer: SLICKRAILS_REVIEW=off leaves the local review off" \
  || fail "installer: SLICKRAILS_REVIEW=off leaves the local review off"


grep -q 'slickrails:start' CLAUDE.md && grep -q 'slickrails:start' AGENTS.md \
  && ok "installer: rules block in CLAUDE.md and AGENTS.md" \
  || fail "installer: rules block in CLAUDE.md and AGENTS.md"

BEFORE="$(find . -not -path './.git/*' | sort)"
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
AFTER="$(find . -not -path './.git/*' | sort)"
[ "$BEFORE" = "$AFTER" ] && ! ls ./*.slickrails-new >/dev/null 2>&1 \
  && ok "installer: second run is idempotent" || fail "installer: second run is idempotent"

new_repo py-repo
touch requirements.txt; mkdir -p tests
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
grep -q 'pytest' .slickrails/config.sh \
  && ok "installer: python stack detected" || fail "installer: python stack detected"

new_repo lang-repo
printf '{"name":"t"}' > package.json
sh "$KIT_DIR/install.sh" --lang de . >/dev/null 2>&1
grep -q 'verbindlich' CLAUDE.md \
  && ok "installer: --lang de installs German rules block" \
  || fail "installer: --lang de installs German rules block"

new_repo go-repo
printf 'module example.com/t\n' > go.mod
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
grep -q 'go test' .slickrails/config.sh && grep -q 'setup-go' .github/workflows/ci.yml \
  && ok "installer: go stack detected (config + ci)" || fail "installer: go stack detected (config + ci)"

new_repo rust-repo
printf '[package]\nname = "t"\n' > Cargo.toml
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
grep -q 'cargo test' .slickrails/config.sh \
  && ok "installer: rust stack detected" || fail "installer: rust stack detected"

new_repo pnpm-repo
printf '{"name":"t","scripts":{"test":"node -e \\"console.log(1)\\""}}' > package.json
touch pnpm-lock.yaml
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
grep -q 'pnpm run --if-present test' .slickrails/config.sh \
  && ok "installer: pnpm detected from lockfile" || fail "installer: pnpm detected from lockfile"

# setup follows what the user has: a local claude or codex turns the pre-push review on with that CLI (no API key)
RDET="$WORK/review-detect"; mkdir -p "$RDET/claude-only" "$RDET/codex-only" "$RDET/both" "$RDET/tb"
P="$(command -v git)" && printf '#!/bin/sh\nexec "%s" "$@"\n' "$P" > "$RDET/tb/git" && chmod +x "$RDET/tb/git"
for D in claude-only both; do printf '#!/bin/sh\nexit 0\n' > "$RDET/$D/claude"; chmod +x "$RDET/$D/claude"; done
for D in codex-only both; do printf '#!/bin/sh\nexit 0\n' > "$RDET/$D/codex"; chmod +x "$RDET/$D/codex"; done
review_detect() { # <description> <stub-dir|none> <want CHECK_PREPUSH_REVIEW> <want REVIEW_CLI> [installer args...]
  RD_D="$1"; RD_P="$RDET/$2"; RD_C="$3"; RD_W="$4"; shift 4
  new_repo "review-detect-$RD_C-$RD_W-$#"
  env SLICKRAILS_REVIEW=auto SLICKRAILS_CODEX_APP=/nonexistent PATH="$RD_P:$RDET/tb:/usr/bin:/bin" sh "$KIT_DIR/install.sh" "$@" >"$WORK/rd.out" 2>&1
  if grep -q "^CHECK_PREPUSH_REVIEW=\"$RD_C\"" .slickrails/config.sh && grep -q "^REVIEW_CLI=\"$RD_W\"" .slickrails/config.sh; then ok "installer: $RD_D"
  else fail "installer: $RD_D ($(grep -E '^(CHECK_PREPUSH_REVIEW|REVIEW_CLI)=' .slickrails/config.sh | tr '\n' ' '))"; fi
}
review_detect "a local claude turns the pre-push review on with claude" claude-only 1 claude
grep -E '^\| 6 \|' .slickrails/STATUS.md | grep -q '☑' && ok "installer: with the local review on, the AI-review rule counts as in place" \
  || fail "installer: with the local review on, the AI-review rule counts as in place ($(grep -E '^\| 6 \|' .slickrails/STATUS.md))"
review_detect "a local codex turns it on with codex"                    codex-only  1 codex
review_detect "with both, --agent codex picks codex"                    both        1 codex --agent codex
review_detect "with both, the default picks claude"                     both        1 claude
review_detect "without either it stays off"                             none        0 auto
grep -q "no claude or codex CLI" "$WORK/rd.out" && ok "installer: says when no reviewer CLI was found" || fail "installer: says when no reviewer CLI was found"
review_detect "--review off wins over a found CLI"                      claude-only 0 auto --review off
DOC_OUT="$(env PATH="$RDET/claude-only:$RDET/tb:/usr/bin:/bin" sh "$KIT_DIR/install.sh" doctor 2>&1)"
case "$DOC_OUT" in *"local AI review before push is off, but the claude CLI is here"*) ok "doctor: an off review with a local claude is pointed out";; *) fail "doctor: an off review with a local claude is pointed out";; esac

# bundled: the kit's own files live under .slickrails/, nothing of it in the project root except the rules block
new_repo bundle-fresh-repo
sh "$KIT_DIR/install.sh" > "$WORK/inst.out" 2>&1
if [ -f .slickrails/SLICKRAILS.md ] && [ -f .slickrails/STATUS.md ] && [ ! -e SLICKRAILS.md ] && [ ! -e SLICKRAILS-STATUS.md ] && [ ! -e scripts ]; then
  ok "installer: rulebook and status live in .slickrails/, no root files, no scripts/ folder"
else fail "installer: rulebook and status live in .slickrails/, no root files, no scripts/ folder ($(ls | tr '\n' ' '))"; fi
grep -q '\.slickrails/SLICKRAILS\.md' CLAUDE.md && grep -q '\.slickrails/STATUS\.md' AGENTS.md \
  && ok "installer: the agent rules block points at the bundled files" || fail "installer: the agent rules block points at the bundled files"
# quiet by default: a summary, not one line per file; the next steps fit the repo (no remote: no branch protection)
grep -q '+ .githooks/pre-commit' "$WORK/inst.out" && fail "installer: no line per file by default" || ok "installer: no line per file by default"
grep -Eq 'files added' "$WORK/inst.out" && ok "installer: says how many files it added" || fail "installer: says how many files it added"
grep -q 'slickrails protect' "$WORK/inst.out" && fail "installer: no branch-protection step without a GitHub remote" || ok "installer: no branch-protection step without a GitHub remote"
new_repo bundle-github-repo
git remote add origin https://github.com/example/app.git
sh "$KIT_DIR/install.sh" --verbose > "$WORK/inst.out" 2>&1
grep -q '+ .githooks/pre-commit' "$WORK/inst.out" && ok "installer: --verbose lists every file" || fail "installer: --verbose lists every file"
grep -q 'slickrails protect' "$WORK/inst.out" && ok "installer: with a GitHub remote the branch-protection step is shown" || fail "installer: with a GitHub remote the branch-protection step is shown"
# an older install is moved, not duplicated: the user's edits survive, an untouched protection script goes away
new_repo bundle-migrate-repo
printf 'my rulebook edits\n' > SLICKRAILS.md; printf 'my status notes\n' > SLICKRAILS-STATUS.md
# the rules block and the CI workflow an older install wrote, with the old paths
printf '<!-- slickrails:start -->\nThis repo follows the slickrails standard (see `SLICKRAILS.md`).\n- Track gaps in `SLICKRAILS-STATUS.md`.\n<!-- slickrails:end -->\n' > CLAUDE.md
cp CLAUDE.md AGENTS.md; mkdir -p .github/workflows; printf 'run: echo "record this as a gap in SLICKRAILS-STATUS.md."\n' > .github/workflows/ci.yml
mkdir scripts; cp "$KIT_DIR/scripts/setup-branch-protection.sh" scripts/
sh "$KIT_DIR/install.sh" > "$WORK/inst.out" 2>&1
if grep -q 'my rulebook edits' .slickrails/SLICKRAILS.md && grep -q 'my status notes' .slickrails/STATUS.md && [ ! -e SLICKRAILS.md ] && [ ! -e SLICKRAILS-STATUS.md ] && [ ! -e scripts ]; then
  ok "installer: an older install's root files move into .slickrails/ with their edits, the unchanged script goes"
else fail "installer: an older install's root files move into .slickrails/ with their edits, the unchanged script goes ($(ls | tr '\n' ' '))"; fi
grep -q 'moved SLICKRAILS.md' "$WORK/inst.out" && ok "installer: says what it moved" || fail "installer: says what it moved"
# the agents and CI must find the moved files (found by the real claude review, 2026-10-29)
if grep -q '`.slickrails/SLICKRAILS.md`' CLAUDE.md && grep -q '`.slickrails/STATUS.md`' AGENTS.md && grep -q '.slickrails/STATUS.md' .github/workflows/ci.yml \
   && ! grep -Eq '(^|[^/])SLICKRAILS-STATUS\.md|`SLICKRAILS\.md`' CLAUDE.md AGENTS.md .github/workflows/ci.yml; then
  ok "installer: the rules block and the CI workflow point at the moved files"
else fail "installer: the rules block and the CI workflow point at the moved files ($(grep -h 'SLICKRAILS' CLAUDE.md .github/workflows/ci.yml | tr '\n' ' '))"; fi
new_repo bundle-edited-script-repo
mkdir scripts; printf '#!/bin/sh\necho my own protection\n' > scripts/setup-branch-protection.sh
sh "$KIT_DIR/install.sh" > "$WORK/inst.out" 2>&1
[ -f scripts/setup-branch-protection.sh ] && grep -q 'no longer needed' "$WORK/inst.out" \
  && ok "installer: an edited protection script stays, with a note" || fail "installer: an edited protection script stays, with a note"

# the local review is the default; the server-side review on GitHub is set up on request
new_repo review-default-repo
sh "$KIT_DIR/install.sh" > "$WORK/inst.out" 2>&1
[ ! -e .github/workflows/claude-review.yml ] && ok "installer: no GitHub review workflow by default (the local review is the default)" \
  || fail "installer: no GitHub review workflow by default (the local review is the default)"
grep -q 'slickrails github-review' "$WORK/inst.out" && ok "installer: says how to add the review on GitHub" || fail "installer: says how to add the review on GitHub"
new_repo review-github-repo
sh "$KIT_DIR/install.sh" --github-review >/dev/null 2>&1
[ -f .github/workflows/claude-review.yml ] && ok "installer: --github-review adds the GitHub review workflow" || fail "installer: --github-review adds the GitHub review workflow"
new_repo review-later-repo
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
GR_OUT="$(sh "$KIT_DIR/bin/slickrails" github-review 2>&1)"
[ -f .github/workflows/claude-review.yml ] && case "$GR_OUT" in *"github.com/apps/claude"*"CLAUDE_CODE_OAUTH_TOKEN"*) true;; *) false;; esac \
  && ok "cli: slickrails github-review adds the workflow later and names the App and the secret" \
  || fail "cli: slickrails github-review adds the workflow later and names the App and the secret"
# the status mod: offered to the team through the project settings, on request only
new_repo status-mod-repo
sh "$KIT_DIR/install.sh" --status-mod >/dev/null 2>&1
if command -v jq >/dev/null 2>&1; then
  jq -e '.enabledPlugins["slickrails-status@slickrails"] == true and (.extraKnownMarketplaces.slickrails.source.repo | length > 0)
         and (.hooks.Stop | length == 1)' .claude/settings.json >/dev/null 2>&1 \
    && ok "installer: --status-mod offers the status mod to the team in .claude/settings.json (hooks kept)" \
    || fail "installer: --status-mod offers the status mod to the team in .claude/settings.json ($(tr -d '\n ' < .claude/settings.json | head -c 300))"
fi
new_repo no-status-mod-repo
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
grep -q 'enabledPlugins' .claude/settings.json && fail "installer: no status mod without --status-mod" || ok "installer: no status mod without --status-mod"

# ------------------------------------------------------------------- CLI ----

CLI_V="$(sh "$KIT_DIR/bin/slickrails" version 2>/dev/null || true)"
[ "$CLI_V" = "$(cat "$KIT_DIR/VERSION")" ] \
  && ok "cli: version matches VERSION file" || fail "cli: version matches VERSION file (got '$CLI_V')"

new_repo cli-repo
printf '{"name":"t"}' > package.json
sh "$KIT_DIR/bin/slickrails" init . >/dev/null 2>&1
[ -f .slickrails/SLICKRAILS.md ] && [ -f .slickrails/ai-review.sh ] \
  && ok "cli: init installs the kit (incl. ai-review.sh)" || fail "cli: init installs the kit (incl. ai-review.sh)"
[ -f .slickrails/review-learnings.md ] && grep -q 'REVIEW_PROFILE="chill"' .slickrails/config.sh \
  && ok "installer: review learnings + profile installed" || fail "installer: review learnings + profile installed"
# branch protection comes from the kit, not from a copy in every repo
mkdir -p "$WORK/protect-stub"; printf '#!/bin/sh\necho "gh $*" >> "%s/protect-stub/calls"\nexit 1\n' "$WORK" > "$WORK/protect-stub/gh"; chmod +x "$WORK/protect-stub/gh"
PATH="$WORK/protect-stub:$PATH" sh "$KIT_DIR/bin/slickrails" protect >/dev/null 2>&1
grep -q '^gh repo view' "$WORK/protect-stub/calls" 2>/dev/null && ok "cli: slickrails protect runs the kit's branch-protection script in this repo" \
  || fail "cli: slickrails protect runs the kit's branch-protection script in this repo"

# slickrails status: one screen — health (from doctor), checks, reviewer, rules from STATUS.md, dossiers
new_repo status-repo
printf '{"name":"t","scripts":{"test":"echo ok"}}' > package.json
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
mkdir -p docs/features; printf '# Login\n' > docs/features/login.md
git add -A >/dev/null 2>&1; git commit -qm "install" --no-verify >/dev/null 2>&1
ST_OUT="$(sh "$KIT_DIR/bin/slickrails" status 2>&1)"; ST_RC=$?
[ "$ST_RC" -eq 0 ] && ok "status: runs in an installed repo (exit 0)" || fail "status: runs in an installed repo (exit $ST_RC)"
case "$ST_OUT" in *"Health"*"0 problems"*) ok "status: health comes from doctor's checks";; *) fail "status: health comes from doctor's checks ($(printf '%s' "$ST_OUT" | grep -i health))";; esac
case "$ST_OUT" in *"Checks"*"npm"*) ok "status: shows the configured checks";; *) fail "status: shows the configured checks";; esac
case "$ST_OUT" in *"Review"*"off"*) ok "status: shows that the local review is off";; *) fail "status: shows that the local review is off";; esac
case "$ST_OUT" in *"Rules"*"of 12"*"Branch protection on main"*) ok "status: counts the rules from STATUS.md and names the open ones";; *) fail "status: counts the rules from STATUS.md and names the open ones ($(printf '%s' "$ST_OUT" | grep -i rules))";; esac
case "$ST_OUT" in *"Dossiers"*"1"*"login"*) ok "status: counts the feature dossiers";; *) fail "status: counts the feature dossiers ($(printf '%s' "$ST_OUT" | grep -i dossier))";; esac
git config --unset core.hooksPath
ST_OUT="$(CI='' sh "$KIT_DIR/bin/slickrails" status 2>&1)"
case "$ST_OUT" in *"1 problem"*"core.hooksPath"*) ok "status: a problem doctor finds is named";; *) fail "status: a problem doctor finds is named ($(printf '%s' "$ST_OUT" | grep -iE 'health|problem' | head -3 | tr '\n' ' '))";; esac
new_repo status-empty-repo
ST_OUT="$(sh "$KIT_DIR/bin/slickrails" status 2>&1)"; ST_RC=$?
case "$ST_OUT" in *"not installed"*) [ "$ST_RC" -ne 0 ] && ok "status: a repo without slickrails says so (exit $ST_RC)" || fail "status: a repo without slickrails says so (exit 0)";; *) fail "status: a repo without slickrails says so";; esac
# --porcelain: what the status mod reads, one key=value per line, no doctor run (fast enough after every turn)
cd "$WORK/status-repo" || exit 1
git config core.hooksPath .githooks
printf 'green %s\n' "$(date +%s)" > "$(git rev-parse --git-dir)/slickrails-last-gate"
PO="$(sh "$KIT_DIR/bin/slickrails" status --porcelain 2>&1)"
for KV in installed=1 review=off gate=green rules_total=12 dossiers=1 hooks=1 guard=1; do
  case "$PO" in *"$KV"*) ok "status --porcelain: $KV";; *) fail "status --porcelain: $KV ($(printf '%s' "$PO" | tr '\n' ' '))";; esac
done
case "$PO" in *rules_open=*) ok "status --porcelain: rules_open";; *) fail "status --porcelain: rules_open";; esac
cd "$WORK/status-empty-repo" || exit 1
case "$(sh "$KIT_DIR/bin/slickrails" status --porcelain 2>&1)" in "installed=0") ok "status --porcelain: installed=0 outside a slickrails repo";; *) fail "status --porcelain: installed=0 outside a slickrails repo";; esac
# a repo whose Stop gate never ran has no gate file: that is gate=none, not an error message (seen on a fresh checkout)
cd "$WORK/status-repo" || exit 1
rm -f "$(git rev-parse --git-dir)/slickrails-last-gate"
ST_ERR="$(sh "$KIT_DIR/bin/slickrails" status --porcelain 2>&1 >/dev/null)"; ST_ERR2="$(sh "$KIT_DIR/bin/slickrails" status 2>&1 >/dev/null)"
[ -z "$ST_ERR$ST_ERR2" ] && ok "status: no gate file yet is quiet (no error on stderr)" || fail "status: no gate file yet is quiet ($ST_ERR$ST_ERR2)"
case "$(sh "$KIT_DIR/bin/slickrails" status --porcelain 2>/dev/null)" in *"gate=none"*) ok "status --porcelain: gate=none before the first Stop gate run";; *) fail "status --porcelain: gate=none before the first Stop gate run";; esac
# the mod ships with the kit: a marketplace entry, a manifest, a hooks module
if command -v jq >/dev/null 2>&1; then
  jq -e '.plugins[] | select(.name == "slickrails-status") | .source' "$KIT_DIR/.claude-plugin/marketplace.json" >/dev/null 2>&1 \
    && jq -e '.name == "slickrails-status"' "$KIT_DIR/mods/slickrails-status/.claude-plugin/plugin.json" >/dev/null 2>&1 \
    && jq -e '.modules | length == 1' "$KIT_DIR/mods/slickrails-status/hooks/hooks.json" >/dev/null 2>&1 \
    && [ -f "$KIT_DIR/mods/slickrails-status/hooks/register.ts" ] \
    && ok "mod: slickrails-status ships with a marketplace entry, manifest and hooks module" \
    || fail "mod: slickrails-status ships with a marketplace entry, manifest and hooks module"
fi

# ------------------------------------------------------------- bootstrap ----

BOOT_HOME="$WORK/boot-home"
BOOT_BIN="$WORK/boot-bin"
mkdir -p "$BOOT_BIN"
# SLICKRAILS_BIN keeps the test from touching the user's real bin dirs.
if git -C "$KIT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  SLICKRAILS_REPO="$KIT_DIR" SLICKRAILS_HOME="$BOOT_HOME" SLICKRAILS_BIN="$BOOT_BIN" \
    sh "$KIT_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  [ -x "$BOOT_HOME/bin/slickrails" ] && [ -x "$BOOT_BIN/slickrails" ] \
    && [ "$(sh "$BOOT_HOME/bin/slickrails" version)" = "$(cat "$KIT_DIR/VERSION")" ] \
    && ok "bootstrap: clones kit, links CLI into SLICKRAILS_BIN" \
    || fail "bootstrap: clones kit, links CLI into SLICKRAILS_BIN"
  [ "$(sh "$BOOT_BIN/slickrails" version 2>/dev/null)" = "$(cat "$KIT_DIR/VERSION")" ] \
    && ok "bootstrap: the command in SLICKRAILS_BIN works" || fail "bootstrap: the command in SLICKRAILS_BIN works"
  # the README media are not part of the tool: the clone leaves them out (on Windows too, where Git Bash rewrites
  # arguments that look like paths)
  if [ -f "$BOOT_HOME/install.sh" ] && [ ! -e "$BOOT_HOME/assets" ] && [ ! -e "$BOOT_HOME/demo" ]; then
    ok "bootstrap: the clone leaves the README media (assets/, demo/) out"
  else fail "bootstrap: the clone leaves the README media (assets/, demo/) out ($(ls "$BOOT_HOME" | tr '\n' ' '))"; fi
  # a half install (a .git without files, the checkout was interrupted) is completed on the next run
  # (one commit behind upstream: the pull must not take the missing files for deletions)
  rm -rf "$WORK/boot-up" "$WORK/boot-half"; git clone -q "$KIT_DIR" "$WORK/boot-up" 2>/dev/null
  git clone -q --no-checkout "$WORK/boot-up" "$WORK/boot-half" 2>/dev/null
  ( cd "$WORK/boot-up" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "upstream moved on" )
  SLICKRAILS_REPO="$WORK/boot-up" SLICKRAILS_HOME="$WORK/boot-half" SLICKRAILS_BIN="$BOOT_BIN" sh "$KIT_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  [ -f "$WORK/boot-half/install.sh" ] && [ "$(git -C "$WORK/boot-half" log -1 --format=%s 2>/dev/null)" = "upstream moved on" ] \
    && ok "bootstrap: a half install one commit behind is checked out and updated on the next run" \
    || fail "bootstrap: a half install one commit behind is checked out and updated on the next run"
  # an empty SLICKRAILS_HOME made beforehand is used; a non-empty one that is no clone is refused, not nested into
  rm -rf "$WORK/boot-empty"; mkdir -p "$WORK/boot-empty"
  SLICKRAILS_REPO="$KIT_DIR" SLICKRAILS_HOME="$WORK/boot-empty" SLICKRAILS_BIN="$BOOT_BIN" sh "$KIT_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  [ -f "$WORK/boot-empty/install.sh" ] && ok "bootstrap: an empty SLICKRAILS_HOME made beforehand is used" || fail "bootstrap: an empty SLICKRAILS_HOME made beforehand is used"
  rm -rf "$WORK/boot-busy"; mkdir -p "$WORK/boot-busy"; : > "$WORK/boot-busy/notes.txt"
  SLICKRAILS_REPO="$KIT_DIR" SLICKRAILS_HOME="$WORK/boot-busy" SLICKRAILS_BIN="$BOOT_BIN" sh "$KIT_DIR/bootstrap.sh" >/dev/null 2>&1
  BB_RC=$?
  [ "$BB_RC" -ne 0 ] && [ ! -e "$WORK/boot-busy.partial" ] && [ "$(ls "$WORK/boot-busy")" = "notes.txt" ] \
    && ok "bootstrap: a non-empty SLICKRAILS_HOME that is no clone is refused, nothing nested into it" \
    || fail "bootstrap: a non-empty SLICKRAILS_HOME that is no clone is refused (exit $BB_RC)"
  # an interrupted fresh clone leaves only $DEST.partial, which the next run replaces
  rm -rf "$WORK/boot-fresh" "$WORK/boot-fresh.partial"; mkdir -p "$WORK/boot-fresh.partial/.git"
  SLICKRAILS_REPO="$KIT_DIR" SLICKRAILS_HOME="$WORK/boot-fresh" SLICKRAILS_BIN="$BOOT_BIN" sh "$KIT_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  [ -f "$WORK/boot-fresh/install.sh" ] && [ ! -e "$WORK/boot-fresh.partial" ] \
    && ok "bootstrap: a leftover partial clone is replaced, the kit lands in place" || fail "bootstrap: a leftover partial clone is replaced, the kit lands in place"
  # a SLICKRAILS_HOME with a trailing slash: the clone is built next to it, not inside it
  rm -rf "$WORK/boot-slash" "$WORK/boot-slash.partial"
  SLICKRAILS_REPO="$KIT_DIR" SLICKRAILS_HOME="$WORK/boot-slash/" SLICKRAILS_BIN="$BOOT_BIN" sh "$KIT_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  [ -f "$WORK/boot-slash/install.sh" ] && [ ! -e "$WORK/boot-slash/.partial" ] && [ ! -e "$WORK/boot-slash.partial" ] \
    && ok "bootstrap: a SLICKRAILS_HOME with a trailing slash works" || fail "bootstrap: a SLICKRAILS_HOME with a trailing slash works"
  # an explicitly named bin dir that does not exist yet is created, not swapped for ~/.local/bin
  SLICKRAILS_REPO="$KIT_DIR" SLICKRAILS_HOME="$BOOT_HOME" SLICKRAILS_BIN="$WORK/boot-bin-new/sub" HOME="$WORK/boot-fakehome" \
    sh "$KIT_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  [ -x "$WORK/boot-bin-new/sub/slickrails" ] && [ ! -e "$WORK/boot-fakehome/.local/bin/slickrails" ] \
    && ok "bootstrap: a SLICKRAILS_BIN that does not exist yet is created and used" \
    || fail "bootstrap: a SLICKRAILS_BIN that does not exist yet is created and used"
  # Git Bash without symlink permission: `ln -s` copies. A copy of bin/slickrails would look for the kit next to itself.
  mkdir -p "$WORK/copy-ln" "$WORK/boot-bin2"
  printf '#!/bin/sh\n# ln that copies, like Git Bash without symlink permission\nfor a in "$@"; do case "$a" in -*) ;; *) set -- "$@" "$a";; esac; shift; done\ncp "$1" "$2"\n' > "$WORK/copy-ln/ln"
  chmod +x "$WORK/copy-ln/ln"
  PATH="$WORK/copy-ln:$PATH" SLICKRAILS_REPO="$KIT_DIR" SLICKRAILS_HOME="$BOOT_HOME" SLICKRAILS_BIN="$WORK/boot-bin2" \
    sh "$KIT_DIR/bootstrap.sh" >/dev/null 2>&1 || true
  [ "$(sh "$WORK/boot-bin2/slickrails" version 2>/dev/null)" = "$(cat "$KIT_DIR/VERSION")" ] \
    && ok "bootstrap: where ln -s copies (Git Bash), the command still finds the kit" \
    || fail "bootstrap: where ln -s copies (Git Bash), the command still finds the kit"
else
  # the test clones the kit; a plain copy (e.g. extracted from `git archive`) has nothing to clone
  printf 'SKIP  bootstrap: the kit is not a git checkout (the test clones it)\n'
fi

# ------------------------------------------------------------ pre-commit ----

new_repo hook-repo
printf '{"name":"t","scripts":{"test":"node -e \\"console.log(1)\\""}}' > package.json
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
git add -A && git commit -qm "init" --no-verify

# Fixture assembled from parts so this file itself never matches the scanner.
FAKE_KEY="sk-""abcdefghijklmnopqrstuvwxyz123456"
printf 'key = "%s"\n' "$FAKE_KEY" > leak.js
git add leak.js
# gitleaks judges by entropy and lets a low-entropy key through (seen with gitleaks 8.30); the patterns still run
mkdir -p "$WORK/lenient-gitleaks"; printf '#!/bin/sh\nexit 0\n' > "$WORK/lenient-gitleaks/gitleaks"; chmod +x "$WORK/lenient-gitleaks/gitleaks"
PATH="$WORK/lenient-gitleaks:$PATH" sh .githooks/pre-commit >/dev/null 2>&1
[ $? -eq 1 ] && ok "pre-commit: a key gitleaks lets through is still caught by the patterns" \
  || fail "pre-commit: a key gitleaks lets through is still caught by the patterns"
expect "pre-commit: blocks staged secret" 1 git commit -qm leak
git reset -q leak.js && rm leak.js

printf 'X=1\n' > .env
git add -f .env
expect "pre-commit: blocks .env file" 1 git commit -qm env
git reset -q .env && rm .env

printf 'console.log("ok")\n' > ok.js
git add ok.js
expect "pre-commit: clean commit passes" 0 git commit -qm "ok"

# Destination paths count, not just added/copied/modified ones (renames, type changes).
git mv ok.js .env
expect "pre-commit: blocks a rename onto .env" 1 git commit -qm "rename to env"
git reset -q --hard HEAD; rm -f .env

mkdir -p "my app/sub"; printf 'X=1\n' > "my app/sub/.env"
git add -f "my app/sub/.env"
expect "pre-commit: blocks nested .env in a path with spaces" 1 git commit -qm nested
git reset -q --hard HEAD; rm -rf "my app"

git mv ok.js .env.example
expect "pre-commit: rename onto .env.example passes" 0 git commit -qm "rename to example"

printf 'X=1\n' > .ENV; git add -f .ENV
expect "pre-commit: blocks .ENV (same file on case-insensitive file systems)" 1 git commit -qm upper
git reset -q --hard HEAD; rm -f .ENV

# git prints non-ASCII paths quoted unless -z is used; the quote broke the end-of-line match.
mkdir -p "café"; printf 'X=1\n' > "café/.env"; git add -f "café/.env"
expect "pre-commit: blocks .env below a non-ASCII directory" 1 git commit -qm unicode
git reset -q --hard HEAD; rm -rf "café"

# ------------------------------------------------------------ commit-msg ----

i=0; while [ $i -lt 40 ]; do echo "console.log($i)"; i=$((i+1)); done > big.js
git add big.js
expect "commit-msg: blocks 40-line diff with one-liner" 1 git commit -qm "big"
expect "commit-msg: same diff with body passes" 0 git commit -qm "big

Why: test fixture for the commit-msg hook.
What: 40 lines of dummy logging."

printf 'x\n' > small.txt
git add small.txt
expect "commit-msg: small diff with one-liner passes" 0 git commit -qm "small"

# ------------------------------------------------------------- post-merge ---

BR="$(git rev-parse --abbrev-ref HEAD)"
git checkout -q -b feat-x
printf 'console.log("f")\n' > feature.js
git add feature.js && git commit -qm "feat"
git checkout -q "$BR"
MERGE_OUT="$(git merge --no-ff --no-edit feat-x 2>&1)"
case "$MERGE_OUT" in
  *dossier*) ok "post-merge: reminds about the missing dossier";;
  *)         fail "post-merge: reminds about the missing dossier";;
esac

# -------------------------------------------------------------- pre-push ----

git init -q --bare "$WORK/remote.git"
git remote add origin "$WORK/remote.git"

node -e 'const f="package.json",p=require(process.cwd()+"/"+f);p.scripts.test="node -e \"process.exit(1)\"";require("fs").writeFileSync(f,JSON.stringify(p))'
git add package.json && git commit -qm "red test

Why: fixture.
What: failing test." >/dev/null 2>&1
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
expect "pre-push: blocks red tests" 1 git push -q origin "$BRANCH"

node -e 'const f="package.json",p=require(process.cwd()+"/"+f);p.scripts.test="node -e \"console.log(1)\"";require("fs").writeFileSync(f,JSON.stringify(p))'
git add package.json && git commit -qm "green test

Why: fixture.
What: passing test." >/dev/null 2>&1
expect "pre-push: green tests pass" 0 git push -q origin "$BRANCH"

# The checks must describe what leaves the machine: HEAD, with a clean working tree.
git commit -q --allow-empty -m "pending push"   # an up-to-date push never reaches the hook
printf '// local edit\n' >> feature.js
expect "pre-push: blocks when the working tree has uncommitted changes" 1 git push -q origin "$BRANCH"
git checkout -q -- feature.js

git branch -q side HEAD~1
expect "pre-push: refuses a ref other than HEAD (checks ran on HEAD)" 1 git push -q origin side
SLICKRAILS_SKIP=1 git push -q origin side >/dev/null 2>&1
expect "pre-push: deleting a branch needs no checks" 0 git push -q origin :side

git tag -a v0 -m "test tag"
expect "pre-push: annotated tag on HEAD passes" 0 git push -q origin v0

printf 'new\n' > untracked-note.txt
expect "pre-push: blocks when an untracked (not ignored) file is present" 1 git push -q origin "$BRANCH"
rm -f untracked-note.txt

git tag -a v-old HEAD~2 -m "old release"
expect "pre-push: a tag on an older commit passes (with a note)" 0 git push -q origin v-old

git branch -q side2 HEAD~1
expect "pre-push: every pushed ref is checked, not just the first" 1 git push -q origin "$BRANCH" side2
git branch -q -D side2

git commit -q --allow-empty -m "skip fixture"
SLICKRAILS_SKIP=1 git push -q origin "$BRANCH" >/dev/null 2>&1 \
  && ok "pre-push: SLICKRAILS_SKIP bypasses" || fail "pre-push: SLICKRAILS_SKIP bypasses"

# ------------------------------------------------------------- ai-review ----
# Stub `claude` on PATH: this tests the wrapper protocol (verdict parsing, ERROR reporting), not model quality.

printf 'export const z = 1;\n' > z.js
git add z.js && git commit -qm "z"

# review_case <description> <want-exit> <needle|!needle> <stub-script> [ENV=value]
review_case() {
  mkdir -p "$WORK/stub"
  printf '#!/bin/sh\n%s\n' "$4" > "$WORK/stub/claude"; chmod +x "$WORK/stub/claude"
  # ${5:-} is zero or more VAR=value words for env, split on purpose
  # shellcheck disable=SC2086
  RV_OUT="$(PATH="$WORK/stub:$PATH" env ${5:-} sh .slickrails/ai-review.sh 2>&1)"; RV_RC=$?
  case "$3" in
    '!'*) NEEDLE="${3#!}"; case "$RV_OUT" in *"$NEEDLE"*) HIT=0;; *) HIT=1;; esac;;
    *)    case "$RV_OUT" in *"$3"*) HIT=1;; *) HIT=0;; esac;;
  esac
  if [ "$RV_RC" -eq "$2" ] && [ "$HIT" -eq 1 ]; then ok "$1"; else fail "$1 (exit $RV_RC, wanted $2; output: $(printf '%s' "$RV_OUT" | tail -2 | tr '\n' ' '))"; fi
}

review_case "ai-review: exact PASS verdict passes" 0 "PASS — push proceeds" \
  'cat >/dev/null; echo "VERDICT: PASS"'
review_case "ai-review: the output carries no shell job-control noise (Terminated)" 0 "!Terminated" \
  'cat >/dev/null; echo "VERDICT: PASS"'
review_case "ai-review: a finished review leaves no watcher process behind" 0 "PASS — push proceeds" \
  'cat >/dev/null; echo "VERDICT: PASS"' "REVIEW_TIMEOUT=$RT_UNIQ"
[ "$(running "[s]leep $RT_UNIQ")" = "0" ] \
  && ok "ai-review: no orphaned watcher sleep after the review" \
  || { fail "ai-review: no orphaned watcher sleep after the review"; pkill -f "sleep $RT_UNIQ" 2>/dev/null; }
review_case "ai-review: 'PASS but actually FAIL' is never a PASS" 3 "!PASS — push proceeds" \
  'cat >/dev/null; echo "VERDICT: PASS but actually FAIL: SQL injection"'
review_case "ai-review: 'PASS but actually FAIL' is reported as ERROR" 3 "ERROR" \
  'cat >/dev/null; echo "VERDICT: PASS but actually FAIL: SQL injection"'
review_case "ai-review: reviewer crash (exit 17) is reported as ERROR" 3 "ERROR" \
  'cat >/dev/null; exit 17'
review_case "ai-review: unparseable answer is reported as ERROR" 3 "ERROR" \
  'cat >/dev/null; echo "no verdict here"'
review_case "ai-review: FAIL verdict blocks (exit 1)" 1 "FAIL — findings" \
  'cat >/dev/null; printf "VERDICT: FAIL\nz.js:1 — [high] — issue — scenario\n"'
review_case "ai-review: REVIEW_ON_ERROR=block turns an invalid answer into a block" 1 "ERROR" \
  'cat >/dev/null; echo "no verdict here"' "REVIEW_ON_ERROR=block"

if command -v jq >/dev/null 2>&1; then
  JSON_STUB='cat >/dev/null; case "$*" in *--json-schema*) echo "$STUB_JSON";; *) echo "VERDICT: PASS";; esac'
  export STUB_JSON
  STUB_JSON='{"structured_output":{"verdict":"FAIL","findings":["z.js:1 — [high] — issue — scenario"]}}'
  review_case "ai-review: structured FAIL verdict blocks" 1 "FAIL — findings" "$JSON_STUB"
  STUB_JSON='{"structured_output":{"verdict":"PASS","findings":[]}}'
  review_case "ai-review: structured PASS verdict passes" 0 "PASS — push proceeds" "$JSON_STUB"
  STUB_JSON='{"structured_output":{"verdict":"MAYBE","findings":[]}}'
  review_case "ai-review: structured verdict outside PASS/FAIL is an ERROR" 3 "ERROR" "$JSON_STUB"
  # claude reports why it stopped on stdout, not stderr (a PR-sized diff hit --max-turns 3 on the first real run)
  review_case "ai-review: a reviewer that stopped says why (subtype from its JSON answer)" 3 "error_max_turns" \
    'cat >/dev/null; echo "{\"type\":\"result\",\"subtype\":\"error_max_turns\",\"is_error\":true}"; exit 1'
  review_case "ai-review: claude gets enough turns for a PR-sized diff" 0 "PASS — push proceeds" \
    'cat >/dev/null; case "$*" in *"--max-turns 3"*) exit 1;; esac; echo "VERDICT: PASS"'
  # the reviewer reads, it never runs or writes anything (found 2026-11-02: a review "reproduced" a finding by creating
  # and staging a file in the real repo, another ran `git restore .`)
  review_case "ai-review: claude reviews with read-only tools (no Bash, no Edit, no Write)" 0 "PASS — push proceeds" \
    'cat >/dev/null; case "$*" in *"--tools Read,Grep,Glob"*) echo "VERDICT: PASS";; *) echo "VERDICT: FAIL"; echo "tools not limited: $*";; esac'
  # ...and without the user's MCP servers (mail, CRM, cloud APIs) or the project's hooks (the Stop gate would run the
  # whole suite inside every review) — found by the real claude review, 2026-11-02
  review_case "ai-review: claude reviews without MCP servers and without project hooks" 0 "PASS — push proceeds" \
    'cat >/dev/null; case "$*" in *"--strict-mcp-config"*"--setting-sources user"*) echo "VERDICT: PASS";; *) echo "VERDICT: FAIL"; echo "not isolated: $*";; esac'
  # Windows: jq ends its output lines with \r\n — "PASS\r" must still be a PASS
  make_crlf_jq "$WORK/crlfjq"
  RV_PATH="$PATH"; PATH="$WORK/crlfjq:$PATH"
  STUB_JSON='{"structured_output":{"verdict":"PASS","findings":[]}}'
  review_case "ai-review: a structured PASS from a jq that writes CRLF (Windows) passes" 0 "PASS — push proceeds" "$JSON_STUB"
  PATH="$RV_PATH"
fi

GARBAGE='cat >/dev/null; echo "no verdict here"'
review_case "ai-review: FAIL without findings still says something" 1 "no details" \
  'cat >/dev/null; echo "VERDICT: FAIL"'
review_case "ai-review: a hanging reviewer is killed and reported as ERROR" 3 "timed out" \
  'cat >/dev/null; exec sleep 30' "REVIEW_TIMEOUT=1"
review_case "ai-review: REVIEW_ON_ERROR=Block (any case) blocks" 1 "Blocked" "$GARBAGE" "REVIEW_ON_ERROR=Block"
review_case "ai-review: an unknown REVIEW_ON_ERROR value is treated as block" 1 "Unknown REVIEW_ON_ERROR" "$GARBAGE" "REVIEW_ON_ERROR=blok"

cp .slickrails/config.sh "$WORK/config.bak"
printf 'REVIEW_ON_ERROR="block"\n' >> .slickrails/config.sh
review_case "ai-review: REVIEW_ON_ERROR=block set in config.sh blocks" 1 "Blocked" "$GARBAGE"
cp "$WORK/config.bak" .slickrails/config.sh

# Codex as the reviewer (REVIEW_CLI=codex, or auto without claude): the same protocol through `codex exec`, whose
# stub writes its last message to the -o file and records its arguments. A tool box without the real claude/codex
# (launchers: Git Bash keeps git in /mingw64/bin) makes "auto" testable on a machine that has both installed.
RTB="$WORK/review-tb"; CSTUB="$WORK/codex-stub"; mkdir -p "$RTB" "$CSTUB"
for T in git jq; do P="$(command -v "$T" 2>/dev/null)" && printf '#!/bin/sh\nexec "%s" "$@"\n' "$P" > "$RTB/$T" && chmod +x "$RTB/$T"; done
cat > "$CSTUB/codex" <<'CODEX'
#!/bin/sh
cat > /dev/null
OUT=""; for A in "$@"; do [ "$PREV" = "-o" ] && OUT="$A"; PREV="$A"; done
printf '%s\n' "$*" > "$CSTUB_ARGS"
[ -n "$OUT" ] && printf '%s\n' "$CSTUB_LAST" > "$OUT"
exit "${CSTUB_RC:-0}"
CODEX
chmod +x "$CSTUB/codex"; export CSTUB_ARGS="$WORK/codex.args" CSTUB_LAST CSTUB_RC
codex_case() { # <description> <want-exit> <needle> <PATH> [ENV=value...]
  D="$1"; W="$2"; N="$3"; P="$4"; shift 4
  CX_OUT="$(env PATH="$P" SLICKRAILS_CODEX_APP=/nonexistent "$@" sh .slickrails/ai-review.sh 2>&1)"; CX_RC=$?
  case "$CX_OUT" in *"$N"*) CX_HIT=1;; *) CX_HIT=0;; esac
  if [ "$CX_RC" -eq "$W" ] && [ "$CX_HIT" -eq 1 ]; then ok "$D"; else fail "$D (exit $CX_RC, wanted $W; output: $(printf '%s' "$CX_OUT" | tail -2 | tr '\n' ' '))"; fi
}
NOCLAUDE="$CSTUB:$RTB:/usr/bin:/bin"
if command -v jq >/dev/null 2>&1; then
  CSTUB_LAST='{"verdict":"FAIL","findings":["z.js:1 — [high] — issue — scenario"]}'
  codex_case "ai-review (codex): a FAIL verdict blocks" 1 "FAIL — findings" "$NOCLAUDE" REVIEW_CLI=codex
  grep -q -- '--sandbox read-only' "$CSTUB_ARGS" && grep -q -- '--ephemeral' "$CSTUB_ARGS" && grep -q -- '--output-schema' "$CSTUB_ARGS" \
    && ok "ai-review (codex): runs read-only, without a stored session, with the verdict schema" \
    || fail "ai-review (codex): runs read-only, without a stored session, with the verdict schema ($(cat "$CSTUB_ARGS"))"
  CSTUB_LAST='{"verdict":"PASS","findings":[]}'
  codex_case "ai-review (codex): a PASS verdict passes" 0 "PASS — push proceeds" "$NOCLAUDE" REVIEW_CLI=codex
  codex_case "ai-review (codex): auto without claude falls back to codex" 0 "codex exec" "$NOCLAUDE"
  CSTUB_LAST='{"verdict":"PASS but actually FAIL","findings":[]}'
  codex_case "ai-review (codex): a verdict outside PASS/FAIL is an ERROR" 3 "ERROR" "$NOCLAUDE" REVIEW_CLI=codex
  CSTUB_LAST='{"verdict":"PASS","findings":[]}'
  codex_case "ai-review (codex): a crashed codex is an ERROR, not its last message" 3 "ERROR" "$NOCLAUDE" REVIEW_CLI=codex CSTUB_RC=1
  # auto with both: claude (stub answers FAIL) wins over codex (stub answers PASS)
  printf '#!/bin/sh\ncat >/dev/null\necho "VERDICT: FAIL"\n' > "$CSTUB/claude"; chmod +x "$CSTUB/claude"
  codex_case "ai-review: auto with both CLIs uses claude" 1 "FAIL — findings" "$NOCLAUDE"
  rm -f "$CSTUB/claude"
fi
codex_case "ai-review: REVIEW_CLI=codex without codex skips with a message" 0 "codex CLI not found" "$RTB:/usr/bin:/bin" REVIEW_CLI=codex

# a diff that cannot be built (no merge base: unrelated history, a shallow clone) is not an empty diff
# (found by the real claude review of this script, 2026-10-29)
RV_HOME="$PWD"
new_repo review-nobase-repo
mkdir .slickrails; cp "$KIT_DIR/templates/ai-review.sh" .slickrails/
printf 'b\n' > b.txt && git add b.txt && git commit -qm base --no-verify && git branch -M main
git switch -q --orphan feat && printf 'x\n' > f.txt && git add f.txt && git commit -qm feat --no-verify
git branch -q --set-upstream-to=main 2>/dev/null
printf '#!/bin/sh\ncat >/dev/null\necho "VERDICT: PASS"\n' > "$CSTUB/claude"; chmod +x "$CSTUB/claude"
codex_case "ai-review: no merge base with the base branch is an ERROR, not a silent pass" 3 "ERROR" "$NOCLAUDE"
rm -f "$CSTUB/claude"
cd "$RV_HOME" || exit 1

# pre-push must not call an unreviewed push "All green".
printf 'CHECK_PREPUSH_REVIEW="1"\n' >> .slickrails/config.sh
git add -A && git commit -qm "enable the pre-push review" >/dev/null 2>&1
printf '#!/bin/sh\ncat >/dev/null\nexit 3\n' > "$WORK/stub/claude"; chmod +x "$WORK/stub/claude"
PUSH_OUT="$(PATH="$WORK/stub:$PATH" git push origin "$BRANCH" 2>&1)"; PUSH_RC=$?
case "$PUSH_OUT" in
  *"All green"*) fail "pre-push: a push whose AI review errored is not reported as All green";;
  *"did NOT run"*) [ "$PUSH_RC" -eq 0 ] && ok "pre-push: a push whose AI review errored is not reported as All green" \
                    || fail "pre-push: errored review with warn lets the push proceed (exit $PUSH_RC)";;
  *) fail "pre-push: a push whose AI review errored is not reported as All green (no notice: $(printf '%s' "$PUSH_OUT" | tail -2 | tr '\n' ' '))";;
esac

# ---------------------------------------------------------- session-check ---

printf 'dirty\n' > dirty.txt
node -e 'const f="package.json",p=require(process.cwd()+"/"+f);p.scripts.test="node -e \"process.exit(1)\"";require("fs").writeFileSync(f,JSON.stringify(p))'
printf '{}' | sh .slickrails/session-check.sh >/dev/null 2>&1
[ $? -eq 2 ] && ok "session-check: red checks block (exit 2)" || fail "session-check: red checks block (exit 2)"
grep -q '^red [0-9]' "$(git rev-parse --git-dir)/slickrails-last-gate" 2>/dev/null \
  && ok "session-check: records a red result for the status display" || fail "session-check: records a red result for the status display"

# stop_hook_active no longer means "let it through": the hook keeps its own counter per unchanged state.
printf '{"stop_hook_active":true}' | sh .slickrails/session-check.sh >/dev/null 2>&1
[ $? -eq 2 ] && ok "session-check: red checks still block when stop_hook_active is true" \
  || fail "session-check: red checks still block when stop_hook_active is true"
printf '{"stop_hook_active":true}' | sh .slickrails/session-check.sh >/dev/null 2>&1
SC_OUT="$(printf '{"stop_hook_active":true}' | sh .slickrails/session-check.sh 2>&1)"; SC_RC=$?
case "$SC_OUT" in
  *"NOT done"*) [ "$SC_RC" -eq 0 ] && ok "session-check: after 3 blocks at an unchanged state the session may end, loudly" \
                  || fail "session-check: after 3 blocks the session may end (exit $SC_RC)";;
  *) fail "session-check: after 3 blocks the session may end, loudly (no warning: $(printf '%s' "$SC_OUT" | tail -2 | tr '\n' ' '))";;
esac

node -e 'const f="package.json",p=require(process.cwd()+"/"+f);p.scripts.test="node -e \"console.log(1)\"";require("fs").writeFileSync(f,JSON.stringify(p))'
printf '{}' | sh .slickrails/session-check.sh >/dev/null 2>&1 \
  && ok "session-check: green checks pass" || fail "session-check: green checks pass"
grep -q '^green [0-9]' "$(git rev-parse --git-dir)/slickrails-last-gate" 2>/dev/null \
  && ok "session-check: records a green result for the status display" || fail "session-check: records a green result for the status display"

git add -A && git commit -qm "clean tree

Why: fixture.
What: commit everything." >/dev/null 2>&1
printf '{}' | sh .slickrails/session-check.sh >/dev/null 2>&1 \
  && ok "session-check: committed green work passes" || fail "session-check: committed green work passes"

# --- session-check in isolation: commits ahead, cache, deadline, crash --------
new_repo sess-repo
git init -q --bare "$WORK/sess-remote.git"
git remote add origin "$WORK/sess-remote.git"
mkdir .slickrails; cp "$KIT_DIR/templates/session-check.sh" .slickrails/
printf 'CHECK_TEST="sh ./t.sh"\n' > .slickrails/config.sh
printf 'exit 1\n' > t.sh
git add -A && git commit -qm base
git push -q -u origin HEAD
SC() { printf '{"stop_hook_active":false}' | sh .slickrails/session-check.sh; }

SC >/dev/null 2>&1
[ $? -eq 0 ] && ok "session-check: clean tree and nothing ahead of upstream skips the checks" \
  || fail "session-check: clean tree and nothing ahead of upstream skips the checks"

printf 'exit 1\n# red commit\n' > t.sh
git commit -qam "red commit"
SC >/dev/null 2>&1
[ $? -eq 2 ] && ok "session-check: a red commit on a clean tree still blocks (commits ahead of upstream)" \
  || fail "session-check: a red commit on a clean tree still blocks"

printf 'exit 0\n' > t.sh
git commit -qam "green commit"
SC >/dev/null 2>&1
[ $? -eq 0 ] && ok "session-check: the green commit passes" || fail "session-check: the green commit passes"

# cache: an unchanged state that was already green is not checked again
printf 'exit 0\n# runs\n' > t.sh; git commit -qam "count runs"
printf 'CHECK_TEST="sh ./t.sh"\nCHECK_SESSION="echo x >> \\"%s/runs\\""\n' "$WORK" > .slickrails/config.sh
git add -A && git commit -qm "count runs in config"
rm -f "$WORK/runs"; SC >/dev/null 2>&1; SC >/dev/null 2>&1
[ "$(wc -l < "$WORK/runs" 2>/dev/null | tr -d ' ')" = "1" ] \
  && ok "session-check: an unchanged green state is checked once (cache)" \
  || fail "session-check: an unchanged green state is checked once (runs: $(wc -l < "$WORK/runs" 2>/dev/null | tr -d ' '))"
printf 'more\n' > new-file.txt
SC >/dev/null 2>&1
[ "$(wc -l < "$WORK/runs" 2>/dev/null | tr -d ' ')" = "2" ] \
  && ok "session-check: a changed state (new untracked file) is checked again" \
  || fail "session-check: a changed state is checked again"
rm -f new-file.txt

# deadline: the hook ends the check itself with exit 2 (the host would otherwise cancel it and let the session end)
printf 'CHECK_TEST="sh ./t.sh"\nCHECK_SESSION="sh -c \\"sleep %s\\""\n' "$TAG_A" > .slickrails/config.sh
printf 'dirty\n' > dirty.txt
SC_START="$(date +%s)"
SC_OUT="$(SLICKRAILS_STOP_DEADLINE_MS=300 SC 2>&1)"; SC_RC=$?
SC_SECS=$(( $(date +%s) - SC_START ))
[ "$SC_RC" -eq 2 ] && [ "$SC_SECS" -lt 3 ] && ok "session-check: a check over its deadline ends in exit 2 (${SC_SECS}s)" \
  || fail "session-check: a check over its deadline ends in exit 2 (exit $SC_RC after ${SC_SECS}s)"
case "$SC_OUT" in *deadline*) ok "session-check: the deadline is named in the message";; *) fail "session-check: the deadline is named in the message";; esac
[ "$(running "[s]leep $TAG_A")" = "0" ] \
  && ok "session-check: the killed check leaves no child processes behind" \
  || fail "session-check: the killed check leaves no child processes behind"

# crash: a broken config must not be read as "nothing to check"
printf 'if then fi\n' > .slickrails/config.sh
SC_OUT="$(SC 2>&1)"; SC_RC=$?
[ "$SC_RC" -eq 2 ] && ok "session-check: a crash blocks (exit 2) instead of letting the session end" \
  || fail "session-check: a crash blocks (exit $SC_RC)"
case "$SC_OUT" in *crashed*) ok "session-check: the crash is named in the message";; *) fail "session-check: the crash is named in the message";; esac

# --- session-check, round 2 (self-review): no remote, cache key, counter, process hygiene -------------
new_repo sess2-repo
mkdir .slickrails; cp "$KIT_DIR/templates/session-check.sh" .slickrails/
printf 'CHECK_TEST="sh ./t.sh"\n' > .slickrails/config.sh
printf 'exit 0\n' > t.sh
git add -A && git commit -qm base

# without any remote/upstream every commit is unpushed: a red commit on a clean tree must still block
printf 'exit 1\n' > t.sh; git commit -qam "red commit"
SC >/dev/null 2>&1
[ $? -eq 2 ] && ok "session-check: without a remote a red commit on a clean tree blocks" \
  || fail "session-check: without a remote a red commit on a clean tree blocks"
printf 'exit 0\n' > t.sh; git commit -qam "green commit"
SC >/dev/null 2>&1
[ $? -eq 0 ] && ok "session-check: without a remote the green commit passes" || fail "session-check: without a remote the green commit passes"

# the cache is keyed on the command as well: same tree, different checks
( CHECK_SESSION=true SC ) >/dev/null 2>&1
( CHECK_SESSION=false SC ) >/dev/null 2>&1
[ $? -eq 2 ] && ok "session-check: a different check command is not served from the cache" \
  || fail "session-check: a different check command is not served from the cache"

# a broken git state is a crash, not 'nothing to check'
mkdir -p "$WORK/idx"; cp .git/index "$WORK/idx/index"
printf 'garbage\n' > .git/index
SC >/dev/null 2>&1
SC_RC=$?
cp "$WORK/idx/index" .git/index
[ "$SC_RC" -eq 2 ] && ok "session-check: a failing git status blocks instead of passing" \
  || fail "session-check: a failing git status blocks (exit $SC_RC)"

# 3 blocks per unchanged state, then the session ends WITHOUT running the checks again
printf 'one\n' > untracked-1.txt
rm -f "$WORK/runs3"
for _ in 1 2 3; do ( CHECK_SESSION="echo x >> \"$WORK/runs3\"; exit 1" SC ) >/dev/null 2>&1; done
SC_OUT="$(CHECK_SESSION="echo x >> \"$WORK/runs3\"; exit 1" SC 2>&1)"; SC_RC=$?
[ "$SC_RC" -eq 0 ] && [ "$(wc -l < "$WORK/runs3" | tr -d ' ')" = "3" ] \
  && ok "session-check: the 4th stop at an unchanged red state ends the session without re-running the checks" \
  || fail "session-check: the 4th stop must not re-run the checks (exit $SC_RC, runs $(wc -l < "$WORK/runs3" | tr -d ' '))"
case "$SC_OUT" in *"NOT done"*) ok "session-check: ...and says so loudly";; *) fail "session-check: ...and says so loudly";; esac

# a check over its deadline blocks once; the next stop does not pay the deadline again
printf 'two\n' > untracked-2.txt
rm -f "$WORK/runs4"
( SLICKRAILS_STOP_DEADLINE_MS=300 CHECK_SESSION="echo x >> \"$WORK/runs4\"; sleep 5" SC ) >/dev/null 2>&1
SC_RC1=$?
( SLICKRAILS_STOP_DEADLINE_MS=300 CHECK_SESSION="echo x >> \"$WORK/runs4\"; sleep 5" SC ) >/dev/null 2>&1
SC_RC2=$?
[ "$SC_RC1" -eq 2 ] && [ "$SC_RC2" -eq 0 ] && [ "$(wc -l < "$WORK/runs4" | tr -d ' ')" = "1" ] \
  && ok "session-check: a too-slow check blocks once, then the session may end (no 2nd run)" \
  || fail "session-check: a too-slow check blocks once (exits $SC_RC1/$SC_RC2, runs $(wc -l < "$WORK/runs4" | tr -d ' '))"

# a wrapper that starts a second command after the first dies must not leave anything behind
printf 'three\n' > untracked-3.txt
( SLICKRAILS_STOP_DEADLINE_MS=300 CHECK_SESSION="sh -c \"sleep $TAG_B; true\"" SC ) >/dev/null 2>&1
[ "$(running "[s]leep $TAG_B")" = "0" ] \
  && ok "session-check: the whole process tree of a killed check is gone" \
  || fail "session-check: the whole process tree of a killed check is gone"

# a child that appears AFTER the process snapshot must not survive the deadline (Codex review of 0b87f6d):
# the ps shim takes the real snapshot first, announces it, then delays its output; the check starts its child
# only once the snapshot was taken.
mkdir -p "$WORK/psshim"
REAL_PS="$(command -v ps)"
cat > "$WORK/psshim/ps" <<PSSHIM
#!/bin/sh
if [ -f "$WORK/ps.marker" ]; then exec "$REAL_PS" "\$@"; fi
"$REAL_PS" "\$@" > "$WORK/ps.snap"; PS_RC=\$?
: > "$WORK/ps.marker"
sleep 0.4
cat "$WORK/ps.snap"
exit \$PS_RC
PSSHIM
chmod +x "$WORK/psshim/ps"
rm -f "$WORK/ps.marker" "$WORK/ps.snap"
printf 'late-child\n' > untracked-late.txt
( PATH="$WORK/psshim:$PATH" SLICKRAILS_STOP_DEADLINE_MS=300 \
  CHECK_SESSION="while [ ! -f \"$WORK/ps.marker\" ]; do sleep 0.02; done; sleep $TAG_C & wait" SC ) >/dev/null 2>&1
if [ "$(running "[s]leep $TAG_C")" = "0" ]; then ok "session-check: a child started after the process snapshot does not survive the deadline"
else fail "session-check: a child started after the process snapshot does not survive the deadline"; pkill -9 -f "sleep $TAG_C" 2>/dev/null; fi

# Git Bash: its ps has no -A/-o. The deadline must still stop the whole tree of a hung check.
make_msys_ps "$WORK/msysps"
printf 'msys\n' > untracked-msys.txt
T_START="$(date +%s)"
( PATH="$WORK/msysps:$PATH" SLICKRAILS_STOP_DEADLINE_MS=300 CHECK_SESSION="sh -c \"sleep $TAG_D; true\"" SC ) >/dev/null 2>&1
MSYS_RC=$?; T_SECS=$(( $(date +%s) - T_START ))
if [ "$MSYS_RC" -eq 2 ] && [ "$T_SECS" -le 8 ] && [ "$(running "[s]leep $TAG_D")" = "0" ]; then
  ok "session-check: with a Git Bash style ps the deadline still stops the whole tree (${T_SECS}s)"
else fail "session-check: with a Git Bash style ps the deadline still stops the whole tree (exit $MSYS_RC after ${T_SECS}s, left: $(running "[s]leep $TAG_D"))"; pkill -9 -f "sleep $TAG_D" 2>/dev/null; fi

# The host's hook timeout runs from the start of the hook, not from the start of the checks: time spent before the
# checks (git status and the state key take seconds in a big repository) must come out of the deadline.
mkdir -p "$WORK/slowgit"
# (git status made slow: 8 s before the checks start, deadline 6 s. The hook must end right after that 8 s, since its
# own bound — 7 s from the start — has passed; counting the deadline from the checks' start would take 14 s or more)
printf '#!/bin/sh\ncase "$1" in status) sleep 8;; esac\nexec "%s" "$@"\n' "$(command -v git)" > "$WORK/slowgit/git"
chmod +x "$WORK/slowgit/git"
printf 'slowgit\n' > untracked-slowgit.txt
T_START="$(date +%s)"
SG_OUT="$( (PATH="$WORK/slowgit:$PATH" SLICKRAILS_STOP_DEADLINE_MS=6000 CHECK_SESSION="sleep 40" SC) 2>&1 )"
SG_RC=$?; T_SECS=$(( $(date +%s) - T_START ))
if [ "$SG_RC" -eq 2 ] && [ "$T_SECS" -le 11 ]; then ok "session-check: time spent before the checks counts against the deadline (${T_SECS}s for a 6s deadline)"
else fail "session-check: time spent before the checks counts against the deadline (exit $SG_RC after ${T_SECS}s for a 6s deadline)"; fi
# ...and a deadline that is used up before the checks could start does not start them at all (on Git Bash a process
# that is stopped while it is still starting can miss the signal and run on)
case "$SG_OUT" in
  *"before the checks could start"*) ok "session-check: a deadline used up before the checks does not start them, and says so";;
  *) fail "session-check: a deadline used up before the checks does not start them, and says so ($(printf '%s' "$SG_OUT" | head -1))";;
esac

# the hook leaves no watcher behind and works when the host started it with SIGTERM ignored
printf 'four\n' > untracked-4.txt
rm -f "$WORK/ign.rc"
( trap '' TERM; SLICKRAILS_STOP_DEADLINE_MS=$MS_UNIQ CHECK_SESSION=false sh .slickrails/session-check.sh </dev/null >/dev/null 2>&1; echo $? > "$WORK/ign.rc" ) &
IGN_PID=$!; i=0
while [ "$i" -lt 40 ] && kill -0 "$IGN_PID" 2>/dev/null; do sleep 0.1; i=$((i+1)); done
if kill -0 "$IGN_PID" 2>/dev/null; then kill -9 "$IGN_PID" 2>/dev/null; pkill -f "sleep $SECS_UNIQ" 2>/dev/null; fail "session-check: finishes promptly even with SIGTERM ignored"
else [ "$(cat "$WORK/ign.rc" 2>/dev/null)" = "2" ] && ok "session-check: finishes promptly even with SIGTERM ignored" || fail "session-check: finishes promptly even with SIGTERM ignored (rc $(cat "$WORK/ign.rc" 2>/dev/null))"; fi
[ "$(running "[s]leep $SECS_UNIQ")" = "0" ] \
  && ok "session-check: no watcher process is left behind" || { fail "session-check: no watcher process is left behind"; pkill -f "sleep $SECS_UNIQ" 2>/dev/null; }

# working-state keys must not fill the object database with untracked files
head -c 300000 /dev/urandom > untracked-big.bin
OBJ_BEFORE="$(find .git/objects -type f | wc -l | tr -d ' ')"
( CHECK_SESSION=true SC ) >/dev/null 2>&1
OBJ_AFTER="$(find .git/objects -type f | wc -l | tr -d ' ')"
[ "$OBJ_BEFORE" = "$OBJ_AFTER" ] && ok "session-check: computing the state key writes no objects into the repository" \
  || fail "session-check: computing the state key writes no objects ($OBJ_BEFORE -> $OBJ_AFTER)"

# an actual runtime error (not a syntax error) must also block
printf 'echo "$SLICKRAILS_UNSET_VARIABLE_FOR_TEST"\nCHECK_TEST=true\n' > .slickrails/config.sh
SC_OUT="$(SC 2>&1)"; SC_RC=$?
[ "$SC_RC" -eq 2 ] && ok "session-check: a runtime error in the config blocks (exit 2)" || fail "session-check: a runtime error in the config blocks (exit $SC_RC)"
printf 'CHECK_TEST="sh ./t.sh"\n' > .slickrails/config.sh

# ------------------------------------------------- seeded-bug benchmark ----
# L1 only (deterministic, offline). A regression, or a fixed gap whose
# known-miss marker was not deleted, fails the suite. L2/L3: see tests/benchmark/run.sh.

BENCH_OUT="$(sh "$KIT_DIR/tests/benchmark/run.sh" 2>&1)"
BENCH_RC=$?
[ "$BENCH_RC" -eq 0 ] && ok "benchmark L1: no regression, no stale known-miss marker" \
  || { fail "benchmark L1: no regression, no stale known-miss marker"; printf '%s\n' "$BENCH_OUT" | grep -E 'REGRESSION|STALE|HARNESS' ; }
printf '%s\n' "$BENCH_OUT" | tail -1

# ------------------------- installer honesty: hook manager, Claude settings, guard, doctor ----

# A repo with its own hook manager (Husky): never switch core.hooksPath silently.
new_repo husky-repo
mkdir .husky; printf '#!/bin/sh\necho husky\n' > .husky/pre-commit; chmod +x .husky/pre-commit
git config core.hooksPath .husky
INST_OUT="$(sh "$KIT_DIR/install.sh" 2>&1)"
[ "$(git config core.hooksPath)" = ".husky" ] && ok "installer: an existing core.hooksPath (Husky) is not switched" \
  || fail "installer: an existing core.hooksPath (Husky) is not switched (now: $(git config core.hooksPath))"
case "$INST_OUT" in *"NOT active"*) ok "installer: says loudly that the git hooks are NOT active";; *) fail "installer: says loudly that the git hooks are NOT active";; esac
grep -q 'NOT active' .slickrails/STATUS.md 2>/dev/null && ok "installer: .slickrails/STATUS.md records the inactive hooks" \
  || fail "installer: .slickrails/STATUS.md records the inactive hooks"
grep -E '^\| 3 \|' .slickrails/STATUS.md 2>/dev/null | grep -q '☑' \
  && fail "installer: rule 3 must not be checked off while the hooks are inactive" \
  || ok "installer: rule 3 is not checked off while the hooks are inactive"
[ -x .githooks/pre-push ] && ok "installer: the hook files are still placed (to chain them)" || fail "installer: the hook files are still placed (to chain them)"

# The first commit after the install is big; the commit-msg hook wants a body. The installer must say how to commit it,
# and that command must actually pass the hook (a new user's first experience must not be an error of the tool itself).
new_repo first-commit-repo
printf '{"name":"t","scripts":{"test":"node -e \\"console.log(1)\\""}}' > package.json
FC_OUT="$(sh "$KIT_DIR/install.sh" 2>&1)"
git add -A >/dev/null 2>&1
git commit -q -m "plain one-liner" >/dev/null 2>&1; FC_PLAIN_RC=$?
[ "$FC_PLAIN_RC" -ne 0 ] && ok "first commit: a plain one-liner is refused by the commit-msg hook (it is a big commit)" || fail "first commit: a plain one-liner is refused by the commit-msg hook"
case "$FC_OUT" in *"git commit -m"*"Why:"*) ok "installer: the next steps give a first-commit command with a body";; *) fail "installer: the next steps give a first-commit command with a body";; esac
git commit -q -m "Install slickrails" -m "Why: the standard for this repo" -m "What: hooks, CI, docs layer" >/dev/null 2>&1
[ $? -eq 0 ] && ok "first commit: the shape the installer suggests passes the hook" || fail "first commit: the shape the installer suggests passes the hook"

# Existing Claude settings: merge the slickrails hooks, keep everything else, stay idempotent, never touch broken JSON.
new_repo settings-repo
mkdir .claude
printf '{"model":"sonnet","hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}' > .claude/settings.json
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
S=.claude/settings.json
if grep -q '"model"' $S && grep -q 'echo mine' $S && grep -q 'session-check.sh' $S && grep -q 'bash-guard.sh' $S; then
  ok "installer: merges the slickrails hooks into existing Claude settings and keeps foreign entries"
else fail "installer: merges the slickrails hooks into existing Claude settings and keeps foreign entries"; fi
cp $S "$WORK/settings.after1"
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
cmp -s $S "$WORK/settings.after1" && ok "installer: a second run leaves the merged settings unchanged" \
  || fail "installer: a second run leaves the merged settings unchanged"
if command -v jq >/dev/null 2>&1; then
  jq -e '(.hooks.Stop | length == 2) and (.hooks.PreToolUse | length == 1)' $S >/dev/null 2>&1 \
    && ok "installer: the merged settings are valid JSON with 2 Stop and 1 PreToolUse entries" \
    || fail "installer: the merged settings are valid JSON with 2 Stop and 1 PreToolUse entries"
fi
new_repo broken-settings-repo
mkdir .claude; printf '{ not json' > .claude/settings.json
INST_OUT="$(sh "$KIT_DIR/install.sh" 2>&1)"
[ "$(cat .claude/settings.json)" = '{ not json' ] && ok "installer: broken settings JSON is never overwritten" \
  || fail "installer: broken settings JSON is never overwritten"
case "$INST_OUT" in *"settings.json"*"merge"*|*"settings.json"*"not valid"*) ok "installer: tells the user to fix the settings file";; *) fail "installer: tells the user to fix the settings file";; esac

# The Bash guard: stops the agent from bypassing the git hooks. Hint, not a boundary.
guard() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1" | sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1; }
guard 'git commit --no-verify -m wip'; [ $? -eq 2 ] && ok "bash-guard: blocks git commit --no-verify" || fail "bash-guard: blocks git commit --no-verify"
guard 'git push --no-verify origin main'; [ $? -eq 2 ] && ok "bash-guard: blocks git push --no-verify" || fail "bash-guard: blocks git push --no-verify"
guard 'cd app && SLICKRAILS_SKIP=1 git push'; [ $? -eq 2 ] && ok "bash-guard: blocks SLICKRAILS_SKIP=1" || fail "bash-guard: blocks SLICKRAILS_SKIP=1"
guard 'git status && git log --oneline -3'; [ $? -eq 0 ] && ok "bash-guard: lets ordinary git commands through" || fail "bash-guard: lets ordinary git commands through"
guard 'grep -rn SLICKRAILS_SKIP SLICKRAILS.md'; [ $? -eq 0 ] && ok "bash-guard: reading about the escape hatch is fine" || fail "bash-guard: reading about the escape hatch is fine"
printf '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}' | env SLICKRAILS_ALLOW_BYPASS=1 sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "bash-guard: SLICKRAILS_ALLOW_BYPASS=1 (set by the human in the hook environment) allows it" \
  || fail "bash-guard: SLICKRAILS_ALLOW_BYPASS=1 allows it"
GUARD_MSG="$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify"}}' | sh "$KIT_DIR/templates/bash-guard.sh" 2>&1)"
case "$GUARD_MSG" in *SLICKRAILS_ALLOW_BYPASS*) ok "bash-guard: the message names the human-only way out";; *) fail "bash-guard: the message names the human-only way out";; esac

# doctor: a fresh clone has no core.hooksPath (it is local git config) — that must be visible.
new_repo doctor-src
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
git add -A && git commit -qm "install" --no-verify
git clone -q "$WORK/doctor-src" "$WORK/doctor-clone"
cd "$WORK/doctor-clone"
# CI= : on a CI machine (CI=true, as on GitHub) doctor rightly downgrades this to a warning; this test is about a laptop
DOC_OUT="$(CI='' sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
if [ "$DOC_RC" -ne 0 ]; then case "$DOC_OUT" in *"core.hooksPath"*) ok "doctor: a fresh clone without core.hooksPath is reported (exit $DOC_RC)";; *) fail "doctor: names core.hooksPath";; esac
else fail "doctor: a fresh clone without core.hooksPath is reported (exit 0)"; fi
git config core.hooksPath .githooks
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
[ "$DOC_RC" -eq 0 ] && ok "doctor: with core.hooksPath set the repo checks pass" || fail "doctor: with core.hooksPath set the repo checks pass (exit $DOC_RC: $(printf '%s' "$DOC_OUT" | grep -iE 'missing|not' | head -2 | tr '\n' ' '))"
printf 'CHECK_TYPECHECK=""\nCHECK_TEST=""\n' > .slickrails/config.sh
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"
case "$DOC_OUT" in *"no checks"*) ok "doctor: an empty config.sh (nothing is checked) is called out";; *) fail "doctor: an empty config.sh (nothing is checked) is called out";; esac
case "$DOC_OUT" in *"not verified"*|*"Not verified"*) ok "doctor: says what it does not verify (installed is not the same as working)";; *) fail "doctor: says what it does not verify";; esac

# Branch protection script, with a gh stub (the real GitHub behavior is not tested here).
new_repo protect-repo
mkdir -p .github/workflows; : > .github/workflows/security.yml; : > .github/workflows/pr-size.yml
mkdir -p "$WORK/ghstub"
cat > "$WORK/ghstub/gh" <<'GHSTUB'
#!/bin/sh
case "$*" in
  "repo view"*) echo "o/r";;
  "api -X PUT"*) cat > "$GH_BODY"; echo '{}';;
  "api repos/o/r/branches/main/protection") [ -f "$GH_READBACK" ] && cat "$GH_READBACK" || exit 1;;
  *) exit 1;;
esac
GHSTUB
chmod +x "$WORK/ghstub/gh"
protect() { # protect <readback-json|-> [ENV=value...]  -> sets PR_OUT, PR_RC
  RB="$1"; shift
  rm -f "$WORK/gh.body" "$WORK/gh.readback"
  [ "$RB" != "-" ] && printf '%s' "$RB" > "$WORK/gh.readback"
  PR_OUT="$(env GH_BODY="$WORK/gh.body" GH_READBACK="$WORK/gh.readback" PATH="$WORK/ghstub:$PATH" "$@" sh "$KIT_DIR/scripts/setup-branch-protection.sh" 2>&1)"; PR_RC=$?
}
RB_ON='{"required_status_checks":{"strict":true,"contexts":["ci","gitleaks","audit","size"]},"enforce_admins":{"enabled":true}}'
RB_OFF='{"required_status_checks":{"strict":true,"contexts":["ci","gitleaks","audit","size"]},"enforce_admins":{"enabled":false}}'
protect "$RB_ON" X=1
grep -q '"enforce_admins": true' "$WORK/gh.body" 2>/dev/null && ok "protection: admins are bound by the rules by default (enforce_admins true)" \
  || fail "protection: admins are bound by the rules by default (body: $(tr -d '\n ' < "$WORK/gh.body" 2>/dev/null | cut -c1-120))"
[ "$PR_RC" -eq 0 ] && ok "protection: a matching read-back succeeds" || fail "protection: a matching read-back succeeds (exit $PR_RC)"
case "$PR_OUT" in *"only accepts PRs"*) fail "protection: no false 'only accepts PRs' claim";; *) ok "protection: no false 'only accepts PRs' claim";; esac
case "$PR_OUT" in *"pull request required"*"no"*|*"Pull requests are NOT required"*) ok "protection: states plainly that pull requests are not required";; *) fail "protection: states plainly that pull requests are not required";; esac
protect "$RB_OFF" ENFORCE_ADMINS=0
grep -q '"enforce_admins": false' "$WORK/gh.body" 2>/dev/null && ok "protection: ENFORCE_ADMINS=0 sends enforce_admins false" || fail "protection: ENFORCE_ADMINS=0 sends enforce_admins false"
[ "$PR_RC" -eq 0 ] && ok "protection: ENFORCE_ADMINS=0 with a matching read-back succeeds" || fail "protection: ENFORCE_ADMINS=0 with a matching read-back succeeds (exit $PR_RC)"
protect "$RB_OFF" X=1
if [ "$PR_RC" -ne 0 ]; then case "$PR_OUT" in *MISMATCH*) ok "protection: a read-back that differs from the request fails with MISMATCH";; *) fail "protection: names the MISMATCH";; esac
else fail "protection: a read-back that differs from the request fails (exit 0)"; fi
protect -  X=1
if [ "$PR_RC" -ne 0 ]; then case "$PR_OUT" in *"NOT verified"*) ok "protection: no read-back means NOT verified, not success";; *) fail "protection: says NOT verified";; esac
else fail "protection: no read-back means NOT verified, not success (exit 0)"; fi

# ---- installer honesty, round 2 (self-review of 0ff4b2a): guard variants, merge edge cases, doctor, protection ----

# The guard parses the command with jq (quoted text such as commit messages is ignored); jq builds the hook JSON here too.
if command -v jq >/dev/null 2>&1; then
  gj() { # gj <command-text> <expected-exit> <description>
    jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1
    GJ_RC=$?
    if [ "$GJ_RC" -eq "$2" ]; then ok "bash-guard: $3"; else fail "bash-guard: $3 (exit $GJ_RC, wanted $2)"; fi
  }
  gj 'git commit -m x --no-verif'                              2 "blocks an abbreviated --no-verif (git accepts unique prefixes)"
  gj 'git commit -n -m x'                                      2 "blocks git commit -n (short for --no-verify)"
  gj 'git commit -nm x'                                        2 "blocks git commit -nm (combined short flags)"
  gj 'git commit -am x'                                        0 "lets git commit -am through"
  gj 'git log -n 3'                                            0 "lets git log -n through"
  gj 'SLICKRAILS_SKIP="1" git commit -m x'                     2 "blocks a quoted SLICKRAILS_SKIP value"
  gj 'git commit -m "fix: a; b" --no-verify'                   2 "blocks --no-verify after a message containing a semicolon"
  gj '/usr/bin/git commit --no-verify -m x'                    2 "blocks --no-verify with an absolute git path"
  gj 'git commit -m "docs: explain the --no-verify rule"'      0 "lets a commit MESSAGE that mentions --no-verify through"
  gj 'git commit -m "add the -n option"'                       0 "lets a commit message that mentions -n through"
  gj 'echo "SLICKRAILS_SKIP=1 is the bypass"'                  0 "lets text that merely mentions SLICKRAILS_SKIP=1 through"
  gj 'lazygit --no-verify'                                     0 "does not mistake lazygit for git"
  gj 'git -c core.hooksPath=/dev/null commit -m x'             2 "blocks git -c core.hooksPath=... (hooks switched off for one command)"
  gj 'git config core.hooksPath /dev/null'                     2 "blocks setting core.hooksPath"
  gj 'git config --unset core.hooksPath'                       2 "blocks unsetting core.hooksPath"
  # commit messages are usually written as heredocs; their body is text, not a command
  gj "$(printf 'git commit -q -F - <<'"'"'EOF'"'"'\nWhy: the guard blocks --no-verify and SLICKRAILS_SKIP=1 now\nEOF')" 0 "lets a heredoc commit message that mentions --no-verify through"
  # Windows: jq hands the command back with \r\n line ends; the heredoc must still end at "EOF"
  make_crlf_jq "$WORK/crlfjq"
  printf '%s' "$(printf 'git commit -q -F - <<'"'"'EOF'"'"'\nWhy: mentions --no-verify\nEOF\ngit status')" \
    | jq -cRs '{tool_name:"Bash",tool_input:{command:.}}' | PATH="$WORK/crlfjq:$PATH" sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1
  GJ_RC=$?
  [ "$GJ_RC" -eq 0 ] && ok "bash-guard: a heredoc read through a jq that writes CRLF (Windows) still ends at EOF" \
    || fail "bash-guard: a heredoc read through a jq that writes CRLF (Windows) still ends at EOF (exit $GJ_RC)"
  gj "$(printf 'git commit -q -F - <<EOF\nmentions git push --no-verify\nEOF')"                                     0 "lets an unquoted-delimiter heredoc body through"
  gj "$(printf 'git commit -F - <<-'"'"'EOF'"'"'\n\tmentions --no-verify\n\tEOF')"                                    0 "lets an indented (<<-) heredoc body through"
  gj "$(printf 'git commit -F - <<'"'"'EOF'"'"'\nbody\nEOF\ngit push --no-verify')"                                   2 "still blocks a real --no-verify AFTER a heredoc"
  gj "$(printf 'git commit -m x <<<y\ngit push --no-verify')"                                                     2 "a here-string does not hide the next line"
  # heredoc scanning must follow the shell's quoting and terminator rules (Codex review of 91341ed)
  gj "$(printf 'echo "<<EOF"\ngit push --no-verify\nEOF')"                                    2 "a quoted <<EOF is no heredoc: the push --no-verify line after it is blocked"
  gj "$(printf "echo '<<EOF'\ngit push --no-verify\nEOF")"                                    2 "a single-quoted <<EOF is no heredoc either"
  gj "$(printf 'cat <<EOF\n EOF\ngit push --no-verify\nEOF')"                                  0 "<<EOF is closed by EOF at column 0 only: an indented EOF stays inside the body"
  gj "$(printf 'cat <<-EOF\n  EOF\ngit push --no-verify\n\tEOF')"                              0 "<<- strips tabs only: a space-indented EOF stays inside the body"
  gj "$(printf 'cat <<A <<B\nbody a\nA\ngit push --no-verify as text\nB')"                      0 "two heredocs on one line: both bodies are skipped, in order"
  gj "$(printf '# <<EOF\ngit push --no-verify\nEOF')"                                          2 "a <<EOF inside a comment is no heredoc"
  gj "$(printf 'echo $((1<<3))\ngit push --no-verify\n3')"                                    2 "a shift operator is no heredoc"
  gj "$(printf 'git commit -F - <<EOF\nbody\nEOF\ngit status')"                                0 "an ordinary heredoc followed by git status passes"
  gj 'git status && echo --no-verify'                          0 "looks at one command segment only (git status && echo --no-verify)"
  gj 'git config core.hooksPath .githooks'                     0 "lets an agent point core.hooksPath back at .githooks"
  gj 'git config core.hooksPath'                               0 "lets reading core.hooksPath through"
  gj 'git config --get core.hooksPath && echo ok'              0 "lets --get core.hooksPath && ... through"
fi

# ---- the guard, round 2: destructive commands and the guardrail files themselves ----------------------------------
# Commands that lose work or data are blocked; the human runs them (Claude Code: `! <command>`) or starts the session
# with SLICKRAILS_ALLOW_DESTRUCTIVE=1. Writes to the files that hold the guardrails (hook scripts, config.sh, .githooks,
# agent hook settings) are blocked too: an agent once edited the guard script right after it had been blocked.
if command -v jq >/dev/null 2>&1; then
  gj 'git reset --hard'                                        2 "blocks git reset --hard (uncommitted work is gone)"
  gj 'git reset --hard origin/main'                            2 "blocks git reset --hard <ref>"
  gj 'git reset --soft HEAD~1'                                 0 "lets git reset --soft through"
  gj 'git clean -fdx'                                          2 "blocks git clean -fdx"
  gj 'git clean -n'                                            0 "lets a dry-run git clean -n through"
  gj 'git push --force origin feat'                            2 "blocks git push --force (use --force-with-lease)"
  gj 'git push origin feat -f'                                 2 "blocks git push -f"
  gj 'git push --force-with-lease origin feat'                 0 "lets --force-with-lease on a feature branch through"
  gj 'git push --force-with-lease origin main'                 2 "blocks any forced push onto main"
  gj 'git push origin +main'                                   2 "blocks a +refspec onto main"
  gj 'git push -u origin feat'                                 0 "lets an ordinary push through"
  gj 'git checkout -- .'                                       2 "blocks git checkout -- . (discards every change)"
  gj 'git restore .'                                           2 "blocks git restore . (discards every change)"
  gj 'git restore --staged .'                                  0 "lets git restore --staged . (only unstages) through"
  # --worktree next to --staged discards the tree too (found by the real claude review, 2026-10-29)
  gj 'git restore --staged --worktree .'                       2 "blocks git restore --staged --worktree ."
  gj 'git restore -SW .'                                       2 "blocks git restore -SW ."
  gj 'git restore -S .'                                        0 "lets git restore -S . (only unstages) through"
  # the exemption belongs to the command that has the . (found by the real claude review, 2026-10-29)
  gj 'git restore --staged a.txt; git restore .'               2 "an unstage before it does not let a discarding restore . through"
  gj 'git restore -S a && git checkout .'                      2 "an unstage before it does not let a discarding checkout . through"
  gj 'git checkout -b feat'                                    0 "lets git checkout -b through"
  gj 'rm -rf /'                                                2 "blocks rm -rf /"
  gj 'rm -rf ~'                                                2 "blocks rm -rf ~"
  gj 'rm -rf "$HOME"'                                          2 "blocks rm -rf \"\$HOME\" (quoted)"
  # quotes around part of the target (found by the real claude review, 2026-11-02)
  gj 'rm -rf "$HOME"/'                                         2 "blocks rm -rf \"\$HOME\"/"
  gj 'rm -rf "$HOME"/*'                                        2 "blocks rm -rf \"\$HOME\"/*"
  gj 'rm -rf "${HOME}"'                                        2 "blocks rm -rf \"\${HOME}\""
  gj 'rm -rf "$HOME/project/dist"'                             0 "lets rm -rf of a folder inside \$HOME through"
  gj 'cd app && rm -fr .'                                      2 "blocks rm -fr . behind &&"
  gj 'sudo rm -r .git'                                         2 "blocks rm -r .git"
  gj 'rm -rf node_modules dist'                                0 "lets rm -rf of build folders through"
  gj 'git commit -m "never rm -rf / in scripts"'               0 "a commit message about rm -rf / is text"
  gj 'php artisan migrate:fresh --seed'                        2 "blocks artisan migrate:fresh"
  gj 'npx prisma migrate reset'                                2 "blocks prisma migrate reset"
  gj 'bin/rails db:drop'                                       2 "blocks rails db:drop"
  gj 'psql -c "DROP TABLE users"'                              2 "blocks DROP TABLE through psql"
  gj 'php artisan migrate'                                     0 "lets an ordinary migration through"
  gj 'psql -c "select 1"'                                      0 "lets an ordinary query through"
  # a ; inside quotes does not end the command (found by the real claude review, 2026-10-29)
  gj 'psql -c "BEGIN; DROP TABLE users"'                      2 "blocks DROP TABLE after another statement in the same quoted SQL"
  gj 'psql -c "select 1; select 2"'                           0 "lets two harmless statements in one quoted SQL through"
  gj 'echo "a;b" > .slickrails/config.sh'                     2 "a ; inside the quoted text does not hide the redirect onto config.sh"
  # each line of a multi-line call is its own command (found by the real claude review, 2026-10-29)
  gj "$(printf 'git push origin feat\nrm -f tmp.txt')"                                          0 "a push followed by rm -f on the next line is no forced push"
  gj "$(printf 'git checkout feat\nls .')"                                                     0 "a checkout followed by ls . on the next line discards nothing"
  gj "$(printf 'git commit -m x \\\n  --no-verify')"                                           2 "a --no-verify after a line continuation is still blocked"
  gj "$(printf 'git push origin feat \\\n  --force')"                                          2 "a --force after a line continuation is still blocked"
  printf '{"tool_name":"Bash","tool_input":{"command":"git reset --hard"}}' | env SLICKRAILS_ALLOW_DESTRUCTIVE=1 sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "bash-guard: SLICKRAILS_ALLOW_DESTRUCTIVE=1 (set by the human) allows a destructive command" \
    || fail "bash-guard: SLICKRAILS_ALLOW_DESTRUCTIVE=1 allows a destructive command"
  DG_MSG="$(printf '{"tool_name":"Bash","tool_input":{"command":"git reset --hard"}}' | sh "$KIT_DIR/templates/bash-guard.sh" 2>&1)"
  case "$DG_MSG" in *'! <command>'*) ok "bash-guard: the destructive-command message tells the human how to run it";; *) fail "bash-guard: the destructive-command message tells the human how to run it ($DG_MSG)";; esac
  # the guardrail files, through the shell
  gj 'rm .slickrails/bash-guard.sh'                            2 "blocks deleting the guard script"
  gj 'echo "exit 0" > .slickrails/session-check.sh'            2 "blocks overwriting the Stop gate by redirection"
  gj 'sed -i "" "s/CHECK_TEST=.*/CHECK_TEST=true/" ".slickrails/config.sh"' 2 "blocks sed -i on config.sh (quoted path)"
  gj 'cp /tmp/x .githooks/pre-push'                            2 "blocks copying over a git hook"
  gj 'printf "{}" > .claude/settings.local.json'               2 "blocks overwriting the local Claude settings"
  gj 'tee .codex/hooks.json < /dev/null'                       2 "blocks tee onto the Codex hooks file"
  gj 'cat .slickrails/config.sh'                               0 "lets reading config.sh through"
  gj 'sh .slickrails/session-check.sh'                         0 "lets running the Stop gate through"
  gj 'git diff .githooks/pre-push > /tmp/hook.diff'            0 "lets a diff of a hook into /tmp through"
  gj 'git commit -m "fix: rm .slickrails/x was wrong"'         0 "a commit message naming a guardrail file is text"
  # a > inside quotes is text, a quoted redirect target is still a target (found by the real claude review, 2026-10-29)
  gj 'git commit -m "docs: never echo x > .slickrails/config.sh"' 0 "a commit message with a quoted > onto a guardrail file is text"
  gj 'echo x > "/My Repo/.slickrails/config.sh"'               2 "blocks a redirect onto a quoted guardrail path with a space"
  gj 'npm test 2>&1 | tee build.log'                           0 "2>&1 and a pipe are no redirect onto a guardrail file"
  gj 'echo x >> .slickrails/review-learnings.md'               0 "lets an agent append to the review learnings"
  # the folders that hold them, as a whole (found by the real claude review, 2026-10-29)
  gj 'rm -rf .slickrails'                                      2 "blocks deleting the whole .slickrails folder"
  gj 'mv .slickrails /tmp/x'                                   2 "blocks moving the .slickrails folder away"
  gj 'rm -rf ./.claude'                                        2 "blocks deleting the .claude folder"
  gj 'rm -r .codex/'                                           2 "blocks deleting the .codex folder"
  gj 'rm -rf .githooks'                                        2 "blocks deleting the .githooks folder"
  gj 'rm -rf .slickrails/*'                                    2 "blocks emptying .slickrails with a glob"
  gj 'rm -rf .claude/*'                                        2 "blocks emptying .claude with a glob"
  gj 'rm -f .slickrails/*.bak'                                 0 "lets a glob that hits no guardrail file through"
  gj 'cp review.md .claude/commands/'                          0 "lets an agent add a file elsewhere under .claude"
  gj 'ls -la .slickrails .claude'                              0 "lets listing the folders through"
  # the guardrail files, through the agent's own edit tools (Claude Code: Edit, Write, MultiEdit, NotebookEdit)
  ge() { # ge <tool> <path> <expected-exit> <description>
    jq -cn --arg t "$1" --arg p "$2" '{tool_name:$t,tool_input:{file_path:$p,content:"x"}}' | sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1
    GE_RC=$?
    if [ "$GE_RC" -eq "$3" ]; then ok "bash-guard: $4"; else fail "bash-guard: $4 (exit $GE_RC, wanted $3)"; fi
  }
  ge Edit  "/Users/x/My Repo/.slickrails/bash-guard.sh" 2 "Edit on the guard script (absolute path with a space) is blocked"
  ge Write ".slickrails/config.sh"                      2 "Write on config.sh is blocked"
  ge Write ".claude/settings.json"                      2 "Write on .claude/settings.json is blocked"
  ge MultiEdit "/r/.githooks/pre-commit"                2 "MultiEdit on a git hook is blocked"
  ge Edit  "/r/src/app.ts"                              0 "Edit on ordinary code passes"
  ge Edit  "/r/.slickrails/rules.md"                    0 "Edit on the review rules passes (project-specific, meant to be edited)"
  ge Write "/r/templates/bash-guard.sh"                 0 "Write on a file that merely has a guard's name passes"
  printf '{"tool_name":"Write","tool_input":{"file_path":".slickrails/config.sh"}}' | env SLICKRAILS_ALLOW_BYPASS=1 sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "bash-guard: SLICKRAILS_ALLOW_BYPASS=1 allows editing the guardrail files" || fail "bash-guard: SLICKRAILS_ALLOW_BYPASS=1 allows editing the guardrail files"
fi

# ---- package check: an agent installs a package that does not exist or appeared days ago (slopsquatting) ---------
# curl is a stub: answers come from fixture files named after the URL, every request is logged; no network in tests.
DEPFIX="$WORK/depfix"; mkdir -p "$DEPFIX/bin"
cat > "$DEPFIX/bin/curl" <<'STUB'
#!/bin/sh
OUT=""; URL=""
while [ $# -gt 0 ]; do case "$1" in -o) OUT="$2"; shift;; -w|--max-time|-H) shift;; -*) ;; *) URL="$1";; esac; shift; done
echo "$URL" >> "$DEPFIX/requests.log"
F="$DEPFIX/$(printf '%s' "$URL" | tr '/:@%' '____')"
[ -f "$F.offline" ] && exit 6
if [ -f "$F" ]; then cat "$F" > "${OUT:-/dev/stdout}"; printf 200; else printf 'Not Found' > "${OUT:-/dev/stdout}"; printf 404; fi
STUB
sed -i.bak "s|\$DEPFIX|$DEPFIX|g" "$DEPFIX/bin/curl" && rm -f "$DEPFIX/bin/curl.bak"; chmod +x "$DEPFIX/bin/curl"
fix() { printf '%s' "$2" > "$DEPFIX/$(printf '%s' "$1" | tr '/:@%' '____')"; }
TODAY="$(date -u +%Y-%m-%d)"
fix "https://api.npmjs.org/downloads/point/last-week/lodash"            '{"downloads":51234567,"package":"lodash"}'
fix "https://api.npmjs.org/downloads/point/last-week/@types/node"       '{"downloads":98000000,"package":"@types/node"}'
fix "https://api.npmjs.org/downloads/point/last-week/tiny-old"          '{"downloads":40,"package":"tiny-old"}'
fix "https://registry.npmjs.org/tiny-old"                               '{"name":"tiny-old","time":{"created":"2019-03-02T10:00:00.000Z"}}'
fix "https://api.npmjs.org/downloads/point/last-week/left-padx"         '{"downloads":12,"package":"left-padx"}'
fix "https://registry.npmjs.org/left-padx"                              "{\"name\":\"left-padx\",\"time\":{\"created\":\"${TODAY}T01:00:00.000Z\"}}"
fix "https://api.npmjs.org/downloads/point/last-week/react-auth-helperz" '{"error":"package react-auth-helperz not found"}'
fix "https://pypi.org/pypi/requests/json"  '{"info":{"name":"requests"},"releases":{"0.2.0":[{"upload_time":"2011-02-14T00:00:00"}],"2.32.3":[{"upload_time":"2024-05-29T00:00:00"}]}}'
fix "https://pypi.org/pypi/flask/json"     '{"info":{"name":"flask"},"releases":{"0.1":[{"upload_time": "2010-04-16T00:00:00"}]}}'
fix "https://pypi.org/pypi/fresh-helper/json" "{\"info\":{\"name\":\"fresh-helper\"},\"releases\":{\"0.0.1\":[{\"upload_time\":\"${TODAY}T08:00:00\"}]}}"
gd() { # gd <command-text> <expected-exit> <description>   (guard with the stub curl on PATH)
  : > "$DEPFIX/requests.log"; mkdir -p "$DEPFIX/home"
  jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | HOME="$DEPFIX/home" PIP_INDEX_URL='' NPM_CONFIG_REGISTRY='' PATH="$DEPFIX/bin:$PATH" sh "$KIT_DIR/templates/bash-guard.sh" >"$DEPFIX/out" 2>&1
  GD_RC=$?
  if [ "$GD_RC" -eq "$2" ]; then ok "package check: $3"; else fail "package check: $3 (exit $GD_RC, wanted $2: $(head -2 "$DEPFIX/out" | tr '\n' ' '))"; fi
}
if command -v jq >/dev/null 2>&1; then
  gd 'npm install lodash'                                 0 "a popular npm package passes"
  gd 'npm i -D @types/node@^22'                            0 "a scoped package with a version range passes"
  gd 'pnpm add tiny-old'                                  0 "an old npm package with few downloads passes"
  # a name that is not on the registry fails to install by itself; it is pointed out, not blocked (workspace packages
  # and private registries are not on the public one either). The danger is the made-up name someone registered since.
  gd 'npm install react-auth-helperz'                     0 "an npm package that is not on npm is not blocked (the install fails by itself)"
  case "$(cat "$DEPFIX/out")" in *"not on npm"*) ok "package check: ...but it is pointed out";; *) fail "package check: ...but it is pointed out";; esac
  gd 'npm install @acme/utils -w apps/web'                0 "a workspace package of the repo's own monorepo is not blocked"
  gd 'yarn add left-padx'                                 2 "an npm package first published today is blocked"
  gd 'bun add lodash left-padx'                           2 "one young package among several is enough to block"
  gd 'pip install "requests>=2" flask[async]==3.0'        0 "PyPI packages with specifiers and extras pass"
  grep -q 'pypi.org/pypi/requests/json' "$DEPFIX/requests.log" && grep -q 'pypi.org/pypi/flask/json' "$DEPFIX/requests.log" \
    && ok "package check: ...and both were really looked up" || fail "package check: ...and both were really looked up ($(tr '\n' ' ' < "$DEPFIX/requests.log"))"
  # a version range must not hide the name (found by the real claude review, 2026-10-29)
  gd 'pip install "fresh-helper>=1"'                      2 "a young PyPI package with a quoted >= range is blocked"
  gd 'npm install "left-padx@<2"'                         2 "a young npm package with a quoted <2 range is blocked"
  # the age comes from the registry's own field, not from anything a package author wrote
  # (found by the real claude review, 2026-11-02: a decoy "created" in package.json made a package published today pass)
  fix "https://api.npmjs.org/downloads/point/last-week/decoy-npm" '{"downloads":3,"package":"decoy-npm"}'
  fix "https://registry.npmjs.org/decoy-npm" "{\"name\":\"decoy-npm\",\"versions\":{\"1.0.0\":{\"name\":\"decoy-npm\",\"created\":\"2015-01-01T00:00:00.000Z\",\"time\":{\"created\":\"2015-01-01T00:00:00.000Z\"}}},\"time\":{\"created\":\"${TODAY}T01:00:00.000Z\",\"1.0.0\":\"${TODAY}T01:00:00.000Z\"}}"
  fix "https://pypi.org/pypi/decoy-py/json" "{\"info\":{\"name\":\"decoy-py\",\"description\":\"see \\\"upload_time\\\": \\\"2010-01-01T00:00:00\\\"\"},\"releases\":{\"0.1\":[{\"upload_time\":\"${TODAY}T08:00:00\"}]}}"
  gd 'npm install decoy-npm'                              2 "a decoy created date inside a version manifest does not make a new npm package old"
  gd 'pip install decoy-py'                               2 "a decoy upload_time inside the description does not make a new PyPI package old"
  # boolean flags do not swallow the next word (npm -f after ERESOLVE is common; pnpm -w is the workspace root)
  gd 'npm install -f left-padx'                           2 "npm install -f <young package> is still checked"
  gd 'pnpm add -w left-padx'                              2 "pnpm add -w <young package> is still checked"
  gd 'pnpm add --workspace left-padx'                     2 "pnpm add --workspace <young package> is still checked (a flag there)"
  gd 'pnpm add --filter web left-padx'                    2 "pnpm --filter <project> skips the project name, not the package"
  gd 'npm install -w apps/web left-padx'                  2 "npm -w <workspace> skips the workspace name, not the package"
  gd 'pip install -r requirements.txt left-padx-py'       0 "pip -r still takes its file as the value"
  grep -q 'requirements' "$DEPFIX/requests.log" && fail "package check: ...and does not look the file up" || ok "package check: ...and does not look the file up"
  # a private registry is not the public one: no lookup, no block (found by the real claude review, 2026-10-29)
  gd 'npm install --registry https://npm.corp.test corp-ui' 0 "an install from --registry is not checked against npm"
  gd 'pip install --index-url https://pypi.corp.test/simple corp-utils' 0 "an install from --index-url is not checked against PyPI"
  [ ! -s "$DEPFIX/requests.log" ] && ok "package check: ...and asks no public registry" || fail "package check: ...and asks no public registry ($(head -1 "$DEPFIX/requests.log"))"
  printf '@acme:registry=https://npm.pkg.github.com\n' > .npmrc
  gd 'npm install @acme/internal-lib'                     0 "a scope mapped to another registry in .npmrc is not checked"
  gd 'npm install left-padx'                              2 "...while an unscoped young package in the same repo is still blocked"
  printf '[[tool.uv.index]]\nurl = "https://pypi.corp.test/simple"\n' > pyproject.toml
  gd 'uv add acme-internal-lib'                           0 "a package from a project's own index (not on PyPI) is not blocked"
  rm -f pyproject.toml
  rm -f .npmrc
  printf 'registry=https://npm.corp.test/\n' > "$DEPFIX/home/.npmrc"
  gd 'npm install corp-only-pkg'                          0 "a default registry other than npm in ~/.npmrc means no npm check"
  rm -f "$DEPFIX/home/.npmrc"
  gd 'pip install requests > /tmp/pip.log 2>&1'           0 "a redirect after the install is not taken for a package"
  grep -Eq '/(2|1|tmp)(/|$)' "$DEPFIX/requests.log" && fail "package check: ...and makes no request for the redirect" || ok "package check: ...and makes no request for the redirect"
  gd 'python3 -m pip install fresh-helper'                2 "a PyPI package first uploaded today is blocked"
  # an answer without a first-publish date is not "published today" (found by the real claude review, 2026-10-29)
  fix "https://pypi.org/pypi/no-dates/json" '{"info":{"name":"no-dates"},"urls":[]}'
  fix "https://api.npmjs.org/downloads/point/last-week/no-created" '{"downloads":3,"package":"no-created"}'
  fix "https://registry.npmjs.org/no-created" '{"name":"no-created","time":{}}'
  gd 'pip install no-dates'                               0 "a PyPI answer without upload dates lets the install through"
  case "$(cat "$DEPFIX/out")" in *"not checked"*"no-dates"*) ok "package check: ...and says it was not checked";; *) fail "package check: ...and says it was not checked";; esac
  gd 'npm install no-created'                             0 "an npm answer without time.created lets the install through"
  gd 'uv add pip-made-up-name'                            0 "a PyPI package that is not on PyPI is not blocked"
  case "$(cat "$DEPFIX/out")" in *"not on PyPI"*) ok "package check: ...but it is pointed out";; *) fail "package check: ...but it is pointed out";; esac
  gd 'cd web && npm ci && npm install'                    0 "installing from the lockfile is not checked"
  [ ! -s "$DEPFIX/requests.log" ] && ok "package check: a lockfile install makes no request" || fail "package check: a lockfile install makes no request ($(head -1 "$DEPFIX/requests.log"))"
  gd 'pip install -r requirements.txt -e .'               0 "requirements files and local paths are not checked"
  [ ! -s "$DEPFIX/requests.log" ] && ok "package check: -r and -e make no request" || fail "package check: -r and -e make no request ($(head -1 "$DEPFIX/requests.log"))"
  gd 'npm install ./vendor/pkg git+https://x.test/r.git'  0 "local paths and git URLs are not checked"
  gd 'echo "npm install react-auth-helperz"'              0 "an install command inside text is not run"
  touch "$DEPFIX/$(printf '%s' 'https://api.npmjs.org/downloads/point/last-week/react-auth-helperz' | tr '/:@%' '____').offline"
  gd 'npm install react-auth-helperz'                     0 "an unreachable registry lets the install through (fail open)"
  case "$(cat "$DEPFIX/out")" in *"not checked"*) ok "package check: an unreachable registry is said, not hidden";; *) fail "package check: an unreachable registry is said, not hidden";; esac
  : > "$DEPFIX/requests.log"
  jq -cn '{tool_name:"Bash",tool_input:{command:"yarn add left-padx"}}' | env SLICKRAILS_ALLOW_NEW_DEPS=1 PATH="$DEPFIX/bin:$PATH" sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1
  [ $? -eq 0 ] && [ ! -s "$DEPFIX/requests.log" ] && ok "package check: SLICKRAILS_ALLOW_NEW_DEPS=1 (set by the human) skips it" || fail "package check: SLICKRAILS_ALLOW_NEW_DEPS=1 (set by the human) skips it"
fi

# Settings merge edge cases
new_repo empty-settings-repo
mkdir .claude; : > .claude/settings.json
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
if command -v jq >/dev/null 2>&1; then
  jq -e '(.hooks.Stop | length == 1) and (.hooks.PreToolUse | length == 1)' .claude/settings.json >/dev/null 2>&1 \
    && ok "installer: an empty settings.json becomes a valid settings file with both hooks" \
    || fail "installer: an empty settings.json becomes a valid settings file with both hooks ($(wc -c < .claude/settings.json | tr -d ' ') bytes)"
fi
new_repo fooled-settings-repo
mkdir .claude
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo session-check.sh bash-guard.sh"}]}]}}' > .claude/settings.json
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
[ "$(grep -c 'CLAUDE_PROJECT_DIR' .claude/settings.json)" -ge 2 ] \
  && ok "installer: a foreign hook that merely mentions our script names does not suppress the merge" \
  || fail "installer: a foreign hook that merely mentions our script names does not suppress the merge"
# an install from before the write protection has the guard on `Bash` only; re-running the installer widens it
new_repo widen-matcher-repo
mkdir .claude
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"sh \\"$CLAUDE_PROJECT_DIR/.slickrails/bash-guard.sh\\"","timeout":10}]}]}}' > .claude/settings.json
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
grep -q '"Bash|Edit|Write|MultiEdit|NotebookEdit"' .claude/settings.json && [ "$(grep -c 'bash-guard.sh' .claude/settings.json)" -eq 1 ] \
  && ok "installer: an old Bash-only guard is widened to the edit tools (no duplicate)" \
  || fail "installer: an old Bash-only guard is widened to the edit tools (no duplicate): $(tr -d '\n' < .claude/settings.json)"
new_repo symlink-settings-repo
mkdir .claude; printf '{"model":"x"}' > real-settings.json; ln -s ../real-settings.json .claude/settings.json
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
if [ -L .claude/settings.json ] && grep -q 'bash-guard.sh' real-settings.json; then ok "installer: a symlinked settings.json stays a symlink and the target gets the hooks"
else fail "installer: a symlinked settings.json stays a symlink and the target gets the hooks"; fi
new_repo shape-settings-repo
mkdir .claude; printf '{"hooks":{"Stop":{"oops":true}}}' > .claude/settings.json
INST_OUT="$(sh "$KIT_DIR/install.sh" 2>&1)"
case "$INST_OUT" in *"unexpected shape"*) ok "installer: names the reason when the settings have an unexpected shape";; *) fail "installer: names the reason when the settings have an unexpected shape";; esac
new_repo json-reason-repo
mkdir .claude; printf '{ not json' > .claude/settings.json
INST_OUT="$(sh "$KIT_DIR/install.sh" 2>&1)"
case "$INST_OUT" in *"not valid JSON"*) ok "installer: names the reason when the settings are not valid JSON";; *) fail "installer: names the reason when the settings are not valid JSON";; esac

# Our own hook directory written differently is still ours; a rerun after a hook manager appeared updates the status.
for HP in ".githooks/" "./.githooks"; do
  new_repo "hp-variant-repo"
  git config core.hooksPath "$HP"
  INST_OUT="$(sh "$KIT_DIR/install.sh" 2>&1)"
  case "$INST_OUT" in *"NOT active"*) fail "installer: core.hooksPath '$HP' is our own directory, not a foreign hook manager";; *) ok "installer: core.hooksPath '$HP' is our own directory, not a foreign hook manager";; esac
done
new_repo status-rerun-repo
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
mkdir .husky; git config core.hooksPath .husky
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
grep -q 'NOT active' .slickrails/STATUS.md && ok "installer: a rerun after a hook manager appeared records it in .slickrails/STATUS.md" \
  || fail "installer: a rerun after a hook manager appeared records it in .slickrails/STATUS.md"
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
[ "$(grep -c 'NOT active' .slickrails/STATUS.md)" = "1" ] && ok "installer: ...and does not repeat the line on every run" \
  || fail "installer: ...and does not repeat the line on every run"

# doctor: never runs project code, judges the configuration structurally
new_repo doctor2-src
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
git config core.hooksPath .githooks
printf 'touch "%s/doctor-side-effect"\nexit 3\n' "$WORK" >> .slickrails/config.sh
rm -f "$WORK/doctor-side-effect"
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"
[ ! -f "$WORK/doctor-side-effect" ] && ok "doctor: does not execute .slickrails/config.sh" || fail "doctor: does not execute .slickrails/config.sh"
new_repo doctor3-src
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
printf 'CHECK_TEST=""\nexit 3\n' > .slickrails/config.sh
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"
case "$DOC_OUT" in *"defines checks"*) fail "doctor: a config without any check is not reported as 'defines checks'";; *) ok "doctor: a config without any check is not reported as 'defines checks'";; esac
printf 'CHECK_TEST="npm test"\nif then\n' > .slickrails/config.sh
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
[ "$DOC_RC" -ne 0 ] && ok "doctor: a config with a syntax error is a problem (exit $DOC_RC)" || fail "doctor: a config with a syntax error is a problem"
printf 'CHECK_TEST="npm test"\n' > .slickrails/config.sh
git config core.hooksPath .githooks
rm .slickrails/bash-guard.sh
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
[ "$DOC_RC" -ne 0 ] && ok "doctor: a configured but missing bash-guard.sh is a problem" || fail "doctor: a configured but missing bash-guard.sh is a problem"
cp "$KIT_DIR/templates/bash-guard.sh" .slickrails/bash-guard.sh
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"sh \\"$CLAUDE_PROJECT_DIR/.slickrails/session-check.sh\\""}]}]}}' > .claude/settings.json
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
[ "$DOC_RC" -ne 0 ] && ok "doctor: a Stop hook without the Bash guard in settings is a problem" || fail "doctor: a Stop hook without the Bash guard in settings is a problem"
sh "$KIT_DIR/install.sh" >/dev/null 2>&1      # re-merge the guard
mkdir -p .husky; printf '#!/bin/sh\nsh .githooks/pre-commit\n' > .husky/pre-commit
git config core.hooksPath .husky
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
[ "$DOC_RC" -eq 0 ] && ok "doctor: a hook manager that calls .githooks/* counts as chained (exit 0)" || fail "doctor: a hook manager that calls .githooks/* counts as chained (exit $DOC_RC)"
git config --unset core.hooksPath
DOC_OUT="$(CI=true sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
[ "$DOC_RC" -eq 0 ] && ok "doctor: in CI a missing core.hooksPath is a warning, not a failure" || fail "doctor: in CI a missing core.hooksPath is a warning, not a failure (exit $DOC_RC)"

# doctor self-test: installed is not working — the guard and pre-commit get a probe each and must answer right
new_repo doctor-probe-repo
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
git config core.hooksPath .githooks
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
case "$DOC_OUT" in *"ok       Bash guard blocks a --no-verify probe"*) ok "doctor: the installed Bash guard is probed and blocks";; *) fail "doctor: the installed Bash guard is probed and blocks";; esac
case "$DOC_OUT" in *"ok       pre-commit blocks a staged test key"*) ok "doctor: the installed pre-commit hook is probed and blocks a key";; *) fail "doctor: the installed pre-commit hook is probed and blocks a key";; esac
[ "$DOC_RC" -eq 0 ] && ok "doctor: a working install passes its self-test (exit 0)" || fail "doctor: a working install passes its self-test (exit $DOC_RC)"
cp .slickrails/bash-guard.sh "$WORK/guard.keep"
printf '#!/bin/sh\nexit 0\n' > .slickrails/bash-guard.sh
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
case "$DOC_OUT" in *"PROBLEM  Bash guard lets a --no-verify probe through"*) [ "$DOC_RC" -ne 0 ] && ok "doctor: a guard that lets everything through is a problem" || fail "doctor: a guard that lets everything through is a problem (exit 0)";;
  *) fail "doctor: a guard that lets everything through is a problem";; esac
printf '#!/bin/sh\nexit 2\n' > .slickrails/bash-guard.sh
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"
case "$DOC_OUT" in *"PROBLEM  Bash guard blocks a harmless git status"*) ok "doctor: a guard that blocks everything is a problem";; *) fail "doctor: a guard that blocks everything is a problem";; esac
cp "$WORK/guard.keep" .slickrails/bash-guard.sh
printf '#!/bin/sh\nexit 0\n' > .githooks/pre-commit
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
case "$DOC_OUT" in *"PROBLEM  pre-commit lets a staged test key through"*) [ "$DOC_RC" -ne 0 ] && ok "doctor: a pre-commit hook that lets a key through is a problem" || fail "doctor: a pre-commit hook that lets a key through is a problem (exit 0)";;
  *) fail "doctor: a pre-commit hook that lets a key through is a problem";; esac

# Protection script: what is compared, which values are accepted, what the stub insists on
protect "$RB_ON" X=1
grep -q '"contexts": \[ "ci", "gitleaks", "audit", "size" \]' "$WORK/gh.body" 2>/dev/null \
  && ok "protection: the request carries the required contexts" || fail "protection: the request carries the required contexts"
protect '{"required_status_checks":{"strict":true,"contexts":["ci"]},"enforce_admins":{"enabled":true}}' X=1
[ "$PR_RC" -ne 0 ] && case "$PR_OUT" in *MISMATCH*) ok "protection: differing status check contexts fail with MISMATCH";; *) fail "protection: differing contexts name the MISMATCH";; esac \
  || fail "protection: differing status check contexts fail (exit $PR_RC)"
protect '{"required_status_checks":{"strict":false,"contexts":["ci","gitleaks","audit","size"]},"enforce_admins":{"enabled":true}}' X=1
[ "$PR_RC" -ne 0 ] && ok "protection: strict=false (branch need not be up to date) is a MISMATCH" || fail "protection: strict=false is a MISMATCH"
protect '{"required_status_checks":{"strict":true,"contexts":["ci","gitleaks","audit","size"]},"enforce_admins":{"enabled":true},"required_pull_request_reviews":{"required_approving_review_count":1}}' X=1
[ "$PR_RC" -ne 0 ] && ok "protection: a review requirement nobody asked for is a MISMATCH, not 'PRs are NOT required'" \
  || fail "protection: a review requirement nobody asked for is a MISMATCH (exit 0)"
protect "$RB_OFF" ENFORCE_ADMINS=off
grep -q '"enforce_admins": false' "$WORK/gh.body" 2>/dev/null && ok "protection: ENFORCE_ADMINS=off means off" || fail "protection: ENFORCE_ADMINS=off means off"
protect "$RB_ON" ENFORCE_ADMINS=maybe
[ "$PR_RC" -ne 0 ] && [ ! -f "$WORK/gh.body" ] && ok "protection: an unknown ENFORCE_ADMINS value stops before anything is sent" \
  || fail "protection: an unknown ENFORCE_ADMINS value stops before anything is sent (exit $PR_RC)"

# ---- installer honesty, round 3 (Codex review of eb0e69a): no jq on the machine ------------------------------
# NOJQ_NODE = a PATH with node but without jq; NOJQ_NONE = a PATH with neither (system tools only).
NOJQ_BASE="$WORK/nojq-base"; NOJQ_NODE="$WORK/nojq-node"
mkdir -p "$NOJQ_BASE" "$NOJQ_NODE"
# launchers, not symlinks: on Windows a linked .exe does not reliably run away from its DLLs, and Git Bash keeps git
# in /mingw64/bin, outside /usr/bin
tool_launcher() { printf '#!/bin/sh\nexec "%s" "$@"\n' "$1" > "$2"; chmod +x "$2"; }
for F in /usr/bin/* /bin/*; do
  B="${F##*/}"; B="${B%.exe}"
  case "$B" in jq|node|*.dll|*.*) continue;; esac
  [ -f "$F" ] && [ -x "$F" ] && [ ! -e "$NOJQ_BASE/$B" ] && tool_launcher "$F" "$NOJQ_BASE/$B"
done
[ -e "$NOJQ_BASE/git" ] || tool_launcher "$(command -v git)" "$NOJQ_BASE/git"
NODE_BIN="$(command -v node 2>/dev/null || true)"
[ -n "$NODE_BIN" ] && tool_launcher "$NODE_BIN" "$NOJQ_NODE/node"
# without jq and node the guard matches the raw hook JSON: an Edit on a guardrail file is still caught
printf '{"tool_name":"Edit","tool_input":{"file_path":"/r/.slickrails/bash-guard.sh"}}' | env PATH="$NOJQ_BASE" sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1
[ $? -eq 2 ] && ok "bash-guard without jq and node: an Edit on the guard script is still blocked" || fail "bash-guard without jq and node: an Edit on the guard script is still blocked"
printf '{"tool_name":"Edit","tool_input":{"file_path":"/r/src/app.ts"}}' | env PATH="$NOJQ_BASE" sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1
[ $? -eq 0 ] && ok "bash-guard without jq and node: an Edit on ordinary code passes" || fail "bash-guard without jq and node: an Edit on ordinary code passes"
# the package check without jq and node: the decoys must not win there either
# (an outside review saw both fail once in an Ubuntu container: registry settings of the host are cleared here, and a
# failure prints what the check said and which tools it found, so the next one can be told apart from a host quirk)
for DC in "npm install decoy-npm" "pip install decoy-py"; do
  printf '%s\n' "$DC" | env -u NPM_CONFIG_REGISTRY -u npm_config_registry -u PIP_INDEX_URL -u UV_INDEX_URL -u UV_DEFAULT_INDEX \
    HOME="$DEPFIX/home" PATH="$DEPFIX/bin:$NOJQ_BASE" sh "$KIT_DIR/templates/dep-check.sh" >"$DEPFIX/nojq.out" 2>&1
  DC_RC=$?
  if [ "$DC_RC" -eq 2 ]; then ok "package check without jq and node: $DC is still judged by the registry's date"
  else
    fail "package check without jq and node: $DC is still judged by the registry's date (exit $DC_RC: $(head -3 "$DEPFIX/nojq.out" | tr '\n' ' ')| tools: $(for T in awk sed grep sort date mktemp; do printf '%s=%s ' "$T" "$(PATH="$NOJQ_BASE" command -v "$T" >/dev/null 2>&1 && echo yes || echo NO)"; done)| /etc/pip.conf: $([ -f /etc/pip.conf ] && echo present || echo none))"
  fi
done
FOOLED='{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo .slickrails/session-check.sh .slickrails/bash-guard.sh"}]}]}}'

if [ -n "$NODE_BIN" ] && command -v jq >/dev/null 2>&1; then
  new_repo nojq-node-repo
  mkdir .claude; printf '%s' "$FOOLED" > .claude/settings.json
  PATH="$NOJQ_NODE:$NOJQ_BASE" sh "$KIT_DIR/install.sh" >/dev/null 2>&1
  [ "$(grep -c 'CLAUDE_PROJECT_DIR' .claude/settings.json)" -ge 2 ] \
    && ok "installer without jq (node only): a foreign hook that mentions our script paths does not suppress the merge" \
    || fail "installer without jq (node only): a foreign hook that mentions our script paths does not suppress the merge"
  # the guard parses the hook JSON with node, so a harmless quoted mention passes without jq as well
  gn() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | env PATH="$NOJQ_NODE:$NOJQ_BASE" sh "$KIT_DIR/templates/bash-guard.sh" >/dev/null 2>&1; GN_RC=$?; }
  gn 'echo "release notes mention git commit --no-verify"'
  [ "$GN_RC" -eq 0 ] && ok "bash-guard without jq (node only): a quoted mention of --no-verify passes" || fail "bash-guard without jq (node only): a quoted mention of --no-verify passes (exit $GN_RC)"
  gn 'git commit --no-verify -m x'
  [ "$GN_RC" -eq 2 ] && ok "bash-guard without jq (node only): still blocks git commit --no-verify" || fail "bash-guard without jq (node only): still blocks git commit --no-verify (exit $GN_RC)"
fi

if command -v jq >/dev/null 2>&1; then
  # same trap with jq: a foreign command that names our script PATHS (echo, extra arguments) is not our hook
  new_repo fooled-paths-repo
  mkdir .claude; printf '%s' "$FOOLED" > .claude/settings.json
  sh "$KIT_DIR/install.sh" >/dev/null 2>&1
  jq -e '(.hooks.Stop | length == 2) and (.hooks.PreToolUse | length == 1)' .claude/settings.json >/dev/null 2>&1 \
    && ok "installer (jq): a foreign command that names our script paths does not suppress the merge" \
    || fail "installer (jq): a foreign command that names our script paths does not suppress the merge"
  sh "$KIT_DIR/install.sh" >/dev/null 2>&1
  jq -e '(.hooks.Stop | length == 2) and (.hooks.PreToolUse | length == 1)' .claude/settings.json >/dev/null 2>&1 \
    && ok "installer (jq): ...and a rerun does not add the hooks a second time" \
    || fail "installer (jq): ...and a rerun does not add the hooks a second time"

  new_repo nojq-none-repo
  mkdir .claude; printf '%s' "$FOOLED" > .claude/settings.json
  INST_OUT="$(PATH="$NOJQ_BASE" sh "$KIT_DIR/install.sh" 2>&1)"
  [ "$(cat .claude/settings.json)" = "$FOOLED" ] && ok "installer with neither jq nor node: the settings file is left untouched" \
    || fail "installer with neither jq nor node: the settings file is left untouched"
  case "$INST_OUT" in *"neither jq nor node"*) ok "installer with neither jq nor node: says why nothing was merged";; *) fail "installer with neither jq nor node: says why nothing was merged ($(printf '%s' "$INST_OUT" | grep -i -m3 'settings\|error\|not found\|jq' | tr '\n' ' '))";; esac
  git config core.hooksPath .githooks
  DOC_OUT="$(PATH="$NOJQ_BASE" sh "$KIT_DIR/install.sh" doctor 2>&1)"
  case "$DOC_OUT" in
    *"Stop hook is configured"*|*"Bash guard (no --no-verify) is configured"*) fail "doctor with neither jq nor node: must not claim the hooks are configured";;
    *"cannot verify"*) ok "doctor with neither jq nor node: says it cannot verify the hooks";;
    *) fail "doctor with neither jq nor node: says it cannot verify the hooks ($(printf '%s' "$DOC_OUT" | tail -4 | tr '\n' ' '))";;
  esac
fi

# A repo path with a space: our own hook command is quoted as one token and must be recognised (Codex review of 1c76677).
space_hook_case() { # <description> <PATH for the installer>
  new_repo "space repo"
  mkdir .claude
  printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"sh \\"%s/.slickrails/session-check.sh\\""}]}]}}' "$PWD" > .claude/settings.json
  env PATH="$2" sh "$KIT_DIR/install.sh" >/dev/null 2>&1
  cp .claude/settings.json "$WORK/space-settings.after1"
  env PATH="$2" sh "$KIT_DIR/install.sh" >/dev/null 2>&1
  SPACE_STOPS="$(jq '.hooks.Stop | length' .claude/settings.json 2>/dev/null)"
  SPACE_GUARDS="$(jq '.hooks.PreToolUse | length' .claude/settings.json 2>/dev/null)"
  if [ "$SPACE_STOPS" = "1" ] && [ "$SPACE_GUARDS" = "1" ] && cmp -s .claude/settings.json "$WORK/space-settings.after1"; then ok "$1"
  else fail "$1 (Stop hooks: $SPACE_STOPS, guards: $SPACE_GUARDS; wanted 1 and 1, unchanged on rerun)"; fi
}
if command -v jq >/dev/null 2>&1; then
  space_hook_case "installer (jq): a quoted hook command with a space in the repo path counts as installed" "$PATH"
  [ -n "$NODE_BIN" ] && space_hook_case "installer (node only): a quoted hook command with a space in the repo path counts as installed" "$NOJQ_NODE:$NOJQ_BASE"
fi

# A repo path containing a double quote: the quote is shell-escaped inside the hook command (Codex review of 689aee9).
quote_hook_case() { # <description> <PATH for the installer> <agent flag> <hooks file> <event key to count>
  new_repo 'quote"repo'
  QPATH="$(printf '%s' "$PWD" | sed 's/"/\\"/g')"
  mkdir -p "$(dirname "$4")"
  jq -n --arg c "sh \"${QPATH}/.slickrails/session-check.sh\"" '{hooks:{Stop:[{hooks:[{type:"command",command:$c}]}]}}' > "$4"
  env PATH="$2" sh "$KIT_DIR/install.sh" "$3" >/dev/null 2>&1
  cp "$4" "$WORK/quote-hooks.after1"
  env PATH="$2" sh "$KIT_DIR/install.sh" "$3" >/dev/null 2>&1
  Q_STOPS="$(jq '.hooks.Stop | length' "$4" 2>/dev/null)"
  if [ "$Q_STOPS" = "1" ] && cmp -s "$4" "$WORK/quote-hooks.after1"; then ok "$1"
  else fail "$1 (Stop hooks: $Q_STOPS, wanted 1 and an unchanged rerun)"; fi
}
if command -v jq >/dev/null 2>&1; then
  quote_hook_case "installer (jq): an escaped double quote in the repo path does not duplicate the Claude Stop hook" "$PATH" "--agent=claude" .claude/settings.json
  quote_hook_case "installer (jq): an escaped double quote in the repo path does not duplicate the Codex Stop hook" "$PATH" "--agent=codex" .codex/hooks.json
  [ -n "$NODE_BIN" ] && quote_hook_case "installer (node only): an escaped double quote in the repo path does not duplicate the Stop hook" "$NOJQ_NODE:$NOJQ_BASE" "--agent=codex" .codex/hooks.json
fi

# The read-back compares contexts as a set: GitHub may return them in another order.
protect '{"required_status_checks":{"strict":true,"contexts":["size","audit","gitleaks","ci"]},"enforce_admins":{"enabled":true}}' X=1
[ "$PR_RC" -eq 0 ] && ok "protection: the same contexts in another order are not a MISMATCH" \
  || fail "protection: the same contexts in another order are not a MISMATCH (exit $PR_RC; $(printf '%s' "$PR_OUT" | tail -3 | tr '\n' ' '))"

# Windows: jq ends every output line with \r\n; values read with jq must not carry that \r into comparisons
if command -v jq >/dev/null 2>&1; then
  make_crlf_jq "$WORK/crlfjq"
  protect "$RB_ON" "PATH=$WORK/crlfjq:$WORK/ghstub:$PATH"
  [ "$PR_RC" -eq 0 ] && ok "protection: a matching read-back succeeds with a jq that writes CRLF (Windows)" \
    || fail "protection: a matching read-back succeeds with a jq that writes CRLF (Windows) (exit $PR_RC; $(printf '%s' "$PR_OUT" | tail -3 | tr '\n' ' '))"
fi

# ---- Codex parity (plan point 5): the same Stop gate and Bash guard for the Codex CLI ------------------------
# Codex hooks use the same shape as Claude Code's (matcher "Bash", tool_input.command, exit 2 blocks); there is no
# project-dir variable, so the commands resolve the repo root themselves. Measured on a real Codex CLI 0.163 (see
# docs/features/codex-parity.md): exit 2 = "Stop Blocked" (the model continues), timeout and crash = "Stop Failed" and
# the session ends — the same fail-open as Claude Code, hence the gate's own deadline and crash handling.
CXT="$KIT_DIR/templates/codex-hooks.json"
if command -v jq >/dev/null 2>&1; then
  jq -e '(.hooks.Stop | length == 1) and (.hooks.PreToolUse | length == 1) and (.hooks.PreToolUse[0].matcher == "Bash")' "$CXT" >/dev/null 2>&1 \
    && ok "codex-hooks.json: valid JSON with one Stop entry and one PreToolUse entry matching Bash" \
    || fail "codex-hooks.json: valid JSON with one Stop entry and one PreToolUse entry matching Bash"
  jq -e '[.hooks.Stop[].hooks[].command, .hooks.PreToolUse[].hooks[].command] | all(contains("git rev-parse --show-toplevel"))' "$CXT" >/dev/null 2>&1 \
    && ok "codex-hooks.json: commands resolve the repo root themselves (Codex sets no project-dir variable)" \
    || fail "codex-hooks.json: commands resolve the repo root themselves"
  jq -e '[.hooks.Stop[].hooks[].timeout] | all(. == 300)' "$CXT" >/dev/null 2>&1 \
    && ok "codex-hooks.json: the Stop hook timeout (300 s) is above the gate's own deadline (270 s)" \
    || fail "codex-hooks.json: the Stop hook timeout (300 s) is above the gate's own deadline (270 s)"
fi

new_repo agent-both-repo
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
[ -f .codex/hooks.json ] && [ -f .claude/settings.json ] && ok "installer: by default both agents get their hook configuration" \
  || fail "installer: by default both agents get their hook configuration"
new_repo agent-claude-repo
sh "$KIT_DIR/install.sh" --agent claude >/dev/null 2>&1
[ -f .claude/settings.json ] && [ ! -e .codex ] && ok "installer --agent claude: no Codex files" || fail "installer --agent claude: no Codex files"
new_repo agent-codex-repo
sh "$KIT_DIR/install.sh" --agent codex >/dev/null 2>&1
if [ -f .codex/hooks.json ] && [ ! -e .claude/settings.json ] && [ -x .slickrails/session-check.sh ] && [ -x .slickrails/bash-guard.sh ] && grep -q 'slickrails:start' AGENTS.md; then
  ok "installer --agent codex: .codex/hooks.json, the shared scripts and the AGENTS.md rules block, no Claude settings"
else fail "installer --agent codex: .codex/hooks.json, the shared scripts and the AGENTS.md rules block, no Claude settings"; fi
INST_OUT="$(sh "$KIT_DIR/install.sh" --agent codex 2>&1)"
case "$INST_OUT" in *"/hooks"*) ok "installer: tells Codex users that new project hooks must be reviewed and trusted (/hooks)";; *) fail "installer: tells Codex users that new project hooks must be reviewed and trusted (/hooks)";; esac
new_repo agent-eq-repo
sh "$KIT_DIR/install.sh" --agent=codex >/dev/null 2>&1
[ -f .codex/hooks.json ] && [ ! -e .claude/settings.json ] && ok "installer: --agent=codex (with an equals sign) works like --agent codex" \
  || fail "installer: --agent=codex (with an equals sign) works like --agent codex"
new_repo agent-bad-repo
sh "$KIT_DIR/install.sh" --agent vim >/dev/null 2>&1; BAD_RC=$?
[ "$BAD_RC" -ne 0 ] && ok "installer: an unknown --agent value is an error" || fail "installer: an unknown --agent value is an error"

if command -v jq >/dev/null 2>&1; then
  new_repo codex-merge-repo
  mkdir .codex
  printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]},"description":"mine"}' > .codex/hooks.json
  sh "$KIT_DIR/install.sh" --agent codex >/dev/null 2>&1
  jq -e '(.description == "mine") and (.hooks.Stop | length == 2) and (.hooks.PreToolUse | length == 1) and (.hooks.Stop[0].hooks[0].command == "echo mine")' .codex/hooks.json >/dev/null 2>&1 \
    && ok "installer: merges into an existing .codex/hooks.json and keeps foreign entries" \
    || fail "installer: merges into an existing .codex/hooks.json and keeps foreign entries"
  cp .codex/hooks.json "$WORK/codex-hooks.after1"
  sh "$KIT_DIR/install.sh" --agent codex >/dev/null 2>&1
  cmp -s .codex/hooks.json "$WORK/codex-hooks.after1" && ok "installer: a rerun leaves .codex/hooks.json unchanged" || fail "installer: a rerun leaves .codex/hooks.json unchanged"
fi

# doctor: Codex part ("installed", never "trusted")
new_repo codex-doctor-repo
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
git config core.hooksPath .githooks
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
case "$DOC_OUT" in *"Codex Stop hook is configured"*"Codex Bash guard"*) ok "doctor: reports the Codex Stop hook and Bash guard as configured";; *) fail "doctor: reports the Codex Stop hook and Bash guard as configured";; esac
case "$DOC_OUT" in *"Codex"*"trust"*) ok "doctor: says that Codex hook trust is not verified";; *) fail "doctor: says that Codex hook trust is not verified";; esac
[ "$DOC_RC" -eq 0 ] && ok "doctor: a complete both-agent install passes (exit 0)" || fail "doctor: a complete both-agent install passes (exit $DOC_RC)"
rm .codex/hooks.json
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
case "$DOC_OUT" in *"WARN"*"Codex hooks"*) ok "doctor: missing Codex hooks are a warning (a Claude-only install is legitimate)";; *) fail "doctor: missing Codex hooks are a warning";; esac
[ "$DOC_RC" -eq 0 ] && ok "doctor: ...and not a failure" || fail "doctor: ...and not a failure (exit $DOC_RC)"
mkdir -p .codex; printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"echo mine"}]}]}}' > .codex/hooks.json
DOC_OUT="$(sh "$KIT_DIR/install.sh" doctor 2>&1)"; DOC_RC=$?
[ "$DOC_RC" -ne 0 ] && ok "doctor: a .codex/hooks.json without our Stop gate is a problem" || fail "doctor: a .codex/hooks.json without our Stop gate is a problem"

# The hook contract with Codex-shaped input: Stop prints nothing on stdout (Codex wants JSON or nothing), exit 2 + stderr blocks.
new_repo codex-contract-repo
mkdir .slickrails; cp "$KIT_DIR/templates/session-check.sh" "$KIT_DIR/templates/bash-guard.sh" .slickrails/
printf 'CHECK_TEST="sh ./t.sh"\n' > .slickrails/config.sh
printf 'exit 0\n' > t.sh
git add -A && git commit -qm base
CX_STOP="{\"session_id\":\"s\",\"turn_id\":\"t\",\"transcript_path\":null,\"cwd\":\"$PWD\",\"hook_event_name\":\"Stop\",\"model\":\"m\",\"permission_mode\":\"default\",\"stop_hook_active\":false,\"last_assistant_message\":\"ok\"}"
cx_stop() { printf '%s' "$CX_STOP" | sh .slickrails/session-check.sh >"$WORK/cx.out" 2>"$WORK/cx.err"; CX_RC=$?; }
printf 'dirty\n' > cx-dirty.txt
cx_stop
[ "$CX_RC" -eq 0 ] && [ ! -s "$WORK/cx.out" ] && ok "codex contract: Stop on green checks exits 0 and prints nothing on stdout" \
  || fail "codex contract: Stop on green checks exits 0 and prints nothing on stdout (exit $CX_RC, stdout: $(head -c 80 "$WORK/cx.out"))"
printf 'exit 1\n' > t.sh
cx_stop
[ "$CX_RC" -eq 2 ] && [ ! -s "$WORK/cx.out" ] && [ -s "$WORK/cx.err" ] && ok "codex contract: Stop on red checks exits 2 with the reason on stderr and nothing on stdout" \
  || fail "codex contract: Stop on red checks exits 2 with the reason on stderr and nothing on stdout (exit $CX_RC)"
cx_stop; cx_stop; cx_stop
[ "$CX_RC" -eq 0 ] && [ ! -s "$WORK/cx.out" ] && ok "codex contract: the block counter ends the session with nothing on stdout" \
  || fail "codex contract: the block counter ends the session with nothing on stdout (exit $CX_RC)"
CX_PRE() { printf '{"session_id":"s","turn_id":"t","transcript_path":null,"cwd":"%s","hook_event_name":"PreToolUse","model":"m","permission_mode":"default","tool_name":"Bash","tool_use_id":"u","tool_input":{"command":"%s"}}' "$PWD" "$1" | sh .slickrails/bash-guard.sh >"$WORK/cx.out" 2>"$WORK/cx.err"; CX_RC=$?; }
CX_PRE 'git commit --no-verify -m x'
[ "$CX_RC" -eq 2 ] && [ ! -s "$WORK/cx.out" ] && [ -s "$WORK/cx.err" ] && ok "codex contract: PreToolUse blocks git commit --no-verify with exit 2, reason on stderr, nothing on stdout" \
  || fail "codex contract: PreToolUse blocks git commit --no-verify (exit $CX_RC)"
CX_PRE 'git status'
[ "$CX_RC" -eq 0 ] && [ ! -s "$WORK/cx.out" ] && ok "codex contract: PreToolUse lets git status through without output" || fail "codex contract: PreToolUse lets git status through without output (exit $CX_RC)"

# The hook COMMAND STRINGS of both templates are executed as the agents would (sh -c), not just inspected:
# from the repo root, from a subdirectory, and in a repo whose path contains spaces (self-review of 99819a9).
if command -v jq >/dev/null 2>&1; then
  hook_cmd() { jq -r "$2" "$KIT_DIR/templates/$1"; }
  CX_STOP_CMD="$(hook_cmd codex-hooks.json '.hooks.Stop[0].hooks[0].command')"
  CX_GUARD_CMD="$(hook_cmd codex-hooks.json '.hooks.PreToolUse[0].hooks[0].command')"
  CL_STOP_CMD="$(hook_cmd claude-settings.json '.hooks.Stop[0].hooks[0].command')"
  CL_GUARD_CMD="$(hook_cmd claude-settings.json '.hooks.PreToolUse[0].hooks[0].command')"
  cmd_case() { # <description> <command> <dir> <stdin-json> <want-exit>
    ( cd "$3" && printf '%s' "$4" | CLAUDE_PROJECT_DIR="$CMD_ROOT" sh -c "$2" >/dev/null 2>&1 ); CMD_RC=$?
    if [ "$CMD_RC" -eq "$5" ]; then ok "hook command: $1"; else fail "hook command: $1 (exit $CMD_RC, wanted $5)"; fi
  }
  for CMD_REPO in "cmd-repo" "cmd repo with spaces"; do
    new_repo "$CMD_REPO"
    CMD_ROOT="$PWD"
    mkdir .slickrails sub; cp "$KIT_DIR/templates/session-check.sh" "$KIT_DIR/templates/bash-guard.sh" .slickrails/
    printf 'CHECK_TEST="sh ./t.sh"\n' > .slickrails/config.sh
    printf 'exit 1\n' > t.sh
    git add -A && git commit -qm base
    printf 'dirty\n' > cmd-dirty.txt
    STOP_IN='{"hook_event_name":"Stop","stop_hook_active":false}'
    BYPASS_IN='{"tool_name":"Bash","tool_input":{"command":"git commit --no-verify -m x"}}'
    FINE_IN='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
    cmd_case "Codex Stop command blocks red checks from the repo root [$CMD_REPO]"      "$CX_STOP_CMD" "$CMD_ROOT" "$STOP_IN" 2
    cmd_case "Codex Stop command blocks red checks from a subdirectory [$CMD_REPO]"     "$CX_STOP_CMD" "$CMD_ROOT/sub" "$STOP_IN" 2
    cmd_case "Claude Stop command blocks red checks [$CMD_REPO]"                       "$CL_STOP_CMD" "$CMD_ROOT" "$STOP_IN" 2
    cmd_case "Codex Bash guard command blocks --no-verify from a subdirectory [$CMD_REPO]" "$CX_GUARD_CMD" "$CMD_ROOT/sub" "$BYPASS_IN" 2
    cmd_case "Claude Bash guard command blocks --no-verify [$CMD_REPO]"                "$CL_GUARD_CMD" "$CMD_ROOT" "$BYPASS_IN" 2
    cmd_case "Codex Bash guard command lets git status through [$CMD_REPO]"            "$CX_GUARD_CMD" "$CMD_ROOT" "$FINE_IN" 0
  done
fi

# ---- local gate (core idea of kunchenguid/no-mistakes, without daemon/TUI/agent pipeline) -----------------------
# `slickrails gate init` adds a `gate` remote that is a local bare repo with a pre-receive hook: the PUSHED commit is
# checked out into a disposable worktree, checked with the project's own config, and forwarded to the real remote
# only when green. Everything here runs offline against local bare repositories.
GATE_SH="$KIT_DIR/templates/gate.sh"
gate_repo() { # <name> [config lines...]: repo + bare origin, green base on main pushed, gate initialized
  GR="$1"; shift
  new_repo "$GR"
  git init -q --bare "$WORK/$GR-origin.git"
  git remote add origin "$WORK/$GR-origin.git"
  mkdir .slickrails
  printf 'CHECK_TEST="sh ./t.sh"\n' > .slickrails/config.sh
  for L in "$@"; do printf '%s\n' "$L" >> .slickrails/config.sh; done
  printf 'exit 0\n' > t.sh
  git add -A && git commit -qm base
  git branch -M main
  git push -q origin main
  sh "$GATE_SH" init >"$WORK/gate-init.out" 2>&1
}
gate_push() { # <refspec...> -> GP_OUT, GP_RC
  GP_OUT="$(git push gate "$@" 2>&1)"; GP_RC=$?
}
origin_has() { git --git-dir="$WORK/$GR-origin.git" rev-parse -q --verify "$1" >/dev/null 2>&1; }

gate_repo gate-basic
[ "$(git remote get-url gate 2>/dev/null)" != "" ] && ok "gate init: adds a 'gate' remote" || fail "gate init: adds a 'gate' remote"
GATE_DIR_FOUND="$(git rev-parse --git-common-dir)/slickrails-gate.git"
[ -x "$GATE_DIR_FOUND/hooks/pre-receive" ] && ok "gate init: the gate repository has an executable pre-receive hook" || fail "gate init: the gate repository has an executable pre-receive hook"
# compared with what git itself reports as the push target (git on Windows stores /tmp/... as C:/Users/.../Temp/...)
GT_STORED="$(git -C "$GATE_DIR_FOUND" config slickrails.target)"
[ -n "$GT_STORED" ] && [ "$GT_STORED" = "$(git remote get-url --push origin)" ] \
  && ok "gate init: the real remote's URL is stored as the forwarding target" \
  || fail "gate init: the real remote's URL is stored as the forwarding target (stored '$GT_STORED', push URL '$(git remote get-url --push origin)')"
sh "$GATE_SH" init >/dev/null 2>&1
[ $? -eq 0 ] && ok "gate init: a second run is fine (idempotent)" || fail "gate init: a second run is fine (idempotent)"
sh "$GATE_SH" status 2>&1 | grep -q "gate-basic-origin.git" && ok "gate status: names the forwarding target" || fail "gate status: names the forwarding target"

git checkout -q -b feature
echo one > one.txt; git add one.txt; git commit -qm "green change"
gate_push feature
[ "$GP_RC" -eq 0 ] && origin_has refs/heads/feature && ok "gate: a green push is forwarded to the real remote" \
  || fail "gate: a green push is forwarded to the real remote (exit $GP_RC; $(printf '%s' "$GP_OUT" | tail -3 | tr '\n' ' '))"
case "$GP_OUT" in *"slickrails[gate]"*) ok "gate: the push output says what the gate did";; *) fail "gate: the push output says what the gate did";; esac

git checkout -q -b redbranch
printf 'echo failing-test-output; exit 1\n' > t.sh; git commit -qam "red change"
gate_push redbranch
if [ "$GP_RC" -ne 0 ] && ! origin_has refs/heads/redbranch; then ok "gate: a red push is rejected and never reaches the real remote"
else fail "gate: a red push is rejected and never reaches the real remote (exit $GP_RC)"; fi
case "$GP_OUT" in *failing-test-output*) ok "gate: the failing check's output is shown";; *) fail "gate: the failing check's output is shown";; esac

# the point of checking the PUSHED commit: the working copy does not matter in either direction
printf 'exit 0\n' > t.sh       # uncommitted fix of the red commit: the commit itself stays red
gate_push redbranch
if [ "$GP_RC" -ne 0 ] && ! origin_has refs/heads/redbranch; then ok "gate: a red commit is rejected even though the working copy is green"
else fail "gate: a red commit is rejected even though the working copy is green"; fi
git checkout -q -- t.sh
git checkout -q feature
printf 'exit 1\n' > t.sh; echo junk > untracked-junk.txt   # red AND dirty working copy
git branch -q greencopy feature
gate_push greencopy
if [ "$GP_RC" -eq 0 ] && origin_has refs/heads/greencopy; then ok "gate: a green commit is forwarded even with a red, dirty working copy"
else fail "gate: a green commit is forwarded even with a red, dirty working copy (exit $GP_RC)"; fi
git checkout -q -- t.sh; rm -f untracked-junk.txt

git tag release-1 feature
gate_push release-1
[ "$GP_RC" -eq 0 ] && origin_has refs/tags/release-1 && ok "gate: a tag is forwarded (with a note, without checks)" || fail "gate: a tag is forwarded (exit $GP_RC)"
gate_push :greencopy
[ "$GP_RC" -eq 0 ] && ! origin_has refs/heads/greencopy && ok "gate: deleting a branch is forwarded" || fail "gate: deleting a branch is forwarded (exit $GP_RC)"
git update-ref refs/notes/x "$(git rev-parse HEAD)"
gate_push refs/notes/x
[ "$GP_RC" -ne 0 ] && ok "gate: refs other than branches and tags are refused" || fail "gate: refs other than branches and tags are refused"

# what the pushed commit's own config can ask for: setup command, linked dependency dirs, a deadline
gate_repo gate-setup 'CHECK_GATE_SETUP="touch setup-ran"' 'GATE_LINK_DIRS="deps"'
mkdir -p deps; echo marker > deps/marker.txt
printf 'test -f setup-ran && test -f deps/marker.txt\n' > t.sh
git add t.sh; git commit -qm "needs setup and deps"
git checkout -q -b needs-setup
gate_push needs-setup
[ "$GP_RC" -eq 0 ] && ok "gate: CHECK_GATE_SETUP runs and GATE_LINK_DIRS makes dependency directories available in the worktree" \
  || fail "gate: CHECK_GATE_SETUP runs and GATE_LINK_DIRS makes dependency directories available (exit $GP_RC; $(printf '%s' "$GP_OUT" | tail -3 | tr '\n' ' '))"

gate_repo gate-slow 'CHECK_TEST="sleep 20"'
git -C "$(git rev-parse --git-common-dir)/slickrails-gate.git" config slickrails.timeout 1
git checkout -q -b slow-branch; echo s > s.txt; git add s.txt; git commit -qm slow
GATE_T0="$(date +%s)"
gate_push slow-branch
GATE_SECS=$(( $(date +%s) - GATE_T0 ))
if [ "$GP_RC" -ne 0 ] && [ "$GATE_SECS" -lt 10 ]; then ok "gate: a check over the gate timeout is stopped and the push rejected (${GATE_SECS}s)"
else fail "gate: a check over the gate timeout is stopped and the push rejected (exit $GP_RC after ${GATE_SECS}s)"; fi
case "$GP_OUT" in *"timed out"*) ok "gate: the timeout is named";; *) fail "gate: the timeout is named";; esac

gate_repo gate-nocfg
git rm -q -r --cached .slickrails >/dev/null 2>&1; rm -rf .slickrails; git commit -qm "no config" >/dev/null 2>&1
git checkout -q -b nocfg-branch; echo n > n.txt; git add n.txt; git commit -qm n
gate_push nocfg-branch
if [ "$GP_RC" -eq 0 ]; then case "$GP_OUT" in *"nothing to check"*) ok "gate: a pushed commit without .slickrails/config.sh passes, loudly";; *) fail "gate: ...passes, loudly";; esac
else fail "gate: a pushed commit without .slickrails/config.sh passes (exit $GP_RC)"; fi

# the real remote can still refuse: that is reported as a rejection of the gate push
gate_repo gate-fwd
printf '#!/bin/sh\necho "origin says no" >&2\nexit 1\n' > "$WORK/gate-fwd-origin.git/hooks/pre-receive"; chmod +x "$WORK/gate-fwd-origin.git/hooks/pre-receive"
git checkout -q -b fwd-branch; echo f > f.txt; git add f.txt; git commit -qm f
gate_push fwd-branch
if [ "$GP_RC" -ne 0 ]; then case "$GP_OUT" in *"origin says no"*|*"forward"*) ok "gate: a refusal by the real remote rejects the gate push and is shown";; *) fail "gate: a refusal by the real remote is shown";; esac
else fail "gate: a refusal by the real remote rejects the gate push (exit 0)"; fi

# AI review in the gate (opt-in via CHECK_PREPUSH_REVIEW), with a stub reviewer
gate_repo gate-review 'CHECK_PREPUSH_REVIEW="1"'
cp "$KIT_DIR/templates/ai-review.sh" .slickrails/ai-review.sh
git add -A; git commit -qm "review script"; git push -q origin main
git checkout -q -b rv-fail; echo r > r.txt; git add r.txt; git commit -qm r
mkdir -p "$WORK/gate-stub"
printf '#!/bin/sh\ncat >/dev/null\nprintf "VERDICT: FAIL\\nr.txt:1 — [high] — bad — scenario\\n"\n' > "$WORK/gate-stub/claude"; chmod +x "$WORK/gate-stub/claude"
GP_OUT="$(PATH="$WORK/gate-stub:$PATH" git push gate rv-fail 2>&1)"; GP_RC=$?
if [ "$GP_RC" -ne 0 ] && ! origin_has refs/heads/rv-fail; then ok "gate: a FAIL verdict of the AI review rejects the push"
else fail "gate: a FAIL verdict of the AI review rejects the push (exit $GP_RC; $(printf '%s' "$GP_OUT" | tail -3 | tr '\n' ' '))"; fi
case "$GP_OUT" in *"against $(git --git-dir="$WORK/gate-review-origin.git" rev-parse refs/heads/main)"*) ok "gate: the AI review diffs against the tip of the branch on the real remote";; *) fail "gate: the AI review diffs against the tip of the real remote's branch (no base named in the output)";; esac
printf '#!/bin/sh\ncat >/dev/null\necho "VERDICT: PASS"\n' > "$WORK/gate-stub/claude"
git checkout -q -b rv-pass main; echo p > p.txt; git add p.txt; git commit -qm p
GP_OUT="$(PATH="$WORK/gate-stub:$PATH" git push gate rv-pass 2>&1)"; GP_RC=$?
[ "$GP_RC" -eq 0 ] && origin_has refs/heads/rv-pass && ok "gate: a PASS verdict lets the push through" || fail "gate: a PASS verdict lets the push through (exit $GP_RC)"
printf '#!/bin/sh\ncat >/dev/null\nexit 17\n' > "$WORK/gate-stub/claude"
git checkout -q -b rv-err main; echo e > e.txt; git add e.txt; git commit -qm e
GP_OUT="$(PATH="$WORK/gate-stub:$PATH" git push gate rv-err 2>&1)"; GP_RC=$?
if [ "$GP_RC" -eq 0 ]; then case "$GP_OUT" in *ERROR*) ok "gate: an unreviewable push (ERROR) goes through and says so";; *) fail "gate: an unreviewable push goes through and says so";; esac
else fail "gate: an unreviewable push (REVIEW_ON_ERROR=warn) goes through (exit $GP_RC)"; fi

# the real remote's HEAD may point at a branch that does not exist (a bare repo made with init.defaultBranch=master that
# only ever received `main`: GitHub's runners do exactly that). The review must still find its base, and when it truly
# cannot, the push output has to say that the review was skipped — not pass silently as if it had been reviewed.
gate_repo gate-review-head 'CHECK_PREPUSH_REVIEW="1"'
cp "$KIT_DIR/templates/ai-review.sh" .slickrails/ai-review.sh
git add -A; git commit -qm "review script"; git push -q origin main
git --git-dir="$WORK/gate-review-head-origin.git" symbolic-ref HEAD refs/heads/does-not-exist
printf '#!/bin/sh\ncat >/dev/null\nprintf "VERDICT: FAIL\\nr.txt:1 — [high] — bad — scenario\\n"\n' > "$WORK/gate-stub/claude"; chmod +x "$WORK/gate-stub/claude"
git checkout -q -b rvh-fail; echo r > r.txt; git add r.txt; git commit -qm r
GP_OUT="$(PATH="$WORK/gate-stub:$PATH" git push gate rvh-fail 2>&1)"; GP_RC=$?
if [ "$GP_RC" -ne 0 ] && ! origin_has refs/heads/rvh-fail; then ok "gate: with the remote's HEAD pointing nowhere the review still runs against main (FAIL rejects)"
else fail "gate: with the remote's HEAD pointing nowhere the review still runs against main (exit $GP_RC)"; fi
# no base anywhere: the remote has neither the branch, nor a HEAD target, nor main/master
gate_repo gate-review-nobase 'CHECK_PREPUSH_REVIEW="1"'
cp "$KIT_DIR/templates/ai-review.sh" .slickrails/ai-review.sh
git add -A; git commit -qm "review script"
git --git-dir="$WORK/gate-review-nobase-origin.git" symbolic-ref HEAD refs/heads/does-not-exist
git push -q origin main:trunk; git push -q origin --delete main
git checkout -q -b rvn; echo n > n.txt; git add n.txt; git commit -qm n
GP_OUT="$(PATH="$WORK/gate-stub:$PATH" git push gate rvn 2>&1)"; GP_RC=$?
case "$GP_OUT" in *"skipping"*) ok "gate: a review skipped for lack of a base says so in the push output";;
  *) fail "gate: a review skipped for lack of a base says so in the push output (exit $GP_RC; nothing about the review)";; esac

# --- gate, round 2 (Codex review and self-review of f5bea27) -------------------------------------------------
# several refs in one push: all checked first, then forwarded together — or nothing at all
gate_repo gate-multi
git checkout -q -b good; echo g > g.txt; git add g.txt; git commit -qm good
git checkout -q main; git checkout -q -b bad; printf 'exit 1\n' > t.sh; git commit -qam bad
GP_OUT="$(git push gate good bad 2>&1)"; GP_RC=$?
if [ "$GP_RC" -ne 0 ] && ! origin_has refs/heads/good && ! origin_has refs/heads/bad; then ok "gate: one red ref in a multi-ref push means NOTHING reaches the real remote (not even the green ref)"
else fail "gate: one red ref in a multi-ref push means nothing reaches the real remote (exit $GP_RC, good on origin: $(origin_has refs/heads/good && echo yes || echo no))"; fi
GP_OUT="$(git push gate bad good 2>&1)"; GP_RC=$?
if [ "$GP_RC" -ne 0 ] && ! origin_has refs/heads/good; then ok "gate: ...whatever the order of the refs"; else fail "gate: ...whatever the order of the refs"; fi
git checkout -q main; git checkout -q -b good2; echo g2 > g2.txt; git add g2.txt; git commit -qm good2
GP_OUT="$(git push gate good good2 2>&1)"; GP_RC=$?
if [ "$GP_RC" -eq 0 ] && origin_has refs/heads/good && origin_has refs/heads/good2; then ok "gate: two green refs are forwarded together"
else fail "gate: two green refs are forwarded together (exit $GP_RC; $(printf '%s' "$GP_OUT" | tail -3 | tr '\n' ' '))"; fi

# the real push destination: remote.<name>.pushurl, not the fetch url (several push urls: refuse)
gate_repo gate-pushurl
git init -q --bare "$WORK/gate-pushurl-dest.git"
git remote set-url --push origin "$WORK/gate-pushurl-dest.git"
sh "$GATE_SH" init >/dev/null 2>&1
git checkout -q -b pu; echo p > p.txt; git add p.txt; git commit -qm pu
gate_push pu
if [ "$GP_RC" -eq 0 ] && git --git-dir="$WORK/gate-pushurl-dest.git" rev-parse -q --verify refs/heads/pu >/dev/null 2>&1 && ! origin_has refs/heads/pu; then ok "gate init: forwards to the push URL of the remote, not its fetch URL"
else fail "gate init: forwards to the push URL of the remote, not its fetch URL (exit $GP_RC)"; fi
git remote set-url --add --push origin "$WORK/gate-pushurl-other.git"
sh "$GATE_SH" init >/dev/null 2>&1; [ $? -ne 0 ] && ok "gate init: several push URLs are refused (the gate forwards to exactly one place)" || fail "gate init: several push URLs are refused"

# a hung check must end the push in time, including grandchildren that hold the connection to the pusher open
gate_repo gate-tree "CHECK_TEST=\"sh -c 'sleep $TAG_C' ; sleep $TAG_C\""
git -C "$(git rev-parse --git-common-dir)/slickrails-gate.git" config slickrails.timeout 1
git checkout -q -b tree-branch; echo t > t2.txt; git add t2.txt; git commit -qm tree
T_START="$(date +%s)"
gate_push tree-branch
T_SECS=$(( $(date +%s) - T_START ))
if [ "$GP_RC" -ne 0 ] && [ "$T_SECS" -le 8 ]; then ok "gate: a timed-out check with a grandchild still ends the push promptly (${T_SECS}s)"
else fail "gate: a timed-out check with a grandchild still ends the push promptly (exit $GP_RC after ${T_SECS}s)"; fi
# an unusable ps is a failure here, never an empty (and therefore "clean") process list
if PS_LIST="$(ps_commands 2>/dev/null)" && [ -n "$PS_LIST" ]; then
  [ "$(printf '%s\n' "$PS_LIST" | grep -c "[s]leep $TAG_C")" = "0" ] && ok "gate: ...and leaves no process behind" || { fail "gate: ...and leaves no process behind"; pkill -9 -f "sleep $TAG_C" 2>/dev/null; }
else fail "gate: ...and leaves no process behind (ps is not usable here, so this cannot be checked)"; fi

# the gate stops hung checks by walking the process tree with `ps`; where ps is unusable (a locked-down sandbox, the Codex
# review automation) it must say so and refuse the push, not run checks it could not stop
gate_repo gate-no-ps
mkdir -p "$WORK/gate-no-ps-bin"
printf '#!/bin/sh\necho "ps: Operation not permitted" >&2\nexit 1\n' > "$WORK/gate-no-ps-bin/ps"; chmod +x "$WORK/gate-no-ps-bin/ps"
git checkout -q -b noprs-branch; echo n > np.txt; git add np.txt; git commit -qm np
GP_OUT="$(PATH="$WORK/gate-no-ps-bin:$PATH" git push gate noprs-branch 2>&1)"; GP_RC=$?
if [ "$GP_RC" -ne 0 ] && ! origin_has refs/heads/noprs-branch; then case "$GP_OUT" in *"needs 'ps'"*) ok "gate: without a usable ps the push is refused and the message names ps";; *) fail "gate: without a usable ps the push is refused and the message names ps (no mention of ps)";; esac
else fail "gate: without a usable ps the push is refused (exit $GP_RC, on origin: $(origin_has refs/heads/noprs-branch && echo yes || echo no))"; fi
# ...also when ps prints something and then fails (a truncated list is as useless as none)
printf '#!/bin/sh\necho "123 1"\necho "ps: Operation not permitted" >&2\nexit 1\n' > "$WORK/gate-no-ps-bin/ps"; chmod +x "$WORK/gate-no-ps-bin/ps"
git checkout -q main; git checkout -q -b noprs2-branch; echo n2 > np2.txt; git add np2.txt; git commit -qm np2
GP_OUT="$(PATH="$WORK/gate-no-ps-bin:$PATH" git push gate noprs2-branch 2>&1)"; GP_RC=$?
if [ "$GP_RC" -ne 0 ] && ! origin_has refs/heads/noprs2-branch; then ok "gate: a ps that prints a partial list and then fails also refuses the push"
else fail "gate: a ps that prints a partial list and then fails also refuses the push (exit $GP_RC, on origin: $(origin_has refs/heads/noprs2-branch && echo yes || echo no))"; fi
# ...but the ps of Git Bash (no -A/-o, `ps -e` in its own format) is usable: green pushes go through and a hung
# check with a grandchild is still stopped in time
make_msys_ps "$WORK/msysps"
gate_repo gate-msys "CHECK_TEST=\"sh -c 'sleep $TAG_E' ; sleep $TAG_E\""
git -C "$(git rev-parse --git-common-dir)/slickrails-gate.git" config slickrails.timeout 1
git checkout -q -b msys-hung; echo h > h.txt; git add h.txt; git commit -qm h
T_START="$(date +%s)"
GP_OUT="$(PATH="$WORK/msysps:$PATH" git push gate msys-hung 2>&1)"; GP_RC=$?
T_SECS=$(( $(date +%s) - T_START ))
if [ "$GP_RC" -ne 0 ] && [ "$T_SECS" -le 8 ] && ! origin_has refs/heads/msys-hung && [ "$(running "[s]leep $TAG_E")" = "0" ]; then
  ok "gate: with a Git Bash style ps a hung check and its grandchild are stopped in time (${T_SECS}s)"
else fail "gate: with a Git Bash style ps a hung check and its grandchild are stopped in time (exit $GP_RC after ${T_SECS}s, left: $(running "[s]leep $TAG_E"); $(printf '%s' "$GP_OUT" | tail -2 | tr '\n' ' '))"; pkill -9 -f "sleep $TAG_E" 2>/dev/null; fi
printf 'CHECK_TEST="true"\n' > .slickrails/config.sh; git commit -qam "green checks"
# the 1-second limit was for the hung check only: on a slow Windows runner, creating the gate's worktree alone can take
# longer, and the green push was then declined as timed out (failed 2 of 3 runs on GitHub's windows-latest)
git -C "$(git rev-parse --git-common-dir)/slickrails-gate.git" config --unset slickrails.timeout
git checkout -q -b msys-green; echo g > g.txt; git add g.txt; git commit -qm g
GP_OUT="$(PATH="$WORK/msysps:$PATH" git push gate msys-green 2>&1)"; GP_RC=$?
[ "$GP_RC" -eq 0 ] && origin_has refs/heads/msys-green && ok "gate: with a Git Bash style ps a green push is forwarded" \
  || fail "gate: with a Git Bash style ps a green push is forwarded (exit $GP_RC; $(printf '%s' "$GP_OUT" | grep -v '^remote: *$' | tail -6 | tr '\n' ' '))"

# what a pushed commit may ask of the gate
gate_repo gate-safety 'GATE_LINK_DIRS="../escape ok-dir"'
mkdir -p ok-dir "$WORK/gate-escape-target"; echo m > ok-dir/m.txt
printf 'test -f ok-dir/m.txt && test ! -e ../escape\n' > t.sh
git add t.sh; git commit -qm "link dirs"; git push -q origin main
git checkout -q -b safe-branch; echo s > s.txt; git add s.txt; git commit -qm s
gate_push safe-branch
[ "$GP_RC" -eq 0 ] && ok "gate: GATE_LINK_DIRS links a relative directory but ignores a path that leaves the worktree" \
  || fail "gate: GATE_LINK_DIRS links a relative directory but ignores a path that leaves the worktree (exit $GP_RC; $(printf '%s' "$GP_OUT" | tail -3 | tr '\n' ' '))"
gate_repo gate-symlink
mv .slickrails/config.sh "$WORK/outside-config.sh"; ln -s "$WORK/outside-config.sh" .slickrails/config.sh
git add -A; git commit -qm "symlinked config"
git checkout -q -b symlink-branch; echo y > y.txt; git add y.txt; git commit -qm y
gate_push symlink-branch
if [ "$GP_RC" -ne 0 ]; then case "$GP_OUT" in *symlink*) ok "gate: a config.sh that is a symlink is refused";; *) fail "gate: a config.sh that is a symlink is refused (no mention of the symlink)";; esac
else fail "gate: a config.sh that is a symlink is refused (exit 0)"; fi

# a network failure is not a refusal
gate_repo gate-net
git -C "$(git rev-parse --git-common-dir)/slickrails-gate.git" config slickrails.target "$WORK/does-not-exist.git"
git checkout -q -b net-branch; echo n > n2.txt; git add n2.txt; git commit -qm n
gate_push net-branch
if [ "$GP_RC" -ne 0 ]; then case "$GP_OUT" in *"refused, unreachable or timed out"*) ok "gate: a forward failure says 'refused, unreachable or timed out' instead of claiming a refusal";; *) fail "gate: a forward failure is not described as a plain refusal";; esac
else fail "gate: forwarding to a missing target must fail (exit 0)"; fi

# a repository with another object format (sha256) gets a gate repository of the same format
if git init -q --object-format=sha256 "$WORK/sha256-probe" >/dev/null 2>&1; then
  rm -rf "$WORK/gate-sha256" "$WORK/gate-sha256-origin.git"
  git init -q --object-format=sha256 --bare "$WORK/gate-sha256-origin.git"
  git init -q --object-format=sha256 -b main "$WORK/gate-sha256"; cd "$WORK/gate-sha256" || exit 1
  git config user.email t@t; git config user.name t; git remote add origin "$WORK/gate-sha256-origin.git"
  mkdir .slickrails; printf 'CHECK_TEST="true"\n' > .slickrails/config.sh; git add -A; git commit -qm base
  sh "$GATE_SH" init >/dev/null 2>&1
  git push gate main >"$WORK/sha256.out" 2>&1
  [ $? -eq 0 ] && git --git-dir="$WORK/gate-sha256-origin.git" rev-parse -q --verify refs/heads/main >/dev/null 2>&1 \
    && ok "gate init: a sha256 repository gets a sha256 gate and its push goes through" \
    || fail "gate init: a sha256 repository gets a sha256 gate and its push goes through ($(tail -2 "$WORK/sha256.out" | tr '\n' ' '))"
fi

# ai-review.sh takes its base from SLICKRAILS_REVIEW_BASE when the gate passes one
printf 'ai-review base override: '
new_repo base-override-repo
mkdir .slickrails; cp "$KIT_DIR/templates/ai-review.sh" .slickrails/
echo a > a.txt; git add -A; git commit -qm a; BASE_A="$(git rev-parse HEAD)"
echo b > b.txt; git add -A; git commit -qm b
printf '#!/bin/sh\ncat >/dev/null\necho "VERDICT: PASS"\n' > "$WORK/gate-stub/claude"
BASE_OUT="$(PATH="$WORK/gate-stub:$PATH" SLICKRAILS_REVIEW_BASE="$BASE_A" sh .slickrails/ai-review.sh 2>&1)"
case "$BASE_OUT" in *"against $BASE_A"*) ok "ai-review: SLICKRAILS_REVIEW_BASE selects the base of the diff";; *) fail "ai-review: SLICKRAILS_REVIEW_BASE selects the base of the diff ($(printf '%s' "$BASE_OUT" | head -2 | tr '\n' ' '))";; esac

# gate remove
gate_repo gate-remove
sh "$GATE_SH" remove >/dev/null 2>&1
if ! git remote get-url gate >/dev/null 2>&1 && [ ! -d "$(git rev-parse --git-common-dir)/slickrails-gate.git" ]; then ok "gate remove: removes the remote and the gate repository"
else fail "gate remove: removes the remote and the gate repository"; fi
new_repo gate-noremote-repo
sh "$GATE_SH" init >/dev/null 2>&1; [ $? -ne 0 ] && ok "gate init: without a real remote it is an error" || fail "gate init: without a real remote it is an error"

# ---- the kit's own repo uses its own standard: its copies must not drift from the templates ---------------------
# (an outdated .githooks/pre-push without the pushed-SHA guard was found by the overall Codex review)
DOG_BAD=""
for PAIR in hooks/pre-commit:.githooks/pre-commit hooks/pre-push:.githooks/pre-push hooks/commit-msg:.githooks/commit-msg \
            hooks/post-merge:.githooks/post-merge session-check.sh:.slickrails/session-check.sh \
            ai-review.sh:.slickrails/ai-review.sh bash-guard.sh:.slickrails/bash-guard.sh dep-check.sh:.slickrails/dep-check.sh claude-settings.json:.claude/settings.json \
            codex-hooks.json:.codex/hooks.json; do
  DOG_SRC="${PAIR%%:*}"; DOG_DST="${PAIR#*:}"
  cmp -s "$KIT_DIR/templates/$DOG_SRC" "$KIT_DIR/$DOG_DST" || DOG_BAD="$DOG_BAD $DOG_DST"
done
[ -z "$DOG_BAD" ] && ok "dogfood: the repo's own hooks, scripts and Claude settings equal the templates" \
  || fail "dogfood: the repo's own hooks, scripts and Claude settings equal the templates (differ:$DOG_BAD)"

# ---- opt-in deep security workflow: how the third-party action is used ----------------------------------------
# (checked against anthropics/claude-code-security-review's action.yml: it scans only the FIRST commit of a PR
# unless run-every-commit is true, has no tags, and has no fork-PR check of its own)
SRW="$KIT_DIR/templates/workflows/security-review-ai.yml"
grep -Eq 'uses: anthropics/claude-code-security-review@[0-9a-f]{40}( |$)' "$SRW" \
  && ok "security-review-ai.yml: the third-party action is pinned to a commit SHA" \
  || fail "security-review-ai.yml: the third-party action is pinned to a commit SHA"
grep -q 'claude-code-security-review@main' "$SRW" \
  && fail "security-review-ai.yml: no moving @main reference" || ok "security-review-ai.yml: no moving @main reference"
grep -Eq '^[[:space:]]+run-every-commit:[[:space:]]*"?true"?[[:space:]]*$' "$SRW" \
  && ok "security-review-ai.yml: every commit of a PR is scanned (run-every-commit)" \
  || fail "security-review-ai.yml: every commit of a PR is scanned (run-every-commit)"
grep -q 'github.event.pull_request.head.repo.full_name == github.repository' "$SRW" \
  && ok "security-review-ai.yml: fork PRs are skipped" || fail "security-review-ai.yml: fork PRs are skipped"
# gitleaks-action lists a pull request's commits through the API; without pull-requests: read it fails on every PR (403)
for F in templates/workflows/security.yml .github/workflows/security.yml; do
  awk '/^  gitleaks:/{g=1} /^  [a-z]+:$/ && !/gitleaks/{g=0} g && /pull-requests: read/{f=1} END{exit !f}' "$KIT_DIR/$F" \
    && ok "$F: the gitleaks job may read pull requests (needed on PRs)" || fail "$F: the gitleaks job may read pull requests (needed on PRs)"
done
# a YAML parser: python3 with PyYAML, else ruby (its standard library has one; GitHub's macOS runners lack PyYAML)
YAML_PARSE=""
if python3 -c 'import yaml' >/dev/null 2>&1; then YAML_PARSE="python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))'"
elif ruby -ryaml -e '' >/dev/null 2>&1; then YAML_PARSE="ruby -ryaml -e 'YAML.load_file(ARGV[0])'"; fi
if [ -n "$YAML_PARSE" ]; then
  YAML_BAD=""
  for WF in "$KIT_DIR"/templates/workflows/*.yml; do
    eval "$YAML_PARSE \"\$WF\"" >/dev/null 2>&1 || YAML_BAD="$YAML_BAD $(basename "$WF")"
  done
  [ -z "$YAML_BAD" ] && ok "workflow templates: every file is valid YAML" || fail "workflow templates: every file is valid YAML (broken:$YAML_BAD)"
else
  printf 'SKIP  workflow templates: no YAML parser (python3 with PyYAML, or ruby) — validity not checked\n'
fi

# ---- Node CI template: the package manager's downloads are cached, keyed by the lockfile ------------------------
# (every other stack template cached already; a cold install on every PR run is the classic slow CI)
NODE_CI="$KIT_DIR/templates/workflows/ci-node.yml"
grep -q 'uses: actions/cache@v4' "$NODE_CI" && grep -q "hashFiles('package-lock.json', 'pnpm-lock.yaml', 'yarn.lock', 'bun.lock', 'bun.lockb')" "$NODE_CI" \
  && grep -q '[~]/.npm' "$NODE_CI" && grep -q 'pnpm/store' "$NODE_CI" && grep -q 'bun/install/cache' "$NODE_CI" \
  && ok "ci-node.yml: caches npm/pnpm/yarn/bun downloads keyed by the lockfile" || fail "ci-node.yml: caches npm/pnpm/yarn/bun downloads keyed by the lockfile"

# ---- AI review in CI: a Claude subscription token works as well as an API key ------------------------------------
# (claude-code-action accepts claude_code_oauth_token from `claude setup-token`; the security-review action has no such input)
F=templates/workflows/claude-review.yml   # the template only: the kit repo itself reviews locally (no workflow copy)
grep -Eq 'claude_code_oauth_token:[[:space:]]*\$\{\{[[:space:]]*secrets\.CLAUDE_CODE_OAUTH_TOKEN' "$KIT_DIR/$F" \
  && grep -Eq 'anthropic_api_key:[[:space:]]*\$\{\{[[:space:]]*secrets\.ANTHROPIC_API_KEY' "$KIT_DIR/$F" \
  && ok "$F: accepts ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN" || fail "$F: accepts ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN"
grep -q 'claude_code_oauth_token' "$KIT_DIR/actions/claude-review/action.yml" \
  && grep -A3 '^  anthropic_api_key:' "$KIT_DIR/actions/claude-review/action.yml" | grep -q 'required: false' \
  && ok "composite action: API key optional, OAuth token input present" || fail "composite action: API key optional, OAuth token input present"
grep -q 'CLAUDE_CODE_OAUTH_TOKEN' "$KIT_DIR/install.sh" && ok "installer next steps name the subscription token" || fail "installer next steps name the subscription token"
# without the Claude GitHub App the action fails ("Claude Code is not installed on this repository"), secret or not —
# seen on this repo's own first PR. Everyone who sets up the review has to be told.
for F in install.sh templates/workflows/claude-review.yml README.md README.de.md; do
  grep -q 'github.com/apps/claude\|/install-github-app' "$KIT_DIR/$F" \
    && ok "$F: names the Claude GitHub App the review needs" || fail "$F: names the Claude GitHub App the review needs"
done

# ---- the pre-push hook must not hand git's hook environment (GIT_DIR) to the project's checks ----------------------
# (it did: a test suite run from pre-push in a linked worktree wrote into the real repository — core.bare=true,
# a test identity, test branches, and test pushes to the real remote)
new_repo leak-repo
printf '{"name":"t","scripts":{"test":"node -e \\"console.log(1)\\""}}' > package.json
sh "$KIT_DIR/install.sh" >/dev/null 2>&1
printf '\nCHECK_TEST="cd %s && rm -rf inner && git init -q inner && cd inner && git config user.name leak-probe && git config core.bare true"\n' "$WORK" >> .slickrails/config.sh
git add -A && git commit -qm "kit

Why: fixture.
What: installs the kit." --no-verify
git init -q --bare "$WORK/leak-remote.git"; git remote add origin "$WORK/leak-remote.git"
git worktree add -q -b leak-wt "$WORK/leak-wt" >/dev/null 2>&1
( cd "$WORK/leak-wt" && git push -q origin leak-wt >/dev/null 2>&1 )
LEAK_NAME="$(git config --local user.name 2>/dev/null || true)"; LEAK_BARE="$(git config --local core.bare)"
if [ "$LEAK_NAME" != "leak-probe" ] && [ "$LEAK_BARE" = "false" ] && [ -d "$WORK/inner/.git" ]; then
  ok "pre-push: checks run without git's hook environment (a check's own git repo stays its own)"
else fail "pre-push: checks run without git's hook environment (user.name=$LEAK_NAME, core.bare=$LEAK_BARE)"; fi

# ---- public hygiene: nothing from the maker's machine or work process in the tracked files ----------------------
# (a dossier once pointed at an untracked planning file; paths and mailbox names of one machine mean nothing to anyone else)
if git -C "$KIT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  HYG="$(git -C "$KIT_DIR" grep -nIE -e '/Users/[a-z]' -e '/home/[a-z]+/' -e 'PLAN-final' -e 'LOOP-STATE' -e 'slickrails-loop' -e 'Claude Area' -- . ':!tests/run.sh' 2>/dev/null | head -5)"
  [ -z "$HYG" ] && ok "hygiene: no personal paths or process files referenced in tracked files" \
    || fail "hygiene: no personal paths or process files referenced in tracked files ($(printf '%s' "$HYG" | head -2 | tr '\n' ' '))"
  # the maker's name belongs in LICENSE only (dossiers say "the maintainer"), the employer and private projects nowhere
  HYG3="$(git -C "$KIT_DIR" grep -nIiE -e 'Jonah' -e 'vetstage' -e 'okido' -e 'slick-ai' -- . ':!tests/run.sh' ':!LICENSE' ':!SECURITY.md' 2>/dev/null | head -5)"
  [ -z "$HYG3" ] && ok "hygiene: no personal names, employer or private projects in tracked files" \
    || fail "hygiene: no personal names, employer or private projects in tracked files ($(printf '%s' "$HYG3" | head -2 | tr '\n' ' '))"
  HYG2="$(git -C "$KIT_DIR" ls-files | grep -E '(^|/)(\.DS_Store|LOOP-STATE\.md|PLAN-final\.md|settings\.local\.json)$' | head -3)"
  [ -z "$HYG2" ] && ok "hygiene: no local state files are tracked" || fail "hygiene: no local state files are tracked ($HYG2)"
else
  printf 'SKIP  hygiene: the kit is not a git checkout\n'
fi

# --------------------------------------------- benchmark host check (stubs) ----
# tests/benchmark/host/claude-stop-timeout.sh must not call a failed measurement a confirmation.
# Offline: a stub `claude` decides what the "CLI" does; the real-host run stays behind BENCH_AI.

host_case() { # <description> <want-exit: 0|nonzero> <needle|!needle> <stub body>
  mkdir -p "$WORK/hoststub"
  printf '#!/bin/sh\ncase "$1" in --version) echo fake-claude; exit 0;; esac\n%s\n' "$4" > "$WORK/hoststub/claude"
  chmod +x "$WORK/hoststub/claude"
  HOST_OUT="$(PATH="$WORK/hoststub:$PATH" BENCH_AI=1 BENCH_HOST_TIMEOUT=3 sh "$KIT_DIR/tests/benchmark/host/claude-stop-timeout.sh" 2>&1)"; HOST_RC=$?
  case "$3" in
    '!'*) case "$HOST_OUT" in *"${3#!}"*) HIT=0;; *) HIT=1;; esac;;
    *)    case "$HOST_OUT" in *"$3"*) HIT=1;; *) HIT=0;; esac;;
  esac
  if [ "$2" = "0" ]; then [ "$HOST_RC" -eq 0 ] && RCOK=1 || RCOK=0; else [ "$HOST_RC" -ne 0 ] && RCOK=1 || RCOK=0; fi
  if [ "$RCOK" -eq 1 ] && [ "$HIT" -eq 1 ]; then ok "$1"; else fail "$1 (exit $HOST_RC; $(printf '%s' "$HOST_OUT" | tail -2 | tr '\n' ' '))"; fi
}

HOST_SETTINGS='case "$(cat .claude/settings.json)" in *ctl.sh*) printf "x\nx\nx\n" > ctl;; *) echo x > calls;; esac'
host_case "host check: a CLI that works and ignores the timed-out hook confirms fail-open" 0 "FAIL-OPEN CONFIRMED" \
  "$HOST_SETTINGS; echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false}'; exit 0"
host_case "host check: a CLI that dies after the hook call is a harness error, not a confirmation" nonzero "!CONFIRMED" \
  "$HOST_SETTINGS; echo 'API connection failed' >&2; exit 42"
if command -v jq >/dev/null 2>&1; then
  host_case "host check: a turn-limit abort is a harness error, not a confirmation" nonzero "!CONFIRMED" \
    "$HOST_SETTINGS; echo '{\"type\":\"result\",\"subtype\":\"error_max_turns\",\"is_error\":true}'; exit 0"
fi
host_case "host check: a CLI that hangs after the control run is stopped by the deadline" nonzero "timed out" \
  'case "$(cat .claude/settings.json)" in *ctl.sh*) printf "x\nx\nx\n" > ctl; echo "{\"subtype\":\"success\",\"is_error\":false}"; exit 0;; *) exec sleep 30;; esac'

# ------------------------------------------------------------------ done ----

echo ""
echo "slickrails tests: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

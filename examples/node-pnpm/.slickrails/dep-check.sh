#!/bin/sh
# slickrails: package check before an agent installs a dependency. bash-guard.sh calls it with the simple commands of
# a Bash call on stdin (one per line, quotes kept). A model that makes up a package name opens the door to
# slopsquatting: someone registers the name and waits. Blocks (exit 2) a package that was first published less than
# SLICKRAILS_DEP_MIN_DAYS (default 30) days ago; on npm only if it also had fewer than 1000 downloads last week (that
# one small request settles most installs). A name that is not on the public registry is only pointed out: its install
# fails by itself, and workspace packages and private registries are not there either.
# Only names on the command line are checked: installs from a lockfile, -r/-c files, local paths, URLs and git sources
# are not. Fail open: no curl, a registry that does not answer or a slow network lets the install through, with a note
# (no network is no reason to stop work). The way out belongs to the human: install it yourself, or start the agent
# with SLICKRAILS_ALLOW_NEW_DEPS=1.

set -u

[ "${SLICKRAILS_ALLOW_NEW_DEPS:-0}" = "1" ] && exit 0
command -v curl >/dev/null 2>&1 || exit 0
MIN_DAYS="${SLICKRAILS_DEP_MIN_DAYS:-30}"
BUDGET=7   # seconds for all lookups together; the guard's hook timeout is 10

# "<registry> <name>" per package named on an install command line
targets() {
  awk '
    function bare(t) { gsub(/["\047]/, "", t); return t }
    {
      n = split($0, a, /[ \t]+/); for (k = 1; k <= n; k++) a[k] = bare(a[k])
      i = 0; eco = ""
      if (a[1] ~ /^(npm|pnpm|bun)$/ && a[2] ~ /^(install|i|add|in)$/) { eco = "npm"; i = 3 }
      else if (a[1] == "yarn" && a[2] == "add")                        { eco = "npm"; i = 3 }
      else if (a[1] ~ /^pip3?$/ && a[2] == "install")                  { eco = "pypi"; i = 3 }
      else if (a[1] ~ /^python3?$/ && a[2] == "-m" && a[3] ~ /^pip3?$/ && a[4] == "install") { eco = "pypi"; i = 5 }
      else if (a[1] == "uv" && a[2] == "add")                          { eco = "pypi"; i = 3 }
      else if (a[1] == "uv" && a[2] == "pip" && a[3] == "install")     { eco = "pypi"; i = 4 }
      else if (a[1] == "poetry" && a[2] == "add")                      { eco = "pypi"; i = 3 }
      if (eco == "") next
      # another registry on the command line: the public one says nothing about these packages (fail open)
      for (k = i; k <= n; k++) if (a[k] ~ /^(--registry|-i|--index-url|--extra-index-url|--index|--default-index)(=.*)?$/) next
      for (; i <= n; i++) {
        t = a[i]
        if (t == "") continue
        # options that take a value: skip the value too
        # (per ecosystem: npm -f is --force and pnpm -w the workspace root, flags without a value)
        if (eco == "pypi" && t ~ /^(-r|-c|-e|-i|-f|-t|--requirement|--constraint|--editable|--index-url|--extra-index-url|--find-links|--target|--prefix|--group|-G)$/) { i++; continue }
        if (eco == "npm" && (t ~ /^(--registry|--prefix|--filter)$/ || (a[1] == "npm" && (t == "-w" || t == "--workspace")))) { i++; continue }
        # a redirect (>, 2>, <, >>file) and its target are no package; a range like "pkg>=1" or "pkg@<2" is
        if (t ~ /^[0-9]*[<>]/) { if (t ~ /^[0-9]*[<>]+&?$/) i++; continue }
        if (t ~ /^-/ || t ~ /[$`]/) continue
        if (eco == "npm") {
          if (t ~ /^@[^\/@]+\/[^\/@]+/) { sub(/^@[^\/@]+\/[^\/@]+/, "&\001", t); sub(/\001.*/, "", t) }
          else { if (t ~ /[\/:]/ || t ~ /^[.~]/ || t ~ /\.tgz$/) continue; sub(/@.*/, "", t) }
        } else {
          if (t ~ /[\/:]/ || t ~ /^[.~]/ || t ~ /\.(whl|zip|tar\.gz)$/) continue
          sub(/[\[=<>!~;].*/, "", t); t = tolower(t)
        }
        if (t ~ /^[@A-Za-z0-9._\/-]+$/) print eco, t
      }
    }'
}

# days since <YYYY-MM-DD...>, by calendar arithmetic (no GNU/BSD date differences)
age_days() {
  printf '%s %s\n' "$(date -u +%Y-%m-%d)" "$1" | awk '
    function d(s,   y, m, x) { y = substr(s, 1, 4) + 0; m = substr(s, 6, 2) + 0; x = substr(s, 9, 2) + 0
      if (m < 3) { y--; m += 12 }
      return 365 * y + int(y / 4) - int(y / 100) + int(y / 400) + int((153 * (m - 3) + 2) / 5) + x }
    { print d($1) - d($2) }'
}

TMP="$(mktemp "${TMPDIR:-/tmp}/slickrails-dep.XXXXXX")"
trap 'rm -f "$TMP"' EXIT
# first_published <npm|pypi>: the date the registry itself recorded, never a field a package author wrote — npm's
# top-level time.created (a version manifest may carry a decoy "created"), PyPI's earliest file upload_time.
# Without jq and node: npm's top-level "time" object is the last one in the document (a JSON string cannot hold an
# unescaped "time":{), PyPI's upload_time keys are written by PyPI and a description cannot hold one unescaped.
first_published() {
  if command -v jq >/dev/null 2>&1; then
    if [ "$1" = "npm" ]; then jq -r '.time.created // empty' "$TMP" 2>/dev/null
    else jq -r '[.releases[]?[]?.upload_time, .urls[]?.upload_time] | map(select(type == "string")) | min // empty' "$TMP" 2>/dev/null; fi
  elif command -v node >/dev/null 2>&1; then
    node -e 'const [k,f]=process.argv.slice(1);let d;try{d=JSON.parse(require("fs").readFileSync(f,"utf8"))}catch(e){process.exit(0)}
      if(k==="npm"){const c=d&&d.time&&d.time.created;if(typeof c==="string")process.stdout.write(c)}
      else{const t=[];for(const r of Object.values((d&&d.releases)||{}))for(const x of r||[])if(x&&typeof x.upload_time==="string")t.push(x.upload_time);
        for(const x of (d&&d.urls)||[])if(x&&typeof x.upload_time==="string")t.push(x.upload_time);if(t.length)process.stdout.write(t.sort()[0])}' "$1" "$TMP" 2>/dev/null
  elif [ "$1" = "npm" ]; then
    sed 's/.*"time":[[:space:]]*{//' "$TMP" | grep -o '"created":[[:space:]]*"[^"]*"' | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/'
  else
    grep -o '"upload_time":[[:space:]]*"[^"]*"' "$TMP" | sed 's/.*"\([^"]*\)"$/\1/' | sort | head -n 1
  fi
}

# fetch <url>: body into $TMP, prints the HTTP status ("000" when nothing answered)
fetch() { curl -sS --max-time 3 -o "$TMP" -w '%{http_code}' "$1" 2>/dev/null || printf '000'; }

# Private registries configured for this repo or user: npm (.npmrc, NPM_CONFIG_REGISTRY; a scope can have its own) and
# PyPI (PIP_INDEX_URL, UV_INDEX_URL, UV_DEFAULT_INDEX, pip.conf). Their packages are not looked up publicly.
NPMRC="$(cat .npmrc "$HOME/.npmrc" 2>/dev/null || true)"
NPM_REG="${NPM_CONFIG_REGISTRY:-$(printf '%s\n' "$NPMRC" | sed -n 's/^[[:space:]]*registry[[:space:]]*=[[:space:]]*//p' | head -n 1)}"
NPM_PUBLIC=1; case "$NPM_REG" in ""|*registry.npmjs.org*) ;; *) NPM_PUBLIC=0;; esac
PIP_REG="${PIP_INDEX_URL:-${UV_INDEX_URL:-${UV_DEFAULT_INDEX:-$(cat "$HOME/.config/pip/pip.conf" "$HOME/.pip/pip.conf" /etc/pip.conf 2>/dev/null \
  | sed -n 's/^[[:space:]]*index-url[[:space:]]*=[[:space:]]*//p' | head -n 1)}}}"
PYPI_PUBLIC=1; case "$PIP_REG" in ""|*pypi.org*) ;; *) PYPI_PUBLIC=0;; esac

START="$(date +%s)"; BLOCKED=""; UNCHECKED=""; NOTFOUND=""
for T in $(targets | tr ' ' '|' | sort -u); do
  ECO="${T%%|*}"; NAME="${T#*|}"
  if [ "$ECO" = "npm" ]; then
    [ "$NPM_PUBLIC" = "1" ] || continue
    case "$NAME" in @*/*) printf '%s\n' "$NPMRC" | grep -q "^[[:space:]]*${NAME%%/*}:registry[[:space:]]*=" && continue;; esac
  else
    [ "$PYPI_PUBLIC" = "1" ] || continue
  fi
  if [ $(( $(date +%s) - START )) -ge "$BUDGET" ]; then UNCHECKED="$UNCHECKED $NAME"; continue; fi
  WHY=""
  if [ "$ECO" = "npm" ]; then
    CODE="$(fetch "https://api.npmjs.org/downloads/point/last-week/$NAME")"
    case "$CODE" in 200|404) ;; *) UNCHECKED="$UNCHECKED $NAME"; continue;; esac
    DL="$(sed -n 's/.*"downloads":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$TMP")"
    [ "${DL:-0}" -ge 1000 ] && continue
    CODE="$(fetch "https://registry.npmjs.org/$(printf '%s' "$NAME" | sed 's|/|%2F|')")"
    if [ "$CODE" = "404" ]; then NOTFOUND="$NOTFOUND $NAME (not on npm)"
    elif [ "$CODE" = "200" ]; then
      CREATED="$(first_published npm)"
      # no date to judge by (the answer changed shape, …): not checked, never "published today"
      case "$CREATED" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) ;; *) UNCHECKED="$UNCHECKED $NAME"; continue;; esac
      AGE="$(age_days "$CREATED")"
      [ "$AGE" -lt "$MIN_DAYS" ] && WHY="was first published $AGE day(s) ago and had ${DL:-0} downloads last week"
    else UNCHECKED="$UNCHECKED $NAME"; continue
    fi
  else
    CODE="$(fetch "https://pypi.org/pypi/$NAME/json")"
    if [ "$CODE" = "404" ]; then NOTFOUND="$NOTFOUND $NAME (not on PyPI)"
    elif [ "$CODE" = "200" ]; then
      FIRST="$(first_published pypi)"
      case "$FIRST" in [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) ;; *) UNCHECKED="$UNCHECKED $NAME"; continue;; esac
      AGE="$(age_days "$FIRST")"
      [ "$AGE" -lt "$MIN_DAYS" ] && WHY="was first uploaded $AGE day(s) ago"
    else UNCHECKED="$UNCHECKED $NAME"; continue
    fi
  fi
  [ -n "$WHY" ] && BLOCKED="$BLOCKED
  - $NAME ($ECO) $WHY"
done

[ -n "$UNCHECKED" ] && echo "slickrails: package check — not checked (the registry did not answer in time, or gave no date):$UNCHECKED" >&2
[ -n "$NOTFOUND" ] && echo "slickrails: package check — check the spelling, a made-up name is how slopsquatting starts:$NOTFOUND" >&2
if [ -n "$BLOCKED" ]; then
  {
    echo "slickrails: blocked — a package in this install looks wrong:$BLOCKED"
    echo "Check the name (a made-up name is how slopsquatting gets in) or pick an established package."
    echo "If it is really meant, the human installs it themselves or starts the session with SLICKRAILS_ALLOW_NEW_DEPS=1."
  } >&2
  exit 2
fi
exit 0

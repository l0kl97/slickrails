#!/bin/sh
# slickrails bootstrap — one-line install:
#   curl -fsSL https://raw.githubusercontent.com/l0kl97/slickrails/main/bootstrap.sh | sh
#
# Clones (or updates) the kit into ~/.slickrails and puts a `slickrails`
# command on PATH. No daemon, no telemetry; inspect this script freely.
# Overrides: SLICKRAILS_REPO (git URL/path), SLICKRAILS_HOME (install dir).

set -eu

REPO="${SLICKRAILS_REPO:-https://github.com/l0kl97/slickrails.git}"
DEST="${SLICKRAILS_HOME:-$HOME/.slickrails}"
# no trailing slash: the clone is built at "$DEST.partial", next to $DEST and not inside it
while [ "${#DEST}" -gt 1 ] && [ "${DEST%/}" != "$DEST" ]; do DEST="${DEST%/}"; done

echo "slickrails: installing kit into $DEST"

if [ -d "$DEST/.git" ]; then
  # an install that stopped between clone and checkout has a .git but no files (and no index): check out first, a
  # pull would take every file for deleted
  [ -f "$DEST/install.sh" ] || git -C "$DEST" checkout -q
  git -C "$DEST" pull --ff-only
else
  # $DEST must be free for the finished clone; an empty directory (made beforehand) is fine, anything else is not
  if [ -e "$DEST" ]; then
    rmdir "$DEST" 2>/dev/null || { echo "slickrails: $DEST exists and is not a slickrails clone — move it away or set SLICKRAILS_HOME" >&2; exit 1; }
  fi
  # The README's media (assets/, demo/: GIFs and the trailer, about 6 MB) are not part of the tool. A sparse checkout
  # leaves them out. The patterns go into the sparse file, not on the command line: Git Bash rewrites arguments that
  # start with / into Windows paths, and the file works with any git since 1.7.
  # The files are fetched only at checkout; the clone is built next to $DEST and moved into place when complete, so a
  # dropped connection leaves no half install that every later run would take for a finished one.
  PART="$DEST.partial"
  rm -rf "$PART"
  git clone --depth 1 --filter=blob:none --no-checkout "$REPO" "$PART"
  git -C "$PART" config core.sparseCheckout true
  mkdir -p "$PART/.git/info"   # a clone template without info/ (init.templateDir with hooks only) leaves it out
  printf '/*\n!/assets/\n!/demo/\n' > "$PART/.git/info/sparse-checkout"
  git -C "$PART" checkout -q
  mv "$PART" "$DEST"
fi

BIN_DIR="${SLICKRAILS_BIN:-/usr/local/bin}"
# an explicitly named bin dir is created, not silently swapped for ~/.local/bin
[ -n "${SLICKRAILS_BIN:-}" ] && { mkdir -p "$BIN_DIR" 2>/dev/null || true; }
if [ ! -w "$BIN_DIR" ]; then
  BIN_DIR="$HOME/.local/bin"
fi
mkdir -p "$BIN_DIR"

ln -sf "$DEST/bin/slickrails" "$BIN_DIR/slickrails" 2>/dev/null || true
if [ ! -L "$BIN_DIR/slickrails" ]; then
  # Git Bash without symlink permission copies instead of linking; a copy would look for the kit next to itself.
  # A two-line launcher calls the kit where it lives.
  rm -f "$BIN_DIR/slickrails"
  printf '#!/bin/sh\nexec sh "%s/bin/slickrails" "$@"\n' "$DEST" > "$BIN_DIR/slickrails"
  chmod +x "$BIN_DIR/slickrails"
fi
chmod +x "$DEST/bin/slickrails" "$DEST/install.sh" 2>/dev/null || true
echo "slickrails: linked $BIN_DIR/slickrails"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) echo "slickrails: NOTE — $BIN_DIR is not on your PATH. Add it, e.g.: export PATH=\"$BIN_DIR:\$PATH\"";;
esac

echo ""
sh "$DEST/install.sh" doctor
echo ""
echo "slickrails: done. Next: cd into a project and run 'slickrails init'."

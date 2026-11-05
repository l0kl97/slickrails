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

echo "slickrails: installing kit into $DEST"

if [ -d "$DEST/.git" ]; then
  git -C "$DEST" pull --ff-only
else
  git clone --depth 1 "$REPO" "$DEST"
fi

BIN_DIR="${SLICKRAILS_BIN:-/usr/local/bin}"
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

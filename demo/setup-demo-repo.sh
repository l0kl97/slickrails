#!/bin/sh
# Builds a throwaway repo for recording demo/demo.tape.
# Usage: sh demo/setup-demo-repo.sh /tmp/slickrails-demo

set -eu

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-/tmp/slickrails-demo}"

rm -rf "$DEST"
mkdir -p "$DEST"
cd "$DEST"
git init -q -b main
git config user.email demo@slickrails.local
git config user.name "slickrails Demo"

printf '{"name":"demo","scripts":{"test":"node -e \\"process.exit(1)\\""}}' > package.json
sh "$KIT_DIR/install.sh" >/dev/null

git add -A && git commit -qm "init" --no-verify
rm -rf ../slickrails-demo-remote.git
git init -q --bare ../slickrails-demo-remote.git
git remote add origin ../slickrails-demo-remote.git

echo "Demo repo ready at $DEST (test script is red on purpose — the tape fixes it on camera)."
echo "Record with: cd $DEST && vhs < $KIT_DIR/demo/demo.tape"

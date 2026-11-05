#!/bin/sh
# Renders assets/header.png from assets/header.html at 2x (2560x800).
# Needs Chrome; network access for the Google Fonts used in the header.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
command -v "$CHROME" >/dev/null 2>&1 || CHROME="google-chrome"
"$CHROME" --headless --disable-gpu --force-device-scale-factor=2 \
  --window-size=1280,400 --screenshot="$DIR/header.png" \
  --virtual-time-budget=8000 "file://$DIR/header.html"
echo "rendered $DIR/header.png"

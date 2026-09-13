#!/bin/sh
# Builds TokenBar.app and installs it into /Applications (override with INSTALL_DIR),
# replacing any previous copy, then launches it. Used by `make install`.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
SRC="$ROOT/build/TokenBar.app"
DEST="$INSTALL_DIR/TokenBar.app"

"$ROOT/scripts/bundle.sh"

if [ ! -d "$INSTALL_DIR" ] || [ ! -w "$INSTALL_DIR" ]; then
  echo "Cannot write to $INSTALL_DIR. Try: INSTALL_DIR=\$HOME/Applications make install" >&2
  exit 1
fi

# The binary cannot be replaced while it is running. Ask politely first, then insist.
if pgrep -xq TokenBar; then
  echo "Quitting the running TokenBar…"
  osascript -e 'tell application id "com.lazarevic.tokenbar" to quit' >/dev/null 2>&1 || true
  i=0
  while pgrep -xq TokenBar && [ "$i" -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
  pgrep -xq TokenBar && pkill -x TokenBar || true
fi

rm -rf "$DEST"
ditto "$SRC" "$DEST"
echo "Installed $DEST"
open "$DEST"

#!/bin/sh
# Sanity-checks an assembled TokenBar.app: required files, menu-bar-only flag, signature.
# Usage: scripts/check-bundle.sh [path/to/TokenBar.app]   (default: build/TokenBar.app)
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/build/TokenBar.app}"

for path in \
  "$APP/Contents/MacOS/TokenBar" \
  "$APP/Contents/Info.plist" \
  "$APP/Contents/Resources/AppIcon.icns" \
  "$APP/Contents/Resources/TokenBar_TokenBar.bundle"; do
  test -e "$path" || { echo "Missing $path" >&2; exit 1; }
done

# LSUIElement keeps the app out of the Dock; losing it changes how it launches.
/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$APP/Contents/Info.plist" | grep -qx true \
  || { echo "LSUIElement is not true in Info.plist" >&2; exit 1; }

codesign --verify --deep --strict "$APP"
echo "Bundle OK: $APP"

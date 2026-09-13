#!/bin/sh
# Zips build/TokenBar.app into build/TokenBar-<version>.zip for GitHub Releases and the
# Homebrew cask. `ditto` keeps the bundle structure, permissions and signature intact,
# which a plain `zip` does not. Prints the SHA-256 the cask needs.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/TokenBar.app"
[ -d "$APP" ] || "$ROOT/scripts/bundle.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="$ROOT/build/TokenBar-$VERSION.zip"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $ZIP"
shasum -a 256 "$ZIP"

#!/bin/sh
# Builds TokenBar in release mode and assembles an ad-hoc-signed build/TokenBar.app.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/TokenBar"
# SPM puts the target's processed resources in this bundle next to the binary.
# `Bundle.module` searches `Bundle.main.resourceURL`, so it must land in Contents/Resources.
RESOURCE_BUNDLE="$BIN_DIR/TokenBar_TokenBar.bundle"

APP="$ROOT/build/TokenBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TokenBar"
cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  swift "$ROOT/scripts/make-icon.swift" "$ROOT/assets/tokenbar-logo-app-icon.png" "$ROOT/build/AppIcon.iconset"
  iconutil -c icns "$ROOT/build/AppIcon.iconset" -o "$ROOT/Resources/AppIcon.icns"
fi
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP"
echo "Built $APP"

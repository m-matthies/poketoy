#!/bin/bash
# Builds build/PokeToy.app from the Swift package (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product PokeToy
BIN_DIR="$(swift build -c release --show-bin-path)"

APP=build/PokeToy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PokeToy" "$APP/Contents/MacOS/PokeToy"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Sprites "$APP/Contents/Resources/Sprites"
cp -R Resources/Portraits "$APP/Contents/Resources/Portraits"

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift Resources/Icon/portrait-0025.png "$ICONSET"
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

codesign --force --sign - "$APP"
echo "Built $APP"

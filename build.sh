#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$ROOT_DIR/Meowy.app"
EXECUTABLE="$BUILD_DIR/CAT"

mkdir -p "$BUILD_DIR"

swiftc \
  -swift-version 5 \
  -parse-as-library \
  -O \
  -framework AppKit \
  -framework QuartzCore \
  "$ROOT_DIR/Sources/CATApp/CATApp.swift" \
  "$ROOT_DIR/Sources/CATApp/CatSimulation.swift" \
  "$ROOT_DIR/Sources/CATApp/SpriteSheet.swift" \
  -o "$EXECUTABLE"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$EXECUTABLE" "$APP_DIR/Contents/MacOS/CAT"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/Meowy.gif" "$APP_DIR/Contents/Resources/Meowy.gif"
cp "$ROOT_DIR/Resources/Meowy.icns" "$APP_DIR/Contents/Resources/Meowy.icns"

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"

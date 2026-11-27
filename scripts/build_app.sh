#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_BUNDLE="$BUILD_DIR/IkiNotch.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

CACHE_ROOT="${IKINOTCH_CACHE_DIR:-/tmp/ikinotch-cache}"
mkdir -p "$CACHE_ROOT/clang" "$CACHE_ROOT/swiftpm"
export CLANG_MODULE_CACHE_PATH="$CACHE_ROOT/clang"
export SWIFT_MODULECACHE_PATH="$CACHE_ROOT/clang"

echo "▶ Building IkiNotch (release)..."
cd "$ROOT_DIR"
swift build -c release \
    --disable-sandbox \
    --cache-path "$CACHE_ROOT/swiftpm" \
    --config-path "$CACHE_ROOT/swiftpm-cfg" \
    --security-path "$CACHE_ROOT/swiftpm-sec" \
    -Xswiftc -module-cache-path -Xswiftc "$CACHE_ROOT/clang"

BIN_PATH="$(swift build -c release \
    --disable-sandbox \
    --cache-path "$CACHE_ROOT/swiftpm" \
    --config-path "$CACHE_ROOT/swiftpm-cfg" \
    --security-path "$CACHE_ROOT/swiftpm-sec" \
    --show-bin-path)/IkiNotch"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "Error: compiled binary not found at $BIN_PATH" >&2
    exit 1
fi

echo "▶ Assembling IkiNotch.app bundle..."
rm -rf "$APP_BUNDLE" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_PATH" "$MACOS_DIR/IkiNotch"
cp "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "▶ Generating AppIcon.icns..."
swift -module-cache-path "$CACHE_ROOT/clang" "$ROOT_DIR/scripts/generate_icon.swift" "$RESOURCES_DIR/AppIcon.icns"

echo "▶ Code-signing ad-hoc..."
codesign --force --deep --sign - "$APP_BUNDLE"
touch "$APP_BUNDLE"

echo "✓ Built successfully: $APP_BUNDLE"
du -sh "$APP_BUNDLE"

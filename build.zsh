#!/bin/zsh

set -euo pipefail

readonly PROJECT_DIR="${0:A:h}"
readonly OUTPUT_DIR="$PROJECT_DIR/outputs"
readonly BUILD_DIR="$PROJECT_DIR/.build"
readonly APP_NAME="Dia 中文补丁助手.app"
readonly APP_DIR="$OUTPUT_DIR/$APP_NAME"
readonly CONTENTS_DIR="$APP_DIR/Contents"
readonly MACOS_DIR="$CONTENTS_DIR/MacOS"
readonly RESOURCES_DIR="$CONTENTS_DIR/Resources"
readonly PATCH_VERSION="0.1.0-rc.2"
readonly PATCH_ARCHIVE_NAME="dia-zh-patch-$PATCH_VERSION-macos-arm64.zip"
readonly PATCH_SHA256="96fc8bf38be19b170a8df8a3dc67a71339103e4ba406c66dd1450634bc4d6ee1"
readonly PATCH_URL="https://github.com/AYangZi/dia-zh-patch/releases/download/v$PATCH_VERSION/$PATCH_ARCHIVE_NAME"
readonly PATCH_ARCHIVE="$BUILD_DIR/$PATCH_ARCHIVE_NAME"
readonly PATCH_EXTRACT="$BUILD_DIR/vendor-$PATCH_VERSION"
readonly PATCH_SOURCE="$PATCH_EXTRACT/dia-zh-patch-$PATCH_VERSION-macos-arm64"

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

if [[ ! -f "$PATCH_ARCHIVE" ]]; then
  curl -L --fail --silent --show-error "$PATCH_URL" -o "$PATCH_ARCHIVE"
fi
print -r -- "$PATCH_SHA256  $PATCH_ARCHIVE" | shasum -a 256 -c -

if [[ ! -d "$PATCH_SOURCE" ]]; then
  mkdir -p "$PATCH_EXTRACT"
  ditto -x -k "$PATCH_ARCHIVE" "$PATCH_EXTRACT"
fi
if ! grep -q 'com.apple.developer.aps-environment' "$PATCH_SOURCE/scripts/sign-app.zsh"; then
  patch -d "$PATCH_SOURCE" -p1 < "$PROJECT_DIR/patches/strip-aps-entitlement.patch"
fi

swiftc -swift-version 5 -O \
  -framework AppKit \
  "$PROJECT_DIR/Sources/main.swift" \
  -o "$MACOS_DIR/DiaZhHelper"

cp "$PROJECT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
ditto "$PATCH_SOURCE" "$RESOURCES_DIR/Patch"
chmod +x "$RESOURCES_DIR/Patch/dia-zh.command" "$RESOURCES_DIR/Patch/scripts/"*.zsh

swiftc -swift-version 5 -O \
  -framework AppKit \
  "$PROJECT_DIR/Sources/IconGenerator.swift" \
  -o "$BUILD_DIR/IconGenerator"
"$BUILD_DIR/IconGenerator" "$BUILD_DIR/icon-1024.png"

readonly ICONSET="$BUILD_DIR/DiaZhHelper.iconset"
mkdir -p "$ICONSET"
sips -z 16 16 "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$BUILD_DIR/icon-1024.png" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$BUILD_DIR/icon-1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/DiaZhHelper.icns"

codesign --force --deep --sign - --timestamp=none "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$OUTPUT_DIR/DiaZhHelper-1.0.0.zip"

print -r -- "$APP_DIR"

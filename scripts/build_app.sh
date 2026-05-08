#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Photos Archive Exporter"
BINARY_NAME="PhotosArchiveExporterApp"
VERSION="0.3.1"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/PhotosArchiveExporter-v$VERSION-macos-universal.zip"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_PATH="$ROOT_DIR/Resources/PhotosArchiveExporter.icns"
ARM64_BUILD_DIR="$ROOT_DIR/.build/universal-arm64"
X86_64_BUILD_DIR="$ROOT_DIR/.build/universal-x86_64"
ARM64_TRIPLE="arm64-apple-macosx13.0"
X86_64_TRIPLE="x86_64-apple-macosx13.0"

cd "$ROOT_DIR"
if [[ ! -f "$ICON_PATH" || "$ROOT_DIR/scripts/generate_app_icon.swift" -nt "$ICON_PATH" ]]; then
    swift "$ROOT_DIR/scripts/generate_app_icon.swift"
fi

swift build -c release --product "$BINARY_NAME" --triple "$ARM64_TRIPLE" --scratch-path "$ARM64_BUILD_DIR"
swift build -c release --product "$BINARY_NAME" --triple "$X86_64_TRIPLE" --scratch-path "$X86_64_BUILD_DIR"

ARM64_BINARY="$(swift build -c release --product "$BINARY_NAME" --triple "$ARM64_TRIPLE" --scratch-path "$ARM64_BUILD_DIR" --show-bin-path)/$BINARY_NAME"
X86_64_BINARY="$(swift build -c release --product "$BINARY_NAME" --triple "$X86_64_TRIPLE" --scratch-path "$X86_64_BUILD_DIR" --show-bin-path)/$BINARY_NAME"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

lipo -create "$ARM64_BINARY" "$X86_64_BINARY" -output "$MACOS_DIR/$BINARY_NAME"
cp "$ICON_PATH" "$RESOURCES_DIR/PhotosArchiveExporter.icns"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>PhotosArchiveExporterApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.dev1ny.photos-archive-exporter</string>
    <key>CFBundleIconFile</key>
    <string>PhotosArchiveExporter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Photos Archive Exporter</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.1</string>
    <key>CFBundleVersion</key>
    <string>5</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPhotoLibraryUsageDescription</key>
    <string>Photos Archive Exporter needs read access to export original photos and videos into your chosen archive folder.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --norsrc --noextattr --noqtn --noacl --keepParent "$APP_DIR" "$ZIP_PATH"
echo "$APP_DIR"
echo "$ZIP_PATH"

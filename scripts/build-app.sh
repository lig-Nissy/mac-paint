#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MacPaint"
BUNDLE_ID="com.example.macpaint"
VERSION="1.0"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RES="${CONTENTS}/Resources"

echo "==> swift build -c release"
swift build -c release

echo "==> reset ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RES}"

echo "==> copy executable"
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"
chmod +x "${MACOS}/${APP_NAME}"

echo "==> generate icon set"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${ICONSET_DIR}"
"${BUILD_DIR}/${APP_NAME}" --export-iconset "${ICONSET_DIR}"
iconutil -c icns "${ICONSET_DIR}" -o "${RES}/AppIcon.icns"

echo "==> write Info.plist"
cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
</dict>
</plist>
PLIST

echo "==> ad-hoc codesign"
codesign --force --deep --sign - "${APP_DIR}" >/dev/null

echo ""
echo "Done: ${APP_DIR}"
echo "Run:  open ${APP_DIR}"

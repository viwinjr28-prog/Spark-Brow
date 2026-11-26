#!/bin/bash
set -e
APP_NAME="Spark Brow"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="Spark-Brow.dmg"
STAGE_DIR="./dmg_stage"

echo "Generating Spark Brow app icon..."
swift make_icon.swift
iconutil -c icns AppIcon.iconset -o AppIcon.icns || true

echo "Building ${APP_BUNDLE}..."
rm -rf "${APP_BUNDLE}" "${STAGE_DIR}" "${DMG_NAME}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

cp sparkos.html "${APP_BUNDLE}/Contents/Resources/sparkos.html"
[ -f AppIcon.icns ] && cp AppIcon.icns "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Spark Brow</string>
  <key>CFBundleDisplayName</key><string>Spark Brow</string>
  <key>CFBundleIdentifier</key><string>com.viwin.sparkbrow</string>
  <key>CFBundleVersion</key><string>3.0</string>
  <key>CFBundleShortVersionString</key><string>3.0</string>
  <key>CFBundleExecutable</key><string>SparkBrow</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

swiftc -O -framework Cocoa -framework WebKit SparkBrow.swift -o "${APP_BUNDLE}/Contents/MacOS/SparkBrow"
codesign --force --deep --sign - "${APP_BUNDLE}" || true

echo "Packaging ${DMG_NAME}..."
mkdir -p "${STAGE_DIR}"
cp -R "${APP_BUNDLE}" "${STAGE_DIR}/"
ln -s /Applications "${STAGE_DIR}/Applications"
hdiutil create -volname "Spark Brow" -srcfolder "${STAGE_DIR}" -ov -format UDZO "${DMG_NAME}"
rm -rf "${STAGE_DIR}" AppIcon.iconset AppIcon.icns
echo "Done! Created ${DMG_NAME}"

#!/usr/bin/env bash
# Builds a double-clickable LectureQuest.app from the Swift package.
# Usage:  ./scripts/build-app.sh            -> ./build/LectureQuest.app
#         ./scripts/build-app.sh --install  -> also copies it to ~/Applications
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product LectureQuest
BIN="$(swift build -c release --product LectureQuest --show-bin-path)/LectureQuest"

APP="build/LectureQuest.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LectureQuest"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>LectureQuest</string>
  <key>CFBundleDisplayName</key><string>LectureQuest</string>
  <key>CFBundleIdentifier</key><string>com.lecturequest.mac</string>
  <key>CFBundleExecutable</key><string>LectureQuest</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so Gatekeeper lets it run locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/LectureQuest.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "Installed to ~/Applications/LectureQuest.app"
fi

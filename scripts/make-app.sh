#!/bin/bash
# Builds Vigia.app, signs it ad-hoc, and writes Vigia.dmg and Vigia.zip.
# Installs ship from GitHub Releases, not from Actions artifacts.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
test -n "$VERSION"

swift build -c release --product Pulse
BIN="$(swift build -c release --product Pulse --show-bin-path)"
test -x "$BIN/Pulse"
test -d "$BIN/Pulse_Pulse.bundle"

ROOT="build.noindex"
APP="$ROOT/Vigia.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ROOT"
touch "$ROOT/.metadata_never_index"

cp "$BIN/Pulse" "$APP/Contents/MacOS/Vigia"
chmod +x "$APP/Contents/MacOS/Vigia"
cp -R "$BIN/Pulse_Pulse.bundle" "$APP/Contents/Resources/"
# SwiftPM already writes this bundle's Info.plist at its root. Give it an
# identifier codesign will accept without moving the resources.
RES_PLIST="$APP/Contents/Resources/Pulse_Pulse.bundle/Info.plist"
if [ -f "$RES_PLIST" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.vigia.mac.resources" "$RES_PLIST" \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.vigia.mac.resources" "$RES_PLIST" \
        || true
fi

ICON_SRC="icons/AppIcon.jpg"
test -f "$ICON_SRC"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
# iconutil names: pixel size is the filename, @2x is the double-resolution twin.
sips -s format png -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -s format png -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -s format png -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -s format png -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -s format png -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -s format png -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -s format png -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -s format png -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -s format png -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -s format png -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Vigia</string>
    <key>CFBundleDisplayName</key><string>Vigía</string>
    <key>CFBundleExecutable</key><string>Vigia</string>
    <key>CFBundleIdentifier</key><string>com.vigia.mac</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
        <string>zh-Hant</string>
        <string>ja</string>
        <string>ko</string>
        <string>es</string>
    </array>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key><string>com.vigia.mac.navigation</string>
        <key>CFBundleURLSchemes</key><array><string>pulse</string></array>
        <key>CFBundleTypeRole</key><string>Viewer</string>
    </dict></array>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>github.com/camilocristancho14/vigia</string>
</dict>
</plist>
PLIST

# Inside out. --deep on the outer bundle resigns nested code; verify must pass strict.
codesign --force --sign - "$APP/Contents/Resources/Pulse_Pulse.bundle"
codesign --force --sign - "$APP/Contents/MacOS/Vigia"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/Vigia.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$ROOT/Vigia.dmg"
hdiutil create -volname "Vigía" -srcfolder "$STAGE" -ov -format UDZO "$ROOT/Vigia.dmg"
rm -rf "$STAGE"

rm -f "$ROOT/Vigia.zip"
ditto -c -k --keepParent "$APP" "$ROOT/Vigia.zip"

echo "→ $APP"
echo "→ $ROOT/Vigia.dmg"
echo "→ $ROOT/Vigia.zip"

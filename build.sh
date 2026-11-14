#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DEPLOYMENT_TARGET="${SWITCH_MTP_DEPLOYMENT_TARGET:-13.0}"
BUILD_ARCH="$(uname -m)"
DEPS_PREFIX="${SWITCH_MTP_DEPS_PREFIX:-$HOME/Library/Caches/mac-switch-mtp/deps-$BUILD_ARCH-macos$DEPLOYMENT_TARGET}"
bash vendor/build-libraries.sh "$DEPS_PREFIX" "$DEPLOYMENT_TARGET"
MTP_PREFIX="$DEPS_PREFIX"
USB_PREFIX="$DEPS_PREFIX"
APP="${SWITCH_MTP_APP_PATH:-$PWD/dist/Switch MTP.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
cp vendor/licenses/libmtp-LICENSE.txt "$APP/Contents/Resources/libmtp-LICENSE.txt"
cp vendor/licenses/libusb-LICENSE.txt "$APP/Contents/Resources/libusb-LICENSE.txt"
cp README.md THIRD_PARTY.md LICENSE "$APP/Contents/Resources/"
clang -Wall -Wextra -Werror -O2 -mmacosx-version-min="$DEPLOYMENT_TARGET" -I"$MTP_PREFIX/include" Sources/mtp_helper.c \
    -L"$MTP_PREFIX/lib" -lmtp -o "$APP/Contents/MacOS/mtp-helper"
swiftc -swift-version 5 -O -target "$BUILD_ARCH-apple-macos$DEPLOYMENT_TARGET" Sources/SwitchMTP.swift -o "$APP/Contents/MacOS/SwitchMTP" \
    -framework AppKit -framework SwiftUI -framework UniformTypeIdentifiers
cp "$MTP_PREFIX/lib/libmtp.9.dylib" "$APP/Contents/Frameworks/"
cp "$USB_PREFIX/lib/libusb-1.0.0.dylib" "$APP/Contents/Frameworks/"
chmod u+w "$APP/Contents/Frameworks/"*.dylib
install_name_tool -id '@rpath/libmtp.9.dylib' "$APP/Contents/Frameworks/libmtp.9.dylib"
install_name_tool -id '@rpath/libusb-1.0.0.dylib' "$APP/Contents/Frameworks/libusb-1.0.0.dylib"
install_name_tool -change "$USB_PREFIX/lib/libusb-1.0.0.dylib" '@loader_path/libusb-1.0.0.dylib' "$APP/Contents/Frameworks/libmtp.9.dylib"
install_name_tool -change "$MTP_PREFIX/lib/libmtp.9.dylib" '@executable_path/../Frameworks/libmtp.9.dylib' "$APP/Contents/MacOS/mtp-helper"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SwitchMTP</string>
<key>CFBundleIdentifier</key><string>local.codex.switch-mtp</string>
<key>CFBundleName</key><string>Switch MTP</string>
<key>CFBundleDisplayName</key><string>Switch MTP</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>本地试用工具 · 2026</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion $DEPLOYMENT_TARGET" "$APP/Contents/Info.plist"
xattr -cr "$APP"
for binary in "$APP/Contents/Frameworks/"*.dylib "$APP/Contents/MacOS/mtp-helper"; do
    codesign --force --sign - "$binary"
done
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "已生成：$APP"

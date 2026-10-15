#!/bin/bash
# Builds Infinity Flow.app with the Command Line Tools only (no Xcode) and opens it.
#
# Usage: ./scripts/build-app.sh            # release build, ad-hoc signed, then opens the app
#        SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" ./scripts/build-app.sh
#        NO_OPEN=1 CONFIG=debug ./scripts/build-app.sh
# Ad-hoc builds change identity on every build, so macOS asks for Accessibility again; a certificate keeps it.
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
NAME="Infinity Flow"
APP="build/$NAME.app"

# The macOS 27 SDK turns SwiftUI's @State into a macro whose plugin ships only with Xcode,
# so use the newest older SDK the Command Line Tools have.
if [ -z "${SDKROOT:-}" ] && [ ! -d /Applications/Xcode.app ]; then
  for sdk in $(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX2[0-6].*.sdk 2>/dev/null | sort -V -r); do
    export SDKROOT="$sdk"; break
  done
fi
echo "Building ($CONFIG) with ${SDKROOT:-the default SDK}…"
swift build -c "$CONFIG" --product InfinityFlow
BIN="$(swift build -c "$CONFIG" --show-bin-path)/InfinityFlow"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$NAME"

# App icon: the asset catalog's PNGs as an .icns.
SET=Sources/Assets.xcassets/AppIcon.appiconset
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  cp "$SET/icon_$size.png" "$ICONSET/icon_${size}x${size}.png"
  cp "$SET/icon_$((size * 2)).png" "$ICONSET/icon_${size}x${size}@2x.png" 2>/dev/null || true
done
cp "$SET/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# Info.plist: the privacy strings from Support/Info.plist plus the bundle keys Xcode would generate.
version() { grep -E "^\s+$1:" project.yml | head -1 | sed -E 's/.*: *"?([^"]*)"?/\1/'; }
PLIST="$APP/Contents/Info.plist"
cp Support/Info.plist "$PLIST"
set_key() { /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$PLIST"; }
set_key CFBundleExecutable string "$NAME"
set_key CFBundleIdentifier string com.oneinfinitylabs.InfinityFlow
set_key CFBundleName string "$NAME"
set_key CFBundleDisplayName string "$NAME"
set_key CFBundlePackageType string APPL
set_key CFBundleShortVersionString string "$(version MARKETING_VERSION)"
set_key CFBundleVersion string "$(version CURRENT_PROJECT_VERSION)"
set_key CFBundleIconFile string AppIcon
set_key LSMinimumSystemVersion string 15.0
set_key LSApplicationCategoryType string public.app-category.productivity
set_key NSHighResolutionCapable bool true

codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
echo "Built $APP"
if [ -z "${NO_OPEN:-}" ]; then
  pkill -f "$NAME.app/Contents/MacOS" || true
  open "$APP"
fi

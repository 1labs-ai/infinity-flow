#!/bin/bash
# Builds Infinity Flow.app with the Command Line Tools only (no Xcode) and opens it.
#
# Usage: ./scripts/build-app.sh            # release build, then opens the app
#        SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" ./scripts/build-app.sh
#        NO_OPEN=1 CONFIG=debug ./scripts/build-app.sh
#
# macOS remembers permissions (microphone, Accessibility, System Audio Recording) by the app's signature.
# An ad-hoc signature changes on every build, so every rebuild would ask again. Without SIGN_IDENTITY, the
# script signs with a local self-signed certificate it creates once, in its own keychain (your login keychain
# is not touched), so permissions survive rebuilds.
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

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "$SIGN_IDENTITY" "$APP"
else
  SIGNING="$HOME/Library/Application Support/InfinityFlow/Signing"
  KEYCHAIN="$SIGNING/signing.keychain-db"
  LOCAL_ID="Infinity Flow Local Signing"
  if [ ! -f "$KEYCHAIN" ]; then
    echo "Creating a local signing certificate (once)…"
    mkdir -p "$SIGNING" && chmod 700 "$SIGNING"
    openssl rand -hex 24 > "$SIGNING/password" && chmod 600 "$SIGNING/password"
    WORK="$(mktemp -d)"
    printf '[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n[dn]\nCN=%s\n[ext]\nbasicConstraints=critical,CA:false\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\n' "$LOCAL_ID" > "$WORK/cert.cnf"
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -days 3650 -config "$WORK/cert.cnf" 2>/dev/null
    openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" -passout pass:import -legacy 2>/dev/null \
      || openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/id.p12" -passout pass:import
    security create-keychain -p "$(cat "$SIGNING/password")" "$KEYCHAIN"
    security set-keychain-settings "$KEYCHAIN"
    security unlock-keychain -p "$(cat "$SIGNING/password")" "$KEYCHAIN"
    security import "$WORK/id.p12" -k "$KEYCHAIN" -P import -T /usr/bin/codesign >/dev/null
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$(cat "$SIGNING/password")" "$KEYCHAIN" >/dev/null
    rm -f "$WORK/key.pem" "$WORK/id.p12"
  fi
  security unlock-keychain -p "$(cat "$SIGNING/password")" "$KEYCHAIN"
  codesign --force --keychain "$KEYCHAIN" --sign "$LOCAL_ID" "$APP"
fi
echo "Built $APP"
if [ -z "${NO_OPEN:-}" ]; then
  pkill -f "$NAME.app/Contents/MacOS" && sleep 1 || true
  open "$APP"
fi

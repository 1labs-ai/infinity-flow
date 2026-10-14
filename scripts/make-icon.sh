#!/bin/sh
# Regenerates Sources/Assets.xcassets/AppIcon.appiconset from scripts/make-icon.swift.
set -e
cd "$(dirname "$0")/.."
SET=Sources/Assets.xcassets/AppIcon.appiconset
swift scripts/make-icon.swift "$SET/icon_1024.png"
for px in 16 32 64 128 256 512; do
  sips -z $px $px "$SET/icon_1024.png" --out "$SET/icon_$px.png" >/dev/null
done

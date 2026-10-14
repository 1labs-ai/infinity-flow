#!/bin/bash
# Builds and launches Infinity Flow signed with your Apple Development certificate.
# Ad-hoc builds change identity on every build, so macOS drops the Accessibility grant;
# a real certificate keeps it across rebuilds.
#
# Usage: SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" TEAM_ID=ABCDE12345 ./scripts/run.sh
# Find yours with: security find-identity -v -p codesigning
set -e
cd "$(dirname "$0")/.."
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to an Apple Development certificate name}"
: "${TEAM_ID:?Set TEAM_ID to the team ID of that certificate (its OU field)}"
xcodegen generate >/dev/null
pkill -f 'Infinity Flow.app/Contents/MacOS' || true
xcodebuild -project InfinityFlow.xcodeproj -scheme InfinityFlow -derivedDataPath build -destination 'platform=macOS' \
  build CODE_SIGN_IDENTITY="$SIGN_IDENTITY" DEVELOPMENT_TEAM="$TEAM_ID" | grep -E 'error:|\*\* '
open "build/Build/Products/Debug/Infinity Flow.app"

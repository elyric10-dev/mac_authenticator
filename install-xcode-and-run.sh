#!/bin/bash
set -euo pipefail

# Installs Xcode 26.2 (compatible with macOS 15.6) and runs MacAuthenticator.
# Run from Terminal: bash install-xcode-and-run.sh

XIP=$(ls -t ~/Downloads/Xcode_26.2*.xip 2>/dev/null | head -1 || true)

if [[ -z "$XIP" ]]; then
  echo "No Xcode_26.2*.xip found in ~/Downloads."
  echo "Download it from: https://developer.apple.com/download/all/?q=Xcode%2026.2"
  echo "Then run this script again."
  exit 1
fi

echo "Installing from: $XIP"
xcodes install 26.2 --path "$XIP" --experimental-unxip

sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept 2>/dev/null || true

cd "$(dirname "$0")"
xcodegen generate 2>/dev/null || true

echo "Building MacAuthenticator..."
xcodebuild -scheme MacAuthenticator -configuration Debug -destination 'platform=macOS' -derivedDataPath build build

APP="build/Build/Products/Debug/MacAuthenticator.app"
open "$APP"
echo "Launched. Look for the shield icon in your menu bar (top right)."

#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
APP_NAME="MacAuthenticator"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"

# Prefer full Xcode over Command Line Tools.
if [[ -d "/Applications/Xcode-26.2.0.app" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode-26.2.0.app/Contents/Developer"
elif [[ -d "/Applications/Xcode.app" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

cd "$ROOT"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate
fi

echo "Building $APP_NAME (Release)..."
xcodebuild \
  -project MacAuthenticator.xcodeproj \
  -scheme MacAuthenticator \
  -configuration Release \
  -derivedDataPath "$ROOT/build" \
  build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES

APP_PATH="$ROOT/build/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build failed: app not found at $APP_PATH" >&2
  exit 1
fi

echo "Installing to $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_PATH" "$INSTALL_DIR/"

mkdir -p "$DIST"
ZIP_PATH="$DIST/$APP_NAME.zip"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

echo ""
echo "Done."
echo "  Installed: $INSTALL_DIR/$APP_NAME.app"
echo "  Shareable: $ZIP_PATH"
echo ""
echo "To launch: open \"$INSTALL_DIR/$APP_NAME.app\""
echo "Tip: recipients may need Right-click -> Open the first time (unsigned app)."

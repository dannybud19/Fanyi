#!/bin/bash
set -euo pipefail

APP_NAME="Fanyi"
BUNDLE_ID="com.danny.fanyi"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

APP_BUNDLE="build/$APP_NAME.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

echo "Compiling..."
# The default SDK that `xcrun` resolves can be newer than this machine's swiftc
# (e.g. a beta SDK ahead of the installed toolchain), which fails with an
# "SDK is not supported by the compiler" error. Pin the unversioned SDK symlink,
# which CLT keeps pointed at a build the installed compiler actually supports.
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk"
if [[ ! -d "$SDK_PATH" ]]; then
  SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
fi

swiftc Sources/*.swift \
  -swift-version 5 -O \
  -sdk "$SDK_PATH" \
  -target arm64-apple-macosx13.0 \
  -framework AppKit -framework SwiftUI \
  -framework ApplicationServices -framework ServiceManagement \
  -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"

if [[ "${1:-}" == "install" ]]; then
  DEST="/Applications/$APP_NAME.app"
  echo "Installing to $DEST"
  rm -rf "$DEST"
  cp -R "$APP_BUNDLE" "$DEST"

  echo "Resetting Accessibility permission for $BUNDLE_ID (ad-hoc signature changed)"
  tccutil reset Accessibility "$BUNDLE_ID" || true

  echo "Launching $APP_NAME"
  open "$DEST"
fi

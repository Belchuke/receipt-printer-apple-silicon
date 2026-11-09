#!/bin/bash
# Assembles "Receipt Printer Settings.app" in dist/ from the release build of receipt-printer-settings.
# build.sh runs this; sign.sh signs the bundle; build-pkg.sh installs it into /Applications.
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/config.sh

BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
APP="$DIST_DIR/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/$APP_EXECUTABLE" "$APP/Contents/MacOS/$APP_EXECUTABLE"
render_template pkg/app/Info.plist.template "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
echo "assembled $APP"

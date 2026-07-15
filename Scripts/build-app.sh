#!/bin/bash
# PadSwitch.app を組み立てるスクリプト (Apple Silicon 専用)
#   usage: Scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> swift build (release)"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/PadSwitch.app"

echo "==> ${APP} を組み立て"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/PadSwitchApp" "$APP/Contents/MacOS/PadSwitch"
cp "$BIN_DIR/padswitch-cli" "$APP/Contents/Resources/padswitch-cli"
cp Support/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> ad-hoc 署名"
codesign --force --deep --sign - "$APP"

echo "==> 完了: $APP"
echo "    /Applications へコピーするには: cp -R $APP /Applications/"

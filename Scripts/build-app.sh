#!/bin/bash
# PadSwitch.app を組み立てるスクリプト (Apple Silicon 専用)
#   usage: Scripts/build-app.sh
#
# 署名は既定で ad-hoc。配布用は CODESIGN_IDENTITY に Developer ID を渡すと
# hardened runtime + timestamp 付きで署名する(公証は Scripts/release.sh で行う)
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

# 同梱 CLI は Resources 下にあり --deep では署名されないため、内側から個別に署名する
IDENTITY="${CODESIGN_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    echo "==> ad-hoc 署名"
    codesign --force --sign - "$APP/Contents/Resources/padswitch-cli"
    codesign --force --sign - "$APP"
else
    echo "==> Developer ID 署名: $IDENTITY"
    codesign --force --sign "$IDENTITY" --timestamp --options runtime \
        --identifier com.watahiki.padswitch.cli "$APP/Contents/Resources/padswitch-cli"
    codesign --force --sign "$IDENTITY" --timestamp --options runtime "$APP"
fi

echo "==> 完了: $APP"
echo "    /Applications へコピーするには: cp -R $APP /Applications/"

#!/bin/bash
# Developer ID 署名 + 公証(notarization)済みの配布用 zip を作るスクリプト
#   usage: Scripts/release.sh
#
# 事前準備(初回のみ):
#   1. Developer ID Application 証明書を作成してキーチェーンに入れる
#      Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2. 公証用の認証情報をキーチェーンに保存する
#      xcrun notarytool store-credentials padswitch-notary \
#        --apple-id <Apple ID> --team-id <Team ID>
#      パスワードには https://account.apple.com で発行した app-specific password を使う
set -euo pipefail

cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-padswitch-notary}"
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"

if [ -z "$IDENTITY" ]; then
    echo "error: Developer ID Application 証明書が見つかりません。" >&2
    echo "       このスクリプト冒頭の「事前準備」を参照してください。" >&2
    exit 1
fi

CODESIGN_IDENTITY="$IDENTITY" Scripts/build-app.sh

APP="build/PadSwitch.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
ZIP="build/PadSwitch-${VERSION}.zip"

echo "==> 公証を申請 (完了まで数分待つ)"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> チケットを .app に添付して zip を作り直し"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Gatekeeper 検証"
spctl --assess --type execute -v "$APP"

echo "==> 完了: $ZIP"
echo "    リリースするには: gh release create v${VERSION} $ZIP"

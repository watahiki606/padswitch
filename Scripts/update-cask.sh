#!/bin/bash
# Homebrew tap の cask 定義をリリースに合わせて更新する
#   usage: Scripts/update-cask.sh <version> <zip>
#
# gh の認証に homebrew-tap への書き込み権限が必要。
# CI では TAP_GITHUB_TOKEN を GH_TOKEN として渡す
set -euo pipefail

VERSION="$1"
ZIP="$2"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
TAP_REPO="watahiki606/homebrew-tap"
CASK_PATH="Casks/padswitch.rb"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
cat > "$TMP" <<CASK
cask "padswitch" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/watahiki606/padswitch/releases/download/v#{version}/PadSwitch-#{version}.zip"
  name "PadSwitch"
  desc "Menu bar app for switching a Magic Trackpad between two Macs"
  homepage "https://github.com/watahiki606/padswitch"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "PadSwitch.app"

  zap trash: "~/Library/Application Support/PadSwitch"
end
CASK

# 既存ファイルの blob SHA を渡すと上書き、無ければ新規作成になる
CURRENT_SHA="$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" -q .sha 2>/dev/null || true)"
gh api "repos/$TAP_REPO/contents/$CASK_PATH" --method PUT \
    -f message="padswitch $VERSION" \
    -f content="$(base64 -i "$TMP")" \
    ${CURRENT_SHA:+-f sha="$CURRENT_SHA"} > /dev/null

echo "==> cask を更新: $TAP_REPO padswitch $VERSION"

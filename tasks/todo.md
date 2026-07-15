# Todo

## E2E テスト

- [x] 相手Mac側の Bluetooth 権限(sshd-keygen-wrapper)
- [x] 切り替え方式の確立: 接続中に release(unpair) → 受け取る側が pair + connect
- [x] CLI 直接実行での往復切り替え成功(2026-07-15)
- [ ] アプリの⑤切り替えテストで往復成功(ユーザー確認待ち)
- [ ] 失敗ケースの表示確認(相手スリープ中など)

## 配布(テスト完了後)

- [ ] Developer ID署名 + 公証 (issue #1)
- [ ] Homebrew cask (issue #2)

## Review

- 切り替えの核心は SwitchEngine(検証付きリトライ・失敗時のローカル復旧)
- 相手Mac側は sshd + ~/.padswitch/rc(強制コマンド) + padswitch-cli のみ。常駐なし

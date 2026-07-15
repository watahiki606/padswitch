# PadSwitch

Magic Trackpad の接続先を、2台の Mac 間でワンクリックで切り替えるメニューバーアプリ。

- メニューバーのアイコンをクリックするか、ホットキー ⌥⌘T で切り替え
- Apple アカウントが異なる Mac 同士でも使える
- Apple Silicon 専用

## 使い方

初回のみ、次の準備をする。

1. トラックパッドを両方の Mac に一度ずつ USB-C ケーブルで接続してペアリングする
2. もう一方の Mac でシステム設定を開き、「一般 > 共有 > リモートログイン」を ON にする

続いてアプリの設定画面を、表示される順番どおりに進める。

1. **ステップ1**: トラックパッドを選ぶ
2. **ステップ2**: 相手 Mac のホスト名とユーザー名を入力し、①〜④のボタンを順に実行する
   - ① セットアップコマンドをコピーし、ターミナルに貼り付けて実行する。相手 Mac のパスワードを1回だけ入力する
   - ② 接続テスト
   - ③ 切り替え用プログラムを相手 Mac に配置
   - ④ 相手 Mac の Bluetooth 動作確認。失敗する場合は、相手 Mac の「システム設定 > プライバシーとセキュリティ > Bluetooth」で sshd を許可する
3. **ステップ3**: ログイン時起動を設定し、切り替えテストを実行する

以後はメニューバーのアイコンか ⌥⌘T で切り替えられる。アイコンは塗りつぶしがこの Mac に接続中、枠のみが相手 Mac に接続中を表す。

## ビルド

```sh
Scripts/build-app.sh                       # build/PadSwitch.app を作成
cp -R build/PadSwitch.app /Applications/

swift build && swift test                  # 開発ビルド + テスト
```

## 仕組み

Magic Trackpad は複数の Mac にペアリング情報を保持できるが、接続できるのは同時に1台のみ。切り替えは「現在接続中の Mac が切断 → 相手 Mac が接続」という手順で行う。

相手 Mac 側でのコマンド実行には macOS 標準のリモートログイン、つまり SSH を使う。OS が常時受け付けている仕組みに乗るため、相手 Mac に常駐アプリを置く必要がない。

```
[Mac A: PadSwitch.app]                       [Mac B: リモートログインのみ]
  メニューバー / ホットキー ──── ssh ────▶  ~/.padswitch/rc → padswitch-cli
  ローカルの接続/切断                          セットアップ時に自動配置
```

- 各ステップは結果を検証しながらリトライする。相手 Mac へ渡すのに失敗した場合は自動でこちらに接続し直すため、トラックパッドがどちらからも操作できなくなることはない
- SSH 鍵は専用に生成し、相手側 authorized_keys には restrict と強制コマンド付きで登録する。この鍵ではトラックパッドの切り替えに関する操作しかできない

## CLI

`padswitch-cli` は単体でも使える。

```
padswitch-cli list [--json]        ペアリング済みデバイス一覧
padswitch-cli status <address>     接続状態を表示。exit 0 が接続中、3 が未接続
padswitch-cli connect <address>
padswitch-cli disconnect <address>
```

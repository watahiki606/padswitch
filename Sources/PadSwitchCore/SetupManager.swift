import Foundation

/// 初回セットアップ(SSH 鍵作成・相手 Mac への登録・CLI 配置)を担当する。
///
/// 相手 Mac 側に必要なのは「リモートログイン(SSH)を ON」+「セットアップコマンドを1回ペースト実行」のみ。
/// authorized_keys には restrict + 強制コマンド(~/.padswitch/rc)付きで鍵を登録するため、
/// この鍵では Bluetooth 切り替え関連の操作しかできない。
public enum SetupManager {
    /// SSH 鍵ペアがなければ作成し、公開鍵の内容を返す。
    @discardableResult
    public static func ensureKeyPair() async throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: AppSettings.supportDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if !fm.fileExists(atPath: AppSettings.privateKeyPath) {
            let result = try await ProcessRunner.run(
                "/usr/bin/ssh-keygen",
                ["-t", "ed25519", "-N", "", "-C", "padswitch", "-f", AppSettings.privateKeyPath]
            )
            guard result.exitCode == 0 else {
                throw PadError.commandFailed("SSH鍵の作成に失敗しました: \(result.stderrTrimmed)")
            }
        }
        return try publicKey()
    }

    public static func publicKey() throws -> String {
        guard let key = try? String(contentsOfFile: AppSettings.publicKeyPath, encoding: .utf8) else {
            throw PadError.notConfigured("公開鍵が見つかりません。先に鍵を作成してください。")
        }
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 相手 Mac のターミナルではなく「この Mac のターミナル」に貼り付けて実行するセットアップコマンド。
    /// パスワードを1回入力するだけで、強制コマンド(rc)の設置と公開鍵の登録が完了する。
    public static func setupCommand(user: String, host: String) throws -> String {
        let pubkey = try publicKey()
        return """
        ssh \(user)@\(host) /bin/sh <<'PADSWITCH_SETUP'
        umask 077
        mkdir -p "$HOME/.padswitch" "$HOME/.ssh"
        cat > "$HOME/.padswitch/rc" <<'RC'
        #!/bin/sh
        set -e
        c="$SSH_ORIGINAL_COMMAND"
        case "$c" in
          ping)
            echo pong
            ;;
          install-cli)
            cat > "$HOME/.padswitch/padswitch-cli.tmp"
            chmod 755 "$HOME/.padswitch/padswitch-cli.tmp"
            mv "$HOME/.padswitch/padswitch-cli.tmp" "$HOME/.padswitch/padswitch-cli"
            echo installed
            ;;
          cli\\ *)
            case "$c" in
              *[!A-Za-z0-9\\ :._-]*) echo "invalid arguments" >&2; exit 1 ;;
            esac
            exec "$HOME/.padswitch/padswitch-cli" ${c#cli }
            ;;
          *)
            echo "denied" >&2
            exit 1
            ;;
        esac
        RC
        chmod 700 "$HOME/.padswitch/rc"
        touch "$HOME/.ssh/authorized_keys"
        chmod 600 "$HOME/.ssh/authorized_keys"
        grep -qF "\(pubkey)" "$HOME/.ssh/authorized_keys" || printf '%s\\n' 'restrict,command="$HOME/.padswitch/rc" \(pubkey)' >> "$HOME/.ssh/authorized_keys"
        echo "PadSwitch: セットアップ完了"
        PADSWITCH_SETUP
        """
    }

    /// 専用鍵での疎通確認。強制コマンド経由で "pong" が返れば成功。
    public static func ping(_ remote: SSHRemoteEndpoint) async throws {
        let result = try await remote.run("ping", timeout: 10)
        guard result.stdoutTrimmed == "pong" else {
            throw PadError.commandFailed("応答が不正です: \(result.stdoutTrimmed) \(result.stderrTrimmed)")
        }
    }

    /// アプリに同梱した padswitch-cli を相手 Mac の ~/.padswitch/ へ配置(更新)する。
    public static func deployCLI(_ remote: SSHRemoteEndpoint, cliURL: URL) async throws {
        let data = try Data(contentsOf: cliURL)
        let result = try await remote.run("install-cli", stdin: data, timeout: 60)
        guard result.exitCode == 0, result.stdoutTrimmed == "installed" else {
            throw PadError.commandFailed("CLIの配置に失敗しました: \(result.stderrTrimmed)")
        }
    }

    /// 相手 Mac 上で padswitch-cli が Bluetooth を操作できるか確認する。
    public static func remoteCheck(_ remote: SSHRemoteEndpoint) async throws -> String {
        let result = try await remote.run("cli list", timeout: 15)
        guard result.exitCode == 0 else {
            throw PadError.commandFailed(
                "相手MacでのBluetooth操作に失敗しました。相手Macの「システム設定 > プライバシーとセキュリティ > Bluetooth」で sshd(または sshd-keygen-wrapper)を許可してください。詳細: \(result.stderrTrimmed)"
            )
        }
        return result.stdoutTrimmed
    }

    /// アプリバンドルに同梱された padswitch-cli の場所。
    public static func bundledCLIURL() -> URL? {
        if let url = Bundle.main.url(forResource: "padswitch-cli", withExtension: nil) {
            return url
        }
        // 開発時(swift run): ビルドディレクトリ内の隣にある
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("padswitch-cli")
        return FileManager.default.fileExists(atPath: sibling.path) ? sibling : nil
    }
}

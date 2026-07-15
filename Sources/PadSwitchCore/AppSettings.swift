import Foundation

/// 設定の永続化(UserDefaults)とファイルパス類。
public enum AppSettings {
    static let defaults = UserDefaults.standard

    public static var deviceAddress: String? {
        get { defaults.string(forKey: "deviceAddress") }
        set { defaults.set(newValue, forKey: "deviceAddress") }
    }

    public static var deviceName: String? {
        get { defaults.string(forKey: "deviceName") }
        set { defaults.set(newValue, forKey: "deviceName") }
    }

    public static var remoteHost: String? {
        get { defaults.string(forKey: "remoteHost") }
        set { defaults.set(newValue, forKey: "remoteHost") }
    }

    public static var remoteUser: String? {
        get { defaults.string(forKey: "remoteUser") }
        set { defaults.set(newValue, forKey: "remoteUser") }
    }

    /// SSH 鍵などを置くディレクトリ (~/Library/Application Support/PadSwitch)
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("PadSwitch", isDirectory: true)
    }

    public static var privateKeyPath: String { supportDirectory.appendingPathComponent("id_ed25519").path }
    public static var publicKeyPath: String { privateKeyPath + ".pub" }

    public static func makeRemoteEndpoint() throws -> SSHRemoteEndpoint {
        guard let host = remoteHost, !host.isEmpty, let user = remoteUser, !user.isEmpty else {
            throw PadError.notConfigured("相手のMac(ホスト名とユーザー名)が未設定です。設定画面から登録してください。")
        }
        guard FileManager.default.fileExists(atPath: privateKeyPath) else {
            throw PadError.notConfigured("SSH鍵が未作成です。設定画面のセットアップを実行してください。")
        }
        return SSHRemoteEndpoint(host: host, user: user, keyPath: privateKeyPath)
    }

    public static func makeEngine() throws -> SwitchEngine {
        SwitchEngine(remote: try makeRemoteEndpoint())
    }
}

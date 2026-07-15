import Foundation

/// トラックパッドを操作できる場所(自分の Mac、または SSH 越しの相手の Mac)の抽象。
public protocol PadEndpoint: Sendable {
    var label: String { get }
    func isConnected(_ address: String) async throws -> Bool
    func connect(_ address: String) async throws
    func disconnect(_ address: String) async throws
    /// ペアリングする。トラックパッドが発見可能モードのときのみ成功する
    func pair(_ address: String) async throws
    /// 接続中にペアリング解除してトラックパッドを発見可能モードにする(切り替えの起点)
    func release(_ address: String) async throws
}

/// この Mac 上での Bluetooth 操作。
public struct LocalEndpoint: PadEndpoint {
    public let label = "この Mac"

    public init() {}

    public func isConnected(_ address: String) async throws -> Bool {
        try await runBlocking { try BluetoothController.isConnected(address) }
    }

    public func connect(_ address: String) async throws {
        try await runBlocking { try BluetoothController.connect(address) }
    }

    public func disconnect(_ address: String) async throws {
        try await runBlocking { try BluetoothController.disconnect(address) }
    }

    public func pair(_ address: String) async throws {
        try await runBlocking { try BluetoothController.pair(address) }
    }

    public func release(_ address: String) async throws {
        try await runBlocking { try BluetoothController.release(address) }
    }

    private func runBlocking<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try body())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// SSH 越しに相手 Mac の padswitch-cli を実行するエンドポイント。
///
/// 相手側 authorized_keys の強制コマンド(~/.padswitch/rc)がディスパッチするため、
/// こちらから送るコマンドは "ping" / "install-cli" / "cli <subcommand> <args>" の形式。
public struct SSHRemoteEndpoint: PadEndpoint {
    public let host: String
    public let user: String
    public let keyPath: String
    public var label: String { host }

    /// padswitch-cli status の「未接続」を表す終了コード(接続済みは 0)
    public static let statusDisconnectedExitCode: Int32 = 3

    public init(host: String, user: String, keyPath: String) {
        self.host = host
        self.user = user
        self.keyPath = keyPath
    }

    public func run(_ command: String, stdin: Data? = nil, timeout: TimeInterval = 20) async throws -> ProcessResult {
        let result = try await ProcessRunner.run(
            "/usr/bin/ssh",
            [
                "-i", keyPath,
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=3",
                "-o", "StrictHostKeyChecking=accept-new",
                "\(user)@\(host)",
                command,
            ],
            stdin: stdin,
            timeout: timeout
        )
        // ssh 自体の失敗(認証・到達不可)は 255 を返す
        if result.exitCode == 255 {
            throw PadError.unreachable(result.stderrTrimmed.isEmpty ? "\(host) に接続できません" : result.stderrTrimmed)
        }
        return result
    }

    public func isConnected(_ address: String) async throws -> Bool {
        let result = try await run("cli status \(address)")
        switch result.exitCode {
        case 0: return true
        case Self.statusDisconnectedExitCode: return false
        default:
            throw PadError.commandFailed("相手Macでの状態確認に失敗: \(result.stderrTrimmed)")
        }
    }

    public func connect(_ address: String) async throws {
        // 接続に失敗した場合は相手側で自動ペアリングが走るため、余裕を持たせる
        let result = try await run("cli connect \(address)", timeout: 60)
        guard result.exitCode == 0 else {
            throw PadError.commandFailed("相手Macでの接続に失敗: \(result.stderrTrimmed)")
        }
    }

    public func disconnect(_ address: String) async throws {
        let result = try await run("cli disconnect \(address)")
        guard result.exitCode == 0 else {
            throw PadError.commandFailed("相手Macでの切断に失敗: \(result.stderrTrimmed)")
        }
    }

    public func pair(_ address: String) async throws {
        let result = try await run("cli pair \(address)", timeout: 25)
        guard result.exitCode == 0 else {
            throw PadError.commandFailed("相手Macでのペアリングに失敗: \(result.stderrTrimmed)")
        }
    }

    public func release(_ address: String) async throws {
        let result = try await run("cli release \(address)", timeout: 20)
        guard result.exitCode == 0 else {
            throw PadError.commandFailed("相手Macでのペアリング解除に失敗: \(result.stderrTrimmed)")
        }
    }
}

import Foundation

/// 切り替えの本体。「切断 → 接続 → 検証」を検証付きリトライで実行する。
public struct SwitchEngine: Sendable {
    public enum Location: Sendable, Equatable {
        /// この Mac に接続中
        case here
        /// 相手の Mac に接続中
        case away
        /// どちらにも接続していない(電源 OFF・スリープ等)
        case nowhere
    }

    public struct Status: Sendable, Equatable {
        public let local: Bool
        /// nil = 相手 Mac に到達できず不明
        public let remote: Bool?

        public var location: Location? {
            if local { return .here }
            switch remote {
            case true: return .away
            case false: return .nowhere
            default: return nil
            }
        }
    }

    public let local: any PadEndpoint
    public let remote: any PadEndpoint
    public var connectRetries = 5
    public var retryDelay: TimeInterval = 1.0

    public init(local: any PadEndpoint = LocalEndpoint(), remote: any PadEndpoint) {
        self.local = local
        self.remote = remote
    }

    /// 現在どちらに接続しているか調べる。remote は問い合わせ失敗時 nil。
    public func status(of address: String) async throws -> Status {
        let localConnected = try await local.isConnected(address)
        if localConnected {
            return Status(local: true, remote: false)
        }
        let remoteConnected = try? await remote.isConnected(address)
        return Status(local: false, remote: remoteConnected)
    }

    /// 現在地に応じてトグル。こちらにあれば渡す、なければ取る。切り替え後の場所を返す。
    public func toggle(_ address: String) async throws -> Location {
        let status = try await status(of: address)
        if status.location == .here {
            return try await handoff(address)
        } else {
            return try await take(address)
        }
    }

    /// 渡す: ローカル切断 → 相手が接続(リトライ)。失敗したらローカルに接続し直して復旧。
    public func handoff(_ address: String) async throws -> Location {
        try await local.disconnect(address)

        var lastError: Error = PadError.timeout("相手のMacへの接続に失敗しました")
        for attempt in 1...connectRetries {
            do {
                try await remote.connect(address)
                if try await remote.isConnected(address) {
                    return .away
                }
                lastError = PadError.timeout("相手のMacへの接続が確認できませんでした")
            } catch let error as PadError {
                // SSH 到達不可はリトライしても無駄なので即座に復旧へ
                if case .unreachable = error {
                    try? await local.connect(address)
                    throw error
                }
                lastError = error
            }
            if attempt < connectRetries {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        // 相手が接続できなかった場合、トラックパッドが宙に浮かないよう取り戻す
        try? await local.connect(address)
        throw PadError.timeout("切り替えに失敗したため、トラックパッドをこのMacに戻しました (\((lastError as? PadError)?.errorDescription ?? String(describing: lastError)))")
    }

    /// 取る: 相手が切断(到達不可なら無視して続行) → ローカル接続(リトライ)。
    public func take(_ address: String) async throws -> Location {
        do {
            try await remote.disconnect(address)
        } catch let error as PadError {
            // 相手に到達できなくても、トラックパッドが空いていれば接続できるので続行する
            if case .unreachable = error {} else { throw error }
        }

        var lastError: Error = PadError.timeout("トラックパッドに接続できませんでした")
        for attempt in 1...connectRetries {
            do {
                try await local.connect(address)
                if try await local.isConnected(address) {
                    return .here
                }
            } catch {
                lastError = error
            }
            if attempt < connectRetries {
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }
        throw PadError.timeout("トラックパッドに接続できませんでした。電源と距離を確認してください (\((lastError as? PadError)?.errorDescription ?? String(describing: lastError)))")
    }
}

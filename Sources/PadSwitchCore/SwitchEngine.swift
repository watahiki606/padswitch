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
    public var connectRetries = 6
    public var retryDelay: TimeInterval = 0.5
    /// 接続確認直後の瞬断を成功と誤判定しないための再確認までの待ち時間
    public var stabilityCheckDelay: TimeInterval = 1.0
    /// 切り替え中の進捗をリアルタイムに受け取るコールバック(UI表示用)
    public var onProgress: (@Sendable (String) -> Void)?

    public init(local: any PadEndpoint = LocalEndpoint(), remote: any PadEndpoint) {
        self.local = local
        self.remote = remote
    }

    private func report(_ message: String) {
        Log.switch.info("\(message, privacy: .public)")
        onProgress?(message)
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

    /// 渡す: ローカルで接続中にペアリング解除(トラックパッドが発見可能になる)
    /// → 相手がペアリングして接続(リトライ)。失敗したらローカルにペアリングし直して復旧。
    ///
    /// Magic Trackpad はペアリング情報を1台分しか保持せず、待機中はペアリング要求を
    /// 受け付けない。接続中の解除だけが発見可能モードを誘発するため、この手順になる。
    public func handoff(_ address: String) async throws -> Location {
        report("\(local.label) の接続を解除中…")
        try await local.release(address)

        do {
            try await pairAndConnect(on: remote, address: address)
            return .away
        } catch {
            // 失敗してもトラックパッドはまだ発見可能なはずなので、こちらにペアリングし直す
            let reason = describe(error)
            report("\(remote.label) への切り替えに失敗したため、\(local.label) に戻しています…")
            if await recover(on: local, address: address) {
                throw PadError.timeout("\(local.label) → \(remote.label) の切り替えに失敗したため、トラックパッドを \(local.label) に戻しました。原因: \(reason)")
            }
            throw PadError.timeout("\(local.label) → \(remote.label) の切り替えに失敗し、\(local.label) への再接続もできませんでした。トラックパッドの電源を入れ直してから「このMacに接続する」を実行してください。原因: \(reason)")
        }
    }

    /// 取る: 相手がペアリング解除(到達不可なら発見可能モードを期待して続行)
    /// → ローカルがペアリングして接続(リトライ)。失敗したら相手に戻して復旧。
    public func take(_ address: String) async throws -> Location {
        var remoteReleased = true
        report("\(remote.label) の接続を解除中…")
        do {
            try await remote.release(address)
        } catch let error as PadError {
            // 相手に到達できなくても、トラックパッドが発見可能(電源入れ直し直後など)なら取れる
            if case .unreachable = error {
                remoteReleased = false
                report("\(remote.label) に到達できないため、発見可能モードと仮定して続行します…")
            } else {
                throw error
            }
        }

        do {
            try await pairAndConnect(on: local, address: address)
            return .here
        } catch {
            let reason = describe(error)
            if remoteReleased {
                report("\(local.label) への切り替えに失敗したため、\(remote.label) に戻しています…")
                if await recover(on: remote, address: address) {
                    throw PadError.timeout("\(remote.label) → \(local.label) の切り替えに失敗したため、トラックパッドを \(remote.label) に戻しました。原因: \(reason)")
                }
            }
            throw PadError.timeout("\(remote.label) → \(local.label) の切り替えに失敗しました。トラックパッドの電源を入れ直してから、もう一度「このMacに接続する」を実行してください。原因: \(reason)")
        }
    }

    /// ペアリング→接続→確認を検証付きでリトライする。
    /// 解除直後の1回目のペアリングは失敗しやすいため、リトライが本質的に必要。
    /// 接続確認は一度 true が出ても、瞬断していないか少し待ってから再確認する。
    func pairAndConnect(on endpoint: any PadEndpoint, address: String) async throws {
        var lastError: Error = PadError.timeout("\(endpoint.label) とペアリングできませんでした")
        for attempt in 1...connectRetries {
            report("\(endpoint.label) にペアリング中…(\(attempt)/\(connectRetries)回目)")
            do {
                try await endpoint.pair(address)
                try await endpoint.connect(address)
                if try await endpoint.isConnected(address) {
                    if stabilityCheckDelay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(stabilityCheckDelay * 1_000_000_000))
                    }
                    if try await endpoint.isConnected(address) {
                        report("\(endpoint.label) への接続を確認しました")
                        return
                    }
                    lastError = PadError.timeout("\(endpoint.label) への接続が瞬断しました")
                } else {
                    lastError = PadError.timeout("\(endpoint.label) への接続が確認できませんでした")
                }
            } catch let error as PadError {
                // SSH 到達不可はリトライしても無駄なので即座に中断
                if case .unreachable = error { throw error }
                lastError = error
            } catch {
                lastError = error
            }
            Log.switch.info("pairAndConnect: \(endpoint.label, privacy: .public) 試行\(attempt)失敗 - \(describe(lastError), privacy: .public)")
            if attempt < connectRetries {
                let delay = retryDelay * Double(attempt)
                if delay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError
    }

    /// 切り替え失敗後の復旧。指定側にペアリングし直す。
    private func recover(on endpoint: any PadEndpoint, address: String) async -> Bool {
        (try? await pairAndConnect(on: endpoint, address: address)) != nil
    }

    private func describe(_ error: Error) -> String {
        (error as? PadError)?.errorDescription ?? String(describing: error)
    }
}

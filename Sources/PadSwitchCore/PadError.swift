import Foundation

/// PadSwitch 全体で使うエラー。ユーザーに日本語でそのまま表示できるメッセージを持つ。
public enum PadError: Error, LocalizedError, Equatable {
    /// 相手 Mac に SSH で到達できない(スリープ・ネットワーク断・リモートログイン OFF など)
    case unreachable(String)
    /// コマンドは実行されたが失敗した
    case commandFailed(String)
    /// リトライしても目的の状態にならなかった
    case timeout(String)
    /// 設定が未完了
    case notConfigured(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let s): return "相手のMacに到達できません: \(s)"
        case .commandFailed(let s): return s
        case .timeout(let s): return s
        case .notConfigured(let s): return s
        }
    }
}

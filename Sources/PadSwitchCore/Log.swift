import os

/// アプリ・CLI 共通のロガー。Console.app や `log show` でサブシステム名 `com.watahiki.padswitch` を
/// フィルタすると、切り替え処理で何が起きたかを追跡できる。
enum Log {
    static let `switch` = Logger(subsystem: "com.watahiki.padswitch", category: "switch")
}

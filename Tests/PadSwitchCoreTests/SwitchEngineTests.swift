import XCTest
@testable import PadSwitchCore

/// テスト用のモックエンドポイント。ペアリング・接続状態と失敗を注入できる。
final class MockEndpoint: PadEndpoint, @unchecked Sendable {
    let label: String
    var paired: Bool
    var connected: Bool
    /// pair() を成功させるまでに失敗させる回数
    var pairFailuresRemaining = 0
    /// connect() を成功させるまでに失敗させる回数
    var connectFailuresRemaining = 0
    /// すべての呼び出しを unreachable にする
    var unreachable = false
    /// 接続確認の再確認(stabilityCheckDelay後)で false を返す回数。瞬断の再現に使う
    var flapsRemaining = 0

    private(set) var pairCalls = 0
    private(set) var connectCalls = 0
    private(set) var releaseCalls = 0
    private(set) var disconnectCalls = 0
    private var checksSinceLastConnect = 0

    init(label: String, paired: Bool, connected: Bool) {
        self.label = label
        self.paired = paired
        self.connected = connected
    }

    private func checkReachable() throws {
        if unreachable { throw PadError.unreachable(label) }
    }

    func isConnected(_ address: String) async throws -> Bool {
        try checkReachable()
        checksSinceLastConnect += 1
        // 2回目の確認(安定性の再確認)を、指定回数だけ瞬断として false にする
        if checksSinceLastConnect == 2, flapsRemaining > 0 {
            flapsRemaining -= 1
            connected = false
        }
        return connected
    }

    func connect(_ address: String) async throws {
        try checkReachable()
        connectCalls += 1
        if connectFailuresRemaining > 0 {
            connectFailuresRemaining -= 1
            throw PadError.commandFailed("connect失敗(テスト)")
        }
        guard paired else { throw PadError.commandFailed("未ペアリング(テスト)") }
        connected = true
        checksSinceLastConnect = 0
    }

    func disconnect(_ address: String) async throws {
        try checkReachable()
        disconnectCalls += 1
        connected = false
    }

    func pair(_ address: String) async throws {
        try checkReachable()
        pairCalls += 1
        if pairFailuresRemaining > 0 {
            pairFailuresRemaining -= 1
            throw PadError.commandFailed("pair失敗(テスト)")
        }
        paired = true
    }

    func release(_ address: String) async throws {
        try checkReachable()
        releaseCalls += 1
        paired = false
        connected = false
    }
}

/// onProgress コールバックのメッセージを収集するテスト用ヘルパー。
final class ProgressCollector: @unchecked Sendable {
    private(set) var messages: [String] = []
    func append(_ message: String) { messages.append(message) }
}

final class SwitchEngineTests: XCTestCase {
    let address = "aa-bb-cc-dd-ee-ff"

    func makeEngine(local: MockEndpoint, remote: MockEndpoint) -> SwitchEngine {
        var engine = SwitchEngine(local: local, remote: remote)
        engine.retryDelay = 0
        engine.connectRetries = 4
        engine.stabilityCheckDelay = 0
        return engine
    }

    func testToggleHandsOffWhenConnectedHere() async throws {
        let local = MockEndpoint(label: "local", paired: true, connected: true)
        let remote = MockEndpoint(label: "remote", paired: false, connected: false)
        let engine = makeEngine(local: local, remote: remote)

        let location = try await engine.toggle(address)

        XCTAssertEqual(location, .away)
        XCTAssertEqual(local.releaseCalls, 1)
        XCTAssertTrue(remote.paired)
        XCTAssertTrue(remote.connected)
        XCTAssertFalse(local.connected)
    }

    func testToggleTakesWhenConnectedAway() async throws {
        let local = MockEndpoint(label: "local", paired: false, connected: false)
        let remote = MockEndpoint(label: "remote", paired: true, connected: true)
        let engine = makeEngine(local: local, remote: remote)

        let location = try await engine.toggle(address)

        XCTAssertEqual(location, .here)
        XCTAssertEqual(remote.releaseCalls, 1)
        XCTAssertTrue(local.paired)
        XCTAssertTrue(local.connected)
        XCTAssertFalse(remote.connected)
    }

    func testHandoffRetriesPairingUntilSuccess() async throws {
        // 解除直後の1回目のペアリングは失敗しやすい実挙動を再現
        let local = MockEndpoint(label: "local", paired: true, connected: true)
        let remote = MockEndpoint(label: "remote", paired: false, connected: false)
        remote.pairFailuresRemaining = 2
        let engine = makeEngine(local: local, remote: remote)

        let location = try await engine.handoff(address)

        XCTAssertEqual(location, .away)
        XCTAssertEqual(remote.pairCalls, 3)
    }

    func testHandoffRecoversLocallyWhenRemoteKeepsFailing() async throws {
        let local = MockEndpoint(label: "local", paired: true, connected: true)
        let remote = MockEndpoint(label: "remote", paired: false, connected: false)
        remote.pairFailuresRemaining = 100
        let engine = makeEngine(local: local, remote: remote)

        do {
            _ = try await engine.handoff(address)
            XCTFail("失敗するはず")
        } catch let error as PadError {
            guard case .timeout(let message) = error else { return XCTFail("timeout であるべき: \(error)") }
            XCTAssertTrue(message.contains("戻しました"), "復旧成功が伝わるメッセージであるべき: \(message)")
        }
        // 失敗後はローカルにペアリングし直している
        XCTAssertTrue(local.paired)
        XCTAssertTrue(local.connected)
        XCTAssertEqual(remote.pairCalls, 4)
    }

    func testHandoffReportsWhenRecoveryAlsoFails() async throws {
        let local = MockEndpoint(label: "local", paired: true, connected: true)
        let remote = MockEndpoint(label: "remote", paired: false, connected: false)
        remote.pairFailuresRemaining = 100
        local.pairFailuresRemaining = 100
        let engine = makeEngine(local: local, remote: remote)

        do {
            _ = try await engine.handoff(address)
            XCTFail("失敗するはず")
        } catch let error as PadError {
            guard case .timeout(let message) = error else { return XCTFail("timeout であるべき: \(error)") }
            XCTAssertTrue(message.contains("再接続もできませんでした"), "復旧失敗が伝わるメッセージであるべき: \(message)")
            XCTAssertFalse(message.contains("戻しました。"), "戻せていないのに戻したと言ってはいけない: \(message)")
        }
        XCTAssertFalse(local.connected)
    }

    func testHandoffAbortsImmediatelyWhenRemoteUnreachable() async throws {
        let local = MockEndpoint(label: "local", paired: true, connected: true)
        let remote = MockEndpoint(label: "remote", paired: false, connected: false)
        remote.unreachable = true
        let engine = makeEngine(local: local, remote: remote)

        do {
            _ = try await engine.handoff(address)
            XCTFail("失敗するはず")
        } catch let error as PadError {
            guard case .timeout(let message) = error else { return XCTFail("timeout であるべき: \(error)") }
            XCTAssertTrue(message.contains("戻しました"), "復旧成功が伝わるメッセージであるべき: \(message)")
        }
        // 到達不可はリトライせず、即座にローカルへ復旧している
        XCTAssertEqual(remote.pairCalls, 0)
        XCTAssertTrue(local.connected)
    }

    func testTakeProceedsWhenRemoteUnreachable() async throws {
        // 相手Macがスリープしていても、トラックパッドが発見可能なら取れる
        let local = MockEndpoint(label: "local", paired: false, connected: false)
        let remote = MockEndpoint(label: "remote", paired: true, connected: false)
        remote.unreachable = true
        let engine = makeEngine(local: local, remote: remote)

        let location = try await engine.take(address)

        XCTAssertEqual(location, .here)
        XCTAssertTrue(local.connected)
    }

    func testTakeRecoversToRemoteWhenLocalPairingFails() async throws {
        let local = MockEndpoint(label: "local", paired: false, connected: false)
        let remote = MockEndpoint(label: "remote", paired: true, connected: true)
        local.pairFailuresRemaining = 100
        let engine = makeEngine(local: local, remote: remote)

        do {
            _ = try await engine.take(address)
            XCTFail("失敗するはず")
        } catch let error as PadError {
            guard case .timeout(let message) = error else { return XCTFail("timeout であるべき: \(error)") }
            XCTAssertTrue(message.contains("戻しました"), "相手側への復旧が伝わるメッセージであるべき: \(message)")
        }
        // 相手側にペアリングし直している
        XCTAssertTrue(remote.paired)
        XCTAssertTrue(remote.connected)
    }

    func testHandoffRetriesWhenConnectionFlapsAfterStabilityCheck() async throws {
        // isConnected() が一度 true を返した直後に瞬断するケースを再現する
        let local = MockEndpoint(label: "local", paired: true, connected: true)
        let remote = MockEndpoint(label: "remote", paired: false, connected: false)
        remote.flapsRemaining = 2
        let engine = makeEngine(local: local, remote: remote)

        let location = try await engine.handoff(address)

        XCTAssertEqual(location, .away)
        XCTAssertEqual(remote.pairCalls, 3)
        XCTAssertTrue(remote.connected)
    }

    func testHandoffReportsProgress() async throws {
        let local = MockEndpoint(label: "local", paired: true, connected: true)
        let remote = MockEndpoint(label: "remote", paired: false, connected: false)
        var engine = makeEngine(local: local, remote: remote)
        let collector = ProgressCollector()
        engine.onProgress = { collector.append($0) }

        _ = try await engine.handoff(address)

        XCTAssertTrue(collector.messages.contains { $0.contains("解除中") })
        XCTAssertTrue(collector.messages.contains { $0.contains("ペアリング中") })
        XCTAssertTrue(collector.messages.contains { $0.contains("確認しました") })
    }

    func testStatusNowhere() async throws {
        let local = MockEndpoint(label: "local", paired: true, connected: false)
        let remote = MockEndpoint(label: "remote", paired: false, connected: false)
        let engine = makeEngine(local: local, remote: remote)

        let status = try await engine.status(of: address)

        XCTAssertEqual(status.location, .nowhere)
    }

    func testStatusUnknownWhenRemoteUnreachable() async throws {
        let local = MockEndpoint(label: "local", paired: true, connected: false)
        let remote = MockEndpoint(label: "remote", paired: false, connected: false)
        remote.unreachable = true
        let engine = makeEngine(local: local, remote: remote)

        let status = try await engine.status(of: address)

        XCTAssertNil(status.location)
    }
}

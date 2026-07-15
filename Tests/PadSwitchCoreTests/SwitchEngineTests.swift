import XCTest
@testable import PadSwitchCore

/// テスト用のモックエンドポイント。接続状態と失敗を注入できる。
final class MockEndpoint: PadEndpoint, @unchecked Sendable {
    let label: String
    var connected: Bool
    /// connect() を成功させるまでに失敗させる回数
    var connectFailuresRemaining = 0
    /// すべての呼び出しを unreachable にする
    var unreachable = false

    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0

    init(label: String, connected: Bool) {
        self.label = label
        self.connected = connected
    }

    private func checkReachable() throws {
        if unreachable { throw PadError.unreachable(label) }
    }

    func isConnected(_ address: String) async throws -> Bool {
        try checkReachable()
        return connected
    }

    func connect(_ address: String) async throws {
        try checkReachable()
        connectCalls += 1
        if connectFailuresRemaining > 0 {
            connectFailuresRemaining -= 1
            throw PadError.commandFailed("connect失敗(テスト)")
        }
        connected = true
    }

    func disconnect(_ address: String) async throws {
        try checkReachable()
        disconnectCalls += 1
        connected = false
    }
}

final class SwitchEngineTests: XCTestCase {
    let address = "aa-bb-cc-dd-ee-ff"

    func makeEngine(local: MockEndpoint, remote: MockEndpoint) -> SwitchEngine {
        var engine = SwitchEngine(local: local, remote: remote)
        engine.retryDelay = 0
        return engine
    }

    func testToggleHandsOffWhenConnectedHere() async throws {
        let local = MockEndpoint(label: "local", connected: true)
        let remote = MockEndpoint(label: "remote", connected: false)
        let engine = makeEngine(local: local, remote: remote)

        let location = try await engine.toggle(address)

        XCTAssertEqual(location, .away)
        XCTAssertEqual(local.disconnectCalls, 1)
        XCTAssertTrue(remote.connected)
        XCTAssertFalse(local.connected)
    }

    func testToggleTakesWhenConnectedAway() async throws {
        let local = MockEndpoint(label: "local", connected: false)
        let remote = MockEndpoint(label: "remote", connected: true)
        let engine = makeEngine(local: local, remote: remote)

        let location = try await engine.toggle(address)

        XCTAssertEqual(location, .here)
        XCTAssertEqual(remote.disconnectCalls, 1)
        XCTAssertTrue(local.connected)
    }

    func testHandoffRetriesUntilSuccess() async throws {
        let local = MockEndpoint(label: "local", connected: true)
        let remote = MockEndpoint(label: "remote", connected: false)
        remote.connectFailuresRemaining = 3
        let engine = makeEngine(local: local, remote: remote)

        let location = try await engine.handoff(address)

        XCTAssertEqual(location, .away)
        XCTAssertEqual(remote.connectCalls, 4)
    }

    func testHandoffRecoversLocallyWhenRemoteKeepsFailing() async throws {
        let local = MockEndpoint(label: "local", connected: true)
        let remote = MockEndpoint(label: "remote", connected: false)
        remote.connectFailuresRemaining = 100
        let engine = makeEngine(local: local, remote: remote)

        do {
            _ = try await engine.handoff(address)
            XCTFail("失敗するはず")
        } catch let error as PadError {
            guard case .timeout = error else { return XCTFail("timeout であるべき: \(error)") }
        }
        // 失敗後はローカルに取り戻している
        XCTAssertTrue(local.connected)
        XCTAssertEqual(remote.connectCalls, 5)
    }

    func testHandoffAbortsImmediatelyWhenRemoteUnreachable() async throws {
        let local = MockEndpoint(label: "local", connected: true)
        let remote = MockEndpoint(label: "remote", connected: false)
        remote.unreachable = true
        let engine = makeEngine(local: local, remote: remote)

        do {
            _ = try await engine.handoff(address)
            XCTFail("失敗するはず")
        } catch let error as PadError {
            guard case .unreachable = error else { return XCTFail("unreachable であるべき: \(error)") }
        }
        // リトライせず即座に復旧している
        XCTAssertEqual(remote.connectCalls, 0)
        XCTAssertTrue(local.connected)
    }

    func testTakeProceedsWhenRemoteUnreachable() async throws {
        // 相手Macがスリープしていても、トラックパッドが空いていれば取れる
        let local = MockEndpoint(label: "local", connected: false)
        let remote = MockEndpoint(label: "remote", connected: false)
        remote.unreachable = true
        let engine = makeEngine(local: local, remote: remote)

        let location = try await engine.take(address)

        XCTAssertEqual(location, .here)
        XCTAssertTrue(local.connected)
    }

    func testStatusNowhere() async throws {
        let local = MockEndpoint(label: "local", connected: false)
        let remote = MockEndpoint(label: "remote", connected: false)
        let engine = makeEngine(local: local, remote: remote)

        let status = try await engine.status(of: address)

        XCTAssertEqual(status.location, .nowhere)
    }

    func testStatusUnknownWhenRemoteUnreachable() async throws {
        let local = MockEndpoint(label: "local", connected: false)
        let remote = MockEndpoint(label: "remote", connected: false)
        remote.unreachable = true
        let engine = makeEngine(local: local, remote: remote)

        let status = try await engine.status(of: address)

        XCTAssertNil(status.location)
    }
}

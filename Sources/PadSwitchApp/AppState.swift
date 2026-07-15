import SwiftUI
import ServiceManagement
import UserNotifications
import PadSwitchCore

@MainActor
final class AppState: ObservableObject {
    @Published var deviceAddress: String = AppSettings.deviceAddress ?? "" {
        didSet { AppSettings.deviceAddress = deviceAddress }
    }
    @Published var deviceName: String = AppSettings.deviceName ?? "" {
        didSet { AppSettings.deviceName = deviceName }
    }
    @Published var remoteHost: String = AppSettings.remoteHost ?? "" {
        didSet { AppSettings.remoteHost = remoteHost }
    }
    @Published var remoteUser: String = AppSettings.remoteUser ?? "" {
        didSet { AppSettings.remoteUser = remoteUser }
    }

    @Published var location: SwitchEngine.Location?
    @Published var busy = false
    @Published var lastError: String?

    private var refreshTimer: Timer?
    private var hotkey: Hotkey?

    init() {
        hotkey = Hotkey { [weak self] in
            Task { @MainActor in await self?.toggle() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLocal() }
        }
        Task { await refreshLocal() }
    }

    var isConfigured: Bool {
        !deviceAddress.isEmpty && !remoteHost.isEmpty && !remoteUser.isEmpty
    }

    var iconSymbol: String {
        if busy { return "rectangle.dashed" }
        if lastError != nil { return "exclamationmark.triangle" }
        switch location {
        case .here: return "rectangle.inset.filled"
        case .away: return "rectangle"
        case .nowhere: return "rectangle.slash"
        case nil: return "rectangle.dashed"
        }
    }

    var statusText: String {
        guard isConfigured else { return "未設定(設定を開いてください)" }
        let device = deviceName.isEmpty ? "トラックパッド" : deviceName
        if busy { return "切り替え中…" }
        switch location {
        case .here: return "\(device): このMacに接続中"
        case .away: return "\(device): \(remoteHost) に接続中"
        case .nowhere: return "\(device): どちらにも未接続"
        case nil: return "\(device): 状態不明"
        }
    }

    var toggleTitle: String {
        switch location {
        case .here: return "\(remoteHost) に渡す"
        case .away, .nowhere: return "このMacに接続する"
        case nil: return "切り替える"
        }
    }

    /// ローカルの接続状態だけを安価に確認する(定期実行用。SSH は発生させない)。
    func refreshLocal() async {
        guard !deviceAddress.isEmpty, !busy else { return }
        guard let connected = try? await LocalEndpoint().isConnected(deviceAddress) else { return }
        if connected {
            location = .here
        } else if location == .here {
            // こちらから離れたが行き先は不明
            location = nil
        }
    }

    /// SSH も使ってどちらに接続しているかを確認する(メニューの「状態を更新」用)。
    func refreshFull() async {
        guard isConfigured, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let engine = try AppSettings.makeEngine()
            location = try await engine.status(of: deviceAddress).location
            lastError = nil
        } catch {
            lastError = errorMessage(error)
        }
    }

    func toggle() async {
        guard !busy else { return }
        guard isConfigured else {
            lastError = "設定が未完了です。設定画面からセットアップしてください。"
            return
        }
        busy = true
        defer { busy = false }
        do {
            let engine = try AppSettings.makeEngine()
            let newLocation = try await engine.toggle(deviceAddress)
            location = newLocation
            lastError = nil
            notify(newLocation == .here ? "トラックパッドをこのMacに接続しました" : "トラックパッドを \(remoteHost) に渡しました")
        } catch {
            lastError = errorMessage(error)
            // 失敗後の実際の位置を反映しておく
            if let connected = try? await LocalEndpoint().isConnected(deviceAddress) {
                location = connected ? .here : nil
            }
            notify("切り替えに失敗しました: \(lastError ?? "")")
        }
    }

    // MARK: - ログイン時に起動

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        objectWillChange.send()
    }

    // MARK: - private

    private func errorMessage(_ error: Error) -> String {
        (error as? PadError)?.errorDescription ?? error.localizedDescription
    }

    private var notificationPermissionRequested = false

    private func notify(_ message: String) {
        // .app バンドル外(swift run)では UNUserNotificationCenter が使えない
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundlePath.hasSuffix(".app") else { return }
        let center = UNUserNotificationCenter.current()
        let send = {
            let content = UNMutableNotificationContent()
            content.title = "PadSwitch"
            content.body = message
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
        if notificationPermissionRequested {
            send()
        } else {
            notificationPermissionRequested = true
            center.requestAuthorization(options: [.alert]) { granted, _ in
                if granted { send() }
            }
        }
    }
}

import SwiftUI
import AppKit
import PadSwitchCore

/// セットアップ手順の各ステップの実行状態
enum StepState: Equatable {
    case idle
    case running
    case ok(String = "完了")
    case fail(String)
}

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    @State private var devices: [BTDevice] = []
    @State private var copyStep: StepState = .idle
    @State private var pingStep: StepState = .idle
    @State private var deployStep: StepState = .idle
    @State private var checkStep: StepState = .idle
    @State private var testStep: StepState = .idle
    @State private var launchAtLogin = false

    var body: some View {
        Form {
            deviceSection
            remoteSection
            behaviorSection
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .frame(minHeight: 640)
        .task {
            reloadDevices()
            launchAtLogin = state.launchAtLogin
        }
    }

    // MARK: - 1. トラックパッド

    private var deviceSection: some View {
        Section {
            if devices.isEmpty {
                Text("ペアリング済みのBluetoothデバイスが見つかりません。トラックパッドをUSB-CケーブルでこのMacに一度接続してペアリングしてください。")
                    .foregroundStyle(.secondary)
            } else {
                Picker("トラックパッド", selection: $state.deviceAddress) {
                    Text("未選択").tag("")
                    ForEach(devices) { device in
                        Text("\(device.name) (\(device.address))\(device.isTrackpad ? "" : " ※トラックパッド以外")")
                            .tag(device.address)
                    }
                }
                .onChange(of: state.deviceAddress) { _, newValue in
                    state.deviceName = devices.first { $0.address == newValue }?.name ?? ""
                }
            }
            Button("一覧を更新") { reloadDevices() }
        } header: {
            Text("ステップ1: トラックパッドを選ぶ")
        } footer: {
            Text("前提: トラックパッドは両方のMacに一度ずつUSB-Cケーブルで接続し、ペアリングを済ませておいてください(初回のみ)。")
        }
    }

    // MARK: - 2. 相手の Mac

    private var remoteSection: some View {
        Section {
            TextField("ホスト名 / IPアドレス", text: $state.remoteHost, prompt: Text("例: MacBook-Pro.local"))
                .autocorrectionDisabled()
            TextField("ユーザー名", text: $state.remoteUser, prompt: Text("相手Macのログインユーザー名"))
                .autocorrectionDisabled()

            stepRow(number: "①", title: "セットアップコマンドをコピー", step: copyStep, buttonTitle: "コピー") {
                await runStep(into: { copyStep = $0 }) {
                    try await SetupManager.ensureKeyPair()
                    let command = try SetupManager.setupCommand(user: state.remoteUser, host: state.remoteHost)
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(command, forType: .string)
                    return "コピーしました。ターミナル.app に貼り付けて実行し、相手Macのパスワードを入力してください(初回のみ)"
                }
            }
            stepRow(number: "②", title: "接続テスト", step: pingStep, buttonTitle: "テスト") {
                await runStep(into: { pingStep = $0 }) {
                    try await SetupManager.ping(AppSettings.makeRemoteEndpoint())
                    return "SSH接続OK"
                }
            }
            stepRow(number: "③", title: "切り替え用CLIを相手Macに配置", step: deployStep, buttonTitle: "配置") {
                await runStep(into: { deployStep = $0 }) {
                    guard let cliURL = SetupManager.bundledCLIURL() else {
                        throw PadError.notConfigured("同梱のpadswitch-cliが見つかりません(アプリを.appとしてビルドしてください)")
                    }
                    try await SetupManager.deployCLI(AppSettings.makeRemoteEndpoint(), cliURL: cliURL)
                    return "配置しました"
                }
            }
            stepRow(number: "④", title: "相手MacのBluetooth動作確認", step: checkStep, buttonTitle: "確認") {
                await runStep(into: { checkStep = $0 }) {
                    let list = try await SetupManager.remoteCheck(AppSettings.makeRemoteEndpoint())
                    let paired = list.contains(state.deviceAddress)
                        ? "OK(トラックパッドは相手Macにもペアリング済み)"
                        : "動作OK。ただし選択中のトラックパッドが相手Macにペアリングされていません。ケーブルで一度接続してください"
                    return paired
                }
            }
        } header: {
            Text("ステップ2: 相手のMacを登録する")
        } footer: {
            Text("相手のMacでは「システム設定 > 一般 > 共有 > リモートログイン」をONにしておいてください。アプリのインストールは不要です。登録される鍵は切り替え操作専用に制限されます。")
        }
    }

    // MARK: - 3. 動作設定

    private var behaviorSection: some View {
        Section {
            LabeledContent("切り替えホットキー", value: "⌥⌘T")

            Toggle("ログイン時にPadSwitchを起動", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try state.setLaunchAtLogin(newValue)
                    } catch {
                        launchAtLogin = state.launchAtLogin
                    }
                }

            stepRow(number: "⑤", title: "切り替えテスト(1回切り替えます)", step: testStep, buttonTitle: "実行") {
                await runStep(into: { testStep = $0 }) {
                    await state.toggle()
                    if let error = state.lastError {
                        throw PadError.commandFailed(error)
                    }
                    return state.location == .here ? "このMacに接続しました" : "相手のMacに切り替えました"
                }
            }
        } header: {
            Text("ステップ3: 動作を確認する")
        } footer: {
            Text("以後はメニューバーのアイコンをクリックするか、ホットキーで切り替えられます。")
        }
    }

    // MARK: - helpers

    private func reloadDevices() {
        // Bluetooth許可待ちなどでブロックしてもUIが固まらないようバックグラウンドで実行する
        Task {
            devices = await Task.detached { BluetoothController.pairedDevices() }.value
        }
    }

    @ViewBuilder
    private func stepRow(
        number: String,
        title: String,
        step: StepState,
        buttonTitle: String,
        action: @escaping () async -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(number) \(title)")
                Spacer()
                if step == .running {
                    ProgressView().controlSize(.small)
                }
                Button(buttonTitle) {
                    Task { await action() }
                }
                .disabled(step == .running)
            }
            switch step {
            case .ok(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            case .fail(let message):
                Label(message, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            default:
                EmptyView()
            }
        }
    }

    private func runStep(
        into setStep: @escaping (StepState) -> Void,
        body: @escaping () async throws -> String
    ) async {
        setStep(.running)
        do {
            setStep(.ok(try await body()))
        } catch {
            let message = (error as? PadError)?.errorDescription ?? error.localizedDescription
            setStep(.fail(message))
        }
    }
}

import SwiftUI

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(state.statusText)

        if let error = state.lastError {
            Text("⚠️ \(error)")
        }

        Divider()

        Button(state.toggleTitle) {
            Task { await state.toggle() }
        }
        .disabled(!state.isConfigured || state.busy)

        Button("状態を更新") {
            Task { await state.refreshFull() }
        }
        .disabled(!state.isConfigured || state.busy)

        Divider()

        Button("設定…") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("PadSwitch を終了") {
            NSApp.terminate(nil)
        }
    }
}

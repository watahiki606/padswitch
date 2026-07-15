import SwiftUI

@main
struct PadSwitchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(state)
        } label: {
            Image(systemName: state.iconSymbol)
        }

        Window("PadSwitch 設定", id: "settings") {
            SettingsView()
                .environmentObject(state)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

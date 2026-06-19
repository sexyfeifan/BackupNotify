import SwiftUI

@main
struct BackupNotifyApp: App {
    @StateObject private var engine = MonitorEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine)
        } label: {
            Label("BackupNotify", systemImage: "externaldrive.badge.checkmark")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: engine)
        }
    }
}

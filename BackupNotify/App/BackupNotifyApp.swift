import SwiftUI

@main
struct BackupNotifyApp: App {
    @StateObject private var engine = MonitorEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(engine: engine)
                .onAppear {
                    // Auto-start engine if monitors are configured
                    if !engine.isRunning {
                        let config = ConfigStore.shared.load()
                        if config.monitors.contains(where: { $0.enabled }) {
                            engine.start()
                        }
                    }
                    // Request local notification permission
                    LocalNotifier.requestAuthorization()
                }
        } label: {
            Label("BackupNotify", systemImage: "externaldrive.badge.checkmark")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(engine: engine)
        }
    }
}

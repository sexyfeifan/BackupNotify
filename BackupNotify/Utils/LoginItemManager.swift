import Foundation
import ServiceManagement

/// Manages login item (launch at login) using SMAppService.
enum LoginItemManager {

    /// Check if the app is set to launch at login.
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// Enable or disable launch at login.
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger.shared.error("LoginItemManager failed: \(error.localizedDescription)")
            }
        }
    }
}

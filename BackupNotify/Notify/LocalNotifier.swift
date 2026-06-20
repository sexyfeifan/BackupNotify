import Foundation
import UserNotifications

/// Handles macOS local notifications (Notification Center).
enum LocalNotifier {

    /// Request notification authorization from the user.
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                Logger.shared.warning("Local notification authorization error: \(error.localizedDescription)")
            }
            if granted {
                Logger.shared.info("Local notification authorization granted")
            } else {
                Logger.shared.info("Local notification authorization denied")
            }
        }
    }

    /// Check if local notifications are authorized.
    static func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    /// Send a local notification for a backup event.
    static func notify(event: BackupEvent) {
        let content = UNMutableNotificationContent()
        content.title = "备份报告 — \(event.folderName)"
        content.subtitle = event.monitorName
        content.body = "大小: \(ByteFormatter.string(fromByteCount: event.totalSizeBytes)) · \(event.fileCount) 个文件"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                Logger.shared.error("Failed to deliver local notification: \(error.localizedDescription)")
            }
        }
    }
}

import Foundation

// MARK: - Configuration Models

enum WebhookPlatform: String, Codable, CaseIterable {
    case feishu
    case dingtalk
    case wecom
    case slack
    case discord
    case custom

    var displayName: String {
        switch self {
        case .feishu:   return "飞书"
        case .dingtalk: return "钉钉"
        case .wecom:    return "企业微信"
        case .slack:    return "Slack"
        case .discord:  return "Discord"
        case .custom:   return "自定义"
        }
    }
}

struct AppConfig: Codable {
    var monitors: [MonitorConfig]
    var webhooks: [WebhookConfig]
    var pollingInterval: TimeInterval
    var scanDepth: Int
    var videoExtensions: [String]
    var quietHours: QuietHours?
    var launchAtLogin: Bool
    var logRetentionDays: Int
    var enableLocalNotification: Bool

    static var `default`: AppConfig {
        AppConfig(
            monitors: [],
            webhooks: [],
            pollingInterval: 300,
            scanDepth: 1,
            videoExtensions: [
                "mov", "mp4", "mxf", "r3d", "ari", "braw", "crm",
                "cinema", "dnx", "prores", "mkv", "avi", "ts", "mts", "m2ts"
            ],
            quietHours: nil,
            launchAtLogin: false,
            logRetentionDays: 14,
            enableLocalNotification: true
        )
    }
}

struct MonitorConfig: Codable, Identifiable {
    var id: UUID
    var path: String
    var name: String
    var enabled: Bool
    var excludePatterns: [String]

    init(id: UUID = UUID(), path: String, name: String, enabled: Bool = true, excludePatterns: [String] = []) {
        self.id = id
        self.path = path
        self.name = name
        self.enabled = enabled
        self.excludePatterns = excludePatterns
    }
}

struct WebhookConfig: Codable, Identifiable {
    var id: UUID
    var url: String
    var name: String
    var platform: WebhookPlatform
    var enabled: Bool
    var customTemplate: String?

    init(id: UUID = UUID(), url: String, name: String, platform: WebhookPlatform = .custom, enabled: Bool = true, customTemplate: String? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.platform = platform
        self.enabled = enabled
        self.customTemplate = customTemplate
    }
}

struct QuietHours: Codable {
    var enabled: Bool
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
}

// MARK: - Snapshot Model

struct DirectorySnapshot: Codable {
    var monitorId: UUID
    var timestamp: Date
    var knownFolders: Set<String>
}

// MARK: - Event Model

struct BackupEvent: Codable, Identifiable {
    var id: UUID
    var monitorId: UUID
    var monitorName: String
    var folderName: String
    var folderPath: String
    var createdAt: Date
    var modifiedAt: Date
    var totalSizeBytes: UInt64
    var fileCount: Int
    var videoCount: Int
    var videoSizeBytes: UInt64
    var videoExtensions: [String]
    var levels: [LevelInfo]
    var notifiedAt: Date
    var webhookResults: [WebhookResult]
}

struct LevelInfo: Codable {
    var relativePath: String
    var sizeBytes: UInt64
}

struct WebhookResult: Codable {
    var webhookId: UUID
    var webhookName: String
    var success: Bool
    var statusCode: Int?
    var error: String?
    var sentAt: Date
}

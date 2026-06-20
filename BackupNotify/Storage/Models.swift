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

    /// Convenience alias used by MonitorEngine timer setup.
    var pollingIntervalSeconds: TimeInterval { pollingInterval }

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
    var depth: Int
    var excludePatterns: [String]

    init(
        id: UUID = UUID(),
        path: String,
        name: String,
        enabled: Bool = true,
        depth: Int = 1,
        excludePatterns: [String] = []
    ) {
        self.id = id
        self.path = path
        self.name = name
        self.enabled = enabled
        self.depth = depth
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

    init(
        id: UUID = UUID(),
        url: String,
        name: String,
        platform: WebhookPlatform = .custom,
        enabled: Bool = true,
        customTemplate: String? = nil
    ) {
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

// MARK: - File Tree Entry

/// A single node in the complete file tree (file or directory).
struct FileEntry: Codable, Identifiable {
    var id: UUID
    var name: String
    var relativePath: String
    var sizeBytes: UInt64
    var isDirectory: Bool
    var depth: Int
    var childCount: Int  // number of direct children (files only, for directories)

    init(
        id: UUID = UUID(),
        name: String,
        relativePath: String,
        sizeBytes: UInt64,
        isDirectory: Bool,
        depth: Int,
        childCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.depth = depth
        self.childCount = childCount
    }
}

// MARK: - Event Model

/// Canonical LevelInfo — single source of truth.
/// Contains `id` for Identifiable conformance and `fileCount` for display.
struct LevelInfo: Codable, Identifiable, Hashable {
    var id: UUID
    var relativePath: String
    var sizeBytes: UInt64
    var fileCount: Int

    init(
        id: UUID = UUID(),
        relativePath: String,
        sizeBytes: UInt64,
        fileCount: Int = 0
    ) {
        self.id = id
        self.relativePath = relativePath
        self.sizeBytes = sizeBytes
        self.fileCount = fileCount
    }
}

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
    var fileEntries: [FileEntry]
    var notifiedAt: Date
    var webhookResults: [WebhookResult]

    /// Full memberwise initializer with sensible defaults.
    init(
        id: UUID = UUID(),
        monitorId: UUID,
        monitorName: String,
        folderName: String,
        folderPath: String,
        createdAt: Date,
        modifiedAt: Date,
        totalSizeBytes: UInt64,
        fileCount: Int,
        videoCount: Int,
        videoSizeBytes: UInt64,
        videoExtensions: [String],
        levels: [LevelInfo],
        fileEntries: [FileEntry] = [],
        notifiedAt: Date = Date(),
        webhookResults: [WebhookResult] = []
    ) {
        self.id = id
        self.monitorId = monitorId
        self.monitorName = monitorName
        self.folderName = folderName
        self.folderPath = folderPath
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.totalSizeBytes = totalSizeBytes
        self.fileCount = fileCount
        self.videoCount = videoCount
        self.videoSizeBytes = videoSizeBytes
        self.videoExtensions = videoExtensions
        self.levels = levels
        self.fileEntries = fileEntries
        self.notifiedAt = notifiedAt
        self.webhookResults = webhookResults
    }

    /// Convenience factory: create from a FolderInfo analysis result.
    init(
        monitorId: UUID,
        monitorName: String,
        folderInfo: FolderInfo,
        notifiedAt: Date = Date()
    ) {
        self.init(
            monitorId: monitorId,
            monitorName: monitorName,
            folderName: folderInfo.name,
            folderPath: folderInfo.path,
            createdAt: folderInfo.createdAt,
            modifiedAt: folderInfo.modifiedAt,
            totalSizeBytes: folderInfo.totalSizeBytes,
            fileCount: folderInfo.fileCount,
            videoCount: folderInfo.videoCount,
            videoSizeBytes: folderInfo.videoSizeBytes,
            videoExtensions: folderInfo.videoExtensions,
            levels: folderInfo.levels,
            fileEntries: folderInfo.fileEntries,
            notifiedAt: notifiedAt
        )
    }
}

struct WebhookResult: Codable {
    var webhookId: UUID
    var webhookName: String
    var success: Bool
    var statusCode: Int?
    var error: String?
    var sentAt: Date
}

// MARK: - Shared Constants

/// macOS system files/directories to skip during scanning.
/// Single source of truth — used by DirectoryScanner, FolderAnalyzer,
/// LevelSizeCalculator, VideoDetector, and MonitorEngine.
enum SystemFiles {
    static let names: Set<String> = [
        ".DS_Store",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        ".VolumeIcon.icns",
        ".DocumentRevisions-V100",
        ".PKInstallSandboxManager",
        ".PKInstallSandboxManager-SystemSoftware"
    ]

    static func contains(_ name: String) -> Bool {
        names.contains(name)
    }
}

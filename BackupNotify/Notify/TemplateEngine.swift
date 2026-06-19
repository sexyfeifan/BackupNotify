import Foundation

// MARK: - NotificationTemplate Protocol

/// Unified protocol for all platform-specific notification templates.
/// Eliminates the switch-based dispatch and enables OCP-compliant extension.
protocol NotificationTemplate {
    /// Render a backup event into a platform-specific JSON payload.
    static func render(event: BackupEvent) -> Data
}

// MARK: - TemplateHelpers

/// Shared helpers for all template implementations.
/// Eliminates the 7× duplication of `serialize` and repeated level formatting.
enum TemplateHelpers {

    /// Serialize a JSON-compatible dictionary to Data.
    static func serialize(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: StorageUtils.jsonOptions)) ?? Data()
    }

    /// Format levels as human-readable bullet list (used by templates).
    static func formatLevelsText(_ levels: [LevelInfo], bullet: String = "•") -> String {
        guard !levels.isEmpty else { return "" }
        return levels.map { level in
            "\(bullet) \(level.relativePath) — \(ByteFormatter.string(fromByteCount: Int64(level.sizeBytes)))"
        }.joined(separator: "\n")
    }

    /// Sanitize a string for safe insertion into JSON/Markdown payloads.
    /// Escapes characters that could break payload structure.
    static func sanitize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

// MARK: - RenderedPayload

/// The output of TemplateEngine.render — body, headers, and metadata.
struct RenderedPayload {
    let body: Data
    let headers: [String: String]
}

// MARK: - TemplateEngine

/// Renders a `BackupEvent` into platform-specific JSON payloads
/// and applies custom template variable substitution.
struct TemplateEngine {

    /// Registry of built-in templates keyed by platform.
    /// To add a new platform: (1) create a struct conforming to NotificationTemplate,
    /// (2) add a case to WebhookPlatform, (3) register here.
    private static let registry: [WebhookPlatform: NotificationTemplate.Type] = [
        .feishu:   FeishuTemplate.self,
        .dingtalk: DingTalkTemplate.self,
        .wecom:    WeComTemplate.self,
        .slack:    SlackTemplate.self,
        .discord:  DiscordTemplate.self,
    ]

    /// Render a BackupEvent into the appropriate format for the given platform.
    func render(
        event: BackupEvent,
        platform: WebhookPlatform,
        customTemplate: String?
    ) -> RenderedPayload {
        // Custom platform with user template → variable substitution
        if platform == .custom, let custom = customTemplate, !custom.isEmpty {
            let rendered = applyCustomTemplate(custom, event: event)
            let body = rendered.data(using: .utf8) ?? Data()
            return RenderedPayload(body: body, headers: defaultHeaders)
        }

        // Look up registered template
        if let templateType = Self.registry[platform] {
            let body = templateType.render(event: event)
            return RenderedPayload(body: body, headers: defaultHeaders)
        }

        // Fallback: generic JSON payload for .custom without template
        let body = buildGenericPayload(event: event)
        return RenderedPayload(body: body, headers: defaultHeaders)
    }

    // MARK: - Custom Template Variable Replacement

    /// Replace variables in a custom template string with actual event data.
    ///
    /// Supported variables:
    /// - `{name}`           — folder name
    /// - `{path}`           — full folder path
    /// - `{created_at}`     — folder creation date (ISO 8601)
    /// - `{modified_at}`    — folder modification date (ISO 8601)
    /// - `{total_size}`     — human-readable total size (e.g. "12.3 GB")
    /// - `{total_size_bytes}` — total size in raw bytes
    /// - `{file_count}`     — total number of files
    /// - `{video_count}`    — number of video files
    /// - `{video_size}`     — human-readable video size
    /// - `{levels}`         — multi-line text block of level details
    /// - `{levels_json}`    — JSON array of level objects
    func applyCustomTemplate(_ template: String, event: BackupEvent) -> String {
        var result = template

        let replacements: [String: String] = [
            "{name}":            event.folderName,
            "{path}":            event.folderPath,
            "{created_at}":      DateUtils.iso8601String(from: event.createdAt),
            "{modified_at}":     DateUtils.iso8601String(from: event.modifiedAt),
            "{total_size}":      ByteFormatter.string(fromByteCount: Int64(event.totalSizeBytes)),
            "{total_size_bytes}": "\(event.totalSizeBytes)",
            "{file_count}":      "\(event.fileCount)",
            "{video_count}":     "\(event.videoCount)",
            "{video_size}":      ByteFormatter.string(fromByteCount: Int64(event.videoSizeBytes)),
            "{levels}":          TemplateHelpers.formatLevelsText(event.levels),
            "{levels_json}":     formatLevelsJSON(event.levels),
        ]

        for (key, value) in replacements {
            result = result.replacingOccurrences(of: key, with: value)
        }

        return result
    }

    // MARK: - Private

    private var defaultHeaders: [String: String] {
        ["Content-Type": "application/json; charset=utf-8"]
    }

    /// Format levels as a JSON array string.
    private func formatLevelsJSON(_ levels: [LevelInfo]) -> String {
        guard !levels.isEmpty else { return "[]" }
        if let data = try? StorageUtils.encoder.encode(levels),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    /// Build a generic JSON payload for the .custom platform when no template is given.
    private func buildGenericPayload(event: BackupEvent) -> Data {
        let payload: [String: Any] = [
            "event": "backup_complete",
            "folder_name": event.folderName,
            "folder_path": event.folderPath,
            "created_at": DateUtils.iso8601String(from: event.createdAt),
            "modified_at": DateUtils.iso8601String(from: event.modifiedAt),
            "total_size_bytes": event.totalSizeBytes,
            "total_size": ByteFormatter.string(fromByteCount: Int64(event.totalSizeBytes)),
            "file_count": event.fileCount,
            "video_count": event.videoCount,
            "video_size_bytes": event.videoSizeBytes,
            "video_size": ByteFormatter.string(fromByteCount: Int64(event.videoSizeBytes)),
            "levels": event.levels.map { [
                "relative_path": $0.relativePath,
                "size_bytes": $0.sizeBytes,
                "size": ByteFormatter.string(fromByteCount: Int64($0.sizeBytes))
            ] as [String: Any] }
        ]
        return TemplateHelpers.serialize(payload)
    }
}

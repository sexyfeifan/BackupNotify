import Foundation

/// Renders a `BackupEvent` into platform-specific JSON payloads
/// and applies custom template variable substitution.
struct TemplateEngine {

    /// Render a BackupEvent into the appropriate format for the given platform.
    /// Returns the request body, extra headers, and a placeholder URL
    /// (the caller overrides the URL with the webhook's configured URL).
    func render(
        event: BackupEvent,
        platform: WebhookPlatform,
        customTemplate: String?
    ) -> (body: Data, headers: [String: String], url: String) {
        // If a custom template is provided and the platform is .custom, use it directly.
        if platform == .custom, let custom = customTemplate, !custom.isEmpty {
            let rendered = applyCustomTemplate(custom, event: event)
            let body = rendered.data(using: .utf8) ?? Data()
            return (body: body, headers: ["Content-Type": "application/json; charset=utf-8"], url: "")
        }

        let body: Data
        let headers: [String: String]
        let url: String

        switch platform {
        case .feishu:
            body = FeishuTemplate.render(event: event)
            headers = ["Content-Type": "application/json; charset=utf-8"]
            url = ""  // caller uses webhook config URL

        case .dingtalk:
            body = DingTalkTemplate.render(event: event)
            headers = ["Content-Type": "application/json; charset=utf-8"]
            url = ""

        case .wecom:
            body = WeComTemplate.render(event: event)
            headers = ["Content-Type": "application/json; charset=utf-8"]
            url = ""

        case .slack:
            body = SlackTemplate.render(event: event)
            headers = ["Content-Type": "application/json; charset=utf-8"]
            url = ""

        case .discord:
            body = DiscordTemplate.render(event: event)
            headers = ["Content-Type": "application/json; charset=utf-8"]
            url = ""

        case .custom:
            // custom platform without a template — fall back to a simple JSON payload
            body = buildGenericPayload(event: event)
            headers = ["Content-Type": "application/json; charset=utf-8"]
            url = ""
        }

        return (body: body, headers: headers, url: url)
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
            "{levels}":          formatLevelsText(event.levels),
            "{levels_json}":     formatLevelsJSON(event.levels),
        ]

        for (key, value) in replacements {
            result = result.replacingOccurrences(of: key, with: value)
        }

        return result
    }

    // MARK: - Helpers

    /// Format levels as a human-readable multi-line text block.
    private func formatLevelsText(_ levels: [LevelInfo]) -> String {
        guard !levels.isEmpty else { return "(no sub-directories)" }
        return levels.map { level in
            "  • \(level.relativePath) — \(ByteFormatter.string(fromByteCount: Int64(level.sizeBytes)))"
        }.joined(separator: "\n")
    }

    /// Format levels as a JSON array string.
    private func formatLevelsJSON(_ levels: [LevelInfo]) -> String {
        guard !levels.isEmpty else { return "[]" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(levels),
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
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
    }
}

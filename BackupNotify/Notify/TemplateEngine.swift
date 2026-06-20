import Foundation

// MARK: - NotificationTemplate Protocol

protocol NotificationTemplate {
    static func render(event: BackupEvent) -> Data
}

// MARK: - TemplateHelpers

enum TemplateHelpers {

    static func serialize(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: StorageUtils.jsonOptions)) ?? Data()
    }

    static func formatLevelsText(_ levels: [LevelInfo], bullet: String = "•") -> String {
        guard !levels.isEmpty else { return "" }
        return levels.map { level in
            "\(bullet) \(level.relativePath) — \(ByteFormatter.string(fromByteCount: level.sizeBytes))"
        }.joined(separator: "\n")
    }
}

// MARK: - RenderedPayload

struct RenderedPayload {
    let body: Data
    let headers: [String: String]
}

// MARK: - TemplateEngine

struct TemplateEngine {

    private static let registry: [WebhookPlatform: NotificationTemplate.Type] = [
        .feishu:   FeishuTemplate.self,
        .dingtalk: DingTalkTemplate.self,
        .wecom:    WeComTemplate.self,
        .slack:    SlackTemplate.self,
        .discord:  DiscordTemplate.self,
    ]

    func render(
        event: BackupEvent,
        platform: WebhookPlatform,
        customTemplate: String?
    ) -> RenderedPayload {
        // Custom platform with user template
        if platform == .custom, let custom = customTemplate, !custom.isEmpty {
            let rendered = applyCustomTemplate(custom, event: event)
            let body = rendered.data(using: .utf8) ?? Data()
            return RenderedPayload(body: body, headers: defaultHeaders)
        }

        // Built-in platform templates (use custom template if provided)
        if let custom = customTemplate, !custom.isEmpty {
            let rendered = applyCustomTemplate(custom, event: event)
            let body = rendered.data(using: .utf8) ?? Data()
            return RenderedPayload(body: body, headers: defaultHeaders)
        }

        if let templateType = Self.registry[platform] {
            let body = templateType.render(event: event)
            return RenderedPayload(body: body, headers: defaultHeaders)
        }

        let body = buildGenericPayload(event: event)
        return RenderedPayload(body: body, headers: defaultHeaders)
    }

    // MARK: - Custom Template

    func applyCustomTemplate(_ template: String, event: BackupEvent) -> String {
        var result = template

        let replacements: [String: String] = [
            "{name}":            event.folderName,
            "{path}":            event.folderPath,
            "{monitor_name}":    event.monitorName,
            "{created_at}":      DateUtils.iso8601String(from: event.createdAt),
            "{modified_at}":     DateUtils.iso8601String(from: event.modifiedAt),
            "{notified_at}":     DateUtils.iso8601String(from: event.notifiedAt),
            "{backup_time}":     DateUtils.displayString(from: event.createdAt),
            "{notify_time}":     DateUtils.displayString(from: event.notifiedAt),
            "{total_size}":      ByteFormatter.string(fromByteCount: event.totalSizeBytes),
            "{total_size_bytes}": "\(event.totalSizeBytes)",
            "{file_count}":      "\(event.fileCount)",
            "{video_count}":     "\(event.videoCount)",
            "{video_size}":      ByteFormatter.string(fromByteCount: event.videoSizeBytes),
            "{file_tree}":       ReportBuilder.plainText(from: event).components(separatedBy: "文件树").last.map { "文件树\($0)" } ?? "",
            "{levels}":          TemplateHelpers.formatLevelsText(event.levels),
            "{levels_json}":     formatLevelsJSON(event.levels),
            "{report}":          ReportBuilder.plainText(from: event),
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

    private func formatLevelsJSON(_ levels: [LevelInfo]) -> String {
        guard !levels.isEmpty else { return "[]" }
        if let data = try? StorageUtils.encoder.encode(levels),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return "[]"
    }

    private func buildGenericPayload(event: BackupEvent) -> Data {
        let report = ReportBuilder.build(from: event)

        var payload: [String: Any] = [
            "event": "backup_report",
            "folder_name": event.folderName,
            "folder_path": event.folderPath,
            "monitor_name": event.monitorName,
            "backup_time": DateUtils.iso8601String(from: event.createdAt),
            "notify_time": DateUtils.iso8601String(from: event.notifiedAt),
            "total_size_bytes": event.totalSizeBytes,
            "total_size": ByteFormatter.string(fromByteCount: event.totalSizeBytes),
            "file_count": event.fileCount,
            "video_count": event.videoCount,
            "video_size_bytes": event.videoSizeBytes,
            "video_size": ByteFormatter.string(fromByteCount: event.videoSizeBytes),
            "levels": event.levels.map { [
                "relative_path": $0.relativePath,
                "size_bytes": $0.sizeBytes,
                "file_count": $0.fileCount,
                "size": ByteFormatter.string(fromByteCount: $0.sizeBytes)
            ] as [String: Any] },
        ]

        // Add sections as structured data
        var sections: [[String: String]] = []
        for section in report.sections {
            sections.append(["label": section.label, "value": section.value])
        }
        payload["sections"] = sections
        payload["file_tree"] = report.fileTree

        return TemplateHelpers.serialize(payload)
    }
}

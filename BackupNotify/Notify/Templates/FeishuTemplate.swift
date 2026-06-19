import Foundation

/// Renders a BackupEvent as a Feishu interactive message card.
///
/// Feishu webhook format:
/// {
///   "msg_type": "interactive",
///   "card": {
///     "header": { "title": {...}, "template": "..." },
///     "elements": [...]
///   }
/// }
struct FeishuTemplate {

    /// Render the event as a Feishu interactive card message.
    static func render(event: BackupEvent) -> Data {
        // Header
        let header: [String: Any] = [
            "title": [
                "tag": "plain_text",
                "content": "📹 新备份通知 — \(event.folderName)"
            ] as [String: Any],
            "template": "green"
        ]

        // Field rows as Feishu div elements
        var elements: [[String: Any]] = []

        // Summary fields in a two-column layout
        elements.append(makeFieldDiv(label: "📂 文件夹", value: event.folderName))
        elements.append(makeFieldDiv(label: "📁 路径", value: event.folderPath))
        elements.append(makeFieldDiv(label: "🕐 创建时间", value: DateUtils.displayString(from: event.createdAt)))
        elements.append(makeFieldDiv(label: "🕐 修改时间", value: DateUtils.displayString(from: event.modifiedAt)))

        // Divider
        elements.append(["tag": "hr"])

        // Stats row
        elements.append(makeFieldDiv(
            label: "📊 总大小",
            value: ByteFormatter.string(fromByteCount: Int64(event.totalSizeBytes))
        ))
        elements.append(makeFieldDiv(label: "📄 文件数", value: "\(event.fileCount)"))
        elements.append(makeFieldDiv(label: "🎬 视频数", value: "\(event.videoCount)"))
        elements.append(makeFieldDiv(
            label: "🎬 视频大小",
            value: ByteFormatter.string(fromByteCount: Int64(event.videoSizeBytes))
        ))

        // Level details
        if !event.levels.isEmpty {
            elements.append(["tag": "hr"])
            let levelsText = event.levels.map { level in
                "• \(level.relativePath) — \(ByteFormatter.string(fromByteCount: Int64(level.sizeBytes)))"
            }.joined(separator: "\n")

            elements.append([
                "tag": "div",
                "text": [
                    "tag": "lark_md",
                    "content": "**📂 子目录详情：**\n\(levelsText)"
                ] as [String: Any]
            ] as [String: Any])
        }

        // Note
        elements.append(["tag": "hr"])
        elements.append([
            "tag": "note",
            "elements": [
                [
                    "tag": "plain_text",
                    "content": "BackupNotify • \(DateUtils.displayString(from: event.notifiedAt))"
                ] as [String: Any]
            ]
        ] as [String: Any])

        // Assemble card
        let card: [String: Any] = [
            "header": header,
            "elements": elements
        ]

        let payload: [String: Any] = [
            "msg_type": "interactive",
            "card": card
        ]

        return serialize(payload)
    }

    // MARK: - Helpers

    /// Create a div element with a label-value pair using Feishu lark_md.
    private static func makeFieldDiv(label: String, value: String) -> [String: Any] {
        return [
            "tag": "div",
            "text": [
                "tag": "lark_md",
                "content": "\(label)：**\(value)**"
            ] as [String: Any]
        ] as [String: Any]
    }

    private static func serialize(_ object: [String: Any]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]) else {
            return Data()
        }
        return data
    }
}

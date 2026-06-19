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
struct FeishuTemplate: NotificationTemplate {

    static func render(event: BackupEvent) -> Data {
        let header: [String: Any] = [
            "title": [
                "tag": "plain_text",
                "content": "📹 新备份通知 — \(event.folderName)"
            ] as [String: Any],
            "template": "green"
        ]

        var elements: [[String: Any]] = []

        elements.append(makeFieldDiv(label: "📂 文件夹", value: event.folderName))
        elements.append(makeFieldDiv(label: "📁 路径", value: event.folderPath))
        elements.append(makeFieldDiv(label: "🕐 创建时间", value: DateUtils.displayString(from: event.createdAt)))
        elements.append(makeFieldDiv(label: "🕐 修改时间", value: DateUtils.displayString(from: event.modifiedAt)))

        elements.append(["tag": "hr"])

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

        if !event.levels.isEmpty {
            elements.append(["tag": "hr"])
            let levelsText = TemplateHelpers.formatLevelsText(event.levels)
            elements.append([
                "tag": "div",
                "text": [
                    "tag": "lark_md",
                    "content": "**📂 子目录详情：**\n\(levelsText)"
                ] as [String: Any]
            ] as [String: Any])
        }

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

        let card: [String: Any] = [
            "header": header,
            "elements": elements
        ]

        let payload: [String: Any] = [
            "msg_type": "interactive",
            "card": card
        ]

        return TemplateHelpers.serialize(payload)
    }

    // MARK: - Helpers

    private static func makeFieldDiv(label: String, value: String) -> [String: Any] {
        [
            "tag": "div",
            "text": [
                "tag": "lark_md",
                "content": "\(label)：**\(value)**"
            ] as [String: Any]
        ] as [String: Any]
    }
}

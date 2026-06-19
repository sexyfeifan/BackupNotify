import Foundation

/// Renders a BackupEvent as a DingTalk markdown message.
///
/// DingTalk webhook format:
/// {
///   "msgtype": "markdown",
///   "markdown": {
///     "title": "...",
///     "text": "..."
///   }
/// }
struct DingTalkTemplate: NotificationTemplate {

    static func render(event: BackupEvent) -> Data {
        let title = "📹 新备份通知 — \(event.folderName)"

        var md = ""
        md += "## 📹 新备份通知\n\n"
        md += "---\n\n"
        md += "**📂 文件夹：** \(event.folderName)\n\n"
        md += "**📁 路径：** \(event.folderPath)\n\n"
        md += "**🕐 创建时间：** \(DateUtils.displayString(from: event.createdAt))\n\n"
        md += "**🕐 修改时间：** \(DateUtils.displayString(from: event.modifiedAt))\n\n"
        md += "---\n\n"
        md += "**📊 总大小：** \(ByteFormatter.string(fromByteCount: event.totalSizeBytes))\n\n"
        md += "**📄 文件数：** \(event.fileCount)\n\n"
        md += "**🎬 视频数：** \(event.videoCount)\n\n"
        md += "**🎬 视频大小：** \(ByteFormatter.string(fromByteCount: event.videoSizeBytes))\n\n"

        if !event.levels.isEmpty {
            md += "---\n\n"
            md += "**📂 子目录详情：**\n\n"
            for level in event.levels {
                md += "- \(level.relativePath) — \(ByteFormatter.string(fromByteCount: Int64(level.sizeBytes)))\n"
            }
            md += "\n"
        }

        let payload: [String: Any] = [
            "msgtype": "markdown",
            "markdown": [
                "title": title,
                "text": md
            ] as [String: Any]
        ]

        return TemplateHelpers.serialize(payload)
    }
}

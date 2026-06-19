import Foundation

/// Renders a BackupEvent as a WeCom (企业微信) markdown message.
///
/// WeCom webhook format:
/// {
///   "msgtype": "markdown",
///   "markdown": {
///     "content": "..."
///   }
/// }
///
/// Note: WeCom markdown uses a subset of Markdown.
/// Supported: headers (# ##), bold (**), links, quotes (>), color text (<font>).
struct WeComTemplate {

    /// Render the event as a WeCom markdown payload.
    static func render(event: BackupEvent) -> Data {
        var md = ""
        md += "# 📹 新备份通知\n"
        md += "> **\(event.folderName)**\n\n"
        md += "**📂 文件夹：**<font color=\"info\">\(event.folderName)</font>\n"
        md += "**📁 路径：**\(event.folderPath)\n"
        md += "**🕐 创建时间：**\(DateUtils.displayString(from: event.createdAt))\n"
        md += "**🕐 修改时间：**\(DateUtils.displayString(from: event.modifiedAt))\n\n"
        md += "**📊 总大小：**<font color=\"warning\">\(ByteFormatter.string(fromByteCount: Int64(event.totalSizeBytes)))</font>\n"
        md += "**📄 文件数：**\(event.fileCount)\n"
        md += "**🎬 视频数：**\(event.videoCount)\n"
        md += "**🎬 视频大小：**\(ByteFormatter.string(fromByteCount: Int64(event.videoSizeBytes)))\n"

        if !event.levels.isEmpty {
            md += "\n**📂 子目录详情：**\n"
            for level in event.levels {
                md += "> \(level.relativePath) — \(ByteFormatter.string(fromByteCount: Int64(level.sizeBytes)))\n"
            }
        }

        let payload: [String: Any] = [
            "msgtype": "markdown",
            "markdown": [
                "content": md
            ] as [String: Any]
        ]

        return serialize(payload)
    }

    private static func serialize(_ object: [String: Any]) -> Data {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return Data()
        }
        return data
    }
}

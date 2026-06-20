import Foundation

/// Professional report builder — single source of truth for all notification content.
enum ReportBuilder {

    // MARK: - Structured Data

    struct ReportSection {
        let label: String
        let value: String
    }

    struct ReportData {
        let title: String
        let subtitle: String
        let sections: [ReportSection]
        let fileTree: String
        let footer: String
    }

    // MARK: - Build

    static func build(from event: BackupEvent) -> ReportData {
        var sections: [ReportSection] = []

        sections.append(ReportSection(label: "备份文件夹", value: event.folderName))
        sections.append(ReportSection(label: "监控源", value: event.monitorName))
        sections.append(ReportSection(label: "目标路径", value: event.folderPath))
        sections.append(ReportSection(label: "备份时间", value: DateUtils.displayString(from: event.createdAt)))
        sections.append(ReportSection(label: "通知时间", value: DateUtils.displayString(from: event.notifiedAt)))

        // Duration
        let duration = event.notifiedAt.timeIntervalSince(event.createdAt)
        if duration > 0 {
            sections.append(ReportSection(label: "检测耗时", value: formatDuration(duration)))
        }

        sections.append(ReportSection(label: "总大小", value: ByteFormatter.string(fromByteCount: event.totalSizeBytes)))
        sections.append(ReportSection(label: "文件总数", value: "\(event.fileCount) 个"))

        if event.videoCount > 0 {
            sections.append(ReportSection(
                label: "视频文件",
                value: "\(event.videoCount) 个（\(ByteFormatter.string(fromByteCount: event.videoSizeBytes))）"
            ))
        }

        let fileTree = buildCompleteTree(event)
        let footer = "BackupNotify · \(DateUtils.displayString(from: event.notifiedAt))"

        return ReportData(
            title: "备份报告",
            subtitle: event.folderName,
            sections: sections,
            fileTree: fileTree,
            footer: footer
        )
    }

    // MARK: - Formatted Outputs

    /// Plain text report (for custom templates / generic platforms).
    static func plainText(from event: BackupEvent) -> String {
        let data = build(from: event)
        var lines: [String] = []

        let width = 50
        lines.append(String(repeating: "═", count: width))
        lines.append(centerAlign("📋 \(data.title)", width: width))
        lines.append(centerAlign(data.subtitle, width: width))
        lines.append(String(repeating: "═", count: width))
        lines.append("")

        // Key-value sections with aligned columns
        let maxLabel = data.sections.map { $0.label.count }.max() ?? 0
        for section in data.sections {
            let paddedLabel = section.label.padding(toLength: maxLabel, withPad: " ", startingAt: 0)
            lines.append("  \(paddedLabel)  \(section.value)")
        }

        if !data.fileTree.isEmpty {
            lines.append("")
            lines.append(String(repeating: "─", count: width))
            lines.append("  📁 文件结构")
            lines.append(String(repeating: "─", count: width))
            lines.append("")
            lines.append(data.fileTree)
        }

        lines.append("")
        lines.append(String(repeating: "─", count: width))
        lines.append("  \(data.footer)")
        lines.append(String(repeating: "═", count: width))

        return lines.joined(separator: "\n")
    }

    /// Markdown report (for DingTalk / WeCom).
    static func markdown(from event: BackupEvent) -> String {
        let data = build(from: event)
        var md = ""

        md += "## 📋 \(data.title)\n\n"
        md += "> **\(data.subtitle)**\n\n"

        for section in data.sections {
            md += "**\(section.label)：** \(section.value)\n\n"
        }

        if !data.fileTree.isEmpty {
            md += "---\n\n"
            md += "**📁 文件结构：**\n\n"
            md += "```\n\(data.fileTree)\n```\n\n"
        }

        md += "---\n\n"
        md += "*\(data.footer)*\n"

        return md
    }

    /// Lark markdown (for Feishu cards).
    static func larkMarkdown(from event: BackupEvent) -> String {
        let data = build(from: event)
        var md = ""

        for section in data.sections {
            md += "**\(section.label)：**\(section.value)\n"
        }

        if !data.fileTree.isEmpty {
            md += "\n**📁 文件结构：**\n```\n\(data.fileTree)\n```"
        }

        return md
    }

    // MARK: - Complete File Tree Builder

    private static func buildCompleteTree(_ event: BackupEvent) -> String {
        if !event.fileEntries.isEmpty {
            return renderFileEntries(event.fileEntries)
        }
        if !event.levels.isEmpty {
            return renderLevels(event.levels)
        }
        return ""
    }

    private static func renderFileEntries(_ entries: [FileEntry]) -> String {
        guard !entries.isEmpty else { return "" }

        var lines: [String] = []

        for (index, entry) in entries.enumerated() {
            let indent = entry.depth > 0
                ? String(repeating: "│   ", count: entry.depth - 1)
                : ""

            let connector: String
            if entry.depth == 0 {
                connector = ""
            } else {
                let isLast = isLastAtDepth(entries: entries, index: index)
                connector = isLast ? "└── " : "├── "
            }

            let sizeStr = ByteFormatter.string(fromByteCount: Int64(entry.sizeBytes))

            if entry.isDirectory {
                let countStr = entry.childCount > 0 ? " (\(entry.childCount) 个文件)" : ""
                lines.append("\(indent)\(connector)📁 \(entry.name)/\(countStr)  \(sizeStr)")
            } else {
                let ext = (entry.name as NSString).pathExtension.lowercased()
                let icon = fileIcon(ext)
                lines.append("\(indent)\(connector)\(icon) \(entry.name)  \(sizeStr)")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Render legacy levels as fallback.
    private static func renderLevels(_ levels: [LevelInfo]) -> String {
        let sorted = levels.sorted { $0.relativePath < $1.relativePath }
        var lines: [String] = []

        for (i, level) in sorted.enumerated() {
            let isLast = i == sorted.count - 1
            let prefix = isLast ? "└── " : "├── "
            let sizeStr = ByteFormatter.string(fromByteCount: Int64(level.sizeBytes))
            let fileStr = level.fileCount > 0 ? " (\(level.fileCount) 个文件)" : ""
            lines.append("\(prefix)📁 \(level.relativePath)/\(fileStr)  \(sizeStr)")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func isLastAtDepth(entries: [FileEntry], index: Int) -> Bool {
        let currentDepth = entries[index].depth
        // Look ahead for any entry at the same depth (same parent)
        for i in (index + 1)..<entries.count {
            if entries[i].depth < currentDepth { return true }  // went up, so previous was last
            if entries[i].depth == currentDepth { return false } // found sibling
        }
        return true
    }

    private static func fileIcon(_ ext: String) -> String {
        switch ext {
        case "mov", "mp4", "mxf", "avi", "mkv", "r3d", "braw", "ari", "crm", "mts", "m2ts":
            return "🎬"
        case "jpg", "jpeg", "png", "tiff", "tif", "bmp", "gif", "heic", "heif", "raw", "cr2", "cr3", "nef", "arw", "dng":
            return "🖼 "
        case "wav", "mp3", "aac", "flac", "aiff", "m4a":
            return "🎵"
        case "pdf":
            return "📄"
        case "xml", "json", "txt", "csv", "log":
            return "📝"
        default:
            return "  "
        }
    }

    private static func centerAlign(_ text: String, width: Int) -> String {
        let padding = max(0, width - text.count) / 2
        return String(repeating: " ", count: padding) + text
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 1 {
            return String(format: "%.0fms", seconds * 1000)
        } else if seconds < 60 {
            return String(format: "%.1fs", seconds)
        } else {
            let min = Int(seconds) / 60
            let sec = Int(seconds) % 60
            return "\(min)m \(sec)s"
        }
    }
}
